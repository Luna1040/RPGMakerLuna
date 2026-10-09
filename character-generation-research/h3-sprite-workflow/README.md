# Sprite Extractor

Sprite Extractor turns a character reference image, or a directory of images,
into four-direction idle, running, walking, jumping, crouching, and crouch-walking
sprites. It sends the bundled
workflow to an already-running local ComfyUI instance, downloads the resulting
videos, selects animation frames, removes their backgrounds, and exports a
transparent sprite sheet plus WebP animations.

This guide assumes ComfyUI is already installed and working. Model inference,
including SDPose and background removal, runs inside ComfyUI; the command-line
tool needs only a small ordinary Python environment.

## Web interface

The browser interface provides image upload, animation selection, render
settings, saved jobs, sprite-sheet and animation previews, and downloads. Its
Settings page edits the server's YAML defaults. Required animation dependencies
are generated automatically, and compatible work is retained for later renders.
Animation choices also show completed raw videos and generated images while a
render progresses. Click a thumbnail to open the original media in a lightbox.

For cycle-based animations, **Review cycles** compares the sampled alternatives
with the **System pick** preselected. Choose another cycle and select **Update
sprite sheet** to rebuild the package from saved generation and pose analysis.
The previous download stays available. Older renders offer an explicit
**Analyze saved video for cycles** action.

The interface uses a Wayfarer Forge-inspired theme through locally owned assets;
it builds and runs independently. Generation runs
on the backend's configured ComfyUI server, so the browser can be on another
computer. Prompt-based animation authoring is a later feature.

See [Using the web interface](docs/web-user-guide.md) for the workflow and
[Web deployment](docs/web-deployment.md) for installation and server setup.
The existing CLI remains available without the optional web dependencies.

From the repository root, with your Python environment active:

```bash
python -m pip install -e '.[web]'
npm --prefix web ci
npm --prefix web run build
sprite-extractor-web --host 127.0.0.1 --port 8787 \
  --data-root ./web-data --config ./config.yaml
```

Open `http://127.0.0.1:8787/`. This command uses the repository's configuration
file for server defaults and retains uploads and generated work in `web-data`.
For access from another computer, follow the authentication and reverse-proxy
instructions in the deployment guide.

## Install from GitHub

Clone the GitHub repository using the URL shown by its **Code** button, then
enter this project directory:

```bash
git clone https://github.com/envy-ai/sprite-generator.git
cd sprite-generator
```

Create a virtual environment, then install Sprite Extractor's runtime
dependencies and command:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m pip install -e . --no-deps
```

FFmpeg and FFprobe must also be available on `PATH`.

## Configure

Portable defaults live in [`config.default.yaml`](config.default.yaml). Model
filenames are relative to the standard model folder used by their ComfyUI
loader node:

```yaml
comfyui_url: http://localhost:8188
generation_timeout: 7200 # seconds (120 minutes)
seed: -1 # choose and record a random seed for each fresh run
sprite_box_height: 256
sprite_render_width: 400
sprite_render_height: 512
pad_top_percent: 0

animation_frames:
  idle: 4
  run: 8
  walk: 8
  jump: 8
  crouch_walk: 8

postprocess:
  sdpose_batch_size: 8

postprocess_workflow_models:
  sdpose:
    "2":
      ckpt_name: sdpose_wholebody_fp16.safetensors
  background-removal:
    "2":
      bg_removal_name: BiRefNet.safetensors
```

The standard folders are `models/checkpoints` for SDPose,
`models/background_removal` for BiRefNet, `models/text_encoders` for node 149,
`models/diffusion_models` for node 154, `models/loras` for node 163, and
`models/vae` for nodes 173 and 174.

For local changes, copy the defaults to the ignored `config.yaml` and edit only
what differs. Nested mappings are merged, so a local file may be partial:

```bash
cp config.default.yaml config.yaml
```

Configuration is read in this order, with later values winning:

1. `config.default.yaml`
2. `config.yaml`, when present
3. Each repeatable `--config PATH` supplied on the command line

Every connected `.safetensors` input must remain configured. Unconnected
workflow branches are intentionally ignored.

Both workflows use the four included 404x640 dummy views under
[`workflows/dummy-views`](workflows/dummy-views). A pixel-art alternative is
included under
[`workflows/dummy-views-pixel-art`](workflows/dummy-views-pixel-art). Select it,
or any compatible folder, with `--dummy-image-folder PATH` or the
`dummy_image_folder` configuration setting. The folder must
contain `1-right.png`, `2-left.png`, `3-back.png`, and `4-front.png`. Custom
dummy images can have any dimensions and are resized with nearest-neighbor
sampling to preserve pixel edges. At render time, the default views use images
whose original bottom 48 pixels were removed and replaced with 48
pixels of their upper-left background color at the top. It scales each one
proportionally to 512 pixels high, then center-crops or pads it to
the configured per-view render size using its top-left background color, joins
the four views horizontally, and optionally adds `pad_top_percent` of the
original rendered dummy height above the dummy using that color. This padding
does not crop or alter the character reference image. The tool uploads the
result and sets the workflow's initial width and height to its actual dimensions.
The default 400x512 per-view size with 0% padding produces a 1600x512 reference.
Put the configured SDPose checkpoint in
ComfyUI's `models/checkpoints` directory and the configured background-removal
model in `models/background_removal`. These checkpoints are not included in the
repository. The post-processing workflows use ComfyUI's built-in
`SDPoseKeypointExtractor`, `PreviewAny`, `LoadBackgroundRemovalModel`, and
`RemoveBackground` nodes.

## Run

Start ComfyUI normally, then run Sprite Extractor with one reference image or a
directory of reference images:

```bash
sprite-extractor path/to/reference.png \
  --output output/character-run-idle \
  --workflow bundled \
  --dummy-image-folder workflows/dummy-views-pixel-art
```

To generate only chosen outputs, use the split, dependency-aware workflow:

```bash
sprite-extractor path/to/reference.png --output output/character \
  --workflow staged --actions jump,walk --jump-frames 6 --walk-frames 8
```

New animations can be defined in YAML with external prompt files, generation
settings, input dependencies, and frame-selection rules. Load an overlay with
`--definitions PATH` and use `--set-frames NAME=COUNT` for an action's exported
frame count. See [Authoring animation definitions](docs/animation-authoring.md)
for a complete example. List available outputs without generating anything:

```bash
sprite-extractor --workflow staged --list-animations
```

`--actions` accepts `idle,run,jump,crouch,crouch-walk,walk`. The tool resolves
and caches the transition stages needed by those outputs. For example, `jump`
runs `run -> jump`, while `walk` runs
`run -> stop -> walk-start -> walk`. A later invocation against the same output
can request more actions without regenerating completed compatible stages.

Use `--poses` to export named key images independently of animation selection.
The names are `run-first`, `jump-last`, `standing`, `idle-last`, `crouch`,
`crouch-walk-start`, `crouch-walk-last`, `walk-start`, and `walk-last`.
Supplying `--poses` without `--actions` produces only those stills;
`--poses-only` selects all of them. With neither selector, staged mode selects
all six actions. To inspect the resolved stages without writing files or
contacting ComfyUI, add `--dry-run`.

Each requested multi-frame action still uses its action-specific frame option.
Dependencies create videos and key frames for later stages, but only selected
actions and poses are placed in the final sprite package. Packages without a
selected run animation derive their ground origin from the bottom of the
selected foreground alpha and record that fallback in the manifest.

Useful options include `--idle-style neutral|feminine`, `--seed`, `--idle-frames`,
`--run-frames`, `--walk-frames`, `--jump-frames`, and
`--crouch-walk-frames`. Their defaults are
set under `animation_frames` in `config.yaml`. Set `sprite_box_height` in
`config.yaml`, or use
`--sprite-box-height PIXELS` for one run; it defaults to 256. Use `--server URL`
to override `comfyui_url` for one run. `generation_timeout` is measured in
seconds and defaults to 7200 (120 minutes); use `--generation-timeout SECONDS`
for one run. Set `sprite_render_width` and
`sprite_render_height` in YAML, or override them with
`--sprite-render-width PIXELS` and `--sprite-render-height PIXELS`. Set
`pad_top_percent`, or use `--pad-top-percent PERCENT`, to prepend dummy-only
background padding equal to that percentage of its pre-padding render height.
Use `--dummy-image-folder PATH` to replace the four bundled pose guides for one
generation run.
Use one or more `--config PATH` options
for additional YAML overrides, including alternate models. Run
`sprite-extractor --help` for the complete command reference.

`seed` defaults to `-1`, which chooses one pseudorandom seed for each fresh
invocation and records the resolved nonnegative value in `generation-state.json`.
Resuming that output reuses the recorded seed. Set `seed` in YAML or pass
`--seed INTEGER` for deterministic generation.

By default, `--split-algorithm blobs` removes matte values below 5% opacity,
combines the cleaned alpha masks from every selected frame, finds the four
largest connected foreground components in that union, and chooses one set of
cuts halfway through the three horizontal spaces between them. Those exact cuts
are reused for every action and frame. Each animation and direction is then
centered independently from the union of its frame alpha masks; one offset is
reused for all frames in that animation to prevent jitter. Use
`--split-algorithm quarters` to restore the original equal-quarter splitter.

The bundled full workflow uses the Minimax H3 full-animation 1.3.1 graph and
exports the configured number of evenly spaced jump
frames, the last frame of the stand-to-crouch clip as the still crouch pose,
and independently configured run, walk, and crouch-walk frame counts. Run,
walk, and crouch-walk cycles use the same right-foot cycle-selection heuristic.
When several complete cycles are available, the selector uses their temporal
median; for an even count it chooses the earlier of the two central cycles.
The intermediate stationary crouch-to-crouch-walk and idle-to-walk clips are
not downloaded or placed in the sprite sheet.
The retained original run/idle workflow uses the same updated feminine and
neutral walking-to-idle transition prompts as the 1.3.1 graph.
Use `--workflow original` to select the earlier run-and-idle-only workflow;
`--workflow full` is an alias for `--workflow bundled`.

Each character is written beneath the output directory with downloaded videos,
generation provenance, a transparent PNG sheet, and a WebP per animated action
and direction (the one-frame crouch pose is sheet-only). Every WebP loops,
including animations such as jump that are conceptually one-shot. Interrupted
generations can be resumed
by running the same command again with the same inputs and settings.

## Code documentation

Maintainers and coding agents should start with
[`docs/agent-overview.md`](docs/agent-overview.md). The complete code reference
is indexed in [`docs/README.md`](docs/README.md).

## License

Sprite Extractor is free software licensed under the
[GNU Affero General Public License, version 3 only](LICENSE).
