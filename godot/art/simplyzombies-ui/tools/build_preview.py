from pathlib import Path
import base64, json

root=Path(__file__).resolve().parents[1]
art=root
manifest=json.loads((art/'manifest.json').read_text())
def data(path,mime='image/png'):
    return 'data:'+mime+';base64,'+base64.b64encode(path.read_bytes()).decode()
images={s['id']:data(art/s['path']) for s in manifest['sprites']}
images.update({p.stem:data(p) for p in (root/'demo-assets').glob('*.png')})
font=data(art/'fonts/VT323-Regular.ttf','font/ttf')
code=(root/'tools/viewer.cjs').read_text()
html='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>simplyZOMBIES · UI Field Kit</title>
<style>@font-face{font-family:FieldPixel;src:url(FONT_DATA)}*{box-sizing:border-box}html,body{margin:0;background:#080b07;color:#9a9278}body{font:20px FieldPixel,monospace}main{min-width:960px;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px 0}canvas{display:block;width:960px;height:600px;image-rendering:pixelated;outline:none;border:1px solid #272e1b}canvas:focus-visible{outline:1px solid #c99a3f}p{margin:14px 20px;max-width:920px;font-size:18px}span{color:#c8c2a6}@media(min-width:1940px){canvas{width:1920px;height:1200px}}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}</style>
<main><canvas id="kit" width="960" height="600" tabindex="0" aria-label="Interactive simplyZOMBIES UI asset preview. Tab moves between controls. Enter activates. Escape opens the pause screen."></canvas><p><span>ASSET PREVIEW</span> · Click to inspect. Tab + Enter to navigate. Escape to pause. Controls are demonstrations; they do not alter the game.</p><p id="loading" role="status">Loading textures…</p></main>
<script>const MANIFEST=MANIFEST_DATA;const SOURCES=IMAGE_DATA;
VIEWER_CODE
(async()=>{try{
 const font=new FontFace('FieldPixel','url(FONT_DATA)');await font.load();document.fonts.add(font);await document.fonts.ready;
 const images={};await Promise.all(Object.entries(SOURCES).map(([k,src])=>new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>{images[k]=im;resolve();};im.onerror=reject;im.src=src;})));
 const canvas=document.getElementById('kit'),ui=new UIFieldKit(canvas,images,MANIFEST);window.uiFieldKit=ui;
 ui.reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
 const point=e=>{const r=canvas.getBoundingClientRect();return [(e.clientX-r.left)*960/r.width,(e.clientY-r.top)*600/r.height];};
 canvas.addEventListener('pointermove',e=>{const [x,y]=point(e);ui.hover=ui.point(x,y);canvas.style.cursor=ui.hover>=0?'pointer':'default';});
 canvas.addEventListener('pointerleave',()=>{ui.hover=-1;ui.down=false;});
 canvas.addEventListener('pointerdown',()=>{ui.down=true;canvas.focus();});
 window.addEventListener('pointerup',()=>{ui.down=false;});canvas.addEventListener('click',e=>ui.click(...point(e)));
 canvas.addEventListener('keydown',e=>{if(ui.key(e.key,e.shiftKey))e.preventDefault();});
 let start;function frame(t){if(start===undefined)start=t;ui.draw(t-start);requestAnimationFrame(frame);}requestAnimationFrame(frame);
 document.getElementById('loading').textContent='76 assets · 120 PNG exports · 4 animations · nearest-neighbor pixels';
 }catch(error){document.getElementById('loading').textContent='Could not load the preview. Please reopen the file in a modern browser.';console.error(error);}})();
</script></html>'''
html=html.replace('FONT_DATA',font).replace('MANIFEST_DATA',json.dumps(manifest,separators=(',',':'))).replace('IMAGE_DATA',json.dumps(images,separators=(',',':'))).replace('VIEWER_CODE',code)
(root/'simplyzombies-ui-preview.html').write_text(html)
print('Built self-contained preview:',len(html),'bytes')
