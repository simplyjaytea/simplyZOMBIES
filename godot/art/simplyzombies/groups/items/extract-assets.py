from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, math
ROOT=Path(__file__).resolve().parent
NEAR=Image.Resampling.NEAREST
GROUPS=[('icons-weapons-ammo.png',['pistol','revolver','smg','pump-shotgun','assault-rifle','bolt-rifle','bow','crossbow','kitchen-knife','hatchet','crowbar','baseball-bat','pistol-rounds','rifle-rounds','shells','arrows']),('icons-consumables.png',['bolts','empty-magazine','water-bottle','tin-beans','tinned-meat','bread','apple','mre','bandage-roll','first-aid-kit','painkillers','antiseptic','splint','antibiotics','scrap','wood-planks']),('icons-crafting-gear.png',['cloth','wire','electronics','battery','fuel-can','toolkit','backpack','helmet','vest','gas-mask','flashlight','radio','binoculars','map','key','repair-kit'])]
weapons=GROUPS[0][1][:12]
categories={x:'weapon' for x in weapons}
for x in ['pistol-rounds','rifle-rounds','shells','arrows','bolts','empty-magazine']:categories[x]='ammo'
for x in ['water-bottle','tin-beans','tinned-meat','bread','apple','mre']:categories[x]='food-drink'
for x in ['bandage-roll','first-aid-kit','painkillers','antiseptic','splint','antibiotics']:categories[x]='medical'
for x in ['scrap','wood-planks','cloth','wire','electronics','battery','fuel-can','toolkit']:categories[x]='crafting'
assets=[]; extraction=[]
def trim_bounds(im):
 # Threshold is solely a measurement mask; original RGBA is retained untouched.
 b=im.getchannel('A').point(lambda x:255 if x>=128 else 0).getbbox()
 if not b:raise ValueError('No opaque sprite')
 return (max(0,b[0]-1),max(0,b[1]-1),min(im.width,b[2]+1),min(im.height,b[3]+1))
def fitted(im,limit,canvas):
 s=min(limit[0]/im.width,limit[1]/im.height)
 size=(max(1,round(im.width*s)),max(1,round(im.height*s)))
 sprite=im.resize(size,NEAR)
 dest=((canvas[0]-size[0])//2,(canvas[1]-size[1])//2)
 out=Image.new('RGBA',canvas);out.paste(sprite,dest)
 return out,size,dest
for sheet,names in GROUPS:
 im=Image.open(ROOT/'sources'/sheet)
 for i,n in enumerate(names):
  cell=(round(i%4*im.width/4),round(i//4*im.height/4),round((i%4+1)*im.width/4),round((i//4+1)*im.height/4))
  crop=im.crop(cell);b=trim_bounds(crop);sprite=crop.crop(b)
  out,size,dest=fitted(sprite,(27,27),(32,32));path=f'icons/item-{n}.png';out.save(ROOT/path)
  cat=categories.get(n,'gear')
  a={'id':'item-'+n,'label':n.replace('-',' ').title(),'category':'inventory','itemCategory':cat,'path':path,'size':[32,32],'anchor':[16,16],'occupiedSize':size,'iconOnly':True}
  if n in weapons:a['heldAsset']='weapon-'+n
  assets.append(a)
  extraction.append({'id':a['id'],'source':'sources/'+sheet,'cell':cell,'cropWithinCell':b,'nativeOccupied':size,'placement':dest,'method':'Original RGBA crop, nearest-neighbor resize, transparent padding. No repainting or palette replacement.'})
# Source rectangles separate weapons with individually inspected bow row overlap.
held_specs=[
 ('pistol',(130,60,390,230),(24,16),(12,10),(204,174),(335,127),'pistol',0.3),
 ('revolver',(610,60,900,235),(24,16),(15,10),(685,180),(877,116),'pistol',0.45),
 ('smg',(1120,60,1450,235),(32,16),(19,11),(1305,180),(1416,131),'smg',0.11),
 ('pump-shotgun',(40,325,465,470),(48,16),(25,9),(213,402),(445,366),'shotgun',0.9),
 ('assault-rifle',(530,315,1000,480),(48,16),(26,10),(675,410),(978,368),'rifle',0.15),
 ('bolt-rifle',(1080,320,1515,460),(48,16),(27,9),(1230,410),(1496,365),'rifle',1.2),
 ('bow',(180,480,385,780),(24,32),(14,22),(261,632),(361,631),'arrow',0.8),
 ('crossbow',(570,530,940,730),(48,24),(25,13),(696,648),(918,631),'bolt',1.1),
 ('kitchen-knife',(1150,580,1450,705),(24,16),(14,4),(1221,644),(1430,631),'melee',0.35),
 ('hatchet',(70,810,405,960),(24,16),(16,7),(146,873),(375,889),'melee',0.55),
 ('crowbar',(570,815,965,945),(32,16),(22,6),(644,881),(941,879),'melee',0.6),
 ('baseball-bat',(1080,820,1500,940),(32,16),(22,5),(1173,886),(1482,882),'melee',0.65)
]
im=Image.open(ROOT/'sources/held-weapons.png')
for n,box,canvas,limit,grip,muzzle,fx,cd in held_specs:
 cell=im.crop(box);b=trim_bounds(cell);sprite=cell.crop(b);out,size,dest=fitted(sprite,limit,canvas)
 def xy(p):return [round(dest[0]+(p[0]-box[0]-b[0])*size[0]/sprite.width,2),round(dest[1]+(p[1]-box[1]-b[1])*size[1]/sprite.height,2)]
 g=xy(grip);m=xy(muzzle);path='held/weapon-'+n+'.png';out.save(ROOT/path)
 a={'id':'weapon-'+n,'label':n.replace('-',' ').title()+' held','category':'held-weapon','path':path,'size':canvas,'occupiedSize':size,'anchor':g,'grip':g,'muzzle':m,'tip':m,'facing':'east','inventoryAsset':'item-'+n,'weapon':{'grip':g,'muzzle':m,'demoFxType':fx,'demoCooldownSeconds':cd,'demoOnly':True}}
 assets.append(a);extraction.append({'id':a['id'],'source':'sources/held-weapons.png','cell':box,'cropWithinCell':b,'nativeOccupied':size,'placement':dest,'gripSource':grip,'muzzleSource':muzzle,'method':'Original RGBA crop, nearest-neighbor resize, transparent padding. Measurement mask only; alpha preserved.'})
manifest={'version':1,'group':'core-items-weapons','title':'Core item set and held weapons','description':'48 inventory icons and 12 separate held weapons. Concrete core item set; does not assert complete game catalog coverage. Gear icons are inventory representations, not fitted character overlays.','nativePixelArt':True,'pixelSampling':'nearest','assets':assets,'counts':{'inventory':48,'heldWeapons':12},'notes':['Grip/muzzle coordinates use top-left texture origin and east/right weapon aim.','Cooldown and FX metadata are preview timings only, not game balance or combat logic.','Hatchet tip indicates head position; its cutting edge angles downward/right.','Weapon sprite art is static; runtime rotation/recoil and separate FX provide actions.','Original generated alpha is preserved, including a few partially transparent edge pixels.','Icons contain simplified pictograms only; no textual item labels are baked into the art.']}
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2))
(ROOT/'metadata/extraction.json').write_text(json.dumps(extraction,indent=2))
# Exact-size atlas plus labelled nearest-neighbor inspection contacts.
atlas=Image.new('RGBA',(8*32,6*32))
for i,a in enumerate(assets[:48]):atlas.paste(Image.open(ROOT/a['path']),(i%8*32,i//8*32))
atlas.save(ROOT/'icons/inventory-atlas.png')
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',12)
contact=Image.new('RGB',(8*160,6*165+60),'#172328');d=ImageDraw.Draw(contact)
d.text((18,18),'simplyZOMBIES / 48 CORE INVENTORY ICONS / NATIVE + 3x',font=font,fill='#e8dec9')
for i,a in enumerate(assets[:48]):
 x=i%8*160;y=i//8*165+60;d.rectangle((x+4,y+2,x+155,y+158),fill='#293840');sp=Image.open(ROOT/a['path']);contact.paste(sp.resize((96,96),NEAR),(x+31,y+7),sp.resize((96,96),NEAR));contact.paste(sp,(x+12,y+119),sp);d.text((x+48,y+120),a['label'],font=font,fill='#e7ddc8')
contact.save(ROOT/'previews/inventory-contact.png')
contact=Image.new('RGB',(4*270,3*160+60),'#172328');d=ImageDraw.Draw(contact)
d.text((18,18),'simplyZOMBIES / HELD WEAPONS / NATIVE + 4x / ORANGE GRIP, CYAN TIP',font=font,fill='#e8dec9')
for i,a in enumerate(assets[48:]):
 x=i%4*270;y=i//4*160+60;d.rectangle((x+4,y+2,x+265,y+154),fill='#293840');sp=Image.open(ROOT/a['path']);big=sp.resize((sp.width*4,sp.height*4),NEAR);ox=x+(270-big.width)//2;oy=y+6;contact.paste(big,(ox,oy),big)
 for pt,c in [(a['grip'],'#ffad59'),(a['muzzle'],'#6eeae5')]:
  px=ox+round(pt[0]*4);py=oy+round(pt[1]*4);d.rectangle((px-1,py-1,px+1,py+1),fill=c)
 contact.paste(sp,(x+16,y+119),sp);d.text((x+72,y+120),a['label'],font=font,fill='#e7ddc8')
contact.save(ROOT/'previews/held-contact.png')
print('Exported',len(assets),'assets')
