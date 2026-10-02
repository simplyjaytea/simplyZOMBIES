#!/usr/bin/env python3
"""Mechanical crop, alignment, nearest-neighbor export, and review composition.

Requires Pillow, numpy, scipy. No pixels are painted, recolored, or background-masked.
The alpha threshold is used ONLY to locate bounds; original RGBA pixels are retained.
Run from this directory after sources/index.json exists: python build_pack.py
"""
from pathlib import Path
import json, math, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

ROOT=Path(__file__).resolve().parent
ORDER=['workwear','commuter','raincoat','stalker','runner','armored','heavy']
DIRS=['south','east','north','west']
FPS=dict(workwear=5,commuter=5,raincoat=5,stalker=6,runner=9,armored=4,heavy=4)
LABELS=dict(workwear='Workwear',commuter='Commuter',raincoat='Raincoat',stalker='Stalker',runner='Runner',armored='Armored',heavy='Heavy')
TARGET_HEIGHT=dict.fromkeys(ORDER,28); TARGET_HEIGHT['heavy']=34
SIZES={k:(32,40) for k in ORDER}; SIZES['heavy']=(40,48)
PIVOTS={k:(16,40) for k in ORDER}; PIVOTS['heavy']=(20,48)
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BG=(26,33,32,255); INK=(223,223,204,255); MUTED=(153,165,156,255)

def components(im,min_area):
    lab,n=ndimage.label(np.array(im.getchannel('A'))>=128)
    out=[]
    for i,sl in enumerate(ndimage.find_objects(lab)):
        if sl is None: continue
        if np.count_nonzero(lab[sl]==i+1)>=min_area:
            out.append((sl[1].start,sl[0].start,sl[1].stop,sl[0].stop))
    return out

def pad_bounds(b,size,pad=2):
    return (max(0,b[0]-pad),max(0,b[1]-pad),min(size[0],b[2]+pad),min(size[1],b[3]+pad))

def save(im,path):
    dest=ROOT/path; dest.parent.mkdir(parents=True,exist_ok=True); im.save(dest)
    return str(path)

def head_x(im,b):
    a=np.array(im.getchannel('A')); h=b[3]-b[1]
    band=a[b[1]+round(.08*h):b[1]+round(.28*h),b[0]:b[2]]>=128
    return float(np.median(np.nonzero(band)[1]))+b[0]

def font(sz): return ImageFont.truetype(FONT,sz)
def label(draw,xy,txt,sz=17,fill=INK): draw.text(xy,txt,font=font(sz),fill=fill)
def place(frame,sprite,xy,scale=4):
    spr=sprite.resize((sprite.width*scale,sprite.height*scale),Image.Resampling.NEAREST)
    frame.alpha_composite(spr,xy)

def main():
    index=json.loads((ROOT/'sources/index.json').read_text())
    assets=[]; extraction=[]; review={}; atlas_info=[]; qa=[]
    for key in ORDER:
        rec=index[key]; im=Image.open(ROOT/rec['animation']).convert('RGBA')
        boxes=components(im,2000)
        assert len(boxes)==20,(key,len(boxes))
        boxes=sorted(boxes,key=lambda b:(b[1]+b[3])/2)
        rows=[sorted(boxes[r*5:r*5+5],key=lambda b:b[0]) for r in range(4)]
        heights=[b[3]-b[1] for b in boxes]
        factor=TARGET_HEIGHT[key]/float(np.median(heights))
        size=SIZES[key]; pivot=PIVOTS[key]; review[key]={}
        atlas=Image.new('RGBA',(size[0]*5,size[1]*4))
        for r,(direction,row) in enumerate(zip(DIRS,rows)):
            # Match head's horizontal position to this direction's idle silhouette.
            idle_center=(row[0][0]+row[0][2])/2
            head_offset=(head_x(im,row[0])-idle_center)*factor
            frame_records=[]; native=[]
            for col,b in enumerate(row):
                cropbox=pad_bounds(b,im.size)
                crop=im.crop(cropbox)
                scaled=crop.resize((max(1,round(crop.width*factor)),max(1,round(crop.height*factor))),Image.Resampling.NEAREST)
                effective_x=scaled.width/crop.width; effective_y=scaled.height/crop.height
                px=round(pivot[0]+head_offset-(head_x(im,b)-cropbox[0])*effective_x)
                py=round(pivot[1]-(b[3]-cropbox[1])*effective_y)
                canvas=Image.new('RGBA',size); canvas.alpha_composite(scaled,(px,py))
                state='idle' if col==0 else 'walk'; num=0 if col==0 else col-1
                path=f'textures/zombie-{key}/{state}-{direction}-{num:02d}.png'
                save(canvas,path); native.append(canvas)
                atlas.alpha_composite(canvas,(col*size[0],r*size[1]))
                frame_records.append({'path':path,'atlas_rect':[col*size[0],r*size[1],*size]})
                extraction.append({'path':path,'source':rec['animation'],'source_rect':list(cropbox),'source_body_rect':list(b),'scale':factor,'resized_size':list(scaled.size),'placement':[px,py],'alignment':'head x stabilized to idle; alpha>=128 body sole at foot boundary'})
                alpha=np.array(canvas.getchannel('A'))
                assert np.count_nonzero(alpha>=128)>50,path
                assert np.count_nonzero(alpha==0)>0,path
                assert not np.any(alpha[:,0]>=128) and not np.any(alpha[:,-1]>=128),('side clipping',path)
            assert len({n.tobytes() for n in native[1:]})==4,('duplicate walk frames',key,direction)
            # Differences after alpha bounding-box normalization catch translated duplicate poses.
            masks=[]
            for n in native[1:]:
                a=np.array(n.getchannel('A'))>=128; ys,xs=np.nonzero(a)
                masks.append(a[ys.min():ys.max()+1,xs.min():xs.max()+1].tobytes())
            assert len(set(masks))>1,('unchanged silhouette',key,direction)
            review[key][direction]=native
            for state,frames in [('idle',frame_records[:1]),('walk',frame_records[1:])]:
                assets.append({'id':f'zombie-{key}-{state}-{direction}','label':f'{LABELS[key]} {state} {direction}','category':'zombie','path':frames[0]['path'],'size':list(size),'anchor':list(pivot),'direction':direction,'state':state,'frames':{state:frames},'fps':1 if state=='idle' else FPS[key],'loop':state=='walk','status':'integrated-locomotion'})
            qa.append({'id':key,'direction':direction,'walk_distinct_rgba_frames':4,'walk_distinct_cropped_silhouettes':len(set(masks)),'heights_native':[n.getchannel('A').point(lambda x:255 if x>=128 else 0).getbbox()[3]-n.getchannel('A').point(lambda x:255 if x>=128 else 0).getbbox()[1] for n in native]})
        atlaspath=save(atlas,f'atlases/zombie-{key}.png')
        atlas_info.append({'id':f'zombie-{key}','path':atlaspath,'size':list(atlas.size),'cell_size':list(size),'rows':DIRS,'columns':['idle','walk-00','walk-01','walk-02','walk-03']})
        pose=Image.open(ROOT/rec['poses']).convert('RGBA')
        pb=sorted(components(pose,10000),key=lambda b:b[0]); assert len(pb)==3
        corpse_scale=TARGET_HEIGHT[key]/(pb[0][3]-pb[0][1])
        corpses=[]
        for b,name in zip(pb[1:],['supine','prone']):
            cropbox=pad_bounds(b,pose.size); crop=pose.crop(cropbox)
            scaled=crop.resize((round(crop.width*corpse_scale),round(crop.height*corpse_scale)),Image.Resampling.NEAREST)
            csize=(56,40) if key=='heavy' else (48,40)
            assert scaled.width<=csize[0] and scaled.height<=csize[1],(key,name,scaled.size)
            canvas=Image.new('RGBA',csize); xy=((csize[0]-scaled.width)//2,(csize[1]-scaled.height)//2); canvas.alpha_composite(scaled,xy)
            path=save(canvas,f'textures/zombie-{key}/corpse-{name}.png'); corpses.append(canvas)
            assets.append({'id':f'zombie-{key}-corpse-{name}','label':f'{LABELS[key]} corpse {name}','category':'corpse','path':path,'size':list(csize),'anchor':[csize[0]//2,csize[1]//2],'state':'corpse','pose':name,'frames':{'corpse':[{'path':path}]},'fps':0,'loop':False,'status':'integrated-corpse'})
            extraction.append({'path':path,'source':rec['poses'],'source_rect':list(cropbox),'scale':corpse_scale,'resized_size':list(scaled.size),'placement':list(xy)})
        review[key]['corpses']=corpses

    human=[]
    if 'human_corpses' in index:
        rec=index['human_corpses']; im=Image.open(ROOT/rec['poses']).convert('RGBA')
        boxes=components(im,10000); assert len(boxes)==4
        boxes=sorted(boxes,key=lambda b:(b[1]+b[3])/2)
        boxes=sorted(boxes[:2],key=lambda b:b[0])+sorted(boxes[2:],key=lambda b:b[0])
        factor=40/max(b[2]-b[0] for b in boxes)
        for b,name in zip(boxes,['supine','prone','side','supine-diagonal']):
            cropbox=pad_bounds(b,im.size); crop=im.crop(cropbox)
            scaled=crop.resize((round(crop.width*factor),round(crop.height*factor)),Image.Resampling.NEAREST)
            canvas=Image.new('RGBA',(48,40)); xy=((48-scaled.width)//2,(40-scaled.height)//2); canvas.alpha_composite(scaled,xy)
            path=save(canvas,f'textures/human/corpse-{name}.png'); human.append(canvas)
            assets.append({'id':f'human-corpse-{name}','label':f'Human corpse {name}','category':'corpse','path':path,'size':[48,40],'anchor':[24,20],'state':'corpse','pose':name,'frames':{'corpse':[{'path':path}]},'fps':0,'loop':False,'status':'integrated-corpse'})
            extraction.append({'path':path,'source':rec['poses'],'source_rect':list(cropbox),'scale':factor,'resized_size':list(scaled.size),'placement':list(xy)})

    # The manifest and native exports are the reusable deliverable.
    manifest={'schema_version':1,'title':'simplyZOMBIES - zombie animation and corpse study v1','date':'2026-10-02','status':'integrated; content-selected Godot sprites','tile_size':32,'sampling':'nearest','anchor_convention':'pixels from top-left; living anchor is bottom pixel boundary (sole row 39 or 47); corpse anchor is ground center','notes':['Idle is one pose in each direction, not a breathing loop.','Walk state is locomotion for all families, including the runner sprint.','No attack, hit, death-transition, or rise animations are included.','Armored base has no painted helmet or vest; live equipment uses the game gear renderer.','Heavy uses a 40x48 canvas; renderer and picking use its declared bounds.','Locomotion reads velocity and the simulation tick; per-family rates are checked by godot:check:zombie_art.','Sources preserve original partial alpha; no procedural background removal or color cleanup was applied.'],'atlases':atlas_info,'assets':assets}
    (ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (ROOT/'extraction.json').write_text(json.dumps(extraction,indent=2)+'\n')
    (ROOT/'qa.json').write_text(json.dumps(qa,indent=2)+'\n')

    # Static contact sheet at integer enlargement, on two practical game mattes.
    cardw=294; cardh=370; contact=Image.new('RGBA',(cardw*4,cardh*2),BG); dr=ImageDraw.Draw(contact)
    for i,key in enumerate(ORDER):
        x=(i%4)*cardw; y=(i//4)*cardh
        dr.rectangle((x+6,y+6,x+cardw-6,y+cardh-6),fill=(34,43,40,255),outline=(64,76,64,255))
        label(dr,(x+16,y+16),LABELS[key],23)
        label(dr,(x+16,y+46),f'{FPS[key]} fps | S / E / N / W',14,MUTED)
        for j,d in enumerate(DIRS):
            spr=review[key][d][0]; place(contact,spr,(x+12+j*69,y+76),2)
        label(dr,(x+16,y+181),'SUPINE / PRONE',13,MUTED)
        for j,spr in enumerate(review[key]['corpses']):
            place(contact,spr,(x+12+j*139,y+208),2)
        label(dr,(x+16,y+335),'40x48 heavy' if key=='heavy' else '32x40 living frames',13,MUTED)
    x=3*cardw; y=cardh
    label(dr,(x+20,y+30),'Human corpses',21)
    label(dr,(x+20,y+61),'4 fallen poses',14,MUTED)
    for i,spr in enumerate(human): place(contact,spr,(x+10+(i%2)*138,y+106+(i//2)*103),2)
    label(dr,(x+20,y+335),'Review draft - not in game',13,MUTED)
    save(contact,'previews/contact-sheet.png')

    # Real looping previews: all four directions animate together, each variant at its own FPS.
    W,H=1160,560; previews=[]
    for tick in range(100):
        t=tick*.04; panel=Image.new('RGBA',(W,H),BG); d=ImageDraw.Draw(panel)
        label(d,(24,12),'simplyZOMBIES | locomotion study',23)
        label(d,(24,43),'Native pixels enlarged 3x. Review draft; idle + corpse poses are in the pack.',14,MUTED)
        for r,direction in enumerate(DIRS): label(d,(16,107+r*108),direction[0].upper(),19,MUTED)
        for col,key in enumerate(ORDER):
            x=52+col*156
            label(d,(x,78),LABELS[key],16)
            for r,direction in enumerate(DIRS):
                spr=review[key][direction][1+math.floor(t*FPS[key])%4]
                cell_y=100+r*108
                # Ground line helps expose sliding and pivot errors.
                base=cell_y+99
                d.line((x+6,base,x+136,base),fill=(64,74,64,255))
                place(panel,spr,(x+65-spr.width*3//2,base-spr.height*3),3)
        previews.append(panel.convert('RGB'))
    target=ROOT/'previews/zombie-walks.gif'; target.parent.mkdir(exist_ok=True)
    previews[0].save(target,save_all=True,append_images=previews[1:],duration=40,loop=0,optimize=False,disposal=2)
    # APNG preserves alpha/color precisely; GIF is for convenient review.
    previews[0].save(ROOT/'previews/zombie-walks.png',save_all=True,append_images=previews[1:],duration=40,loop=0)
    # Four sequential phases together allow static visual inspection as well.
    strip=Image.new('RGBA',(W,H*4),BG)
    for i in range(4): strip.alpha_composite(previews[i*5].convert('RGBA'),(0,H*i))
    save(strip,'previews/motion-contact.png')
    print(json.dumps({'native_living_frames':140,'zombie_corpse_poses':14,'human_corpse_poses':len(human),'animation_groups':28,'assets':len(assets),'review_gif':str(target)}))

if __name__=='__main__': main()
