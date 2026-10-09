# Output formats and durable state

## Web publication

Web jobs retain the engine's normal generation tree and state JSON. The web
layer assigns opaque package and artifact IDs only after the exact selected
package completes. Downloadable JSON contains sheet layout, origins, cells,
action playback summaries, WebP names, and frame holds. It excludes source
paths, prompts, model configuration, generation provenance paths, and
postprocess details. ZIP downloads contain only that public JSON, the sheet, and
the selected WebPs; downloading never changes engine state.

Cycle review adds engine-owned `cycle-analyses/poses/` and
`cycle-analyses/samples/` caches, plus `background-mask-cache/`. Candidate
metadata identifies the analysis, sampled frame set, exact complete interval,
source timestamps, frame digests, and automatic choice. The legacy
`six_frame_cycle` field remains the selected sequence despite its historical
name. Candidate IDs are independent of the exported frame count.

Web workspaces retain per-job `cycle-job-index/<job-id>.json` records outside
temporary package directories. Preview frames have durable opaque asset IDs;
analysis can remain reviewable after packaging fails. Internal manifests record
`cycle_selections` with the analysis/sample/candidate IDs, system choice,
selection origin, and private cache reference. Public metadata retains safe
choice provenance while omitting local paths. A revision publishes a new
immutable package and leaves the earlier package intact.

Paths below are relative to the workflow-mode output directory.

```text
output/
├── generation-state.json
├── workflow-source.json
├── workflow-dummy-reference.png
└── <character-slug>/
    ├── generated/
    │   ├── rendered-workflow.json
    │   ├── history.json
    │   └── <action>.<video-extension>
    └── sprites/
        ├── manifest.json
        ├── character-sheet-<height>h.png
        ├── character-sheet-<height>h.json
        ├── <action>-<direction>-<height>h.webp
        ├── <action>-frames/
        ├── background-masks/
        └── timing-evidence/<periodic-action>-extraction/
```

Catalog-backed staged mode records version `3.0-definitions` in
`staged-generation-state.json` and keeps immutable generation revisions:

```text
output/
├── staged-generation-state.json
├── definition-archives/<catalog-hash>.json
├── workflow-dummy-reference.png
└── <character-slug>/
    ├── generated/stages/<stage>/revisions/<generation-id>/
    │   ├── rendered-workflow.json
    │   ├── generation-provenance.json
    │   ├── history.json
    │   ├── video.<extension>
    │   ├── frames/
    │   └── poses/
    └── sprites/selection-<hash>/
```

Within each character, `stages.<stage>.revisions` stores generation records and
`active_revision` identifies the revision selected for the current request.
Each revision retains its generation identity, submission/recovery IDs,
artifact hashes, and separately identified pose exports. Definition archives
contain resolved prompt text, so provenance does not depend on authoring files
remaining unchanged.

Each new revision's `generation-provenance.json` records the template version
and hash, effective prompt/settings, model filenames, seed, and source/dependency
hashes. Imported legacy revisions retain a reference to their original rendered
workflow as migration evidence.

New generations retain the decoded image batch as lossless PNGs under `frames/`.
Pose exports select from this cache without another inference request. Legacy
generations can reuse their recorded canonical pose images; additional legacy
poses may require decoding the saved video, which is recorded as a fallback
rather than described as the original lossless generation data.

Generation identity uses effective graph semantics and image inputs; it does
not hash the entire catalog. Adding an action leaves unrelated revisions
reusable. Package identity includes selected source artifacts, frame-selection
and playback policies, counts, ordering, and postprocessing settings. A later
selection writes a separate package without overwriting an earlier one.

Legacy `2.0-staged` state is retained as migration evidence. Completed artifacts
are imported only when their stored graph semantics, inputs, and hashes prove
compatibility. Old packages remain on disk. In-flight client and prompt IDs
remain recoverable, and an unknown outcome is not silently resubmitted.

Selected-package manifests contain only requested `actions` and WebPs. When
poses are requested they also contain `poses`, `layout.pose_ranges`,
`pose_transforms`, and `pose_horizontal_offsets`; generated-pose frame timing
fields are null because the source is a still image. If run is absent, the
origin evidence records `selected_alpha_bottom`, derived across the selected
foreground masks instead of invoking run SDPose analysis.

Character slugs preserve letters, numbers, dots, underscores, and hyphens;
other runs become hyphens. Empty names become `character`. Case-insensitive
collisions get `-2`, `-3`, and so on. Input directories are sorted
case-insensitively by filename.

## `generation-state.json`

This is the durable workflow orchestration record. Top-level fields include:

- `version` (`"1.0"`), effective workflow path/fingerprint, dummy-reference
  metadata/upload descriptor (including base size, additive top-padding percent
  and pixels, and resulting height), idle style, effective seed and seed mode;
- one character record per source image, including source hash, slug, current
  status, uploads, client/prompt IDs, rendered graph hash/path, downloaded video
  descriptors/hashes, and eventually deliverables;
- `generation_complete`, `models_unloaded`, postprocessing settings, and final
  `complete` flags as the run progresses.

Normal character transitions are:

```text
pending -> uploaded -> submitting -> submitted -> downloaded -> complete
                          |                         |
                          v                         v
                submission_unknown              failed
                                                    \
                                                     -> postprocess_failed
```

The state file is atomically replaced after meaningful transitions. A failure
stores `"<ExceptionType>: <message>"`. `submission_unknown` is special: the next
run searches queue/history by persisted client ID; if not found, it records the
unknown outcome and does not risk duplicate submission.

On resume, the code validates version, effective workflow hash, dummy metadata,
render dimensions, idle style, exact source path/hash list, and any explicitly
fixed seed. A `downloaded` or `complete` character is skipped only when every
expected action file exists and has its recorded SHA-256.

## Sprite manifest

`sprites/manifest.json` and `sprites/character-sheet-<height>h.json` contain the
same final document. Important sections are:

- `version`, `execution_status: "exported"`, and
  `quality_evaluated: false`;
- `sheet` and `layout`: row/column count, square cell size, direction order, and
  half-open `[start, end)` action column ranges;
- `origin`: run-derived ground point when run is selected, otherwise the
  alpha-bottom fallback in cell-top-left pixels;
- `webp_origin`: the same point after each cell is resized to the requested
  output height;
- `origin_evidence`: the pose evidence used to choose the ground estimate;
- `horizontal_centering`, `animation_horizontal_offsets`, and
  `vertical_padding`: exact centering basis and offsets;
- `transforms`: source size, scale, scaled size, and split edges by action;
- `splitting`: algorithm, alpha threshold, shared union-mask edges/components,
  and per-frame split records;
- `actions`: source hash/time base, action duration, selected frame count,
  conceptual looping flag, and selected frame records;
- `cells`: row, column, direction, action/frame index, source frame ID/PTS/time,
  and sheet rectangle for every cell;
- `webps`: `action:direction` to filename;
- `frame_durations_ms`: `action:direction` to the exact positive millisecond
  hold list used by the WebP encoder;
- `background_removal`, `source_videos`, `request`, and
  `generation_provenance`: configured models, source/workflow/dummy hashes,
  uploads, prompt/output nodes, idle style, and seed.

The `cells` records in the full character package identify source timing but do
not duplicate `duration_ms`; consumers should use `frame_durations_ms` for
animation holds. The standalone direct-video `sprite_sheet.build` format does
include `duration_ms` on each cell. Keep this distinction in mind when changing
either schema.

Direction rows default to right, left, back, front. Full-workflow action ranges
default to idle 4, run 8, jump 8, crouch 1, crouch-walk 8, and walk 8, for 37
columns. Counts except crouch are configurable. Original-workflow packages have
only idle and run.

Every generated WebP except absent crouch is square at the configured sprite
height, lossless, and loops forever. Total action seconds are rounded to
milliseconds; rounded interval boundaries divide that duration across frames so
the holds sum exactly and remain positive.

## Direct video output

The outer direct-video command creates one directory and log per input plus
`batch-summary.json`. Each successful extraction contains:

- `manifest.json` with source path/hash, analysis crop, selected frame names,
  execution status, and `quality_evaluated: false`;
- `raw_pose.json`, `summary.json`, and `period_candidates.json`;
- `frames/` for the chosen complete cycle and `cycle_starts/` for predicted
  starts;
- waveform SVG and three diagnostic contact sheets;
- optionally `sprite-sheet-<height>h.png/json` unless `--frames-only` is used.

A failed child still receives a minimal manifest with return code and relative
log path. The batch summary records input/output/status/log for every video and
returns a failing process exit status if any child failed.

`animate_frames.py` is a separate utility for an existing extraction tree. It
uses each extraction summary's cycle period to write looping lossless WebPs and
an `animation-<height>h.json` manifest.
