const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const crypto=require('crypto');
const ROOT=__dirname;
const SPECS=[
 ['pistol-muzzle','Pistol muzzle flash','combat-flashes',0,[32,16],[3,8],[73,176],.075,24,false],
 ['rifle-muzzle','Rifle muzzle flash','combat-flashes',1,[32,16],[3,8],[73,176],.075,24,false],
 ['shotgun-muzzle','Shotgun muzzle flash','combat-flashes',2,[32,16],[3,8],[73,166],.075,20,false],
 ['metal-sparks','Metal impact sparks','combat-flashes',3,[32,32],[16,16],[164,158],.095,12,false],
 ['concrete-dust','Concrete impact dust','impacts',0,[32,32],[16,20],[164,220],.085,12,false],
 ['wood-splinters','Wood impact splinters','impacts',1,[32,32],[16,20],[164,220],.085,12,false],
 ['blood-hit','Blood hit','impacts',2,[32,32],[16,16],[164,195],.085,12,false],
 ['water-splash','Water splash','impacts',3,[32,32],[16,26],[164,232],.09,12,false],
 ['explosion','Small explosion','fire-smoke-casing',0,[64,64],[32,56],[164,299],.18,12,false],
 ['flame-loop','Flame loop','fire-smoke-casing',1,[32,48],[16,44],[168,299],.13,8,true],
 ['smoke-loop','Smoke loop','fire-smoke-casing',2,[48,64],[24,60],[168,301],.19,6,true],
 ['ejected-casing','Ejected casing bounce','fire-smoke-casing',3,[32,32],[16,28],[164,236],.055,12,false],
];
const DECALS=[['blood-pool-dry','Dried blood pool',0,0,26],['blood-pool-fresh','Fresh blood pool',0,1,30],['bullet-hole-metal','Metal bullet hole',0,2,10],['bullet-hole-concrete','Concrete bullet hole',0,3,14],['scorch-mark','Scorch mark',1,0,30],['wood-chips','Wood chips',1,1,20],['shell-pile','Shell casing pile',1,2,16],['footprint','Muddy footprint',1,3,20]];
function blank(w,h){return createCanvas(w,h);}
async function png(canvas,p){await fs.promises.writeFile(p,canvas.toBuffer('image/png'));}
async function main(){
 const assets=[],sourceRects=[];
 for(const [slug,label,source,row,size,anchor,sourceAnchor,scale,fps,loop] of SPECS){
  const img=await loadImage(path.join(ROOT,'sources',source+'.png'));
  const cw=img.width/4,ch=img.height/4;
  const frames=[];const atlas=blank(size[0]*4,size[1]);const actx=atlas.getContext('2d');actx.imageSmoothingEnabled=false;
  for(let col=0;col<4;col++){
   let x0=Math.round(cw*col),x1=Math.round(cw*(col+1));
   // Hand-audited gutters isolate source art where a particle crosses nominal cell divisions.
   if(source==='impacts'&&row<3){if(col===2)x1=980;if(col===3)x0=980;}
   if(source==='combat-flashes'&&row===1){if(col===1)x1=670;if(col===2)x0=670;}
   const y0=Math.round(ch*row),y1=Math.round(ch*(row+1));
   const localX=x0-Math.round(cw*col);
   const dw=Math.max(1,Math.round((x1-x0)*scale)),dh=Math.max(1,Math.round((y1-y0)*scale));
   const dx=Math.round(anchor[0]+(localX-sourceAnchor[0])*scale),dy=Math.round(anchor[1]-sourceAnchor[1]*scale);
   const c=blank(...size),ctx=c.getContext('2d');ctx.imageSmoothingEnabled=false;
   ctx.drawImage(img,x0,y0,x1-x0,y1-y0,dx,dy,dw,dh);
   const relative='frames/fx-'+slug+'-'+String(col).padStart(2,'0')+'.png';await png(c,path.join(ROOT,relative));actx.drawImage(c,col*size[0],0);frames.push({path:relative});
   sourceRects.push({id:'fx-'+slug,frame:col,source:'sources/'+source+'.png',rect:[x0,y0,x1-x0,y1-y0],destinationRect:[dx,dy,dw,dh],sourceAnchor,scale});
  }
  const atlasPath='atlases/fx-'+slug+'.png';await png(atlas,path.join(ROOT,atlasPath));
  assets.push({id:'fx-'+slug,label,category:'effects',path:frames[0].path,size,anchor,frames:{[loop?'loop':'play']:frames},fps,duration:4/fps,loop,atlas:{path:atlasPath,columns:4,rows:1,frameSize:size},blend:'normal',...(slug.includes('muzzle')?{facing:'right',attachment:'weapon muzzle'}:{})});
 }
 const img=await loadImage(path.join(ROOT,'sources','decals.png'));
 const cw=img.width/4,ch=img.height/2;
 for(const[slug,label,row,col,maxSide]of DECALS){
  let x0=Math.round(cw*col),x1=Math.round(cw*(col+1));if(row===0&&col===1)x1=970;if(row===0&&col===2)x0=1030;
  const y0=Math.round(ch*row),y1=Math.round(ch*(row+1));
  const crop=await sharp(path.join(ROOT,'sources','decals.png')).extract({left:x0,top:y0,width:x1-x0,height:y1-y0}).png().toBuffer();
  const source=await sharp(crop).trim({threshold:20}).png().toBuffer();
  const sm=await sharp(source).metadata();const scale=maxSide/Math.max(sm.width,sm.height),w=Math.max(1,Math.round(sm.width*scale)),h=Math.max(1,Math.round(sm.height*scale));
  const resized=await sharp(source).resize(w,h,{kernel:'nearest'}).png().toBuffer();const native=blank(32,32),ctx=native.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.drawImage(await loadImage(resized),Math.floor((32-w)/2),Math.floor((32-h)/2));
  const rel='frames/fx-'+slug+'.png';await png(native,path.join(ROOT,rel));
  assets.push({id:'fx-'+slug,label,category:'decals',path:rel,size:[32,32],anchor:[16,16],loop:false});sourceRects.push({id:'fx-'+slug,source:'sources/decals.png',rect:[x0,y0,x1-x0,y1-y0],method:'alpha trim then nearest-neighbor fit',maxSide});
 }
 const manifest={version:1,style:'Original compact pixel VFX for simplyZOMBIES; informed by ZERO Sievert reference screenshots.',nativeWorldTile:32,assets,notes:['Source illustration created with built-in image generation; native exports only crop, pad, and nearest-neighbor scale.','Four genuinely distinct frames per effect. Non-loop effects must hide after their duration; looping previews include a pause between one-shots.','All images retain real source alpha, including partial-alpha edge pixels. No baked checkerboards.','Muzzles face right; rotate around anchor to attach to a weapon muzzle.','Explosion anchor is its ground contact at [32,56]. Fire/smoke anchors attach to the emitter base.','Casing is a tiny four-pose bounce; arc positions are baked into its 32×32 canvas.']};
 fs.writeFileSync(path.join(ROOT,'manifest.json'),JSON.stringify(manifest,null,2));
 fs.writeFileSync(path.join(ROOT,'extraction.json'),JSON.stringify({method:'Mechanical crops, nearest-neighbor scaling and transparent padding; no pixel repainting or background removal.',sourceRects},null,2));
 const qa=[];for(const a of assets){const ff=a.frames?Object.values(a.frames)[0]:[{path:a.path}];const hashes=[];for(const f of ff){const p=path.join(ROOT,f.path),meta=await sharp(p).metadata(),{data}=await sharp(p).raw().toBuffer({resolveWithObject:true});let empty=0,nonempty=0;for(let i=3;i<data.length;i+=4){if(data[i]===0)empty++;else nonempty++;}hashes.push(crypto.createHash('sha256').update(data).digest('hex'));qa.push({id:a.id,path:f.path,size:[meta.width,meta.height],hasAlpha:meta.hasAlpha,emptyPixels:empty,nonemptyPixels:nonempty});}if(new Set(hashes).size!==hashes.length)throw Error('Duplicate frames '+a.id);}
 fs.writeFileSync(path.join(ROOT,'validation.json'),JSON.stringify({assets:assets.length,animated:12,uniqueAnimationFrames:48,staticDecals:8,checks:qa},null,2));
 console.log('Wrote '+assets.length+' effects/decals, 48 animated frames.');
}
main().catch(e=>{console.error(e);process.exit(1)});
