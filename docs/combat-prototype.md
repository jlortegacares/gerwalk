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
| Afterburner (hold) | Shift | Right trigger |
| Dash | Space | Left shoulder |
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
   viewport (measured at 0.05 px in the smoke test, at the spawn and again after a
   long run). Shake uses `h_offset` / `v_offset`, which move the image without
   moving the camera target.
2. **The camera is world-aligned and never rotates.** It keeps straight bullets
   straight on screen. Rotating it with the ship's heading would make every
   bullet appear to curve and P1's readability would collapse.
3. **The camera pitch is a compromise between depth and framing.** The rig sits
   at `(0, 50, 13.4)` with a `-75°` pitch and a `58°` field of view. That reads
   as a top-down shooter while still giving the surface a horizon and enough of a
   side-on view that the ship shows its wings and tail instead of reading as a
   flat silhouette.

### The planet rolls under the ship

The ground is a sphere of `PLANET_RADIUS = 400` whose centre tracks the ship's
planar position, so the ship is always at the sphere's pole. At this size the
limb sits outside the frame: the surface fills the screen and reads as a
continuous terrain rather than a globe. **The planet is the travel mechanism, not
a backdrop**: every
physics frame the arena turns it by exactly the arc length the ship covered,
about the axis perpendicular to the movement:

```gdscript
axis  = Vector3(-movement.z, 0.0, movement.x).normalized()
angle = distance / PLANET_RADIUS          # rolling without slipping
```

Three consequences, and all three are deliberate:

- **No boundary.** The surface under the ship is replaced as the planet turns, so
  a straight line never hits a wall. Travelling `2 * PI * PLANET_RADIUS`
  (≈ 2513 units, about 94 s at top speed) brings the original terrain back under
  the ship: the planet is finite and circumnavigable, and "cover the whole
  planet" is a lap, not a wall.
- **The geometry never moves in world space.** A sphere is rotation-invariant, so
  rotating it changes no vertex, no normal and no silhouette — only the shader's
  object-space input. That is why the roll is cheap and why it cannot desync from
  the collision plane.
- **The roll is applied after the player moves.** `Arena.process_physics_priority
  = 100` makes the arena step last; otherwise the terrain would lag one frame
  behind the ship and shimmer.

`PLANET_RADIUS` is the one number that sets the scale of the fantasy. A larger
radius means a longer lap and a flatter horizon; a smaller one means a curvier
surface with the limb closer to the ship. At 400 a lap is ≈ 2513 units (≈ 94 s of
flight), which is the "there is a lot of planet to cross" the design wants. The
price is curvature: the camera looks 75° down from 51.5 units above the surface,
so past a radius of about 100 the top of the screen meets the ground before the
horizon and the limb leaves the frame. The planet then reads as a continuous
surface, not a globe. Getting the limb back would need a camera about
`0.54 * PLANET_RADIUS` above the ground, which shrinks the ship and the fight to
nothing — a bigger planet is incompatible with a close cockpit.

The surface itself is a procedural shader
(`levels/arena/planet_surface.gdshader`), not a texture. It samples **object
space** with 3D value noise: the terrain has to be painted onto the sphere so it
turns with it, and the ship sits at the pole of its own patch, where any spherical
UV layout collapses. 3D noise has no poles and is uniform over the whole planet.
The topographic isolines are the motion reference: on a uniform surface the player
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
5. **Can speed itself be a resource?** The afterburner is a tank, not a cooldown:
   holding it tops out at 42 instead of 26.8 and drains the reserve in about
   2.2 s, and the reserve only fills back while the burner is off (about 4.2 s
   from empty). Emptying it latches until the button is released, so holding the
   key at zero cannot stutter the ship between two speeds. The dash stays a
   separate tool: a 0.16 s invulnerable burst does something the burner does not.
6. **Does flying over the planet read as a planet?** The ground is a real sphere,
   the ship can fly in one direction forever, and the surface turns under it so
   the whole planet passes beneath the ship. At the current radius the limb is
   outside the frame, so the planet is sold by the rolling terrain and by the lap,
   not by a visible edge. Surface detail is the orientation landmark: on a uniform
   plane a player cannot tell they are moving, so the ground is an object-space
   fBm shader with topographic isolines rather than a flat colour. Enemies live on
   the planet too: they roam the surface, engage when the ship comes close and are
   left behind when it leaves. `tests/smoke_test.tscn` drives a long run through
   input actions and fails if the ship stops being able to travel, if the planet
   drifts off the ship, if the planet turns by anything other than
   `distance / PLANET_RADIUS`, or if a turret follows the ship.

## Tuning knobs

All values are named constants at the top of each script.

| Feel | File | Constant |
|------|------|----------|
| Movement weight | `entities/player/player.gd` | `MAX_SPEED`, `ACCELERATION`, `FRICTION` |
| Fire rhythm | `entities/player/player.gd` | `FIRE_INTERVAL`, `BULLET_SPEED` |
| Risk margin | `entities/player/player.gd` | `MAX_HP`, `IFRAME_DURATION` |
| Evasion | `entities/player/player.gd` | `DASH_SPEED`, `DASH_DURATION`, `DASH_COOLDOWN` |
| Afterburner speed | `entities/player/player.gd` | `BOOST_SPEED`, `BOOST_ACCELERATION`, `FOV_BOOST_KICK`, `FOV_RATE` |
| Turbo economy | `entities/player/player.gd` | `TURBO_MAX`, `TURBO_DRAIN_PER_SECOND`, `TURBO_RECHARGE_PER_SECOND` |
| Thruster plume | `entities/player/player.gd` | `THRUSTER_X`, `THRUSTER_Z`, flame lengths and alphas in `_update_afterburner_visual()` |
| Ship silhouette | `entities/player/player.gd` | fuselage stations in `_build_fuselage()`, wing outlines in `_build_wing()`, tail surfaces in `_build_empennage()` |
| Wing sweep | `entities/player/player.gd` | `WING_SWEEP_FORWARD`, `WING_SWEEP_BACK` (degrees on top of the wing's built-in leading-edge sweep) |
| Muzzle clears the nose | `entities/player/player.gd` | `MUZZLE_DISTANCE`, `BEAM_START` |
| Pattern cadence | `entities/enemy/turret.gd` | `TELEGRAPH_TIME`, `RECOVER_TIME` |
| Pattern shape | `entities/enemy/turret.gd` | `RING_BULLETS`, `RING_SPEED`, `FAN_BULLETS`, `FAN_CONVERGENCE`, `FAN_SPEED` |
| Planet scale and lap length | `levels/arena/arena.gd` | `PLANET_RADIUS` (lap = `2 * PI * PLANET_RADIUS`), `PLANET_SEGMENTS`, `PLANET_RINGS` |
| Ground height | `levels/arena/arena.gd` | `GROUND_Y` |
| Surface look | `levels/arena/planet_surface.gdshader` | noise scales, palette stops, contour count and strength |
| Camera framing | `entities/player/player.tscn` | `CameraRig` position, pitch, `Camera3D.fov` |
| Camera shake | `entities/player/player_camera.gd` | `MAX_OFFSET`, `DECAY_PER_SECOND` |
| Enemy engagement | `entities/enemy/turret.gd` | `AGGRO_RADIUS`, `LEASH_RADIUS`, `ORBIT_RADIUS`, `PURSUIT_SPEED`, `STRAFE_SPEED` |
| Enemy roaming | `entities/enemy/turret.gd` | `ROAM_SPEED`, `ROAM_LEG_MIN`, `ROAM_LEG_MAX`, `ROAM_LEG_TIME` |
| Encounter streaming | `levels/arena/arena.gd` | `MAX_ENEMIES`, `SPAWN_INTERVAL`, `SPAWN_DISTANCE_MIN/MAX`, `SPAWN_HEADING_SPREAD`, `DESPAWN_DISTANCE`, `FIRST_SPAWN_DISTANCE/ANGLE` |

## Architecture

```
common/global_event_bus.gd      lifecycle signals only (< 15 events)
common/hit_spark.*              self-freeing 3D impact flash
combat/projectile.*             one shared bullet, team decides layers + shape
entities/player/                CharacterBody3D, camera rig, aim, dash, afterburner, HP
entities/enemy/turret.gd        turret: roam -> engage -> telegraph -> pattern -> recover
ui/hud/                         listens to the bus, never touches the player
levels/arena/arena.gd           rolling planet sphere, stars, encounter streaming
```

Visuals are built in code (`_build_visual()`) instead of being serialised into
the `.tscn` files. Placeholder geometry is a swap target, not an asset: when the
pre-rendered pipeline lands (D-02) each entity can drop in a mesh or a sprite
without touching the scene graph or the collision shapes.

The player airframe is lofted and extruded rather than assembled from engine
primitives. `_loft()` sweeps octagonal stations along the fuselage, so the
planform — pointed nose, intake shoulders, narrow tail — is data, not geometry
code; `_slab()` extrudes a flat outline into a wing, tailplane or fin, and one
outline serves both sides through a mirror flag. `_face()` winds every triangle
against an outward hint, which removes the usual failure mode of a hand-built
mesh (a face that comes out inside-out and lights like a hole); the materials also
run with `CULL_DISABLED` as a second guard.

The swing wings hang off pivots at the wing root, so the sweep rotates around the
joint instead of sliding the wing through the fuselage. Sweep follows the
throttle, not the burner button: the tip swings aft as the ship gets faster, which
is the reference aircraft's signature and a free speed cue beside the plume. The
muzzle distance tracks the nose so bullets leave the airframe instead of spawning
inside it.

Ownership rule: the player owns its HP and its turbo reserve, and only exposes
`take_damage()`. The HUD is a projection of `player_health_changed` and
`player_turbo_changed`. Nothing in the UI mutates gameplay. The turbo event fires
once per whole reserve unit rather than once per physics frame: the bar is 234 px
wide, so a unit is under 2.5 px and the bus stays quiet.

## Checks

```sh
# Headless gameplay assertions (movement, firing, patterns, i-frames, death)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn

# Render one real frame to /tmp/gerwalk_frame.png for visual review
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn

# Same, after travelling: the terrain must not match the resting frame
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --travel 180 --out /tmp/gerwalk_moved.png
```

Both exit non-zero on failure. The smoke test drives input through `InputMap`
actions, so it exercises the same path a player does.

## Known gaps

- **The ship is always at the top of the planet.** Because the sphere follows the
  camera, the player never sees the planet from outside or approaches an edge —
  the whole planet is traversed as terrain passing under the ship, not as a globe
  you fly around. Rendering it any other way would mean rotating the camera or
  curving the play plane, and both break planar hitboxes.
- **The roll is visible only through the terrain.** A sphere is rotation-invariant,
  so the only thing that moves is the shader's object-space pattern. Dark terrain
  plus slow movement makes the scroll hard to read; the isolines exist partly for
  that reason.

- **Bullets are one node each.** At 400 concurrent bullets this will need a
  pooled manager or `PhysicsServer3D` (NFR-05). Not measured yet.
- **No audio.** Hit and dash feedback are visual only.
- **The afterburner outruns everything on purpose.** `BOOST_SPEED` (42) sits far
  above `PURSUIT_SPEED` (24), so a full reserve buys a clean disengage. The
  reserve is the price; if escaping stops feeling earned, raise the drain before
  lowering the speed.
- **Shift no longer dashes.** It is the afterburner now; the dash is Space. The
  keyboard mapping is the one binding that changed when the burner landed.
- **No art.** Every visual is a runtime placeholder mesh built in code; the
  pre-rendered asset pipeline (D-02) is untouched, and whether entities become
  real-time meshes at all is OPEN-06. The player jet is a flat-coloured airframe
  built from lofted stations, not a real model: it reads at prototype zoom, but it
  is not production geometry.
- **The airframe is bigger than its hitbox on purpose.** The collision capsule is
  a 1.0-radius circle on the play plane, while the jet is about 4.1 units long and
  3.9 wide. The nose and wings are therefore grazeable — the hitbox is the cockpit,
  which is the usual bullet-hell bargain. If grazing starts to feel like a lie,
  shrink the airframe before growing the hitbox.
- **The ship casts no shadow.** The directional light spans the whole planet, so a
  4-unit object's shadow lands as a dotted smear instead of a silhouette; every
  ship mesh sets `SHADOW_CASTING_SETTING_OFF`. A dedicated shadow would need its
  own light or a blob quad, and altitude is currently read from the camera framing
  and the plume instead.
- **No wave escalation.** A population of up to 3 turrets is streamed around the
  ship, so the planet stays inhabited and the difficulty stays flat (FR-10 is
  still a proposal, not implemented).
- **The planet no longer shows a limb.** At `PLANET_RADIUS = 400` the surface
  fills the frame, so the star field is effectively scenery and the "globe" read
  comes from rolling terrain, not from a visible edge.
- **i-frames and dash are prototypes of FR-09 and FR-11**, which remain
  unconfirmed product requirements — try them and decide, do not assume.
