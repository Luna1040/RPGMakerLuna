# RPGMakerLuna Godot 主工程

这是仓库中供团队继续开发的唯一 Godot 主工程。请导入本目录的 `project.godot`，不要把网页导出目录或其他历史实验目录当作工程打开。

## 环境要求

- Godot **4.7.2 标准版**（GDScript，不需要 .NET 版）
- Git
- Git LFS
- Python 3（只用于工程自检和自动化测试，运行游戏不需要）

引擎、`.godot/` 导入缓存、测试日志、模型权重和本地密钥不进入仓库。素材源文件通过 Git LFS 管理，因此不要使用 GitHub 的“Download ZIP”获取开发工程。

## 首次获取工程

在 PowerShell、终端或 Git Bash 中执行：

```sh
git lfs install
git clone https://github.com/Luna1040/RPGMakerLuna.git
cd RPGMakerLuna
git switch b/content-patch-foundation
git lfs pull --include="godot-belt-map/**"
```

`b/content-patch-foundation` 是当前成员 B 成果所在分支；该分支合并后，直接使用仓库默认分支即可。

先执行不依赖 Godot 的完整性检查：

```sh
python3 godot-belt-map/tools/verify_checkout.py
```

Windows 也可以使用：

```powershell
py -3 godot-belt-map/tools/verify_checkout.py
```

看到 `PASS: Godot checkout is complete` 后再打开编辑器。如果检查报告 LFS 指针未还原，重新运行 `git lfs pull --include="godot-belt-map/**"`。该自检只验证主工程，不要求下载仓库里的历史实验和网页归档。

## 用 Godot 打开

1. 启动 Godot 4.7.2，在项目管理器选择“导入”。
2. 选择 `godot-belt-map/project.godot`。
3. 第一次打开时等待右下角素材导入完成。
4. 按 **F5** 或点击右上角“运行项目”。入口场景是 `res://stage.tscn`。

macOS 命令行方式：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --editor --path godot-belt-map
```

Windows 命令行方式（按实际解压位置修改 Godot 路径）：

```powershell
& "C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --editor --path godot-belt-map
```

工程不依赖开发者个人的绝对路径；运行现有玩法也不需要 API Key、ComfyUI、Node.js 或额外 Python 包。

## 团队继续开发

主要目录：

- `stage.tscn` / `stage.gd`：当前运行入口和庭院舞台。
- `systems/`：剧情、战斗、存档、内容生成和 Agent 运行系统。
- `content/`：基础内容、生成协议与 JSON Schema。
- `assets/`：运行时美术、字体、NPC 和角色资源。
- `characters/`：玩家角色场景、动画与战斗表现。
- `tests/`：跨平台回归测试及测试运行器。
- `FOUNDATIONS.md`：底层模块、数据边界和扩展说明。

推荐每名成员从最新分支建立自己的短分支：

```sh
git switch b/content-patch-foundation
git pull
git lfs pull --include="godot-belt-map/**"
git switch -c member/your-feature
```

协作规则：

- 不提交 `.godot/`、`test-results/`、日志、存档或个人密钥；这些路径已被忽略。
- 不手动编辑 `.godot/imported/`；Godot 会在每台机器上重新生成。
- 新增 PNG、音频、视频、字体、压缩包等大文件前确认由 `.gitattributes` 中的 Git LFS 规则管理。
- 不复制第二份主工程。所有可继续修改的 Godot 源文件都以本目录为准，网页目录只是导出产物。
- 修改 JSON 内容后保持 UTF-8 编码，并先运行完整性检查。
- 提交前确认 `git status` 中没有缓存、测试截图或无关素材。

## 提交前验证

先检查文件完整性：

```sh
python3 godot-belt-map/tools/verify_checkout.py
```

再运行完整回归。macOS 示例：

```sh
python3 godot-belt-map/tests/run_tests.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --suite all
```

Windows PowerShell 示例：

```powershell
py -3 godot-belt-map/tests/run_tests.py `
  --godot "C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" `
  --suite all
```

当前测试基线为一次资源导入检查加 **36 项自动化测试**，正常结果是 `PASS: 37 passed, 0 failed.`。测试报告写入被忽略的 `godot-belt-map/test-results/`。

## 常见问题

- 图片、字体或音频打不开：运行 `git lfs pull --include="godot-belt-map/**"`，再执行工程完整性检查。
- 文件开头出现 `version https://git-lfs.github.com/spec/v1`：当前拿到的是 LFS 指针，不是真实素材。
- 第一次打开较慢：让 Godot 完成导入，不要提交生成的 `.godot/`。
- 运行到错误场景：使用“运行项目 / F5”，不要从历史实验目录打开其他工程。
- 更新后资源异常：关闭 Godot，确认代码已提交，再删除本机 `godot-belt-map/.godot/` 让编辑器重建缓存；不要把缓存上传。
