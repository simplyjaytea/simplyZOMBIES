from pathlib import Path
from PIL import Image, ImageDraw
import json, shutil, hashlib

ROOT=Path(__file__).resolve().parent
SOURCE=ROOT/'source'/'shambler-walk-rgba.png'
im=Image.open(SOURCE).convert('RGBA')
directions=['s','e','n','w']
rows=[(0,380,354),(380,750,705),(750,1105,1071),(1105,1536,1417)]
scale=28/294
atlas=Image.new('RGBA',(128,192))
frames=[]
for r,d in enumerate(directions):
    y0,y1,baseline=rows[r]
    for c in range(4):
        cell=im.crop((c*256,y0,(c+1)*256,y1))
        bbox=cell.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        cropped=cell.crop(bbox)
        cropped.save(ROOT/'source-crops'/f'shambler_walk_{d}_{c:02d}.png')
        native=cropped.transform((32,48),Image.Transform.AFFINE,(1/scale,0,128-16/scale-bbox[0],0,1/scale,baseline-y0-40/scale-bbox[1]),resample=Image.Resampling.NEAREST)
        filename=f'shambler_walk_{d}_{c:02d}.png'
        native.save(ROOT/'native'/filename)
        atlas.alpha_composite(native,(c*32,r*48))
        frames.append({'id':f'shambler_walk_{d}_{c:02d}','direction':d,'frame':c,'texture':'native/'+filename,'atlas_rect':[c*32,r*48,32,48],'pivot':[16,40],'source_cell':[c*256,y0,256,y1-y0],'source_crop_bbox':bbox,'source_registration':[128,baseline-y0],'occupied_bbox':native.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox(),'sha256':hashlib.sha256(native.tobytes()).hexdigest()})
atlas.save(ROOT/'native'/'shambler-walk-atlas.png')
contact=Image.new('RGB',(1024,1536),'#343b35')
contact.paste(atlas.resize((1024,1536),Image.Resampling.NEAREST),mask=atlas.getchannel('A').resize((1024,1536),Image.Resampling.NEAREST))
contact.save(ROOT/'shambler-walk-contact.png')
loop=[]
for c in range(4):
    out=Image.new('RGBA',(128,48),'#343b35')
    for r in range(4):
        out.alpha_composite(atlas.crop((c*32,r*48,c*32+32,r*48+48)),(r*32,0))
    loop.append(out.convert('RGB').resize((1024,384),Image.Resampling.NEAREST))
loop[0].save(ROOT/'shambler-walk-loop.gif',save_all=True,append_images=loop[1:],duration=200,loop=0,disposal=2)
manifest={'title':'simplyZOMBIES shambler directional walk','character':'shambler','state':'walk','directions':directions,'frames_per_direction':4,'fps':5,'loop':True,'cell_size':[32,48],'pivot':[16,40],'atlas':'native/shambler-walk-atlas.png','source':'source/shambler-walk-rgba.png','source_size':list(im.size),'uniform_scale':scale,'processing':'Source bounds located at alpha >=128; original RGBA values preserved within each crop. Each crop transformed with uniform nearest-neighbor scale, fixed original cell center x=128 and a shared ground baseline per row. No per-frame body bounds centering, silhouette editing, color changes, or alpha thresholding.','frames':frames}
(ROOT/'shambler-walk-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'atlas':str(ROOT/'native'/'shambler-walk-atlas.png'),'frames':len(frames),'unique_frames':len({f['sha256'] for f in frames}),'scale':scale},indent=2))
