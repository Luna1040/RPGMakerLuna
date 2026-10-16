#!/bin/zsh
set -e
GAME_DIR="${0:A:h}"
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
if [[ ! -x "$GODOT_BIN" ]]; then
  echo "请先安装 Godot 4.7.2 到 /Applications/Godot.app，再打开本启动器。"
  read -r "?按回车退出"
  exit 1
fi
"$GODOT_BIN" --headless --path "$GAME_DIR" --editor --import
exec "$GODOT_BIN" --path "$GAME_DIR" --windowed
