// Exercise the actual terrain/editor/export code with lightweight canvas adapters.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const context={};for(const n of ['drawImage','putImageData','beginPath','moveTo','lineTo','stroke','fill','arc','strokeRect','strokeText','fillText','save','restore','clearRect','fillRect','scale','translate','setLineDash'])context[n]=()=>{};
context.createImageData=(w,h)=>({data:new Uint8ClampedArray(w*h*4)});
const elements=new Map(),get=id=>{if(!elements.has(id))elements.set(id,{value:({seed:20261009,sea:36,radius:7,tool:'raise',place:'测试地点'})[id],checked:true,width:id==='mini'?220:1200,height:id==='mini'?150:750,getContext:()=>context,addEventListener(){},appendChild(){},replaceChildren(){},showModal(){},close(){},getBoundingClientRect:()=>({left:0,top:0,width:1200,height:750})});return elements.get(id);};
const sandbox={document:{getElementById:get,createElement:()=>({getContext:()=>context})},console,Float32Array,Uint8ClampedArray,Blob,setTimeout,URL};
vm.createContext(sandbox);for(const file of ['map-physics.cjs','world-core.cjs','atlas.js','ai-ui.js'])vm.runInContext(fs.readFileSync(__dirname+'/'+file,'utf8'),sandbox);
vm.runInContext(`
const original=heights.slice();create();
if(!heights.every((v,i)=>v===original[i]))throw Error('Seed regeneration is not deterministic');
const oldCenter=heightAt(80,50);snapshot();brush({x:80,y:50});
if(!(heightAt(80,50)>oldCenter))throw Error('Raise brush did not modify terrain');
el('undo').onclick();if(heightAt(80,50)!==oldCenter)throw Error('Undo did not restore heights');
el('tool').value='lower';brush({x:80,y:50});
if(!(heightAt(80,50)<oldCenter))throw Error('Lower brush failed');
el('tool').value='smooth';brush({x:80,y:50});
if(!heights.every(v=>Number.isFinite(v)&&v>=0&&v<=1))throw Error('Invalid terrain after editing');
player={x:32,y:24};draw();
if(!el('coords').textContent.includes('32.0, 24.0'))throw Error('Minimap position did not update');
const saved=JSON.parse(JSON.stringify(data()));
if(saved.heights.length!==16000||saved.worldBounds.width!==16000)throw Error('Export shape mismatch');
if(!saved.places.every(validPoint))throw Error('Invalid settlement position');
AtlasCore.validate(saved);
AtlasCore.validateLinks(saved);
const broken=JSON.parse(JSON.stringify(saved));Object.values(broken.maps)[0].entrances[1].target.mapId='missing-map';let linkRejected=false;try{AtlasCore.validateLinks(broken);}catch(e){linkRejected=true;}if(!linkRejected)throw Error('Broken map link accepted');
if(saved.version!==2||saved.biomes.length!==16000||saved.generation.jobs.length!==saved.places.length)throw Error('AI contract missing');
for(const b of ['desert','grassland','tundra','snow','mountain'])if(!saved.biomes.includes(b))throw Error('Expected biome absent: '+b);
for(const p of saved.places){const m=saved.maps[p.mapId];if(!m||m.worldLocationId!==p.id||m.biome!==p.biome||m.interiors.length!==3)throw Error('Location linking failed');AtlasCore.validateMap(m);for(const e of m.entrances.filter(e=>e.kind==='door'))if(!m.interiors.some(i=>i.id===e.target.mapId&&i.entrances.some(n=>n.target.mapId===m.id)))throw Error('Interior return link failed');}
const beforePaint=ecology.biomes[50*W+80];snapshot();el('tool').value='biome';el('biome-paint').value='volcanic';brush({x:80,y:50});draw();
if(data().biomes[50*W+80]!=='volcanic')throw Error('AI biome override failed');el('undo').onclick();if(data().biomes[50*W+80]!==beforePaint)throw Error('Biome undo failed');
const invalid=JSON.parse(JSON.stringify(Object.values(saved.maps)[0]));invalid.layers.collision[invalid.spawn.y*invalid.width+invalid.spawn.x]=1;let rejected=false;try{AtlasCore.validateMap(invalid);}catch(e){rejected=true;}if(!rejected)throw Error('Blocked entrances accepted');
adopt(saved);if(JSON.stringify(data().biomes)!==JSON.stringify(saved.biomes))throw Error('Biome import roundtrip failed');
currentLocation=saved.places[0];el('physics-demo').onclick();moveTo({x:4.5,y:4.5},'walk');if(localPlayer.z!==0||!motionMessage.includes('跳'))throw Error('UI box walk collision failed');moveTo({x:4.5,y:4.5},'jump');if(localPlayer.z!==.8||localPlayer.platform!=='box')throw Error('UI jump landing failed');moveTo({x:4.55,y:4.5},'walk');if(localPlayer.z!==.8)throw Error('UI platform support failed');activeMap=null;
console.log('Biomes: '+[...new Set(saved.biomes)].join(', '));console.log('Linked maps: '+saved.places.length+' outdoor + '+saved.places.length*3+' indoor');
`,sandbox);
console.log('PASS: terrain editing, biome override/undo, AI JSON roundtrip, linked local/interior maps, reachable entrances and rejection of blocked spawn.');
fs.writeFileSync(__dirname+'/sample-world.json',vm.runInContext('JSON.stringify(data())',sandbox));

