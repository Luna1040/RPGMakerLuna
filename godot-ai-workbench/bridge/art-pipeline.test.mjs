import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {artInstructions} from './art-pipeline.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
test('production contract is available for existing and newly created games',async()=>{
 for(const directory of ['godot-belt-map','created-games/test-new-game']){
  const project=path.join(root,directory);
  const text=await artInstructions(root,project);
  assert.ok(text.includes(JSON.stringify(path.join(project,'art-jobs'))));
  for(const required of ['art_cli.py','comfy_client.py','matte_frames.py','pack_frames.py','9315','9316','prompt_id','不能静默'])assert.ok(text.includes(required),required);
 }
});
test('missing skill fails instead of silently skipping production instructions',async()=>{
 await assert.rejects(artInstructions(path.join(root,'nonexistent-root'),root));
});
