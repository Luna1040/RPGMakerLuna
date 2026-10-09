@echo off
call "%~dp0cocos.cmd" --no-interactive preview --project "%~dp0pixel-rpg-cli-test" --scene db://assets/Main.scene --port 9527 --no-open
