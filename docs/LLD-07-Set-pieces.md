# LLD-07 Set pieces

Part of the [Dead Shift game design document](GDD.md). File and line references point at `DeadShift/scripts/` as of 2026-10-09.

The set pieces are self-contained Node3D modules under the world. Each exposes `prompt()` and `buy()` (or `feed()`) to `game._find_interact` and `game.interact`, and runs its own `_process`. None of them is required for a run to work.

## Hammy (`hammy.gd`)

**Constants:** `HOME (31.25, 0.81, −3.3)` (the cage on a classroom desk), `FEED_SPOT (29.5, 0, −3.3)`, `COST = 500`, `PAP_COST = 5000`.

**States:**

| State | Flags | Behaviour |
| --- | --- | --- |
| Caged | `free = false` | Idles in the cage. When fed, runs the wheel for 3.2 s |
| Free | `free = true` | Follows and bites (below) |
| In PaP | `in_pap > 0` | Hidden for 3.4 s while Pack-a-Punch is busy |
| Mega | `mega = true` | Free behaviour at 2× size, violet and glowing |

**Transitions:**

- **Caged → free:** `feed()` increments `fed`. On the third feeding, `_break_out()` runs 1.4 s later.
- **Free → in PaP:** `pap_buy()`. It needs Hammy within 4.5 m of PaP, the player within 2.2 m and looking within 35°, power on, and PaP idle.
- **In PaP → mega:** `_go_mega()` when `in_pap` expires.

**Free behaviour:**

1. **Targeting:** every 0.3 s, pick the nearest live, emerged zombie within 8 m of the player and less than 1.2 m vertical from Hammy.
2. **Movement:** 8.5 m/s toward the target, or 6.5 m/s to a heel spot 1.3 m behind and 0.6 m beside the player when idle. ×1.35 beyond 4 m and ×1.4 when mega. A low ray blocks walls. Floor snap and gravity 20.
3. **Biting:** within 0.85 m, bite every 0.42 s (0.32 mega). Damage is `(22 + 5w) × (0.35 vs boss) × (3 if mega)` on the leg zone.
4. **Mega chain:** the zap jumps to the nearest other zombie within 6 m for half damage. Kills give +50.
5. **Leash:** more than 15 m away, or more than 2.2 m vertical, for 1.2 s teleports him to 1.1 m behind the player.

Hammy's prompts are `hampap` (priority 3) and `hamster` (priority 9) in `_find_interact`.

## Power-ups (`silly.gd`)

- **Drop:** `maybe_drop(at)` rolls 1.3% per kill and picks among power types not already on the ground. `drop(kind, at)` adds a billboard Label3D with a light as pickup `pw_<kind>` (15 s life).
- **Effects (`activate(kind)`):**
    - `snow`: `z.freeze(5)` on every zombie (`freeze_t`, ice tint), plus a snowfall particle system and a screen tint.
    - `drill`: `z.fire_drill(6)` (`flee_t`), alarm sound and tint.
    - `free`: `player.free_t = 10` (no ammo used) and a full magazine.

## Shock Gate (`silly.gd`)

- **Geometry:** posts `GATE_A (−48, 0, 6)` and `GATE_B (−44, 0, 6)`. Lever at `LEVER_POS`, used from `LEVER_SPOT`. The zone is x between the posts, |z − 6| < 1.5 m (2.6 m for bosses), and y between −0.5 and 3.
- **Timing:** `GATE_COST = 1000`, `GATE_TIME = 30` s (`gate_t`), `GATE_COOL = 60` s (`gate_cd`). It needs `world.powered`.
- **While live, every frame:** arcs between the posts every 0.05–0.14 s and a hum. Each zombie in the zone gets a zap at most every 0.4 s. A boss takes 7% max HP and 0.4 s of stagger. Anything else is charred (`char_mat` tint kept on the ragdoll) and killed with 99,999 damage.
- **Player in the zone:** 14 damage every 0.6 s and a push out along z.
- **Lever lamp colours:** green ready, blue live, red cooling, dark without power.

## PA announcements (`silly.gd`)

`pa(wave)` picks line `(wave / 10 − 1) % 8` from `PA_LINES`. It plays the chime, then 1.3 s later the voice and a 7 s caption ("PRINCIPAL (PA): …"). Long lines get a second voice clip after 3.2 s. It is skipped if the run ended in between. `game._process` calls it on wave clear when `wave % 10 == 0`.

`_band_room()` also dresses the upstairs boiler room as band storage: music stands, a bass drum and a banner.

## Bus escape (`escape.gd`)

**Constants:** `COST = 30000`, `DOOR_SPOT (36.1, 0, 29.7)` (prompt within 2.4 m), `BUS_C (33, 0, 27)` (the bus pivot), front gate at `GATE_X = 50` spanning z 24–30, `MAP_ID = "westfield"`.

**Setup:**

- `bus.glb` is crisped and parented to the `bus` pivot node, so moving the pivot moves the whole bus.
- 2 taillights, 2 headlight spots (28 m) and a cabin light, all off until the engine starts.
- `_build_gate()` builds two chain-link leaves under a sign and a WORLD `gate_body` closing the fence gap.
- A full-screen `black` fade rect sits on the HUD.

**`buy()`:** needs `!escaped`, at least 30,000 points and no cutscene playing. It records `points_at` (before the cost is taken), subtracts 30,000 and calls `_cutscene(points_at)`.

**`_cutscene`:**

1. `player.invuln = true`. `_road()` builds 220 m of asphalt, grass, lane paint and five street lamps east of the gate. `_spawn_swarm()` adds 16 walkers and runners (`max(wave, 3)`) 5–12 m around the bus with `rush_t = 20`.
2. `cutscene.play` runs six shots, keeping the boss active if there is one:
    1. Board (2.0 s): wakes the zombies, caption "…the keys are still in it?", door sound.
    2. Engine (3.0 s): a cough, then the engine catches at 2.1 s and the lights come on.
    3. Swarm (2.6 s).
    4. Drive (2.4 s): sets `driving = true`.
    5. Gate (0.85 s of game time): `Engine.time_scale = 0.3` with hitstop held for 3.5 s, then `_smash()` frees `gate_body` and flings the leaves.
    6. Night (3.4 s): fade to black.
3. `state = "over"`, then `settings.record_escape(wave, kills, points_at, run_t, MAP_ID)` and `hud.escaped(…)`. Fade in, `can_leave = true`, and after 9 s `_to_menu()` reloads the scene to the menu.

**Driving (`_process`):** `bus_v` accelerates at 3 m/s² (9 after the crash) up to 22 m/s along +x with a small bob. Zombies in the front 2.6 m slab within 1.9 m of the centreline take 99,999 damage at power 14, so they gib or ragdoll out of the way. Driving stops at x = 200.
