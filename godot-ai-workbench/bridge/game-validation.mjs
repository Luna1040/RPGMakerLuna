import {readFile,readdir,stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';

export function isEmptyScene(scene){
 return /^\s*\[gd_scene[^\]]*\]\s*\[node name="[^"]+" type="Node2D"\]\s*$/.test(scene);
}

export async function projectFingerprint(project){
 const records=[];
 async function walk(folder){
  for(const entry of await readdir(folder,{withFileTypes:true})){
   if(['.godot','.git','art-jobs'].includes(entry.name)||entry.name.startsWith('.assistant-write-probe-'))continue;
   const file=path.join(folder,entry.name);
   if(entry.isDirectory()){await walk(file);continue;}
   if(!entry.isFile())continue;
   const info=await stat(file);
   const content=/\.(gd|tscn|tres|godot|json|cfg)$/.test(entry.name)?createHash('sha256').update(await readFile(file)).digest('hex'):`${info.size}:${info.mtimeMs}`;
   records.push([path.relative(project,file),content]);
  }
 }
 await walk(project);
 return JSON.stringify(records.sort((a,b)=>a[0].localeCompare(b[0])));
}

export async function validatePlayableProject(project){
 const config=await readFile(path.join(project,'project.godot'),'utf8');
 const main=config.match(/^run\/main_scene="res:\/\/([^"\r\n]+)"/m)?.[1];
 if(!main)throw Error('项目没有配置主场景');
 const scene=await readFile(path.join(project,main),'utf8');
 if(isEmptyScene(scene))throw Error('游戏仍是空场景，生成任务尚未完成；请继续完善。');
}
