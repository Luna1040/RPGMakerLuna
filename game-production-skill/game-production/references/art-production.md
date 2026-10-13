# 美术生产：已验证方法和边界

## 母图 → 动画

先制作完整、精细的原创成年角色参考，统一镜头、轮廓、配色和比例。完整头发、鞋底、披风和武器都在画幅内，角色高度约占 60%，留挥剑空间。正交/固定侧视是本实例的选择，不是假定所有游戏都是侧视。

母图验收：轮廓和内部空隙均无原背景，双手朝向正确，远侧肢体位于身体后方，武器不截断。透明底必须实际存在 alpha，不能是画出来的棋盘格。先叠到深灰、白、彩色底上检查。精细母图有利于后续美感，但不能保证逐帧身份一致。

动作提示词分为身份、动作阶段、镜头与画幅四段：

> The adult character in <Picture 1>, preserve the illustrated identity and outfit. One complete sword slash: bend knees and load hips, turn torso and raise sword, drive through hips and shoulders into a fast diagonal strike, follow through, recover. Head and torso participate naturally; hair and cape follow with a delay. Keep the full weapon visible throughout. Fixed side camera, full body with generous margins, no camera movement, no cuts. Solid black background, no scenery or floor shadow. No additional effects.

站立呼吸与职业闲置分开：铁匠检查工具、法师翻书、卫兵环视，动作与身份相符。走路要明确左右脚交替、承重和抬脚；攻击要前摇、出手、收招；受击要身体失衡和恢复。先每种生成一个完整片段，不让模型一次输出整套技能。

## 本次成功的 H3 配置

来源：已运行的 ComfyUI 核心版本 `a4b5a045e56fc334903db8457b728b64e006119c` 与项目生成记录。不是对所有 ComfyUI 版本的兼容承诺。

| 部分 | 参数 |
|---|---|
| diffusion | minimax_h3_ref2va_pruned_fp8_scaled.safetensors |
| text encoder | qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors |
| VAE | minimax_h3_video_vae_fp16.safetensors |
| 输出 | 768×768，124 源帧，24 fps |
| 采样 | 20 steps，normal，res_multistep，denoise 1 |
| LoRA | 不加载 turbo LoRA；4 step 早期结果不足 |

不要只凭文件名下载同名来源不明模型。团队调用现成主机无须下载这些大模型；自建主机应先核查官方发布/许可证与节点版本，再决定资源开销。

每次输出前缀包含项目、角色、动作和唯一作业标识。每块 GPU 默认串行跑生成；CPU 抠图可独立执行。不要中断另一位成员或主机用户的任务。

## 背景与透明度

本项目绿幕参考曾保留发丝/颈部的四个封闭白色区域，动画继承污染。清母图外围不够，内部孔洞同样检查。H3 在绿幕指令下仍生成黑底；背景色合规是检查项，不能在提示词里写了就算成功。

随附 `matte_frames.py` 使用 BiRefNet ONNX 语义 mask，保留原画布，并按黑底合成假设校正半透明边缘颜色。需安装 `numpy pillow onnxruntime` 并自行提供匹配的 BiRefNet 模型（ImageNet 归一化、1024 输入）；不适用于未知模型、绿底、白底或有地面场景的视频。深色衣服、细发丝、内部孔洞仍可能出错，检查预览后再选帧。

过去为蓝披风写过颜色保护区域：这是角色专用补丁，不能作为通用自动抠图。不要阈值删除所有黑色/白色，否则连盔甲高光和衣服也删掉。修改算法后更换缓存键或目录，缓存应包含模型、算法、源文件 hash。

特效优先独立生成。黑底发光效果在 Godot 用 `CanvasItemMaterial.BLEND_MODE_ADD`；人物用普通 alpha。烘焙到人物里的光不能完美反分离。

## 选帧与时序

保存源视频、源帧，不覆盖认可版本。每帧记录 source_frame 和 duration_ms。已认可一次斩击示例：

- 源帧：8,14,20,25,28,30,33,36,39,42,45,48,52,57,63,70,78,90。
- 时长 ms：35,35,40,45,50,20,20,20,20,55,25,30,35,40,40,45,45,40。
- 合计 640 ms，命中事件 305 ms；展示循环额外停顿不属于技能时长。

这是特定原片的取帧实例，新片不能照抄编号。检查有效姿势和速度峰值，短出手、可读的前后摇；攻击逻辑不要每个显示帧重复命中同一对象。循环需看末帧到首帧、脚底漂移和身体高度，静态接触表不足以判定连续性。

## 地图和资产分工

先画地面/遮挡/交互体积草图，再生成符合镜头的背景、前景、建筑和道具。宽场景用专门宽构图或重叠拼接，保持纵横比；不要把方图拉满屏幕。碰撞按落地占地体积配置，不能拿整张喷泉的外框当地面障碍。水流、火焰、布幡等需要动画或特效，不把静态贴图称为动态。

## 已试过但不应直接量产的路线

- 独立生成人物零件：肢体朝向、光照、比例和接缝不一致；适合受控原画拆件，不保证 AI 任意分件自动拼好。
- 2.5D 骨骼切图：保留画风但会有木偶感；需要躯干变形、遮挡、替换姿势，不能只转四肢。
- 粗模 3D 低分辨率渲染：出现塑料感、发虚阴影和锯齿；关光照不等于复原二维轮廓。适合已有优质模型/贴图和像素修饰流程时再试。
- 全身生成动画的装备替换：原武器已烘焙；换装备数值不等于外观改变。精确换装需新动作资源或规范独立武器/衣层生产，明确成本。
