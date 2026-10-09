# Web deployment

Install the project with its optional web dependencies and build the independent
frontend before starting the service:

```bash
python -m pip install -e '.[web]'
cd web && npm ci && npm run build && cd ..
sprite-extractor-web --host 127.0.0.1 --port 8787 \
  --data-root /srv/sprite-extractor --config /srv/sprite-extractor/config.yaml
```

The production server serves the compiled `web_static` files and API from one
origin. Node is not needed after the build. Set `SPRITE_EXTRACTOR_BASE_PATH` or
`--base-path /sprites` when a reverse proxy mounts the application below a path.
For development and contract tests, install both extras with
`python -m pip install -e '.[web,test]'`.

For access beyond loopback, configure `SPRITE_EXTRACTOR_USERNAME`,
`SPRITE_EXTRACTOR_PASSWORD`, and a long random `SPRITE_EXTRACTOR_SECRET`.
Terminate HTTPS at the reverse proxy. Allow request bodies larger than the
configured upload maximum, permit large streamed downloads, and disable proxy
buffering for `/api/jobs/*/events`.

For a trusted home LAN where a password is intentionally unwanted, add
`--no-auth` or set `SPRITE_EXTRACTOR_NO_AUTH=true`. Omitting this opt-in retains
the credential-backed or loopback-only defaults. CSRF and same-origin checks
remain active, but every device that can reach the server receives full operator
access. Keep this mode behind the LAN firewall and never expose it publicly.

`SPRITE_EXTRACTOR_UPLOAD_LIMIT_BYTES` (default 20971520) and
`SPRITE_EXTRACTOR_PIXEL_LIMIT` (default 40000000) set encoded and decoded image
limits; the matching flags are `--upload-limit` and `--pixel-limit`. For an
Nginx `/sprites` mount, proxy `/sprites/` to `http://127.0.0.1:8787`, preserve
the public Host, set the body limit just above the application limit, and disable
buffering for event streams. Accept forwarded scheme/host values only from the
trusted local proxy and terminate HTTPS there.

The data root contains uploads, immutable job/config/definition snapshots,
SQLite queue state, generation sets, submission journals, public package
metadata, and download ZIPs. Back it up as one unit. The configured YAML path is
the file edited by Settings; it may live under the data root. The service never
writes the packaged `config.default.yaml`.

Run exactly one API scheduler for a data root. It claims one queued job at a
time and launches generation in a separate Python process. A browser disconnect
does not affect that process. ComfyUI submissions, including postprocessing,
use the durable journal and refuse ambiguous duplicates.

A second, temporary UI/API process may share the data root only with
`--no-scheduler`. Use `--static-root /path/to/compiled-web` to serve a separate
frontend build without replacing the installed `web_static` directory. The
equivalent environment settings are `SPRITE_EXTRACTOR_NO_SCHEDULER=true` and
`SPRITE_EXTRACTOR_STATIC_ROOT=/path/to/compiled-web`. The existing scheduler
continues to own and execute the shared queue; the secondary process is for
read-only deployment validation and ordinary API requests.

Use a service account that owns the data root and can reach ComfyUI, FFmpeg, and
FFprobe. Do not run it as root. The CLI and web workers share an output-tree lock
around generation and packaging.

The initial worker host targets Linux: cross-process locking uses `fcntl`, and
restart ownership checks compare the process ID with Linux `/proc` start time to
avoid mistaking a reused PID for the original worker.
