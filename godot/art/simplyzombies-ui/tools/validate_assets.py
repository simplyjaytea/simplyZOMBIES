"""Validate transparency, atlas correspondence and pixel export metadata."""
from pathlib import Path
from PIL import Image
import numpy as np
import json, hashlib

root=Path(__file__).resolve().parents[1]
art=root
manifest=json.loads((art/'manifest.json').read_text())
atlas_meta=json.loads((art/'atlas.json').read_text())
atlas=Image.open(art/'atlas.png')
checks=[]
def check(condition,name):
    assert condition,name
    checks.append(name)
check(len({a['id'] for a in manifest['assets']})==76,'76 unique logical IDs')
check(len({s['id'] for s in manifest['sprites']})==120,'120 unique native PNG IDs')
occupancy=np.zeros(atlas.size[::-1],dtype=np.uint8)
for s in manifest['sprites']:
    im=Image.open(art/s['path']);a=np.asarray(im)
    check(im.mode=='RGBA','RGBA: '+s['id'])
    check(list(im.size)==s['size'],'Dimensions: '+s['id'])
    check(set(np.unique(a[:,:,3]))=={0,255},'Real binary transparency: '+s['id'])
    check(np.all(a[a[:,:,3]==0,:3]==0),'Zero RGB outside alpha: '+s['id'])
    rgb=a[:,:,:3].astype(int);opaque=a[:,:,3]>0
    background=(rgb.max(2)>=85)&(np.ptp(rgb,axis=2)<=20)
    check(not np.any(background&opaque),'No neutral checkerboard pixels: '+s['id'])
    x,y,w,h=atlas_meta['sprites'][s['id']]['rect']
    check(0<=x<x+w<=atlas.width and 0<=y<y+h<=atlas.height,'Atlas bounds: '+s['id'])
    check(not np.any(occupancy[y:y+h,x:x+w]),'Unique atlas region: '+s['id'])
    occupancy[y:y+h,x:x+w]=1
    check(np.array_equal(np.asarray(atlas.crop((x,y,x+w,y+h))),a),'Exact atlas pixels: '+s['id'])
for a in manifest['assets']:
    if a['category']=='animation':
        hashes={hashlib.sha256(Image.open(art/p).tobytes()).hexdigest() for p in a['frames']}
        check(len(hashes)==4,'Distinct frames: '+a['id'])
        check(all(list(Image.open(art/p).size)==a['size'] for p in a['frames']),'Shared canvas: '+a['id'])
    if 'nine_slice_ltrb' in a:
        l,t,r,b=a['nine_slice_ltrb'];w,h=a['size']
        check(l+r<w and t+b<h,'Positive nine-slice center: '+a['id'])
    if 'hotspot' in a:
        im=Image.open(art/a['path'])
        check(im.getpixel(tuple(a['hotspot']))[3]==255,'Cursor hotspot on opaque pixel: '+a['id'])
report={'result':'PASS','native_pngs':120,'logical_assets':76,'atlas_size':list(atlas.size),'checks_passed':len(checks),'checks':checks}
(root/'docs/asset-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='checks'}))
