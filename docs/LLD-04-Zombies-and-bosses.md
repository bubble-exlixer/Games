# LLD-04 Zombies and bosses

Part of the [Dead Shift game design document](GDD.md). File and line references point at `DeadShift/scripts/` as of 2026-10-09.

Every enemy, bosses included, is one `zombie.gd` `CharacterBody3D`, configured by `kind` and, for bosses, `bt`. The body is a code-posed joint rig carrying meshes from an exported `.glb`. Damage arrives only through `damage()`. Boss-specific moves and taunts live in `bosses.gd`, which is called from the zombie's brain.

## Setup (`setup(g, kind, pos, wave, boss_type)`)

1. **Pick the sample.** Choose a random `zombie_samples` entry of the matching `kind`. Bosses force a look: the Coach uses `janitor`, the Lunch Lady `lunch`, and the others `teacher`. Hall Monitors use `student`.
2. **Stats.** `_stats(wave)` sets hp, speed and dmg (formulas in the GDD Enemies table). Bosses get ×1.2 HP, and `max_hp = hp`.
3. **Collider.** A capsule (radius 0.32, height 1.7) on layer `ZOMBIE_BODY` with mask `WORLD`, floor angle up to 52°.
4. **Rig.** Builds `joints{}` from `sample.joints` (`root, core, spine, head, armL1/2, armR1/2, legL1/2, legR1/2`). Each mesh in `sample.parts` is reparented from the instanced `z%02d.glb` onto its joint and recorded as `{n, joint, head, armor}`. Two unshaded eye boxes go on the head.
5. **Dressing.**
    - Bosses: `_dress_boss()` scales by `BOSS_SCALE` (coach 1.8, principal 1.55, chem 1.5, lunch 1.75) and applies boss shirt and pants textures plus props.
    - Monitors: scale 0.82, sash, badge, whistle, cap.
    - 22% of walkers, runners, spitters and bloaters get a hat.
6. **Hitboxes.** `_hitboxes()` adds `Area3D`s on layer `HITBOX` with meta `zombie` and `zone`:
    - head: 0.36 × 0.42 × 0.38, ×1.15 for armored
    - body: spine and core, ×1.5 width for bloaters
    - arm L/R and leg, two boxes per limb
7. **Agent.** A `NavigationAgent3D` with radius 0.4, height 1.8, path distance 0.4 and target distance 0.6.
8. **Animation and voice.** Lean, sway, tilt, arm style and phase offsets. A voice timbre from `VTYPE`, with pitch 0.85–1.15 (1.3–1.5 for monitors). `emerge = 1.3` s of climbing out of the ground.

## Damage pipeline (`damage(amount, zone, dir, power, blast, at)`)

1. If not alive: return `{kill: false}`.
2. **Armored:** a head hit with `helmet_hp > 0` (not a blast) does `helmet_hp −= 2.2 × amount` and returns `{armor: true}`, with no HP loss. A body hit with `vest_hp > 0` does `vest_hp −= amount`, then `amount ×= 0.25`. Blasts do ×0.6. A broken helmet or vest drops off as a gib.
3. **Headshot** (not a blast): ×2.2, and the hat pops off.
4. **Boss and blast:** ×0.5.
5. **Apply.** `hp −= amount`, a 0.08 s hit flash, then knockback: `(1.4 if blast, 0.8 if power > 5, else 0.35) × 6` m/s, ×0.15 for bosses.
6. **Stagger:** 0.5 for a blast, 0.35 for power > 5, otherwise 0.18. Bosses never stagger, and leg hits stagger at least 0.45.
7. **Kill check.** `hp ≤ 0` calls `_kill()` and returns `{kill: true, head}`.
8. **Non-boss maiming:** an arm zone has a 35% chance to `_sever()`. If not a crawler or bloater and `hp < 60%`, roll `_make_crawler()` at 0.6 for a blast, 0.25 for runners, otherwise 0.4, halved when `power < 5`.

**`_kill()` order of effects:**

1. Turn off collision and hitboxes, and blank the eyes.
2. `game.on_zombie_killed`, then floor splats.
3. Type effects: boss calls `game.boss_down`, a bloater bursts, a spitter leaves an acid puddle.
4. Body:
    - **Full gib** when `blast or power ≥ 7 or bloater or boss`: every mesh drops.
    - **Headshot:** the head drops.
    - **Otherwise:** spray and a wall splat, then `physics.ragdoll()`.

## Brain (`_physics_process`, `zombie.gd:650`)

The first rule that applies wins:

1. **Dead:** run `_corpse(dt)`.
2. **Snow Day** (`freeze_t > 0`): no horizontal movement.
3. **Emerging:** count down `emerge`.
4. **Fire Drill** (`flee_t > 0`): walk away from the player, sliding along walls.
5. **Boss wind-up or charge** (`hold_t` / `charge_t`): face the player and lunge. When the wind-up ends, start the charge (1.25 s along `charge_dir`) or the ground pound. A charge that hits the player knocks them back (×20) for 1.1 × dmg. Hitting a wall stuns the Coach for 1.2 s.
6. **Chase:**
    - Within reach (1.2 m, ×0.9 for crawlers, 2.2 for the Coach, 1.2 × `bscale` for other bosses): face and swing every 0.9 s (1.1 for crawlers). Damage lands 0.22 s later if still in range, and bosses add a 14 m/s knockback.
    - Otherwise: the boss brain mode (1 = back away, 2 = strafe), the monitor whistle, spitter spit and strafe, or `_nav_dir()`.

**Speed multipliers:** ×0.25 staggered · ×1.75 rushing · ×2.2 charging · ×0.35 slowed · ×1.5 enraged.

**Separation:** a push from each neighbour within `0.8 × max(bscale, 1)` m is added at ×2.2, then limited to 1.

**Getting unstuck:**

- A 0.5 m ledge step-up.
- Wall contact sets `nav_force = 2 s`. A head-on wall also triggers a 0.6 s sidestep.
- If it has moved less than 0.2 × speed in 0.5 s: `nav_force` and a random 0.5 s sidestep.
- Five consecutive seconds under 0.3 m of movement, or y < −10: `game.respawn_near`.

**`_nav_dir()`:** an active sidestep wins. Otherwise, every 0.2 s check body-wide line of sight with three rays (shoulders ±0.3 at 0.45 m, plus 1.3 m), only within 25 m and less than 1 m height difference. With line of sight and no `nav_force`, or within 2.5 m, go straight. Otherwise repath every 0.3 s and follow `agent.get_next_path_position()`.

**Voice:** every 2.5–7 s within 35 m: moan, grunt or stutter. Spitters hiss and runners shriek. **Pose:** `_pose(dt)`, a port of the web game's `animEnemy` (walk cycle, crawler pose, arm styles, lunge, emerge, flinch by zone).

## Special enemy behaviours

- **Spitter:** 4.5–21 m with line of sight and the cooldown ready: a 0.6 s spit animation, then `game.spit()` after 0.55 s. The shot is a ballistic arc aimed 0.4 s ahead of the player, with gravity 17. Cooldown 3.5–5 s. Strafes when within 11 m.
- **Hall Monitor:** within 20 m with line of sight and `whistle_cd ≤ 0`: `_blow_whistle()` gives every zombie within 24 m `rush_t = 5` and resets their nav. Cooldown 8–11 s.
- **Bloater:** dies with `bloater_burst`: a 3.2 m bile blast, 15 damage (acid).

## Bosses (`zombie._boss_brain` + `bosses.gd`)

- **Spawn:** `game.spawn_boss()` excludes `last_boss`. 15% Lunch Lady, otherwise random among the rest. It runs the cutscene, and the Principal brings 2 escorts after 0.9 s.
- **`bosses.start(z)`** resets the taunt bag, phase and lines.
- **`bosses.brain()` runs every frame:**
    - Idle taunts every 8–15 s, drawn from a shuffled bag.
    - Phase 2 below 50% HP: a callout and the per-boss buff.
    - The "near" line below 15%.
    - `move_t` and `move2_t` tick 1.6× faster in phase 2.

| Boss | Brain mode (`_boss_brain`) | Move 1 (`move_t`) | Move 2 (`move2_t`) | Other timers |
| --- | --- | --- | --- | --- |
| Coach | Always 0 (chase) | Charge every 6–8 s, 4.5–22 m with line of sight | Whistle every 10–13 s within 16 m: stun 1.4 / 1.9 s, horde rush 4 s | — |
| Principal | Back away within 5.5 m, strafe within 10 m | — | Paddle every 4.5–6 s within 3.4 m: 22 m/s fling, 0.7 × dmg | `ab_t` 7.5–10.5 s: assembly, detention or monitors (never the same twice; two in phase 2) |
| Chem | Back away within 8 m, strafe within 13 m | Gas flask every 7–9 s, 3–22 m | — | `th_t` 1.7–2.6 s: green flask; every 3rd is volatile (3.6 m blast); phase 2 adds a wide flask 0.3 s later |
| Lunch | Strafe at 6–12 m unless enraged | Ground pound every 5–7 s within 7 m: a ring expanding 9 m/s to 9 m, 0.75 / 0.95 × dmg, dodged by jumping | — | `th_t` gravy every 2.2–3.2 s; `tray_t` every 4–5.5 s; ×2 rate when enraged (within 9 m of `KITCHEN (-8, 0, 2.5)`) |

**Detention shutters (`game._detention`):** up to 4 shutters drop over `DOORWAYS` entries that are open (or always present) and 1.8–16 m from a player on the ground floor. They stay down 6 s and lift over 1.4 s.

**`boss_down`:** +1,000, hitstop 0.12 s, a poison cloud (chem only), Max Ammo (magazines full, reserve at least `box_reserve` or 4 magazines for infinite guns), grenades to 4, a guaranteed 2X drop and the banner.
