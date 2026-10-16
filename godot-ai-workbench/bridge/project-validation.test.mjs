import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {assertImplementedProject,assertCleanGodotRun} from './project-validation.mjs';

async function fixture(t,scene,main='main.tscn'){
 const folder=await mkdtemp(path.join(os.tmpdir(),'luna-validation-'));
 t.after(()=>rm(folder,{recursive:true,force:true}));
 await writeFile(path.join(folder,'project.godot'),`[application]\nrun/main_scene="res://${main}"\n`);
 await writeFile(path.join(folder,'main.tscn'),scene);
 return folder;
}
test('completed AI turn with imported starter scene is still unfinished',async t=>{
 const folder=await fixture(t,'; starter\r\n[gd_scene format=3]\r\n\r\n[node name="Game" type="Node2D"]\r\n');
 await assert.rejects(assertImplementedProject(folder),/空场景/);
});
test('scene containing game script passes structural gate',async t=>{
 const folder=await fixture(t,'[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Game" type="Node2D"]\nscript = ExtResource("1")\n');
 await assertImplementedProject(folder);
});
test('missing scene and path outside project cannot pass',async t=>{
 await assert.rejects(assertImplementedProject(await fixture(t,'','missing.tscn')),/ENOENT/);
 await assert.rejects(assertImplementedProject(await fixture(t,'','../outside.tscn')),/工程内/);
});
test('Godot errors fail validation even when exit code is zero',()=>{
 assert.throws(()=>assertCleanGodotRun(0,'SCRIPT ERROR: Parse Error'),/检查失败/);
 assert.throws(()=>assertCleanGodotRun(0,'\x1b[31mERROR: Missing font\x1b[0m'),/检查失败/);
 assert.throws(()=>assertCleanGodotRun(1,''),/检查失败/);
 assertCleanGodotRun(0,'Godot Engine\n[ DONE ]');
});
