# Godot / Web 发行验收清单

本清单是 B-14 的可重复发行门禁。它验证 Godot 运行时、导出策略、Web 制品、凭据隔离和浏览器首启；通过不代表真实付费模型账号、Windows、移动端或线上 CDN 已验收。

## 1. 环境

- 使用 `project.godot` 声明的 Godot 版本；当前为 4.7.2 stable。
- 安装同版本官方 Export Templates。
- `export_presets.cfg` 固定读取仓库本地工具路径：`.tools/godot/web-templates/web_nothreads_release.zip`。`.tools/` 不提交。
- API Key 只通过当前进程内存或 `RPG_AGENT_API_KEY` 提供，不写入项目、发布目录或测试报告。

## 2. 全量 Godot 回归

在 `godot-belt-map/` 的上级仓库目录运行：

```sh
python3 godot-belt-map/tests/run_tests.py \
  --godot /absolute/path/to/Godot \
  --suite all
```

必须同时通过资源导入预检与所有 core/gameplay 测试。报告写入 `godot-belt-map/test-results/`，该目录不会进入 Web 包。

## 3. Web 导出

```sh
/absolute/path/to/Godot \
  --headless \
  --path godot-belt-map \
  --export-release "Web Preview" \
  ../releases/knight-web/game.html
```

`export_presets.cfg` 必须继续排除 `tests/`、`captures/`、`test-results/`、日志、测试脚本、审阅脚本和生成提示词。Web 使用无线程模板，不要求部署端提供 SharedArrayBuffer。

## 4. 发行制品自动门禁

先启动静态服务器：

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory releases/knight-web
```

再运行：

```sh
python3 godot-belt-map/tests/release_acceptance.py \
  --url http://127.0.0.1:8765/ \
  --godot /absolute/path/to/Godot \
  --output godot-belt-map/test-results/release-acceptance.json
```

门禁检查：

- `game.html/js/pck/wasm` 存在、大小合理、签名正确，并生成 SHA-256 清单；
- 导出策略仍排除开发制品；发布目录和 PCK 不包含已知测试/截图/报告路径；
- 文本制品中不存在疑似供应商密钥；如当前进程设置了 `RPG_AGENT_API_KEY`，还会逐字确认该值没有进入文本或 PCK，但不会把值写进报告；
- HTTP 能完整提供 HTML、PCK 和 WASM；
- 桌面 Godot 能从导出的 PCK 启动，且控制台没有引擎或脚本错误。

门禁自身的单元测试：

```sh
python3 godot-belt-map/tests/test_release_acceptance.py
```

## 5. 浏览器首启

打开 `http://127.0.0.1:8765/game.html`，等待加载层消失后检查：

- Canvas 完成渲染，城镇背景、玩家、NPC、HUD、小地图和技能栏可见；
- 控制台在本次加载时间之后没有新的 error/warn；
- NPC 资产注册表正常，旅店主人和铁匠不会因 PCK 资源重映射而缺失；
- 输入焦点、移动、Esc 菜单、L 手册和 M 地图至少各执行一次人工冒烟。

## 6. 发布边界

- 不把 `.tools/`、密钥、用户校验点或本地测试报告提交到 Git。
- `releases/knight-web/game.pck`、WASM、PNG 等按 `.gitattributes` 走 Git LFS。
- 真实供应商调用可能计费，必须由用户在创作控制台明确发起；B-14 不把本地回环验收冒充为真实付费账号验收。
- 当前世界生成只组合经过登记的 2.5D 组件和 NPC 资产，不执行 Agent 生成的 GDScript、场景源码、Shader 或任意文件路径。
