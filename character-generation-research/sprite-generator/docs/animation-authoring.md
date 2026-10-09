# Authoring animation definitions

Staged generation uses an animation catalog to describe each stage's inputs,
prompt, generation settings, and exported animations or poses. ComfyUI node
wiring lives in shared workflow templates. Adding a stage that uses an existing
template and selection policy does not require a new Python action branch.

## Add an animation

Create an overlay file and a prompt file beside it:

```text
my-animations/
├── animations.yaml
└── prompts/
    └── attack.txt
```

In `animations.yaml`:

```yaml
version: 1
stages:
  attack:
    template: reference_video
    inputs:
      character: source
      pose: {stage: stop, output: standing}
      dimensions: {stage: stop, output: standing}
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

Write the desired animation in `prompts/attack.txt`. Describe the same character
in all four views, ordered right, left, back, front, and the required motion.
The prompt is passed to the model as text; the tool does not evaluate expressions
or expand environment variables inside it. The bundled prompt files provide
longer examples of the existing model's prompt format.

List the available animations and preview the dependency plan:

```bash
sprite-extractor --workflow staged \
  --definitions my-animations/animations.yaml --list-animations

sprite-extractor reference.png --output output/character \
  --workflow staged --definitions my-animations/animations.yaml \
  --actions attack --dry-run
```

Generate the animation, optionally overriding its exported frame count:

```bash
sprite-extractor reference.png --output output/character \
  --workflow staged --definitions my-animations/animations.yaml \
  --actions attack --set-frames attack=6
```

The pose reference creates the dependency chain `run -> stop -> attack`.
Generation retains the intermediate artifacts; the sprite package includes
only selected outputs. Use `--poses attack_end` to request the final pose, or
combine `--actions attack --poses attack_end` to export both.

## Definitions and runtime settings

The built-in catalog is loaded first. Each repeatable `--definitions PATH`
replaces any stage of the same name with the complete stage from that file.
Define all inputs and outputs when replacing a stage; fields from its old
definition are not implicitly retained. Prompt file paths are relative to the
definition file that declares them, not the shell's working directory.

Use `--config PATH` for server/model settings and `--definitions PATH` for
animation definitions. The ignored machine-local `config.yaml` remains a runtime
override and is not an animation catalog.

The existing action-specific frame flags remain supported. Generic
`--set-frames NAME=COUNT` also works for new action names. Conflicting explicit
overrides for the same action are errors. Exported sprite frame counts and
generated video frame counts are separate settings: changing an export count
does not change the video generation duration.

Identifiers use lowercase letters, digits, and underscores, starting with a
letter. Catalogs require `version: 1` and a `stages` mapping; optional
`action_order` controls sheet ordering separately from dependency execution.
Built-in actions retain their existing order, with additional actions appended
deterministically unless explicitly ordered. Unknown fields and duplicate YAML
keys are errors.

Each stage requires `template`, `inputs`, `prompt`, `generation`, and `outputs`.
Generation requires positive `duration_seconds`; `fps` defaults to 24. Optional
`steps` is a positive integer, `sampler` and `scheduler` are ComfyUI names, and
`denoise` is between zero and one. Omitted sampler settings retain template
defaults. The server must support any sampler or scheduler name you choose.

Use `prompt: {inline: "Your prompt"}` instead of a file, or supply both style
variants under `prompt.variants`:

```yaml
prompt:
  variants:
    neutral: {file: prompts/attack-neutral.txt}
    feminine: {file: prompts/attack-feminine.txt}
```

`--idle-style` selects that variant across the catalog. Both variant branches
are validated. An intermediate stage may omit `outputs.animation` and expose
only named entries under `outputs.poses`.

Every input block contains `character`, `pose`, and `dimensions`.
`character` is `source`. For `initial_reference`, both `pose` and `dimensions`
must be `dummy`; `reference_video` uses named stage image artifacts for those
two fields.

## Templates and dependencies

| Template | Purpose |
| --- | --- |
| `initial_reference` | Generate from the original character and the prepared dummy views, preserving the initial latent-resize path |
| `reference_video` | Generate from the original character and a named image produced by an earlier stage |

An input such as `{stage: stop, output: standing}` names an image artifact,
not merely a scheduling dependency. `pose` and `dimensions` may refer to
different images. Both references participate in planning and cache identity.
Missing outputs, wrong artifact types, and dependency cycles fail validation.

An animation output may include optional `label` and `description` display
metadata. `label` must be non-empty text when present; `description` must be
text. Interfaces fall back to a readable form of the animation identifier when
these fields are absent, so existing catalogs and archived snapshots remain
valid. Display metadata is preserved in definition snapshots and provenance but
does not participate in stage generation identity or cache reuse.

```yaml
outputs:
  animation:
    name: attack
    label: Heavy attack
    description: A committed overhead strike.
    selection: {method: uniform, frames: 7, include_last: true}
    conceptual_loop: false
    webp_loop: 0
```

The renderer owns model-specific frame-count alignment. Requested duration can
therefore differ from the effective video duration. Plans and artifact metadata
distinguish the requested settings from effective counts and measured media.
Changing duration does not rewrite the prompt; keep any timing described in the
prompt consistent with the settings you choose.

## Frame selection and playback

| Selection method | Use |
| --- | --- |
| `cycle` | Select a complete periodic motion cycle with the existing named-ankle detector |
| `uniform` | Sample a clip evenly, optionally including its endpoint |
| `single` | Export the first, last, or a numbered frame |

The cycle detector fits foot motion; it is appropriate for the existing run,
walk, and crouch-walk animations. A motion such as an attack generally needs
uniform sampling rather than foot-cycle detection.

`cycle` and `uniform` require `frames` of at least two. `uniform` also requires
the Boolean `include_last` field. `single` requires `frame` set to `first`,
`last`, or a non-negative zero-based ordinal. Generic frame overrides must
respect the policy: `single` accepts only one frame.

Pose outputs select first, last, or zero-based numbered frames. Multiple poses
can be exported from one generation. Set `webp_loop: null` for a `single`
output with no animated WebP; null is invalid for the animated policies.

`conceptual_loop` describes the action's semantics. `webp_loop` controls encoded
playback separately; zero means loop forever. Built-in animations retain their
existing infinite WebP playback, including jump.

Only selected frames participate in shared view splitting and centering. When
run is selected, its analysis supplies the ground origin. Otherwise the package
records the selected-alpha-bottom fallback. Neither a successful generation nor
that fallback establishes the visual quality or physical foot contact of a new
animation.

## Reusing work

Use the same output directory to reuse compatible generation artifacts.
Generation revisions, pose exports, and sprite packages have separate content
identities. Adding an animation leaves unrelated stages reusable. A changed
prompt or generation setting creates a distinct revision; earlier artifacts
remain available. Changing only selected frames or package layout reuses the
video.

Resolved definitions and prompt content are archived with generated work for
provenance. Upload filenames do not determine cache identity. Interrupted
submissions retain their original recovery IDs; an unknown server outcome is
not automatically resubmitted.

See [configuration.md](configuration.md) for runtime configuration and
CLI settings, and [output-format.md](output-format.md) for artifact layout and
legacy-state migration.
