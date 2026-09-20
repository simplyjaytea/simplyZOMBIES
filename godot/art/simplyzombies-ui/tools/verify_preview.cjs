// Uses the same canvas drawing and input code as the self-contained HTML.
// Requires @napi-rs/canvas; NODE_PATH may point at the installed dependency directory.
const fs=require('fs'),path=require('path'),assert=require('assert');
const {createCanvas,loadImage,GlobalFonts}=require('@napi-rs/canvas');
const {UIFieldKit}=require('./viewer.cjs');
const root=path.resolve(__dirname,'..'),art=root;
const manifest=JSON.parse(fs.readFileSync(path.join(art,'manifest.json')));
async function main(){
 GlobalFonts.registerFromPath(path.join(art,'fonts/VT323-Regular.ttf'),'FieldPixel');
 const images={};for(const s of manifest.sprites)images[s.id]=await loadImage(path.join(art,s.path));
 for(const p of fs.readdirSync(path.join(root,'demo-assets')).filter(p=>p.endsWith('.png')))images[path.basename(p,'.png')]=await loadImage(path.join(root,'demo-assets',p));
 const canvas=createCanvas(960,600),ui=new UIFieldKit(canvas,images,manifest);
 const results=[];
 function ok(name,condition){assert(condition,name);results.push(name);}
 function action(label){const h=ui.hits.find(h=>h.label===label);assert(h,label);ui.click(h.x+2,h.y+2);ui.draw(200);}
 ui.draw(0);action('WATER BOTTLE');ok('Inventory selection updates inspected item',ui.selected===1);
 action('Use');ok('Action feedback changes',ui.message.includes('water bottle'));
 action('Components');ok('Mode navigation works',ui.mode==='Components');
 action('Show hints');ok('Checkbox toggles',ui.check===false);
 action('Ambient audio');ok('Switch toggles',ui.audio===false);
 ok('Disabled button is not actionable',!ui.hits.some(h=>h.label==='Unavailable'));
 action('Reduced motion');ok('Reduced motion toggles',ui.reduced===true);
 ok('Reduced saved tick resolves to completed frame',ui.animation('saved_tick',0,0,1,0)===2);
 ui.reduced=false;
 ok('Looping animation advances',ui.animation('busy',0,0,1,125)===1);
 ok('Looping animation wraps',ui.animation('busy',0,0,1,500)===0);
 ok('One-shot holds final frame',ui.animation('saved_tick',0,0,1,1000)===3);
 ui.focus=-1;ui.key('Tab');ok('Tab focuses a control',ui.focus===0);ui.key('Enter');ok('Enter activates a control',ui.mode==='Inventory');
 ui.key('Escape');ui.draw(0);ok('Escape opens pause',ui.mode==='Pause');action('Resume');ok('Resume returns to inventory',ui.mode==='Inventory');
 for(const mode of ['Inventory','Components','Motion','Pause']){
  ui.setMode(mode);ui.selected=0;ui.focus=-1;ui.hover=-1;ui.draw(180);
  fs.writeFileSync(path.join(root,'previews','native-'+mode.toLowerCase()+'.png'),canvas.toBuffer('image/png'));
  ok(mode+' hit regions stay inside canvas',ui.hits.every(h=>h.x>=0&&h.y>=0&&h.x+h.w<=960&&h.y+h.h<=600));
 }
 const frameDir=path.join(root,'previews','motion-frames');fs.mkdirSync(frameDir,{recursive:true});
 ui.setMode('Motion');
 for(let i=0;i<150;i++){
  const t=i*20;ui.replayAt.item_ping=Math.floor(t/1500)*1500;ui.replayAt.saved_tick=Math.floor(t/1500)*1500;ui.draw(t);
  const frame=createCanvas(960,390);frame.getContext('2d').drawImage(canvas,0,116,960,390,0,0,960,390);
  fs.writeFileSync(path.join(frameDir,`frame-${String(i).padStart(3,'0')}.png`),frame.toBuffer('image/png'));
 }
 fs.writeFileSync(path.join(root,'docs','preview-validation.json'),JSON.stringify({renderer:'@napi-rs/canvas; shared browser canvas renderer',checks:results,checks_passed:results.length,browser_window_tested:false,note:'Native browser canvas drawing is shared; browser DOM/font loading has not been exercised in a browser window in this environment.'},null,2)+'\n');
 console.log(JSON.stringify({checks:results.length,result:'PASS',rendered_modes:4,motion_frames:150}));
}
main().catch(e=>{console.error(e);process.exit(1)});
