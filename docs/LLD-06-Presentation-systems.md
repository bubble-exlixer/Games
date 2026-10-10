# LLD-06 Presentation systems

Part of the [Dead Shift game design document](GDD.md). File and line references point at `DeadShift/scripts/` as of 2026-10-09.

Presentation is six independent services that gameplay calls one way: `hud.gd`, `fx.gd`, `audio.gd`, `cutscene.gd`, `menu.gd` and `settings.gd`. None of them changes game rules. The exceptions: cutscenes freeze actors and switch `game.state`, and menus pause the tree.

## HUD (`hud.gd`, CanvasLayer 5, inside the half-resolution HUD viewport)

- **Fonts:** Black Ops One (display) and VT323 (mono), duplicated with antialiasing off, no hinting and oversampling 0.5 for hard pixels.
- **Palette constants:** `INK #E6DCCB`, `DIM #8A8273`, `BLOOD #B3121B`, `BLOOD2 #6E080E`, `AMBER #D9A441`, `GOLD #FFD36B`.
- **Screen layers, bottom to top:** hurt flash (red, alpha 0.15–0.55 by damage), bile flash (green 0.4), radial vignette (0.62 at the edge), and a 2-pixel scanline shader (alpha 0.14).
- **Panels:** `tl` (wave and health with a ghost bar), `tr` (points), and bottom right (gun, ammo, grenades, x2). Each panel jolts and sways as a group.
- **Centre:** prompt, hint, banner and subtitle, callout and small callout, combo box, crosshair (spread-driven) with hit markers, DMR scope, boss bar, now-playing label, letterbox and cut titles, and the game-over and escaped screens.
- **`update(dt, state)`:** each frame `game` passes `player.hud_state()` merged with `{round, points, prompt, nades, x2}`.
- **Button tokens:** `{action}` in any text goes through `keys()`. On keyboard it becomes the key name in gold. On pad it becomes a coloured Xbox badge (A green, B red, X blue, Y yellow) via `BTN` and `PAD_COL`. `rset()` caches by text plus device so labels re-parse only on a change. `device_changed()` refreshes the live labels and the menu hint.
- **Animated calls:**
    - `banner` scales from 1.5× with −4°, holds for `dur` of real time, and is token-guarded so a newer banner wins.
    - `points_pop` spawns a floating +N and punches the counter for values of 100 or more.
    - `jolt(k)` adds shake up to 1.
    - `combo(n, k)` and `combo_end` drive the combo box.

## FX (`fx.gd`, a Node3D under the world)

- **Particles:** one `MultiMesh` of 0.08 m unshaded cubes, `CAP = 1400` instances, with vertex colours. Each particle is `{p, v, s, c, life, blood, str, fl}`. Every frame they fall at gravity 16 and settle on the floor height `fl` cached at spawn. Streaked particles stretch along their velocity. Blood landing faster than −2 m/s has a 30% chance to leave a splat decal, limited to 3 per frame (`splat_budget`).
- **Decals:** quads with procedural splat textures (3 blood variants, bullet hole, bile) plus `scorch.png`, capped at `MAX_DECALS = 170`, oldest freed first. Calls: `splat`, `wall_splat`, `hole`, `scorch`, `bile_splat`.
- **Puffs:** mesh billboards that grow from s0 to s1 along √t and fade.
- **Gibs and casings:** ray-swept bounce on the real floor. Gibs bleed a trail and splat on landing. Casings click on their first two bounces.
- **Composite calls:**
    - `blood_hit` (entry splash, exit spurt, drops, mist)
    - `blood`, `gib_bits`, `spark`, `splash`
    - `tracer` (a stretched quad)
    - `arc` (a jagged chain of tracers)
    - `flash_light` (a temporary OmniLight)
    - `boom` (fireball puffs, sparks, scorch, a light flash; bile variant)
    - `eject`

## Audio (`audio.gd`)

- **Buses:** `Music` (with a low-pass, −5 dB) and `SFX`, both feeding Master.
- **Assets:** sounds load lazily from `res://assets/audio/sfx/<name>.ogg` and are cached. A missing file plays nothing.
- **`play(name, pos, vol_db, pitch)`:** with no `pos`, a 2D `AudioStreamPlayer`. Otherwise an `AudioStreamPlayer3D` under `world_root` (unit size 6, max distance 70, inverse-distance falloff). Pitch gets ±3% jitter.
- **Voice caps (`_cap`):**

    | Sounds | Simultaneous voices |
    | --- | --- |
    | `shot_*` | 2 |
    | Hit and kill markers, crackle, low-ammo cue | 1 |
    | Impacts and footsteps | 4 |
    | Everything else | 6 |

    A new voice over the cap fades the oldest out in 50 ms. This stops the phasing whine automatic fire used to cause.
- **Music:** `set_track(name)` crossfades (out 1.2 s, in 0.6 s) and fires `on_track`, so the HUD shows NOW PLAYING. `set_calm(true)` tweens the low-pass to 900 Hz between waves and back to 20 kHz in play. The ambience loop runs on the SFX bus.

## Cutscenes (`cutscene.gd`)

- **Shot spec:** `{from, to | path[], look | look_from + look_to, dur, fov, end_dir?, events: [[t, Callable]]}`. Position lerps or follows a Catmull-Rom path with smoothstep easing.
- **`play(shots, keep, run_skipped)`:**
    - `_begin` saves `game.state`, sets it to `cutscene`, freezes the player and hides the viewmodel, disables every zombie except `keep`, and switches to the cutscene camera with letterbox.
    - On skip, remaining events still fire when `run_skipped` is set, so lights and banners stay consistent.
    - `_end` restores everything.
- **Scenes:**
    - `intro()`: 6.5 s path from the sky to the player's eye, then the controls hint banner.
    - `boss(z)`: 3.4 s push-in, pulled in from walls by a ray, with `z.emerge = 3.6`.
    - `power()`: four shots, with the lamps cascading from the breaker.
    - `infection()`: the prologue. Disabled actors are humanized (clean materials), then `_turn()` flickers them to zombie looks.
    - The escape cutscene is built in `escape.gd` ([LLD-07](LLD-07-Set-pieces.md)).

## Menus (`menu.gd`, CanvasLayer 20, `PROCESS_MODE_ALWAYS`)

- **Pages:** dictionary `pages`, one `VBoxContainer` per page.

    | Page | Contents |
    | --- | --- |
    | `main` | Title, best line, PLAY, MAP: WESTFIELD HIGH (no-op), BUNKER 9 (COMING SOON, disabled), LOADOUT & UNLOCKS, SETTINGS, QUIT |
    | `pause` | RESUME, SETTINGS, QUIT TO MENU (reloads the scene), QUIT GAME |
    | `settings` | Sliders and choices bound to `settings.s` keys |
    | `unlocks` | Start gun, skin, unlock checklist |

- **Widgets:** `_slider(key, lo, hi, step, fmt)` and `_choice(key, opts, names, locked)` write straight to `settings.s` and call `main.on_settings_changed()` and `settings.apply()`. Locked options check `settings.unlocked(id)`.
- **Showing a page:** `show_page` grabs focus on the first enabled control so pad navigation works. `open_pause` pauses the tree.
- **Back actions:** `_unhandled_input` maps pause and cancel to back, saving settings on the way out.
- **Background:** while the main menu is open, the cutscene camera loops a 15-point Catmull-Rom path through the school every 70 s.

## Settings (`settings.gd`)

- **`s` defaults:**

    | Key | Default |
    | --- | --- |
    | sens | 1.0 |
    | fov | 72 |
    | master / music / sfx | 0.85 / 0.7 / 1.0 |
    | fullscreen | false |
    | pixel | 2 |
    | physics | 1.0 |
    | start_gun | pistol |
    | skin | normal |
    | invert_y | false |
    | pad_sens | 1.0 |
    | aim_assist | 1.0 |
    | pad_dead | 0.15 |

- **`scores`:** best_wave, best_kills, best_points, total_kills, games, escapes, best_escape_points, fastest_escape, escape_wave, escaped_from.
- **`apply(main)`:**
    - Sets bus volumes (music −5 dB offset) and the window mode.
    - Sets the 3D `stretch_shrink = pixel` and the HUD shrink to `clamp(pixel, 1, 2)`.
    - Sets `physics.detail`.
- **`record()`:** updates the maxima and totals, saves, and returns `{best, unlocks: [names newly earned]}`.
- **`record_escape()`:** wraps `record()` and adds the escape records with `first_escape` and `fastest` flags.
