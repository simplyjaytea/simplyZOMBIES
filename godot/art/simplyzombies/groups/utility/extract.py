from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,math,hashlib
ROOT=Path(__file__).resolve().parent
N=ROOT/'native'; F=ROOT/'frames'; P=ROOT/'previews'
for p in (N,F,P,ROOT/'crops'):p.mkdir(exist_ok=True)
assets=[]; extraction=[]
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14)
small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',11)
def bbox(im):return im.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
def write_asset(id,label,category,im,anchor,extra=None):
 path='native/'+id+'.png';im.save(ROOT/path)
 item=dict(id=id,label=label,category=category,path=path,size=list(im.size),anchor=anchor)
 if extra:item.update(extra)
 assets.append(item);return item

def place(crop,b,scale,canvas,anchor,baseline=None,center=None):
 # Only crop, nearest-neighbor resize and transparent padding; no repainting or alpha repair.
 b=(max(0,b[0]-2),max(0,b[1]-2),min(crop.width,b[2]+2),min(crop.height,b[3]+2))
 cut=crop.crop(b)
 dest=cut.resize((max(1,round(cut.width*scale)),max(1,round(cut.height*scale))),Image.Resampling.NEAREST)
 baseline=baseline if baseline is not None else b[3]-2
 center=center if center is not None else (b[0]+b[2])/2
 x=round(anchor[0]-(center-b[0])*scale);y=round(anchor[1]-(baseline-b[1])*scale)
 out=Image.new('RGBA',canvas);out.alpha_composite(dest,(x,y));return out

# Vehicle source rows are deliberately measured from the visible objects rather than assumed equal cells.
im=Image.open(ROOT/'sources/vehicles.png').convert('RGBA')
ybounds=[0,304,593,871,im.height];xbounds=[0,620,im.width]
for r,kind in enumerate(['hatchback','van','pickup','ambulance']):
 cells=[]
 for c in range(2):
  rect=(xbounds[c],ybounds[r],xbounds[c+1],ybounds[r+1]); crop=im.crop(rect); b=bbox(crop);cells.append((crop,b,rect))
 canvas=(96,48) if r==0 else (112,56);anchor=[canvas[0]//2,canvas[1]-2]
 scale=min((canvas[0]-6)/max(b[2]-b[0] for _,b,_ in cells),(canvas[1]-5)/max(b[3]-b[1] for _,b,_ in cells))
 for c,(crop,b,rect) in enumerate(cells):
  state=['intact','wreck'][c];id='vehicle-'+kind+'-'+state
  native=place(crop,b,scale,canvas,anchor)
  write_asset(id,kind.title()+' · '+state,'vehicles',native,anchor,dict(state=state,variantGroup='vehicle-'+kind,facing='east'))
  crop.save(ROOT/'crops'/f'{id}.png');extraction.append(dict(id=id,source='sources/vehicles.png',sourceRect=list(rect),opaqueBounds=list(b),scale=scale,paddingAnchor=anchor))

# Nine utility design studies. Matched states use one shared scale and explicit ground pivot.
im=Image.open(ROOT/'sources/utilities.png').convert('RGBA')
utils=[('generator-off','Generator off',(40,48),32/301),('generator-on','Generator running',(40,48),32/301),('barricade-intact','Wood barricade intact',(48,40),42/354),('barricade-broken','Wood barricade broken',(48,40),42/354),('rain-collector','Rain collector',(40,48),40/350),('stove','Iron stove',(32,40),34/351),('worklamp-off','Work lamp off',(40,48),32/323),('spike-trap-armed','Spike trap armed',(40,40),34/327),('spike-trap-triggered','Spike trap triggered',(40,40),34/327)]
for i,(short,label,canvas,scale) in enumerate(utils):
 c,r=i%3,i//3;rect=(round(c*im.width/3),round(r*im.height/3),round((c+1)*im.width/3),round((r+1)*im.height/3));crop=im.crop(rect);b=bbox(crop);anchor=[canvas[0]//2,canvas[1]-4]
 id='utility-'+short;native=place(crop,b,scale,canvas,anchor)
 write_asset(id,label,'utilities',native,anchor)
 crop.save(ROOT/'crops'/f'{id}.png');extraction.append(dict(id=id,source='sources/utilities.png',sourceRect=list(rect),opaqueBounds=list(b),scale=scale,paddingAnchor=anchor))

# Genuine animation frames. Chassis width/ground anchor govern scale, not changing smoke and light bounds.
im=Image.open(ROOT/'sources/utility-animations.png').convert('RGBA')
anim_frames={}
for row,kind in enumerate(['generator','worklamp']):
 paths=[]
 for c in range(4):
  rect=(384*c,512*row,384*(c+1),512*(row+1));crop=im.crop(rect);b=bbox(crop)
  if kind=='generator':
   chassis=crop.crop((0,173,384,452));cb=bbox(chassis);scale=32/298;center=(cb[0]+cb[2])/2;baseline=451
  else:
   scale=32/308;center=[192.5,192,190,191][c];baseline=391
  anchor=[20,44];native=place(crop,b,scale,(40,48),anchor,baseline=baseline,center=center)
  path=f'frames/utility-{kind}-{c:02d}.png';native.save(ROOT/path);paths.append(dict(path=path))
  crop.save(ROOT/'crops'/f'utility-{kind}-frame-{c:02d}.png')
  extraction.append(dict(id=f'utility-{kind}-{c:02d}',source='sources/utility-animations.png',sourceRect=list(rect),opaqueBounds=list(b),scale=scale,sourceGround=baseline,sourceCenterX=center,paddingAnchor=anchor))
 anim_frames[kind]=paths
 if kind=='generator':
  a=next(a for a in assets if a['id']=='utility-generator-on');a.update(path=paths[0]['path'],frames={'running':paths},fps=6,loop=True,state='running')
 else:
  a=next(a for a in assets if a['id']=='utility-worklamp-off');a['path']=paths[0]['path'];a['state']='off'
  on=Image.open(ROOT/paths[3]['path']);write_asset('utility-worklamp-on','Work lamp on','utilities',on,[20,44],dict(state='on'))
  act=Image.open(ROOT/paths[0]['path']);write_asset('utility-worklamp-activation','Work lamp activation','utilities',act,[20,44],dict(frames={'activate':paths},fps=8,loop=False,holdLastFrame=True))

im=Image.open(ROOT/'sources/ui-icons.png').convert('RGBA')
ui=['crosshair','interaction-hand','backpack','health','hunger','thirst','stamina','radio','warning','ammo','lock','work','wound','temperature','map-marker','exit']
for i,kind in enumerate(ui):
 c,r=i%4,i//4;rect=(round(c*im.width/4),round(r*im.height/4),round((c+1)*im.width/4),round((r+1)*im.height/4));crop=im.crop(rect);b=bbox(crop)
 scale=min(14/(b[2]-b[0]),14/(b[3]-b[1]));cut=crop.crop(b);dest=cut.resize((max(1,round(cut.width*scale)),max(1,round(cut.height*scale))),Image.Resampling.NEAREST)
 native=Image.new('RGBA',(16,16));native.alpha_composite(dest,((16-dest.width)//2,(16-dest.height)//2))
 id='ui-'+kind;write_asset(id,kind.replace('-',' ').title(),'ui',native,[8,8])
 crop.save(ROOT/'crops'/f'{id}.png');extraction.append(dict(id=id,source='sources/ui-icons.png',sourceRect=list(rect),opaqueBounds=list(b),scale=scale))

manifest=dict(name='simplyZOMBIES vehicles, utilities and HUD',version=1,worldTileSize=32,characterOccupiedHeight=28,rendering='nearest-neighbor',assets=assets,notes=['Original generated pixel artwork, informed by ZERO Sievert screenshots; no extracted game art.','Ground anchors are shared within state pairs. Generator smoke and worklamp activation use actual distinct frame shapes.','Vehicles are east-facing static intact/wreck states, not driving animations.','Worklamp activation is a one-shot animation that holds its final frame.','Spikes and barricades have static intact/broken state art, not destruction animation.','Sprites preserve source RGBA, including a few partly transparent edge pixels.'])
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ROOT/'extraction.json').write_text(json.dumps(extraction,indent=2)+'\n')

# Contact sheets only composite the actual native outputs.
world=[a for a in assets if a['category']!='ui'];w=1040;panelW=260;panelH=240;h=68+math.ceil(len(world)/4)*panelH
sheet=Image.new('RGB',(w,h),'#20282b');d=ImageDraw.Draw(sheet);d.text((20,18),'simplyZOMBIES | VEHICLES + UTILITIES',font=font,fill='#ede7d3');d.text((20,40),'Original native sprites at 2x / 4x nearest neighbor; matched ground pivots',font=small,fill='#bac4bf')
for i,a in enumerate(world):
 x=(i%4)*panelW;y=68+(i//4)*panelH;d.rectangle((x+6,y+6,x+panelW-6,y+panelH-6),fill='#303a3b');p=Image.open(ROOT/a['path']);s=2 if a['category']=='vehicles' else 4;p=p.resize((p.width*s,p.height*s),Image.Resampling.NEAREST);sheet.paste(p,(x+(panelW-p.width)//2,y+15),p);d.text((x+15,y+panelH-32),a['label'],font=small,fill='#ede7d3')
sheet.save(P/'world-contact.png')
uiSheet=Image.new('RGB',(768,832),'#20282b');d=ImageDraw.Draw(uiSheet);d.text((20,16),'simplyZOMBIES | HUD ICONS',font=font,fill='#ede7d3')
for i,a in enumerate(a for a in assets if a['category']=='ui'):
 x=(i%4)*192;y=56+(i//4)*192;d.rectangle((x+8,y+8,x+184,y+180),fill='#303a3b');p=Image.open(ROOT/a['path']).resize((112,112),Image.Resampling.NEAREST);uiSheet.paste(p,(x+40,y+24),p);d.text((x+14,y+151),a['label'],font=small,fill='#ede7d3')
uiSheet.save(P/'ui-contact.png')

# Sixteen samples show a looping generator and a lamp that holds at full illumination before reset.
preview=[]
for t in range(16):
 frame=Image.new('RGB',(704,448),'#253132');d=ImageDraw.Draw(frame);d.text((22,16),'simplyZOMBIES | UTILITY ANIMATION',font=font,fill='#ede7d3')
 for j,kind in enumerate(['generator','worklamp']):
  idx=t%4 if kind=='generator' else min(t%8,3);p=Image.open(ROOT/anim_frames[kind][idx]['path']).resize((280,336),Image.Resampling.NEAREST);frame.paste(p,(40+j*344,56),p)
  d.text((60+j*344,412),'GENERATOR / 6 FPS' if kind=='generator' else 'WORKLAMP / ACTIVATE + HOLD',font=small,fill='#ede7d3')
 preview.append(frame)
preview[0].save(P/'utility-animations.gif',save_all=True,append_images=preview[1:],duration=167,loop=0,disposal=2)
# Verify paths, canvas consistency, alpha and unique animation shapes after downscaling.
checks=[]
for a in assets:
 paths=[a['path']]+[f['path'] for state in a.get('frames',{}).values() for f in state]
 for path in paths:
  im=Image.open(ROOT/path);assert im.size==tuple(a['size']);assert im.mode=='RGBA';assert im.getchannel('A').getextrema()[0]==0
 hashes={hashlib.sha256(Image.open(ROOT/f['path']).tobytes()).hexdigest() for state in a.get('frames',{}).values() for f in state}
 if a.get('frames'):assert len(hashes)==4
 checks.append(dict(id=a['id'],pathsValid=True,size=a['size'],transparent=True,uniqueAnimationFrames=len(hashes)))
(ROOT/'verification.json').write_text(json.dumps(dict(assetCount=len(assets),animationFrameCount=8,checks=checks),indent=2)+'\n')
print(json.dumps(dict(assets=len(assets),animationFrames=8,contactSheets=['previews/world-contact.png','previews/ui-contact.png'],animationPreview='previews/utility-animations.gif')))
