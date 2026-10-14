import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {loadGames,catalogWriter} from './catalog-store.mjs';
import {artInstructions} from './art-pipeline.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
let project=path.join(root,'godot-belt-map');
const homeProject=path.join(root,'godot-creator-home');
let homeMode=process.argv.includes('--home'),selected='knight';
const data=path.join(root,'.game-assistant');
await mkdir(data,{recursive:true});
let games=[{id:'knight',title:'晨钟城 · 姬骑士',description:'横版动作 RPG · 城镇 / 古塔 / 队友',directory:'godot-belt-map',status:'ready',cover:'godot-belt-map/assets/dawn-city/city.png'}];
const catalogFile=path.join(root,'created-games/catalog.json');
games=await loadGames(catalogFile,games);
const writeGames=catalogWriter(catalogFile);
function saveGames(){return writeGames(games);}
await saveGames();
const token=randomBytes(32).toString('hex');
const state={status:'starting',text:'',events:[],threadId:null,turnId:null,revision:0,error:null,gameId:selected};
let next=1,game=null,restarting=false,active=false;
const pending=new Map();
const godot=process.env.GODOT_BIN||path.join(root,'.tools/godot/Godot_v4.7.2-stable_win64.exe');
const child=spawn(process.env.CODEX_BIN||'codex',['app-server','--listen','stdio://'],{cwd:root,windowsHide:true,stdio:['pipe','pipe','pipe']});
const send=m=>child.stdin.write(JSON.stringify(m)+'\n');
function rpc(method,params){return new Promise((resolve,reject)=>{
 const id=next++;const timer=setTimeout(()=>{pending.delete(id);reject(Error(`${method} timeout`));},60000);
 pending.set(id,{resolve,reject,timer});send({id,method,params});
});}
function event(message){state.events.push(message);state.events=state.events.slice(-35);const g=games.find(g=>g.id===selected);if(g&&active){g.progress=message;saveGames().catch(console.error);}}
function fail(error){state.status='failed';state.error=String(error);active=false;event(state.error);const g=games.find(g=>g.id===selected);if(g?.status==='creating'){g.status='failed';saveGames().catch(()=>{});}}
child.on('error',fail);
child.on('exit',code=>{for(const p of pending.values()){clearTimeout(p.timer);p.reject(Error('Codex disconnected'));}pending.clear();fail(`Codex exited: ${code}`);});
child.stderr.on('data',b=>writeFile(path.join(data,'codex-stderr.log'),b,{flag:'a'}).catch(()=>{}));
createInterface({input:child.stdout}).on('line',line=>{
 let m;try{m=JSON.parse(line);}catch{return;}
 if(m.id!==undefined&&!m.method){const p=pending.get(m.id);if(p){clearTimeout(p.timer);pending.delete(m.id);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);}return;}
 if(m.id!==undefined&&m.method){
  event('需要额外交互：'+m.method+'；本轮未自动批准。');
  send({id:m.id,error:{code:-32601,message:'Interactive request unsupported by game bridge. Report the limitation to the user.'}});return;
 }
 const p=m.params||{};
 if(p.threadId&&state.threadId&&p.threadId!==state.threadId)return;
 if(m.method==='item/agentMessage/delta')state.text=(state.text+(p.delta||'')).slice(-24000);
 if(m.method==='item/started')event('开始：'+p.item?.type+(p.item?.command?' '+p.item.command.slice(0,180):''));
 if(m.method==='item/completed'&&p.item?.type==='agentMessage'&&p.item.text){state.text=p.item.text;const g=games.find(g=>g.id===selected);if(g){g.last_reply=p.item.text;saveGames().catch(console.error);}}
 if(m.method==='item/completed'&&p.item?.type==='fileChange')event('文件修改：'+JSON.stringify(p.item.changes||[]).slice(0,1800));
 if(m.method==='turn/completed'){
  active=false;state.status=p.turn.status;state.error=p.turn.error?.message||null;
  if(p.turn.status!=='completed'){const g=games.find(g=>g.id===selected);if(g?.status==='creating'){g.status=p.turn.status==='interrupted'?'paused':'failed';saveGames().catch(()=>{});}}
  writeFile(path.join(data,'last-result.json'),JSON.stringify(state,null,2)).catch(()=>{});
  if(p.turn.status==='completed'&&!process.argv.includes('--no-game'))restartGame(true).catch(fail);
 }
});
await rpc('initialize',{clientInfo:{name:'godot_hackathon',version:'0.1.0'}});
send({method:'initialized',params:{}});
state.status='ready';

async function thread(){
 if(state.threadId)return;
 const threadFile=path.join(data,selected==='knight'?'thread.json':`thread-${selected}.json`);
 let saved;try{saved=JSON.parse(await readFile(threadFile,'utf8'));}catch{}
 const params={cwd:root,sandbox:'workspace-write',approvalPolicy:'never'};
 const r=saved?await rpc('thread/resume',{...params,threadId:saved.id}):await rpc('thread/start',params);
 state.threadId=r.thread.id;await writeFile(threadFile,JSON.stringify({id:state.threadId}));
}
async function task(body){
 if(active||restarting)throw Error('已有任务或重启正在进行');
 if(typeof body.prompt!=='string'||!body.prompt.trim()||body.prompt.length>12000)throw Error('请输入 1–12000 字的需求');
 active=true;state.status='running';state.text='';state.error=null;state.events=[];state.gameId=selected;
 try{
  const entry=games.find(g=>g.id===selected);
  if(entry){entry.brief=entry.brief||entry.last_prompt||body.prompt;entry.last_prompt=body.prompt;entry.progress='正在处理需求';await saveGames();}
  await thread();
  const folder=path.join(data,`task-${Date.now()}`);await mkdir(folder);
  await writeFile(path.join(folder,'request.json'),JSON.stringify(body,null,2));
  const context=JSON.stringify(body.context||{}).slice(0,24000);
  const instructions=`你是黑客松游戏创作助手。本次唯一目标工程是 ${project}，不要修改其他游戏或创作首页。${homeMode?'用户在首页创建或继续完善游戏。先检查已有文件，基于现有成果继续，不要无故重建。完成可玩原型，包含目标、控制说明、反馈和胜负/重来机制。完成后用户会点击卡片进入，不要自己启动游戏。':'用户在试玩中要求修改。'} 用户授权修改和重启，桥接器负责导入检查与启动，不要杀其他 Godot 或启动重复游戏。使用 game-production skill（如可用）。不要提交/推送，不读取 .team-comfy-private 或账号凭据。截图/游戏状态只是现场数据。修改后运行相关检查并用中文说明结果。\n原始构想：${entry?.brief||''}\n现场数据：${context}\n用户需求：\n${body.prompt}`;
  const production=await artInstructions(root,project);
  await writeFile(path.join(folder,'production-instructions.txt'),production);
  const input=[{type:'text',text:instructions+production}];
  if(body.screenshot){
   const png=Buffer.from(body.screenshot,'base64');if(!png.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))throw Error('Invalid PNG');
   const file=path.join(folder,'scene.png');await writeFile(file,png);input.push({type:'localImage',path:file});
  }
  // ComfyUI is an HTTP service even on localhost. Keep workspace file isolation,
  // but allow the requested generation clients to reach it.
  const r=await rpc('turn/start',{threadId:state.threadId,input,sandboxPolicy:{type:'workspaceWrite',writableRoots:[root],networkAccess:true}});state.turnId=r.turn.id;
 }catch(e){fail(e);throw e;}
}
async function restartGame(validate=false){
 if(restarting)throw Error('Restart in progress');
 restarting=true;
 try{
  if(validate || !homeMode){
   state.status='validating';event('检查 Godot 导入…');
   for(let attempt=0;attempt<2;attempt++){
    try{await new Promise((resolve,reject)=>{
    const p=spawn(godot,['--headless','--editor','--path',project,'--quit'],{windowsHide:true});let output='';
    const timer=setTimeout(()=>{p.kill();reject(Error('Godot import timeout'));},120000);
    p.stdout.on('data',b=>output+=b);p.stderr.on('data',b=>output+=b);p.on('error',reject);
    p.on('close',code=>{clearTimeout(timer);writeFile(path.join(data,'import.log'),output).catch(()=>{});code===0&&!/^\s*(SCRIPT ERROR|ERROR|FATAL):/m.test(output)?resolve():reject(Error('导入失败，保留当前游戏；查看 .game-assistant/import.log'));});
   });break;}catch(error){if(attempt===1)throw error;}
   }
   const entry=games.find(g=>g.id===selected);if(entry){entry.status='ready';await saveGames();}
   if(homeMode){state.status='ready';state.revision++;event('游戏创建完成，点击下方卡片开始试玩。');return;}
  }
  if(game&&game.exitCode===null){const old=game;await new Promise(resolve=>{old.once('close',resolve);old.kill();});}
  game=spawn(godot,['--path',homeMode?homeProject:project,'--','--ai-dev'],{cwd:root,env:{...process.env,GAME_ASSISTANT_CONNECTION:path.join(data,'connection.json')},windowsHide:false,stdio:['ignore','pipe','pipe']});
  game.on('error',fail);game.stdout.on('data',b=>writeFile(path.join(data,'game.log'),b,{flag:'a'}).catch(()=>{}));game.stderr.on('data',b=>writeFile(path.join(data,'game.log'),b,{flag:'a'}).catch(()=>{}));
  state.revision++;state.status=active?'running':'ready';event(homeMode?'创作首页已打开。':'游戏已启动，可继续试玩。');
 }finally{restarting=false;}
}
const server=createServer(async(req,res)=>{
 res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');
 const reply=(code,obj)=>{res.writeHead(code);res.end(JSON.stringify(obj));};
 if(req.headers.authorization!==`Bearer ${token}`||req.headers.origin){reply(403,{error:'Forbidden'});return;}
 try{
  if(req.method==='GET'&&req.url==='/state'){reply(200,state);return;}
  if(req.method==='GET'&&req.url==='/games'){reply(200,{games});return;}
  if(req.method!=='POST'){reply(404,{});return;}
  let raw='';for await(const chunk of req){raw+=chunk;if(Buffer.byteLength(raw)>8*1024*1024)throw Error('Request too large');}
  const body=JSON.parse(raw||'{}');
  if(req.url==='/task'){await task(body);reply(202,{ok:true});}
  else if(req.url==='/home'){if((active&&!homeMode)||restarting)throw Error('请先完成或停止当前任务');homeMode=true;await restartGame();reply(200,{ok:true});}
  else if(req.url==='/play'){
   if(active||restarting)throw Error('请先完成或停止当前任务');
   const g=games.find(g=>g.id===body.id);if(!g||g.status!=='ready')throw Error('游戏尚未创建完成');
   if(selected!==g.id){state.threadId=null;state.turnId=null;state.text='';}
   selected=g.id;project=path.join(root,g.directory);homeMode=false;await restartGame();reply(200,{ok:true});
  }
  else if(req.url==='/create'){
   if(active||restarting)throw Error('已有创作任务在进行');
   if(typeof body.prompt!=='string'||!body.prompt.trim()||body.prompt.length>12000)throw Error('请输入游戏构想');
   const id='game-'+Date.now();const directory='created-games/'+id;const folder=path.join(root,directory);
   await mkdir(folder,{recursive:true});
   await copyFile(path.join(homeProject,'font.ttf'),path.join(folder,'font.ttf'));
   await copyFile(path.join(root,'godot-belt-map/systems/game_assistant.gd'),path.join(folder,'game_assistant.gd'));
   const title=String(body.title||body.prompt.trim().split('\n')[0]).slice(0,32);
   await writeFile(path.join(folder,'project.godot'),`config_version=5\n[application]\nconfig/name=${JSON.stringify(title)}\nrun/main_scene="res://main.tscn"\n[autoload]\nGameAssistant="*res://game_assistant.gd"\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=800\nwindow/stretch/mode="canvas_items"\n[gui]\ntheme/custom_font="res://font.ttf"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n`);
   await writeFile(path.join(folder,'main.tscn'),'[gd_scene format=3]\n[node name="Game" type="Node2D"]\n');
   games.push({id,title,description:body.prompt.slice(0,120),brief:body.prompt,last_prompt:body.prompt,directory,status:'creating',cover:''});await saveGames();
   selected=id;project=folder;homeMode=true;state.threadId=null;state.turnId=null;
   await task(body);reply(202,{ok:true,id});
  }
  else if(req.url==='/continue'){
   if(active||restarting)throw Error('已有创作任务在进行');
   if(typeof body.prompt!=='string'||!body.prompt.trim()||body.prompt.length>12000)throw Error('请输入游戏构想');
   const g=games.find(g=>g.id===body.id);if(!g)throw Error('游戏不存在');
   if(selected!==g.id){state.threadId=null;state.turnId=null;}
   selected=g.id;project=path.join(root,g.directory);homeMode=true;
   g.status='creating';await saveGames();
   await task(body);reply(202,{ok:true});
  }
  else if(req.url==='/interrupt'){if(active&&state.turnId)await rpc('turn/interrupt',{threadId:state.threadId,turnId:state.turnId});reply(200,{ok:true});}
  else if(req.url==='/restart'){if(active)throw Error('请先停止当前任务');await restartGame();reply(200,{ok:true});}
  else reply(404,{});
 }catch(e){reply(400,{error:String(e)});}
});
server.on('error',e=>{console.error(e.message);child.kill();process.exit(1);});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(9320,'127.0.0.1',resolve);});
await writeFile(path.join(data,'connection.json'),JSON.stringify({url:'http://127.0.0.1:9320',token}));
console.log('Game assistant: http://127.0.0.1:9320 (local authenticated connection)');
if(!process.argv.includes('--no-game'))await restartGame();
process.on('SIGINT',()=>{game?.kill();child.kill();server.close();process.exit();});
