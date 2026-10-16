import path from 'node:path';
import os from 'node:os';
import {readFile,access} from 'node:fs/promises';

// Shared by /create, /continue and in-game /task through task().
export async function artInstructions(root,project){
 const skill=path.join(root,'shareable-skills/game-production');
 await access(path.join(skill,'SKILL.md'));
 const guide=await readFile(path.join(root,'godot-ai-workbench/ART_PIPELINE.md'),'utf8');
 let localArt={};
 try{localArt=JSON.parse((await readFile(path.join(root,'.game-assistant/art-config.json'),'utf8')).replace(/^\uFEFF/,''));}
 catch(error){if(error.code!=='ENOENT')throw error;}
 const localPython=path.join(root,'.tools/art-python/python.exe');
 const legacyPython=path.join(os.homedir(),'Downloads/Flux2_klein_v1.0_普通版/Flux2_klein/python_embeded/python.exe');
 let python=process.env.GAME_ART_PYTHON||localArt.GAME_ART_PYTHON;
 if(!python){
  try{await access(localPython);python=localPython;}
  catch{python=legacyPython;}
 }
 const config={
  skill,project,
  artCli:path.join(root,'godot-ai-workbench/art_cli.py'),
  python,
  imageUrl:process.env.GAME_IMAGE_COMFY_URL||localArt.GAME_IMAGE_COMFY_URL||'http://127.0.0.1:9315',
  videoUrl:process.env.GAME_VIDEO_COMFY_URL||localArt.GAME_VIDEO_COMFY_URL||'http://127.0.0.1:9316',
  jobs:path.join(project,'art-jobs'),
  videoWorkflow:path.join(skill,'assets/h3-reference-api.json'),
  imageWorkflow:path.join(root,'map-generation-research/comfy-map-trials/desert-town-v1/workflow.json'),
  imageClient:path.join(skill,'scripts/image_client.py'),
  matteModel:process.env.GAME_MATTE_MODEL||localArt.GAME_MATTE_MODEL||path.join(root,'character-generation-research/h3-runtime/matte-v2/birefnet-lite.onnx'),
 };
 return '\n必须遵守的美术生产流程（所有新建、续作、游戏内请求均适用）：\n'+guide+'\n本次绝对路径和服务配置：\n'+JSON.stringify(config,null,2)+'\n';
}
