# Games

## Dead Shift: Westfield High

A CoD-Zombies-style survival FPS with a PS2 look, set in a high school on the night the last bell never rang.
Built in **Godot 4.4.1** (GL Compatibility renderer, Jolt physics).

| Folder | What's in it |
|---|---|
| `DeadShift/` | The Godot project. Open `DeadShift/project.godot` in Godot 4.4.1. |
| `docs/` | Design docs: the GDD and the low-level design notes (LLD-01 to LLD-08). |
| `tools/` | Scripts that generate assets (sounds, textures, music, map export) and build the Windows release. |

### Working on it

1. Install **Godot 4.4.1 stable** (Standard, not .NET): https://godotengine.org/download/archive/4.4.1-stable/
2. Clone the repo and open `DeadShift/project.godot`. The first open re-imports assets; that takes a minute.
3. Press F5 to play. `scripts/main.gd` is the entry point; `scripts/game.gd` holds the rules.

**Always pull before you start and push when you're done**, so both of us are on the latest version.
Commit small, focused changes with a clear message. If you're making a big change, use a branch and a pull request.

The `.godot/` folder is Godot's local cache and is not committed.

### Making the Windows build

Export from the editor (Project > Export > Windows Desktop), or run `GODOT=/path/to/godot tools/mkbuild.sh`,
which makes `build/DeadShift_Play.zip` (the game's `.pck`, a launcher `.bat` and a readme).
The launcher needs `Godot_v4.4.1-stable_win64.exe` placed next to it the first time (see `tools/Play_README.txt`).

### Asset tools

- `tools/gen_sfx.py`, `gen_sfx3.py`, `gen_sfx_bat.py`: generated sound effects (numpy + scipy + ffmpeg).
- `tools/gen_dressing.py`: posters, banners and other set-dressing textures.
- `tools/synth_track.py`: the "Night School" music track.
- `tools/godot_export.py`: regenerates `DeadShift/data/map.json`, the map, guns and zombies from the original web game's export.
  That source data (about 100 MB) is not in the repo; point `DEADSHIFT_SRC` at it. Day-to-day work doesn't need it.

### Test modes

Run the project with arguments after `--` to use the built-in checks, for example
`godot --path DeadShift -- --t3=bat,pause` or `-- --bot --time=120` (see `scripts/main.gd` and `scripts/tests3.gd`).
