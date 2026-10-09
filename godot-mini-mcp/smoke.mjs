import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { promises as fs } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const home=path.dirname(fileURLToPath(import.meta.url));
const scene=path.join(home,'../godot-pixel-demo/main.tscn');
const original=await fs.readFile(scene);
const client=new Client({name:'workflow-verification',version:'1.0'});
const transport=new StdioClientTransport({command:process.execPath,args:[path.join(home,'server.mjs')],stderr:'pipe'});
const report={tests:[],metrics:{}};
const call=async(name,args={})=>{
 const start=performance.now();
 const raw=await client.callTool({name,arguments:args});
 const value=JSON.parse(raw.content[0].text);
 report.tests.push({tool:name,ok:value.ok,elapsed_ms:Math.round(performance.now()-start),response_chars:raw.content[0].text.length});
 return value;
};
try{
 await client.connect(transport);
 const {tools}=await client.listTools();
 assert.equal(tools.length,4);
 report.metrics.godot_tool_definitions_chars=JSON.stringify(tools).length;
 const cocos=JSON.parse(await fs.readFile(path.join(home,'../cocos-cli/mcp-tools.json'),'utf8'));
 report.metrics.cocos_tool_definitions_chars=JSON.stringify(cocos).length;
 report.metrics.cocos_tools=cocos.length;report.metrics.godot_tools=tools.length;
 assert.equal((await call('godot_validate')).ok,true);
 const before=await call('godot_scene_summary');
 assert.equal(before.ok,true);
 const batch=await call('godot_scene_batch',{expected_sha256:before.sha256,operations:[
   {kind:'add_node',parent:'.',name:'MCPMarker',type:'Node2D'},
   {kind:'set_property',path:'MCPMarker',property:'position',value:[120,80]}
 ]});
 assert.equal(batch.ok,true);
 const after=await call('godot_scene_summary');
 assert.deepEqual(after.nodes.find(n=>n.path==='MCPMarker').position,[120,80]);
 const bytes=await fs.readFile(scene);
 assert.equal((await call('godot_scene_batch',{expected_sha256:before.sha256,operations:[{kind:'add_node',name:'Stale'}]})).ok,false);
 assert.equal((await call('godot_scene_batch',{expected_sha256:after.sha256,operations:[{kind:'add_node',name:'ShouldRollback'},{kind:'set_property',path:'Missing',property:'position',value:[1,2]}]})).ok,false);
 assert.deepEqual(await fs.readFile(scene),bytes);
 const outside=path.join(home,'outside-test.tscn');
 await fs.writeFile(outside,original);
 try{assert.equal((await call('godot_scene_summary',{scene:'../godot-mini-mcp/outside-test.tscn'})).ok,false);}finally{await fs.unlink(outside);}
 assert.equal((await call('godot_run_probe',{frames:120})).ok,true);
 const bad=path.join(home,'../godot-pixel-demo/intentionally_invalid.gd');
 await fs.writeFile(bad,'extends Node\nfunc broken(\n');
 try{assert.equal((await call('godot_validate')).ok,false);}finally{await fs.unlink(bad);await fs.unlink(bad+'.uid').catch(()=>{});}
 await fs.writeFile(scene,original);
 assert.equal((await call('godot_validate')).ok,true);
 report.ok=true;
 await fs.writeFile(path.join(home,'verification.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify(report,null,2));
}finally{
 await fs.writeFile(scene,original);
 await client.close();
}
