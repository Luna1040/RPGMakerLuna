# Enemy encounters and companion support

`encounters.gd` owns deterministic encounter simulation. `enemy_art.gd` is a replaceable view; it contains no combat or reward rules. Positions use the same logical meters as `belt_physics.gd`: horizontal `foot.x`, ground depth `foot.y`, and independent elevation. Rendering goes through `stage.project()` and the stage's foot-sorted container.

## Runtime integration

Create the service as a child of the runtime, call `setup(stage)`, then call `step(delta)` once per active gameplay tick. The service has no autonomous gameplay `_process`, timers, or tweens. The stage must omit its tick while a modal menu or hit pause is active. Resolve a queued player death before the stage's modal early return.

The stage provides `project`, `bounds`, `volumes`, `foot`, `height_z`, `knight`, and `sorting`.

| Entry point | Contract |
| --- | --- |
| `begin_wave(number, seed) -> bool` | Creates one of three finite waves. Refuses numbers outside 1–3 or replacing an active wave. |
| `hit(foot, z, event) -> int` | Accepts the original actor's attack event, checks facing/depth/height/obstructions, and returns the number of enemies hit. |
| `hit_projectile(from_x, to_x, depth, z, damage) -> bool` | Swept hit against the nearest enemy; `true` also means a wall consumed the projectile. The caller must remove it. |
| `set_companion_enabled(bool)` | Recruitment gate. Starts disabled; enabling safely places the ally beside the current hero. Call again after scene travel. |
| `set_companion(mode)` | `follow`, `guard`, or `passive`. Changing mode cancels a pending ally strike. |
| `clear()` | Clears enemies, hostile projectiles and transient damage numbers; recruitment state remains unchanged. |
| `snapshot()` / `restore(data)` | Versioned encounter state, JSON-safe coordinates and RNG state. Invalid enemy data is rejected before mutation. |

`enemy_defeated` emits one receipt per enemy with `id`, `kind`, `wave`, `foot`, `gold`, `xp` and `drops`. The root prefixes receipts with its run identity, updates quests/XP, and creates world loot. `wave_cleared` fires once after the final living enemy dies. Only an actual `kind == "boss"` death should publish the narrative `boss_killed` event; wave completion is a separate event.

The current game runtime saves safe checkpoints between battles. It does not persist this service's mid-combat snapshot in player save slots. The encounter snapshot API remains available and tested for future replay or resumable battle work.

## Combat rules

States are `idle`, `chase`, `telegraph`, `attack`, `recover`, `return`, and `dead`. Telegraphs lock their target and resolve once; moving away, jumping, or interrupting with a hit can prevent damage. The eastern arena has a leash, and pathfinding uses the existing map collision/support functions. Four enemy definitions provide melee, caster, elite and boss behavior. Randomness is seeded at wave creation; rewards are decided once per enemy.

Hit reactions reuse `dummy_reactions.gd` for shock ticks, launch/gravity, bounded aerial juggling and hitstun. Enemy projectiles test each swept movement segment against walls and the player's actual depth/elevation. The player's authored cast releases its bolt at approximately **1.666 m**, so the enemy projectile hurt-height margin is **1.9 m**, matching practice targets. Reducing it below the release height makes ordinary spells miss every grounded enemy.

The companion is currently an invulnerable support echo. It shares the hero's existing texture cache and authored animation definitions instead of loading a second complete character. It has independent movement, a 0.18-second attack windup, a 1.6-second cooldown, and 12 damage per strike. It does not have an inventory, independent health, resurrection, or friendly fire. Guarding holds an anchor; passive mode follows without attacks.

## Art and scope

Enemies are deliberately labeled code-drawn prototypes, with readable health bars, reactions and ground warnings. The ally is tinted original hero art. Final enemy sprites, enemy portraits, collision between actors, multiplayer authority, and full companion character sheets are not implemented here. Obstacles are respected; actors do not become extra solid map volumes.

`review.png` is a development view of the art and telegraphs. Regenerate it with `tests/encounters_review.gd`; it is not gameplay source data.

## Verification

Run from the Godot project with the matching Godot executable:

```text
godot --headless --path . --script tests/encounters_test.gd --quit-after 120
godot --headless --path . --script tests/encounters_integration_test.gd --quit-after 300 -- --foundations
```

The isolated suite covers damage, facing/depth/height, launch/air combos/shock, telegraphs, cooldowns, projectile ordering and walls, real hero death, one-time rewards/clear events, companion modes/pathfinding, and save validation. The integration suite uses the actual stage and scene handoff, verifies real actor animation events and cast height, modal pauses, three-wave quest/loot progression, and the defeat/menu ordering edge case. Its brief final asynchronous wait drains audio-mixer stop requests after accelerated simulation.
