# 安装与团队 ComfyUI API

## 安装 skill

解压分享包，将 `game-production` 整个文件夹复制到 `~/.codex/skills/`（或 `$CODEX_HOME/skills/`）。Windows 通常为 `%USERPROFILE%\.codex\skills\`，macOS 为 `~/.codex/skills/`。重新打开会话，调用 `$game-production`。其他支持 SKILL.md 的 Agent 按其安装路径放置；不支持的工具可直接读取该文件与 references。

只运行客户端需要 Python 3.10+，抠图/导出额外安装 `pillow numpy onnxruntime`。模型不在分享包内。

## 当前团队采用 STCP

主机的独立 ComfyUI 仅监听 `127.0.0.1:9316`；frpc 的 STCP 转发该端口。成员持有单独私发的 visitor 配置，运行 frpc 后，通过自己机器的 `http://127.0.0.1:19316` 调用。没有公开的 HTTP URL，也不需要在公网开放 ComfyUI 端口。

依据 [frp 官方 STCP 示例](https://gofrp.org/en/docs/examples/stcp/)。STCP 需要成员也运行 frpc，并持有服务端认证与隧道 secretKey；共享凭据只适用于可信团队，不能把这些配置提交 Git 或随公开 skill 发出。该方案不提供每成员任务隔离、配额或密钥单独撤销，团队成员可以看到并影响实例上的任务。需要分用户控制时再增加身份网关和批准工作流白名单。

维护者需要保存自己的 frpc.exe、主机配置、启动脚本；成员安装对应 Windows/macOS/Linux 的 frpc（本次使用 0.71.0），运行 `frpc -c visitor.toml`。主机保持在线且 ComfyUI 启动，访问端不要绑定 `0.0.0.0`。更换 secretKey 并重启主机与成员的隧道即可撤销旧隧道凭据；服务端 auth token 属服务器级凭据，应由管理员另行管理。

## 一次生成

在 skill 目录运行。直接使用主机时将 URL 改成 `http://127.0.0.1:9316`；成员使用 19316。

```sh
python scripts/comfy_client.py check --workflow assets/h3-reference-api.json
python scripts/comfy_client.py submit --workflow assets/h3-reference-api.json --reference my-character.png --prompt-file motion.txt --seed 731420 --out jobs/hero-attack-01
python scripts/comfy_client.py wait --out jobs/hero-attack-01 --timeout 7200
```

`motion.txt` 写完整的身份+动作+镜头提示，参考 art-production.md。参考上传 PNG。客户端为上传与输出生成唯一前缀，避免团队互相覆盖。`submit` 只排队，`wait` 才轮询完成并下载原视频/帧。输出索引记录服务端文件名与节点，数字下载名不是源帧号；从 SaveImage 节点顺序映射源帧后再选帧。

保存 job.json 后可断点续查；若提交 HTTP 超时且未保存 prompt_id，查队列/history 中 submission.json 的 client_id，找回 ID 写入 job.json 后再 wait，不能盲目重复提交。

H3 客户端修改固定节点 1/6/8/14/15，适用于随附模板；普通 ComfyUI 图可调用 `/upload/image`、`/prompt`、`/history/{id}`、`/view`，不要把任意模板套进这些节点编号。通过 `/object_info` 确认节点/schema和已安装模型，不能拿 UI workflow 代替 API format。

## 抠图、选择和导出

```sh
python scripts/matte_frames.py --model /path/to/birefnet-lite.onnx --source jobs/hero-attack-01/outputs --out work/hero-attack-alpha
python scripts/pack_frames.py --source work/hero-attack-alpha --selection hero-attack-selection.json --out exports/hero-attack-v1
```

先确认 source 目录只有该动作的源 PNG；对抠图 review 深浅底图片与动画进行检查，然后编写 selection（结构见 assets/selection.example.json）。这里的打包输出是单动作 action.json，接入游戏时组合成角色动画表；不会自动修改你的项目。

主机开销管理：让 ComfyUI 串行 GPU 队列，不批量启动多个实例；不要调用全局 interrupt/free 来取消别人的任务。查看输出失败信息再修节点/模型，不自动下载巨量文件。主机已有其他 ComfyUI 时保持其端口与配置不变。
