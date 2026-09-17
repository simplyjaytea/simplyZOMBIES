from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import json

ROOT=Path(__file__).resolve().parent
DIRS=['s','e','n','w']
FIT={
 'vest':{'s':(13,11,10,22),'e':(9,11,12,22),'n':(14,11,10,22),'w':(9,11,11,22)},
 'helmet':{'s':(16,9,8,10),'e':(16,9,9,10),'n':(16,9,9,10),'w':(16,9,8,10)},
 'gasmask':{'s':(12,11,10,14),'e':(13,11,11,14),'n':(12,10,10,13),'w':(13,11,8,14)},
 'backpack':{'s':(13,10,9,23),'e':(8,12,5,22),'n':(14,12,9,22),'w':(8,12,21,22)}
}
LABELS={'vest':'Olive utility vest','helmet':'Olive steel helmet','gasmask':'Graphite respirator','backpack':'Tan canvas backpack'}
Z={'vest':{'s':2,'e':2,'n':2,'w':2},'helmet':{'s':5,'e':5,'n':5,'w':5},'gasmask':{'s':4,'e':4,'n':4,'w':4},'backpack':{'s':3,'e':-1,'n':3,'w':-1}}
assets=[]; extracts=[]
(ROOT/'source-crops').mkdir(exist_ok=True)
for item in FIT:
 im=Image.open(ROOT/'sources'/f'{item}.png').convert('RGBA')
 if im.getchannel('A').getextrema()[0]!=0: raise ValueError(f'Background is not transparent: {item}')
 atlas=Image.new('RGBA',(128,48));frames={};metadata={}
 for j,d in enumerate(DIRS):
  # Generated helmet profile brims point opposite the requested source labels;
  # assign the actual right-pointing silhouette to east and left to west.
  source_index={'s':0,'e':3,'n':2,'w':1}[d] if item=='helmet' else j
  c=source_index%2;r=source_index//2
  cell=(c*im.width//2,r*im.height//2,(c+1)*im.width//2,(r+1)*im.height//2)
  region=im.crop(cell)
  bbox=region.getchannel('A').point(lambda p:255 if p>=128 else 0).getbbox()
  crop=region.crop(bbox)
  crop.save(ROOT/'source-crops'/f'{item}-{d}.png')
  w,h,x,y=FIT[item][d]
  fitted=crop.resize((w,h),Image.Resampling.NEAREST)
  out=Image.new('RGBA',(32,48));out.alpha_composite(fitted,(x,y))
  path=f'native/gear-{item}-{d}.png';out.save(ROOT/path)
  atlas.alpha_composite(out,(32*j,0))
  frames[f'idle_{d}']=[{'path':path}]
  metadata[d]={'occupied_size':[w,h],'placement':[x,y],'z':Z[item][d]}
  extracts.append({'id':f'gear-{item}-{d}','source':f'sources/{item}.png','source_cell':cell,'alpha_bbox_in_cell':bbox,'native_size':[32,48],'fitted_size':[w,h],'placement':[x,y],'path':path})
 atlas.save(ROOT/'native'/f'gear-{item}-atlas.png')
 assets.append({'id':f'gear-{item}','label':LABELS[item],'category':'wearable','path':f'native/gear-{item}-s.png','size':[32,48],'anchor':[16,40],'offset':[0,0],'directions':DIRS,'frames':frames,'fps':0,'loop':False,'atlas':f'native/gear-{item}-atlas.png','z_by_direction':Z[item],'fit':metadata,'state':'standing-overlay','notes':'Static four-direction overlay fitted to approved survivor idle. No human parts baked in. Animated walk fit needs future per-frame rigging.'})

manifest={'format_version':1,'title':'simplyZOMBIES compact survivor wearables','canvas':[32,48],'anchor':[16,40],'base_reference':'character-revision/pack/native/survivor_{s,e,n,w}.png','direction_order':DIRS,'processing':'Generated isolated equipment, cropped from actual RGBA alpha bounds, resized with nearest-neighbor into directional fit boxes, padded with transparency. No pixel repaint, palette edit or procedural background removal. Fit resizing may use separate X and Y ratios.','status':'Four wearable items, four static directional overlays each; not animated per-frame rigs.','assets':assets,'extraction':extracts,'layer_order_note':'Backpack east/west behind body; all other entries over body at z values. Draw gasmask before helmet. South backpack is front straps only; north is exterior backpack.'}
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2))

# Compose unchanged native character with overlays for actual fit inspection.
cw,ch=224,310
preview=Image.new('RGB',(cw*4,ch*5+76),(29,35,39));draw=ImageDraw.Draw(preview)
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',17)
small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',13)
draw.text((20,16),'simplyZOMBIES • MODULAR WEARABLE FIT',font=font,fill=(233,226,207))
draw.text((20,43),'Original gear • untouched approved survivor • 32×48 native canvas • 5× nearest-neighbor',font=small,fill=(166,178,172))
for row,choice in enumerate(['vest','backpack','helmet','gasmask','all']):
 for col,d in enumerate(DIRS):
  base=Image.open(ROOT.parent.parent/'character-revision'/'pack'/'native'/f'survivor_{d}.png').convert('RGBA')
  stack=[(0,base)]
  for item in FIT:
   if choice=='all' or choice==item: stack.append((Z[item][d],Image.open(ROOT/'native'/f'gear-{item}-{d}.png')))
  comp=Image.new('RGBA',(32,48))
  for z,layer in sorted(stack,key=lambda a:a[0]):comp.alpha_composite(layer)
  x=col*cw;y=76+row*ch
  draw.rectangle((x+8,y+8,x+cw-8,y+ch-8),fill=(43,52,57))
  preview.paste(comp.resize((160,240),Image.Resampling.NEAREST),(x+32,y+24),comp.resize((160,240),Image.Resampling.NEAREST))
  draw.text((x+20,y+277),(LABELS.get(choice,'Full loadout')+' / '+d.upper()),font=small,fill=(226,217,195))
preview.save(ROOT/'previews'/'wearable-fit-contact.png')

contact=Image.new('RGBA',(4*128,4*192),(37,44,49,255))
for row,item in enumerate(FIT):
 for col,d in enumerate(DIRS):
  im=Image.open(ROOT/'native'/f'gear-{item}-{d}.png')
  contact.alpha_composite(im.resize((128,192),Image.Resampling.NEAREST),(128*col,192*row))
contact.save(ROOT/'previews'/'wearables-only-contact.png')
print(json.dumps({'assets':len(assets),'directional_sprites':len(extracts),'preview':str(ROOT/'previews'/'wearable-fit-contact.png')}))
