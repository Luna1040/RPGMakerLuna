"""Package only allowlisted skill files; never include private service configs."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

root = Path(__file__).resolve().parent
source = root / 'shareable-skills'
private = root / '.team-comfy-private'
release = root / 'releases/game-production-skill.zip'
files = [source / '分享说明.md'] + sorted(p for p in (source / 'game-production').rglob('*')
                                         if p.is_file() and '__pycache__' not in p.parts and p.suffix in {'.md', '.py', '.yaml', '.json'})
import tomllib
secrets = tomllib.loads((private / 'host.toml').read_text(encoding='utf-8'))
for file in files:
    data = file.read_bytes()
    for value in (secrets['auth']['token'], secrets['proxies'][0]['secretKey'], secrets['serverAddr']):
        assert value.encode() not in data, 'Private connection value found in public bundle'
with zipfile.ZipFile(release, 'w', zipfile.ZIP_DEFLATED) as z:
    for file in files:
        z.write(file, file.relative_to(source))
release.with_suffix('.zip.sha256').write_text(hashlib.sha256(release.read_bytes()).hexdigest() + '  ' + release.name + '\n', encoding='utf-8')

kit = private / 'team-connection'
kit.mkdir(exist_ok=True)
shutil.copyfile(private / 'visitor.toml', kit / 'visitor.toml')
frp = Path.home() / 'Downloads/frp_0.71.0_windows_amd64'
for name in ('frpc.exe', 'LICENSE'):
    shutil.copyfile(frp / name, kit / name)
(kit / '连接生图主机.cmd').write_bytes(b'@echo off\r\ncd /d "%~dp0"\r\nfrpc.exe -c visitor.toml\r\npause\r\n')
(kit / 'connect.sh').write_text('#!/bin/sh\ncd "$(dirname "$0")" || exit 1\nexec ./frpc -c visitor.toml\n', encoding='utf-8')
(kit / '使用说明.txt').write_text('仅限可信队员，禁止公开或提交 Git。此包含 frp 服务器级认证和团队隧道密钥。\n'
    'Windows 双击连接生图主机.cmd，保持窗口运行。成功后接口为 http://127.0.0.1:19316 。\n'
    'macOS/Linux 从 https://github.com/fatedier/frp/releases/tag/v0.71.0 下载对应架构 frpc 到此目录，chmod +x frpc，sh connect.sh。\n'
    '安装公开 skill 包后运行 python scripts/comfy_client.py check 验证。主机必须在线。\n'
    '所有成员共享此专用实例的队列和历史；勿取消他人作业。关闭本访问窗口即断开本成员连接。\n'
    '泄露时联系维护者轮换隧道 secretKey；服务器 auth token 也在包内，需服务器管理员另行轮换。\n', encoding='utf-8')
with zipfile.ZipFile(private / '团队连接包-仅私发.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for file in sorted(kit.iterdir()):
        z.write(file, file.name)
print(json.dumps({'public_files': len(files), 'public_bytes': release.stat().st_size,
                  'public_secret_scan': 'passed', 'private_kit': 'created separately'}, ensure_ascii=False))
