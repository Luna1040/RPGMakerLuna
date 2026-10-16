# P0 临时资产来源

本文件中的历史 `art-jobs/` 路径指向制作机的原始工程记录；本源码快照保留运行所需素材与来源说明，不包含大体积生成过程文件、团队连接资料或用户参考截图。

- 部分 HUD、交互提示、攻击预警、弹道、粒子和环境动态仍由 `main.gd` 中的 Godot CanvasItem 矩形、线段、圆和文字在 320×180 内部画布上原创绘制。
- 当前标题封面底图 `assets/title-cover-remote-pixel.png` 来自团队远程 ComfyUI 的 Flux 2 Klein 9B FP8 + Qwen 3 8B 图像编辑工作流。`art-jobs/title-cover-remote-20261015-v1` 至 `v4` 分别保存用户参考、提示词、API workflow、seed、prompt_id、history、远程原图、筛选与处理记录；当前采用 v4，原图经 320×180 Nearest 采样、限色和侧边伪文字清理后导入。图片只绘制无字背景，准确的“昨夜不存在”和“Last night never existed”及四个菜单按钮由 Godot 绘制。当前为可试玩候选美术，仍待用户目视确认。
- 当前酒吧底图为 `assets/bar-lounge-dancefloor-gap-pixel.png`，基于用户认可的三分区候选 A 派生。原始远程记录位于 `art-jobs/bar-lounge-dancefloor-remote-20261015-v1/`；本轮派生记录位于 `art-jobs/bar-gap-pixel-cast-20261015-v1/`。缺口使用同一底图相邻走道的原画像素填充 32px 通路，同时从透明前景 mask 中移除该区域，不是只修改碰撞。派生底图 SHA-256 为 `7fff9e8734da38e8e3ad1a678e57b37f908e485879b7f8f75c5d45164845f7bc`，前景为 `47f740c33832c50ac47056267f3c6a511a68c1018a135a032e5a220cbaaa2e9f`。
- 当前采用候选 A：prompt_id `ed08264d-524c-4917-9dc0-3057fb1d60e7`，seed `2026101541`。已目视检查原始 1536×864 输出，确认左侧三组酒红卡座、中央岛式吧台、右侧大舞池与 DJ 台；随后处理为 768×432、128 色、Nearest 硬边像素图，移除吧台右侧重复器具簇，只保留左侧小簇，并将通讯器改为无字图标。最终 SHA-256 为 `2570b6adb03493c18904683a388e4e8fff224ede067277389b3e33b8f2c740e2`。
- 候选 B 已提交并保存 prompt_id `8087e318-bfce-4af6-aa88-a4cffc74ddf8`，但 visitor 在 history 轮询时持续断连；没有重复提交，未取回、未选用，也不声称生成完成。前轮 `bar-expanded-remote-20261015-v1` A/B/C 已按用户实机反馈整批弃选，尤其 C 过于像小休息室；其记录仅作为历史证据保留。
- `assets/bar-lounge-dancefloor-gap-foreground.png` 从候选 A 的岛式吧台前脸原画像素提取真实 RGBA 遮挡层，并同步挖出员工通路；未使用盖住器具的纯色多边形。Godot 对它按世界脚底 Y 排序，并另行绘制整数像素雨窗视差、慢速舞池灯光、人物阴影、普通吧台通讯器和设施升级差分。
- `assets/bartender-idle-static-64.png` 与 `assets/zhou-idle-static-64.png` 来自用户本轮授权的团队 visitor ComfyUI Flux 2 Klein 9B FP8 + Qwen 3 8B 图像编辑工作流。主角 prompt_id `9567f857-afef-4d8d-89ce-3a67253f624a`、seed `2026101561`；周骁 prompt_id `d9d9ed24-e1ff-4580-a2b0-d37581c7083c`、seed `2026101567`。两张 1024×1024 绿底母图均已实际查看，完整 prompt、API workflow、上传映射、history、原图与 SHA-256 保存在 `art-jobs/bar-gap-pixel-cast-20261015-v1/`。
- 透明化参考 `character-generation-research/test_clean_chroma.py` 的封闭背景孔洞经验，使用强绿种子加边缘连通的宽松绿幕区域，不做会误删深色服装的黑白阈值。初版 48px 小样及其记录继续保留；本轮在独立目录 `art-jobs/character-scale-tuning-20261015-v1/` 用同一透明母图比较 56px 与 64px 两档，不重新生成、不逐帧重居中，也不使用运行时缩放。
- 当前接入 `assets/bartender-idle-static-large-80.png` 与 `assets/zhou-idle-static-large-80.png`：统一 80×80 RGBA 画布、64px 可见高度和脚底 `(40,72)`。主角 SHA-256 `af80ecaef6a24973a46228af5b6c19a1f0fd09e160170bab0f867775dd2812e8`，周骁为 `f9c0319814f8764bad36146f84e328da0fa2830edcca4f73bc4b6753fd9949de`。
- 前一轮镜头范围调整记录仍在 `art-jobs/bar-camera-zoom-20261015-v1/`。本轮应用户要求将 768×432 酒吧世界完整映射到 320×180 屏幕，固定相机，保留原有底图与前景遮挡；全景静态构图预览不是运行态截图。
- 本轮四组角色动作来自团队 ComfyUI H3 工作流，使用已有透明母图重新合成绿幕参考，采用 `minimax_h3_ref2va_pruned_fp8_scaled.safetensors`、`qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`、`minimax_h3_video_vae_fp16.safetensors`。全部 prompt、workflow、seed、prompt_id、已取得的 history/源帧、选帧表和深浅底检查位于本机未随源码发布的 `art-jobs/bar-h3-motion-20261015-v1/`。已接入 `assets/bar-motion/`：酒保走路 8 帧、伸手交互 8 帧；周骁走路 8 帧、对话手势 8 帧。四组动作统一 80×80 固定画布与 `(40,72)` 脚底，不逐帧居中或缩放。酒保首次交互原片带场景、周骁首次走路原片带地板而弃选；最终周骁走路采用干净绿幕的 v3。远程服务重启造成部分 history 不可读，保留了 prompt_id、workflow 和从输出文件恢复的帧索引，不把不可读记录声称为完整 history。
- 战斗 Demo 的三张 320×180 RGB 地图分别是 `assets/combat/maps/security_checkpoint.png`、`medical_room.png` 和 `root_lab.png`。它们由本机 `assets/combat/generate_combat_assets.py` 用 Pillow 绘制硬边像素形状：安保检查区有左右双门、扫描闸机与监控屏，医疗室有治疗床、扫描台与药柜，根层神经实验室有环形核心和洋红电路。没有使用旧的 `cyber-memory-arena.png`、用户参考图像素或远程出图。地图是静态底层，门状态、碰撞、前景遮挡、动态光效与攻击预警由 Godot 独立处理。
- 战斗人物共有五种身份与六张 72×88 RGBA 半身立绘：`heroine`、`guard`、`captain_melee`、`captain`、`medic`、`corrector`。队长借身前/后两张立绘保留同一制服，前者枪在腰侧、手持电棍，后者持枪；周骁不是安保队长。另有 35 张 80×80 RGBA 战斗小图：女主 7 帧，普通安保、队长近战、队长持枪、医疗员各 6 帧，校正者 4 帧。小图共用脚底 pivot `(40,72)`，运行时以 `0.5` 倍 Nearest 绘制，人物正常 alpha；电光、枪口闪光和 Boss 特效不烘在人物上。女主造型沿用已有蓝绿色长发、酒红马甲的身份设计，所有新像素由本机脚本绘制，没有复制母图像素，也没有把酒吧 H3 动作误称为战斗动作。
- `assets/combat/manifest.json` 记录新 PNG 的文件路径、尺寸、色彩模式、alpha 范围与 SHA-256；`assets/combat/review/` 的三张接触图仅供复核，不在游戏运行时加载。本机静态检查已验证 3 张地图、6 张立绘与 35 张小图的尺寸、透明度、帧边缘和两相步态差异；这不等同于真实游戏窗口中的视觉验收。
- 本轮新调酒页的六种酒瓶、摇酒器与调酒杯为本机脚本逐像素原创绘制的透明 PNG，位于 `assets/mixer/`。生成脚本、最近邻放大对照图与尺寸/透明度核查记录位于 `art-jobs/mixer-pixel-20261015-v1/`。用户提供的像素酒瓶截图只用于造型密度、像素边缘和酒具陈列方向，不复用截图像素、标签或品牌。
- 上一版 `assets/bar-interior-remote-pixel.png`、`assets/bar-interior-foreground.png` 与 `art-jobs/bar-interior-remote-20261015-v1/` 保留作历史回退，当前 `main.gd` 不再引用。
- 原程序化封面 `assets/title-cover-pixel.png` 及其完整生成记录保留作回退；当前主场景不再引用。此前工具内子任务报告远程生图服务不可达，是其受限沙箱下的访问结果；本轮从主机实际连通团队服务并完成远程生成，不应把本机缺 Flux 9B 模型误当成远程主机缺模型。
- `design-references/` 三张图片只用于阅读 STYLE_GUIDE 指定的像素颗粒、空间层次和远景雾方向；它们被 `.gdignore` 排除，未被加载、复制、描摹或打包为游戏素材。
- 旧的 `assets/cyber-memory-arena.png` 及 `art-jobs/` 中此前生成的记忆地图未被本轮战斗脚本或场景引用。
- `font.ttf` 是工程中原有字体，本轮仅继续使用；当前工程未记录其原始来源与许可证，发布前必须补齐授权或替换为许可证明确的中文像素字体。
- 当前没有音频。主角与周骁在酒吧已有 H3 正向走路与短交互动作候选；主角移动时循环走路，点器具或按 E 后先播伸手动作再进入调酒/调查，周骁从画面外入口走到左侧卡座并在对话时做手势。调酒页已有瓶子单击属性、双击倒酒、液面变化和酒库解锁。战斗页已接入原创程序像素候选与动作切换，但尚无 H3 战斗动画或多方向正式动作。Godot 真实渲染器的八张静帧已核对三层构图、缩小后的人物比例、出口牌与 Boss 预警/特效；连续步态、遮挡、可躲避性和战斗手感仍需人工试玩。远程模型与字体的发布许可仍需核查。
