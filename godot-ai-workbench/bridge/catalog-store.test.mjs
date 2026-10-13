import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile} from 'node:fs/promises';
import path from 'node:path';
import {loadGames,catalogWriter} from './catalog-store.mjs';

test('restart preserves unfinished project, full prompt and reply',async()=>{
 const dir=await mkdtemp(path.resolve('.game-assistant/catalog-test-'));
 const file=path.join(dir,'catalog.json');
 const record={id:'unfinished',directory:'created-games/unfinished',status:'creating',brief:'完整原始需求',last_prompt:'继续补完战斗',last_reply:'已经完成移动'};
 await catalogWriter(file)([record]);
 const loaded=await loadGames(file,[]);
 assert.equal(loaded[0].status,'paused');
 for(const key of ['id','directory','brief','last_prompt','last_reply'])assert.equal(loaded[0][key],record[key]);
});
test('queued writes preserve newest snapshot and corrupt catalog is not reset',async()=>{
 const dir=await mkdtemp(path.resolve('.game-assistant/catalog-test-'));
 const file=path.join(dir,'catalog.json');const save=catalogWriter(file);
 await Promise.all([save([{id:'a',directory:'a',status:'creating'}]),save([{id:'a',directory:'a',status:'ready'}])]);
 assert.equal((await loadGames(file,[]))[0].status,'ready');
 await writeFile(file,'{broken');await assert.rejects(loadGames(file,[]));
 assert.equal(await readFile(file,'utf8'),'{broken');
});
