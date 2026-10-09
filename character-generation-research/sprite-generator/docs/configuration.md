# Configuration and command line

## Merge order

Configuration is a recursive mapping merge. From lowest to highest precedence:

1. committed `config.default.yaml`;
2. ignored `config.yaml`, if it exists beside the default;
3. each repeatable `--config PATH`, from left to right;
4. explicit scalar CLI overrides such as `--server` or `--seed`.

Resolved duplicate override paths are loaded once, at their first occurrence.
An override file can contain only the nested keys it changes. YAML documents
must be mappings. `config.yaml` is intentionally listed in `.gitignore`.

The same merged model mapping configures every graph in `--workflow staged`.
Each staged graph contains the five connected generation-model leaves from the
bundled graph; dependency images are explicit `LoadImage` inputs. Configured
stage graph hashes participate in durable cache identity.

## Default schema

Animation definitions are a separate catalog from the runtime schema below.
Use repeatable `--definitions PATH` overlays in staged mode to add or replace
animation stages. See [animation-authoring.md](animation-authoring.md) for an
example, input dependencies, prompt files, and frame-selection policies.

```yaml
comfyui_url: http://localhost:8188
generation_timeout: 7200
seed: -1
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

workflow_models:
  "149":
    clip_name: qwen3vl_32b_minimax_h3_int8_convrot.safetensors
  "154":
    unet_name: DasiwaMinimaxH3_dasiwaREF2VAHybridV1.safetensors
  "163":
    lora_name: minimax_h3_fl2v_turbo_4step_v1.2_768p_comfyui_bf16.safetensors
  "173":
    vae_name: minimax_h3_video_vae_fp16.safetensors
  "174":
    vae_name: minimax_h3_audio_vae_fp32.safetensors
```

Model strings are server-relative selections for their loader node, not local
filesystem paths. Standard folders are `models/checkpoints` for SDPose,
`models/background_removal` for BiRefNet, `models/text_encoders` for node 149,
`models/diffusion_models` for node 154, `models/loras` for node 163, and
`models/vae` for nodes 173 and 174.

## Validation

- URL: absolute HTTP or HTTPS, no credentials, query, or fragment.
- Timeout/poll interval: positive finite seconds.
- Seed: integer `-1`, or `0..9223372036854775807`; booleans are rejected.
- Sprite dimensions: positive integers; booleans are rejected.
- Dummy top padding: a nonnegative finite percentage. It is measured from the
  pre-padding dummy render height, rounded to pixels, and only increases the
  dummy/workflow height.
- Animated frame counts: integers of at least 2. Crouch is fixed at one frame.
- Directions: exactly four nonempty comma-separated labels.
- Period range: finite and `0 < min < max`.
- SDPose batch size: positive integer.

For configured workflows, model entries must exactly match every connected
`.safetensors` leaf by node ID and input name. This is deliberate fail-fast
behavior. Unconnected nodes are ignored. An arbitrary workflow path with no
explicit additional config layer may retain its graph model values; supplying
model overrides opts it into exact validation.

## CLI option ownership

| Option | Mode | Default/source |
| --- | --- | --- |
| `--workflow PATH|staged|bundled|full|original|legacy` | image | absent selects direct video mode |
| `--actions CSV` | staged | all actions when neither selector is supplied |
| `--poses CSV` | staged | no poses |
| `--poses-only` | staged | all poses and no actions |
| `--dry-run` | staged | false; prints dependency plan without inference |
| `--definitions PATH` | staged | repeatable animation catalog overlays |
| `--set-frames NAME=COUNT` | staged | generic explicit export frame-count override |
| `--list-animations` | staged | list catalog outputs without image input or output directory |
| `--config PATH` | both | repeatable YAML layer |
| `--server URL` | both | merged `comfyui_url` |
| `--generation-timeout SECONDS` | both | merged `generation_timeout`, 7200 |
| `--poll-interval SECONDS` | both | 2.0 |
| `--seed INTEGER` | image | merged `seed`, -1 |
| `--idle-style neutral|feminine` | image | neutral |
| `--sprite-render-width/height` | image | merged 400x512 |
| `--pad-top-percent PERCENT` | image | merged `pad_top_percent`, 0 |
| `--idle-frames` | image | merged 4 |
| `--run-frames`, `--frame-count` | both | merged 8 |
| `--walk-frames` | image | merged 8 |
| `--jump-frames` | image | merged 8 |
| `--crouch-walk-frames` | image | merged 8 |
| `--sprite-box-height`, `--sprite-height` | both | merged 256 |
| `--split-algorithm blobs|quarters` | both | blobs |
| `--directions CSV` | both | right,left,back,front |
| `--crop X0 X1 Y0 Y1` | direct | selected quarter otherwise |
| `--views`, `--view-index` | direct | 4 and 3 |
| `--min-period`, `--max-period` | direct | 0.35 and 3.0 seconds |
| `--frames-only` | direct | false |

An internal hidden `--generation-only` flag belongs to image workflow mode and
ends after generating/downloading videos. `--worker` is the hidden direct-mode
child entry used by the batch parent. Neither is intended as the normal public
interface.

`bundled` and `full` select the packaged full-animation graph. `original` and
`legacy` select the retained run/idle graph. A filesystem path selects a custom
ComfyUI API workflow.

## Effective settings and resume

Web jobs archive the complete resolved configuration before enqueueing. Passing
that resolved mapping through generation and postprocessing prevents later
changes to `config.yaml` from changing queued or resumed work. Settings saves
use a revision token and atomic replacement, preserve unrelated keys, and retain
the previous bytes in `config.yaml.bak`. Resetting a field removes its override
so the portable default is inherited.

The configured workflow fingerprint is a SHA-256 of strict canonical JSON after
model overrides. Main workflow model changes therefore invalidate an existing
generation state. Dummy source hashes and requested render dimensions are also
resume identity. Postprocess models and action settings are stored in the
package request, so an already complete package is reused only for an exact
request match.

For `seed: -1`, a fresh output chooses one value using Python's standard
pseudorandom generator. The saved seed is shared by all characters in that
invocation. A legacy state without a seed attempts to recover node 124 from its
rendered workflows before generating a replacement.
