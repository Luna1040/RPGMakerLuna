# 敌人与队友动画生产 v1

这批使用已经认可的本地 MiniMax H3 reference-to-video 链路，768×768、124 源帧、24 fps、20 steps、normal scheduler、res_multistep，不使用 turbo LoRA。一个动作一段完整全身视频，避免把手脚零件旋转冒充角色动画。

角色 ID：`scout` 灰誓斥候、`caster` 灰誓咒术师、`elite` 灰誓重卫、`boss` 陨星执政官、`serin` 瑟琳。每个角色有 `stand / walk / attack / hurt`，瑟琳另有 `cast` 治疗动作。

## 运行与恢复

入口：`character-generation-research/npc_roster_v1.py`。

1. `init` 建立默认角色配置和导出规格文件。
2. 把透明、完整全身的原始参考放到 `references/<id>.png`。图内不得有重复人物、文字、背景孔洞、被截断武器或脚。
3. `run --watch-references` 等待参考并依次生成。GPU 生成与单独的 CPU BiRefNet 抠图并行；不占用用户 9315。
4. `review` 生成各动作 16 帧源片接触表。检查造型、武器、动作阶段和背景。
5. 在 `export-specs.json` 的 `<id>.<action>` 写入人工确认的 `indices`、`durations`、`event_ms`，可覆盖固定 `pivot`、`scale`。每个 source index 是 0 到 123 的原始视频帧，不是导出的 PNG 文件编号。
6. `export --ids scout --actions attack --force` 重导出指定动作。缓存只保存源帧的 RGBA，不会改变 source index。
7. 在深浅背景接触表及动画 WebP 中检查后，规格中填写 `review_status: visually_reviewed` 并再导出；不能把 `needs_visual_review` 当成验收完成。
8. 同一角色的最终动作规格统一重导出后执行 `publish --ids <id>`。此入口调用 `pack_roster_runtime.pack_character`，只发布人工验收动作，并按动作联合 alpha 包围框裁切游戏副本。不要直接把原稿方图复制到游戏资源。

`run` 会复用成功 history + 完整 124 张源帧；若任务还在 ComfyUI 队列中会继续等待。历史任务失败或帧数不对会停止并保留错误，而不是静默覆盖。`STOP_AFTER_CURRENT` 文件可以让队列完成当前段并等待 CPU 导出后停止；恢复时删除该标志再运行即可。不会清空他人的排队任务。

## 产物

- `roster.json`：身份、职业动作描述、种子、参考路径、目标游戏高度。
- `jobs/<id>/<action>/workflow.json / job.json / history.json / export-selection.json`：完整来源链。
- H3 原视频与 124 张 PNG 留在上级 `output/`，前缀 `npc-roster-v1-<id>-<action>`。
- `mattes/<id>/<action>/NNNN.png`：按原始 source index 命名的透明缓存。
- `review/`：原片、深浅底抠图接触表、动画 WebP、alpha/画布边缘检查 JSON。
- `export/<id>/portrait.png`：原创角色全身立绘。
- `export/<id>/animation.json`：游戏动作表。
- `export/<id>/<action>/NNN.png`：统一 768×768 RGBA 画布。
- `archive/`：失败版本的来源记录、候选帧与 matte 缓存，原始 H3 视频依旧保留。返工必须移开对应旧缓存，不能让新视频复用旧帧 mask。
- `schedule.json`：可热更新 `priority_characters`，当前顺序是瑟琳、斥候、咒术师、重卫、首领。

```json
{
  "version": 1,
  "id": "scout",
  "name": "灰誓斥候",
  "canvas": [768, 768],
  "portrait": "portrait.png",
  "actions": {
    "attack": {
      "frames": [{"file": "attack/000.png", "source_frame": 0, "duration_ms": 60}],
      "duration_ms": 720,
      "pivot": [384, 648],
      "scale": 0.46,
      "event_ms": 300,
      "source": "npc-roster-v1-scout-attack",
      "source_count": 124,
      "review_status": "needs_visual_review"
    }
  }
}
```

示例数值仅解释格式。实际动作长度必须等于所有帧时长之和，事件时间必须按角色出手姿态选择；示例不应直接当成运行素材。

## Alpha 与原点约定

输入按原始 alpha 包围框等比放入 768 画布；瑟琳最高 520 像素，斥候和咒术师 480，持巨斧与巨剑的重卫/首领 440，地面参考 y=648。武器随人物等比缩放，不单独缩短来塞进画幅。H3 提示要求纯黑背景，仍需以实际源帧为准。后处理用 BiRefNet-lite 语义分割结合黑底边缘去色；高置信度实体区域保留不透明的深色布料，不把蓝色/青绿色衣服自动变成加法特效。魔法、弹道、命中闪光均由游戏独立画，不能给整个人物开加法混合。

每个角色固定 pivot 与 scale；先从 stand 源帧 0 的脚底推导，其余动作继承这一原点，不逐帧按包围框缩放、居中或压窄武器。动作切换仍须观察；若模型自己改变了身高或足部位置，应修导出规格或重生成，不让游戏逐帧修形。远程攻击 `emitter: [x,y]` 是实际出手源帧的原始 768 画布坐标，`emitter_source_frame` 记录所依据的源帧。

游戏副本的 `storage_crop: [x,y,w,h]` 只描述无损存储裁切，`canvas`、`pivot`、`emitter` 仍使用原始 768 坐标；Godot 通过 AtlasTexture 恢复原画布空间。这样无需为每帧存入大片空白纹理，也不会让脚底抖动。

母图自带有效 alpha，视频没有原生 alpha，两者不能用同一种保护规则。母图的实体 alpha 接近 253 而不是 255，需要归一化并保护实体；BiRef 会误判大斧刃为背景。视频保护必须结合实际黑底键、实体颜色与语义 mask，再检查完整武器和发丝。

提示中即便有“不要特效”，`healing spell / holy bolt / blessing / unseen impact` 仍容易诱发法阵、光束、红色命中闪光。新法术动作描述纯物理手势（收手、转肩髋、伸掌、收回）；受击描述身体后仰与屈膝。若特效遍布整段并遮住发丝/镀金饰品，应重跑干净动作而非大量手绘 mask。小型独立杖头辉光可以按源帧明确区域去除黑底预乘色，不能全人物提亮。

自动循环选择只比较首尾姿势与运动方向，用作候选。人工仍需检查走路左右腿交替、头躯干随动、头发和衣服延迟、武器不消失、首尾不跳、抠图孔洞及亮边。源动作 5.17 秒和游戏动作时长是两回事；攻击和受击会按源动作阶段压缩时长，待机与步行保持可读循环。

最终 QA 必须查看 `review/<id>-<action>-all-dark.jpg` 与 `all-light.jpg` 的全部选入帧。六帧摘要图只用于快速定位，不能代替全帧检查。斥候攻击原65–77帧刀尖越界被拒绝；保留62/63/64完整主斩，82以后完整落定/收剑，不能靠缩短武器掩饰越界。

局部光晕清理有两种情况：若原 matte 保留了完整渐变，可以在明确的背景区域按亮度计算 alpha 再反预乘；若暗晕已经被阈值截断，必须从原始 RGB 恢复渐变，不能继续 `min(new_alpha, old_alpha)`，否则会留下锯齿贴片。咒术师月牙杖的金属与悬浮紫晶用无光晕源帧的实体模板保护，再重建周围紫光；角色身体与服装不参与这个局部处理。所有局部规则都在 `export-specs.json.alpha_cleanup`，不会静默改原片。
