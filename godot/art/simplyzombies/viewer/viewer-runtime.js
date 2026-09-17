(function () {
  'use strict';
  const B = window.ART_BUNDLE;
  const M = B.manifest;
  const canvas = document.getElementById('scene');
  const ctx = canvas.getContext('2d', {alpha:false});
  const inspect = document.getElementById('inspect');
  const ic = inspect.getContext('2d');
  const byId = new Map(M.assets.map(a => [a.id,a]));
  const scene = M.scene || {};
  const character = M.character || {};
  const movement = character.movement || {};
  const walkSpeed = movement.speed || character.walkSpeed || 45;
  const world = {width:M.canvas?.width || scene.width || 480,height:M.canvas?.height || scene.height || 320,tile:M.canvas?.tileSize || 32};
  const imageCache = new Map();
  const props = (scene.props || []).map(p => ({...p,state:0}));
  const allLayerRefs = character.layers || M.assets.filter(a => a.layer && a.layer !== 'weapon').map(a => a.id);
  const layerAssets = allLayerRefs.map(ref => typeof ref === 'string' ? byId.get(ref) : {...byId.get(ref.asset),...ref}).filter(Boolean).sort((a,b) => (a.z||0)-(b.z||0));
  const enabled = new Set(layerAssets.filter(a => !a.equippable || a.defaultEnabled).map(a => a.id));
  const keys = new Set();
  const spawn = scene.spawn || [world.width/2,world.height/2];
  const player = {x:spawn[0],y:spawn[1],angle:character.initialAngle??Math.PI/2,moveAngle:character.initialAngle??Math.PI/2,facing:'s',moving:false,strideClock:0};
  const effects = [];
  const gear = new Set();
  const npcs = (scene.actors || []).map(npc => ({...npc,moving:false,strideClock:0,patrolTarget:1}));
  const state = {zoom:2,paused:false,walkInPlace:false,autoTurn:false,turnStart:0,night:false,time:0,selected:M.assets[0]?.id,near:null,ready:false,lastStatus:'',pointer:null,weapon:'',lastShot:-10,demo:false,lastDemo:0,shots:0};
  const directions = character.directionCount===4 ? ['e','s','w','n'] : ['e','se','s','sw','w','nw','n','ne'];
  const directionNames={s:'south',e:'east',n:'north',w:'west',se:'southeast',sw:'southwest',ne:'northeast',nw:'northwest'};
  const controls = {};
  ['loading','auto-turn','walk-cycle','pause','night','assets','asset-name','asset-meta','asset-count','scene-state','scale-note','motion-state','interact','interaction-hint','announcement','weapon','shoot','burst','effects-demo','gear','asset-search','asset-category'].forEach(id => controls[id] = document.getElementById(id));
  function announce(text) { controls.announcement.textContent = text; }
  function title(a) { return a.label || a.name || a.id.replace(/[_-]+/g,' '); }
  function direction(angle) { const count=directions.length;return directions[((Math.round(angle/(Math.PI*2/count))%count)+count)%count]; }
  function actorDirection(actor=player) { return direction(actor.moving ? actor.moveAngle : actor.angle); }
  function framesFor(a,anim,dir) {
    const f = a.animations || a.frames || {};
    if (Array.isArray(f)) return f;
    let result = f[anim+'_'+dir] || f[anim]?.[dir] || f[anim];
    if (!result && anim === 'idle') {
      const walk = f['walk_'+dir] || f.walk?.[dir];
      if (walk) result = [Array.isArray(walk) ? walk[0] : walk];
    }
    result = result || f['idle_'+dir] || f.idle?.[dir] || f.idle || f.walk || f.play || f.loop || f.running || f.activate || Object.values(f)[0] || [0];
    if (result && !Array.isArray(result) && typeof result === 'object' && !result.path && !result.rect && result.x === undefined) result = result.e || Object.values(result)[0];
    return Array.isArray(result) ? result : [result];
  }
  function frame(a,anim='idle',dir='e',time=state.time,fpsOverride) {
    const seq = framesFor(a,anim,dir);
    const fps = fpsOverride || (typeof a.fps === 'object' ? (a.fps[anim] || movement.fps || 8) : (a.fps || movement.fps || 8));
    const index=a.holdLastFrame ? Math.min(seq.length-1,Math.floor(time*fps)) : Math.floor(time*fps)%seq.length;
    let item = seq[index] ?? 0;
    if (typeof item === 'string') item = {path:item};
    const key = (typeof item === 'object' && (item.path || item.file)) || a.path;
    const image = imageCache.get(key);
    if (!image) return null;
    const dims = a.frameSize || a.frame_size || [image.naturalWidth || image.width,image.naturalHeight || image.height];
    const w = dims[0], h = dims[1];
    const cols = a.columns || Math.max(1,Math.floor((image.naturalWidth || image.width)/w));
    let rect;
    if (typeof item === 'number') rect = [(item%cols)*w,Math.floor(item/cols)*h,w,h];
    else if (item.rect) rect = item.rect;
    else if (item.x !== undefined) rect = [item.x,item.y || 0,item.width || item.w || w,item.height || item.h || h];
    else rect = [0,0,image.naturalWidth || image.width,image.naturalHeight || image.height];
    return {image,rect,w:rect[2],h:rect[3],item};
  }
  function drawAsset(target,a,x,y,options={}) {
    if (!a) return;
    const f = frame(a,options.anim || 'idle',options.dir || 'e',options.time === undefined ? state.time : options.time,options.fps);
    if (!f) return;
    const scale = options.scale === undefined ? (a.scale || 1) : options.scale;
    const anchor = options.anchor || a.anchor || a.pivot || [f.w/2,f.h];
    const offset = options.offset || [0,0];
    target.save();
    target.imageSmoothingEnabled = false;
    target.translate(Math.round(x+offset[0]),Math.round(y+offset[1]));
    if (options.rotation) target.rotate(options.rotation);
    if (options.flip) target.scale(-1,1);
    if (options.opacity !== undefined) target.globalAlpha = options.opacity;
    target.drawImage(f.image,...f.rect,Math.round(-anchor[0]*scale),Math.round(-anchor[1]*scale),Math.round(f.w*scale),Math.round(f.h*scale));
    target.restore();
  }
  function drawActor(target,x,y,actor=player) {
    const dir = actorDirection(actor);
    const anim = actor.moving || (actor===player && state.walkInPlace) ? 'walk' : 'idle';
    const activeLayers = layerAssets.filter(a => enabled.has(a.id));
    const replacedIds = new Set(activeLayers.flatMap(a => a.replaces || []));
    const equipped = activeLayers.filter(a => !replacedIds.has(a.id));
    for(const id of gear){const a=byId.get(id);if(a)equipped.push(a);}
    equipped.sort((a,b) => (a.z_by_direction?.[dir]??a.z??0)-(b.z_by_direction?.[dir]??b.z??0));
    for (const a of equipped) {
      const offset = a.offset || [0,0];
      const follows = a.rotateWithAim || (character.directionMode === 'rotate' && a.rotateWithAim !== false && a.layer !== 'legs');
      const moveRotate = a.rotateWithMovement;
      const rotation = follows ? actor.angle + (a.angleOffset || 0) : moveRotate ? actor.moveAngle + (a.angleOffset || 0) : 0;
      const hasDirectional = Object.keys(a.animations || a.frames || {}).some(k => /_(e|se|s|sw|w|nw|n|ne)$/.test(k));
      const flip = !follows && !moveRotate && !hasDirectional && a.flipWithAim !== false && Math.cos(actor.angle)<0;
      const mirrorOffset = flip || (a.mirrorOffsetWithAim && Math.cos(actor.angle)<0);
      drawAsset(target,a,x,y,{offset:[mirrorOffset ? -offset[0] : offset[0],offset[1]],anim,dir,rotation,flip,time:anim==='walk'?actor.strideClock:0,fps:movement.fps});
    }
    if(actor===player) drawWeapon(target,x,y);
  }
  function weaponPose() {
    const a=byId.get(state.weapon);if(!a)return null;
    const x=player.x+(Math.cos(player.angle)<0?-5:5),y=player.y-12;
    const angle=player.angle,grip=a.grip||[6,8],muzzle=a.muzzle||[a.size?.[0]||24,8];
    const flip=Math.cos(angle)<0;const dx=muzzle[0]-grip[0],dy=(muzzle[1]-grip[1])*(flip?-1:1);
    return {a,x,y,angle,flip,grip,mx:x+Math.cos(angle)*dx-Math.sin(angle)*dy,my:y+Math.sin(angle)*dx+Math.cos(angle)*dy};
  }
  function drawWeapon(target,x,y){
    const p=weaponPose();if(!p)return;
    const f=frame(p.a,'idle','e',0);if(!f)return;
    target.save();target.translate(Math.round(x+p.x-player.x),Math.round(y+p.y-player.y));target.rotate(p.angle);if(p.flip)target.scale(1,-1);
    target.imageSmoothingEnabled=false;target.drawImage(f.image,...f.rect,-p.grip[0],-p.grip[1],f.w,f.h);target.restore();
  }
  function spawnEffect(asset,x,y,angle=0){
    const a=byId.get(asset);if(!a)return;
    const seq=framesFor(a,'idle','e'),fps=typeof a.fps==='object'?a.fps.idle||12:a.fps||12;
    effects.push({asset,x,y,angle,start:state.time,duration:seq.length/fps,light:/muzzle|explosion/.test(asset)});
    if(effects.length>96)effects.splice(0,effects.length-96);
  }
  function shoot(target){
    if(state.paused || state.time-state.lastShot<.14)return;
    const p=weaponPose();if(!p)return;
    state.lastShot=state.time;state.shots++;
    const kind=p.a.weaponClass || p.a.id;
    const melee=/knife|hatchet|crowbar|bat/.test(kind),bow=/bow/.test(kind);
    const vp=viewport();const point=target|| (state.pointer?{x:state.pointer.screenX/state.zoom+vp.x,y:state.pointer.screenY/state.zoom+vp.y}:{x:p.mx+Math.cos(p.angle)*100,y:p.my+Math.sin(p.angle)*100});
    if(melee){spawnEffect(M.showcase.effects.wood,p.mx+Math.cos(p.angle)*8,p.my+Math.sin(p.angle)*8);return;}
    if(!bow){
      spawnEffect(/shotgun/.test(kind)?M.showcase.effects.shotgun:/rifle|smg/.test(kind)?M.showcase.effects.rifle:M.showcase.effects.pistol,p.mx,p.my,p.angle);
      spawnEffect(M.showcase.effects.casing,p.x,p.y,0);
    }
    const bloody=npcs.some(n=>Math.hypot(n.x-point.x,n.y-12-point.y)<23);
    spawnEffect(bloody?M.showcase.effects.blood:bow?M.showcase.effects.wood:M.showcase.effects.concrete,Math.max(8,Math.min(world.width-8,point.x)),Math.max(8,Math.min(world.height-8,point.y)));
    announce(bow?'Arrow impact preview':'Shot '+state.shots);
  }
  function explosion(){if(state.paused)return;spawnEffect(M.showcase.effects.explosion,504,292);}
  function buildWorkshopControls(){
    const empty=document.createElement('option');empty.value='';empty.textContent='Unequipped';controls.weapon.append(empty);
    for(const id of M.showcase.weapons){const a=byId.get(id);if(!a)continue;const opt=document.createElement('option');opt.value=id;opt.textContent=title(a).replace(/held |world /ig,'');controls.weapon.append(opt);}
    controls.weapon.value=state.weapon;controls.weapon.addEventListener('change',()=>{state.weapon=controls.weapon.value;selectAsset(state.weapon||'survivor');});
    controls.shoot.addEventListener('click',()=>shoot());controls.burst.addEventListener('click',explosion);
    controls['effects-demo'].addEventListener('click',()=>{state.demo=!state.demo;if(state.demo&&!state.weapon){state.weapon=M.showcase.weapons[0];controls.weapon.value=state.weapon;}controls['effects-demo'].setAttribute('aria-pressed',String(state.demo));});
    for(const id of M.showcase.gear||[]){const a=byId.get(id);if(!a)continue;const row=document.createElement('label');row.className='gear-option';const input=document.createElement('input');input.type='checkbox';input.dataset.gear=id;input.addEventListener('change',()=>input.checked?gear.add(id):gear.delete(id));const text=document.createElement('span');text.textContent=title(a);row.append(input,text);controls.gear.append(row);}
    const categories=['All categories',...new Set(M.assets.map(a=>a.category||'artwork'))];
    for(const c of categories){const opt=document.createElement('option');opt.value=c;opt.textContent=c;controls['asset-category'].append(opt);}
    controls['asset-category'].value='All categories';
    function filter(){const q=controls['asset-search'].value.toLowerCase(),c=controls['asset-category'].value;let count=0;document.querySelectorAll('[data-asset]').forEach(el=>{const a=byId.get(el.dataset.asset);el.hidden=!(title(a).toLowerCase().includes(q)&&(c==='All categories'||a.category===c));if(!el.hidden)count++;});controls['asset-count'].textContent=count+' / '+M.assets.length;}
    controls['asset-search'].addEventListener('input',filter);controls['asset-category'].addEventListener('change',filter);
  }
  function tileAsset(id,x,y,size) {
    const a=byId.get(id); if (!a) return;
    const f=frame(a,'idle','e',0); if (!f) return;
    ctx.drawImage(f.image,...f.rect,Math.round(x),Math.round(y),size,size);
  }
  function groundAt(x,y) {
    let ids = scene.groundVariants?.length ? scene.groundVariants : [scene.ground];
    for (const zone of scene.zones || []) if(x>=zone.x && y>=zone.y && x<zone.x+zone.width && y<zone.y+zone.height) ids = zone.variants || [zone.asset];
    const hash = Math.abs(((x/world.tile)*73856093)^((y/world.tile)*19349663));
    return ids[hash%ids.length];
  }
  function drawWorld() {
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = '#0c100a';
    ctx.fillRect(0,0,canvas.width,canvas.height);
    const vp = viewport();
    ctx.save();
    ctx.scale(state.zoom,state.zoom);
    ctx.translate(-vp.x,-vp.y);
    for(let y=0;y<world.height;y+=world.tile) for(let x=0;x<world.width;x+=world.tile) tileAsset(groundAt(x,y),x,y,world.tile);
    for(const d of scene.decals || []) drawAsset(ctx,byId.get(d.asset),d.x,d.y,{...d,time:0});
    const drawables = [];
    for(const w of scene.walls || []) drawables.push({y:w.sortY ?? w.y,draw:() => drawAsset(ctx,byId.get(w.asset),w.x,w.y,w)});
    for(const p of props) drawables.push({y:p.sortY ?? p.y,draw:() => {
      drawAsset(ctx,byId.get(p.states?.[p.state] || p.asset),p.x,p.y,p);
      if(p===state.near) {
        ctx.fillStyle='#dde3b6';ctx.font='7px monospace';ctx.textAlign='center';ctx.fillText('E',Math.round(p.x),Math.round(p.y+12));
      }
    }});
    for(const npc of npcs) drawables.push({y:npc.y,draw:() => {
      const a=byId.get(npc.asset);drawAsset(ctx,a,npc.x,npc.y,{...npc,anim:npc.moving?'walk':'idle',time:npc.moving?npc.strideClock:0});
    }});
    drawables.push({y:player.y,draw:()=>drawActor(ctx,player.x,player.y)});
    drawables.sort((a,b)=>a.y-b.y).forEach(d=>d.draw());
    for(const fx of effects) drawAsset(ctx,byId.get(fx.asset),fx.x,fx.y,{time:state.time-fx.start,rotation:fx.angle||0});
    ctx.restore();
    if(state.night) {
      ctx.fillStyle='rgba(5,13,20,.66)';ctx.fillRect(0,0,canvas.width,canvas.height);
      const px=(player.x-vp.x)*state.zoom,py=(player.y-vp.y-18)*state.zoom;
      const glow=ctx.createRadialGradient(px,py,0,px,py,92*state.zoom);
      glow.addColorStop(0,'rgba(225,211,154,.2)');glow.addColorStop(.42,'rgba(164,156,100,.10)');glow.addColorStop(1,'rgba(156,166,85,0)');
      ctx.fillStyle=glow;ctx.fillRect(0,0,canvas.width,canvas.height);
    }
    for(const fx of effects) if(fx.light && state.time-fx.start<.09){
      ctx.fillStyle='rgba(255,206,98,.055)';ctx.fillRect(0,0,canvas.width,canvas.height);
    }
  }
  function viewport() {
    const vw=canvas.width/state.zoom,vh=canvas.height/state.zoom;
    const x=vw>=world.width ? (world.width-vw)/2 : Math.max(0,Math.min(world.width-vw,player.x-vw/2));
    const y=vh>=world.height ? (world.height-vh)/2 : Math.max(0,Math.min(world.height-vh,player.y-vh/2));
    return {x:Math.round(x),y:Math.round(y),width:vw,height:vh};
  }
  function renderInspect() {
    const a=byId.get(state.selected);if(!a)return;
    ic.clearRect(0,0,inspect.width,inspect.height);ic.imageSmoothingEnabled=false;
    const dir=actorDirection();const anim=framesFor(a,'walk',dir).length>1?'walk':'idle';const f=frame(a,anim,dir);if(!f)return;
    const scale=Math.max(.25,Math.floor(Math.min(136/f.w,136/f.h)));
    drawAsset(ic,a,80,80,{anchor:[f.w/2,f.h/2],anim,dir,scale});
  }
  function spriteThumbnail(a,c) {
    const cx=c.getContext('2d');const f=frame(a,'idle','e',0);if(!f)return;
    const scale=Math.min(40/f.w,40/f.h);cx.imageSmoothingEnabled=false;
    drawAsset(cx,a,24,24,{anchor:[f.w/2,f.h/2],time:0,scale});
  }
  function selectAsset(id) {
    state.selected=id;const a=byId.get(id);if(!a)return;
    controls['asset-name'].textContent=title(a);
    const f=frame(a,'idle','e',0);const animations=a.animations || a.frames || {};
    const count=Array.isArray(animations)?animations.length:Object.values(animations).reduce((n,list)=>n+(Array.isArray(list)?list.length:1),0);
    controls['asset-meta'].textContent=(f?f.w+' × '+f.h+' px':'')+' · '+(a.category || a.layer || 'artwork')+(count>1?' · '+count+' indexed frames':'');
    document.querySelectorAll('[data-asset]').forEach(el=>el.setAttribute('aria-pressed',String(el.dataset.asset===id)));
    inspect.setAttribute('aria-label',title(a)+' pixel art preview');renderInspect();
  }
  function buildControls() {
    document.querySelectorAll('[data-facing]').forEach(btn=>btn.addEventListener('click',()=>setFacing(btn.dataset.facing)));
    document.querySelectorAll('[data-zoom]').forEach(btn=>btn.addEventListener('click',()=>{state.zoom=Number(btn.dataset.zoom);document.querySelectorAll('[data-zoom]').forEach(el=>el.setAttribute('aria-pressed',String(el===btn)));controls['scale-note'].textContent=state.zoom+'× pixel scale';announce('Pixel scale '+state.zoom+' times');}));
    controls['auto-turn'].addEventListener('click',()=>{state.autoTurn=!state.autoTurn;state.turnStart=state.time;state.pointer=null;controls['auto-turn'].setAttribute('aria-pressed',String(state.autoTurn));refreshStatus();});
    controls['walk-cycle'].addEventListener('click',()=>{state.walkInPlace=!state.walkInPlace;player.moving=false;controls['walk-cycle'].setAttribute('aria-pressed',String(state.walkInPlace));refreshStatus();announce(state.walkInPlace?'Walking in place':'Normal movement');});
    controls.pause.addEventListener('click',togglePause);
    controls.night.addEventListener('change',()=>state.night=controls.night.checked);
    controls.interact.addEventListener('click',interact);
    controls['asset-count'].textContent=M.assets.length+' assets';
    for(const a of M.assets) {
      const btn=document.createElement('button');btn.type='button';btn.className='asset-row';btn.dataset.asset=a.id;btn.setAttribute('aria-pressed','false');
      const thumb=document.createElement('canvas');thumb.width=48;thumb.height=48;thumb.setAttribute('aria-hidden','true');
      const name=document.createElement('span');name.textContent=title(a);const cat=document.createElement('span');cat.className='category';cat.textContent=a.category || a.layer || '';
      btn.append(thumb,name,cat);btn.addEventListener('click',()=>selectAsset(a.id));controls.assets.append(btn);spriteThumbnail(a,thumb);
    }
    buildWorkshopControls();
    selectAsset(state.selected);
  }
  function togglePause() {state.paused=!state.paused;controls.pause.textContent=state.paused?'Resume':'Pause';controls.pause.setAttribute('aria-pressed',String(state.paused));refreshStatus();announce(state.paused?'Preview paused':'Preview resumed');}
  function stopAutoTurn() {state.autoTurn=false;controls['auto-turn'].setAttribute('aria-pressed','false');}
  function setFacing(dir) {
    const angles={e:0,s:Math.PI/2,w:Math.PI,n:-Math.PI/2};
    stopAutoTurn();state.pointer=null;player.angle=angles[dir]??Math.PI/2;player.facing=dir;
    refreshStatus();drawWorld();renderInspect();announce('Facing '+directionNames[dir]);
  }
  function refreshStatus() {
    const facing=actorDirection();
    const motion=state.paused?'paused':state.walkInPlace?'walking in place':player.moving?'walking':'standing';
    const text='Survivor · '+directionNames[facing]+' · '+motion;
    if(text!==state.lastStatus) {controls['scene-state'].textContent=text;controls['motion-state'].textContent=motion.toUpperCase();state.lastStatus=text;}
    document.querySelectorAll('[data-facing]').forEach(el=>el.setAttribute('aria-pressed',String(el.dataset.facing===facing)));
  }
  function updateInteraction() {
    let near=null,best=scene.interactionDistance || 44;
    for(const p of props) if(p.states?.length>1) {const dist=Math.hypot(player.x-p.x,player.y-p.y);if(dist<best){near=p;best=dist;}}
    if(near===state.near)return;
    state.near=near;refreshInteraction();
  }
  function refreshInteraction() {
    const p=state.near;controls.interact.disabled=!p;
    if(!p){controls.interact.textContent='Open container';controls['interaction-hint'].textContent=props.some(p=>p.states?.length>1)?'Move up to a container to inspect its states.':'Container states are shown in the asset browser.';return;}
    const next=(p.state+1)%p.states.length;
    controls.interact.textContent=(p.stateLabels?.[next]?'Show '+p.stateLabels[next]:next===0?'Close container':next===1?'Open container':'Show searched');
    controls['interaction-hint'].textContent=title(byId.get(p.states[p.state]))+' · press E to change state';
  }
  function interact() {const p=state.near;if(!p)return;p.state=(p.state+1)%p.states.length;refreshInteraction();announce(title(byId.get(p.states[p.state])));}
  function applyPointerAim() {
    if(!state.pointer)return;
    const vp=viewport();
    const x=state.pointer.screenX/state.zoom+vp.x;
    const y=state.pointer.screenY/state.zoom+vp.y;
    const origin=character.aimOrigin || [0,-20];
    const mirrored=character.directionMode!=='rotate' && x<player.x;
    player.angle=Math.atan2(y-(player.y+origin[1]),x-(player.x+(mirrored?-origin[0]:origin[0])));
  }
  function pointerAim(event) {
    stopAutoTurn();
    const rect=canvas.getBoundingClientRect();
    state.pointer={screenX:(event.clientX-rect.left)/rect.width*canvas.width,screenY:(event.clientY-rect.top)/rect.height*canvas.height};
    applyPointerAim();
  }
  canvas.addEventListener('pointermove',pointerAim);
  canvas.addEventListener('pointerdown',event=>{pointerAim(event);canvas.focus({preventScroll:true});if(event.button===0 || event.pointerType==='touch')shoot();});
  const keyAliases={arrowup:'w',arrowleft:'a',arrowdown:'s',arrowright:'d'};
  window.addEventListener('keydown',event=>{
    const editable=['INPUT','SELECT','TEXTAREA'].includes(event.target.tagName);if(editable)return;
    let key=event.key.toLowerCase();key=keyAliases[key]||key;
    if(['w','a','s','d',' ','e','f'].includes(key)){event.preventDefault();if(key===' '&&!event.repeat)togglePause();else if(key==='e'&&!event.repeat)interact();else if(key==='f'&&!event.repeat)shoot();else keys.add(key);}
  });
  window.addEventListener('keyup',event=>{let key=event.key.toLowerCase();keys.delete(keyAliases[key]||key);});
  window.addEventListener('blur',()=>keys.clear());
  document.addEventListener('visibilitychange',()=>{if(document.hidden)keys.clear();});
  document.querySelectorAll('[data-key]').forEach(btn=>{
    const release=()=>keys.delete(btn.dataset.key);
    btn.addEventListener('pointerdown',event=>{event.preventDefault();keys.add(btn.dataset.key);btn.setPointerCapture(event.pointerId);});
    btn.addEventListener('pointerup',release);btn.addEventListener('pointercancel',release);btn.addEventListener('lostpointercapture',release);
  });
  function blocked(x,y) {
    for(const r of scene.collisions || []) if(x>=r.x&&x<=r.x+r.width&&y>=r.y&&y<=r.y+r.height)return true;
    return false;
  }
  function updateNPC(npc,dt) {
    npc.moving=false;
    if(!npc.patrolA || !npc.patrolB || dt<=0)return;
    const target=npc.patrolTarget?npc.patrolB:npc.patrolA;
    const dx=target[0]-npc.x,dy=target[1]-npc.y,remaining=Math.hypot(dx,dy);
    if(remaining<.001){npc.patrolTarget=1-npc.patrolTarget;return;}
    const speed=npc.speed || 14,distance=Math.min(remaining,speed*dt);
    const nx=npc.x+dx/remaining*distance,ny=npc.y+dy/remaining*distance;
    if(blocked(nx,ny))return;
    npc.x=nx;npc.y=ny;npc.dir=direction(Math.atan2(dy,dx));npc.moving=true;
    npc.strideClock+=distance/speed;
    if(distance>=remaining-.001)npc.patrolTarget=1-npc.patrolTarget;
  }
  function update(dt) {
    if(state.paused)return;
    dt=Math.max(0,dt);
    state.time+=dt;
    for(let i=effects.length-1;i>=0;i--)if(state.time-effects[i].start>=effects[i].duration)effects.splice(i,1);
    if(state.demo && state.time-state.lastDemo>.7){state.lastDemo=state.time;shoot({x:480+(state.shots%3)*15,y:292});if(state.shots%4===0)explosion();}
    const dx=Number(keys.has('d'))-Number(keys.has('a'));const dy=Number(keys.has('s'))-Number(keys.has('w'));
    const oldX=player.x,oldY=player.y;
    if(dx||dy){
      stopAutoTurn();player.moveAngle=Math.atan2(dy,dx);player.facing=direction(player.moveAngle);
      const speed=state.walkInPlace?0:walkSpeed*dt;
      const nx=Math.max(12,Math.min(world.width-12,player.x+Math.cos(player.moveAngle)*speed));
      const ny=Math.max(36,Math.min(world.height-12,player.y+Math.sin(player.moveAngle)*speed));
      if(!blocked(nx,player.y))player.x=nx;if(!blocked(player.x,ny))player.y=ny;
      if(!state.pointer)player.angle=player.moveAngle;
    }
    const distance=Math.hypot(player.x-oldX,player.y-oldY);
    player.moving=distance>.000001;
    if(state.walkInPlace)player.strideClock+=dt;
    else if(player.moving)player.strideClock+=distance/walkSpeed;
    for(const npc of npcs)updateNPC(npc,dt);
    if(state.autoTurn)player.angle=Math.PI/2-Math.floor((state.time-state.turnStart)/.9)*Math.PI/2;
    applyPointerAim();player.facing=actorDirection();updateInteraction();refreshStatus();
  }
  let last=0;
  function tick(now) {const dt=Math.min(.05,last?(now-last)/1000:0);last=now;if(state.ready){update(dt);drawWorld();renderInspect();}window.requestAnimationFrame(tick);}
  Promise.all(Object.entries(B.images).map(([key,info])=>new Promise((resolve,reject)=>{
    const img=new Image();img.onload=()=>{imageCache.set(key,img);resolve();};img.onerror=()=>reject(new Error('Could not decode '+key));img.src=info.src;
  }))).then(()=>{
    buildControls();state.ready=true;controls.loading.hidden=true;refreshStatus();refreshInteraction();updateInteraction();drawWorld();window.requestAnimationFrame(tick);
    // Small public inspection surface, also used by the pack's verification script.
    window.ArtSample={manifest:M,state,player,npcs,effects,gear,shoot,explosion,spawnEffect,weaponPose,props,frame,framesFor,byId,enabled,drawWorld,drawActor,drawAsset,renderInspect,update,viewport,selectAsset,interact,togglePause,setFacing,direction,actorDirection,blocked};
  }).catch(error=>{controls.loading.replaceChildren();const message=document.createElement('span');message.textContent='The artwork could not be loaded.';const detail=document.createElement('small');detail.textContent=error.message;controls.loading.append(message,detail);controls.loading.setAttribute('role','alert');});
})();
