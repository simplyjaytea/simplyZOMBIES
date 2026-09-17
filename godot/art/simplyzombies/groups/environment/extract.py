from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import json, math, statistics

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'textures'
OUT.mkdir(exist_ok=True)
(ROOT/'source-crops').mkdir(exist_ok=True)
assets=[]
extractions=[]
NN=Image.Resampling.NEAREST

def export(id,label,category,im,anchor,meta=None):
    im=im.convert('RGBA')
    path='textures/'+id+'.png'
    im.save(ROOT/path)
    a={'id':id,'label':label,'category':category,'path':path,'size':list(im.size),'anchor':anchor,'opacity':'opaque' if im.getchannel('A').getextrema()==(255,255) else 'transparent-rgba'}
    if meta:a.update(meta)
    assets.append(a)

def crop_cell(source,index,cols,rows):
    im=Image.open(ROOT/'sources'/source).convert('RGBA');w,h=im.size
    c,r=index%cols,index//cols
    box=[round(c*w/cols),round(r*h/rows),round((c+1)*w/cols),round((r+1)*h/rows)]
    return im.crop(box),box

terrain=[('asphalt-a','Slate asphalt A'),('asphalt-b','Cracked asphalt B'),('concrete-a','Worn concrete A'),('concrete-b','Chipped concrete B'),('grass-a','Olive grass A'),('grass-b','Olive grass B'),('dirt-a','Ochre dirt A'),('dirt-b','Ochre dirt B'),('wood-floor','Wood plank floor'),('interior-tile','Teal and cream floor'),('rubble','Rubble ground'),('water','Still teal water')]
for i,(name,label) in enumerate(terrain):
    cell,box=crop_cell('terrain-refined-sheet.png',i,4,3)
    w,h=cell.size
    # Crop the margin to avoid source-sheet divider pixels. No artwork is repainted.
    rect=[8,8,w-8,h-8]
    # Select four complete checker squares so the designed floor pattern repeats.
    if name=='interior-tile':rect=[60,60,300,300]
    crop=cell.crop(rect)
    crop.save(ROOT/'source-crops'/('tile-'+name+'.png'))
    out=crop.resize((32,32),NN)
    export('tile-'+name,label,'terrain',out,[0,0],{'tileSize':[32,32],'repeat':'visual 2x2 preview checked; no autotile rules supplied'})
    extractions.append({'id':'tile-'+name,'source':'sources/terrain-refined-sheet.png','cell':box,'cropWithinCell':rect,'outputSize':[32,32],'resampling':'nearest'})

walls=[('plaster','Cream plaster wall'),('brick','Red brick wall'),('interior','Interior blue wall'),('corner-nw','Cream north-west corner'),('corner-ne','Cream north-east corner'),('door-closed','Olive door closed'),('door-open','Olive door open'),('window-intact','Intact window'),('window-broken','Broken window'),('fence-horizontal','Chain-link fence horizontal'),('fence-vertical','Chain-link fence vertical'),('gate-closed','Chain-link gate closed'),('gate-open','Chain-link gate open')]
for i,(name,label) in enumerate(walls):
    cell,box=crop_cell('architecture-sheet.png',i,4,4)
    bbox=cell.getchannel('A').point(lambda a:255 if a>128 else 0).getbbox()
    crop=cell.crop(bbox)
    crop.save(ROOT/'source-crops'/('wall-'+name+'.png'))
    meta={'drawLayer':'y-sort','geometryNote':'Native canvas and pivot are normalized. Source state wear/perspective may vary slightly; collision and exact map snapping require engine setup.'}
    transform=None
    if name.startswith('corner'):
        out=Image.new('RGBA',(64,64))
        content=crop.resize((64,64),NN)
        if name=='corner-ne':
            content=ImageOps.mirror(content)
            transform='horizontal mirror corrects the generated corner handedness'
        out.alpha_composite(content,(0,0));anchor=[32,64]
        meta['joins']=['north','west' if name.endswith('nw') else 'east']
    elif name=='fence-vertical':
        out=Image.new('RGBA',(32,64));content=crop.resize((10,64),NN);out.alpha_composite(content,(11,0));anchor=[16,64]
    elif name.startswith('fence'):
        out=Image.new('RGBA',(64,32));content=crop.resize((64,30),NN);out.alpha_composite(content,(0,2));anchor=[32,32]
    elif name.startswith('gate'):
        out=Image.new('RGBA',(64,48));height=40 if name.endswith('open') else 30
        content=crop.resize((64,height),NN);out.alpha_composite(content,(0,2));anchor=[32,32]
        meta['state']='open' if name.endswith('open') else 'closed'
        meta['stateGroup']='chain-link-gate';meta['interaction']='switch sprite by state'
    else:
        out=Image.new('RGBA',(64,48));height=44 if name=='door-open' else 40
        content=crop.resize((64,height),NN);out.alpha_composite(content,(0,4));anchor=[32,44]
        if name.startswith('door'):
            meta['state']='open' if name.endswith('open') else 'closed';meta['stateGroup']='olive-door';meta['interaction']='switch sprite by state'
        if name.startswith('window'):
            meta['state']='broken' if name.endswith('broken') else 'intact';meta['stateGroup']='window';meta['interaction']='switch sprite by state'
    export('wall-'+name,label,'architecture',out,anchor,meta)
    extractions.append({'id':'wall-'+name,'source':'sources/architecture-sheet.png','cell':box,'cropWithinCell':list(bbox),'outputSize':list(out.size),'contentSize':list(content.size),'resampling':'nearest','transform':transform})

overlays=[('grass-north','Grass fringe north'),('grass-east','Grass fringe east'),('grass-south','Grass fringe south'),('grass-west','Grass fringe west'),('road-dashed','Dashed ochre road line'),('road-solid','Solid ochre road line'),('puddle','Slate puddle'),('debris','Rubble and paper debris')]
for i,(name,label) in enumerate(overlays):
    cell,box=crop_cell('overlay-sheet.png',i,4,2)
    bbox=cell.getchannel('A').point(lambda a:255 if a>128 else 0).getbbox()
    crop=cell.crop(bbox);crop.save(ROOT/'source-crops'/('overlay-'+name+'.png'))
    out=Image.new('RGBA',(32,32))
    if i in [0,2]:size=(32,16);origin=(0,0 if i==0 else 16)
    elif i in [1,3]:size=(16,32);origin=(16 if i==1 else 0,0)
    elif i in [4,5]:size=(3,32);origin=(15,0)
    else:size=(28,28);origin=(2,2)
    out.alpha_composite(crop.resize(size,NN),origin)
    export('overlay-'+name,label,'terrain-overlay',out,[0,0],{'drawLayer':'ground-overlay','tileSize':[32,32]})
    extractions.append({'id':'overlay-'+name,'source':'sources/overlay-sheet.png','cell':box,'cropWithinCell':list(bbox),'outputSize':[32,32],'contentSize':list(size),'contentOrigin':list(origin),'resampling':'nearest'})

manifest={'name':'simplyZOMBIES environment revision','version':1,'worldTileSize':32,'camera':'elevated top-down orthographic','assets':assets,'notes':['Original generated artwork inspired by reference screenshot pixel discipline.','Transparent sources retain their original alpha, including occasional fractional edge pixels.','Doors, windows and gate are discrete state sprites, not animated frame sequences.','Corner east is mechanically mirrored to correct generated handedness.','No engine TileSet, collision polygons or autotile adjacency rules are included.']}
manifest['atlases']=[]
for family,group,cell,cols in [('terrain',assets[:12],[32,32],4),('architecture',assets[12:25],[64,64],4),('overlays',assets[25:],[32,32],4)]:
    atlas=Image.new('RGBA',(cell[0]*cols,cell[1]*math.ceil(len(group)/cols)))
    regions=[]
    for i,a in enumerate(group):
        pos=[i%cols*cell[0],i//cols*cell[1]]
        sprite=Image.open(ROOT/a['path'])
        atlas.alpha_composite(sprite,pos)
        regions.append({'id':a['id'],'rect':pos+a['size'],'anchor':a['anchor']})
    atlaspath='textures/'+family+'-atlas.png'
    atlas.save(ROOT/atlaspath)
    manifest['atlases'].append({'id':family,'path':atlaspath,'size':list(atlas.size),'cellSize':cell,'regions':regions})
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ROOT/'extraction.json').write_text(json.dumps(extractions,indent=2)+'\n')

font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',16)
small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',13)
# Contact sheet uses only mechanical placement and nearest-neighbor enlargement.
cw,ch,cols=224,220,5
contact=Image.new('RGB',(cols*cw,60+math.ceil(len(assets)/cols)*ch),'#1c2228');d=ImageDraw.Draw(contact)
d.text((20,15),'simplyZOMBIES | TERRAIN + ARCHITECTURE | 33 native assets',font=font,fill='#ede6d6')
for i,a in enumerate(assets):
    x,y=(i%cols)*cw,60+(i//cols)*ch
    d.rectangle((x+5,y+5,x+cw-5,y+ch-5),fill='#313942')
    im=Image.open(ROOT/a['path']);scale=2 if max(im.size)>32 else 4
    im=im.resize((im.width*scale,im.height*scale),NN)
    contact.paste(im,(x+(cw-im.width)//2,y+12),im)
    d.text((x+12,y+170),a['label'],font=small,fill='#e5e0d5')
    d.text((x+12,y+190),f"{a['size'][0]}x{a['size'][1]} | pivot {a['anchor']}",font=small,fill='#b5bfc5')
contact.save(ROOT/'previews/environment-contact.png')
repeat=Image.new('RGB',(4*280,3*310),'#1c2228');d=ImageDraw.Draw(repeat)
stats=[]
for i,a in enumerate(assets[:12]):
    im=Image.open(ROOT/a['path']).convert('RGB');panel=Image.new('RGB',(64,64))
    for yy in [0,32]:
        for xx in [0,32]:panel.paste(im,(xx,yy))
    x,y=(i%4)*280,(i//4)*310;repeat.paste(panel.resize((256,256),NN),(x+12,y+12));d.text((x+12,y+276),a['label'],font=small,fill='#e5e0d5')
    p=im.load();diff=lambda a,b:sum(abs(a[k]-b[k]) for k in range(3))/3
    seam=statistics.mean([diff(p[0,j],p[31,j]) for j in range(32)]+[diff(p[j,0],p[j,31]) for j in range(32)])
    interior=statistics.mean([diff(p[x,y],p[x+1,y]) for y in range(32) for x in range(31)]+[diff(p[x,y],p[x,y+1]) for y in range(31) for x in range(32)])
    stats.append({'id':a['id'],'meanWrappedEdgeRgbDifference':round(seam,2),'meanInteriorNeighborRgbDifference':round(interior,2)})
repeat.save(ROOT/'previews/terrain-repeat-2x2.png')
(ROOT/'previews/terrain-repeat-stats.json').write_text(json.dumps(stats,indent=2)+'\n')
stateframes=[]
for state in [0,1]:
    frame=Image.new('RGB',(840,320),'#1c2228');d=ImageDraw.Draw(frame)
    d.text((20,16),'INTERACTION STATES | sprite switches, not tweened motion',font=font,fill='#ede6d6')
    for j,pair in enumerate([['door-closed','door-open'],['window-intact','window-broken'],['gate-closed','gate-open']]):
        a=next(a for a in assets if a['id']=='wall-'+pair[state])
        im=Image.open(ROOT/a['path']).resize((256,192),NN)
        frame.paste(im,(j*280+12,70),im)
        d.text((j*280+12,285),a['label'],font=font,fill='#e5e0d5')
    stateframes.append(frame)
stateframes[0].save(ROOT/'previews/architecture-states.gif',save_all=True,append_images=stateframes[1:],duration=1000,loop=0)
validation=[]
for a in assets:
    im=Image.open(ROOT/a['path']).convert('RGBA');alpha=list(im.getchannel('A').getdata())
    assert list(im.size)==a['size']
    assert im.getbbox() is not None
    validation.append({'id':a['id'],'sizeMatches':True,'nonempty':True,'transparentPixels':sum(v==0 for v in alpha),'fractionalAlphaPixels':sum(0<v<255 for v in alpha)})
(ROOT/'previews/validation.json').write_text(json.dumps({'assetCount':len(assets),'opaqueTerrainCount':12,'transparentArchitectureAndOverlays':21,'checks':validation},indent=2)+'\n')
print(json.dumps({'assets':len(assets),'manifest':str(ROOT/'manifest.json'),'repeatStats':stats},indent=2))
