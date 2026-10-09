# Using the Sprite Extractor web interface

Open the address provided by the server operator and sign in. The browser is
the control surface: uploads, generation work, and completed renders are kept
on the server. ComfyUI runs on the server configured in Settings.

On a trusted home LAN, the operator can start the server with `--no-auth`. The
app then opens directly without a sign-in screen. Every device that can reach
that address has the same operator access.

## Create sprites

1. Drop one character image onto the upload area, or use Choose image. Check
   the uploaded filename and preview before generating. Replacing the image
   creates a new workspace and retains the previous image's results.
2. Select the animations to export. All available built-in animations are
   selected initially. Adjust frame counts for animated outputs; Crouch is a
   single still frame. Required reference poses are generated automatically.
3. Set the sprite size, prompt style, and seed in the render settings panel.
   Advanced controls adjust generation resolution, padding, and view splitting.
   Animation details expose duration and FPS separately from exported frames.
4. Review the selected outputs and dependency information, then choose Generate
   sprites. The activity window opens with recorded server and ComfyUI work,
   including queueing, generation, pose extraction, background removal, and
   failures that require recovery. Dismissing it does not cancel the job; use
   View activity in the progress panel to reopen it. Progress appears below the setup controls. Keep this page open to
   follow it, or return through Recent renders later.

The sprite size sets the target sprite height and square WebP size. Sheet cells
can expand to fit wider poses; the package metadata records their actual size.
Generation width and height describe each of the four input views; increasing
them changes the work sent to ComfyUI. Exported frame counts determine how many frames enter the
finished sheet. Changing a frame count can reuse an existing video, while
changing the generated clip's duration requires new generation.

The standard all-animation selection exports 37 frames per direction, across
four directions. The sheet has four direction rows. Crouch appears in the
sheet, while the five animated actions also have individual direction WebPs.
Custom catalogs can change the available actions and their defaults.

## Review and download

Completed output appears in a large results area below setup. Fit the sheet to
the available space or zoom in to inspect individual pixels. Choose an action
and direction for the animation preview. Animated actions play automatically;
use Pause/Play to control them. Reduced-motion preferences start previews
paused, while the Play button remains available for an explicit choice.
Still poses do not have an animated download.

Download all gives you `sprite.zip` containing the final deliverables. You can also download
the sheet PNG, metadata JSON, or individual animations. Downloads are copies;
the server retains the work needed for future renders. Raw generation videos,
source images, private configuration, and prompts are not part of the normal
download bundle.

Generation finishing successfully means the pipeline executed and packaged
its output. It does not certify the appearance of the generated art.

## Choose a different cycle

Run, Walk, and Crouch walk offer **Review cycles (N)** in their animation blocks
and beside the results. The first export happens automatically with the
**System pick** selected. This is the middle complete cycle (the earlier of the
two middle cycles for an even count), selected by timing rather than visual quality.

The review window loops the unprocessed four-view frames together. Use the
radio control to select a cycle, or **Enlarge** to inspect it without changing
the selection. Pause, step through frames, or change playback speed. Pages
expose all candidates, and animation tabs let you stage several choices.
Choices are retained when you close and reopen the window or refresh the page.

Select **Update sprite sheet** after the current job finishes. One cycle choice
applies to all four directions. The update rebuilds the whole sheet and its
animations using the saved videos and pose analysis; newly chosen frames may
need background removal. The activity window shows that work. Your previous
downloads remain available during the update and if it fails.

Older renders may need **Analyze saved video for cycles** first. This action
reuses compatible saved pose evidence, or runs pose extraction on the saved
video. Merely opening a render does not start analysis. If the generated video
is unavailable, it cannot be reviewed through this action. Uniformly sampled
animations such as Idle do not have detected cycle alternatives.

## Adjust a previous render

Open a saved job from Recent renders to see its settings and available output.
Use Adjust and generate to start from those settings and reuse compatible work.
Selecting another animation automatically includes any missing dependencies.
Earlier completed packages remain available.

Recent renders also shows workspace storage use. Delete workspace removes its
uploaded image, generated work, and saved results from the server after you
confirm the workspace ID. Active work and work requiring recovery must be
resolved before deletion. Files you already downloaded remain on your computer.

A generation set has one source image and one resolved seed. A fixed seed
reproduces that input choice; Random chooses a seed for new work and the
resolved value is saved with the render. Use Generate a new variation when
you specifically want a fresh random seed rather than an adjustment that
reuses the existing generation set.

## Settings and defaults

Create sprites controls affect the current render draft. Settings edits the
server's configured `config.yaml` defaults for future drafts. The two are
separate so saving defaults cannot change a queued or running render.

Settings groups cover the ComfyUI connection and timeout, render defaults,
animation frame defaults, SDPose batch size, and generation/postprocessing
models. The connection address is resolved by the backend server, even if
you are browsing from another computer. A connection check inspects the server;
it does not generate images or start ComfyUI.

Use Save to persist changes and Discard to abandon unsaved edits. Resetting an
override restores the inherited default. If the configuration file changed
elsewhere, reload and review it before saving again. The server preserves the
previous file as a backup; YAML formatting and comments may be normalized.

Choose Apply updated defaults explicitly to update an already-open draft.
Changing the interface theme affects your browser's appearance preference.
The interface uses locally owned copies of the parent editor's themes and
does not require the parent application.

Creating new animations by writing prompts remains a separate future feature.
Existing catalog entries can be selected and configured for a render now.

## Interrupted work

Refreshing or closing the browser does not cancel a render. Open its saved
link or find it in Recent renders to reconnect. A disconnected browser can
display stale progress while the server continues working.

A queued job can be canceled. Stop after current step lets the active server
operation finish and saves its artifacts before stopping further steps. It
does not interrupt unrelated ComfyUI work.

When Resume is available, it recovers the original job and its recorded work.
An uncertain submission must first be reconciled with ComfyUI; the application
must not create a replacement just because a connection timed out. Failed or
stopped renders retain previous successful downloads and reusable artifacts.

## Raw generation previews

While a render is running, completed raw stage videos and dependency images
appear progressively under **Raw unprocessed output**. Each stage appears once,
in the card for its first selected consumer in the job's recorded execution
plan. The same card shows a generating status while that stage is active. These
files show the pipeline input before frame extraction,
background removal, centering, and packaging. Select a thumbnail to open a
larger image or a video with native playback controls. Viewing a raw preview is
read-only and never submits generation work.

## Review detected cycles

Animations configured for cycle selection expose **Review cycles (N)** after
complete cycles are published. The system's middle complete cycle is selected
initially. The dialog shows chronological unprocessed four-view samples on one
synchronized playback clock, with Pause all, frame stepping, speed, pagination,
and a separate Enlarge action.

Selections are saved for the render and analysis while you compare actions.
**Update sprite sheet** submits all changed choices as one revision after the
source work finishes. Existing package downloads remain available while that
child job runs or if it fails. Older renders without durable cycle evidence
require the explicit **Analyze saved video for cycles** action; opening review
never starts analysis or model work.
