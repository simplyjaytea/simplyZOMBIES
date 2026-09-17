#!/usr/bin/env node
'use strict';
// Runs the emitted, offline HTML's own JavaScript against a real Canvas renderer.
// This verifies art rendering and controls; it does not test browser CSS layout.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const {createHash}=require('node:crypto');
const {createCanvas,Image} = require('@napi-rs/canvas');
const htmlPath = path.resolve(process.argv[2] || path.join(__dirname,'../pack/simplyzombies-walk-preview.html'));
const outputDir = path.resolve(process.argv[3] || path.join(__dirname,'../pack/previews'));
const html = fs.readFileSync(htmlPath,'utf8');
const scripts = Array.from(html.matchAll(/<script>([\s\S]*?)<\/script>/g), m => m[1]);
assert.equal(scripts.length,2,'Expected embedded bundle and runtime script');
const nodes = [];
class Element {
  constructor(tag='div',id='') {
    this.tagName=tag.toUpperCase();this.id=id;this.dataset={};this.attrs={};this.children=[];this.events={};this.checked=false;this.disabled=false;this.hidden=false;this.value='';this.textContent='';
    if(tag==='canvas')this.surface=createCanvas(id==='scene'?960:id==='inspect'?160:48,id==='scene'?640:id==='inspect'?160:48);
    nodes.push(this);
  }
  get width(){return this.surface?.width;} set width(value){if(this.surface)this.surface.width=value;}
  get height(){return this.surface?.height;} set height(value){if(this.surface)this.surface.height=value;}
  append(...children){this.children.push(...children);}
  replaceChildren(...children){this.children=children;}
  setAttribute(key,value){this.attrs[key]=value;}
  addEventListener(type,fn){(this.events[type] ||= []).push(fn);}
  emit(type,props={}){for(const fn of this.events[type] || [])fn({target:this,preventDefault(){},...props});}
  getContext(type,options){return this.surface.getContext(type,options);}
  getBoundingClientRect(){return {left:0,top:0,width:this.width,height:this.height};}
  focus(){} setPointerCapture(){}
}
const ids={};
for(const m of html.matchAll(/<(\w+)[^>]*\sid="([^"]+)"[^>]*>/g))ids[m[2]]=new Element(m[1],m[2]);
const zooms=[1,2,4].map(z=>{const el=new Element('button');el.dataset.zoom=String(z);return el;});
for(const facing of ['s','e','n','w']){const el=new Element('button');el.dataset.facing=facing;}
for(const key of ['w','a','s','d']){const el=new Element('button');el.dataset.key=key;}
const documentEvents={};
const document={hidden:false,getElementById:id=>ids[id],createElement:tag=>new Element(tag),addEventListener:(type,fn)=>{(documentEvents[type] ||= []).push(fn);},querySelectorAll:selector=>{
  const m=selector.match(/^\[data-(.+)\]$/);if(!m)throw Error('Unsupported test selector '+selector);
  const key=m[1].replace(/-([a-z])/g,(_,c)=>c.toUpperCase());return nodes.filter(n=>n.dataset[key]!==undefined);
}};
const windowEvents={};
const window={addEventListener:(type,fn)=>{(windowEvents[type] ||= []).push(fn);},requestAnimationFrame:fn=>window.animationFrame=fn};
const context=vm.createContext({window,document,Image,console,Promise,Map,Set,Math,Error,Number,String,Object,Array});
function keyboard(type,key){for(const fn of windowEvents[type] || [])fn({key,target:ids.scene,repeat:false,preventDefault(){}});}
function save(name){fs.writeFileSync(path.join(outputDir,name),ids.scene.surface.toBuffer('image/png'));}
(async()=>{
  for(const [i,script] of scripts.entries())new vm.Script(script,{filename:'offline-script-'+i+'.js'}).runInContext(context);
  for(let attempts=0;attempts<150&&!window.ArtSample;attempts++)await new Promise(resolve=>setTimeout(resolve,20));
  const app=window.ArtSample;
  assert(app?.state.ready,'Runtime did not finish image loading');
  assert.equal(ids.loading.hidden,true,'Loading overlay must be hidden');
  assert.equal(ids.layers,undefined,'Equipment controls must not be present');
  assert(ids['walk-cycle'],'Walk in place control is required');
  const manifest=app.manifest,checks=[],directions=['s','e','n','w'];
  const facings=document.querySelectorAll('[data-facing]');
  const body=app.byId.get(manifest.character.layers[0]);
  const characters=manifest.assets.filter(a=>directions.every(dir=>app.framesFor(a,'walk',dir).length===4));
  assert.equal(characters.length,2,'Expected animated survivor and shambler');
  const initial={...app.player};
  fs.mkdirSync(outputDir,{recursive:true});
  const checksum=buffer=>createHash('sha256').update(buffer).digest('hex');
  function actorImage(){const surface=createCanvas(96,96);app.drawActor(surface.getContext('2d'),48,72);return surface.toBuffer('image/png');}
  function characterImage(a,dir,time){const surface=createCanvas(96,96);app.drawAsset(surface.getContext('2d'),a,48,72,{anim:'walk',dir,time});return surface.toBuffer('image/png');}
  function fpsFor(a,anim){return typeof a.fps==='object'?(a.fps[anim]||8):(a.fps||8);}
  for(const a of manifest.assets)for(const anim of ['idle','walk'])for(const dir of directions){
    const frames=app.framesFor(a,anim,dir);
    for(let n=0;n<frames.length;n++){
      const f=app.frame(a,anim,dir,(n+.1)/fpsFor(a,anim));
      assert(f,'Missing rendered frame for '+a.id);
      assert(f.rect[0]>=0&&f.rect[1]>=0&&f.rect[0]+f.rect[2]<=f.image.width&&f.rect[1]+f.rect[3]<=f.image.height,'Frame bounds exceed image for '+a.id);
    }
  }
  checks.push('Every embedded PNG decodes and every indexed frame stays within its source image.');
  assert.equal(manifest.character.directionCount,4);
  assert.equal(app.direction(app.player.angle),'s');
  for(const a of characters)for(const dir of directions){
    const hashes=Array.from({length:4},(_,n)=>checksum(characterImage(a,dir,(n+.1)/fpsFor(a,'walk'))));
    assert.equal(new Set(hashes).size,4,a.id+' '+dir+' needs four visibly distinct frames at one fixed ground position');
    assert.equal(app.framesFor(a,'idle',dir).length,1,a.id+' '+dir+' needs its approved standing pose');
  }
  checks.push('Both characters render four distinct animation frames at a fixed position in each of four headings.');
  app.drawWorld();save('scene-room-2x.png');
  zooms[2].emit('click');app.drawWorld();save('scene-detail-4x.png');zooms[1].emit('click');
  const hashes=[];
  for(const btn of facings){btn.emit('click');assert.equal(app.direction(app.player.angle),btn.dataset.facing);hashes.push(checksum(actorImage()));assert.equal(btn.attrs['aria-pressed'],'true');}
  assert.equal(new Set(hashes).size,4,'Four standing headings must remain distinct');
  checks.push('Facing controls still select the approved standing view.');
  app.setFacing('e');
  const speed=manifest.character.movement?.speed||manifest.character.walkSpeed||45;
  const fps=manifest.character.movement?.fps||fpsFor(body,'walk');
  keyboard('keydown','d');
  const walking=[];
  for(let n=0;n<4;n++){app.update(1/fps);walking.push(checksum(actorImage()));}
  keyboard('keyup','d');
  assert.equal(new Set(walking).size,4,'Moving actor must select four frames rather than translate a standing pose');
  assert(Math.abs(app.player.x-initial.x-4*speed/fps)<.000001);
  assert.equal(app.player.facing,'e');assert(ids['scene-state'].textContent.includes('walking'));
  const stoppedClock=app.player.strideClock;app.update(0);assert.equal(app.player.moving,false);
  app.update(.4);assert.equal(app.player.strideClock,stoppedClock,'Idle time must not advance the stride clock');
  const idleAtStop=checksum(actorImage());app.player.strideClock+=.23;assert.equal(checksum(actorImage()),idleAtStop,'Released keys must draw a standing pose');app.player.strideClock=stoppedClock;
  checks.push('Movement advances animation by distance traveled; release selects idle and preserves stride phase.');
  app.player.x=manifest.canvas.width-12;app.player.y=initial.y;app.state.pointer=null;
  keyboard('keydown','d');const blockedClock=app.player.strideClock;app.update(.2);keyboard('keyup','d');
  assert.equal(app.player.moving,false);assert.equal(app.player.strideClock,blockedClock,'Pushing against the world boundary must not run the walk cycle');
  if(manifest.scene.collisions?.length){
    const wall=manifest.scene.collisions[0];app.player.x=wall.x+wall.width/2;app.player.y=wall.y-.1;
    keyboard('keydown','s');app.update(.05);keyboard('keyup','s');assert.equal(app.player.moving,false);assert.equal(app.player.strideClock,blockedClock);
  }
  app.player.x=initial.x;app.player.y=initial.y;app.update(0);
  checks.push('Blocked movement at the map edge and wall collision stays idle without advancing stride phase.');
  for(const key of ['w','a','s','d']){
    const btn=document.querySelectorAll('[data-key]').find(el=>el.dataset.key===key),before={x:app.player.x,y:app.player.y};
    app.state.pointer=null;btn.emit('pointerdown',{pointerId:1});app.update(.05);btn.emit('pointerup',{pointerId:1});app.update(0);
    assert(app.player.x!==before.x||app.player.y!==before.y,'Touch button '+key+' should move the survivor');assert.equal(app.player.moving,false);
  }
  const cancel=document.querySelectorAll('[data-key]')[0];cancel.emit('pointerdown',{pointerId:2});cancel.emit('pointercancel',{pointerId:2});app.update(.05);assert.equal(app.player.moving,false);
  checks.push('All mobile movement buttons work; release and cancellation stop movement.');
  ids.scene.emit('pointermove',{clientX:20,clientY:app.player.y*2-40});app.update(0);assert.equal(app.direction(app.player.angle),'w');
  keyboard('keydown','d');app.update(.05);keyboard('keyup','d');
  assert.equal(app.player.facing,'e','A moving whole-body sprite must face movement, even while the pointer aims west');
  assert.equal(checksum(actorImage()),checksum(characterImage(body,'e',app.player.strideClock)),'Moving east with a west pointer must select the east walk row');
  app.update(0);assert.equal(app.player.facing,'w','Idle should return to the pointer heading');
  for(const el of zooms){el.emit('click');assert.equal(app.state.zoom,Number(el.dataset.zoom));app.drawWorld();}zooms[1].emit('click');
  checks.push('Walking faces the travel direction even with an opposite pointer; idle returns to pointer facing. All three pixel scales render.');
  app.setFacing('s');ids['walk-cycle'].emit('click');
  const inPlaceOrigin=[app.player.x,app.player.y],inPlace=[];
  for(let n=0;n<4;n++){app.update(1/fps);inPlace.push(checksum(actorImage()));assert.deepEqual([app.player.x,app.player.y],inPlaceOrigin);}
  assert.equal(new Set(inPlace).size,4,'Walk in place must show four distinct frames without moving the actor');
  for(const dir of directions){
    app.setFacing(dir);app.player.strideClock=.1/fps;
    const drawn=checksum(actorImage()),expected=checksum(characterImage(body,dir,.1/fps));
    assert.equal(drawn,expected,'Heading '+dir+' must select its own walk row');
  }
  checks.push('Walk in place cycles four frames without translation, and each heading selects its corresponding walk row.');
  ids['auto-turn'].emit('click');const autoDirections=[];
  for(let i=0;i<4;i++){app.update(i===0?0:.95);autoDirections.push(app.direction(app.player.angle));}
  assert.equal(new Set(autoDirections).size,4);
  const frozen={time:app.state.time,clock:app.player.strideClock,player:[app.player.x,app.player.y],npcs:app.npcs.map(n=>[n.x,n.y,n.strideClock])};
  ids.pause.emit('click');app.update(.5);
  assert.equal(app.state.time,frozen.time);assert.equal(app.player.strideClock,frozen.clock);assert.deepEqual([app.player.x,app.player.y],frozen.player);assert.deepEqual(app.npcs.map(n=>[n.x,n.y,n.strideClock]),frozen.npcs);
  ids.pause.emit('click');app.setFacing('s');assert.equal(app.state.autoTurn,false);ids['walk-cycle'].emit('click');
  checks.push('Auto turn cycles all headings; pause freezes actor positions, stride clocks, and inspector time.');
  const patrols=app.npcs.filter(n=>n.patrolA&&n.patrolB);assert(patrols.length,'Expected at least one shambler patrol');
  const prior=patrols.map(n=>[n.x,n.y,n.strideClock]);const patrolFrames=patrols.map(()=>new Set());
  for(let step=0;step<240;step++){
    app.update(.05);
    patrols.forEach((n,i)=>{
      assert(n.x>=Math.min(n.patrolA[0],n.patrolB[0])-.001&&n.x<=Math.max(n.patrolA[0],n.patrolB[0])+.001);
      assert(n.y>=Math.min(n.patrolA[1],n.patrolB[1])-.001&&n.y<=Math.max(n.patrolA[1],n.patrolB[1])+.001);
      patrolFrames[i].add(checksum(characterImage(app.byId.get(n.asset),n.dir,n.strideClock)));
    });
  }
  patrols.forEach((n,i)=>{assert(n.strideClock>prior[i][2]);assert(patrolFrames[i].size>=4,'Patrol should play animation while moving');});
  checks.push('Shamblers move and animate within their local patrol bounds through multiple turns.');
  const interactive=(manifest.scene.props||[]).find(p=>p.states?.length>1);
  if(interactive){
    app.player.x=interactive.x;app.player.y=interactive.y+8;app.update(0);assert.equal(ids.interact.disabled,false);
    const labels=[];for(let i=0;i<interactive.states.length;i++){labels.push(ids['interaction-hint'].textContent);ids.interact.emit('click');}
    assert.equal(new Set(labels).size,interactive.states.length);assert.equal(ids['interaction-hint'].textContent,labels[0]);
    checks.push('Container interaction cycles all three image states and returns to closed.');
  }
  app.player.x=initial.x;app.player.y=initial.y;app.setFacing('s');app.update(0);
  ids.night.checked=true;ids.night.emit('change');app.drawWorld();save('scene-night-2x.png');ids.night.checked=false;ids.night.emit('change');
  for(const a of manifest.assets){app.selectAsset(a.id);assert(ids['asset-name'].textContent.length);}app.selectAsset(body.id);
  const inspectHashes=[];for(let n=0;n<4;n++){app.state.time=(n+.1)/fpsFor(body,'walk');app.renderInspect();inspectHashes.push(checksum(ids.inspect.surface.toBuffer('image/png')));}
  assert.equal(new Set(inspectHashes).size,4,'Character inspector should animate its walk cycle');
  checks.push('Night lighting and every asset preview render; the character inspector plays four distinct walk frames.');
  function encode(name,frameCount,draw){
    const framesDir=path.join(outputDir,name+'-frames');fs.mkdirSync(framesDir,{recursive:true});
    for(let n=0;n<frameCount;n++){const surface=draw(n);fs.writeFileSync(path.join(framesDir,String(n).padStart(3,'0')+'.png'),surface.toBuffer('image/png'));}
    const gifPath=path.join(outputDir,name+'.gif');
    const result=spawnSync('ffmpeg',['-hide_banner','-loglevel','error','-y','-framerate','40','-i',path.join(framesDir,'%03d.png'),'-filter_complex','split[s0][s1];[s0]palettegen=max_colors=256[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3','-loop','0',gifPath],{encoding:'utf8'});
    if(result.status!==0)throw Error(result.stderr||'GIF encoding failed');
    fs.rmSync(framesDir,{recursive:true,force:true});
  }
  const enemy=characters.find(a=>a.id!==body.id);
  const study=createCanvas(640,288),sc=study.getContext('2d');
  app.state.paused=false;app.state.pointer=null;app.player.strideClock=0;app.state.walkInPlace=true;
  encode('walk-in-place-4x',320,n=>{
    const dir=directions[Math.floor(n/80)];app.setFacing(dir);app.update(1/40);
    sc.fillStyle='#141911';sc.fillRect(0,0,640,288);sc.imageSmoothingEnabled=false;
    sc.fillStyle='#c4cc8b';sc.font='bold 13px monospace';sc.textAlign='left';sc.fillText('simplyZOMBIES / WALK STUDY',24,29);
    sc.fillStyle='#909b84';sc.font='11px monospace';sc.textAlign='right';sc.fillText(dir.toUpperCase()+' / 4× PIXELS',616,29);
    sc.fillStyle='#21291b';sc.fillRect(24,48,288,192);sc.fillRect(328,48,288,192);
    sc.save();sc.translate(168,208);sc.scale(4,4);app.drawActor(sc,0,0);sc.restore();
    sc.save();sc.translate(472,208);sc.scale(4,4);app.drawAsset(sc,enemy,0,0,{anim:'walk',dir,time:app.state.time});sc.restore();
    sc.fillStyle='#dce2d2';sc.font='12px monospace';sc.textAlign='center';sc.fillText('SURVIVOR',168,263);sc.fillText('SHAMBLER',472,263);
    if(n===5)fs.writeFileSync(path.join(outputDir,'walk-study-4x.png'),study.toBuffer('image/png'));
    return study;
  });
  app.state.walkInPlace=false;app.player.x=initial.x;app.player.y=initial.y;app.player.strideClock=0;app.state.time=0;
  app.npcs.forEach((n,i)=>Object.assign(n,{x:manifest.scene.actors[i].x,y:manifest.scene.actors[i].y,strideClock:0,patrolTarget:1,moving:false}));
  zooms[1].emit('click');
  const pathKeys=['d','w','a','s'];
  encode('courtyard-walk-2x',320,n=>{
    const section=Math.floor(n/80),key=pathKeys[section];
    if(n%80===0){if(section>0)keyboard('keyup',pathKeys[section-1]);keyboard('keydown',key);}
    app.update(1/40);app.drawWorld();return ids.scene.surface;
  });
  keyboard('keyup','s');app.update(0);
  const report={html:htmlPath,assets:manifest.assets.length,result:'passed',checks,limitations:['Browser CSS layout and real browser event dispatch were not tested.','The approved standing views are idle poses; only directional walk cycles are included.','This standalone courtyard preview is not a Godot game capture.'],previews:['scene-room-2x.png','scene-detail-4x.png','scene-night-2x.png','walk-study-4x.png','walk-in-place-4x.gif','courtyard-walk-2x.gif'],gifs:{framesEach:320,fps:40,durationSecondsEach:8,renderer:'The emitted offline viewer runtime with embedded PNGs',sequences:['Four directions of both walk cycles at fixed positions and 4× native pixels.','Movement around the courtyard at 2× native pixels, with local shambler patrols.']}};
  fs.writeFileSync(path.join(outputDir,'verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(error);process.exitCode=1;});
