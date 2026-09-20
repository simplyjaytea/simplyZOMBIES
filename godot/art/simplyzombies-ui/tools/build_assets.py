"""Reproducible authorized alpha cleanup and nearest-neighbor asset export.
Requires Python 3, Pillow, NumPy and SciPy. Run from any directory.
Source art stays unchanged. No source code from the game is required.
"""
from pathlib import Path
import json, math, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT
LAYOUT = json.loads((ROOT / 'docs/source-layout.json').read_text())
NEAREST = Image.Resampling.NEAREST
entries, sprites, extraction = [], [], {}

def write_json(path, obj):
    path.write_text(json.dumps(obj, indent=2) + '\n')

def clean(name):
    rgb = np.array(Image.open(ROOT / 'sources' / (name+'.png')).convert('RGB'))
    v = rgb.astype(np.int16)
    # Neutral checkerboard is bright; artwork is dark, or warm/olive chromatic.
    mask = (v.max(2) < 85) | ((np.ptp(v, axis=2) > 20) & (v[:,:,0] >= v[:,:,2]) & (v[:,:,1] >= v[:,:,2]))
    labels, n = ndimage.label(mask)
    sizes = np.bincount(labels.ravel())
    keep = sizes >= 48
    keep[0] = False
    mask = keep[labels]
    rgba = np.dstack([rgb, mask.astype('uint8')*255])
    rgba[~mask,:3] = 0
    result = Image.fromarray(rgba)
    result.save(ROOT / 'sources' / (name+'-rgba.png'))
    return result

def cell(im, spec, index):
    cols = spec['columns']
    row, col = divmod(index, cols)
    ys = spec.get('row_boundaries', [round(i*im.height/spec.get('rows',4)) for i in range(spec.get('rows',4)+1)])
    bounds = (round(col*im.width/cols), ys[row], round((col+1)*im.width/cols), ys[row+1])
    cropped = im.crop(bounds)
    box = cropped.getbbox()
    if box is None: raise ValueError((index, bounds))
    return cropped.crop(box), [bounds[0]+box[0], bounds[1]+box[1], bounds[0]+box[2], bounds[1]+box[3]]

def fit(im, size, padding=1, stretch=False):
    w,h = size
    if stretch:
        out_size = (w-2*padding,h-2*padding)
    else:
        ratio = min((w-2*padding)/im.width,(h-2*padding)/im.height)
        out_size = (max(1,round(im.width*ratio)),max(1,round(im.height*ratio)))
    im = im.resize(out_size, NEAREST)
    out = Image.new('RGBA',(w,h))
    out.alpha_composite(im,((w-im.width)//2,(h-im.height)//2))
    return out

def save_sprite(id, im, folder, **meta):
    path = ART/folder/(id+'.png')
    path.parent.mkdir(parents=True,exist_ok=True)
    im.save(path)
    d = {'id':id,'path':str(path.relative_to(ART)), 'size':list(im.size), **meta}
    sprites.append(d)
    return d

for sheet in ['chrome','glyphs','controls']:
    spec = LAYOUT['sheets'][sheet]
    im = clean(sheet)
    extraction[sheet] = []
    for i,a in enumerate(spec['assets']):
        crop, rect = cell(im,spec,i)
        id = ('control_' if sheet=='controls' else '')+a['id']
        size = a['size']
        pad = 2 if sheet=='glyphs' else 1
        native = fit(crop,size,pad,stretch=sheet=='chrome')
        folder = {'chrome':'textures','glyphs':'glyphs','controls':'controls'}[sheet]
        d = save_sprite(id,native,folder,category=sheet)
        extraction[sheet].append({'id':id,'rect_xyxy':rect,'padding':pad,'stretch':sheet=='chrome'})
        if sheet=='chrome':
            margin = [6,6,6,6]
            if id.startswith('panel_'): margin = [12,12,12,12] if id=='panel_dialog' else [10,10,10,10]
            elif id=='divider': margin = [2,0,2,0]
            elif id=='scroll_track': margin = [3,6,3,6]
            elif id.startswith('button_'): margin = [9,6,9,6]
            elif id.startswith('tab_'): margin = [6,5,6,5]
            elif id=='keycap': margin = [5,5,5,5]
            d['nine_slice_ltrb']=margin
        if sheet=='glyphs':
            alt = save_sprite(id+'_small',fit(crop,[16,16],1),'glyphs/small',category='glyph_variant',variant_of=id)
            d['small_path']=alt['path']
        if id.startswith('control_cursor_'):
            d['hotspot']={'control_cursor_arrow':[6,2],'control_cursor_hand':[9,2],'control_cursor_move':[12,12],'control_cursor_blocked':[12,12]}[id]
        entries.append(d)

im = clean('motion')
spec=LAYOUT['sheets']['motion']
extraction['motion']=[]
for row,a in enumerate(spec['animations']):
    crops=[]
    bounds=[]
    for col in range(4):
        crop,rect=cell(im,spec,row*4+col)
        crops.append(crop);bounds.append(rect)
    # Focus and ping use their geometric centers. Busy turns around the cream dot.
    # Saved tick uses its stroke's start so drawing the mark does not recenter it.
    anchors=[]
    for col,rect in enumerate(bounds):
        if row in (0,2): anchor=[(rect[0]+rect[2])/2,(rect[1]+rect[3])/2]
        elif row==1: anchor=[[185,461],[483,518],[772,518],[1074,462]][col]
        else: anchor=[[180,1084],[482,1112],[785,1100],[1098,1100]][col]
        anchors.append(anchor)
    rels=[[r[0]-p[0],r[1]-p[1],r[2]-p[0],r[3]-p[1]] for r,p in zip(bounds,anchors)]
    left=math.floor(min(r[0] for r in rels)); top=math.floor(min(r[1] for r in rels))
    right=math.ceil(max(r[2] for r in rels)); bottom=math.ceil(max(r[3] for r in rels))
    sw,sh=right-left,bottom-top
    w,h=a['size'];ratio=min((w-4)/sw,(h-4)/sh)
    scaled=(max(1,round(sw*ratio)),max(1,round(sh*ratio)))
    frames=[]
    for col,(crop,r) in enumerate(zip(crops,rels)):
        canvas=Image.new('RGBA',(sw,sh))
        canvas.alpha_composite(crop,(round(r[0]-left),round(r[1]-top)))
        small=canvas.resize(scaled,NEAREST)
        native=Image.new('RGBA',(w,h))
        native.alpha_composite(small,((w-scaled[0])//2,(h-scaled[1])//2))
        d=save_sprite(a['id']+'_'+str(col),native,'animations',category='animation_frame',animation=a['id'],frame=col)
        frames.append(d['path'])
    entry={'id':a['id'],'category':'animation','size':a['size'],'frames':frames,'fps':a['fps'],'loop':a['loop'],'reduced_motion_frame':2 if row==3 else 0}
    entries.append(entry)
    extraction['motion'].append({'id':a['id'],'source_rects_xyxy':bounds,'anchors_xy':anchors,'shared_bounds_ltrb':[left,top,right,bottom]})

# Shelf-packed, exact pixel atlas. Two transparent pixels separate all sprites.
atlas=Image.new('RGBA',(512,512))
x=y=2;row_h=0;regions={}
for s in sorted(sprites,key=lambda s:(-s['size'][1],-s['size'][0],s['id'])):
    w,h=s['size']
    if x+w+2>512: x=2;y+=row_h+4;row_h=0
    assert y+h+2<=512
    atlas.alpha_composite(Image.open(ART/s['path']),(x,y))
    regions[s['id']]={'rect':[x,y,w,h],'path':s['path']}
    x+=w+4;row_h=max(row_h,h)
atlas.save(ART/'atlas.png')
write_json(ART/'atlas.json',{'image':'atlas.png','size':[512,512],'gutter':2,'sprites':regions})
manifest={'name':'simplyZOMBIES UI','version':'1.0.0','resource_root':'res://art/simplyzombies-ui/','pixel_filter':'nearest','alpha':'binary RGBA; transparent pixels have zero RGB','palette':{'background':'#10130e','panel':'#141810','edge':'#3c422c','text':'#c8c2a6','muted':'#807a63','focus':'#c99a3f','danger':'#b5502f'},'counts':{'logical_assets':len(entries),'native_pngs':len(sprites),'glyph_variants':32,'animation_frames':16},'assets':entries,'sprites':sprites}
write_json(ART/'manifest.json',manifest)
write_json(ROOT/'docs/extraction.json',{'mask':'Keep max(RGB)<85 OR (chroma>20 AND R>=B AND G>=B); remove connected components smaller than 48 source pixels. Binary alpha. Zero transparent RGB.','resampling':'nearest','sheets':extraction})
LAYOUT['status']='Complete: native RGBA exports, atlas and Godot resources.'
LAYOUT.pop('pending',None)
for a in LAYOUT['sheets']['chrome']['assets']:
    a['nine_slice']=next(e['nine_slice_ltrb'] for e in entries if e['id']==a['id'])
write_json(ROOT/'docs/source-layout.json',LAYOUT)

# Every chrome texture also has a nine-slice StyleBoxTexture resource.
for e in entries:
    if e['category']!='chrome':continue
    l,t,r,b=e['nine_slice_ltrb']
    content=[max(l,8),max(t,8),max(r,8),max(b,8)]
    text='[gd_resource type="StyleBoxTexture" load_steps=2 format=3]\n\n'
    text+=f'[ext_resource type="Texture2D" path="res://art/simplyzombies-ui/{e["path"]}" id="1"]\n\n[resource]\ntexture = ExtResource("1")\n'
    for edge,value in zip(['left','top','right','bottom'],[l,t,r,b]): text+=f'texture_margin_{edge} = {float(value)}\n'
    for edge,value in zip(['left','top','right','bottom'],content): text+=f'content_margin_{edge} = {float(value)}\n'
    (ART/'styles'/(e['id']+'.tres')).write_text(text)

for e in entries:
    if e['category']!='animation':continue
    text='[gd_resource type="SpriteFrames" load_steps=5 format=3]\n\n'
    for i,path in enumerate(e['frames']): text+=f'[ext_resource type="Texture2D" path="res://art/simplyzombies-ui/{path}" id="{i+1}"]\n'
    frames=',\n'.join('{"duration": 1.0, "texture": ExtResource("'+str(i+1)+'")}' for i in range(4))
    text+='\n[resource]\nanimations = [{\n"frames": ['+frames+'],\n"loop": '+str(e['loop']).lower()+',\n"name": &"'+e['id']+'",\n"speed": '+str(float(e['fps']))+'\n}]\n'
    (ART/'animations'/(e['id']+'.tres')).write_text(text)

# Catalog uses actual native exports, magnified with nearest neighbor.
font=ImageFont.truetype(str(ART/'fonts/VT323-Regular.ttf'),24)
large=ImageFont.truetype(str(ART/'fonts/VT323-Regular.ttf'),42)
small_font=ImageFont.truetype(str(ART/'fonts/VT323-Regular.ttf'),18)
catalog=Image.new('RGB',(1440,1520),'#10130e'); draw=ImageDraw.Draw(catalog)
draw.text((40,25),'simplyZOMBIES  /  UI FIELD KIT',font=large,fill='#c8c2a6')
draw.text((40,72),'NATIVE PIXELS  ·  TRANSPARENT EXPORTS  ·  LIVE TEXT  ·  GODOT RESOURCES',font=font,fill='#9a9278')
def section(title,items,y,columns,cell_w,cell_h,scale):
    draw.text((40,y),title,font=font,fill='#c99a3f'); y+=38
    for i,e in enumerate(items):
        xx=40+(i%columns)*cell_w;yy=y+(i//columns)*cell_h
        im=Image.open(ART/e['path'])
        maxw=cell_w-14; maxh=cell_h-35
        sc=min(scale,maxw//im.width,maxh//im.height)
        big=im.resize((im.width*sc,im.height*sc),NEAREST)
        catalog.paste(big,(xx+(cell_w-14-big.width)//2,yy+(maxh-big.height)//2),big)
        label=e['id'].replace('glyph_','').replace('control_','').replace('button_','btn ').replace('panel_','panel ').replace('slot_','slot ')
        draw.text((xx,yy+maxh+4),label,font=small_font if cell_w<180 else font,fill='#9a9278')
    return y+math.ceil(len(items)/columns)*cell_h
y=section('01  /  FRAMEWORK & STATES',[e for e in entries if e['category']=='chrome'],115,6,226,150,3)
y=section('02  /  EQUIPMENT & ACTION GLYPHS',[e for e in entries if e['category']=='glyphs'],y+15,16,85,95,2)
y=section('03  /  SETTINGS & CURSORS',[e for e in entries if e['category']=='controls'],y+15,8,169,116,2)
draw.text((40,y+15),'04  /  MOTION   —   focus pulse  /  busy  /  item ping  /  saved tick',font=font,fill='#c99a3f')
for row,e in enumerate(e for e in entries if e['category']=='animation'):
    for col,p in enumerate(e['frames']):
        im=Image.open(ART/p);im=im.resize((im.width*2,im.height*2),NEAREST)
        catalog.paste(im,(40+row*340+col*74,y+50),im)
catalog=catalog.crop((0,0,1440,y+135))
catalog.save(ROOT/'previews/simplyzombies-ui-catalog.png')
print(json.dumps({'counts':manifest['counts'],'atlas':[512,512],'catalog':list(catalog.size)}))
