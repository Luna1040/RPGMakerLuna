# Map combat motion production record

These three full-body clips were generated locally on 2026-10-09 using the same
clean original knight reference and MiniMax H3 pipeline as the approved jump.
Source image: ComfyUI input `knight-clean-green.png`; despite that background,
the requested video backdrop was black for the established extraction workflow.

## Reproduction

1. Ensure local ports 9315 and 9316 have no queued work. Use only 9316 for H3.
2. Run `character-generation-research/generate_map_combat_motion.py` using the
   existing Flux2 embedded Python. It serially creates run, dash_attack, air_slash.
3. Each job uses 768 x 768, 124 frames, 20 steps, normal scheduler, res_multistep,
   the full H3 FP8 model and no turbo LoRA. Full workflows, job IDs and history
   responses are retained alongside this file.
4. Inspect raw-sheet JPGs using `review_map_combat_motion.py`.
5. Review `export-spec.json`: this records source frame selection, gameplay
   duration and root pivots. Do not resize individual frames to their bounding box.
6. Release H3 before `export_map_combat_motion.py`; it uses BiRefNet GPU extraction,
   precise black-edge keying and navy-cloth preservation. Air strike additionally
   retains the connected character component to remove the model-added sword arc.
7. The exporter writes `godot-belt-map/characters/first_knight/assets/combat-motion.json`
   and `combat-motion/` PNGs. Import in Godot before running the map.

## Timing and runtime contract

- Run: 10 frames, 580 ms, stable complete alternating-foot cycle from source 32-46.
- Dash attack: 9 frames, 420 ms, full sword thrust from 105-255 ms; game hit at 160 ms.
- Air slash: 9 frames, 470 ms. `hold_ms=249`, `landing_start_ms=250`; the actor freezes
  its descending strike before landing, then plays the 220 ms crouch/recovery tail.
- All assets remain 768-square *storage canvases*, preserving the complete natural
  silhouette and sword. The game places them by pivot and fixed clip scale 0.977.
- Airborne pivots remove the source video's vertical root displacement; game physics
  owns world height. The bent-knee silhouette is retained, never stretched taller.

## Visual review

All 28 frames are RGBA with transparent canvas borders and validated duration sums.
Raw and transparent contact sheets and animated WebP previews are retained here.
Run has coordinated torso lean, alternating stride and moving hair/cape. Dash keeps
its complete sword tip in frame. H3 ignored the no-effects request during parts of
both attacks: dash selection skips the prominent effect frames; air effects are
removed by connected-component extraction after segmentation. A tiny attached
highlight remains on the sword tip in one 40 ms air landing frame. No claim of
perfect hand-authored pixel animation is made; the imported Godot preview remains
the final check of temporal scale, root placement and hit timing.
