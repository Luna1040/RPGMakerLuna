
### 团队成员首次运行 AI 开发版（Windows）

`运行游戏-AI开发版.cmd` 需要 Node.js 20 以上（已验证 22.x）、Godot 4（已验证 4.7.2）以及已登录的 Codex。仓库不包含这些程序。启动器现在依次查找环境变量、系统 PATH 和仓库本地工具目录，不再要求固定的 Node.js 文件夹名称。

安装 Node.js 后重新打开终端。Godot 可放在 `.tools/godot/`，或在 PowerShell 中指定自己的完整路径（替换下列示例）：

```powershell
[Environment]::SetEnvironmentVariable('GODOT_BIN', 'D:\Tools\Godot_v4.7.2-stable_win64.exe', 'User')
# 只有 Node.js 不在 PATH 时才需要：
[Environment]::SetEnvironmentVariable('NODE_BIN', 'D:\Tools\nodejs\node.exe', 'User')
```

重新打开终端后，可先在仓库根目录检查依赖，不启动游戏：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\运行游戏-AI开发版.ps1 -CheckOnly
```

看到 `Launcher dependencies OK.` 后双击启动器。缺少程序时会明确显示需要配置的变量；若提示变量指向不存在的文件，请修正或删除旧变量。路径可以含空格。Codex 仍支持 `CODEX_BIN`，并自动查找桌面版随附的程序。
