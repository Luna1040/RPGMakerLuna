import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
for(const name of ['game-server.mjs','art-pipeline.mjs']){
 test(name+' parses before any service or task can start',()=>{
  execFileSync(process.execPath,['--check',fileURLToPath(new URL('./'+name,import.meta.url))],{windowsHide:true,stdio:'pipe'});
 });
}
