#!/usr/bin/env node
'use strict';
// Executes the emitted standalone HTML against a real Canvas renderer.
// This validates Canvas output and runtime event handlers, not browser CSS or Godot.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const {createHash}=require('node:crypto');
const {createCanvas,Image}=require('@napi-rs/canvas');
const htmlPath=path.resolve(process.argv[2]||path.join(__dirname,'../pack/simplyzombies-world-workshop.html'));
const outputDir=path.resolve(process.argv[3]||path.join(__dirname,'../qa'));
const html=fs.readFileSync(htmlPath,'utf8');
const scripts=Array.from(html.matchAll(/<script>([\s\S]*?)<\/script>/g),m=>m[1]);
assert.equal(scripts.length,2,'Expected embedded bundle and runtime script');
const nodes=[],ids={};
class Element{
  constructor(tag='div',id=''){
    Object.assign(this,{tagName:tag.toUpperCase(),id,dataset:{},attrs:{},children:[],events:{},checked:false,disabled:false,hidden:false,value:'',textContent:'',style:{}});
    if(tag==='canvas')this.surface=createCanvas(48,48);
    nodes.push(this);
  }
  get width(){return this.surface?.width;}set width(v){if(this.surface)this.surface.width=Number(v);}
  get height(){return this.surface?.height;}set height(v){if(this.surface)this.surface.height=Number(v);}
  append(...v){this.children.push(...v);}replaceChildren(...v){this.children=v;}
  setAttribute(k,v){this.attrs[k]=String(v);}getAttribute(k){return this.attrs[k];}
  addEventListener(k,fn){(this.events[k]||=[]).push(fn);}
  emit(k,p={}){for(const fn of this.events[k]||[])fn({target:this,preventDefault(){},...p});}
  getContext(type,options){return this.surface.getContext(type,options);}
  getBoundingClientRect(){return{left:0,top:0,width:this.width,height:this.height};}
  focus(){}setPointerCapture(){}
}
for(const m of html.matchAll(/<(\w+)\b([^>]*)>/g)){
  const attrs=Object.fromEntries(Array.from(m[2].matchAll(/([\w-]+)="([^"]*)"/g),a=>[a[1],a[2]]));
  if(!attrs.id&&!Object.keys(attrs).some(k=>k.startsWith('data-')))continue;
  const el=new Element(m[1],attrs.id||'');if(attrs.id)ids[attrs.id]=el;
  for(const[k,v]of Object.entries(attrs)){
    el.attrs[k]=v;
    if(k.startsWith('data-'))el.dataset[k.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=v;
    if(k==='width'||k==='height')el[k]=Number(v);
  }
}
assert(ids.scene.width>0&&ids.scene.height>0,'Scene dimensions must come from HTML');
const documentEvents={},windowEvents={};
const document={hidden:false,getElementById:id=>ids[id],createElement:tag=>new Element(tag),addEventListener:(t,fn)=>{(documentEvents[t]||=[]).push(fn);},querySelectorAll:s=>{
  const m=s.match(/^\[data-(.+)\]$/);if(!m)throw Error('Unsupported test selector '+s);
  const key=m[1].replace(/-([a-z])/g,(_,c)=>c.toUpperCase());return nodes.filter(n=>n.dataset[key]!==undefined);
}};
const window={addEventListener:(t,fn)=>{(windowEvents[t]||=[]).push(fn);},requestAnimationFrame:fn=>window.animationFrame=fn};
const context=vm.createContext({window,document,Image,console,Promise,Map,Set,Math,Error,Number,String,Object,Array});
const checksum=b=>createHash('sha256').update(b).digest('hex');
function keyboard(type,key,target=ids.scene){for(const fn of windowEvents[type]||[])fn({key,target,repeat:false,preventDefault(){}});}
function save(name,surface=ids.scene.surface){fs.writeFileSync(path.join(outputDir,name),surface.toBuffer('image/png'));}
function close(a,b,why){assert(Math.abs(a-b)<1e-6,why+': '+a+' versus '+b);}
(async()=>{
  fs.mkdirSync(outputDir,{recursive:true});
  for(const[i,s]of scripts.entries())new vm.Script(s,{filename:'offline-script-'+i+'.js'}).runInContext(context);
  for(let n=0;n<500&&!window.ArtSample;n++)await new Promise(r=>setTimeout(r,20));
  const app=window.ArtSample;
  assert(app?.state.ready,'Runtime did not finish loading: '+ids.loading.children.map(n=>n.textContent).join(' '));
  assert.equal(ids.loading.hidden,true);
  for(const id of ['weapon','gear','shoot','burst','effects-demo','walk-cycle','asset-search','asset-category'])assert(ids[id],'Required workshop control '+id);
  const M=app.manifest,B=window.ART_BUNDLE,checks=[],directions=['s','e','n','w'],initial={...app.player};
  const zooms=document.querySelectorAll('[data-zoom]');
  const body=app.byId.get(typeof M.character.layers[0]==='string'?M.character.layers[0]:M.character.layers[0].asset);
  const fpsFor=(a,anim)=>(typeof a.fps==='object'?a.fps[anim]:a.fps)||M.character.movement?.fps||8;
  function assetImage(a,anim='idle',dir='e',time=0){const c=createCanvas(192,192);app.drawAsset(c.getContext('2d'),a,96,160,{anim,dir,time});return c.toBuffer('image/png');}
  function actorImage(){const c=createCanvas(192,192);app.drawActor(c.getContext('2d'),96,150);return c.toBuffer('image/png');}
  function enumerate(a){
    const f=a.animations||a.frames;
    if(Array.isArray(f))return[{anim:'idle',dir:'e',seq:f}];
    if(!f)return[{anim:'idle',dir:'e',seq:[0]}];
    const out=[];
    for(const[k,v]of Object.entries(f)){
      if(Array.isArray(v)){const m=k.match(/^(.*)_(e|se|s|sw|w|nw|n|ne)$/);out.push({anim:m?m[1]:k,dir:m?m[2]:'e',seq:v});}
      else if(v&&typeof v==='object'&&!v.path&&!v.rect){for(const[dir,seq]of Object.entries(v))if(Array.isArray(seq))out.push({anim:k,dir,seq});}
    }
    return out.length?out:[{anim:'idle',dir:'e',seq:[0]}];
  }
  const frameReport=[];
  for(const a of M.assets){
    assert(a.path&&B.images[a.path],'Missing embedded image for '+a.id);
    for(const{anim,dir,seq}of enumerate(a)){
      const hashes=[];
      for(let n=0;n<seq.length;n++){
        const item=seq[n],p=typeof item==='string'?item:item?.path||item?.file;
        if(p)assert(B.images[p],'Missing frame image '+p);
        const f=app.frame(a,anim,dir,(n+.05)/fpsFor(a,anim));assert(f,'Missing frame for '+a.id+' '+anim+' '+dir);
        assert(f.rect.every(Number.isFinite)&&f.rect[0]>=0&&f.rect[1]>=0&&f.rect[2]>0&&f.rect[3]>0&&f.rect[0]+f.rect[2]<=f.image.width&&f.rect[1]+f.rect[3]<=f.image.height,'Out-of-bounds frame for '+a.id+' '+anim+' '+dir);
        if(seq.length>1)hashes.push(checksum(assetImage(a,anim,dir,(n+.05)/fpsFor(a,anim))));
      }
      const unique=new Set(hashes).size;
      if(seq.length>1)assert(unique>1,'Animation must change visible pixels: '+a.id+' '+anim+' '+dir);
      frameReport.push({asset:a.id,animation:anim,direction:dir,frames:seq.length,distinctRenderedFrames:seq.length>1?unique:1});
    }
  }
  checks.push('Every embedded asset and frame path resolves; all sampled source rectangles are within decoded PNG dimensions. Every animation sequence changes visible pixels at a fixed anchor.');
  assert.equal(M.character.directionCount,4);assert.equal(app.state.weapon,'');assert.equal(app.gear.size,0);
  app.drawWorld();save('workshop-day-2x.png');
  for(const b of zooms){b.emit('click');assert.equal(app.state.zoom,Number(b.dataset.zoom));app.drawWorld();}zooms.find(b=>b.dataset.zoom==='2').emit('click');
  app.setFacing('e');const speed=M.character.movement?.speed||M.character.walkSpeed||45,fps=M.character.movement?.fps||fpsFor(body,'walk');
  keyboard('keydown','d');const moving=[];
  for(let n=0;n<4;n++){app.update(1/fps);moving.push(checksum(actorImage()));}
  keyboard('keyup','d');assert(new Set(moving).size>1,'Walking must animate');assert(app.player.x>initial.x,'Walking must move');
  const clock=app.player.strideClock;app.update(0);assert.equal(app.player.moving,false);const idle=checksum(actorImage());app.update(.3);close(app.player.strideClock,clock,'Stopping freezes stride phase');assert.equal(checksum(actorImage()),idle);
  app.player.x=M.canvas.width-12;app.player.y=initial.y;keyboard('keydown','d');app.update(.2);keyboard('keyup','d');assert.equal(app.player.moving,false);close(app.player.strideClock,clock,'Blocked movement freezes stride phase');
  app.player.x=initial.x;app.player.y=initial.y;app.update(0);
  checks.push('WASD moves and animates the survivor; key release and map-edge blocking select idle without advancing stride phase.');
  const facingHashes=[];
  for(const b of document.querySelectorAll('[data-facing]')){b.emit('click');assert.equal(app.direction(app.player.angle),b.dataset.facing);facingHashes.push(checksum(actorImage()));}
  assert.equal(new Set(facingHashes).size,4,'Four standing headings must remain distinct');
  for(const key of ['w','a','s','d']){
    const btn=document.querySelectorAll('[data-key]').find(n=>n.dataset.key===key),before=[app.player.x,app.player.y];assert(btn);
    btn.emit('pointerdown',{pointerId:1});app.update(.05);btn.emit('pointerup',{pointerId:1});app.update(0);assert(app.player.x!==before[0]||app.player.y!==before[1],'Mobile '+key+' should move');assert.equal(app.player.moving,false);
  }
  const cancel=document.querySelectorAll('[data-key]')[0];cancel.emit('pointerdown',{pointerId:2});cancel.emit('pointercancel',{pointerId:2});app.update(.05);assert.equal(app.player.moving,false);
  const beforeEditable=[app.player.x,app.player.y];keyboard('keydown','d',ids['asset-search']);app.update(.05);assert.deepEqual([app.player.x,app.player.y],beforeEditable,'Typing in search must not move actor');
  checks.push('Four facing controls, 1×/2×/4× scale controls and all mobile movement/release/cancel handlers work; text entry does not move the character.');
  app.player.x=initial.x;app.player.y=initial.y;app.setFacing('s');
  const bare=checksum(actorImage()),gearNodes=document.querySelectorAll('[data-gear]');assert(gearNodes.length,'Expected equipment checkboxes');
  for(const n of gearNodes){n.checked=true;n.emit('change');assert(app.gear.has(n.dataset.gear));}
  assert.notEqual(checksum(actorImage()),bare,'Equipping clothing must visibly change survivor');app.drawWorld();save('workshop-equipped-2x.png');
  for(const n of gearNodes){n.checked=false;n.emit('change');assert(!app.gear.has(n.dataset.gear));}
  assert.equal(checksum(actorImage()),bare,'Removing all equipment restores original bare sprite');
  const firearm=M.showcase.weapons.find(id=>/pistol/.test(id))||M.showcase.weapons.find(id=>/rifle|shotgun|smg/.test(id));assert(firearm,'Need firearm for flash test');
  ids.weapon.value=firearm;ids.weapon.emit('change');assert.equal(app.state.weapon,firearm);
  const poseSheet=createCanvas(768,256),pc=poseSheet.getContext('2d');pc.fillStyle='#202821';pc.fillRect(0,0,768,256);pc.imageSmoothingEnabled=false;
  for(let i=0;i<directions.length;i++){
    const dir=directions[i];app.setFacing(dir);const p=app.weaponPose();assert(p&&[p.x,p.y,p.mx,p.my,p.angle].every(Number.isFinite));
    const dx=p.mx-p.x,dy=p.my-p.y,forward=dx*Math.cos(p.angle)+dy*Math.sin(p.angle),side=-dx*Math.sin(p.angle)+dy*Math.cos(p.angle);
    close(forward,p.a.muzzle[0]-p.a.grip[0],'Muzzle forward distance '+dir);close(Math.abs(side),Math.abs(p.a.muzzle[1]-p.a.grip[1]),'Muzzle side distance '+dir);assert(forward>0,'Muzzle must remain in front of grip');
    pc.save();pc.translate(96+i*192,200);pc.scale(4,4);app.drawActor(pc,0,0);pc.restore();pc.fillStyle='#d8dfc8';pc.font='14px monospace';pc.textAlign='center';pc.fillText(dir.toUpperCase(),96+i*192,230);
  }
  save('weapon-four-directions-4x.png',poseSheet);
  checks.push('Every gear checkbox updates the equipped layers; removing gear restores the bare survivor. Held pistol grip and muzzle transformations are finite and forward-facing in all four aim directions.');
  app.setFacing('e');app.effects.length=0;app.state.lastShot=-10;app.shoot({x:40,y:40});
  const emitted=app.effects.map(f=>f.asset);for(const id of [M.showcase.effects.pistol,M.showcase.effects.casing,M.showcase.effects.concrete])assert(emitted.includes(id),'Shooting must emit '+id);
  assert(app.effects.every(f=>Number.isFinite(f.duration)&&f.duration>0));app.drawWorld();save('workshop-shot-2x.png');
  const frozen=JSON.stringify({time:app.state.time,effects:app.effects,player:app.player,npcs:app.npcs});ids.pause.emit('click');app.update(.5);app.shoot();app.explosion();assert.equal(JSON.stringify({time:app.state.time,effects:app.effects,player:app.player,npcs:app.npcs}),frozen,'Pause must freeze effects and actors and suppress new combat FX');ids.pause.emit('click');
  const lifetime=Math.max(...app.effects.map(f=>f.duration));app.update(lifetime+.1);assert.equal(app.effects.length,0,'One-shot effects must expire');
  ids.burst.emit('click');assert(app.effects.some(f=>f.asset===M.showcase.effects.explosion));app.drawWorld();save('workshop-explosion-2x.png');app.update(4);assert.equal(app.effects.length,0);
  app.state.lastShot=-10;const shotCount=app.state.shots;ids.shoot.emit('click');assert.equal(app.state.shots,shotCount+1,'Fire button shoots');app.update(.2);keyboard('keydown','f');assert.equal(app.state.shots,shotCount+2,'F key shoots');
  const vp=app.viewport();app.update(.2);ids.scene.emit('pointerdown',{button:0,pointerType:'mouse',clientX:(app.player.x+80-vp.x)*app.state.zoom,clientY:(app.player.y-12-vp.y)*app.state.zoom});assert.equal(app.state.shots,shotCount+3,'Scene mouse press shoots');app.state.pointer=null;
  app.effects.length=0;app.state.lastShot=-10;const demoStart=app.state.shots;ids['effects-demo'].emit('click');let sawExplosion=false;
  for(let n=0;n<80;n++){app.update(.05);sawExplosion ||= app.effects.some(f=>f.asset===M.showcase.effects.explosion);}
  assert(app.state.shots>=demoStart+4,'FX demo must repeat shots');assert(sawExplosion,'FX demo must include explosion');ids['effects-demo'].emit('click');assert.equal(app.state.demo,false);app.update(5);assert.equal(app.effects.length,0);
  checks.push('Fire button, F key and scene clicks produce muzzle flash, casing and impact. One-shot FX expire; pause freezes FX and suppresses new shots. Explosion and repeating FX-demo controls work.');
  const interactive=app.props.filter(p=>p.states?.length>1);assert(interactive.length,'Expected searchable containers');
  for(const p of interactive){
    app.player.x=p.x;app.player.y=p.y+6;app.update(0);assert.equal(app.state.near,p);assert.equal(ids.interact.disabled,false);
    const states=[],labels=[];for(let i=0;i<p.states.length;i++){states.push(p.state);labels.push(ids['interaction-hint'].textContent);ids.interact.emit('click');}
    assert.equal(new Set(states).size,p.states.length);assert.equal(new Set(labels).size,p.states.length);assert.equal(p.state,0);
  }
  checks.push('Each nearby searchable container cycles its distinct image states and returns to its initial state.');
  const rows=document.querySelectorAll('[data-asset]');assert.equal(rows.length,M.assets.length);
  const named=M.assets.find(a=>/pine/.test(a.id))||M.assets[0];ids['asset-search'].value=(named.label||named.name||named.id).slice(0,4);ids['asset-search'].emit('input');assert(rows.some(r=>!r.hidden)&&rows.some(r=>r.hidden),'Search should filter asset rows');
  const category=M.assets.find(a=>a.category)?.category;ids['asset-search'].value='';ids['asset-search'].emit('input');ids['asset-category'].value=category;ids['asset-category'].emit('change');assert(rows.filter(r=>!r.hidden).every(r=>app.byId.get(r.dataset.asset).category===category));
  ids['asset-category'].value='All categories';ids['asset-category'].emit('change');assert(rows.every(r=>!r.hidden));
  for(const a of M.assets){app.selectAsset(a.id);assert(ids['asset-name'].textContent.length);assert(app.frame(a));}
  app.selectAsset(body.id);app.player.x=initial.x;app.player.y=initial.y;app.setFacing('e');app.update(0);ids.night.checked=true;ids.night.emit('change');app.drawWorld();save('workshop-night-2x.png');ids.night.checked=false;ids.night.emit('change');
  checks.push('Asset search and category filtering narrow and restore the catalog; all asset inspector previews and night lighting render.');
  const patrols=app.npcs.filter(n=>n.patrolA&&n.patrolB);assert(patrols.length);const beforePatrol=patrols.map(n=>n.strideClock);for(let i=0;i<40;i++)app.update(.05);assert(patrols.some((n,i)=>n.strideClock>beforePatrol[i]));
  checks.push('Animated shamblers continue moving along their local patrol paths.');
  // Capture the actual workshop runtime, no replacement art or synthetic sprite painting.
  app.effects.length=0;app.state.pointer=null;app.state.walkInPlace=false;app.state.paused=false;app.state.time=0;app.state.lastShot=-10;app.state.shots=0;
  app.player.x=initial.x;app.player.y=initial.y;app.player.strideClock=0;app.player.moving=false;app.setFacing('e');
  for(const n of gearNodes){n.checked=true;n.emit('change');}
  app.npcs.forEach((n,i)=>Object.assign(n,{x:M.scene.actors[i].x,y:M.scene.actors[i].y,strideClock:0,patrolTarget:1,moving:false}));
  const frameDir=path.join(outputDir,'workshop-action-frames');fs.mkdirSync(frameDir,{recursive:true});
  const frameCount=120,captureFPS=20;
  for(let n=0;n<frameCount;n++){
    if(n===0)keyboard('keydown','d');if(n===22){keyboard('keyup','d');app.setFacing('e');}
    if(n===65)keyboard('keydown','a');if(n===88){keyboard('keyup','a');app.setFacing('e');}
    app.update(1/captureFPS);
    if([26,31,37,48,95,103].includes(n))app.shoot({x:504,y:280});
    if(n===53||n===110)app.explosion();
    app.drawWorld();fs.writeFileSync(path.join(frameDir,String(n).padStart(3,'0')+'.png'),ids.scene.surface.toBuffer('image/png'));
    if(n===54)save('workshop-action-2x.png');
  }
  const result=spawnSync('ffmpeg',['-hide_banner','-loglevel','error','-y','-framerate',String(captureFPS),'-i',path.join(frameDir,'%03d.png'),'-filter_complex','split[s0][s1];[s0]palettegen=max_colors=256[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3','-loop','0',path.join(outputDir,'workshop-action-2x.gif')],{encoding:'utf8'});
  if(result.status!==0)throw Error(result.stderr||'GIF encoding failed');fs.rmSync(frameDir,{recursive:true,force:true});
  const report={html:htmlPath,result:'passed',canvas:[ids.scene.width,ids.scene.height],assets:M.assets.length,embeddedImages:Object.keys(B.images).length,animationSequences:frameReport.filter(r=>r.frames>1).length,checkedFrames:frameReport.reduce((n,r)=>n+r.frames,0),checks,frames:frameReport,previews:['workshop-day-2x.png','workshop-equipped-2x.png','weapon-four-directions-4x.png','workshop-shot-2x.png','workshop-explosion-2x.png','workshop-night-2x.png','workshop-action-2x.png','workshop-action-2x.gif'],gif:{frames:frameCount,fps:captureFPS,seconds:frameCount/captureFPS,renderer:'Emitted standalone HTML runtime and embedded PNGs',content:'Survivor movement, local shambler patrols, equipped pistol/clothing, shots and explosions.'},limitations:['Executed in @napi-rs/canvas with DOM event shims, not a full browser. Browser CSS layout and real browser event dispatch are not tested.','This standalone workshop is not a Godot game capture; no Godot integration is claimed.','Container opening is a discrete state swap, not an interpolated lid animation.']};
  fs.writeFileSync(path.join(outputDir,'verification.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({...report,frames:undefined},null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
