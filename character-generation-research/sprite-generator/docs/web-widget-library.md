# Sprite Extractor web widget library

The standalone web app owns the small editor-compatible foundation in
`web/src/ui` and `web/src/theme`. Feature styles arrange these primitives but
do not redefine their focus, control, button, typography, or surface states.

## Registered primitives

- `Button` renders the `editor-button` contract with standard, primary,
  warning, danger, compact, and icon variants. Icon-only buttons require both
  `aria-label` and `title` at the call site.
- `Field`, `TextField`, `NumberField`, and `SelectField` place visible labels
  above controls, render help and validation copy, and use the
  `editor-control` contract. Number inputs preserve native arrow-key behavior.
- `Choice` renders native checkbox and radio controls with a visible label and
  optional help.
- `Panel` renders the shared raised surface, header, kicker, title, optional
  actions, and content body.
- `Status` applies `role=status` for operation feedback or `role=alert` when a
  validation or failure needs immediate attention.
- `BusySpinner` pairs an accessible status label with a compact Lucide progress
  glyph. Reduced-motion environments retain the status without rotation.
- `DialogShell` portals a labelled modal surface into `.editor-shell`, traps
  Tab and Shift+Tab focus, closes on Escape, and restores focus to the opener.
  Callers select `dialog` or `alertdialog` semantics and own visible actions.
  Its `media` size expands to 1200px within the viewport for image and video
  inspection; the standard size remains appropriate for forms and confirmations.
- `MediaLightbox` composes `DialogShell` for read-only images and videos. Images
  use contained sizing; videos use native controls and metadata-only preload.
  Thumbnail activation supplies the accessible title, and the dialog inherits
  Escape handling and focus restoration from `DialogShell`. Native video and
  audio controls participate in the dialog's keyboard focus trap.
- `CycleReviewDialog` is the spacious complete-cycle chooser. Its synchronized
  sampled-frame player uses one clock for visible candidates, native radio
  selection, pause/step/speed controls, lazy images, pagination, and separate
  enlargement through `MediaLightbox`. While the lightbox is open, the chooser
  suspends its focus trap so Escape closes only the topmost dialog and returns
  focus to the Enlarge button.
- `SampledFramePlayer` renders a server-published frame sequence with its
  recorded hold times and local Play/Pause/step controls. Reduced-motion users
  start paused. `SampledFrameImage` is its controlled-frame view, used by the
  chooser so every visible candidate follows one shared clock.

The `/specimen` route is the permanent visual reference for these primitives,
including normal, disabled, warning, invalid, progress, and focus states.
The specimen also exposes the shared dialog interaction.

## Feature compositions

The upload drop zone retains a native hidden file input and visible Choose or
Replace button. Animation rows combine `Choice` and `NumberField`; a still
policy uses fixed explanatory text. Results use grouped toolbar buttons,
labelled action/direction selects, checkerboard preview surfaces, and ordinary
download links carrying the button contract.

Progress uses native `progress`, semantic status text, and an explicit
cooperative stop action. Tabs are represented by the top-level navigation;
each destination is a real history entry and exposes a visible active state.
`ActivityModal` is the feature composition for a job's durable server and
ComfyUI operation stream. It composes `DialogShell`, opens once for submission
or active-job restoration, distinguishes recorded queue/running/idle/error
states, and can be dismissed without cancelling the job. The progress panel's
View activity action reopens the same job view.

## Theme ownership

`web/src/theme/index.scss` owns all `--editor-*` assignments and shared
appearance rules. `web/src/app/app.scss` owns application layout. Themes use
the independent storage key `sprite-extractor.theme.v1`.

Future shared interactions must be added here and to `/specimen`. A second
feature needing the same behavior should use or extract a local primitive.
