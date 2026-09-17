from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'native'
CROPS = ROOT / 'source-crops'
CROPS.mkdir(exist_ok=True)
RESAMPLE = Image.Resampling.NEAREST
assets = []
extraction = []

def extract(source, box, name, label, canvas, content, category, state=None, group=None):
    sheet = Image.open(ROOT/'sources'/source).convert('RGBA')
    cell = sheet.crop(box)
    # Use the alpha support to identify a crop; do not repaint or remove pixels.
    bounds = cell.getchannel('A').point(lambda v: 255 if v >= 128 else 0).getbbox()
    if not bounds: raise ValueError(name)
    l,t,r,b = bounds
    bounds = (max(0,l-2), max(0,t-2), min(cell.width,r+2), min(cell.height,b+2))
    crop = cell.crop(bounds)
    crop.save(CROPS/f'{name}.png')
    if content[1] is None:
        size = (content[0], round(crop.height*content[0]/crop.width))
    else:
        s = min(content[0]/crop.width,content[1]/crop.height)
        size = (round(crop.width*s),round(crop.height*s))
    reduced = crop.resize(size,RESAMPLE)
    origin = ((canvas[0]-size[0])//2,canvas[1]-2-size[1])
    if origin[1]<0: raise ValueError((name,origin))
    result = Image.new('RGBA',canvas)
    result.alpha_composite(reduced,origin)
    result.save(OUT/f'{name}.png')
    record = {'id': name, 'label': label, 'category':category, 'path':f'native/{name}.png', 'size':list(canvas),'anchor':[canvas[0]//2,canvas[1]-2]}
    if state: record.update({'state':state, 'stateGroup':group})
    assets.append(record)
    extraction.append({'id':name,'source':f'sources/{source}','sourceCell':list(box),'alphaCropInCell':list(bounds),'resize':list(size),'origin':list(origin),'operation':'crop, nearest-neighbor resize, transparent padding; original alpha preserved'})

nature = [
('pine','Pine tree',(64,96),(54,88)),('broadleaf','Broadleaf tree',(80,96),(72,86)),('dead-tree','Dead tree',(64,96),(54,82)),('bush','Low bush',(32,32),(28,22)),
('reeds','Reeds',(24,32),(20,27)),('rock-cluster','Rock cluster',(32,24),(28,20)),('stump','Tree stump',(24,24),(20,20)),('fallen-log','Fallen log',(48,24),(42,20))]
for n,(id,label,canvas,content) in enumerate(nature):
    col,row=n%4,n//4
    xs=[0,400,830,1160,1536] if row==0 else [0,384,768,1152,1536]
    box=(xs[col],[0,680][row],xs[col+1],[680,1024][row])
    extract('nature-source.png',box,'nature-'+id,label,canvas,content,'nature')

props = [
('barrel','Oil barrel',(24,32),(16,24)),('dumpster','Dumpster',(48,32),(44,28)),('concrete-barrier','Concrete barrier',(48,24),(44,20)),('pallet-stack','Pallet stack',(32,32),(28,24)),
('workbench','Scavenger workbench',(48,32),(42,26)),('bed','Bed',(48,32),(42,27)),('chair','Wooden chair',(24,32),(15,24)),('table','Wooden table',(40,32),(34,26)),
('fridge','Old refrigerator',(24,40),(20,35)),('shelf','Supply shelf',(40,32),(34,27)),('medical-cabinet','Medical cabinet',(24,32),(21,27)),('streetlamp','Streetlamp',(24,64),(21,57)),
('road-sign','Blank road sign',(24,40),(20,35)),('traffic-cone','Traffic cone',(16,24),(14,21)),('trash-bags','Rubbish bags',(32,24),(28,21)),('fence-post','Fence post',(16,32),(10,28))]
ys=[0,300,530,800,1086]
for n,(id,label,canvas,content) in enumerate(props):
    col,row=n%4,n//4
    extract('props-source.png',(col*362,ys[row],(col+1)*362,ys[row+1]),'prop-'+id,label,canvas,content,'prop')

container_kinds=[('wood-crate','Wooden crate'),('metal-footlocker','Metal footlocker'),('medical-box','Medical box')]
xs=[0,550,1010,1536];ys=[0,342,680,1024]
state_groups=[]
for row,(kind,label) in enumerate(container_kinds):
    group='prop-'+kind
    state_ids={}
    for col,state in enumerate(['closed','open','empty']):
        name=group+'-'+state
        extract('containers-source.png',(xs[col],ys[row],xs[col+1],ys[row+1]),name,label+' / '+state,(32,32),(26,None),'container',state,group)
        state_ids[state]=name
    state_groups.append({'id':group,'label':label,'size':[32,32],'anchor':[16,30],'states':state_ids,'defaultState':'closed','transitionOrder':['closed','open','empty'],'notes':'Three discrete states; not an interpolated opening animation.'})

def font(size):
    return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',size)

def contact(selected,cols,cell,title,out):
    rows=(len(selected)+cols-1)//cols;cw,ch=cell
    im=Image.new('RGB',(cols*cw+32,rows*ch+88),(28,33,33));d=ImageDraw.Draw(im)
    d.text((20,15),title,font=font(22),fill=(227,230,214))
    d.text((20,45),'Original game assets | native + 4x nearest neighbor | 28px survivor scale',font=font(13),fill=(164,179,168))
    for n,a in enumerate(selected):
        x=16+(n%cols)*cw;y=80+(n//cols)*ch
        d.rectangle((x+2,y+2,x+cw-5,y+ch-5),fill=(43,49,47))
        spr=Image.open(ROOT/a['path']);big=spr.resize((spr.width*4,spr.height*4),RESAMPLE)
        px=x+(cw-big.width)//2;py=y+ch-50-big.height
        im.paste(big,(px,py),big)
        im.paste(spr,(x+10,y+ch-42-spr.height),spr)
        d.text((x+10,y+ch-31),a['label'],font=font(13),fill=(224,228,213))
        d.text((x+10,y+ch-16),f"{a['size'][0]} x {a['size'][1]} | pivot {a['anchor']}",font=font(10),fill=(150,166,155))
    im.save(ROOT/'previews'/out)

contact(assets[:8],4,(330,440),'simplyZOMBIES / NATURE','nature-contact.png')
contact(assets[8:24],4,(260,310),'simplyZOMBIES / PROPS','props-contact.png')
contact(assets[24:],3,(250,200),'simplyZOMBIES / SEARCHABLE CONTAINERS','containers-contact.png')

# State transitions are held long enough to make closed/open/looted differences clear.
frames=[]
for state in ['closed','open','empty','open']:
    im=Image.new('RGB',(624,208),(31,37,35));d=ImageDraw.Draw(im)
    d.text((16,12),'SEARCHABLE CONTAINERS / '+state.upper(),font=font(17),fill=(235,231,211))
    for i,(kind,label) in enumerate(container_kinds):
        a=next(a for a in assets if a['id']=='prop-'+kind+'-'+state)
        spr=Image.open(ROOT/a['path']).resize((128,128),RESAMPLE)
        im.paste(spr,(40+i*200,45),spr)
        d.text((23+i*200,180),label,font=font(13),fill=(181,197,179))
    frames.append(im)
frames[0].save(ROOT/'previews/container-states.gif',save_all=True,append_images=frames[1:],duration=[900,1100,1300,500],loop=0,disposal=2)

manifest={'version':1,'name':'simplyZOMBIES nature, props and container states','logicalTileSize':32,'referenceCharacterHeight':28,'camera':'elevated top-down orthographic','assets':assets,'stateGroups':state_groups,'notes':['Original artwork informed by official ZERO Sievert screenshots; no copied game sprites.','Static objects use ground anchors at the bottom center of padded logical canvases.','Three searchable containers have fixed 32x32 canvases and [16,30] ground anchors.','Container sprite state changes are discrete; GIF is a state-transition preview.','All PNG alpha is preserved from generated RGBA source.']}
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ROOT/'extraction.json').write_text(json.dumps(extraction,indent=2)+'\n')
atlas=Image.new('RGBA',(6*96,6*96))
for i,a in enumerate(assets):
    spr=Image.open(ROOT/a['path'])
    x=(i%6)*96+(96-spr.width)//2;y=(i//6)*96+96-spr.height
    atlas.alpha_composite(spr,(x,y))
    a['atlasRect']=[x,y,spr.width,spr.height]
atlas.save(ROOT/'props-atlas.png')
manifest['atlas']='props-atlas.png'
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'assets':len(assets),'containerGroups':len(state_groups),'path':str(ROOT/'manifest.json')}))
