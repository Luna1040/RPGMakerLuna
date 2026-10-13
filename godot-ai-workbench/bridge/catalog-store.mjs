import {readFile,writeFile,mkdir,rename} from 'node:fs/promises';
import path from 'node:path';

export function recoverGames(games){
 if(!Array.isArray(games)||games.some(g=>!g.id||!g.directory))throw Error('Invalid game catalog');
 return games.map(g=>g.status==='creating'?{...g,status:'paused',progress:'上次创作中断，已有文件和需求已保留。'}:g);
}

export async function loadGames(file,defaults){
 try{return recoverGames(JSON.parse(await readFile(file,'utf8')));}
 catch(e){if(e.code==='ENOENT')return defaults;throw e;}
}

export function catalogWriter(file){
 let queued=Promise.resolve();
 return games=>{
  const snapshot=JSON.stringify(games,null,2);
  const write=async()=>{await mkdir(path.dirname(file),{recursive:true});await writeFile(file+'.tmp',snapshot);await rename(file+'.tmp',file);};
  const result=queued.then(write);queued=result.catch(()=>{});return result;
 };
}
