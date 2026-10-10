# LLD-05 World, navigation and physics

Part of the [Dead Shift game design document](GDD.md). File and line references point at `DeadShift/scripts/` as of 2026-10-09.

`world.gd` turns `data/map.json` plus `map.glb` into a playable level: visuals, invisible box collision, one baked navmesh, doors, lamps and weather. `level_mods.gd` adds geometry the exporter missed. `physics.gd` owns every loose rigid body and the physical props. Anything on the WORLD layer under the `Nav` node shapes the navmesh, so changes to it must call `world.rebake()`.

## Map build (`world._ready`)

1. **Environment:** colour background `#0B0D12`, ambient `#7A86A0` at 0.62, depth fog 6–34 m, glow 0.6 (HDR threshold 1.1), contrast 1.08, saturation 0.9, linear tonemap.
2. **Visual map:** `map.glb` is instanced, and `_crisp()` sets every material to nearest-with-mipmaps, Lambert, no specular, roughness 1. Meshes named `door_*` are regrouped under `Doors/<id>` per the data's `doors[].nodes`. Each door's `barriers` become WORLD boxes under `Nav`.
3. **Collision:**
    - 247 `collision` boxes and 36 rotated `floors` (3×3 `rot` matrices) go under `Nav`.
    - 13 `ceilings` go on `ROOF_LAYER` (8), outside `Nav`, for the rain and fog check only.
    - A 130 × 100 m safety ground sits at y = −0.6.
    - Two smooth ramps cover the staircases.
4. **Lights:** 42 omni lights with `energy × 2.4 + 0.5` (0.5–4) and `range × 1.25` (4–20 m), no shadows. 18% flicker and 30% are dead while unpowered.
5. **Atmosphere:** 22 additive light-shaft cones, 4 fires (particles plus a flickering light), and rain (1,400 GPU particles that follow the camera).
6. **Navmesh:** parses `STATIC_COLLIDERS` on mask WORLD. Agent radius 0.4, height 1.8, max climb 0.5, max slope 50°, cell 0.2 × 0.1, region min size 4.

## Navmesh rebakes

`rebake()` bakes on a thread (`bake_navigation_mesh(true)`). A call while a bake is running sets `bake_again`, and `_on_baked` starts one more bake. The first bake fires `nav_ready`, which `main` awaits.

**Rebake triggers:** the barrel floor snap, a barrel exploding, every door opening (after one physics frame), `level_mods` setup, `physics` setup, and the bookshelf block, break and restore.

## Doors

`doors[id] = {node, barriers[], open, def}`. `open_door(id)` frees the barriers, tweens each mesh 2 m down with a random tilt over 0.8 s, frees the group, waits a physics frame and rebakes. Spawns are gated separately through `game.open_areas`.

## Look update (`update_look`, every frame)

- **Rain and fog:** rain follows the camera and stops when an upward ray hits `WORLD | ROOF`. Fog eases to 4–30 m outdoors and 6–30 m indoors.
- **Lamps:** the first frame after the navmesh bake marks outdoor lamps (no roof above) as always on. A powered lamp runs at base energy, with a flicker on flicker lamps. An unpowered lamp is 0 if dead, otherwise 0.32 with random stutters.
- **Power:** `power_on(from, stagger)` sorts the lamps by distance from `from` and turns them on at `i × stagger` s (0.025 in the power cutscene) with a brief 1.6× flash, and tweens ambient to 0.75.

## Level mods (`level_mods.gd`)

- **Doorways:** `_doorway(x, zc)` at (−16, −35) and (0, −38.5) builds ragged jambs, a header and rubble.
- **Balcony hole:** `_balcony_hole()` adds splintered boards, a rubble ramp from the bleachers to the gym balcony, and a debris heap.
- **Breaker:** `_breaker()` sits at `SWITCH_POS (21.7, 5.3, −38)` and is used from `SWITCH_SPOT` within 1.8 m. Its red lamp blinks at 1 Hz until powered. `throw_switch()` tweens the lever up and turns the lamp green.

## Physics props (`physics.gd`)

Layers: rigid props and ragdolls are on `DEBRIS (32)` with mask `WORLD | DEBRIS`. Shootable static props are on `SHOOT (16)`.

| Prop | Built in | Reaction | Notes |
| --- | --- | --- | --- |
| Chairs, bins | `_chairs`, `_bins` | Rigid; `shot` impulse `dir × power × 0.9 × mass × 0.35` | Impact sound by `kind` meta: wood, metal, can, glass, tile, flesh |
| Glass | `_glass`: sneeze guard, trophy case (5 panes), 4 gym windows | `shatter`: 8–24 × detail shards, 8 s temp | Trophies inside are frozen until touched |
| Lockers | 12 upstairs at z = −31.5 | `bang_locker` swings the door (`v −= 9–14`), spring and damped | 30% have loot: 50% +50 points, otherwise an ammo box |
| Vending machine | (10, 0.95, 14.15), WORLD | `hit_vending`: 1–3 cans per hit, 0.12 s cooldown | 30 cans total |
| Fire extinguishers | 6 wall spots | Become rigid, thrust `−axis × 70` for 3.2 s | The spray cloud slows zombies within 2.2 m |
| Pendant lamps | 8 spots | Pendulum `v −= a × 9.8 / len`, damping 0.35 | Spot lights; energy ×0.35 unpowered |
| Ceiling tiles | On blasts under a ceiling | 3–6 × detail tiles, 20 s temp | — |
| Bookshelf | `SHELF_HOME (−16.52, 4, −37.6)` | `push_shelf` tweens to `SHELF_BLOCK` in 0.9 s | Blocks for 25 s, then `_break_shelf`; respawns after 45 s; each step rebakes |

**Per-frame rules** (`_physics_process`):

- Temp props freeze and sink in their last second, then are freed. Bleeding gibs leave drops. Anything below y = −20 is freed.
- Small props: one moving faster than 5 m/s hurts a zombie within 0.55 m for `12 + 2v` and staggers it. A walking zombie kicks clutter, with a 5% chance to stumble.
- Ragdolls freeze and sink after 9 s and are freed at 11 s.

## Ragdolls (`ragdoll(z, dir, power, head, blast)`)

1. For each of the 11 `RAG_PARTS` that still has visible meshes, make a RigidBody3D: mass 8 for the core and spine, 4 for the head, 2 for limbs, × `bscale`. Linear damping 0.4, angular 2.0. Reparent the meshes and fit a box collider to their AABB at ×0.9.
2. Add collision exceptions between all parts of the same body.
3. Join each part to its nearest surviving ancestor with a `ConeTwistJoint3D`: swing 30° and twist 15° for limb ends, 50° and 30° otherwise. Thighs attach to the core.
4. Velocity:
    - Base: `z.velocity × 0.5 + push`, where push = `hdir × clamp(power, 2, 12) × (1.6 if blast else 0.6)`.
    - Upward: +4 for a blast, otherwise 0.6.
    - The top half is pushed forward. A topple spin is added around `hdir × up`.
5. Sleep is disabled for 1.5 s. Ragdolls are capped at `12 × detail`, oldest freed first.

**Staple pin:** the Staple Cannon's `staple_pin` moves the latest ragdoll so the part nearest the hit is 0.22 m off a wall within 2.5 m (vertical walls only), then pins it with a `PinJoint3D` to a static anchor for 10 s.

**Bullets on corpses:** `shot` on a ragdoll is a capped nudge (velocity limited to 5 m/s and 8 rad/s) plus blood, so automatic fire doesn't juggle bodies.

## Detail scaling

`physics.detail` comes from the Physics Detail setting: 0.5 on Low, 1.0 on Normal. It scales the ragdoll cap (12), the temp-prop cap (90), shard and tile counts, and the horde cap ([LLD-02](LLD-02-Game-rules.md)).
