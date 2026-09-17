from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
root=Path(__file__).resolve().parent;m=json.loads((root/'manifest.json').read_text());(root/'atlases').mkdir(exist_ok=True)
atlases=[]
for kind,aid,state in [('generator','utility-generator-on','running'),('worklamp','utility-worklamp-activation','activate')]:
 a=next(a for a in m['assets'] if a['id']==aid);ims=[Image.open(root/f['path']) for f in a['frames'][state]];out=Image.new('RGBA',(160,48))
 for i,im in enumerate(ims):out.alpha_composite(im,(i*40,0))
 path='atlases/utility-'+kind+'.png';out.save(root/path);atlases.append(dict(id=kind,path=path,cellSize=[40,48],grid=[4,1],assetId=aid,state=state,fps=a['fps'],loop=a['loop']))
ui=[a for a in m['assets'] if a['category']=='ui'];out=Image.new('RGBA',(64,64))
for i,a in enumerate(ui):out.alpha_composite(Image.open(root/a['path']),((i%4)*16,(i//4)*16))
out.save(root/'atlases/ui-icons.png');atlases.append(dict(id='ui-icons',path='atlases/ui-icons.png',cellSize=[16,16],grid=[4,4],order=[a['id'] for a in ui]))
m['atlases']=atlases;(root/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
# Show all animation frames at once for visual inspection.
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',14)
out=Image.new('RGB',(1040,690),'#253132');d=ImageDraw.Draw(out);d.text((16,12),'UTILITY ANIMATION FRAMES | locked ground pivots',font=font,fill='#eee6d4')
for r,kind in enumerate(['generator','worklamp']):
 for c in range(4):
  im=Image.open(root/f'frames/utility-{kind}-{c:02d}.png').resize((240,288),Image.Resampling.NEAREST);out.paste(im,(10+c*260,48+r*320),im);d.text((12+c*260,48+r*320+292),f'{kind} / frame {c+1}',font=font,fill='#eee6d4')
out.save(root/'previews/animation-frames-contact.png')
