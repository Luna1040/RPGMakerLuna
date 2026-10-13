# 游戏助手的美术生产合同

每次任务先读取配置中 skill 目录下的 SKILL.md。涉及角色、立绘、地图、道具、动画、特效或像素素材时，必须再读取 references/art-production.md、team-api.md 和 verification.md，然后调用现成工具完成生成、处理、接入和验证。只修改数值、UI 或逻辑时不必生成新美术。

## 工具与执行顺序

1. 母图/地图/道具：检查 imageUrl 的 /system_stats 和 /object_info。读取 imageWorkflow 的 API 图和 map-generation-research/generate_map_trial.py、layered_map_trial.py 了解已验证的 Flux2 参考图生成方法。在当前项目 art-jobs 的唯一子目录复制工作流，再按本次需求修改提示、上传参考、尺寸和输出前缀。不要直接运行硬编码旧地图/输出目录的历史脚本，不要直接沿用旧图的 input 文件名。通过 /upload/image、/prompt、/history/{prompt_id}、/view 提交并取回图片。模型和节点以目标实例实际返回为准，不能把 H3 客户端的固定节点编号套在 Flux 图上。
2. 动画/视频：使用 skill/scripts/comfy_client.py，显式传入 --url videoUrl（参数放在 check/submit/wait 之前）。先 check --workflow videoWorkflow，再 submit --workflow ... --reference 母图 --prompt-file 动作提示文本 --out 唯一作业目录，然后 wait --out 同目录。H3 输出视频和 SaveImage 源帧；保留 output-index.json 的节点及顺序映射。不要假设 CLI 有桌面版 GPT Image 工具；使用本机现有 ComfyUI。
3. 切帧：优先使用 H3 SaveImage 节点导出的原始 PNG，按输出索引顺序整理到单动作 source 目录，不能混入母图/预览。只有视频时用现有 ffmpeg 或 Python 视频解码工具导出固定帧率源帧，记录帧号。禁止逐帧重居中、缩放或紧裁切。
4. 抠图：调用 skill/scripts/matte_frames.py --model matteModel --source 源帧目录 --out 新的透明帧目录。先检查 Python 的 numpy、Pillow、onnxruntime 和模型可用性；可查本机既有嵌入式 Python。此工具适用黑底 H3，绿底/白底要先读取本项目 test_clean_chroma.py（仅参考算法，不直接执行其角色专用硬编码操作） 等对应策略并测试，不能硬套黑底去色。深色服装、高光、头发孔洞不能简单阈值删除。输出必须有真正 alpha。
5. 选帧和打包：查看深浅底预览及实际循环，按 assets/selection.example.json 创建本次选帧表，再调用 skill/scripts/pack_frames.py。记录 source_frame、duration_ms、脚底锚点、统一画布和命中/释放事件。攻击压缩出手阶段，头、躯干、髋和披风协同运动；不能只动四肢。
6. 接入当前 Godot 项目：组合动作清单，伤害/碰撞独立结算，发光特效使用独立加法层。执行相关测试并查看实际效果。可玩占位只允许临时使用，最终回复必须披露未完成美术，不能把占位或仅成功排队称为生成完成。

## 保存和失败处理

所有新作业、提示词、完整 API 图、seed、prompt_id、history、原始输出、透明帧、选帧表和验收记录放在当前项目 art-jobs 下，保持项目隔离。生成结果复制到当前项目 assets 后才算接入。已有已认可素材可复用；用户要求新增时必须真正生成。

提交超时先按 client_id 查队列/history，不能盲目重复提交。GPU 作业串行排队，不停止/释放其他用户的任务，不读取团队私钥。端口未启动、缺模型/节点、网络或执行权限受限时明确报告具体步骤和错误，保留断点记录；不能静默切换为付费接口或声称成功。本机视频服务为 9316、图像服务为 9315，团队访客的 19316 不是本机默认。允许环境变量覆盖地址和模型路径。

图像服务未启动时，使用现有嵌入式 Python 在后台运行 godot-ai-workbench/start_image_service.py（PowerShell Start-Process 必须 -WindowStyle Hidden），日志写 .game-assistant；等待 /system_stats 再检查工作流。视频服务对应 character-generation-research/start_h3.py。不要重复启动已有服务。抠图依赖位于 character-generation-research/h3-runtime/matte-deps 和 deps，嵌入式 Python 需在调用 runpy 前明确加入 sys.path。
