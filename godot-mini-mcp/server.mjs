import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { spawn } from 'node:child_process';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, randomUUID } from 'node:crypto';

const home = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name)+1] : fallback;
const project = await fs.realpath(option('--project', path.join(home,'../godot-pixel-demo')));
const godot = path.resolve(option('--godot', path.join(home,'../.tools/godot/Godot_v4.7.2-stable_win64_console.exe')));
await fs.access(path.join(project,'project.godot'));
const jobs = path.join(project,'.godot','ai-bridge');
await fs.mkdir(jobs,{recursive:true});
const sha = data => createHash('sha256').update(data).digest('hex');
const sceneSchema = z.string().default('main.tscn');
const safeScene = async scene => {
  const relative = scene.replace(/^res:\/\//,'');
  if (!relative.endsWith('.tscn')) throw Error('Only .tscn scenes are supported');
  const file = await fs.realpath(path.resolve(project,relative));
  const rel = path.relative(project,file);
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw Error('Scene is outside the configured project');
  return {file,res:'res://'+rel.replaceAll('\\','/')};
};
function run(extra, timeout=45000) {
  return new Promise((resolve,reject) => {
    const child=spawn(godot,['--headless','--path',project,...extra],{cwd:project,windowsHide:true,shell:false});
    let output='', truncated=false;
    const capture=data=>{if(output.length<250000) output+=data.toString(); else truncated=true;};
    child.stdout.on('data',capture); child.stderr.on('data',capture);
    const timer=setTimeout(()=>{child.kill();reject(Error('Godot timed out'));},timeout);
    child.on('error',e=>{clearTimeout(timer);reject(e);});
    child.on('close',code=>{clearTimeout(timer);resolve({code,output,truncated});});
  });
}
function diagnostics(result) {
  const lines=result.output.split(/\r?\n/);
  const errors=lines.filter(line=>/SCRIPT ERROR|Parse Error|^ERROR:|at:|GDScript::reload/.test(line)).slice(0,24);
  return {ok:result.code===0 && errors.length===0,exit_code:result.code,errors,log_truncated:result.truncated};
}
async function bridge(request) {
  const file=path.join(jobs,randomUUID()+'.json');
  await fs.writeFile(file,JSON.stringify(request));
  try {
    const result=await run(['--script',path.join(home,'bridge.gd'),'--',file]);
    const marker=result.output.split(/\r?\n/).find(line=>line.startsWith('@@MCP@@'));
    if (!marker) throw Error(JSON.stringify(diagnostics(result))+' '+result.output.slice(-1200));
    const data=JSON.parse(marker.slice(7));
    const diagnostic=diagnostics(result);
    if(!diagnostic.ok) return {...data,ok:false,diagnostic};
    return data;
  } finally {await fs.unlink(file).catch(()=>{});}
}
// Serialize project operations: concurrent mutations/imports must not race.
let queue=Promise.resolve();
function serial(action) { const pending=queue.then(action); queue=pending.catch(()=>{}); return pending; }
const response=data=>({content:[{type:'text',text:JSON.stringify(data)}],isError:data.ok===false});
function register(name,description,schema,action) {
  server.registerTool(name,{description,inputSchema:schema},params=>serial(async()=>{
    try{return response(await action(params));}catch(e){return response({ok:false,error:e.message});}
  }));
}
const server=new McpServer({name:'godot-mini-mcp',version:'0.1.0'});
register('godot_scene_summary','Read a compact scene tree with hash; no full file dump.',{scene:sceneSchema,max_nodes:z.number().int().min(1).max(80).default(40)},async params=>{
  const scene=await safeScene(params.scene);
  return {...await bridge({command:'summary',scene:scene.res,max_nodes:params.max_nodes}),sha256:sha(await fs.readFile(scene.file))};
});
register('godot_scene_batch','Batch add native nodes or set typed properties; saves once with backup and expected hash. Use on simple owned scenes; inherited/nested prefab edits are not supported.',{
  scene:sceneSchema,expected_sha256:z.string().regex(/^[a-f0-9]{64}$/),
  operations:z.array(z.object({kind:z.enum(['add_node','set_property']),parent:z.string().optional(),path:z.string().optional(),name:z.string().optional(),type:z.string().optional(),property:z.string().optional(),value:z.union([z.string(),z.number(),z.boolean(),z.array(z.number()).max(4)]).optional()})).min(1).max(64)
},async params=>{
  const scene=await safeScene(params.scene);
  const bytes=await fs.readFile(scene.file);
  if(sha(bytes)!==params.expected_sha256) return {ok:false,error:'Scene changed; obtain a fresh summary first'};
  // Scope this prototype to standalone owned scenes; avoid flattening inherited instances.
  if(/\binstance\s*=/.test(bytes.toString())) return {ok:false,error:'Inherited or nested scenes are not supported in v0.1'};
  const backup=path.join(jobs,randomUUID()+'.backup.tscn');
  await fs.writeFile(backup,bytes);
  const result=await bridge({command:'batch',scene:scene.res,operations:params.operations});
  if(!result.ok) await fs.writeFile(scene.file,bytes);
  return {...result,sha256:sha(await fs.readFile(scene.file)),backup:path.relative(project,backup).replaceAll('\\','/')};
});
register('godot_validate','Import project and check every GDScript; return bounded errors only.',{},async()=>{
  const result=await run(['--editor','--import']);
  const checks=[];
  async function scan(dir){for(const entry of await fs.readdir(dir,{withFileTypes:true})){
    if(entry.name.startsWith('.') || entry.name==='node_modules')continue;
    const file=path.join(dir,entry.name);
    if(entry.isDirectory())await scan(file);
    else if(entry.name.endsWith('.gd'))checks.push(file);
  }}
  await scan(project);
  const combined=diagnostics(result);
  for(const script of checks){const d=diagnostics(await run(['--check-only','--script',script]));combined.ok&&=d.ok;combined.errors.push(...d.errors);}
  combined.errors=combined.errors.slice(0,24);
  return {...combined,scripts_checked:checks.length};
});
register('godot_run_probe','Run scene headlessly for a bounded number of frames; verifies startup/runtime errors, not graphics or complete gameplay.',{frames:z.number().int().min(1).max(600).default(120)},async({frames})=>{
  const result=await run(['--quit-after',String(frames),'--fixed-fps','60']);
  return {...diagnostics(result),frames_requested:frames,signals:result.output.split(/\r?\n/).filter(line=>line.startsWith('DEMO_')).slice(0,6)};
});
await server.connect(new StdioServerTransport());
