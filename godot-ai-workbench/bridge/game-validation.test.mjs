import test from 'node:test';
import assert from 'node:assert/strict';
import {isEmptyScene,projectFingerprint} from './game-validation.mjs';
import {mkdtemp,mkdir,writeFile,unlink,rmdir} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

test('reject the generated empty scene even though Godot can import it',()=>{
 assert.equal(isEmptyScene('[gd_scene format=3]\r\n[node name="Game" type="Node2D"]\r\n'),true);
 assert.equal(isEmptyScene('[gd_scene format=3]\n[node name="Game" type="Node2D"]\nscript = ExtResource("1")'),false);
 assert.equal(isEmptyScene('[gd_scene format=3]\n[node name="Game" type="Node2D"]\n[node name="UI" type="Control" parent="."]'),false);
});

test('importing an unchanged game does not count as fulfilling a request',async()=>{
 const folder=await mkdtemp(path.join(os.tmpdir(),'game-validation-'));
 const source=path.join(folder,'main.gd');
 const cache=path.join(folder,'.godot');
 const imported=path.join(cache,'import.txt');
 try{
  await writeFile(source,'extends Node2D\n');
  const before=await projectFingerprint(folder);
  await mkdir(cache);await writeFile(imported,'imported successfully');
  assert.equal(await projectFingerprint(folder),before);
  await writeFile(source,'extends Node2D\nvar hp=100\n');
  assert.notEqual(await projectFingerprint(folder),before);
 }finally{
  await unlink(source);await unlink(imported);await rmdir(cache);await rmdir(folder);
 }
});
