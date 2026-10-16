"""Local administrator bootstrap. Private material stays outside shareable-skills."""
from pathlib import Path
import json
import secrets
import tomllib

root = Path(__file__).resolve().parent
private = root / '.team-comfy-private'
private.mkdir(exist_ok=True)
source = Path.home() / 'Downloads/frp_0.71.0_windows_amd64/frpc-flux2.toml'
config = tomllib.loads(source.read_text(encoding='utf-8-sig'))
quote = lambda value: json.dumps(value, ensure_ascii=False)
secret_file = private / 'tunnel-secret.txt'
if not secret_file.exists():
    secret_file.write_text(secrets.token_urlsafe(32), encoding='utf-8')
secret = secret_file.read_text(encoding='utf-8')
common = f'''serverAddr = {quote(config['serverAddr'])}
serverPort = {config['serverPort']}
auth.method = "token"
auth.token = {quote(config['auth']['token'])}
transport.tls.enable = true
'''
server = common + f'''
[[proxies]]
name = "game-production-h3-private"
type = "stcp"
secretKey = {quote(secret)}
localIP = "127.0.0.1"
localPort = 9316
transport.useEncryption = true
'''
visitor = common + f'''
[[visitors]]
name = "game-production-h3-visitor"
type = "stcp"
serverName = "game-production-h3-private"
secretKey = {quote(secret)}
bindAddr = "127.0.0.1"
bindPort = 19316
transport.useEncryption = true
'''
server += server[server.index('[[proxies]]'):].replace('game-production-h3','game-production-flux').replace('9316','9315')
visitor += visitor[visitor.index('[[visitors]]'):].replace('game-production-h3','game-production-flux').replace('9316','9315')

(private / 'host.toml').write_text(server, encoding='utf-8')
(private / 'visitor.toml').write_text(visitor, encoding='utf-8')
(private / '.gitignore').write_text('*\n', encoding='utf-8')
print('Created private host and visitor configs; no secrets printed.')
