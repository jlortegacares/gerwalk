# Gerwalk — Combat Feel Prototype

Scope: the smallest build that can answer "does the 360° control and the
segmented HP bar feel right?" before any content investment.

Related: [requirements.md](requirements.md) — pillars P1/P2, FR-01..FR-08, FR-15,
decision D-03.

## Run it

```sh
./run.sh
```

Opens `levels/arena/arena.tscn`. Engine pinned to **Godot 4.7.2 stable, Forward+**.
`./run.sh --editor` opens the editor instead; `./run.sh --headless` runs without a
window and is what CI uses.

## Controls

| Action | Keyboard / mouse | Gamepad |
|--------|------------------|---------|
| Move | WASD | Left stick |
| Aim | Mouse position | Right stick |
| Fire | Left mouse button | Right stick deflection, or right shoulder |
| Dash | Space or Shift | Left shoulder |
| Restart | R (on the game-over screen) | Start |

Aiming and firing are independent of movement by construction: `_move()` never
reads the aim vector and `_update_aim()` never reads the movement vector.

## 3D presentation and the camera

The arena is a `Node3D` scene: the planet's surface is the play field, the ship
flies over it, and the camera is a `Camera3D`. **Gameplay stays on the `y = 0`
plane.** Hitboxes are planar, so a bullet that looks like it passes within a
pixel of the player does pass within a pixel. The third dimension is
presentation, not a second axis of evasion.

Three constraints shaped the camera and the geometry, and each is load-bearing:

1. **The player is pinned to the screen centre.** `CameraRig` is a `Node3D`
   parented to the player, and the `Camera3D` is its child. The rig only ever
   translates with the player, so the player projects to the exact centre of the
   viewport (measured at 0.05 px in the smoke test, at the spawn and again at the
   planet edge). Shake uses `h_offset` / `v_offset`, which move the image without
   moving the camera target.
2. **The camera is world-aligned and never rotates.** It keeps straight bullets
   straight on screen. Rotating it with the ship's heading would make every
   bullet appear to curve and P1's readability would collapse.
3. **The camera pitch is a compromise between depth and framing.** The rig sits
   at `(0, 50, 13.4)` with a `-75°` pitch and a `58°` field of view. That reads
   as a top-down shooter while still giving the surface a horizon and letting the
   ship throw a shadow, which is what sells altitude.

The ground is a surface of revolution built at runtime: flat out to
`ARENA_RADIUS = 55` and falling away on a quadratic profile to `RIM_DROP = 50` at
`GROUND_OUTER_RADIUS = 96`, where the mesh simply ends. The drop starts exactly at
the play boundary, so reaching the edge shows the surface rolling away into space
— the visual confirmation that the planet ends there instead of the player hitting
an invisible wall. Everything past `ARENA_RADIUS` is scenery: the boundary is a
radial clamp in `player.gd`, so no wall geometry can be tunnelled by a dash.

The surface itself is a procedural shader
(`levels/arena/planet_surface.gdshader`), not a texture. World-space fBm keeps
the same detail whether the ship is on top of it or near the horizon, and the
topographic isolines are the motion reference: on a uniform surface the player
cannot tell they are moving.

## What this build is meant to answer

1. **Does 360° aiming read clearly?** The aim line is there to check it, not to
   ship. If you cannot tell where you are shooting while moving the other way,
   P1 has a feedback problem, not a feature problem.
2. **Does the HP bar create tension instead of relief?** 6 segments, 1 damage
   per hit, 0.85 s of invulnerability. If you never feel threatened, the problem
   is the damage economy, not the bar.
3. **Are deaths attributable?** Every enemy pattern is telegraphed for 0.42 s
   and the two patterns are different on purpose:
   - **Ring** — 14 slow bullets. Dodge through the gaps. Tests reading space.
   - **Fan** — 5 fast aimed bullets. Dash or sidestep. Tests reaction.
4. **Is the dash a decision or a reflex?** 0.16 s burst, 0.85 s cooldown, and it
   grants invulnerability, so it doubles as an escape.
5. **Does flying over the planet read as a planet?** The whole disc is playable,
   the ship crosses it in a few seconds, and the surface rolls away into space at
   the boundary, so the planet has a visible edge rather than a lane wall. Surface
   detail is the orientation landmark: on a uniform plane a player cannot tell
   they are moving, so the ground is a world-space fBm shader with topographic
   isolines rather than a flat colour. `tests/smoke_test.tscn` drives a crossing
   of the surface through input actions and fails if the player leaves the disc
   or leaves the screen centre.

## Tuning knobs

All values are named constants at the top of each script.

| Feel | File | Constant |
|------|------|----------|
| Movement weight | `entities/player/player.gd` | `MAX_SPEED`, `ACCELERATION`, `FRICTION` |
| Fire rhythm | `entities/player/player.gd` | `FIRE_INTERVAL`, `BULLET_SPEED` |
| Risk margin | `entities/player/player.gd` | `MAX_HP`, `IFRAME_DURATION` |
| Evasion | `entities/player/player.gd` | `DASH_SPEED`, `DASH_DURATION`, `DASH_COOLDOWN` |
| Pattern cadence | `entities/enemy/turret.gd` | `TELEGRAPH_TIME`, `RECOVER_TIME` |
| Pattern shape | `entities/enemy/turret.gd` | `RING_BULLETS`, `RING_SPEED`, `FAN_BULLETS`, `FAN_CONVERGENCE`, `FAN_SPEED` |
| Arena topology | `levels/arena/arena.gd` | `ARENA_RADIUS`, `GROUND_FLAT_RADIUS`, `GROUND_OUTER_RADIUS`, `RIM_DROP` |
| Surface look | `levels/arena/planet_surface.gdshader` | fBm scales, palette stops, contour count and strength |
| Camera framing | `entities/player/player.tscn` | `CameraRig` position, pitch, `Camera3D.fov` |
| Camera shake | `entities/player/player_camera.gd` | `MAX_OFFSET`, `DECAY_PER_SECOND` |
| Enemy orbit | `entities/enemy/turret.gd` | `ORBIT_SPEED`, `ANGULAR_LEASH`, `FLEE_DISTANCE` |

## Architecture

```
common/global_event_bus.gd      lifecycle signals only (< 15 events)
common/hit_spark.*              self-freeing 3D impact flash
combat/projectile.*             one shared bullet, team decides layers + shape
entities/player/                CharacterBody3D, camera rig, aim, dash, HP
entities/enemy/turret.gd        turret: telegraph -> pattern -> recover, orbits the arena
ui/hud/                         listens to the bus, never touches the player
levels/arena/arena.gd           planet surface mesh, boundary ring, stars
```

Visuals are built in code (`_build_visual()`) instead of being serialised into
the `.tscn` files. Placeholder geometry is a swap target, not an asset: when the
pre-rendered pipeline lands (D-02) each entity can drop in a mesh or a sprite
without touching the scene graph or the collision shapes.

Ownership rule: the player owns its HP and only exposes `take_damage()`. The HUD
is a projection of `player_health_changed`. Nothing in the UI mutates gameplay.

## Checks

```sh
# Headless gameplay assertions (movement, firing, patterns, i-frames, death)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn

# Render one real frame to /tmp/gerwalk_frame.png for visual review
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn
```

Both exit non-zero on failure. The smoke test drives input through `InputMap`
actions, so it exercises the same path a player does.

## Known gaps

- **Bullets are one node each.** At 400 concurrent bullets this will need a
  pooled manager or `PhysicsServer3D` (NFR-05). Not measured yet.
- **No audio.** Hit and dash feedback are visual only.
- **No art.** Every visual is a runtime placeholder mesh built in code; the
  pre-rendered asset pipeline (D-02) is untouched, and whether entities become
  real-time meshes at all is OPEN-06.
- **No wave escalation.** One enemy respawns on a 1.2 s timer, so difficulty is
  flat (FR-10 is still a proposal, not implemented).
- **i-frames and dash are prototypes of FR-09 and FR-11**, which remain
  unconfirmed product requirements — try them and decide, do not assume.
