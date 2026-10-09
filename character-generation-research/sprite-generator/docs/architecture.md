# Architecture and module reference

## Hosted web service

`sprite_extractor.application` is the shared catalog planning and execution
boundary. `runtime_config` resolves configuration once into a frozen mapping;
queued workers consume that snapshot, never mutable YAML. `execution_lock`
serializes CLI and web mutation of an output tree. `submission_journal` records
stable uploads, client IDs, and prompt IDs for every generation and postprocess
submission.

The optional `sprite_extractor.web` package hosts FastAPI routes, a SQLite job
and event index, managed artifacts, and one scheduler per data root. Production
work runs in a separate Python process. Engine JSON remains authoritative for
generation revisions and packages; SQLite owns queue state, immutable requests,
access IDs, and event cursors. See [web-api.md](web-api.md) and
[web-deployment.md](web-deployment.md).

## Entry points and modes

The installed `sprite-extractor` command calls
`sprite_extractor.extract_frames:main`. `bin/sprite-extractor` is a checkout
wrapper that prepends `src` to `PYTHONPATH` and calls the same function.

`extract_frames.main` parses a shared option set and dispatches by the presence
of `--workflow`:

- Image workflow mode accepts one supported image or a directory, resolves a
  workflow alias/path, and calls `generate_character.process_characters`.
- The `staged` workflow alias resolves selected actions and poses to a stage
  closure, executes one independent API graph per stage, then packages only the
  requested outputs. Existing bundled, full, original, and custom graph paths
  retain their monolithic execution behavior.
- Direct video mode accepts one supported video or a directory. The parent
  command creates one subprocess per video sequentially, captures its output in
  a log, and continuously rewrites `batch-summary.json`. The hidden `--worker`
  path probes, poses, analyzes, exports evidence, and optionally packs a sheet.

## Staged image workflow

`animation_definitions.py` loads the built-in YAML catalog and repeatable
definition overlays into a validated registry. Dependencies come from typed
image references, including the source of generation dimensions. Output order
is catalog metadata, separate from deterministic dependency order.

`workflow_templates.py` renders every stage through one of two shared templates:
`initial_reference` for the initial character/dummy generation, and
`reference_video` for generation from an existing pose. Prompt files, resolved
style variants, duration, sampler settings, and output policies are catalog
data. The nine graphs under `workflows/staged/` remain legacy parity and
migration fixtures; they are not nine independent authoring templates.

```text
run -> jump
  \-> stop -> idle
           -> crouch -> crouch_start -> crouch_walk
           -> walk_start -> walk
```

`definition_runtime.py` owns catalog-backed planning, generation revisions,
pose extraction, legacy-state import, and selected packaging. The durable
`staged-generation-state.json` stores revisions per character and stage.
Generation identity includes effective workflow semantics, model settings,
seed, render inputs, and dependency image content. Selection and packaging
identities are separate, so new frame exports do not require video generation.
Stages are submitted in dependency waves across ready characters. A submission
with an unknown outcome is recovered by client ID and is never blindly
duplicated.

`character_animations.py` dispatches catalog actions by their `cycle`, `uniform`,
or `single` selection policies and passes their records to the shared pixel
packer. Existing monolithic callers retain their built-in defaults. See
[animation-authoring.md](animation-authoring.md) for the authoring flow and
[output-format.md](output-format.md) for revision storage and migration.

The CLI rejects direct-only options in workflow mode and workflow-only options
in direct mode. It also rejects an output nested under an input directory,
invalid crops, invalid dimensions/frame counts, non-finite timing values, and
anything other than four nonempty direction labels.

The hidden `--generation-only` switch stops workflow mode after video download.
It exists for internal recovery/diagnostics rather than as a documented end-user
workflow.

## Image workflow mode

`generate_character.generate_videos` resolves image inputs, creates the merged
dummy reference and effective workflow archive, creates or validates resumable
state, uploads inputs, submits all prompts, then polls and downloads only the
recognized action output nodes. See [`output-format.md`](output-format.md) for
states and artifacts.

`process_characters` records postprocessing settings, requires the server queue
to have become idle, and calls `build_character_animations` for each downloaded
character. A per-character exception changes only that character to
`postprocess_failed`; the root state is rewritten after every transition.

`character_animations.build_character_animations` analyzes the right/front
quarter (`view_index=3`) of each periodic video. It stages all work outside the
final directory, then `_pack_character_animations` samples the nonperiodic
clips, requests BiRefNet masks, splits the four views, centers and packs frames,
encodes WebPs, writes metadata, copies analysis evidence, and atomically renames
the package.

## ComfyUI integration

`comfy_workflow.py` owns both graph validation/rendering and the HTTP client.
Graphs use ComfyUI API format: a mapping from node ID strings to objects with
`class_type` and `inputs`.

The bundled full graph is Minimax H3 full-animation revision 1.3.1. The
retained original graph's feminine and neutral run-to-idle prompt values are
copied from full-graph nodes 426 and 427 into original nodes 313 and 314.

`load_configured_workflow` loads JSON, discovers nodes reachable upstream from
the recognized output nodes, discovers their `.safetensors` string leaves, and
requires an exact node/input mapping from configuration for known workflows.
`load_and_render_workflow` then validates and mutates the approved input, dummy,
size, style, and seed leaves. `graph_change_paths` supports the test that no
other graph leaf changed. `workflow_fingerprint` hashes canonical configured
JSON, so model overrides participate in resume identity.

`ComfyClient` uses the Python standard library's `urllib` and exposes:

- `upload_image` -> `POST /upload/image`, using unique hash/UUID filenames in
  the `video-to-sprites` subfolder;
- `submit` -> `POST /prompt`, including the graph as both `prompt` and workflow
  metadata in `extra_pnginfo`;
- `wait` -> poll `GET /history/{prompt_id}`, detect execution errors or
  interruption, and require expected output nodes;
- `output_descriptor` and `download` -> identify output media and atomically
  fetch it from `GET /view`;
- `find_prompt_by_client_id` -> search the queue and the newest 1000 history
  records to recover uncertain submissions;
- `wait_until_idle` and `free_if_idle` -> inspect `GET /queue` and call
  `POST /free` only when no work is queued or running.

The configured base URL must be absolute HTTP(S) with no credentials, query, or
fragment. `/api` and trailing slashes are normalized away.

`comfy_postprocess.py` renders two smaller API graphs. It adds `LoadImage` and
`ImageBatch` nodes dynamically, rewires a fixed consumer, and applies exact
model overrides. `extract_sdpose` uploads one batch and parses JSON text from
node 4. `remove_background_masks` groups images by dimensions before batching
because ComfyUI `ImageBatch` resizes unlike inputs to match its first image; it
restores the caller's order after downloading node 5 masks.

## Media timing and cycle selection

`media.probe_media` calls FFprobe for stream and frame metadata. It builds an
exact rational time base, per-frame PTS/durations, canonical display dimensions,
sample-aspect-ratio correction, normalized 0/90/180/270 clockwise rotation,
color metadata, tool versions, and a content hash. Missing last-frame duration
is inferred from the most recent positive cadence and recorded as a warning.
Missing timestamps or an empty frame list are errors.

`media.decode_frames` decodes requested frame ordinals rather than deriving them
from a nominal FPS. It validates unique in-range IDs, processes at most 128 IDs
per FFmpeg invocation, disables automatic rotation, applies recorded SAR and
orientation transforms, optionally creates an even-size proxy, and returns the
original `FrameTiming` records with decode paths.

`diagnose_cycle.extract_sdpose` crops the selected view, decodes all frames, and
sends configurable batches to ComfyUI. It verifies SDPose's fixed OpenPose group
sizes (18 body, 6 foot, 70 face, and 21 per hand) and writes normalized raw pose
data.

The module also retains a separate `extract` subcommand that imports DWPose from
a local `comfyui_controlnet_aux` checkout and can run its detector and pose model
through Torch. It is not called by `sprite-extractor`, is not represented in
`requirements.txt`, and is superseded in the production path by
`extract-sdpose`. The third module subcommand, `analyze`, is model-free and
consumes an existing `raw_pose.json`.

`diagnose_cycle.analyze` fits right- and left-ankle vertical motion:

- Named ankle indices are right=10 and left=13 in the body group.
- At least 12 observations per ankle are required.
- Samples below confidence 0.35 are discarded. Confident opposite-sign identity
  crossings are rejected; spatial overlaps within 12% of the median confident
  ankle separation are weighted at 20%.
- Autocorrelation seeds periods between configured bounds (default 0.35 to 3.0
  seconds, capped at half the clip), keeps up to eight candidates, and refines
  each over 81 nearby periods.
- Robust confidence-weighted harmonic regression uses two harmonics and a
  half-fundamental penalty. Ground phase is the maximum fitted right-ankle image
  Y, an approximate low-foot center rather than a physical contact claim.
- Complete cycles are enumerated and the lower temporal median is selected.
  Requested samples are evenly spaced over the half-open period and mapped to
  unique nearest source observations.

Analysis writes raw data, a summary, period candidates, selected original
frames, predicted-cycle-start frames, an SVG waveform, and contact sheets.

## Alpha processing, splitting, centering, and packing

`sprite_split.py` contains both splitters. `quarters` uses rounded 25% edges.
`blobs` zeros alpha values below 0.05, takes the pixelwise maximum across all
selected masks, labels 8-connected components with a horizontal-run flood fill,
keeps the four largest components, sorts them by horizontal center, and cuts at
the midpoint of each adjacent horizontal gap. Fewer than four components or
overlap is an actionable error suggesting a wider render width or legacy mode.

Both `sprite_sheet.py` and `character_animations.py` resize in premultiplied
alpha with Lanczos, then store straight RGBA. This prevents hidden RGB colors
from bleeding around transparent edges.

The full packer uses one split-edge set for every selected frame. For each
action/direction pair it unions the resulting alpha masks, measures the occupied
horizontal span, and computes one centering offset shared by all frames in that
animation. Blob-mode cell size is the maximum of requested sprite height and
all occupied widths. Quarter mode also considers panel widths. Vertical offset
is `(cell_size - sprite_height) // 2`.

The origin is derived from the run analysis's fitted right-ankle ground Y,
scaled into the sheet and adjusted for vertical padding. A second origin is
reported in the resized WebP coordinate basis.

## Module inventory

| Module | Responsibility and important public surface |
| --- | --- |
| `extract_frames.py` | Primary `main`, direct `_worker`, supported video discovery |
| `generate_character.py` | Image discovery/slugs, durable generation state, `generate_videos`, `process_characters` |
| `comfy_workflow.py` | Config merge/accessors, workflow paths/rendering/fingerprints, `ComfyClient` |
| `animation_definitions.py` | Strict YAML catalogs, prompt variants, overlays, typed artifact dependencies, public output registry |
| `workflow_templates.py` | Two versioned graph contracts, semantic rendering and generation signatures, legacy parity helpers |
| `definition_runtime.py` | Dependency execution, immutable revisions, pose caching, state migration, selected packaging |
| `staged_workflow.py` | Compatibility entry points and retained legacy graph helpers |
| `comfy_postprocess.py` | Configured SDPose/BiRefNet graphs, batched pose extraction and mask removal |
| `character_animations.py` | Nonperiodic sampling, full action packing, WebP timing, atomic package builder |
| `diagnose_cycle.py` | Pose extraction, identity evidence, period fitting, lower-median cycle selection, diagnostics |
| `media.py` | Exact FFprobe manifest and frame-ordinal FFmpeg decoding |
| `sprite_split.py` | Alpha cleanup, quarter/blob edges, shared-mask split, edge scaling |
| `sprite_sheet.py` | Direct-mode one-cycle sheet and origin metadata; `Remover` adapter |
| `animate_frames.py` | Optional WebP encoder for an existing direct extraction tree |
| `io_utils.py` | Strict canonical JSON, SHA-256, fsync/replace atomic writes and strict reads |
| `contracts.py` | Active media timing records plus reserved typed schemas for a broader staged pipeline |
| `__init__.py` | Package version |

Only `Rational`, `CoordinateTransform`, `FrameTiming`, and `SourceManifest` from
`contracts.py` are currently used by this CLI. The other dataclasses and enums
(`JobOutcome`, observation/artifact types, stage/selection/alignment records,
and `JobManifest`) are reserved schema definitions; do not assume the current
pipeline emits them. `to_jsonable` recursively serializes enums, paths,
dataclasses, mappings, lists, and tuples.

`sprite_sheet.py`, `animate_frames.py`, `character_animations.py`, and
`diagnose_cycle.py` each have module-level maintenance CLIs, but only
`extract_frames.main` is installed as a console script. The
`character_animations` module CLI exposes the older two-video run/idle packer;
the full six-action route is orchestrated by the primary command.
