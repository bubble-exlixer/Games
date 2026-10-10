# LLD-01 Architecture and boot

Part of the [Dead Shift game design document](GDD.md). File and line references point at `DeadShift/scripts/` as of 2026-10-09.

The game is one scene (`scenes/main.tscn`, a single `Node` with `main.gd`) that builds every system in code at `_ready`. There are no autoloads and no class_name globals. Systems find each other through references that `game.setup()` hands out.

## Boot sequence (`main.gd:77`)

1. `randomize()`, then `_actions()` registers all input actions (keyboard, mouse, Xbox pad, and UI navigation on the left stick).
2. Parses user args after `--`: `--bot`, `--time=`, `--shots=`, `--stage`, `--rules`, `--chase`, `--extras`, `--tour=`, `--topdown=`, `--t3=`, `--probe`, `--newtest`, `--phystest`, `--powertest`, `--menutest`.
3. Builds the 3D `SubViewportContainer` (stretch_shrink 2, nearest filter) and its `SubViewport`, `audio.gd`, then the HUD in a second half-resolution `SubViewport` (transparent, input disabled).
4. `world.gd` goes into the 3D viewport, then `fx.gd` and a `Zombies` Node3D under the world.
5. `settings.gd` loads `user://deadshift.cfg`.
6. `game.gd`, then `player.gd` (under the world). `game.setup(world, player, hud, fx, audio, zroot)` builds every dependent system. `player.setup(game, start)`.
7. `menu.gd`, then `settings.apply(main)`, then `on_settings_changed()`.
8. Awaits `world.nav_ready` (the first navmesh bake), starts the ambience, and captures the mouse.
9. Runs a test mode, or otherwise `_boot()`: the infection prologue once per process (`Engine` meta `seen_intro`), then the main menu. `skip_menu` meta (set by R after death) goes straight to `_start_game()`.

## Node tree at runtime

```text
Main (main.gd)
├─ SubViewportContainer (3D, shrink = pixel setting)
│  └─ SubViewport
│     └─ World (world.gd)  ← audio.world_root
│        ├─ Nav (NavigationRegion3D): static colliders, barrels, Pack-a-Punch, bookshelf
│        ├─ Map (map.glb) · Doors · lights, shafts, fires, rain
│        ├─ FX (fx.gd) · Zombies (zombie.gd × n) · Player (player.gd)
│        └─ dressing · physics · level_mods · shop · hammy · silly · wonder · escape
├─ Audio (audio.gd) → buses Master / Music (low-pass) / SFX
├─ SubViewportContainer (HUD, shrink ≤ 2) → SubViewport → HUD (hud.gd, CanvasLayer 5)
├─ Settings (settings.gd)
├─ Game (game.gd) → cutscene.gd · bosses.gd
└─ Menu (menu.gd, CanvasLayer 20, PROCESS_MODE_ALWAYS)
```

## Game state machine (`game.state`)

| State | Entered by | Ticks | Left by |
| --- | --- | --- | --- |
| `menu` | `_boot()`, `--menutest` | HUD only | `_start_game()` → `inter` |
| `inter` | `_start_game()` (3 s), wave clear (8 s) | Projectiles, pickups, box, combo, `inter_t` countdown | `start_wave()` → `play` |
| `play` | `start_wave()` | Everything; spawning; boss trigger; wave-clear check | All dead and quota spent → `inter`; `player_died()` → `over` |
| `cutscene` | `cutscene._begin()` | World look + HUD; zombies `PROCESS_MODE_DISABLED` except `keep` | `_end()` restores `cut_prev_state` |
| `over` | `player_died()`, escape end | Nothing gameplay-side | Scene reload (R/X restart, ESC menu) |
| `stage` | Test modes | Like `menu` (no spawning) | Test quits |

## Input routing (`main.gd:240 _input`)

The order of checks matters:

1. Device detection: a pad button or stick above 0.4 sets `game.pad = true`; keys, mouse buttons or mouse motion above 3 px set it false. Either change calls `hud.device_changed()`.
2. Mouse motion while captured goes to `player.on_mouse()`, and nothing else runs.
3. Menu visible: return (the menu handles its own `_unhandled_input`).
4. Cutscene playing: any press except F11 or stick motion requests a skip.
5. `pause`: game over reloads to the menu; otherwise `play` or `inter` opens the pause menu. The event is marked handled.
6. Click to recapture the mouse. F11 toggles fullscreen.
7. Discrete actions: reload, use, use_reload (contextual), nade/nade2, swap, slot1/2, melee, torch, wheel swap.

Continuous inputs (move, sprint, fire, ADS, stick look) are polled in `player._physics_process`.

## Collision layers

| Bit | Name | Used by | Hit by |
| --- | --- | --- | --- |
| 1 | WORLD | Level boxes, floors, ramps, door barriers, barrels, bookshelf, box, PaP | Player, zombies, grenades, rays |
| 2 | ZOMBIE_BODY | Zombie capsules | Player movement |
| 4 | HITBOX | Zombie limb `Area3D`s (meta `zombie`, `zone`) | Shoot rays |
| 8 | ROOF | Ceiling slabs | Rain and fog roof check only |
| 16 | SHOOT | Glass, lockers, lamps, extinguishers, balloons | Shoot rays, wonder projectiles |
| 32 | DEBRIS | Rigid props, ragdoll parts, gibs | Shoot rays, other debris |

The shoot ray mask is `1 | 4 | 16 | 32` with areas enabled (`game.gd:270`).

## Cross-system contracts

- `game` is the hub. Every subsystem holds `game` and reaches siblings through it (`game.world`, `game.player`, `game.hud`, `game.fx`, `game.audio`, `game.physics` and so on).
- `zombie.damage(amount, zone, dir, power, blast, at)` returns `{kill, head, armor?}`. All damage sources (guns, melee, explosions, Hammy, traps, props) go through it.
- `game.on_zombie_killed(z, head, blast)` is the only place that counts kills and awards kill points.
- `game._find_interact()` builds the prompt for the frame. `game.interact()` dispatches on `kind`.
- `world.rebake()` is debounced (`baking` / `bake_again`) and must be called after any change to WORLD-layer geometry: doors, barrels, the bookshelf, level mods.
- `game.hitstop(t)` sets `Engine.time_scale = 0.03` until `hitstop_until`; `game._process` restores it. Tweens that must keep running use `set_ignore_time_scale` or real-time timers.
