# LLD-03 Player and weapons

Part of the [Dead Shift game design document](GDD.md). File and line references point at `DeadShift/scripts/` as of 2026-10-09.

The player is a `CharacterBody3D` (`player.gd`). Movement runs in `_physics_process`; look, timers, firing and the viewmodel pose run in `_process`. Guns are data records from `map.json`, wrapped by `wdata()` for upgrades. Hitscan resolves in `game.shoot_ray`; projectile and cone guns resolve in `wonder.gd`.

## Body and camera

- **Collider:** a capsule (radius 0.3, height 1.75), layer 0, mask `WORLD | ZOMBIE_BODY`. Floor angle up to 52°, snap 0.45 m.
- **Camera:** eye height 1.6 m, near plane 0.05, far plane 120, FOV `base_fov` (default 72).
- **Lights on the camera:** a spot flashlight (26 m, 30°, shadows on, cull mask 1 so it doesn't light the gun), a 4 m carry fill light, and a 7 m muzzle light.
- **Viewmodel:** meshes are on visual layer 2 with shadows off. The knife and boot are box limbs parented to the camera.

## Movement (`_physics_process`, `player.gd:485`)

```
speed = (7.0 + 4.2·sprint) × (1 − 0.35·ads) × (0.55 if slowed) × (0.4 if stunned)
```

- **Acceleration:** 14 on the ground and 4 in the air (`move_toward` scaled by speed).
- **Jump and gravity:** jump 7.2 m/s, gravity 22.
- **Sprint:** eases toward 1 at 5/s. It needs forward input, ADS below 0.2 and the trigger released. Clicking the pad stick latches sprint until the stick returns to centre.
- **Steps:** step-up of 0.46 m when blocked on the floor (a `test_move` probe).
- **Landing:** a fall faster than −6 m/s triggers a landing dip and sound.
- **Recovery:** falling below y = −20 resets the player to `data.start`.

## Look (`_process`)

- **Mouse:** `0.0022 × sens_k / sqrt(1 + (ads_zoom − 1) × ads)` radians per pixel.
- **Right stick:** deadzone `pad_dead`, then the curve `0.35m + 0.65m³`, × 3.6 × `pad_k` × dt, with the same ADS scaling. The result passes through `_assist()`.
- **Limits and effects:** pitch is clamped to ±1.45 rad. Stun adds a wobble. The weapon sway `sw` follows the look delta.

## Slots and ammo

- **Slot record:** `{id, mag, res, up}`. `res = -1` means infinite (the starting pistol). At most 2 slots.
- **`give(id, reserve)`:** if the gun is already owned, refill its magazine and reserve (`up_reserve` if upgraded) and switch to it. If a slot is free, append it. Otherwise replace the held gun.
- **`reload()`:** blocked while already reloading, with a full magazine, with no reserve, or when dead. Sets `reload_t = wd.reload`. `_finish_reload` moves ammo from reserve, and revolvers and the sawed-off eject a casing per round.
- **`wdata(slot)`:** returns the base record, or a cached upgraded copy with `name = up_name`, dmg × 2.2, `mag = up_mag`, spread × 0.7, reload × 0.85, pierce + 1 and `up = true`.

## Fire pipeline

1. **Gate:** alive, trigger held, `fire_t ≤ 0`, not reloading, swapping or in Pack-a-Punch, and `mag > 0`. Semi-auto guns need a fresh press. An empty magazine clicks and auto-reloads.
2. **`shoot()`:** sets `fire_t = rate`. `mag − 1` unless Free Period is active.
3. **Spread:** `(spread + bloom) × (0.4 if ADS > 0.5) × (1.35 if moving)`. Each pellet direction is a uniform disc sample.
4. **Dispatch:**
    - `proj` or `cone` guns call `wonder.fire`.
    - `flame` guns call `game.flame`.
    - Everything else fires one `game.shoot_ray` per pellet. Single-pellet guns get magnetism: within 3.5° × `assist_k` of the aim point, the ray bends up to 2.2° × `assist_k` toward it.
5. **Feedback:** hit and kill markers and sounds, kick, shake, rumble, casing ejection (the shotgun pumps 0.3 s later), muzzle flash and light, FOV kick, bloom growth, and a low-ammo cue at 25% of the magazine.

## Aim assist (pad only, `player.gd:360`)

- **Target:** `_find_target(cone)` picks the nearest visible live zombie within 40 m whose aim point (head crown, or the body of a crawler) sits inside the cone. The cone scales by `clamp(6 / dist, 0.45, 1.6)`, and the score is `angle / limit + 0.004 × dist`.
- **Slowdown:** look speed drops by up to `(0.4 + 0.15 × ads) × k` inside 7°.
- **Rotational follow:** adds 0.55 × k of the target's angular motion while the player is steering or moving.
- **ADS snap:** on a fresh aim press, a target within `10 + 5k`° pulls the view onto it over 0.14 s.

## Melee

`melee()` has a 0.5 s cooldown (0.8 for the kick). The kind is `kick` if `sprint > 0.4`, `bayo` with the bayonet rifle, otherwise `knife`. It blocks firing for 0.35 s and calls `game.melee` after 0.09 s (0.14 s for the kick). Damage values are in [LLD-02](LLD-02-Game-rules.md).

## Damage and death

- **`hurt(dmg, acid)`:** ignored when dead or `invuln`. It resets `hurt_t`, then adds shake, roll, the HUD flash (green for acid), rumble and a jolt.
- **Death:** at 0 HP, sets `dead` and calls `game.player_died()`.
- **Regeneration:** 5 HP/s once `hurt_t > 4`. Below 30 HP a heartbeat plays every 0.85 s and the flashlight flickers.

## Gun models (`guns.gd`, static `RefCounted`)

- **`Guns.make(id, arms, world)`:** instances the exported web gun `.glb`. The last two pieces are the hand and sleeve, kept only when `arms` is set. The Staple Cannon, Textbook Launcher, Dodgeball Cannon, Trombone and Detention Slip are built from boxes in code.
- **`Guns.upgrade_skin(node)`:** puts the violet circuitry material on everything except the `hand` meta parts.

## Wonder weapons (`wonder.gd`)

**Shot record:** `{n, v, kind, t, up, dmg, bounces, chains, hit[], spin}`.

**Each frame:**

- Gravity: 11 for books, 5 for dodgeballs, 0 for slips.
- A swept ray against `1 | 16`, plus a 0.2 m-step capsule check against zombies (`_zombie_at`) so fast shots can't tunnel through.
- Lifetime: 6 s, or 1.5 s for slips.

**Behaviour by kind:**

| Kind | Speed | On a zombie | On a wall | Upgraded |
| --- | --- | --- | --- | --- |
| `book` | 21 forward + 2 up | 240 (head if hit high), stagger 1.6, shove 9 m/s; bounces off, spent after 2 bounces | Up to 2 bounces at ×0.45, then becomes a physics gib | 3 books, ±5° |
| `dodge` | 27 | 95, stagger 0.8, then retargets the next visible zombie within 11 m at 24 m/s; spent after 3 chains | Up to 6 bounces at ×0.8, banks toward a zombie within 9 m | 5 chains, splits per chain (max 24 shots) |
| `slip` | 30 | Teleports the zombie to the farthest open spawn (`emerge 2.5`), +50 | Puff, spent | Deletes the zombie as a kill, +50 |
| `cone` (Trombone) | — | All zombies in 7.5 m / 32° half-angle with line of sight take `80 × (1 − 0.5 d/r)`, stagger 1.1, shove 11 × k | — | 10 m / 40° |

## Pack-a-Punch (`shop.gd`)

- **Machine:** `PAP_POS (-1.6, 4, -43.25)`, used from `PAP_SPOT`, costs 5,000.
- **Prompt:** shows "needs power" when unpowered, "already upgraded" when done, "Upgrading…" while busy.
- **`pap_buy()`:**
    1. Sets `pap_busy = 3.4` and `player.pap_t = 3.5`, which hides the viewmodel and blocks firing and swapping.
    2. On completion, sets `slot.up = true`, refills the magazine and `up_reserve`, rebuilds the gun, and shows the WEAPON UPGRADED banner.
- **Machine lighting:** the slot lights up and pulses violet while busy.
- **Upstairs wall-buys:** `shop._display()` builds the chalk-outline displays for wall-buys marked `built: true` in the data (bayonet, upstairs SMG, staple, trombone, dodgeball).
