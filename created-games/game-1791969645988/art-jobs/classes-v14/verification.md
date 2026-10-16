# Class models, spells and foundation guidance (v14)

Scope: only game-1791969645988. No commit/push. No editor import, visible game launch, process termination, account credentials or private team data access. Bridge retains responsibility for import and restart.

## Integrated products
- assets/classes/{sword,yinyang,shadow,celestial}.png: four independently generated 768x768 RGBA portraits. Semantic BiRefNet matte via supplied artCli/matte_frames.py, dark/light previews reviewed. profiles.json uses one fixed foot pivot and uniform scale per portrait, map visible body height 72 pixels.
- assets/spell-manuals.png: 1024x256 four-cell class manual atlas, visually reviewed and used in bag/storage item icons.
- spell_system.gd, spell_ui.gd, class_profile.gd; main.gd/estate_ui.gd/dungeon_world.gd integration.
- Sixteen spells: each profession has two qi and two foundation spells. Own profession/realm lock, same-name manual learning cost 1; upgrades cost 2 through 10; maximum level 10. Wild monster manual drop chance 15% per individual, persistent independent RNG; full bag uses pending loot. Foundation manuals can drop at level20 but require foundation realm to learn. Learned spells rotate automatically in both normal and quick combat; damage/healing/guard use the same rules.
- Sect elder quest: accept guidance, level20, prepare foundation pill, actually establish foundation in estate cave, report back. Existing breakthrough chances/failure penalty preserved; hand-in 200 spirit stones once. Lesson NPC explains manual acquisition and K menu.

## Art jobs
- art-jobs/class-{sword,yinyang,shadow,celestial}-portrait-v14: raw image, prompts/workflow/submission/history preserved.
- art-jobs/class-portraits-alpha-v14: four approved static transparent portraits and review images, integrated.
- art-jobs/spell-manuals-v14: generated atlas, integrated.
- art-jobs/class-{sword,yinyang,shadow,celestial}-attack-v14: candidate videos generated; 56 native source PNGs each, 24fps. Sources and output-index mappings preserved in class-*-source-v14.

## Incomplete animation quality checks
New attack animation candidates are NOT finished or integrated. Full-frame alpha processing, fixed-canvas pack and final loop review are incomplete. Sword/celestial strike effects or weapon tips touch/cross the source canvas; shadow recovery pose differs from starting pose; generated embedded glow needs separation before approval. The local Comfy background-removal node lists no available model. DirectML runtime initialization failed and fell back to CPU; it must not be reported as successful GPU matting. Existing sword/bite attack assets remain; other professions retain their own new portrait during lunge/pose movement instead of being replaced by the sword character. Art validation details: art-validation.json.

## Verification
PASS: spells_v14, battle_v5, menu_ui, slot_bounds_v13, breakthrough_v11, dungeon_v10, sweep_v12, retainer_v8, equipment_v6, estate_v7, smoke. Logs are alongside this report. Spells test includes four-class map/battle identity and anchor restoration, learning/upgrading/cap/realm and class locks, deterministic drop distribution, normal/quick equivalence, foundation quest stages, save round-trip and deliberate save-failure rollback.
Headless engine reports the pre-existing Windows root-certificate-store error. The spells test deliberately attempts an invalid save path to verify transactional rollback and therefore emits one expected directory error. No script exceptions or failed assertions in final runs. Static portrait transparency and atlas regions validated. No claim of visible live-game screenshot validation or bridge restart is made.
