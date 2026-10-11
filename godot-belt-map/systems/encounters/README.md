# Enemy encounters and Serin's party combat

`encounters.gd` owns deterministic encounter simulation. `enemy_art.gd` is a replaceable view; it contains no combat or reward rules. Positions use the same logical meters as `belt_physics.gd`: horizontal `foot.x`, ground depth `foot.y`, and independent elevation. Rendering goes through `stage.project()` and the stage's foot-sorted container.

## Runtime integration

Create the service as a child of the runtime, call `setup(stage)`, then call `step(delta)` once per active gameplay tick. The service has no autonomous gameplay `_process`, timers, or tweens. The stage must omit its tick while a modal menu or hit pause is active. Resolve a queued player death before the stage's modal early return.

The stage provides `project`, `bounds`, `volumes`, `foot`, `height_z`, `knight`, and `sorting`.

| Entry point | Contract |
| --- | --- |
| `begin_wave(number, seed) -> bool` | Creates one of three finite waves. Refuses numbers outside 1–3 or replacing an active wave. |
| `hit(foot, z, event) -> int` | Accepts the original actor's attack event, checks facing/depth/height/obstructions, and returns the number of enemies hit. |
| `hit_projectile(from_x, to_x, depth, z, damage) -> bool` | Swept hit against the nearest enemy; `true` also means a wall consumed the projectile. The caller must remove it. |
| `set_companion_enabled(bool)` | Recruitment gate. Starts disabled; enabling safely places the ally beside the current hero without restoring HP, MP or life. Call after scene travel, then restore the saved companion body. |
| `set_companion(mode)` | `follow`, `guard`, or `passive`. Changing mode cancels a pending ally strike. |
| `companion_status()` | Read-only HUD data: identity, class, health/mana, shield, action, defeat, mode, cooldowns and three skill descriptions. |
| `damage_companion(amount, from)` | Applies finite positive damage to shield then independent HP; interrupts an unreleased cast and produces hitstun. Returns damage to HP. |
| `companion_snapshot()` / `restore_companion(data)` | JSON-safe independent party resources and action/cooldown state. Restoring validates before mutation. Empty data upgrades legacy saves to the default healthy companion. |
| `validate_companion(data)` | Rejects malformed and non-finite resources, excess cooldowns, and contradictory HP/defeat or shield/expiry state. Root save validation calls this before restoring any player state. |
| `rest_companion()` | Restores HP/MP, revives, clears shield, cooldowns and hitstun. The root must enforce town access and payment; enabling or changing mode never revives. |
| `replace_companion_view(view)` | Installs a `Node2D` that implements `set_combat_view(Dictionary)`. The view receives action, elapsed, facing and party status; service controls the foot-sorted root position. |
| `clear()` | Clears enemies, hostile projectiles and transient damage numbers; recruitment state remains unchanged. |
| `snapshot()` / `restore(data)` | Versioned encounter state, JSON-safe coordinates and RNG state. Invalid enemy data is rejected before mutation. |

`enemy_defeated` emits one receipt per enemy with `id`, `kind`, `wave`, `foot`, `gold`, `xp` and `drops`. The root prefixes receipts with its run identity, updates quests/XP, and creates world loot. `wave_cleared` fires once after the final living enemy dies. Only an actual `kind == "boss"` death should publish the narrative `boss_killed` event; wave completion is a separate event.

The current game runtime saves safe checkpoints between battles and stores the companion's own HP/MP/defeat/cooldowns in the player save. It does not persist the enemies' mid-combat snapshot in player save slots. The full encounter snapshot API remains available for future resumable battles and includes ally bolts already in flight.

## Combat rules

States are `idle`, `chase`, `telegraph`, `attack`, `recover`, `return`, and `dead`. Telegraphs lock their target and resolve once; moving away, jumping, or interrupting with a hit can prevent damage. The eastern arena has a leash, and pathfinding uses the existing map collision/support functions. Four enemy definitions provide melee, caster, elite and boss behavior. Randomness is seeded at wave creation; rewards are decided once per enemy.

Hit reactions reuse `dummy_reactions.gd` for shock ticks, launch/gravity, bounded aerial juggling and hitstun. Enemy projectiles test each swept movement segment against walls and the player's actual depth/elevation. The player's authored cast releases its bolt at approximately **1.666 m**, so the enemy projectile hurt-height margin is **1.9 m**, matching practice targets. Reducing it below the release height makes ordinary spells miss every grounded enemy.

Enemy targeting considers both living party members. The closer valid body is pursued, with a 0.65 m retention margin to avoid rapid target switching. A telegraph locks its attack geometry, so moving away still dodges it. Melee areas can hit both members; hostile projectiles are consumed by the first party body in their swept path. A fallen companion is excluded from target selection. The hero's defeat stops the encounter as before.

## Serin, battle cleric

Serin has **140 HP and 80 MP**, independent of hero equipment. She is vulnerable in every command mode. Taking damage interrupts a pending spell and causes 0.32 s hitstun with 0.22 s contact invulnerability. A depleted shield lets excess damage reach HP. At zero HP she stays fallen and cannot move, regenerate or cast until explicit town rest. Travel, loading, toggling recruitment, and switching orders preserve this state.

| Skill | Actual rule |
| --- | --- |
| 圣光弹 / Radiant bolt | 18 damage, 1.6 s cooldown, no MP cost. After a 0.24 s windup, launches a visible 7 m/s projectile. Walls consume it; the first eligible enemy receives the damage. It does not automatically apply the hero's shock status. |
| 愈合术 / Mend | 18 MP, 8 s cooldown. Heals 40 HP to the lower-health-ratio party member below 55%, within 4.8 m and line of sight. Cost/cooldown are paid at cast start; interruption or moving out of range can prevent the heal. It never revives. |
| 圣域盾 / Sanctuary ward | 24 MP, 12 s cooldown. During combat, casts on Serin below 72% HP when she has no shield. Absorbs up to 38 damage for 6 s. |

Mana regenerates at 1.4/s during combat and 4/s otherwise. There is no passive HP regeneration. Healing takes priority over ward and attack. Guard holds its anchor and only attacks targets within its guard radius; follow escorts the player and approaches distant targets. Passive follows but suppresses all autonomous damage and support skills. It does not suppress incoming damage. Party movement uses the same obstacle pathfinding as enemies, and all timers advance only through the explicit simulation tick.

The companion view maps `stand`, `walk`, `attack1`, `magic`, `hit`, and `dead` to authored artwork. Portraits, status HUD and catalog descriptions live outside the encounter simulation. Serin currently has a fixed class kit; companion equipment, leveling and additional recruitable classes are extension work.

## Art and scope

Combat and artwork are independent. `enemy_art.gd` reads each enemy's dictionary, while `roster_actor_view.gd` receives the companion status dictionary. Both use `roster_animation.gd` to sample whole authored PNG frames; they do not articulate cutout limbs or borrow the knight's frames. Artwork cannot change meters, attack overlap, resources or reward receipts. Obstacles are respected; actors do not become extra solid map volumes. Multiplayer authority is not implemented.

| Gameplay kind | Art ID | Character | Required clips |
| --- | --- | --- | --- |
| `melee` | `scout` | 灰誓斥候 | `stand`, `walk`, `attack`, `hurt` |
| `ranged` | `caster` | 灰誓咒术师 | `stand`, `walk`, `attack`, `hurt` |
| `elite` | `elite` | 灰誓重卫 | `stand`, `walk`, `attack`, `hurt` |
| `boss` | `boss` | 陨星执政官 | `stand`, `walk`, `attack`, `hurt` |
| companion | `serin` | 瑟琳 · 战牧 | above plus `cast` |

Each directory is `res://assets/roster/<id>/` with `portrait.png` and `animation.json`. The manifest contains `version:1`, `id`, `name`, `canvas:[768,768]`, `portrait`, and `actions`. Each action has a fixed `pivot:[x,y]` and `scale`, `duration_ms`, `source_count:124`, `source`, `review_status`, and ordered frames with `file`, `source_frame`, `duration_ms`. Attack and casting clips also provide `event_ms`. Original export frames keep the full canvas; runtime copies may declare one action-level `storage_crop:[x,y,w,h]`, the alpha-union bounds plus four completely transparent pixels on all sides. AtlasTexture margins restore the 768x768 virtual canvas without changing pivot, scale or timing. Per-frame bbox resizing, offsets and scale changes remain forbidden. Optional `portrait_pivot`/`portrait_scale` govern only the temporary still-image fallback.

Cropped PNG dimensions must match the same action-level rectangle, which must contain integer coordinates wholly inside 768x768. The source archive remains unchanged. The validator reconstructs the full canvas and, with `--source-root`, compares all alpha and visible RGB against the originals. This catches detached weapons omitted by an otherwise clean-looking crop. Without that archival comparison, cropped assets cannot be `release_ready`; structural checks alone do not establish losslessness.

Visual timing is not a new combat clock. `attack_time` maps the engine's exact windup boundary to the authored `event_ms`, then maps recovery across the remaining frames. A longer enemy windup therefore remains dodgeable even if the original generated video was several seconds long. Hurt overrides ordinary locomotion; horizontal facing mirrors around the fixed foot pivot. Check left/right facing and transitions in the actual map, not only in animation thumbnails.

There is **no separately generated death clip**. An enemy holds the endpoint of its hurt clip while fading over 0.7 s. A defeated Serin holds a tinted hurt endpoint with a downed label until town revival; this must not be described as an authored collapse animation. Ground spell projectiles, shields and telegraphs remain separate runtime effects.

**Production status (2026-10-11):** all five portraits and 21 required whole-frame clips are published (351 transparent frames). The source-comparison asset gate reports `release_ready:true` and lossless storage; all 25 Godot checks pass. Native motion sheets cover every required clip, and four real-stage captures verify both projectile facings. The web build was checked for roster portraits, action playback and Escape dismissal. A portrait fallback remains development protection, not an accepted animation. See root `NPC_ROSTER_INTEGRATION.md` for evidence and remaining limitations.

`review.png` is a development view of the art and telegraphs. Regenerate it with `tests/encounters_review.gd`; it is not gameplay source data.

## Verification

Run from the Godot project with the matching Godot executable:

```text
godot --headless --path . --script tests/encounters_test.gd --quit-after 120
godot --headless --path . --script tests/encounters_integration_test.gd --quit-after 300 -- --foundations
godot --headless --path . --script tests/roster_integration_test.gd -- --foundations
godot --headless --path . --script tests/menu_input_test.gd -- --foundations
python tests/validate_roster_assets.py --output test-results/roster-assets.json
```

The isolated suite covers damage, facing/depth/height, launch/air combos/shock, telegraphs, cooldowns, projectile ordering and walls, real hero death, one-time rewards/clear events, companion modes/pathfinding, and save validation. It also checks enemy retargeting, companion projectile interception, independent hitstun and HP, healing MP/range/cooldowns, finite shields, spell interruption, defeat, anti-revival toggles, explicit rest, and JSON persistence of HP/MP/cooldowns. The integration suite uses the actual stage and scene handoff, verifies real actor animation events and cast height, modal pauses, three-wave quest/loot progression, and the defeat/menu ordering edge case. Its brief final asynchronous wait drains audio-mixer stop requests after accelerated simulation.

The roster integration suite checks all five catalog pages, wounded/downed companion snapshot restoration, JSON float roundtrips, legacy saves, upper bounds and contradictory state rejection, one-charge party rest, insufficient funds, town-only revival and HUD/modal visibility. The Python release gate needs Pillow and checks real RGBA pixels as well as timing, event ranges, safe relative paths and fixed transforms. `--allow-pending-review` is a production diagnostic only: pending review always makes `release_ready` false. Its own tests run with `python -m unittest discover -s tests -p test_validate_roster_assets.py -v`.
