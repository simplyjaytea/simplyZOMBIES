/* The browser viewer and offline rendering checks share this exact canvas renderer. */
class UIFieldKit {
  constructor(canvas, images, manifest) {
    this.canvas=canvas; this.ctx=canvas.getContext('2d'); this.images=images;
    this.manifest=manifest; this.assets=Object.fromEntries(manifest.assets.map(a=>[a.id,a]));
    this.mode='Inventory'; this.reduced=false; this.audio=true; this.check=true;
    this.selected=0; this.hover=-1; this.focus=-1; this.down=false; this.hits=[];
    this.message='Select an item to inspect.'; this.started=0; this.replayAt={};
    this.items=[['bandage-roll','BANDAGE ROLL','Clean cloth for binding a wound.','Clean',3],['water-bottle','WATER BOTTLE','A sealed bottle of drinking water.','Sealed',1],['tinned-meat','TINNED MEAT','A sturdy tin. Food for the road.','Sealed',1],['antiseptic','ANTISEPTIC','A small bottle for cleaning wounds.','Intact',1],['apple','APPLE','Something fresh, for a change.','Fresh',2],null,['kitchen-knife','KITCHEN KNIFE','A simple, well-used blade.','Worn',1],['flashlight','FLASHLIGHT','A pocket light with a scratched lens.','Working',1],null,null,null,null,['wood-planks','WOOD PLANKS','Useful timber, tied for carrying.','Dry',1],['first-aid-kit','FIRST AID KIT','Medical supplies in a weathered case.','Intact',1],['cloth','CLOTH','A folded length of salvageable fabric.','Clean',2],['scrap','SCRAP','Loose metal parts for repairs.','Worn',3],['mre','FIELD RATION','A sealed meal for a long walk.','Sealed',1]];
  }
  image(key,x,y,w,h) { const im=this.images[key]; if(im)this.ctx.drawImage(im,Math.round(x),Math.round(y),w,h); }
  text(text,x,y,size=20,color='#c8c2a6',align='left') {
    const c=this.ctx;c.font=`${size}px FieldPixel`;c.fillStyle=color;c.textAlign=align;c.textBaseline='alphabetic';c.fillText(text,Math.round(x),Math.round(y));
  }
  wrap(text,x,y,width,size=20,color='#c8c2a6') {
    let line='';this.ctx.font=`${size}px FieldPixel`;
    for(const word of text.split(' ')){const test=line?line+' '+word:word;if(this.ctx.measureText(test).width>width&&line){this.text(line,x,y,size,color);y+=size+3;line=word;}else line=test;}
    this.text(line,x,y,size,color);return y+size+3;
  }
  nine(id,x,y,w,h) {
    const a=this.assets[id],im=this.images[id],m=a.nine_slice_ltrb;
    if(!im)return;const sw=im.width,sh=im.height,[l,t,r,b]=m;
    const sx=[0,l,sw-r,sw],sy=[0,t,sh-b,sh],dx=[x,x+l,x+w-r,x+w],dy=[y,y+t,y+h-b,y+h];
    for(let row=0;row<3;row++)for(let col=0;col<3;col++){
      const iw=sx[col+1]-sx[col],ih=sy[row+1]-sy[row],ow=dx[col+1]-dx[col],oh=dy[row+1]-dy[row];
      if(iw>0&&ih>0&&ow>0&&oh>0)this.ctx.drawImage(im,sx[col],sy[row],iw,ih,dx[col],dy[row],ow,oh);
    }
  }
  area(x,y,w,h,action,label) {this.hits.push({x,y,w,h,action,label});return this.hits.length-1;}
  button(label,x,y,w,h,action,{disabled=false,danger=false,active=false}={}) {
    let i=-1;if(!disabled)i=this.area(x,y,w,h,action,label);
    const hover=i>=0&&i===this.hover;
    const state=disabled?'disabled':hover&&this.down?'pressed':active||hover?'hover':danger?'danger':'normal';
    this.nine('button_'+state,x,y,w,h);
    this.text(label,x+w/2,y+h/2+6,22,disabled?'#807a63':danger?'#d8794e':active?'#e1b65b':'#c8c2a6','center');
    if(i>=0&&i===this.focus)this.nine('button_focus',x,y,w,h);
  }
  panel(title,x,y,w,h,id='panel_standard') {this.nine(id,x,y,w,h);this.text(title,x+16,y+29,26);this.nine('divider',x+16,y+40,w-32,2);}
  toggle(label,x,y,checked,action) {
    const i=this.area(x,y,186,28,action,label);
    this.image(checked?'control_checkbox_on':'control_checkbox_off',x,y+4,16,16);
    this.text(label,x+24,y+21,18,i===this.hover?'#e1b65b':'#9a9278');
    if(i===this.focus)this.nine('button_focus',x-3,y,189,28);
  }
  setMode(mode) {this.mode=mode;this.focus=-1;this.hover=-1;this.message=mode==='Inventory'?'Select an item to inspect.':'Asset preview — no game state is changed.';}
  slot(index,x,y,size=48) {
    const item=this.items[index];const i=this.area(x,y,size,size,()=>{if(item){this.selected=index;this.message='Inspecting '+item[1].toLowerCase()+'.';}},item?item[1]:'Empty slot');
    this.nine(index===this.selected?'slot_selected':i===this.hover?'slot_hover':'slot_empty',x,y,size,size);
    if(item){this.image('item-'+item[0],x+(size-32)/2,y+(size-32)/2,32,32);if(item[4]>1)this.text(String(item[4]),x+size-6,y+size-5,18,'#c8c2a6','right');}
    if(i===this.focus)this.nine('button_focus',x,y,size,size);
  }
  animation(id,x,y,scale,now) {
    const a=this.assets[id];let frame;
    if(this.reduced)frame=a.reduced_motion_frame;
    else {const raw=Math.floor(Math.max(0,now-(this.replayAt[id]||0))/1000*a.fps);frame=a.loop?raw%4:Math.min(3,raw);}
    this.image(id+'_'+frame,x,y,a.size[0]*scale,a.size[1]*scale);
    return frame;
  }
  inventory() {
    this.nine('panel_dialog',20,66,920,46);this.text('INVENTORY',38,98,30);this.text('|  YOU',213,98,30,'#8a9a5b');
    this.text('Select an item',920,95,18,'#807a63','right');
    this.panel('EQUIPMENT',20,118,280,400);this.panel('CARRIED',310,118,348,400);this.panel('INSPECT',668,118,272,400);
    const left=['HEAD','EYES','FACE','GLOVES','BELT','PRIMARY'],right=['VEST','TORSO','LEGS','FEET','BACK','SECONDARY'];
    for(let r=0;r<6;r++){
      const y=169+r*45;
      this.text(left[r],34,y+24,15,'#a59e82');this.nine('slot_empty',86,y,38,38);
      this.nine('slot_empty',208,y,38,38);this.text(right[r],250,y+24,14,'#a59e82');
      if(r===4)this.image('glyph_belt',93,y+7,24,24);
    }
    this.image('survivor',120,218,96,144);
    this.text('LEFT ARM',160,395,18,'#c8c2a6','center');
    this.text('A shallow scrape.',36,475,18,'#cf7048');
    this.text('It aches when you move.',36,496,18,'#cf7048');
    this.text('POCKETS',330,181,18);for(let i=0;i<6;i++)this.slot(i,330+i*51,191);
    this.text('BELT',330,267,18);for(let i=0;i<6;i++)this.slot(i+6,330+i*51,277);
    this.text('CANVAS PACK',330,351,18);for(let i=0;i<18;i++)this.slot(i+12,330+(i%6)*51,361+Math.floor(i/6)*51);
    const item=this.items[this.selected];this.nine('panel_inset',688,172,232,132);
    this.image('item-'+item[0],772,206,64,64);
    this.text(item[1],688,338,24);this.nine('divider',688,350,232,2);
    this.wrap(item[2],688,378,224,20);this.text('Condition: '+item[3],688,432,20);this.text('Stack: '+item[4],688,456,20);
    for(const [i,title] of ['Use','Move','Drop'].entries())this.button(title,684+i*81,476,78,30,()=>{this.message='Preview: '+title.toLowerCase()+' '+item[1].toLowerCase()+'.';},{danger:title==='Drop'});
    this.nine('panel_standard',310,530,348,66);
    for(let i=0;i<6;i++){this.slot(i,330+i*51,540,46);this.text(String(i+1),333+i*51,550,14);}
    this.wrap(this.message,22,550,270,18,'#9a9278');
  }
  components() {
    this.panel('BUTTON STATES',20,90,282,222);this.panel('SETTINGS',318,90,306,222);this.panel('CURSORS',640,90,300,222);
    this.button('Resume',36,148,120,40,()=>{this.message='Normal button activated.';});
    this.button('Drop',166,148,120,40,()=>{this.message='Danger button activated.';},{danger:true});
    this.button('Unavailable',36,202,250,40,()=>{},{disabled:true});
    this.button('Selected',36,256,250,40,()=>{this.message='Selected state activated.';},{active:true});
    this.toggle('Show hints',336,147,this.check,()=>{this.check=!this.check;});
    this.toggle('Reduced motion',336,193,this.reduced,()=>{this.reduced=!this.reduced;});
    this.image(this.audio?'control_toggle_on':'control_toggle_off',336,252,48,24);
    const au=this.area(330,242,276,46,()=>{this.audio=!this.audio;},'Ambient audio');
    this.text('Ambient audio',400,271,22,au===this.hover?'#e1b65b':'#c8c2a6');
    for(const [i,key] of ['arrow','hand','move','blocked'].entries()){
      this.image('control_cursor_'+key,669+i*65,167,48,48);this.text(key,693+i*65,241,17,'#9a9278','center');
    }
    this.text('EQUIPMENT & ACTION GLYPHS',20,354,24);
    const glyphs=this.manifest.assets.filter(a=>a.category==='glyphs');
    for(let i=0;i<glyphs.length;i++){
      const x=20+(i%16)*57,y=376+Math.floor(i/16)*86;
      this.image(glyphs[i].id,x+5,y,48,48);this.text(glyphs[i].id.slice(6),x+28,y+67,14,'#9a9278','center');
      this.area(x,y,56,76,()=>{this.message=glyphs[i].id+' · 24 px + 16 px variant';},glyphs[i].id);
    }
    this.text(this.message,20,572,18,'#9a9278');
  }
  motion(now) {
    this.text('SMALL SIGNALS. CLEAR FEEDBACK.',20,100,28);
    const ids=['focus_pulse','busy','item_ping','saved_tick'];
    for(let i=0;i<4;i++){
      const x=20+i*232,id=ids[i],a=this.assets[id];
      this.panel(id.replace('_',' ').toUpperCase(),x,126,216,380);
      this.animation(id,x+(216-a.size[0]*4)/2,220,4,now);
      this.text(a.loop?'LOOP':'ONE SHOT',x+108,390,18,'#c99a3f','center');
      this.text(a.fps+' FPS  /  4 FRAMES',x+108,416,18,'#9a9278','center');
      this.button('Replay',x+20,448,176,38,()=>{this.replayAt[id]=this.now;});
    }
    this.text('Hard pixel edges. No blur or bloom. Toggle reduced motion for static states.',20,548,20,'#9a9278');
  }
  pause() {
    this.nine('panel_dialog',310,88,340,432);this.text('PAUSED',480,138,34,'#c8c2a6','center');
    for(const [i,title] of ['Resume','Save','Load','Settings','Quit to title'].entries())this.button(title,348,165+i*61,264,46,()=>{
      if(title==='Resume')this.setMode('Inventory');else if(title==='Settings')this.setMode('Components');else this.message='Preview: '+title.toLowerCase()+'.';
    },{danger:title==='Quit to title'});
    this.text('Returning to title saves your progress.',480,548,20,'#9a9278','center');
    this.text(this.message,480,577,18,'#9a9278','center');
  }
  draw(now=0) {
    this.now=now;const c=this.ctx;c.imageSmoothingEnabled=false;c.fillStyle='#0b0e0a';c.fillRect(0,0,960,600);this.hits=[];
    this.text('simplyZOMBIES',20,35,30);this.text('UI FIELD KIT',217,35,20,'#807a63');
    for(const [i,title] of ['Inventory','Components','Motion','Pause'].entries())this.button(title,524+i*104,14,100,34,()=>{this.setMode(title);},{active:this.mode===title});
    if(this.mode==='Inventory')this.inventory();else if(this.mode==='Components')this.components();else if(this.mode==='Motion')this.motion(now);else this.pause();
    this.toggle('Reduced motion',744,562,this.reduced,()=>{this.reduced=!this.reduced;});
  }
  point(x,y) {return this.hits.findIndex(h=>x>=h.x&&y>=h.y&&x<h.x+h.w&&y<h.y+h.h);}
  click(x,y) {const i=this.point(x,y);if(i>=0){this.focus=i;this.hits[i].action();}}
  key(key,shift=false) {
    if(key==='Tab'){this.focus=(this.focus+(shift?-1:1)+this.hits.length)%this.hits.length;return true;}
    if((key==='Enter'||key===' ')&&this.focus>=0&&this.hits[this.focus]){this.hits[this.focus].action();return true;}
    if(key==='Escape'){this.setMode(this.mode==='Pause'?'Inventory':'Pause');return true;}return false;
  }
}
if(typeof module!=='undefined')module.exports={UIFieldKit};
