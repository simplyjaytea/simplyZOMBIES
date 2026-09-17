const fs=require('fs');const path=require('path');const{createCanvas,loadImage}=require('@napi-rs/canvas');
const ROOT=__dirname;const manifest=require('./manifest.json');
async function main(){
 const imgs={};for(const a of manifest.assets){for(const f of a.frames?Object.values(a.frames)[0]:[{path:a.path}])imgs[f.path]=await loadImage(path.join(ROOT,f.path));}
 const W=1100,H=850,canvas=createCanvas(W,H),ctx=canvas.getContext('2d');ctx.imageSmoothingEnabled=false;
 ctx.fillStyle='#111917';ctx.fillRect(0,0,W,H);ctx.fillStyle='#e7dfbc';ctx.font='bold 25px sans-serif';ctx.fillText('SIMPLY ZOMBIES · PIXEL EFFECTS',30,40);ctx.fillStyle='#84988e';ctx.font='14px sans-serif';ctx.fillText('Native frames shown at 3× · Transparent artwork · 12 effects / 48 frames / 8 decals',30,65);
 manifest.assets.slice(0,12).forEach((a,i)=>{const col=i%3,row=Math.floor(i/3),x=30+col*360,y=90+row*155;ctx.fillStyle='#192520';ctx.fillRect(x,y,340,144);ctx.fillStyle='#d7d9c2';ctx.font='bold 15px sans-serif';ctx.fillText(a.label,x+12,y+22);const frames=Object.values(a.frames)[0];frames.forEach((f,k)=>{const im=imgs[f.path];const scale=Math.min(3,70/a.size[0],105/a.size[1]);const dw=a.size[0]*scale,dh=a.size[1]*scale;ctx.drawImage(im,x+9+k*82+(70-dw)/2,y+32+(104-dh)/2,dw,dh);});});
 ctx.fillStyle='#d7d9c2';ctx.font='bold 15px sans-serif';ctx.fillText('GROUND DECALS',30,743);manifest.assets.slice(12).forEach((a,i)=>{ctx.drawImage(imgs[a.path],34+i*131,755,64,64);ctx.fillStyle='#91a89b';ctx.font='11px sans-serif';ctx.fillText(a.label,30+i*131,838);});
 fs.writeFileSync(path.join(ROOT,'previews/effects-contact.png'),canvas.toBuffer('image/png'));
 fs.mkdirSync(path.join(ROOT,'previews/timeline'),{recursive:true});
 const duration=2,step=1/24;
 for(let index=0;index<duration/step;index++){
  const t=index*step,c=createCanvas(960,640),cctx=c.getContext('2d');cctx.imageSmoothingEnabled=false;cctx.fillStyle='#111917';cctx.fillRect(0,0,960,640);cctx.fillStyle='#e7dfbc';cctx.font='bold 22px sans-serif';cctx.fillText('SIMPLY ZOMBIES · EFFECTS IN MOTION',25,36);cctx.fillStyle='#84988e';cctx.font='13px sans-serif';cctx.fillText('One-shots restart every second · Flame / smoke run continuously',25,59);
  manifest.assets.slice(0,12).forEach((a,i)=>{const x=20+(i%4)*237,y=82+Math.floor(i/4)*182;cctx.fillStyle='#1b2823';cctx.fillRect(x,y,223,170);cctx.fillStyle='#c7d5ca';cctx.font='bold 14px sans-serif';cctx.fillText(a.label,x+10,y+23);const fs=Object.values(a.frames)[0],frame=a.loop?Math.floor(t*a.fps)%4:Math.floor((t%1)*a.fps);if(frame>=4)return;const im=imgs[fs[frame].path],s=Math.min(3,120/a.size[1]);const cx=x+112,cy=y+137;cctx.drawImage(im,cx-a.anchor[0]*s,cy-a.anchor[1]*s,a.size[0]*s,a.size[1]*s);});
  fs.writeFileSync(path.join(ROOT,'previews/timeline',String(index).padStart(3,'0')+'.png'),c.toBuffer('image/png'));
 }
 console.log('Contact sheet and 48 preview frames saved.');
}
main().catch(e=>{console.error(e);process.exit(1)});
