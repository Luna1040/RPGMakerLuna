# Configurable animation definitions implementation plan

Status: implemented on 2026-09-07. All six delivery phases are complete.
The Sprite Extractor contract suite passes: **97 tests**, run in the required
16 GB/no-swap systemd scope. See [animation-authoring.md](animation-authoring.md)
for the supported YAML schema and a new-animation example.

Verification includes both-style semantic parity for all nine legacy stages,
isolated packaged-resource loading, YAML-only attack generation and packaging,
late pose exports, frame-cache recovery and checksum rejection, package-count
revisions, dry-run cache decisions, and legacy import/submission recovery.
Graph parity and mocked inference verify execution contracts, not visual quality.

## Goal

Make adding an animation a data-authoring task: define its prompt, generation
settings, input artifacts, dependency relationships, and frame-selection policy
in YAML. The CLI should discover the new action and resolve its prerequisites
without changes to Python or a copied ComfyUI graph.

Keep ComfyUI topology and model-specific constraints in a small set of versioned
workflow templates. Preserve the existing staged actions, monolithic modes,
atomic artifact publication, and protection against duplicate submissions.

## Baseline before implementation

- `staged_workflow.py` hard-codes nine stages, their dependencies, image-input
  node IDs, output nodes, action names, pose names, and traversal order.
- Nine JSON graphs under `workflows/staged/` are duplicated as package resources.
  Their prompt text, duration, sampling configuration, and frame extraction
  indices are embedded in the graphs.
- `character_animations.py` hard-codes selectable and periodic action names.
  Its shared pixel packer can already package arbitrary selected frame records,
  but orchestration still dispatches sampling by action name.
- `extract_frames.py` exposes frame-count flags for known actions only.
- The staged cache validates hashes of all nine graphs in a global generation
  identity. Adding or changing an unrelated definition currently invalidates
  resume, even when the requested stages did not change.
- Completed packages live in `sprites/selection-<hash>/`. Generation artifacts
  and submission state persist separately from those packages.

The graphs have two main structural forms:

| Template | Existing use | Behavior to preserve |
| --- | --- | --- |
| `initial_reference` | Run | Character plus dummy views; configured initial dimensions; decode/resize/re-encode of the reference latent; currently four sampling steps; first-frame pose export |
| `reference_video` | Remaining eight stages | Character plus an upstream image; dimensions from a declared image; direct reference latent; configured sampler; generally last-frame pose export |

Neutral/feminine prompt switches are definition variants, rather than additional
templates. Some stages use the standing image for dimensions while taking their
pose from a different stage; these are two distinct input dependencies.

## Authoring layout

```text
animation-definitions.yaml       # portable built-in catalog
prompts/                        # built-in UTF-8 prompt files
workflows/templates/             # small, versioned ComfyUI API graphs
src/sprite_extractor/
    animation_definitions.py     # schema, layering, validation, registry
    workflow_templates.py       # template contracts and rendering
    definition_runtime.py       # generic planning and durable execution
    staged_workflow.py          # retained legacy execution/parity helpers
    character_animations.py     # policy-driven sampling and shared packing
    ...packaged resource copies...
```

Use a separate catalog from machine-local `config.yaml`. Runtime configuration
continues to own server URLs and model selections. Animation definitions own
creative content and action behavior. Never read or reproduce the ignored local
configuration as part of this migration.

Ship the catalog, prompt files, and templates as installed package resources.
If source and packaged copies remain necessary, provide a deterministic sync
command and parity checks; do not maintain two independent catalogs.

## Definition schema

Start with a versioned schema and a deliberately bounded vocabulary. The
following is a proposed overlay adding an attack stage to the built-in catalog:

```yaml
version: 1

stages:
  attack:
    template: reference_video

    inputs:
      character: source
      pose:
        stage: stop
        output: standing
      dimensions:
        stage: stop
        output: standing

    prompt:
      file: prompts/attack.txt

    generation:
      duration_seconds: 2
      fps: 24

    outputs:
      animation:
        name: attack
        selection:
          method: uniform
          frames: 8
          include_last: true
        conceptual_loop: false
        webp_loop: 0

      poses:
        attack_end:
          frame: last
```

The first version should support:

- Stable stage, action, and pose identifiers, with clear uniqueness rules.
  Keep existing public action and pose names unchanged.
- Named, versioned template IDs. Template contracts map semantic input names
  onto node IDs and leaf paths; authors do not need node IDs in ordinary YAML.
- Inputs referencing the original character, the rendered dummy, or a named
  artifact from another stage. References are typed: a video cannot satisfy an
  image input. Dimension-source images participate in dependency resolution.
- Inline YAML multiline prompts or prompt files, exactly one per prompt value.
  Allow named variants selected by the existing neutral/feminine style option.
  Preserve current prompt text verbatim during migration. Avoid arbitrary
  expressions, executable templates, or implicit environment expansion.
- Positive finite duration and FPS, plus explicitly supported sampler settings
  such as steps, sampler, scheduler, and denoise. Put defaults and allowed
  settings in template contracts; reject unsupported overrides.
- Zero or one exported animation per stage, and named first/last/numbered pose
  outputs. Numbered frames use zero-based decoded-frame ordinals and must be
  validated against the actual generated clip.
- Intermediate stages with pose outputs and no public animation output.
- Separate frame-selection, conceptual-loop, and WebP-playback settings.
  Existing WebPs must continue to loop forever, including jump.

Keep model frame-length alignment in the renderer. Preserve the existing
duration-to-frame calculation at the default 24 FPS, including its minimum and
alignment constraints. Distinguish requested duration from effective frame
count and measured output duration in the plan and provenance. Changing FPS
must update both frame-length calculation and video creation consistently.

## Catalog loading, validation, and CLI

Add repeatable `--definitions PATH` overlays. Load the built-in catalog first,
then overlays in command-line order. Later stage definitions replace the entire
definition for that stage; this avoids accidentally inheriting stale inputs or
outputs. Document any defaults merge separately. Resolve each prompt file
relative to the file that declared it, even when overlays live elsewhere.

Reject duplicate YAML mapping keys, unknown fields, unsupported schema versions,
invalid identifiers, unresolved artifacts, duplicate public output names,
incompatible template inputs, missing prompt variants, invalid numeric values,
and dependency cycles. Report the file and relevant stage/field in errors.

Build a registry from the validated catalog. Derive dependencies from artifact
references, then use a deterministic topological sort. Do not retain special
cases for standing, walking, or crouching. Preserve the existing exported
action order (`idle`, `run`, `jump`, `crouch`, `crouch_walk`, `walk`) through
catalog metadata; append new actions in a documented deterministic order.
Execution order and sprite-sheet order are separate concerns.

Extend the CLI without removing current options:

- `--actions` and `--poses` accept outputs discovered from the catalog.
- `--set-frames attack=8` provides a generic frame-count override.
- Existing flags such as `--jump-frames` remain compatibility aliases. Reject
  conflicting generic and legacy overrides for the same action.
- Definition defaults apply first, existing runtime frame-count settings apply
  to built-in actions, and explicit CLI values take final precedence.
- `--list-animations` exposes available outputs and selection policies.
- `--dry-run` includes resolved stages, input artifacts, effective settings,
  requested frame counts, and cache decisions where a work directory exists.
  It validates definitions without contacting ComfyUI or writing artifacts.

## Template rendering and parity

Create template contracts that identify required node classes, titles, model
inputs, semantic bindings, and permitted mutations. Preserve exact coverage of
connected model inputs and reject dangling links and unexpected graph changes.

Before replacing any built-in stage, compare its rendered graph against the
current stage graph. Permit deliberate node-ID normalization and declared input
substitutions, while verifying equivalent topology, prompt text, duration math,
sampler settings, reference inputs, audio/video connections, and frame indices.
The initial run path must retain its special latent processing and sampling
behavior. A successful graph comparison is execution-contract evidence, not a
claim of identical generated pixels or acceptable art.

Support multiple named pose exports without multiplying video generation. Where
possible, export poses from the decoded image batch rather than re-decoding a
lossy saved video. Cache video generation and pose extraction separately so
adding a pose export need not regenerate an already compatible video.

## Generic frame selection and packaging

Replace action-name dispatch with a selection-policy registry:

| Policy | Initial behavior |
| --- | --- |
| `cycle` | Existing named-ankle detector, confidence rules, and lower temporal median complete cycle |
| `uniform` | Evenly spaced samples, with an explicit endpoint policy |
| `single` | First, last, or a validated numbered source frame |

Migrate run, walk, and crouch-walk to `cycle`; idle and jump to `uniform` with
their current endpoint behavior; crouch to `single: last`. A new action can use
any existing policy without new code. New detectors remain explicit extensions;
the current right-foot heuristic is not suitable for every possible motion.

Continue using the shared alpha cleanup, combined-mask splitting, per-animation
centering, premultiplied resizing, and packaging implementation. Only requested
outputs contribute frames and masks. Pose-only requests do not invoke cycle
analysis. Preserve current origin behavior: run-derived ground when run is
selected, otherwise the documented selected-alpha-bottom fallback. Record the
chosen basis instead of implying that an arbitrary new action has a measured
foot-contact origin.

## Cache identity, state, and migration

Separate three identities:

1. Generation identity: effective template/version, prompt content and selected
   variant, models, seed, render/sampler settings, and input artifact hashes.
2. Pose/selection identity: source generation identity plus frame-extraction or
   selection policy and its settings.
3. Package identity: selected artifact identities, ordering, frame counts,
   background-removal settings, layout, and playback settings.

Hash logical content, never temporary upload filenames or absolute prompt-file
paths. Archive effective definitions and resolved prompts beside rendered
workflows so each result remains explainable after its authoring files change.

Store multiple immutable stage revisions under the work directory, with state
pointing to the revision used by each request. A changed prompt creates a new
revision for that stage and affects dependent stages when their effective input
identities change. Unrelated branches remain reusable. Adding a new definition
must not invalidate existing work. Changing only sprite frame count or layout
must reuse generated videos. Include source identities in package hashes so
new generation revisions cannot collide with earlier packages.

Version the state schema and provide a tested migration path from
`2.0-staged`. Import legacy completed artifacts only when their stored hashes
and effective graphs can establish compatibility. Do not guess compatibility
from stage names. Preserve old artifacts and packages; if compatibility cannot
be established, retain them and create a distinct revision. Keep legacy
in-flight submission records recoverable by their original client IDs and
prompt IDs. Unknown outcomes must never become permission to resubmit.

Maintain stage-wave submission across ready characters, atomic state/download
writes, temporary package directories, and the idle-queue/model-unload boundary
before postprocessing. Dependency blockage must not overwrite an ambiguous
submission status. Continue recording `quality_evaluated: false`.

## Delivery sequence

| Phase | Work | Exit criteria |
| --- | --- | --- |
| 1. Capture baseline | Record effective settings and reference graphs for all nine stages, including both prompt styles | Fixtures cover every built-in stage and existing output order |
| 2. Load definitions | Implement schema, prompt loading, overlays, typed registry, validation, and topological planning | Existing dependency closures reproduced entirely from YAML; invalid catalogs fail before server access |
| 3. Render templates | Extract the two templates, semantic contracts, and packaged resources | Built-in rendered graphs match the recorded contracts; installed resources load outside the checkout |
| 4. Generalize outputs | Replace action-name sampling dispatch; add dynamic selectors, generic frame overrides, and listing | A new YAML-only action and its pose can be planned and packaged with existing policies |
| 5. Revise caching | Add immutable revisions, definition provenance, content identities, and state migration | Adding/editing an action reuses unaffected work; legacy interruption recovery remains safe |
| 6. Integrate and document | Switch staged mode to the catalog-backed runner; retain original/custom/monolithic behavior | Full contract suite passes; end-to-end mocked authoring scenario works; authoring and migration docs are complete |

Each phase should leave the existing command usable. Do not remove the nine
stage graphs as parity fixtures until the catalog-backed path and migration are
verified. No editor UI, new model family, new motion detector, or automatic
visual-quality scoring is included in this plan.

## Verification and acceptance

Use contract tests with mocked ComfyUI and real image/WebP packaging where
practical. Cover:

- Schema failures, overlay precedence, relative prompt paths, variant selection,
  cycle detection in dependencies, and deterministic ordering.
- Semantic graph parity for all nine built-ins, source/package resource parity,
  exact model coverage, and permitted renderer mutations.
- An added `attack` definition requiring standing: only its dependency closure
  runs, and no Python action registry change is required.
- Sampling and timing for built-in actions, arbitrary uniform/single outputs,
  multiple pose exports, and pose-only requests without SDPose.
- Reuse after adding an action, separate packages after changing frame counts,
  and selective invalidation after prompt, dependency, or model changes.
- Migration of completed and in-flight state, unknown submissions, blocked
  dependencies, missing/corrupt artifacts, and failure during atomic publication.
- The existing original/full workflow and direct-video regression suites.

Run focused tests first, then the complete tool suite after integration, using
the required 16 GB/no-swap systemd wrapper in [development.md](development.md).
Follow repository delegation rules: programming goes to Sol and test work to
Terra when available. Any live inference check is separate from contract tests;
use the existing CUDA-enabled ComfyUI environment, impose no artificial VRAM
cap, and report visual review separately from execution success.

Completion means that an author can add one YAML stage and a prompt file, list
and dry-run its outputs, generate only the required dependencies, export chosen
frames, and revise the animation while reusing compatible artifacts. Update
[configuration.md](configuration.md), [architecture.md](architecture.md),
[output-format.md](output-format.md), [agent-overview.md](agent-overview.md),
[development.md](development.md), and the user README alongside implementation.
