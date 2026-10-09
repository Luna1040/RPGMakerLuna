const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.join(__dirname,'comfy-map-trials/desert-layered-v1'),spec=JSON.parse(fs.readFileSync(path.join(root,'layered-workflow.json'),'utf8'));
const graph={},shared={'329':'1','330':'2','331':'3'};
for(let i=0;i<spec.tasks.length;i++){
 const task=spec.tasks[i],source=JSON.parse(fs.readFileSync(path.join(root,task.id,'workflow.json'),'utf8'));
 const remap=id=>shared[id]||String((i+1)*1000+Number(id));
 for(const [id,n]of Object.entries(source)){
  const target=remap(id);if(shared[id]&&graph[target])continue;
  const node=JSON.parse(JSON.stringify(n));for(const [key,v]of Object.entries(node.inputs))if(Array.isArray(v)&&v.length===2&&typeof v[0]==='string'&&source[v[0]])node.inputs[key]=[remap(v[0]),v[1]];
  node._meta={title:task.id+' / '+n.class_type};if(n.class_type==='SaveImage')node.inputs.filename_prefix='CodexMapLayeredWorkflow/'+task.id;
  // Ground variants consume the newly generated first tile, instead of a stale uploaded image.
  if(n.class_type==='TextEncodeQwenImageEditPlus'&&task.kind==='ground'&&i>0)node.inputs.image1=['1350',0];
  graph[target]=node;
 }
}
// Remove unused raw-reference image loaders in the ground branches.
const reachable=new Set();function visit(id){assert.ok(graph[id],'Missing graph dependency '+id);if(reachable.has(id))return;reachable.add(id);for(const v of Object.values(graph[id].inputs))if(Array.isArray(v)&&v.length===2&&typeof v[0]==='string'&&graph[v[0]])visit(v[0]);}
for(const [id,n]of Object.entries(graph))if(n.class_type==='SaveImage')visit(id);for(const id of Object.keys(graph))if(!reachable.has(id))delete graph[id];
const visiting=new Set(),done=new Set();function dag(id){if(done.has(id))return;assert.ok(!visiting.has(id),'Cyclic graph');visiting.add(id);for(const v of Object.values(graph[id].inputs))if(Array.isArray(v)&&v.length===2&&typeof v[0]==='string')dag(v[0]);visiting.delete(id);done.add(id);}for(const id of Object.keys(graph))dag(id);
assert.equal(Object.values(graph).filter(n=>n.class_type==='SaveImage').length,9);
assert.equal(Object.values(graph).filter(n=>n.class_type==='UNETLoader').length,1);
fs.writeFileSync(path.join(root,'layered-generation-api.json'),JSON.stringify(graph,null,2));
console.log('PASS: packaged ComfyUI API graph, '+Object.keys(graph).length+' nodes, 9 saved outputs, shared model/encoder/VAE, complete acyclic links.');
