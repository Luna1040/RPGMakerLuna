@echo off
setlocal
set "PATH=%~dp0.tools\node-v22.17.0-win-x64;%~dp0cocos-cli\node_modules\.bin;%PATH%"
set "COCOS_CLI_GL_NODE=%TEMP%\cocos-cli-native-node127\webgl.node"
if not exist "%COCOS_CLI_GL_NODE%" (
  if not exist "%TEMP%\cocos-cli-native-node127" mkdir "%TEMP%\cocos-cli-native-node127"
  copy /y "%~dp0cocos-cli\node_modules\gl\build\Release\*" "%TEMP%\cocos-cli-native-node127\" >nul
)
"%~dp0.tools\node-v22.17.0-win-x64\node.exe" "%~dp0cocos-cli\dist\cli.js" %*
exit /b %errorlevel%
