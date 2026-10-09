const assert=require('node:assert/strict');
(async()=>{const base='http://127.0.0.1:8791';async function get(p){const r=await fetch(base+p);assert.equal(r.status,200);return r.json();}
const contract=await get('/api/contract'),w=await get('/api/world'),jobs=await get('/api/jobs');assert.equal(contract.version,2);assert.equal(jobs.jobs.length,w.places.length);
const id=w.places[0].mapId,m=await get('/api/maps/'+id);const interior=await get('/api/maps/'+m.interiors[0].id);assert.equal(interior.parentMapId,id);
let r=await fetch(base+'/api/maps/'+id,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(m)});assert.equal(r.status,200);
const bad=JSON.parse(JSON.stringify(m));bad.layers.collision[bad.spawn.y*bad.width+bad.spawn.x]=1;r=await fetch(base+'/api/maps/'+id,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(bad)});assert.equal(r.status,400);assert.deepEqual((await get('/api/maps/'+id)).layers.collision,m.layers.collision);
const badPhysics=JSON.parse(JSON.stringify(m));badPhysics.physics.surfaces[0].height=-1;r=await fetch(base+'/api/maps/'+id,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(badPhysics)});assert.equal(r.status,400);assert.deepEqual((await get('/api/maps/'+id)).physics,m.physics);
r=await fetch(base+'/api/world',{method:'PUT',headers:{'Content-Type':'application/json',Origin:'https://unrelated.example'},body:'{}'});assert.equal(r.status,403);
console.log('PASS: contract, world/jobs, outdoor/interior lookup, valid map write, invalid map rejection without state mutation, same-origin protection.');})().catch(e=>{console.error(e);process.exitCode=1;});
