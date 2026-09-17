#!/usr/bin/env python3
"""Export Godot 4 SpriteFrames resources from explicit PNG frame arrays.

python docs/export_spriteframes.py pack/manifest.json --out docs/godot
PNG references point into res://art/simplyzombies/ by default. No pack files change.
This writes text resources but does not invoke Godot or claim engine validation.
"""
import argparse
import json
import re
from pathlib import Path, PurePosixPath


def quoted(value):
    return json.dumps(str(value), ensure_ascii=False)


def setting(asset, key, state, default):
    value=asset.get(key, default)
    if isinstance(value, dict):
        return value.get(state,value.get(state.split('_')[0],default))
    return value


def export(manifest_path, out, prefix):
    manifest=json.loads(manifest_path.read_text())
    root=manifest_path.parent
    out.mkdir(parents=True,exist_ok=True)
    resources=[]
    for asset in manifest.get('assets',[]):
        animations=asset.get('frames')
        if not isinstance(animations,dict) or not animations:
            continue
        asset_id=asset['id']
        if not re.fullmatch(r'[A-Za-z0-9_-]+',asset_id):
            raise ValueError(f'Unsafe asset resource filename: {asset_id}')
        sequences={}
        for state,frames in animations.items():
            if not isinstance(frames,list) or not frames:
                raise ValueError(f'{asset_id}/{state}: empty sequence')
            sequence=[]
            for frame in frames:
                path=frame if isinstance(frame,str) else frame.get('path') if isinstance(frame,dict) else None
                if not isinstance(path,str):
                    raise ValueError(f'{asset_id}/{state}: exporter requires explicit per-frame PNG paths')
                rel=PurePosixPath(path)
                if rel.is_absolute() or '..' in rel.parts or '\\' in path or not (root/path).is_file():
                    raise ValueError(f'{asset_id}/{state}: invalid or missing PNG {path}')
                duration=float(frame.get('duration',1.0)) if isinstance(frame,dict) else 1.0
                if duration<=0:
                    raise ValueError(f'{asset_id}/{state}: nonpositive relative duration')
                sequence.append((path,duration))
            sequences[state]=sequence
        unique=list(dict.fromkeys(path for seq in sequences.values() for path,duration in seq))
        ext_ids={path:str(i+1) for i,path in enumerate(unique)}
        lines=[f'[gd_resource type="SpriteFrames" load_steps={len(unique)+1} format=3]','']
        for path in unique:
            lines.append(f'[ext_resource type="Texture2D" path={quoted(prefix.rstrip("/")+"/"+path)} id={quoted(ext_ids[path])}]')
        lines.extend(['','[resource]','animations = ['])
        animation_meta=[]
        for state_i,(state,sequence) in enumerate(sequences.items()):
            # A static one-frame state uses a benign positive speed in SpriteFrames.
            declared_fps=setting(asset,'fps',state,1.0)
            fps=max(float(declared_fps),1.0) if len(sequence)==1 else float(declared_fps)
            if fps<=0:
                raise ValueError(f'{asset_id}/{state}: invalid fps {fps}')
            loop=bool(setting(asset,'loop',state,state.startswith(('idle_','walk_'))))
            lines.extend(['{','"frames": ['])
            for index,(path,duration) in enumerate(sequence):
                comma=',' if index+1<len(sequence) else ''
                lines.append('{"duration": '+str(float(duration))+', "texture": ExtResource('+quoted(ext_ids[path])+')}'+comma)
            lines.extend(['],','"loop": '+str(loop).lower()+',','"name": &'+quoted(state)+',','"speed": '+str(float(fps)),'}'+(',' if state_i+1<len(sequences) else '')])
            animation_meta.append({'name':state,'frames':len(sequence),'fps':fps,'loop':loop})
        lines.append(']')
        resource_path=out/(asset_id+'.tres')
        resource_path.write_text('\n'.join(lines)+'\n')
        anchor=asset.get('anchor',[0,0])
        resources.append({'id':asset_id,'resource':resource_path.name,'anchor':anchor,'nodeCentered':False,'nodeOffset':[-float(anchor[0]),-float(anchor[1])],'animations':animation_meta})
    index={'engine':'Godot 4 text resources','engineTested':False,'pngResourcePrefix':prefix.rstrip('/')+'/','resources':resources,'notes':['Resources contain SpriteFrames playback data only. Position, ground anchors, layer order, attachment and game state are set on scene nodes.','Static one-frame states with manifest fps=0 export with speed=1; this does not create animation.','Imports must be checked in the target Godot project. No engine binary was used during export.']}
    (out/'resources.json').write_text(json.dumps(index,indent=2)+'\n')
    print(json.dumps({'resourceCount':len(resources),'animationStates':sum(len(r['animations']) for r in resources),'output':str(out),'engineTested':False},indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest',type=Path)
    parser.add_argument('--out',type=Path,default=Path(__file__).resolve().parent/'godot')
    parser.add_argument('--prefix',default='res://art/simplyzombies/')
    args=parser.parse_args()
    export(args.manifest.resolve(),args.out.resolve(),args.prefix)
