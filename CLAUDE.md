# Working rules for this repo

- The Godot project lives in `DeadShift/` (Godot 4.4.1, GL Compatibility, Jolt physics). The owner is an artist/animator collaborating with another person.
- Sync with GitHub on every change: `git pull --rebase` before starting work, then commit and `git push` to `main` after each change, so the collaborator always has the latest version (and we get theirs).
- Never commit `DeadShift/.godot/` (cache) or `build/` (release output).
- Release builds are Windows executables (`tools/mkbuild.sh` makes the play zip). The web build on the `gh-pages` branch is not maintained; don't update it unless asked.
- GDScript: values from untyped objects need explicit types (`var x: T = ...`); `:=` inference fails on them.
