# LLD-08 Data, build and tests

Part of the [Dead Shift game design document](GDD.md). File and line references point at `DeadShift/scripts/` as of 2026-10-09.

All level and weapon tuning lives in one JSON file. Player progress lives in one ConfigFile. The build is a single Windows preset. Testing is done with command-line modes built into `main.gd` and `tests3.gd`, which drive the real game and save screenshots to `user://`.

## `data/map.json`

It is exported from the web game and loaded by `world._ready()` with `JSON.parse_string`. All positions are world metres (y up), as `[x, y, z]` arrays.

| Key | Count | Record shape | Consumed by |
| --- | --- | --- | --- |
| `collision` | 247 | `{pos, size}` axis-aligned box | `world._build_collision` (WORLD, under Nav) |
| `floors` | 36 | `{pos, size, rot[9]}` (3×3 row-major) | Same, rotated |
| `ceilings` | 13 | `{pos, size, rot[9]}` | ROOF layer (rain and fog only) |
| `ramps` | 2 | `{x0, x1, z_bottom, z_top, rise}` | Smooth stair ramps |
| `doors` | 10 | `{id, cost, label, nodes[], barriers[{pos, size}], spots[[x,y,z]]}` | `world.doors`, `game._find_interact` |
| `spawns` | 28 | `{area, pos}` (area = `yard` or a door id) | `game._pick_spawn`, Detention Slip |
| `wallbuys` | 12 | `{id, cost, ammo, reserve, spot, show, face?, built?}` | Prompts; `shop._display` when `built` |
| `boxes` | 8 | `{name, pos, ry}` | Mystery box spots |
| `start` | 1 | `[x, y, z, yaw]` | Player spawn and fall reset |
| `lights` | 42 | `{pos, color[rgb 0–255], energy, range}` | `world._build_lights` |
| `shafts` | 22 | `{a, b, r, color, op}` | Light-shaft cones |
| `fires` | 4 | `[x, y, z, scale]` | Fire particles and light |
| `weapons` | 16 | Keyed by id (below) | Player, box, shop, HUD |
| `box_pool` | 17 | `[weapon id]`; duplicates weight the roll | Mystery box |
| `zombie_samples` | 20 | `{kind, look, scale, arm_style, lean, sway, joints[{n, parent, pos}], parts[{node, joint, head, armor}]}` | `zombie.setup`; one per `z00`–`z19.glb` |

**Weapon record fields**

| Field | Meaning |
| --- | --- |
| `name` / `up_name` | Display name / Pack-a-Punch name |
| `mag`, `up_mag` | Magazine size, base / upgraded |
| `rate` | Seconds between shots |
| `dmg`, `pellets` | Per-pellet damage, pellets per shot |
| `spread`, `bloom`, `bloomMax` | Cone (rad), bloom added per shot, bloom cap |
| `reload` | Seconds |
| `kick` | Recoil and shake scale (also drives rumble and puffs) |
| `pierce` | Zombies a ray passes through |
| `power` | Knockback, stagger and gore strength (7 or more gibs on a kill) |
| `auto` | Hold to fire |
| `flash` | Muzzle offset in viewmodel space |
| `ads_zoom`, `ads_x`, `ads_y` | ADS FOV divisor and viewmodel pose |
| `box_reserve`, `up_reserve` | Reserve when taken from the box / after an upgrade (−1 = infinite) |
| `reload_snd`, `shot_snd` | SFX names |
| `fov` | Optional FOV kick |
| Behaviour flags | `flame` + `range`, `bolt` + `blast_r`, `staple`, `proj` (book, dodge, slip), `cone`, `wonder` |

## Save file (`user://deadshift.cfg`)

On Windows this is `%APPDATA%\Godot\app_userdata\Dead Shift- Westfield High\deadshift.cfg`, a Godot `ConfigFile` with two sections. `[settings]` holds every key of `settings.s` and `[scores]` every key of `settings.scores` (both listed in [LLD-06](LLD-06-Presentation-systems.md)). Keys missing from the file keep their defaults, so new settings are backward compatible. It is saved on the menu back buttons, on menu close, after each run, and after each escape.

## Build and distribution

- **Project:** `project.godot` is Godot 4.4 with the GL Compatibility renderer (desktop and mobile), 1280 × 720, stretch disabled, Jolt physics at 60 Hz, MSAA off, 16 lights per object, 2,048 directional shadow map, and navigation cell 0.2 / 0.1.
- **Export preset:**
    - Windows Desktop, x86_64, S3TC/BPTC textures.
    - `export_filter = all_resources`, `include_filter = data/*.json` (needed because the JSON isn't an imported resource).
    - `script_export_mode = 2` (binary tokens, so the scripts ship as `.gdc`).
    - `embed_pck = true`, export path `DeadShift.exe`.
- **Current distribution:** the shipped zip has `DeadShift.pck` next to a copy of the stock Godot 4.4.1 exe renamed `DeadShift.exe`. Godot auto-loads a `.pck` with the same base name. `Play_DeadShift.bat` makes that copy on first run.
- **Open question:** the preset embeds the pck in the exe while distribution uses a separate pck. Pick one: set `embed_pck = false` for the current flow, or ship the single exe.

## Test and debug modes

Run as `DeadShift.exe -- <flags>`. Godot passes everything after `--` to `OS.get_cmdline_user_args()`. Screenshots go to `user://`.

| Flag | What it does |
| --- | --- |
| `--bot` (+ `--time=N`, `--shots=S`) | A crude AI player: aims at the nearest visible zombie, fires, grenades crowds, buys the AK at 1,200. Prints perf and state every 5 s, and quits after N s |
| `--stage` | Lines up one of each type, tests headshot, sever, armor, crawler, barrel chain, box roll and grenade, with screenshots `stage_1`–`10` |
| `--rules` | 100,000 points; buys every door and wall-buy and the box, prints prompts and results; checks navmesh paths yard → library and start → upstairs |
| `--chase` | All doors open, an immortal player at 5 spots, 18 fast walkers from random spawns; reports how many reached the player in 40 s and where the rest got stuck |
| `--extras` | Each boss (coach, principal, chem), the knife, Hammy feeding and bite |
| `--newtest` | PaP on the Staple Cannon, staple pinning, upstairs display, Hall Monitor whistle, Lunch Lady |
| `--phystest` | Ragdolls, grenade props, vending machine, extinguisher, trophy case glass, lockers, bookshelf, lamp swing |
| `--powertest` | Walks to the breaker, films the power cutscene, then a Principal entrance |
| `--menutest` | Menu, settings, pad prompts, unlocks, play, pause, death |
| `--tour=x,y,z,yaw,pitch;…` | Screenshots from fixed camera spots |
| `--topdown=x,z,size,cam_y[,near]` | Orthographic overhead shot for level planning |
| `--probe` | Navmesh closest-point and door and balcony ray probes |
| `--t3=a,b,…` | `tests3.gd` sections: `pad`, `hats`, `power`, `gate`, `hammy`, `guns`, `boss`, `pa`, `escape`, `intro`; `pause`, `rag` and `hitscan` also exist |

Every mode except `--menutest`, `--powertest`, `--probe` and `--t3=intro` turns the school's power on at start. Test helpers set `game.state = "stage"` to stop spawning, and use `player.hp = 1e9` or `player.dead = true` to keep scenes static.
