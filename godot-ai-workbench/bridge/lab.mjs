import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {Codex} from '@openai/codex-sdk';
export const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const codexPath=process.env.CODEX_BIN || 'C:/Users/11043/AppData/Local/OpenAI/Codex/bin/9691020b546a15b2/codex.exe';
const obj=properties=>({type:'object',additionalProperties:false,properties,required:Object.keys(properties)});
const str={type:'string'},int={type:'integer'};
export const schema=obj({title:str,premise:str,rows:{type:'array',items:str},spawn:obj({x:int,y:int}),npcs:{type:'array',items:obj({name:str,role:str,x:int,y:int,dialogue:str})},quest:obj({title:str,steps:{type:'array',items:str}})});
export const prompt='生成一个原创中文海边村庄RPG设计。只返回指定JSON，不要使用工具或读文件。rows严格16行，每行24字符，只能用 . 草地、~水、#建筑、=道路；spawn和全部3个NPC坐标在可行走的.或=上，互不重叠，所有NPC从spawn四向可达。水在右侧，路网贯穿村庄。NPC含女骑士、铁匠和渔夫，各一句中文台词；支线任务3阶段。坐标从0开始。';
export function validate(d){
 if(!Array.isArray(d.rows)||d.rows.length!==16||d.rows.some(r=>typeof r!=='string'||r.length!==24||/[^.~#=]/.test(r)))throw Error('地图尺寸或符号不合格');
 if(d.npcs.length!==3||d.quest.steps.length!==3)throw Error('NPC/任务数量不合格');
 const walk=(x,y)=>x>=0&&y>=0&&x<24&&y<16&&'.='.includes(d.rows[y][x]);
 if(!walk(d.spawn.x,d.spawn.y))throw Error('出生点不可通行');
 const queue=[[d.spawn.x,d.spawn.y]],seen=new Set(queue.map(String));
 for(let i=0;i<queue.length;i++)for(const [dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]){const [x,y]=queue[i],n=[x+dx,y+dy];if(walk(...n)&&!seen.has(String(n))){seen.add(String(n));queue.push(n);}}
 const positions=new Set([`${d.spawn.x},${d.spawn.y}`]);
 for(const n of d.npcs){const k=`${n.x},${n.y}`;if(!seen.has(k)||positions.has(k))throw Error('NPC不可达或重叠: '+n.name);positions.add(k);}
 return {reachableCells:seen.size,npcsReachable:3,mapSize:[24,16]};
}
export async function sdkRun(onEvent=()=>{}){
 const api=new Codex({codexPathOverride:codexPath});
 const thread=api.startThread({workingDirectory:root,skipGitRepoCheck:true,sandboxMode:'read-only',approvalPolicy:'never'});
 const stream=await thread.runStreamed(prompt,{outputSchema:schema,signal:AbortSignal.timeout(240000)});
 let text='',usage=null,count=0;
 for await(const e of stream.events){count++;onEvent(e.type);if(e.type==='item.completed'&&e.item.type==='agent_message')text=e.item.text;if(e.type==='turn.completed')usage=e.usage;if(e.type==='turn.failed'||e.type==='error')throw Error(JSON.stringify(e));}
 const data=JSON.parse(text);return {data,validation:validate(data),threadId:thread.id,usage,events:count};
}
export async function appRun(onEvent=()=>{}){
 const child=spawn(codexPath,['app-server'],{cwd:root,windowsHide:true,stdio:['pipe','pipe','pipe']});
 const pending=new Map();let next=1,events=0,text='',usage=null,doneResolve,doneReject;
 const done=new Promise((r,j)=>{doneResolve=r;doneReject=j;});done.catch(()=>{});
 const send=m=>child.stdin.write(JSON.stringify(m)+'\n');
 const request=(method,params)=>new Promise((resolve,reject)=>{const id=next++;pending.set(id,{resolve,reject});send({id,method,params});});
 const timeout=setTimeout(()=>doneReject(Error('App Server timed out')),240000);
 child.on('error',doneReject);child.stderr.on('data',()=>{});
 const lines=createInterface({input:child.stdout});
 lines.on('line',line=>{let m;try{m=JSON.parse(line);}catch{return;}
  if(m.id!==undefined && !m.method){const p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);}return;}
  if(m.id!==undefined&&m.method){send({id:m.id,error:{code:-32601,message:'Interactive requests are unsupported in this read-only experiment'}});return;}
  events++;onEvent(m.method);
  if(m.method==='item/completed'&&m.params.item.type==='agentMessage')text=m.params.item.text;
  if(m.method==='thread/tokenUsage/updated')usage=m.params.tokenUsage;
  if(m.method==='turn/completed'){m.params.turn.status==='completed'?doneResolve():doneReject(Error(JSON.stringify(m.params.turn)));}
 });
 try{
  await Promise.race([request('initialize',{clientInfo:{name:'godot_generation_lab',version:'0.1.0'}}),done]);send({method:'initialized',params:{}});
  const started=await Promise.race([request('thread/start',{cwd:root,sandbox:'read-only',approvalPolicy:'never',ephemeral:true}),done]);
  await request('turn/start',{threadId:started.thread.id,input:[{type:'text',text:prompt}],outputSchema:schema});
  await done;const data=JSON.parse(text);return {data,validation:validate(data),threadId:started.thread.id,usage,events};
 }finally{clearTimeout(timeout);lines.close();child.stdin.end();child.kill();}
}
export async function generate(mode,onEvent=()=>{}){
 const start=Date.now();const result=await(mode==='sdk'?sdkRun(onEvent):appRun(onEvent));
 result.mode=mode;result.durationMs=Date.now()-start;result.timestamp=new Date().toISOString();
 await mkdir(path.join(root,'results'),{recursive:true});await writeFile(path.join(root,'results',mode+'.json'),JSON.stringify(result,null,2));
 await writeFile(path.join(root,'results','latest.json'),JSON.stringify(result,null,2));return result;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const mode=process.argv[2]||'sdk';try{const r=await generate(mode,e=>console.log(e));console.log(JSON.stringify({mode,title:r.data.title,validation:r.validation,durationMs:r.durationMs,usage:r.usage}));}catch(e){console.error(e);process.exitCode=1;}
}
