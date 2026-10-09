# Web GUI layout exploration

Generated with the built-in image generator on 2026-09-07 as a design brainstorm.
These are illustrative concepts, not screenshots of an implemented GUI.

![Three Solarized Dark web UI layout concepts](web-gui-layout-concepts-v1.png)

## Selected direction

Use **A / Single-page studio** for creating a render, with the larger sheet and
animation preview from **C / Preview workspace** in the completed-results area.
Keep the source, animation choices, settings, and primary action visible together.
On smaller screens, stack these sections in that order.

| Concept | Strength | Tradeoff |
| --- | --- | --- |
| A: Single-page studio | Direct upload, selection, and settings flow; easy to adjust and rerender | Results need enough space below the setup controls |
| B: Guided flow | Clear milestones for a first-time user | Extra navigation when revising an existing render |
| C: Preview workspace | More room for inspecting and downloading completed output | Three columns are dense before any output exists |

The user approved this combination. Concept B remains exploration history.
Implementation uses A's setup layout and C's preview treatment in a full-width
results section below it, with setup controls retained for adjustments.
All concepts use the parent
editor's Solarized Dark palette. The implementation will vendor its theme and
controls locally, keeping the web application independent of the parent.

## Implementation details take precedence over the drawing

- Animation choices and counts come from the catalog. Crouch is one still frame;
  the editable count shown for it in concept A is not an intended control.
- The final sheet contains four direction rows with action frames grouped across
  columns. Concept C's action-row drawing is illustrative, not the output format.
- Upload limits come from server configuration; the plan proposes 20 MiB, not
  the illustrative 10 MB label in the image.
- Sprite size describes the target height and square WebP size; sheet cells
  may expand to fit wider poses. Use that label and help instead of the drawing's
  ambiguous Sprite height.
- The mockup thumbnails and dates are generated examples, not actual Samus test
  results. Previews in the implemented GUI use actual completed artifacts.
- Settings opens the form editor for server config.yaml defaults. It is distinct
  from render-specific controls. Prompt-based animation creation remains later work.
- Concept B's download inset illustrates a later step, not a second simultaneous
  Download page.

## Generation prompt

Mode: built-in image_gen; no reference images.

```text
Use case: ui-mockup
Asset type: high-fidelity web UI layout exploration board for Sprite Extractor.
Primary request: Create one polished comparison board showing THREE genuinely different browser application layouts, labeled A, B and C, to brainstorm an intuitive sprite animation generator. Each concept must be a complete, readable desktop website viewport, arranged in three horizontal rows on a large portrait canvas. Show crisp interface design rather than a diagram or marketing landing page. Use ample resolution for legible UI. Keep text short.
Shared visual theme: match the parent RPG creator's Solarized Dark theme exactly: page #002b36, inset #00252e, panels #073642, raised surfaces #0b404c, borders #1d4f5a, main text #93a1a1, bright headings #eee8d5, muted #839496, primary blue #268bd2, secondary teal #2aa198. Inter-like sans serif, small-radius corners, thin borders, restrained Lucide-style outline icons, compact panel headers, clear spacing. No purple, glassmorphism, giant rounded cards, decorative glow, or desktop operating-system window chrome. This is a web application.
Common content: title "Sprite Extractor"; navigation "Create sprites", "Recent renders", "Settings"; an uploaded small orange armored sci-fi sprite named "samus.png" with a visible drag-and-drop image area and "Replace image"; six animation choices with checkboxes named "Idle", "Run", "Jump", "Crouch", "Crouch walk", "Walk"; counts 4, 8, 8, 1, 8, 8 respectively. Dependency copy "Required source frames are created automatically". Render settings use labels ABOVE fields: "Sprite height" value "256 px", "Style" value "Neutral", "Seed" value "Random", collapsed "Advanced settings". Global Settings is where config.yaml defaults are edited; no raw YAML or developer internals on the main page. A clear primary action and output area with a transparent-checkerboard sprite-sheet thumbnail, tiny animation preview, and download controls. No prompt authoring yet.
A — label above screen "A / Single-page studio". Two-column main layout. Wide left column has a compact upload area followed by six animation rows in a simple well-spaced checklist with frame count steppers. Narrow right column contains render settings and a sticky blue "Generate 6 animations" button, with "37 frames per direction" summary. Below the left content show compact previous completed results with "Download sheet" and "Download animations". This should feel immediately understandable and balanced.
B — label above screen "B / Guided flow". A three-step horizontal stepper "1 Image", "2 Animations & settings", "3 Download". Step 2 is current. Large central area contains six selectable animation tiles in a 3 by 2 grid, each with a tiny sprite illustration and frame count; right summary card shows image thumbnail and the 3 basic render fields. Bottom bar contains "Back" and blue "Generate sprites". Step 3 is a clearly labeled small adjacent result-state inset showing a sheet and two download buttons, so the brainstorm communicates the full flow. Keep steps visually dominant, not a complex workspace.
C — label above screen "C / Preview workspace". Narrow left sidebar has the source image and compact animation checklist; large central canvas displays a sprite sheet on checkerboard with a small Run animation preview and simple play controls beneath; right inspector has render settings. Top toolbar has project name, global Settings, a blue "Generate" button, and a separate "Download" dropdown. Show an unobtrusive footer status "Ready · 6 animations". This is a website optimized for returning users reviewing output, with no timeline editor or extraneous game-engine UI.
Constraints: three clearly distinct layouts, same consistent palette and typography throughout, readable labels, believable controls and alignment, no invented features such as billing, teams or AI chat. Board headings may use brighter text but maintain dark theme. Main focus is interaction layout; sprite artwork remains small supporting content.
```
