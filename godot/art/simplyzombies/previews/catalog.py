#!/usr/bin/env python3
"""Compose a reproducible catalog from packaged PNGs without repainting artwork."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, math, sys
HERE=Path(__file__).resolve().parent
PACK=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else HERE.parent/'pack'
OUT=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else HERE/'asset-catalog.png'
M=json.loads((PACK/'manifest.json').read_text()); A=M['assets']; BY={a['id']:a for a in A}
W=1800; PAD=38; GAP=8; INNER=W-2*PAD; NEAR=Image.Resampling.NEAREST
BG='#132025'; CARD='#223238'; CARD2='#25373d'; RULE='#455550'; INK='#eee8d7'; MUTED='#b2bcb4'; ACCENT='#c6a768'; CYAN='#85b4b5'
FAMILY='/usr/share/fonts/truetype/dejavu/DejaVuSans'
def font(n,b=False):return ImageFont.truetype(FAMILY+('-Bold' if b else '')+'.ttf',n)
F_TITLE=font(37,True); F_SUB=font(17); F_HEAD=font(21,True); F_COUNT=font(16); F_LABEL=font(14); F_TINY=font(10); F_NOTE=font(12)
def get(ids):return [BY[i] for i in ids]
def group(name):return [a for a in A if a.get('group')==name]
chars=[a for a in A if a['id'] in ['survivor','shambler']]+group('wearables')
env=group('environment'); props=group('props'); items=group('items'); effects=group('effects'); util=group('utility')
sections=[
 ('01','SURVIVORS & EQUIPMENT',chars,6,180,'Approved bodies with separate, four-direction standing overlays'),
 ('02','TERRAIN & BUILDING MODULES',env,11,140,'Ground tiles, walls, doors, fences and world overlays'),
 ('03','NATURE, FURNITURE & CONTAINERS',props,11,162,'Outdoor dressing, interior props and searchable container states'),
 ('04','INVENTORY ITEMS',[a for a in items if a['id'].startswith('item-')],12,116,'Weapons, ammunition, provisions, medicine, materials and equipment'),
 ('05','HELD WEAPONS',[a for a in items if a['id'].startswith('weapon-')],12,120,'East-facing world sprites with grip and muzzle / tip metadata'),
 ('06','COMBAT & AMBIENT EFFECTS',effects,10,148,'Representative frames from action effects, loops and persistent decals'),
 ('07','VEHICLES',[a for a in util if a['id'].startswith('vehicle-')],8,152,'Intact and wrecked vehicle pairs'),
 ('08','UTILITY OBJECTS',[a for a in util if a['id'].startswith('utility-')],11,144,'Power, work lights, survival equipment, traps and state changes'),
 ('09','INTERFACE SYMBOLS',[a for a in util if a['id'].startswith('ui-')],16,108,'Compact 16 px interaction and survival symbols'),
]
HEADER=151; SH=58; FOOT=54
H=HEADER+sum(SH+math.ceil(len(s[2])/s[3])*(s[4]+GAP)+18 for s in sections)+FOOT
im=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(im)
d.rectangle((PAD,27,PAD+5,109),fill=ACCENT)
d.text((PAD+21,26),'simplyZOMBIES',font=F_TITLE,fill=INK)
d.text((PAD+22,79),'OUTPOST ART CATALOG  /  ORIGINAL PIXEL ASSETS',font=F_SUB,fill=ACCENT)
d.text((W-PAD,35),f'{len(A)} catalog entries',font=font(25,True),fill=INK,anchor='ra')
d.text((W-PAD,77),'185 new assets + 2 approved characters',font=F_SUB,fill=MUTED,anchor='ra')
d.text((PAD,122),'Native previews + integer enlargements  ·  Nearest-neighbor sampling  ·  Animation frames shown as stills',font=F_SUB,fill=MUTED)
short={
 'tile-asphalt-a':'Slate asphalt A','tile-asphalt-b':'Cracked asphalt B','tile-concrete-a':'Concrete A','tile-concrete-b':'Concrete B','tile-grass-a':'Olive grass A','tile-grass-b':'Olive grass B',
 'wall-corner-nw':'NW corner','wall-corner-ne':'NE corner','wall-fence-horizontal':'Horizontal fence','wall-fence-vertical':'Vertical fence','wall-window-intact':'Intact window','wall-window-broken':'Broken window','wall-gate-closed':'Gate / closed','wall-gate-open':'Gate / open','wall-door-open':'Door / open','wall-door-closed':'Door / closed',
 'overlay-road-dashed':'Dashed road line','overlay-road-solid':'Solid road line','overlay-debris':'Rubble + debris','overlay-grass-north':'Grass fringe N','overlay-grass-east':'Grass fringe E','overlay-grass-south':'Grass fringe S','overlay-grass-west':'Grass fringe W',
 'prop-workbench':'Workbench','prop-medical-cabinet':'Medical cabinet','prop-concrete-barrier':'Concrete barrier','nature-rock-cluster':'Rock cluster',
 'gear-vest':'Utility vest overlay','gear-helmet':'Steel helmet overlay','gear-gasmask':'Respirator overlay','gear-backpack':'Backpack overlay',
 'item-empty-magazine':'Empty magazine','item-kitchen-knife':'Kitchen knife','item-assault-rifle':'Assault rifle','item-first-aid-kit':'First aid kit',
 'fx-pistol-muzzle':'Pistol flash','fx-rifle-muzzle':'Rifle flash','fx-shotgun-muzzle':'Shotgun flash','fx-metal-sparks':'Metal sparks','fx-concrete-dust':'Concrete dust','fx-wood-splinters':'Wood splinters','fx-water-splash':'Water splash','fx-blood-pool-dry':'Dried blood pool','fx-blood-pool-fresh':'Fresh blood pool','fx-bullet-hole-metal':'Metal bullet hole','fx-bullet-hole-concrete':'Concrete bullet hole','fx-ejected-casing':'Ejected casing',
 'utility-generator-off':'Generator / off','utility-generator-on':'Generator / running','utility-worklamp-off':'Work lamp / off','utility-worklamp-on':'Work lamp / on','utility-worklamp-activation':'Lamp activation','utility-barricade-intact':'Barricade / intact','utility-barricade-broken':'Barricade / broken','utility-spike-trap-armed':'Spikes / armed','utility-spike-trap-triggered':'Spikes / triggered','utility-rain-collector':'Rain collector',
 'ui-interaction-hand':'Interact','ui-map-marker':'Map marker',
}
for a in props:
 if '-crate-' in a['id']:short[a['id']]='Crate / '+a['id'].rsplit('-',1)[1]
 if '-footlocker-' in a['id']:short[a['id']]='Footlocker / '+a['id'].rsplit('-',1)[1]
 if '-medical-box-' in a['id']:short[a['id']]='Medical box / '+a['id'].rsplit('-',1)[1]

def label(a):
 s=short.get(a['id'],a['label']).replace(' held','').replace('Smg','SMG').replace('Mre','MRE')
 return s

def load(a):
 if a.get('group')=='wearables':
  face='n' if a['id']=='gear-backpack' else 's'
  base=Image.open(PACK/BY['survivor']['frames']['idle_'+face][0]['path']).convert('RGBA')
  gear=Image.open(PACK/a['frames']['idle_'+face][0]['path']).convert('RGBA')
  if a['z_by_direction'][face]<0:
   gear.alpha_composite(base);return gear
  base.alpha_composite(gear);return base
 # Pick a substantial frame without changing pixels; prefer early/middle action frames.
 framepath=a['path']
 if a.get('group')=='effects' and a.get('frames'):
  seq=next(iter(a['frames'].values()))
  candidates=[]
  for f in seq:
   if isinstance(f,dict) and f.get('path'):
    q=Image.open(PACK/f['path']).convert('RGBA');score=sum(q.getchannel('A').getdata());candidates.append((score,f['path']))
  if candidates:framepath=max(candidates)[1]
 if a['id'] in ['survivor','shambler']:framepath=a['frames']['walk_s'][1]['path']
 return Image.open(PACK/framepath).convert('RGBA')

def fitted_lines(text,maxw,maxlines=2):
 words=text.split();lines=[];cur=''
 for word in words:
  nxt=(cur+' '+word).strip()
  if d.textlength(nxt,font=F_LABEL)<=maxw:cur=nxt
  else:
   if cur:lines.append(cur)
   cur=word
 if cur:lines.append(cur)
 # Available short labels fit in two lines in this layout.
 if len(lines)>maxlines:raise ValueError('Label overflow '+text+' width '+str(maxw))
 return lines
seen=[];y=HEADER
for num,title,assets,cols,rh,note in sections:
 d.line((PAD,y,W-PAD,y),fill=RULE,width=1)
 d.text((PAD,y+15),num,font=F_COUNT,fill=ACCENT)
 d.text((PAD+34,y+11),title,font=F_HEAD,fill=INK)
 d.text((W-PAD,y+13),str(len(assets))+' assets',font=F_COUNT,fill=ACCENT,anchor='ra')
 d.text((PAD+34,y+36),note,font=F_NOTE,fill=MUTED)
 y+=SH;cw=(INNER-(cols-1)*GAP)/cols
 for i,a in enumerate(assets):
  x=round(PAD+(i%cols)*(cw+GAP));cy=y+(i//cols)*(rh+GAP);wi=round(cw)
  d.rectangle((x,cy,x+wi-1,cy+rh-1),fill=CARD2 if i%2 else CARD)
  sp=load(a);seen.append(a['id'])
  labeltext=label(a);lines=fitted_lines(labeltext,wi-10)
  labelh=14*len(lines)
  # Main artwork retains canvas and integer scaling. Larger world props stay native.
  previewh=rh-38-labelh
  primary=sp.crop(sp.getbbox()) if a['id'] in ['survivor','shambler'] or a.get('group')=='wearables' else sp
  scale=max(1,min(4,int((wi-16)/primary.width),int(previewh/primary.height)))
  if a['id'].startswith('vehicle-'):scale=1
  large=primary.resize((primary.width*scale,primary.height*scale),NEAR)
  px=x+(wi-large.width)//2;py=cy+4+(previewh-large.height)//2
  im.paste(large,(px,py),large)
  # Native thumbnail remains exact 1x. Omit duplicate thumbnail when main is already 1x.
  if scale>1:
   nx=x+8;ny=cy+rh-labelh-7-sp.height
   # Put native beside the enlarged crop when the bottom area is too short; no sprite repainting.
   if ny<cy+previewh-3:ny=cy+rh-labelh-7-sp.height
   im.paste(sp,(nx,ny),sp)
   d.text((x+wi-6,cy+rh-labelh-20),str(scale)+'× + 1×',font=F_TINY,fill=MUTED,anchor='ra')
  else:d.text((x+wi-6,cy+rh-labelh-20),'1× native',font=F_TINY,fill=MUTED,anchor='ra')
  ty=cy+rh-labelh-4
  for ln in lines:d.text((x+wi/2,ty),ln,font=F_LABEL,fill=INK,anchor='mt');ty+=14
  if a.get('frames') and a.get('group') not in ['wearables']:
   d.rectangle((x+wi-7,cy+6,x+wi-4,cy+9),fill=CYAN)
 y+=math.ceil(len(assets)/cols)*(rh+GAP)+18
if len(seen)!=len(A) or set(seen)!=set(BY):raise ValueError('Catalog misses or duplicates assets')
d.line((PAD,y,W-PAD,y),fill=RULE,width=1)
d.text((PAD,y+15),'SOURCE OF TRUTH: PACK / MANIFEST.JSON',font=F_NOTE,fill=ACCENT)
d.text((W-PAD,y+15),'Original artwork  ·  All 187 entries represented  ·  Transparent PNG assets',font=F_NOTE,fill=MUTED,anchor='ra')
OUT.parent.mkdir(parents=True,exist_ok=True);im.save(OUT)
print(json.dumps({'path':str(OUT),'size':[W,H],'entries':len(seen),'sections':len(sections)}))
