#!/usr/bin/env node
'use strict';
// Build a completely offline viewer from the pack's real asset files.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const base = path.resolve(__dirname, '../pack');
const manifestPath = path.resolve(process.argv[2] || path.join(base, 'manifest.json'));
const outputPath = path.resolve(process.argv[3] || path.join(base, 'simplyzombies-walk-preview.html'));
const manifestDir = path.dirname(manifestPath);
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const assets = Array.isArray(manifest.assets) ? manifest.assets : Object.entries(manifest.assets || {}).map(([id,a]) => ({id,...a}));
const images = {};
const ids = new Set();
function embed(file) {
  if (!file || typeof file !== 'string') return;
  if (images[file]) return;
  if (/^(https?:|data:)/i.test(file)) throw new Error('Expected a local PNG, got '+file);
  const disk = path.resolve(manifestDir, file);
  const png = fs.readFileSync(disk);
  if (png.subarray(0,8).toString('hex') !== '89504e470d0a1a0a') throw new Error('Not a PNG: '+file);
  images[file] = {src:'data:image/png;base64,'+png.toString('base64'),width:png.readUInt32BE(16),height:png.readUInt32BE(20)};
}
function collectFrames(value) {
  if (typeof value === 'string') embed(value);
  else if (Array.isArray(value)) value.forEach(collectFrames);
  else if (value && typeof value === 'object') {
    if (value.path || value.file) embed(value.path || value.file);
    else Object.values(value).forEach(collectFrames);
  }
}
for (const a of assets) {
  if (!a.id || ids.has(a.id)) throw new Error('Missing or duplicate asset id: '+a.id);
  ids.add(a.id);
  a.path = a.path || a.file || a.sprite;
  embed(a.path);
  collectFrames(a.animations || a.frames);
  if (!a.path && !a.animations && !a.frames) throw new Error('Asset has no image or frames: '+a.id);
  if (a.path) a.imageSize = [images[a.path].width, images[a.path].height];
}
function requireAsset(id, context) {
  if (id && !ids.has(id)) throw new Error('Unknown asset '+id+' in '+context);
}
const scene = manifest.scene || {};
requireAsset(scene.ground, 'scene.ground');
(scene.groundVariants || []).forEach(id => requireAsset(id,'groundVariants'));
for (const key of ['walls','props','decals','zones','actors']) for (const p of scene[key] || []) {
  requireAsset(p.asset, 'scene.'+key);
  (p.states || []).forEach(id => requireAsset(id,'scene.'+key+' states'));
  (p.variants || []).forEach(id => requireAsset(id,'scene.'+key+' variants'));
}
for (const key of ['layers','weapons']) for (const id of (manifest.character || {})[key] || []) requireAsset(typeof id === 'string' ? id : id.asset,'character.'+key);
manifest.assets = assets;
const runtime = fs.readFileSync(path.join(__dirname,'viewer-runtime.js'),'utf8');
new vm.Script(runtime, {filename:'viewer-runtime.js'});
const template = fs.readFileSync(path.join(__dirname,'viewer-template.html'),'utf8');
const bundle = JSON.stringify({manifest,images}).replace(/</g,'\\u003c');
const html = template.replace('/*__ASSET_BUNDLE__*/', 'window.ART_BUNDLE = '+bundle+';').replace('/*__VIEWER_RUNTIME__*/',runtime);
fs.mkdirSync(path.dirname(outputPath), {recursive:true});
fs.writeFileSync(outputPath,html);
console.log(JSON.stringify({output:outputPath,assets:assets.length,embeddedPNGs:Object.keys(images).length,bytes:Buffer.byteLength(html)},null,2));
