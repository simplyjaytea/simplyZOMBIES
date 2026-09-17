#!/usr/bin/env python3
"""Read-only audit of native asset references; reports are written under docs.

Usage: python audit_pack.py pack/manifest.json --out docs
Requires Pillow. Does not change the pack, sprites, or source manifests.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import math
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from PIL import Image


def png_references(value):
    if isinstance(value, str) and value.lower().endswith('.png'):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from png_references(child)
    elif isinstance(value, list):
        for child in value:
            yield from png_references(child)


def frame_path(frame, asset):
    if isinstance(frame, str):
        return frame
    if isinstance(frame, dict) and isinstance(frame.get('path'), str):
        return frame['path']
    if isinstance(frame, int):
        return asset.get('path')
    return None


def animations(asset):
    frames = asset.get('frames', {})
    return frames if isinstance(frames, dict) else {'play': frames} if isinstance(frames, list) else {}


def size_for(asset):
    return asset.get('frameSize') or asset.get('size')


def points(value, prefix=''):
    if isinstance(value, dict):
        for key, child in value.items():
            path = f'{prefix}.{key}' if prefix else key
            if key in ('anchor', 'grip', 'muzzle', 'tip'):
                yield path, child
            elif key not in ('atlas', 'frames'):
                yield from points(child, path)


def visible_fingerprint(im):
    # Ignore hidden RGB under zero alpha; this is analysis only, no image is saved.
    rgba = im.convert('RGBA')
    raw = bytearray(rgba.tobytes())
    for offset in range(0, len(raw), 4):
        if raw[offset + 3] == 0:
            raw[offset:offset + 3] = b'\0\0\0'
    return hashlib.sha256(str(rgba.size).encode() + raw).hexdigest()


def silhouette_fingerprint(im):
    alpha = im.convert('RGBA').getchannel('A').point(lambda p: 255 if p >= 128 else 0)
    bounds = alpha.getbbox()
    if not bounds:
        return 'empty'
    crop = alpha.crop(bounds)
    return hashlib.sha256(str(crop.size).encode() + crop.tobytes()).hexdigest()


def run(manifest_path: Path, out: Path):
    data_bytes = manifest_path.read_bytes()
    manifest = json.loads(data_bytes)
    assets = manifest.get('assets', [])
    root = manifest_path.parent.resolve()
    errors, warnings = [], []
    image_cache = {}
    refs = set(png_references(manifest))

    def error(code, asset, detail):
        errors.append({'code': code, 'asset': asset, 'detail': detail})

    def warning(code, asset, detail):
        warnings.append({'code': code, 'asset': asset, 'detail': detail})

    def image(path, asset_id):
        if not isinstance(path, str):
            error('missing-image-path', asset_id, str(path)); return None
        if path in image_cache:
            return image_cache[path]
        rel = PurePosixPath(path)
        if rel.is_absolute() or '..' in rel.parts or '\\' in path:
            error('unsafe-relative-path', asset_id, path); return None
        source = root / path
        if not source.is_file():
            error('missing-image', asset_id, path); return None
        try:
            with Image.open(source) as opened:
                if opened.format != 'PNG':
                    error('not-png', asset_id, path)
                im = opened.convert('RGBA')
                im.load()
            image_cache[path] = im
            return im
        except Exception as exc:
            error('image-decode', asset_id, f'{path}: {exc}'); return None

    for path in sorted(refs):
        image(path, 'manifest')
    counts = Counter(a.get('id') for a in assets)
    for asset_id, count in counts.items():
        if not isinstance(asset_id, str) or not asset_id:
            error('missing-id', str(asset_id), f'{count} asset(s)')
        elif count > 1:
            error('duplicate-id', asset_id, f'{count} definitions')

    records, animation_records = [], []
    for asset in assets:
        asset_id = asset.get('id', '<missing>')
        declared = size_for(asset)
        base = image(asset.get('path'), asset_id)
        if not (isinstance(declared, list) and len(declared) == 2 and all(isinstance(v, (int, float)) and v > 0 for v in declared)):
            error('invalid-native-size', asset_id, str(declared))
            declared = list(base.size) if base else [0, 0]
        if base is not None and not asset.get('frameSize') and list(base.size) != declared:
            error('native-size-mismatch', asset_id, f'declared {declared}, PNG {list(base.size)}')
        for label, point in points(asset):
            valid = isinstance(point, list) and len(point) == 2 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in point)
            if not valid or not (0 <= point[0] <= declared[0] and 0 <= point[1] <= declared[1]):
                error('coordinate-out-of-bounds', asset_id, f'{label}={point}, canvas={declared}; boundary anchors are allowed')

        sprite_paths = {asset['path']} if isinstance(asset.get('path'), str) else set()
        states = animations(asset)
        multi_states = 0
        frame_entries = 0
        for state, sequence in states.items():
            if not isinstance(sequence, list) or not sequence:
                error('empty-animation', asset_id, state); continue
            hashes, shapes, state_paths = [], [], []
            for index, frame in enumerate(sequence):
                path = frame_path(frame, asset)
                if path is None:
                    error('unsupported-frame', asset_id, f'{state}[{index}]={frame}'); continue
                im = image(path, asset_id)
                if im is None:
                    continue
                if isinstance(frame, int):
                    fw, fh = map(int, declared)
                    cols = im.width // fw if fw else 0
                    if not cols or frame < 0:
                        error('bad-atlas-frame', asset_id, f'{state}[{index}]={frame}'); continue
                    x, y = frame % cols * fw, frame // cols * fh
                    if x + fw > im.width or y + fh > im.height:
                        error('atlas-frame-out-of-bounds', asset_id, f'{path}: index {frame}'); continue
                    im = im.crop((x, y, x + fw, y + fh))
                elif list(im.size) != declared:
                    error('frame-size-mismatch', asset_id, f'{state}[{index}] {path}: {list(im.size)} vs {declared}')
                if im.getchannel('A').getbbox() is None:
                    warning('empty-animation-frame', asset_id, f'{state}[{index}] is fully transparent')
                sprite_paths.add(path); state_paths.append(path)
                hashes.append(visible_fingerprint(im)); shapes.append(silhouette_fingerprint(im))
            unique_frames, unique_shapes = len(set(hashes)), len(set(shapes))
            if len(sequence) > 1:
                multi_states += 1
                if unique_frames <= 1:
                    error('duplicate-only-animation', asset_id, f'{state}: {len(sequence)} entries, {unique_frames} visible pixel patterns')
                elif unique_frames < len(sequence):
                    warning('reused-animation-frame', asset_id, f'{state}: {unique_frames}/{len(sequence)} unique visible frames; repeated holds may be intentional')
                if unique_shapes <= 1:
                    warning('unchanged-animation-silhouette', asset_id, f'{state}: no binary silhouette change after trimming; inspect for translations/recolors')
            frame_entries += len(sequence)
            animation_records.append({'asset_id':asset_id,'group':asset.get('group', 'characters' if asset.get('category','').lower()=='characters' else 'ungrouped'),'animation':state,'frame_entries':len(sequence),'unique_visible_frames':unique_frames,'unique_trimmed_silhouettes':unique_shapes,'unique_png_paths':len(set(state_paths))})

        alpha_counts = {'opaque':0,'with_transparency':0,'with_fractional_alpha':0}
        for path in sorted(sprite_paths):
            im = image_cache.get(path)
            if im is None:
                continue
            alpha = im.getchannel('A')
            histogram = alpha.histogram()
            if histogram[0] or any(histogram[1:255]):
                alpha_counts['with_transparency'] += 1
            else:
                alpha_counts['opaque'] += 1
            if any(histogram[1:255]):
                alpha_counts['with_fractional_alpha'] += 1
            if not alpha.getbbox():
                warning('empty-sprite', asset_id, path)
        category = asset.get('category', '')
        terrain = category.lower() == 'terrain'
        if terrain and alpha_counts['with_transparency']:
            error('nonopaque-terrain', asset_id, 'Ground terrain PNG has transparency')
        if not terrain and alpha_counts['opaque']:
            warning('opaque-nonterrain-image', asset_id, f"{alpha_counts['opaque']} native PNG(s) have no transparency; verify that a filled panel/tile is intentional")
        records.append({'id':asset_id,'label':asset.get('label',''),'group':asset.get('group', 'characters' if category.lower()=='characters' else 'ungrouped'),'category':category,'width':declared[0],'height':declared[1],'animation_states':len(states),'multi_frame_states':multi_states,'frame_entries':frame_entries,'native_png_paths':len(sprite_paths),'opaque_pngs':alpha_counts['opaque'],'transparent_pngs':alpha_counts['with_transparency'],'fractional_alpha_pngs':alpha_counts['with_fractional_alpha'],'state':asset.get('state',''),'notes':asset.get('notes','')})

    groups = defaultdict(lambda:{'assets':0,'animated_assets':0,'animation_states':0,'multi_frame_states':0,'frame_entries':0,'native_png_paths':0})
    for record in records:
        group = groups[record['group']]
        group['assets'] += 1
        group['animated_assets'] += bool(record['multi_frame_states'])
        for key in ('animation_states','multi_frame_states','frame_entries','native_png_paths'):
            group[key] += record[key]
    # Each image is counted once globally even if reused by several assets/states.
    native_paths = {a['path'] for a in assets if isinstance(a.get('path'), str)}
    group_native_paths = defaultdict(set)
    for asset in assets:
        group_name=asset.get('group', 'characters' if asset.get('category','').lower()=='characters' else 'ungrouped')
        if isinstance(asset.get('path'),str):
            group_native_paths[group_name].add(asset['path'])
        for seq in animations(asset).values():
            if isinstance(seq,list):
                seq_paths={p for f in seq if (p:=frame_path(f,asset))}
                native_paths.update(seq_paths)
                group_native_paths[group_name].update(seq_paths)
    for group_name, paths in group_native_paths.items():
        groups[group_name]['native_png_paths']=len(paths)
    report={'generated_at_utc':datetime.now(timezone.utc).isoformat(),'manifest_name':manifest_path.name,'manifest_sha256':hashlib.sha256(data_bytes).hexdigest(),'status':'pass' if not errors else 'fail','asset_count':len(assets),'unique_ids':len(counts),'unique_referenced_pngs':len(refs),'unique_native_sprite_pngs':len(native_paths),'animation_state_count':len(animation_records),'multi_frame_state_count':sum(r['multi_frame_states'] for r in records),'animation_frame_entries':sum(r['frame_entries'] for r in records),'groups':dict(sorted(groups.items())),'errors':errors,'warnings':warnings,'assets':records,'animations':animation_records,'scope':'Checks metadata, PNG decoding, native size, alpha presence, coordinates and pixel uniqueness. Does not validate Godot import, collisions, autotile rules, visual style, animation timing quality or anatomy.'}
    out.mkdir(parents=True,exist_ok=True)
    (out/'asset-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    for filename, rows in [('asset-coverage.csv',records),('animation-coverage.csv',animation_records)]:
        with (out/filename).open('w',newline='') as handle:
            if rows:
                writer=csv.DictWriter(handle,fieldnames=list(rows[0]),lineterminator='\n');writer.writeheader();writer.writerows(rows)
    summary = f"# Native asset audit\n\nStatus: **{report['status'].upper()}**. {len(assets)} assets, {len(native_paths)} unique native sprite PNGs, {report['multi_frame_state_count']} multi-frame animation states.\n\n"
    summary += '| Group | Assets | Animated assets | Animation states | Frame entries |\n|---|---:|---:|---:|---:|\n'
    for group, row in report['groups'].items():
        summary += f"| {group} | {row['assets']} | {row['animated_assets']} | {row['animation_states']} | {row['frame_entries']} |\n"
    summary += f"\nErrors: {len(errors)}. Review notes: {len(warnings)}. The JSON report contains exact IDs and details. Reused frames are flagged for review rather than silently counted as distinct drawings. Single-frame facing states are not counted as animated assets.\n\n{report['scope']}\n"
    (out/'audit-summary.md').write_text(summary)
    print(json.dumps({k:report[k] for k in ('status','asset_count','unique_native_sprite_pngs','multi_frame_state_count','groups','errors','warnings')},indent=2))
    return 0 if not errors else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest',type=Path)
    parser.add_argument('--out',type=Path,default=Path(__file__).resolve().parent/'docs')
    args=parser.parse_args()
    raise SystemExit(run(args.manifest.resolve(),args.out.resolve()))
