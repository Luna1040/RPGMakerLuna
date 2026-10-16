import {readFile} from 'node:fs/promises';
import path from 'node:path';

// This is a structural gate, not a substitute for testing the gameplay.
export async function assertImplementedProject(folder){
 const config=await readFile(path.join(folder,'project.godot'),'utf8');
 const main=config.match(/^run\/main_scene\s*=\s*"res:\/\/([^"\r\n]+)"/m)?.[1];
 if(!main)throw Error('工程没有配置主场景');
 const file=path.resolve(folder,main);
 const relative=path.relative(folder,file);
 if(relative.startsWith('..')||path.isAbsolute(relative))throw Error('主场景必须位于游戏工程内');
 const scene=await readFile(file,'utf8');
 const meaningful=scene.split(/\r?\n/).map(line=>line.trim()).filter(line=>line&&!line.startsWith(';'));
 if(meaningful.length<=2&&meaningful[0]?.startsWith('[gd_scene')&&meaningful[1]?.startsWith('[node ')){
  throw Error('游戏仍是空场景，创作尚未完成；请点击继续创作。');
 }
}

export function assertCleanGodotRun(code,output){
 const plain=output.replace(/\x1b\[[0-9;]*m/g,'');
 if(code!==0||/^\s*(SCRIPT ERROR|ERROR|FATAL):/m.test(plain))throw Error('Godot 检查失败，请查看 .game-assistant 中的检查日志');
}
