# RPGMakerLuna

原创像素/插画风 RPG 原型、角色制作实验及素材档案。2026-10-09 本地素材快照。

## 当前主工程

- `godot-belt-map/`：Godot 4.7.2 庭院试玩，包含角色动作、NPC 职业待机、动态喷泉、装备、技能、地图及开发检查台。
- `releases/knight-web/`：网页试玩成品，入口 `index.html`；通过 HTTP/HTTPS 静态服务器运行。
- `releases/苍石庭院-网页试玩-20261009.zip`：可直接上传静态托管的网页试玩包。
- `CHARACTER_PIPELINE.md`：角色素材生产流程。
- `godot-belt-map/使用与对接说明.txt`：最新操作、机制、测试与集成记录。

## 克隆与运行

二进制素材使用 Git LFS。请安装 Git LFS 后克隆，避免仅获得指针文件：

```sh
git lfs install
git clone https://github.com/Luna1040/RPGMakerLuna.git
cd RPGMakerLuna
git lfs pull
godot --path godot-belt-map
```

安装 Godot 4.7.2 并将可执行文件命名/配置为 `godot`，或用编辑器导入 `godot-belt-map/project.godot`。
根目录的旧 `.cmd` 启动器保留原始开发机路径约定，需要自行配置 `.tools/godot`。

网页包：在 `releases/knight-web` 中运行 `python -m http.server 8793`，访问 `http://localhost:8793/`。不能直接使用 `file://` 双击 HTML。

## 素材与实验归档

- `character-generation-research/`：生成脚本、工作流、参考图、原始动作帧、抠图、视频及验收图；H3 模型和 ComfyUI 运行环境另行安装。
- `map-generation-research/`：地图工坊、世界/地点数据、生成试验及场景素材。
- `godot-first-knight/`：首个角色独立演示。
- 其他 `godot-*`、`discarded-wardrobe-neutral/` 和 `pixel-rpg-cli-test/`：早期分层、换装、3D 转 2D、像素及工具链实验。属于历史试验，不代表当前方案。
- `ASSET_MANIFEST.json`：复制时各源文件路径、字节数与 SHA-256，便于对照素材是否齐全。

## 导出与开发

`godot-belt-map/export_presets.cfg` 包含 Web Preview 预设。网页导出模板不随仓库分发，请安装同版本官方模板并更新自定义模板路径。
中文字体是 Noto Sans SC 字符子集，许可证随素材与网页包保存；添加新界面文字时需要重新生成子集或换用完整字体。
F3 打开开发检查台，F2 碰撞体，F4 命中范围，F6 暂停，F7 单步，F8 慢速。

## 本次未上传

模型权重、ComfyUI/引擎/CLI 下载包、Python/Node 依赖、缓存、临时下载分片、运行日志、认证与环境配置。
保留生成中间素材和验收截图。网页产物及角色压缩包也通过 LFS 保存。
第三方工具目录保留各自许可证，不对第三方内容重新授予许可证。
