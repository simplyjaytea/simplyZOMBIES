"""Mechanical, uniform nearest-neighbor registration of the generated walk sheet."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageChops
from statistics import median
from collections import Counter
import json, shutil, hashlib

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent.parent/'generated_images/exec-b8fb752b-664b-4f15-ab10-1dffe1a5a420.png'
IDLES = ROOT.parent.parent/'character-revision/pack/native'
im = Image.open(SOURCE).convert('RGBA')
assert im.size == (1254,1254)
alpha = Counter(im.getchannel('A').get_flattened_data())
assert alpha.get(0,0)>im.width*im.height*.4
directions = ['s','e','n','w']
# Side-row baselines sit three source pixels (0.34 native px) above the longest
# foot extent, placing the shared sampling grid where the source bob survives.
rows = [(0,323,304,58), (323,619,595,342), (619,900,884,639), (900,1254,1171,917)]
head_target_x = [16,17,16.5,16]
records = []
for r,d in enumerate(directions):
    y0,y1,baseline,head_top = rows[r]
    for c in range(4):
        x0,x1=c*im.width//4,(c+1)*im.width//4
        cell=im.crop((x0,y0,x1,y1))
        bounds=cell.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        head=im.crop((x0,head_top,x1,head_top+100))
        hb=head.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        head_axis=(hb[0]+hb[2])/2
        records.append({'id':f'survivor_walk_{d}_{c:02d}','direction':d,'row':r,'frame':c,
          'source_cell':[x0,y0,x1-x0,y1-y0], 'source_occupied_bbox':list(bounds),
          'source_head_detection_rect':[x0,head_top,x1-x0,100],
          'source_registration':[head_axis,baseline-y0], 'target_head_axis_x':head_target_x[r]})
source_height=median(r['source_occupied_bbox'][3]-r['source_occupied_bbox'][1] for r in records)
scale=28/source_height
atlas=Image.new('RGBA',(128,192))
for r in records:
    x,y,w,h=r['source_cell'];cell=im.crop((x,y,x+w,y+h))
    cell.save(ROOT/'source-crops'/f"{r['id']}.png")
    axis,baseline=r['source_registration']
    native=cell.transform((32,48),Image.Transform.AFFINE,
        (1/scale,0,axis-r['target_head_axis_x']/scale,0,1/scale,baseline-40/scale),
        resample=Image.Resampling.NEAREST)
    native.save(ROOT/'native'/f"{r['id']}.png")
    atlas.alpha_composite(native,(r['frame']*32,r['row']*48))
    strong=native.getchannel('A').point(lambda a:255 if a>=128 else 0)
    r.update(texture=f"native/{r['id']}.png",atlas_rect=[r['frame']*32,r['row']*48,32,48],
       pivot=[16,40],occupied_bbox=list(strong.getbbox()),sha256=hashlib.sha256(native.tobytes()).hexdigest(),
       silhouette_sha256=hashlib.sha256(strong.tobytes()).hexdigest(),
       legs_silhouette_sha256=hashlib.sha256(strong.crop((0,30,32,42)).tobytes()).hexdigest())
atlas.save(ROOT/'native/survivor-walk-atlas.png')
contact=Image.new('RGBA',(128*8,192*8),'#303840')
contact.alpha_composite(atlas.resize(contact.size,Image.Resampling.NEAREST))
contact.convert('RGB').save(ROOT/'survivor-walk-contact.png')
loop=[]
for c in range(4):
    out=Image.new('RGBA',(128,48),'#303840')
    for r in range(4):out.alpha_composite(atlas.crop((c*32,r*48,c*32+32,r*48+48)),(r*32,0))
    loop.append(out.convert('RGB').resize((1024,384),Image.Resampling.NEAREST))
loop[0].save(ROOT/'survivor-walk-loop.gif',save_all=True,append_images=loop[1:],duration=125,loop=0,disposal=2)
# Compare approved idle against the four registered walk poses without changing it.
compare=Image.new('RGBA',(160*8,192*8),'#303840')
for r,d in enumerate(directions):
    idle=Image.open(IDLES/f'survivor_{d}.png').convert('RGBA')
    compare.alpha_composite(idle.resize((256,384),Image.Resampling.NEAREST),(0,r*384))
    strip=atlas.crop((0,r*48,128,r*48+48)).resize((1024,384),Image.Resampling.NEAREST)
    compare.alpha_composite(strip,(256,r*384))
compare.convert('RGB').save(ROOT/'survivor-idle-walk-comparison.png')
stats=[]
for d in directions:
    frames=[r for r in records if r['direction']==d]
    stats.append({'direction':d,'unique_rgba_frames':len({r['sha256'] for r in frames}),
      'unique_silhouettes':len({r['silhouette_sha256'] for r in frames}),
      'unique_leg_silhouettes':len({r['legs_silhouette_sha256'] for r in frames}),
      'occupied_heights':[r['occupied_bbox'][3]-r['occupied_bbox'][1] for r in frames]})
shutil.copy2(SOURCE,ROOT/'source/survivor-walk-rgba.png')
manifest={'title':'simplyZOMBIES survivor directional walk','character':'survivor','state':'walk',
 'directions':directions,'frames_per_direction':4,'fps':8,'loop':True,'cell_size':[32,48],'pivot':[16,40],
 'atlas':'native/survivor-walk-atlas.png','source':'source/survivor-walk-rgba.png','source_size':list(im.size),
 'uniform_scale':scale,'source_median_occupied_height':source_height,'target_median_occupied_height':28,
 'source_alpha':{'zero':alpha.get(0,0),'nonzero':sum(v for k,v in alpha.items() if k),'unique_values':len(alpha)},
 'processing':'Original RGBA preserved. Full source cells sampled with one uniform nearest-neighbor scale; a shared ground baseline per direction preserves vertical motion. X registration uses the upper 100-pixel head silhouette axis, not arm/leg bounds, to retain relative limb motion while correcting uneven source columns. Target head x matches approved idle. No repainting, recoloring, alpha thresholding, or silhouette edits. Alpha >=128 is used only for measurements.',
 'gait_review':{'observed':'All four directions have four distinct leg silhouettes. Side views alternate a wide contact pose and a narrow passing pose; front/back views alternate the leading leg. Shared registration preserves a one-pixel crown-height change; west has a less regular crown cadence than east. Feet stay at y=40 except west passing pose 1 ending at y=39.',
 'idle_comparison':'Approved idles remain untouched. Walk silhouettes are 27–29 px tall around the approved 28 px median, registered to the same ground pivot and directional head axis. Generated walk artwork has brighter skin and slightly narrower front/back shoulders, so a small visual transition remains.',
 'limitations':'Four-frame prototype locomotion loops. Some side-view opposite-leg contact poses are close in outline; changed leg shading and distinct lower-body silhouettes carry the alternation. This is a flattened character animation, not yet separated into paper-doll parts.'},
 'validation':stats,'frames':records}
(ROOT/'survivor-walk-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'scale':scale,'source_median_occupied_height':source_height,'validation':stats},indent=2))
