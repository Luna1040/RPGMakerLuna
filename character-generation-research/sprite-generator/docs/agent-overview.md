# Agent overview

Read this file first in a new session. Sprite Extractor is a Python 3.11 command
that has two modes behind one CLI:

1. With `--workflow`, it turns character reference images into ComfyUI videos,
   extracts animation frames, removes backgrounds through ComfyUI, and publishes
   sprite sheets and looping WebPs.
2. Without `--workflow`, it analyzes existing four-view videos, selects one
   synchronized motion cycle, and optionally makes a single-cycle sprite sheet.

The installed pipeline does not start ComfyUI, install models, score visual
quality, or use Torch locally. NumPy, Pillow, and PyYAML are its Python runtime
dependencies; FFmpeg and FFprobe must be on `PATH`. A retained internal
`diagnose_cycle extract` command can invoke a local DWPose/Torch checkout for
diagnostics, but the normal CLI uses the ComfyUI `extract-sdpose` path and does
not install those legacy dependencies.

## Read order

For most work, inspect files in this order:

1. `src/sprite_extractor/extract_frames.py` — CLI and mode dispatch.
2. `src/sprite_extractor/generate_character.py` — generation state and resume.
3. `src/sprite_extractor/comfy_workflow.py` — config, graph rendering, API client.
4. `src/sprite_extractor/character_animations.py` — full package orchestration.
5. `diagnose_cycle.py`, `media.py`, `comfy_postprocess.py`, `sprite_split.py`, and
   `sprite_sheet.py` — analysis and image-processing details.
6. The contract tests under `tests/` — executable statements of the contracts.

For catalog-backed staged work, also read `animation_definitions.py` (schema,
prompts, registry), `workflow_templates.py` (shared graph contracts and semantic
signatures), and `definition_runtime.py` (revisions, migration, and packaging).
See [animation-authoring.md](animation-authoring.md) for adding an animation.

For web cycle review, read `cycle_review.py`, `web/worker.py`, and
[`cycle-review-design.md`](cycle-review-design.md). Automatic exports retain the
lower-median cycle choice. Review uses durable sampled complete cycles and
creates a child job to rebuild the full package from pinned source revisions.
Revision work must never regenerate video or fall back to SDPose when pinned
analysis is unavailable. Explicit old-render analysis is a separate job kind;
GET routes never start model work. Preserve the previous published package on
failure and keep `quality_evaluated: false` after a user choice.

Use [`architecture.md`](architecture.md) for the full module map,
[`configuration.md`](configuration.md) for settings, and
[`output-format.md`](output-format.md) before changing JSON output.

## End-to-end flow

```text
reference image(s)
  -> merge config layers and validate connected model inputs
  -> scale/crop/pad four bundled dummy views; upload dummy and references
  -> render only approved workflow leaves; queue every character
  -> poll ComfyUI and download action videos
  -> wait for an idle queue and unload cached models
  -> SDPose the right/front quarter of run, walk, and crouch-walk videos
  -> choose the lower temporal median complete right-foot cycle
  -> sample idle/jump/crouch frames
  -> run all selected frames through the ComfyUI background-removal graph
  -> derive one four-view cut set from the union alpha mask
  -> center each action/direction from its union alpha mask
  -> atomically publish PNG sheet, JSON manifests, evidence, and looping WebPs
```

The full workflow emits `idle`, `run`, `jump`, `crouch`, `crouch_walk`, and
`walk`. The original workflow emits only `idle` and `run`. Crouch is always the
last frame of its video and is sheet-only. Jump includes the clip endpoint.

The `staged` alias loads a YAML catalog and renders shared workflow templates.
It accepts discovered `--actions` and `--poses`, repeatable `--definitions`
overlays, and generic `--set-frames` overrides. Its dependency closure may
generate intermediate clips, but the package contains only selected outputs.
Generation revisions remain reusable when selections are expanded or frame
counts change. The old nine graphs are retained for parity and state migration.

## Invariants that are easy to break

- Configuration is deep-merged in this exact order: `config.default.yaml`, an
  optional ignored `config.yaml`, then repeatable `--config` paths in order.
  Explicit CLI value options override the merged result.
- `seed: -1` resolves once per fresh output to a pseudorandom integer. The
  effective seed is persisted and reused on resume. A fixed seed must be in
  `0..9223372036854775807`.
- Model configuration must exactly cover the connected `.safetensors` leaves of
  a bundled/configured graph. Disconnected graph branches do not count.
- A rendered main graph may change only its model leaves plus nodes 114, 283,
  244, 245, 343, and 124. The code checks class types, titles, and leaf paths.
- Queue all new character prompts before waiting on any one prompt. Persist the
  client ID before submission and the prompt ID immediately afterward. An
  ambiguous submission is recovered by client ID and is never blindly retried.
- Existing downloaded artifacts are skipped only when their action set, paths,
  and SHA-256 hashes match. Completed postprocessing cannot resume with different
  settings.
- Postprocessing starts only after the ComfyUI queue becomes idle and model
  unloading is attempted, avoiding interference with queued work.
- Cycle analysis uses named right/left ankle landmarks; never identify feet by
  sorting their X positions. Confident identity crossings are rejected and
  overlaps are downweighted.
- Run, walk, and crouch-walk use the same cycle detector. When multiple complete
  cycles exist, select the temporal lower median: the exact middle for an odd
  count, or the earlier of the two central cycles for an even count.
- Blob splitting cleans alpha below `0.05`, unions masks from every selected
  frame, finds the four largest 8-connected components, and cuts at the middle
  of the three gaps. One shared cut set is used for every action and frame.
- Horizontal centering is per action and direction, based on that animation's
  union alpha mask. Its one offset is reused for every frame, preventing both
  frame jitter and action-wide drift. Vertical placement is shared.
- Direction rows and dummy-view order are exactly `right`, `left`, `back`,
  `front`. Action columns preserve insertion order: `idle`, `run`, `jump`,
  `crouch`, `crouch_walk`, `walk` when the full graph is used.
- Every animated WebP uses `loop=0` (forever), lossless encoding, and positive
  integer millisecond holds. Crouch has no WebP.
- Package creation happens in a sibling `.working-<pid>` directory and is moved
  into place only after completion. JSON and downloads are also atomic.
- Successful execution does not imply acceptable art. Keep
  `quality_evaluated: false` unless a separate human review process is added.

## Main workflow contract

| Purpose | Node | Required class/title |
| --- | ---: | --- |
| Character image | 114 | `LoadImage` / `Character Reference Image` |
| Neutral/feminine switch | 343 | `PrimitiveBoolean` / `Neutral Idle` |
| Four-view dummy | 283 | `LoadImage` / `Last Frame Pose` |
| Combined initial width | 244 | `JWInteger` / `Integer` |
| Initial height | 245 | `JWInteger` / `Integer` |
| Seed | 124 | `SeedNode` / `Seed` |
| Run output | 92 | `SaveVideo` / `Running Animation` |
| Idle output | 341 | `SaveVideo` / `Idle Animation` |
| Jump output | 362 | `SaveVideo` / `Jumping animation` |
| Crouch output | 379 | `SaveVideo` / `Crouch animation` |
| Crouch-walk output | 424 | `SaveVideo` / `Crouch walk` |
| Walk output | 456 | `SaveVideo` / `Walk loop` |

The full profile requires all four extended nodes when any extended output is
present. Output-like nodes on disconnected or intermediate branches are ignored.
SDPose and background-removal output nodes are 4 and 5 respectively.

## Dummy-reference contract

The four bundled source views are RGB, 404x640, share one top-left background
color, and are ordered right/left/back/front. Their original bottom 48 pixels
have been removed and replaced by 48 pixels of that corner color at the top,
shifting the reference figures downward without changing canvas size. Each view
is first scaled proportionally to 512 pixels high, then center-cropped or padded
to the requested per-view render width and height using its background color.
The four results are joined horizontally. `pad_top_percent` then prepends that
percentage of the pre-padding rendered height using the same color; it does not
crop the dummy or affect the character input. Node 245 receives the resulting
height. At defaults of 400x512 and 0%, node 283 receives a 1600x512 image and
initial-size nodes receive 1600 and 512. At 15%, 77 rows are added and the
height becomes 589.

## Change map

| Change | Primary code | Also inspect |
| --- | --- | --- |
| CLI option or mode rule | `extract_frames.py` | config helpers, README, CLI contract tests |
| YAML setting/model | `comfy_workflow.py` or `comfy_postprocess.py` | default YAML, resume fingerprint, tests |
| Main workflow revision | `workflows/*.json`, packaged copy | node/title constants, model coverage, workflow tests |
| ComfyUI transport | `ComfyClient` in `comfy_workflow.py` | resume transitions and mocked client tests |
| Cycle choice | `diagnose_cycle.py` | all three periodic actions and cycle tests |
| Frame sampling/timing | `character_animations.py` | manifests, WebP duration tests |
| Four-view cuts | `sprite_split.py` | both packers and combined-mask tests |
| Centering/origin | `character_animations.py`, `sprite_sheet.py` | output schema and centering tests |
| Output/state JSON | `generate_character.py`, packers | `output-format.md`, compatibility tests |

## Before handing off a change

For hosted work, read `web-api.md` and `web-deployment.md`, then inspect
`application.py`, `runtime_config.py`, `submission_journal.py`, and `web/`.
Preserve each queued request's resolved seed, config and definition snapshots,
generation-set path, submission IDs, and exact selected package. Only the worker
process executes it. Never report ready before package publication or retry an
ambiguous ComfyUI prompt.

Run the smallest relevant contract test, then the complete suite if code or
contracts changed. Follow [`development.md`](development.md); this checkout's
enclosing `AGENTS.md` requires tests to run in a transient 16 GB/no-swap systemd
scope. Check `git diff --check`, inspect `git status`, and confirm no
`config.yaml`, generated media, model, output, or personal absolute path is
being added.
