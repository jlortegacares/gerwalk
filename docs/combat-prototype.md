# Gerwalk — Combat Feel Prototype

Scope: the smallest build that can answer "does the 360° control and the
segmented HP bar feel right?" before any content investment.

Related: [requirements.md](requirements.md) — pillars P1/P2, FR-01..FR-08, FR-15,
decision D-03.

## Run it

```sh
./run.sh
```

Opens `ui/menu/main_menu.tscn`, the boot menu: **START** loads the arena,
**OPTIONS** opens the fullscreen toggle, the livery picker and the controls
reference. Engine pinned to **Godot 4.7.2 stable, Forward+**.
`./run.sh --editor` opens the editor instead; `./run.sh --headless` runs without a
window and is what CI uses.

## Controls

| Action | Keyboard / mouse | Gamepad |
|--------|------------------|---------|
| Move | WASD | Left stick |
| Aim | Mouse position | Right stick |
| Fire | Left mouse button | Right stick deflection, or right shoulder |
| Missile salvo (hold) | Right mouse button / F | X |
| Select weapon | 1 / 2 / 3 | D-pad left / right (cycle) |
| Bomb | E | Y |
| Decoy | C | Right bumper |
| Afterburner (hold) | Shift | Right trigger |
| Dash | Double tap WASD, or Space | Double tap left stick, or left stick click |
| Transform | Q | Left bumper |
| Restart | R (on the death screen) | Start |
| Main menu | Escape (on the death screen) | B |

Aiming and firing are independent of movement by construction: `_move_gerwalk()`
never reads the aim vector and `_update_aim()` never reads the movement vector.
The right stick also fires, so a pad player never has to reach for the trigger.
That independence is a GERWALK property; FIGHTER deliberately gives it up, which
is what the next section is about.

The boot menu takes the same keys: `ui_accept` activates the focused button and
Escape closes the options panel.

## The arsenal

Primary fire is a choice, not a pickup economy: keys 1-3 select a weapon directly
and the D-pad cycles. Each archetype answers a different aim problem.

| Weapon | Shape of the shot | What it rewards |
|--------|-------------------|-----------------|
| Vulcan | Three pellets per shot in a 32° fan, every 0.085 s | Forgiving aim: the spread catches a turret drifting off the crosshair |
| Laser | Hit-scan beam, damage on a 0.05 s tick | Tracking: the beam only pays while it stays on the target |
| Plasma | Slow bolt that locks a turret inside a 30° cone and curves onto it | Lining up once: the shot corrects after it leaves the nose |

The laser stops at the first thing it meets, so the drawn beam is the truth about
what it can hit. Damage ticks on its own clock instead of the visual refresh, which
is what lets a continuous beam pay out in steady bites instead of one burst frame.

Plasma is semi-automatic in the literal sense: the lock needs the aim, the flight
does not. Guidance lives in the shared `Projectile` as an optional target and turn
rate, so a bolt that outlives its target simply flies straight, and the missiles
reuse the same mechanism rather than a second bullet class.

Missiles are a radar you fly, not a clock that fires. The rack only sees inside a
55° cone around the aim, out to 48 units, and it never launches on its own. Holding
the missile button loads one missile every 0.3 s, up to six, and letting go fires the
whole load at once: the hold decides how many, the radar decides who. Held time does
not need company to count, so a lone contact takes every missile; with more contacts
the load is spread round-robin from the nearest outwards, so three missiles over two
turrets land 2/1 and never 3/0. Each missile still chases its own target, leaves from
alternating wings and is angled 14° outward, so the guidance curve is visible from
the first frame.

The load only grows while the radar holds a contact, so a salvo cannot be pre-charged
in empty sky and dumped the instant a turret appears. A tap shorter than one interval
loads nothing at all and fires nothing: the hold is the weapon, not the press.

The cooldown is what makes the hold mean something. A salvo empties the rack into
0.45 s of downtime, so mashing cannot beat held time: without it, hold-release spam
would be a strictly faster way to fire and the radar would be decoration. Contacts are
re-read every frame, so a salvo only spreads over turrets the radar can see right now.

The missile is the one projectile with a silhouette of its own
(`Projectile.Style.MISSILE`): an off-white body, a tinted warhead cone and band, four
swept fins and a lit exhaust cone, built along `+Z` because `rotation.y` maps that
axis onto the flight vector. The style is a parameter of the weapon, not a guess from
guidance: a homing plasma bolt stays a dart, and enemy fire stays an orb unless the
weapon asks for a missile, which is the one silhouette that warns the shot is guided
and can be shaken off.

**A missile can be shot down.** Guided enemy shots are the one projectile the
player's fire can destroy: they sit on their own collision layer, so the vulcan,
plasma and the laser all answer a launch with gunfire while a bullet pattern stays
untouchable. The laser cuts a missile down on contact instead of ticking damage into
it, because a missile has no hull to chew through. The point is to give the warning
window a second ending — a good player kills the shot instead of spending the
burner on it — without turning a ring of orbs into a wall of props.

Each missile drops a puff of smoke every 0.017 s at its tail, and each puff is a node
in the scene rather than a child of the missile. That is the whole point of the
design: the smoke already in the air has to survive the impact that frees the shot.
A puff grows from 0.10 to 0.62, fades out over 0.85 s and frees itself, and it
inherits a fraction of the missile's speed so a guided turn leaves a curved trail
instead of a straight line. The interval is tight enough that consecutive puffs
overlap: a sparser one reads as a dotted line, not as smoke.

**The salvo braids.** A player missile does not track the line of sight dead
straight: it swings its aim direction off that line by `MISSILE_WEAVE_AMPLITUDE`
radians, at `MISSILE_WEAVE_RATE` radians per second, so it crabs sideways for half a
cycle and then swings back. That is the Macross picture — the smoke of a salvo
braiding in the air instead of six parallel lines — and it is why the turn rate went
up to 5.2: a turn rate is a turn radius, and a radius of 15 units cannot bend a path
more than once before the shot arrives. Each missile of a salvo gets its own phase
(`index * 2.1`), so a full rack draws three pairs of opposed curves rather than six
trails in lockstep.

The swing is applied to the desired heading, never to the per-frame turn step. A
step is already an angle: adding the swing to it turns the missile at a rate it never
asked for, and the shot spirals around its target without closing on it. The swing
also fades to zero inside `MISSILE_WEAVE_HIT_RANGE`, because a missile still weaving
at the hull misses the thing it was locked onto. Enemy missiles weave on the same
tuning, because a hostile shot that does not braid reads as a different weapon instead
of the same one aimed at you; what stays the enemy's is the warhead, the speed and
the paint.

**Missiles leave from the wings.** Each shot is born on the hardpoint of the wing it
is angling towards. The point is read from the wing bone's own span axis, so the
sweep carries it: a folded wing launches from where the wing actually is, not from a
fixed offset in the hull. The load fans out in pairs — 11, -11, 22, -22, up to 33
degrees — so every missile of a full rack has a heading of its own instead of three
shots fired twice. The angle also picks the wing: the shot leaves from the pylon it
is angling towards, so the picture and the trajectory agree. A hand's width of
clearance keeps the shot from spawning inside the pylon.

Every contact is visible. While the button is down, each turret the radar holds
carries a mark (`combat/lock_reticle.gd`): flat on the play plane and above the
body, because that is what an angled camera reads as a box around the unit instead
of a line through it. The shape is the anime lock, not a ring — four corner brackets
pointing inwards and a diamond pip on the centre. A bracket box says "this one,
here" while leaving the target itself visible, which a closed circle does not.

The mark is a lock, not a decal. It arrives 1.9× wide and fades in while it snaps
down onto the contact in 0.22 s, and the snap is an ease-out-back: the box passes its
resting size, squeezes, and only then settles. That overshoot is what reads as a lock
instead of a zoom, and it is why the test drives `_process` frame by frame — a single
sample after the fact would miss the squeeze. Once settled it breathes on its
emission instead of spinning: the box is not rotationally symmetric, but rotating it
with the turret would tilt a marker that has to stay level with the play plane. The
reticle is parented to the turret, so it dies with its target and follows it while it
moves, and the HUD counts the loaded missiles while the button is down. A mechanic
whose payoff depends on how long you held a button cannot be invisible, and a salvo
that spreads has to show what it will spread over.

The bomb is the emergency button. One charge detonates a 40-unit ring that cancels
enemy fire inside it and pays 8 damage to every turret in range, in the same frame.
The rack holds 5 and starts at 3; every 12 kills refunds one charge, and a full rack
stops banking progress it cannot spend. The ring is presentation only: the damage
and the cancel already happened when it spawned.

**The decoy answers guided fire, and only guided fire.** A flare dropped with C stays
where the ship was, and every enemy missile within 30 units of it takes it as its
target on the next steering step. It burns for 3 s; when it goes out the missile is
left with nothing and keeps its heading, so the drop buys the distance the ship put
between itself and where the shot was going. It is a 4 s cooldown rather than a
resource, because a countermeasure you can spam is a dodge, and the HUD says
`DECOY READY` or `DECOY CHARGING` instead of a count. Unguided fire ignores it: an orb
was never chasing anything. The check runs on the missile every frame rather than once
on the drop, so a salvo that arrives after the flare still takes it — which is what
lets the countermeasure be a read about timing instead of a reflex about the button.

None of this touches the ship's velocity. Firing never costs translation speed, and
`tests/smoke_test.tscn` asserts it by holding fire and comparing top speed.

## 3D presentation and the camera

The arena is a `Node3D` scene: the planet's surface is the play field, the ship
flies over it, and the camera is a `Camera3D`. **Gameplay stays on the `y = 0`
plane.** Hitboxes are planar, so a bullet that looks like it passes within a
pixel of the player does pass within a pixel. The third dimension is
presentation, not a second axis of evasion.

Three constraints shaped the camera and the geometry, and each is load-bearing:

1. **The player sits at the centre of the frame.** `CameraRig` is a `Node3D`
   parented to the player, and the `Camera3D` is its child. The rig translates
   with the player and trails it by `velocity * LAG_SECONDS` (see
   [Maneuverability](#maneuverability-snappy-not-floaty)), so the ship leads the
   frame by a handful of pixels under thrust and settles back to the exact centre
   at rest (measured at 0.05 px in the smoke test). Shake uses `h_offset` /
   `v_offset`, which move the image without moving the camera target.
2. **The camera is world-aligned and never rotates.** It keeps straight bullets
   straight on screen. Rotating it with the ship's heading would make every
   bullet appear to curve and P1's readability would collapse.
3. **The camera pitch is a compromise between depth and framing.** The rig sits
   at `(0, 50, 13.4)` with a `-75°` pitch and a `58°` field of view. That reads
   as a top-down shooter while still giving the surface a horizon and enough of a
   side-on view that the ship shows its wings and tail instead of reading as a
   flat silhouette.

### The planet rolls under the ship

The ground is a sphere of `PLANET_RADIUS = 1600` whose centre tracks the ship's
planar position, so the ship is always at the sphere's pole. At this size the
limb sits outside the frame: the surface fills the screen and reads as a
continuous terrain rather than a globe. Tessellation tracks the radius, because
the facets are chords: the surface sits below the true sphere by roughly
`(vertex spacing)^2 / (8 * radius)` at each triangle's centre, so the old 96
segments that cost 0.21 units of sag at 400 would cost 0.86 at 1600 and the
terrain would visibly rise and fall under the ship as facets rolled past.
`PLANET_SEGMENTS` and `PLANET_RINGS` doubled to 192/96 to hold the sag at the old
0.21 units. **The planet is the travel mechanism, not
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
  (≈ 10053 units, about 6.3 minutes at GERWALK cruise and 3.5 at FIGHTER cruise)
  brings the original terrain back under the ship: the planet is finite and
  circumnavigable, and "cover the whole planet" is a lap, not a wall.
- **The geometry never moves in world space.** A sphere is rotation-invariant, so
  rotating it changes no vertex, no normal and no silhouette — only the shader's
  object-space input. That is why the roll is cheap and why it cannot desync from
  the collision plane.
- **The roll is applied after the player moves.** `Arena.process_physics_priority
  = 100` makes the arena step last; otherwise the terrain would lag one frame
  behind the ship and shimmer.

`PLANET_RADIUS` is the one number that sets the scale of the fantasy. A larger
radius means a longer lap and a flatter horizon; a smaller one means a curvier
surface with the limb closer to the ship. At 1600 a lap is ≈ 10053 units, which
is the "there is a lot of planet to cross" the design wants, and the curvature is
flat enough that the local surface never betrays the sphere. The
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

### Islands: a sea level, not a texture

The land field is three octaves with three different jobs. A continental term at
~1800 units decides where there is open ocean at all, an island term at ~48 units
carves the landmasses the ship actually crosses, and a coast octave at ~12 units
keeps the shoreline ragged instead of a smooth blob. Each octave is recentred and
stretched before it is composed: value noise averages 0.5 and `fbm3` sums to a
mean of 0.4375, so a field used raw sits on the sea level and every island becomes
one soft smudge with no shoreline at all.

Everything below `0.50` is water: deep, dark and glossy (`ROUGHNESS = 0.18`) so it
picks up the sun, with a shallow shelf around every coast. Everything above rises
through a narrow sand ring into vegetation and high ground, and a thin foam line
marks the waterline — a beach is a couple of pixels wide from 50 units up, so the
foam is what actually draws the coastline. Water is painted only: no collision, no
nodes, the play plane is untouched.

### Cities: districts painted into the surface

The ship flies 1.5 units above the ground with a planar hitbox, so a real building
tall enough to read as a building would have to cross the play plane and block
bullets. Cities are therefore painted: an opaque asphalt square with a street
grid and scattered amber-lit blocks, lit from `EMISSION` so they read from above.

Two details make it work.

- **Where a city goes is decided on a cube-sphere chart.** A per-point tangent
  frame has two poles where it degenerates, and the rolling planet carries the
  ship over them constantly. Six cube faces have no singularity: one candidate
  district per 26-unit cell, chosen by hashing the cell.
- **How a city is drawn uses a tangent plane per district.** The chart is not
  conformal, so a grid drawn straight in it bends across a district. Each district
  therefore recovers its own centre from its chart cell and builds a tangent frame
  there, which keeps every street straight and every block square.

The window scale is the other trap: windows 0.3 units wide are four pixels from
this camera and alias into white noise the moment the surface tilts. A lit *roof*
— a 1.05-unit block — is what reads as a city from 50 units up.

## Maneuverability: snappy, not floaty

A twin-stick ship has to answer like a bullet-hell character and read like a jet.
Those pull in opposite directions: weight sells a fighter but steals the frames
the player needs, and the genre forgives neither. The split this build uses is
**arcade response, aviation presentation**.

| Axis | Behaviour | Constant |
|------|-----------|----------|
| Thrust | rest to cruise in 0.067 s (four ticks) | `ACCELERATION = 420` |
| Braking | cruise to stop in 0.050 s (three ticks) | `FRICTION = 540` |
| Fine control | a 20% tilt settles at 3.0 u/s, about a ninth of cruise | `MOVE_DEADZONE = 0.10` |
| Shot direction | instant: the stick angle of this frame | `_aim_direction` |
| Hull direction | 1800 deg/s, so a 180 flip lands in six frames | `VISUAL_TURN_RATE = 1800` |
| Bank | up to 32 deg in GERWALK from lateral drift plus turn rate; a fighter rolls 50 deg into a full-rate turn | `MAX_BANK`, `YAW_BANK`, `FIGHTER_BANK`, `BANK_RATE` |
| Dash | 3.17x cruise, flat for 0.12 s, inertia dropped on frame one, enemy fire evaded for the whole burst | `DASH_SPEED`, `DASH_DURATION` |
| Dash trigger | double tap the movement stick the way you want to go, any direction; Space / L3 click still works | `DOUBLE_TAP_WINDOW = 0.28`, `DOUBLE_TAP_SIMILARITY = 0.5` |
| Camera lead | `velocity * 0.02`, about 8 px at cruise and 12 under the burner, saturating at 0.6 units | `LAG_SECONDS`, `LAG_RATE`, `LAG_MAX` |

**Acceleration is quantised, so it has to fit in whole frames.** At 60 physics
ticks, 0.05 s is three ticks and 0.08 s is five. 420 u/s² reaches 26.8 u/s in
3.8 ticks, which the player feels as "it moved when I moved". A tenth of a second
of progressive acceleration is invisible in a racing game and fatal in danmaku,
where the pattern is already on screen when you commit.

**Braking is heavier than thrust.** 540 against 420 means the ship stops faster
than it starts. Zero-g coasting is the classic mistake here: it looks cinematic
and turns threading a narrow gap into a guess, because releasing the stick no
longer means stopping.

**The deadzone is low on purpose.** `Input.get_vector` applies a circular
deadzone and rescales the remainder, so 0.10 is the smallest tilt that registers
and a 20% tilt lands near 11% of cruise. That is the tap mode: enough to slide
between two bullets that leave a gap, not enough to overshoot it.

**Aim is instant, the hull is not.** The spec allowed a hard lock (A) or a
smoothed turn of at least 1440–1800 deg/s (B). This build takes A for the shot
and B for the model, which gets both halves: the bullet leaves along the stick on
the same frame, so no trade is lost to input lag, while the airframe takes up to
six frames on a 180 and reads as a snap roll instead of a teleport. Nothing
gameplay-facing reads `_visual.rotation`.

**Bank is presentation only.** Collision stays the flat capsule on `y = 0`; the
roll lives on `_visual.rotation.x` and cannot change what the ship can graze.
GERWALK derives it from the body — lateral drift relative to the nose, plus a
smaller lean into fast aim turns — so it also appears when a dash or a drift
moves the ship sideways. FIGHTER derives it from the turn rate alone, and the rate
is normalised against the rate that mode can turn at: a fighter noses round at
400 deg/s while the aiming ring snaps at 1800, so normalising both against the
ring would leave the fighter banking a quarter of what the turn asks for. A
full-rate turn rolls `FIGHTER_BANK` (50 deg) into the inside of the arc, so the
wing drops on the side the nose is going. Reading the drift term there as well
would have been worse than ignoring it, because in that mode the drift is the
skid — the course trailing the nose — so the two terms would bank twice for one
turn. Both rules settle back to level in about a fifth of a second.

**The dash is an injection, not an acceleration.** The dash branch overwrites
`velocity` with `_dash_direction * DASH_SPEED` for 0.12 s, so the old inertia is
gone on the first frame and the speed profile is flat. The direction is the stick
when it is deflected past the movement deadzone and the nose when it is not, which
means "dash where I am going" and "dash where I am looking" never need a modifier.

**The dash evades fire; it does not delete it.** The window is invulnerable, and
that used to be invisible: a bullet that touched the hull mid-dash dealt no damage
but was still spent, so the dash read as a screen clear that quietly removed the
shots it touched. Now `Player.is_evading()` reports the window and `Projectile`
returns early on a dashing hull — no damage, no impact, and the shot keeps flying,
so it can still catch the ship once the window closes. The evasion is the dash's
own 0.12 s (0.20 s for the fighter's roll) rather than a separate timer: the ship
that phases through a bullet is the ship that is moving through it, and a longer
window would make the dash a defensive cooldown instead of a jink.

**The dash is a double tap, and the second tap is the direction.** A tap is the
movement vector leaving the deadzone, so the gesture is two rising edges inside
`DOUBLE_TAP_WINDOW` (0.28 s) whose directions agree inside a 60 degree cone
(`DOUBLE_TAP_SIMILARITY = 0.5`). Reading the polled vector instead of
`just_pressed` is what keeps it analog: on a stick a tap is a short deflection,
not a click, and the gesture is the same on keyboard, pad and any remap. Two taps
that disagree are a direction change and spend nothing, which is what keeps a
quick left-then-up flick a turn instead of an accidental dash. Space and L3 stay
as the alternative for a player who would rather press once.

In FIGHTER the jink follows the tap on both axes, so up, down and the diagonals
are all valid: the stick is read in the same world axes the flight model uses, so
a tap up is a step forward when the nose is up-screen and a step to the side when
it is not, and the diagonals are simply a direction. The push is composed from
the airframe's own axes, so it still turns with the nose during the 0.20 s, and
`_roll_velocity` is subtracted before airspeed is measured, which is what keeps a
forward jink a seven-unit step instead of a free speed boost.

**Thrust cues fire on change, not on speed.** Plumes follow the forward component
of velocity at a steady state. The burst is a separate term (`_thrust_kick`) set
by acceleration and by the dash and decaying in about a third of a second, so a
constant cruise gives a subtle trail and launching from rest or punching the dash
gives a flash without touching handling.

## Two modes: GERWALK and FIGHTER

Q, or LB on a pad, transforms the ship in place. The two modes are different
games rather than two gears of the same one.

| | GERWALK | FIGHTER |
|---|---|---|
| Translation | 360°, instant, independent of the nose | the nose leads and the course follows, lagging into a skid |
| Top speed | 26.8 | 48.2 airspeed, the 180% of the hover the spec asks for |
| Acceleration | 0.067 s to cruise | 0.054 s to cruise |
| Stop | 0.050 s on the brake | never: drag falls to a 19.3 u/s glide in 0.35 s |
| Wind | none: the hover holds station | a constant 7 u/s world vector |
| Aim | mouse or right stick, instantly | the nose, and only the nose |
| Hull turn | 1800 °/s, presentation only | 400 °/s, and it is the turn rate the game reads |
| Dash | 3.17x burst, 0.12 s, i-frames and enemy fire evaded, on a double tap of the direction | barrel roll, 55 u/s in the tapped direction over 0.20 s with a 0.45 s turn-over, heading kept; the button still repeats the last side |
| Afterburner | 42 u/s | 60 u/s |
| Gun | free aim, 16° vulcan fan, base range | 0°, 4° fan, 1.35x muzzle speed, 1.4x range, no plasma lock |

### The GERWALK airframe

The rules above are the mode; the legs are how it reads. The airframe is the
imported VF-1S (`models/vf-1s/source/Vf-01_BRoid_ULa.glb`), and it already carries
the whole transformation as a clip, so `PlayerModel` samples that clip instead of
posing a stance by hand.

Four decisions keep that pose honest:

- **The bind pose is not the fighter.** The file exports in a neutral pose: the
  fast pack sits flipped onto its back, the rudders folded, the gear doors open.
  Rendered raw, those pieces read as blades floating off the tail, right where the
  fighter should be smooth. Frame zero of the shipped clip
  (`__ActionLegGERWALKgunner`) is the assembled fighter, so it is the base every
  other pose is built on.
- **The stance is the asset's, not a guess.** The clip is named for what it does:
  `__ActionLegGERWALKgunner` plants the legs first, then brings the arms out into
  the gunner stance, and holds both from 8.5 to 10 seconds before it carries on
  into Battroid. The build samples nine seconds, so the legs hang under the hull
  *and* the hands are in front, and `_mode_blend` slerps the two frames bone by
  bone. Angles measured off screenshots put the legs out to the sides; the
  authored hold is the only pose that also gives the gunpod a hand to ride.
- **Only the pieces that ride the transformation take the clip.** Frame zero is
  also the *parked* fighter: gear down, canopy open, wings half folded. The parts
  the clip places (fast pack, rudders, tail hook, gear doors) keep its value;
  everything the mode pose owns goes back to bind, and the canopy and gear bones
  are frozen in both frames so a switch never opens an empty cockpit or cycles
  gear nobody can see.
- **GERWALK lifts the whole airframe.** The model's nacelles reach further below
  the hull than the placeholder's legs did, so `GERWALK_LIFT = 0.55` raises it
  while the nozzles keep their clearance above `GROUND_Y = -1.5`.

The gunpod is the one piece still built in code, because the model carries a gun
bone but no pod mesh. It is a child of the visual, lerped between a stowed
centreline position under the belly and the right hand, which the gunner hold puts
in front of the wing root and to the right: the pod's origin is its grip, so
reading the wrist keeps the receiver ahead of the fist and the stock behind it
through the whole switch.

The model ships with its landing gear deployed and an F-35 cockpit crew inside;
both are hidden by node name at build time, because the airframe is only ever seen
in flight. The canopy is repainted in the same pass: the file's glass is a grey
shell stacked over a teal sheet, which at the few dozen pixels the ship gets reads
as part of the hull, so both panels take a celeste tint and the cockpit becomes
the one piece of the airframe the eye lands on. That tint is now a livery colour
(see below). It also casts no shadow: the hull is a few dozen pixels across and
the directional light covers the whole arena, so its shadowmap resolves as a
dotted arc trailing the ship, which reads as debris at gameplay distance.

One sun and a mirrored airframe is the other half of that story, and it is why the
two legs disagreed. The ship is a mirror, so the two legs present opposite facets
to a light that comes from one side: one spine caught the sun and read warm grey,
its twin turned away and crushed to black, which at gameplay distance looks like
one leg wearing a shadow. No sun angle fixes it — moving the key light only makes
the other leg the dark one. The airframe therefore carries a shadowless fill on the
camera rig: the game camera is fixed behind and above the ship, so a light along
its axis lands on exactly the facets the player can see, equally, whichever leg
they belong to. It culls on the airframe's own render layer, so the planet, the
stars and the enemies keep the single-sun look they were tuned with, and it is
cooler than the sun because it stands in for sky bounce rather than a second key.

### The livery

The ship the player flies is the ship the options panel shows. The livery lives in
three of the file's material families — `Aircraft BASE color*` is the hull,
`Pilot COLOR*` is the stripe that runs across it, and `Pilot TRIM*` is the dark
trim that cuts both into panels — plus the canopy panels, which are found by the
bones they hang from rather than by material, and the nose, which is found by the
name of the mesh the exporter merged it into. Everything else — nozzles, gear,
markings — keeps the paint the file shipped, because repainting those would
flatten the airframe into one colour and lose the detail that makes it read as an
aircraft.

The canopy is its own pass for a concrete reason: the cover panel ships wearing a
hull material (`Aircraft BASE color.004`), so a family match would paint the
cockpit with the hull colour. `_paint_canopy()` walks the canopy bones, takes the
glass sheet and the cover, and leaves the rib alone — the rib is the frame, and
the frame belongs to the lines.

The nose is not a mesh of its own. The exporter merged the cone, the panel lines
across it, the nose gear and the cockpit housing into the forward fuselage mesh
(`__VF_1S-AIRFRAME_018`), and the cone also shares one hull sheet with the section
under the cockpit. `NOSE_MESH` matches that mesh by name, and `_split_nose_cone()`
cuts the sheet at the canopy's leading edge before the paint runs: the half in
front of the cockpit is renamed to `NOSE_MATERIAL` and takes the nose colour, the
half behind keeps the hull family and takes the hull colour. The lines that cross
the nose still take the line colour, and the gear and housing keep their own
families.

The cut is measured, not assumed — the canopy panels are projected into the mesh's
own space and their forward-most vertex is the plane — so a re-export moves the
boundary with the cockpit. `NOSE_GAP` then pushes the paint a little ahead of that
edge, which leaves a strip of hull in front of the cockpit instead of butting the
nose colour straight against the canopy. Both sit on the fighter frame when the
paint runs, and the canopy is frozen there, so the same plane holds in GERWALK.

Two details make that safe:

- **The split is a rebuild, not a second mesh.** The file's vertices are not
  welded, so connectivity cannot tell the cone from the fuselage under it, and a
  second `MeshInstance3D` over the same triangles would z-fight. Each triangle goes
  whole to the side its centroid falls on, so nothing is dropped or duplicated and
  the silhouette does not change.
- **The paint is duplicated per surface.** The GLB is one shared resource, so
  writing into its materials would repaint every later ship and the preview along
  with it. `_paint_livery()` clones the families and installs them as surface
  overrides, which also means a colour change is a write to the clones instead of a
  rebuild of the model — that is what the preview does on every click.
- **The options panel is a palette, not a colour wheel.** Nine swatches, offered
  five times: one row each for the hull, the nose, the stripe, the canopy and the
  lines. The first four are the factory colours, so coming back to the shipped
  livery is a swatch and not a hidden reset; the nose ships in the hull's own
  white, so the same swatch is its factory colour too. A `ButtonGroup` makes each
  row one exclusive choice, and the group refuses to unpress, so the ship always
  has all five.

The preview is not a picture: `LiveryPreview` builds the same `PlayerModel` the
game builds and paints it through the same `set_livery()`, so it cannot drift from
the ship. It is built the first time the panel opens, because the menu starts with
the panel hidden and the airframe is the most expensive thing in the menu. The
choice lives in `user://settings.cfg` next to the display setting, and the arena
reads it once when the player is built.

The pose is driven by `_mode_blend`. The blend follows the mode the switch is
*committing to*, so the shape finishes changing exactly when the flight rules flip
rather than one switch later.

**The stick asks for a heading, it does not translate.** This is the whole mode
in one sentence. The stick angle names the bearing the ship should be flying,
the hull takes the short arc to it at a capped rate, and thrust follows the nose.
The alternative reading — the stick commands a yaw rate — cannot explain the
spec's braking rule: in a rate model, releasing the stick would leave nothing to
decelerate against. Only a heading request makes the stick the throttle: hold it
and the ship flies, release it and it falls to its glide.

**The turn cap is the mode, not a limiter on it.** 400 °/s sits in the requested
360–450 band and turns a 180 into 0.45 s, so a reversal is a decision you make
before you need it. Pushing the stick the other way does not flip the nose: the
ship banks through the arc and arrives pointing backwards. Anyone who wants to
snap around on the spot has the hover, one button away.

**Two rules, one model: the air, not the ground.** Everything in the table
above is *airspeed*, which is the ground velocity minus the jink. Airspeed is
tracked as a course plus a magnitude, and that split is the whole model.

- **Stall speed.** Releasing the stick does not stop the ship. The coasting target
  and the throttle's own floor are the same number,
  `FIGHTER_STALL_SPEED = 0.4 * FIGHTER_SPEED` (19.3 u/s), so no input and the
  lightest touch of the stick give the same speed and there is no seam between
  them. `FIGHTER_DRAG` is derived rather than tuned beside the spec number: the
  airspeed falls from cruise to that floor in the same 0.35 s the old full stop
  took, so the fade feels identical and only its destination moved. From the
  burner the same drag takes 0.44 s.
- **Grip, or the skid.** The nose turns at 400 °/s, but the course only follows at
  `FIGHTER_GRIP / airspeed` — about 226 °/s at cruise, and faster than the nose at
  stall speed. The lag between the two is the skid: a full reversal opens about
  78° of drift and takes a couple of tenths to settle, and the drift shrinks as
  the ship slows, which is what a wing does. It is deliberately *not* two
  independent axes with their own targets: that model manufactures airspeed out
  of a turn, and a twelve-frame test of it reached 390 u/s sideways.
- **No wind.** The model is deliberately free of a world-space breeze. A constant
  wind of `(7, 0, 0)` u/s made the same run 15% faster downwind than upwind, and
  because the wing sweep and the plumes read the speed along the nose, the wings
  swept on one heading at cruise and stayed straight on the other three. That is a
  bug the eye finds immediately, so every heading now flies the same speed.
  GERWALK never answered to it either: the hover holds station, and that is its
  reason to exist next to the fighter.

**The barrel roll is outside the model.** `_roll_velocity` is subtracted before the
air is read, so the jink is a scripted 55 u/s step and never airspeed. Without
that subtraction the roll is additive: a measured 393 u/s sideways against an
intended 55, and the step grows from 7 units to 46 until the grip can shed it.

**The roll and the jink run on separate clocks.** 0.20 s is the rule: the 55 u/s
step and the i-frames it buys. The airframe's turn-over is presentation, and at
0.20 s it was twelve frames of blur that read as a teleport;
`FIGHTER_ROLL_ANIM_TIME` takes the same 360 degrees over 0.45 s, so the wings come
over where they can be seen while the distance covered and the protection window
stay exactly as they were. The side is remembered too: a centred stick repeats the
last roll instead of defaulting right, and the spin follows that side, so a left
dodge rolls left and the animation agrees with the step. A jink with no side of its
own — straight ahead, or straight back — keeps the side it last rolled to, because
the step has a direction but the spin still has to pick one.

**The switch costs 0.28 s and buys nothing.** Weapons are locked, the ship takes
no thrust, and it grants no invulnerability. A free dodge on the same button that
changes the whole airframe would make the dash and the bomb optional. Momentum is
preserved, and on entry the heading snaps to the direction the ship is already
travelling, so transforming never teleports the velocity onto a new axis.

**The gun points at the nose in FIGHTER, and the 0° rule is about the gun.** The
right stick stops aiming, so every primary fires down the longitudinal axis with
1.4x range and a 1.35x muzzle speed. Plasma loses the lock-on that gives it its
identity in the hover. Missiles and the bomb are untouched: they are
fire-and-forget systems of their own, not the main gun, and the spec's constraint
is about where the gun points. The right stick keeps two small jobs instead of an
aim: it bends the requested bearing by up to 8° and nudges the course at 60 °/s
while coasting, and the dash becomes a barrel roll that steps the ship in the
tapped direction without turning the nose.

**The burner is speed, not a shield.** It used to carry a frontal cone that
destroyed enemy fire — 7 units, ±30° off the nose — and the cone outlived its own
mesh: after the wedge was removed as a stray triangle, the rule kept deleting
projectiles the player could not see a reason for. It is gone now. The burner's
tell is the wingtip vapour, and what keeps the ship alive in FIGHTER is the
airframe — 48.2 u/s, a 400 °/s nose and a barrel roll with i-frames — not a
hitbox nobody can read.

**The tips leave a vapour trail from the middle of the throttle up.** Each wingtip
draws a ribbon: a triangle strip rebuilt every frame through the positions the tip
has visited, so the line is continuous by construction. A particle wake could only
ever be as dense as the rate it spawns at, and at 60 u/s that leaves visible gaps,
which is why the tips read as a dotted trail instead. The strip is built in world
space from the posed wing bone, so a swept wing trails from where the tip actually
is and a turn bends the line rather than snapping it. The head is bright and the
tail fades, and it is additive unlike the grey wake: the tips are read against the
sky, and a bright line is what makes the speed legible from the game camera.

The emission point is the outer edge of the wing, measured off the mesh and carried
in each wing bone's own frame. The wingtip is a chord rather than a point, and
which corner of it is outermost depends on the sweep: measured at rest the leading
corner sticks out furthest, and a point calibrated there floats outside the
silhouette once the wing folds back. So the measurement is taken at cruise — the
pose the vapour actually lives in — where the outer edge is the trailing corner.
Keeping the point in the bone frame is what makes it ride the sweep, and the values
are per side because the rig's wings are not the same length.

The vapour answers airspeed in FIGHTER, not the burner. It fades in from 55% of
cruise and is at full strength by cruise, so the tips are already trailing at
medium throttle and the afterburner is simply the top of that range — which is
also where the burst rule applies. It reads the speed through the air rather than
the component along the nose: in a turn the nose outruns the course, and the
forward projection collapses while the wing is still moving at cruise, which used
to make the vapour die exactly when the airframe was loaded.

GERWALK has no wingtip vapour at all. That mode is a hover, not a wing: it flies
sideways and backwards as happily as forwards, so a trail there says nothing about
the throttle and nothing about the airframe. The strips are wiped on the frame the
ship stops being a fighter — including mid-transition, while the wings are
folding — so a line laid down in FIGHTER does not hang in the air through the
switch. The trail outlives the grey exhaust on purpose: the two lines have to
survive past the nozzle rope, or they end inside it and there is nothing to see.

**The exhaust answers a change in speed, not the speed.** Each nozzle carries a GPU
emitter that drops soft puffs and leaves them where they were born, so the gap
between consecutive puffs — and with it the length of the wake — is whatever
distance the ship covered while they lived. Density is the only knob that needs
turning, and `amount_ratio` changes it without restarting the emission. This is
deliberately a different mechanism from the missile trail: a missile needs puffs
that outlive the shot and curve with it, which means nodes in the scene, while the
ship needs a continuous ribbon at a cadence no node budget would enjoy. In GERWALK
the two emitters sit on the feet, so the wake reads as a twin trail converging
behind the stance.

The density is fed by the measured acceleration, not by the airspeed: a steady
throttle leaves the nozzles clean, and the puffs only appear while the ship is
climbing. The burst then outlives the acceleration by the puffs' own lifetime and
clears itself, so what the player sees is a short smear behind the hull each time
the speed goes up. That also fixes a bug the eye finds before the profiler does:
the puffs are born at the nozzle and stay there until the ship outruns them, so a
ship standing on its legs wore its own plume, and from the game camera a grey veil
over a white leg reads as a shadow the other leg does not have.

**The camera lead saturates.** FR-15 promises the ship never leads the frame by
more than 16 px. At 180% speed and then 60 u/s the proportional lead would reach
0.96 and 1.2 world units, which is over 20 px on this camera, so `LAG_MAX` caps
the lead at 0.6 units instead of letting it scale with speed. The ship stays
framed at fighter cruise; the camera reads the speed through the FOV kick and the
terrain, not through the ship sliding off centre.

## The interceptor

The third contact is a mirror. It flies the player's own airframe and the player's
own nose-first flight model — a heading requested by the nose, a capped turn, an
airspeed with a floor — and it never transforms: the wings stay folded, the gun
stays bolted to the airframe, and the missile rack is the only weapon. The paint is
what keeps friend and foe apart, since the silhouette is deliberately the same one.

The ceiling is the brief's **medium speed**, 34 u/s, between the hover's cruise
(26.8) and the burner (42). That single number is the whole encounter: GERWALK
cannot outrun it, so running in the hover only prolongs the pass, while FIGHTER
(48.2) and the afterburner both leave it behind. The chase is a decision about the
mode, not about holding a direction. The floor is 15, so a disengaged patrol keeps
flying instead of hovering in place like a turret, and the wings sweep on the same
curve the player's fighter uses, measured against this ship's own ceiling.

The turn is capped at 120 deg/s against the player's 400. That is on purpose: the
pass has to be readable and dodgeable, and a mirror of the player's turn rate would
turn every merge into a coin flip. It commits inside 46 units and roughly on the
nose, hangs a 5.5-unit aim beam off the nose for 0.72 s, then fires a pair of
guided missiles from the wing hardpoints. After the launch it extends for 2.1 s
before it comes back, which is the window to punish the pass.

The salvo is the launcher's, one step faster: 36 u/s against the launcher's 33, so
it still closes on a hovering ship but stays under the burner. Both the decoy and
shooting it down work exactly as they do against the launcher, because it is the
same `Projectile` with the same enemy-missile layer.

Its flight profile is the player's, not the launcher's: the pair holds its heading
for `MISSILE_GUIDANCE_DELAY` so the two lines separate, then weaves on
`MISSILE_WEAVE_*` with one phase per shot, and its turn rate is the player's 5.2
rather than the launcher's 1.6, because the weave cannot bend a path on a 21-unit
radius. Only the warhead, the speed and the paint stay the enemy's.

It inherits from `Enemy` for the identity rather than for the movement. Being an
`Enemy` in the `enemy` group is what makes it a first-class target: the arena
counts and despawns it, the radar paints it, the bomb damages it and the player's
own missiles lock it. The turret's roam/orbit state machine, its hull and its
bullet patterns are all replaced; what survives from the base is the hit flash,
the damage bookkeeping and the `killed` signal.

## Death and the next run

Death is a five-second question, not a game over: **SIGNAL LOST** takes the
screen, the panel counts `RESPAWN IN 5` down to zero, and the run restarts by
itself when it gets there. **CONTINUE** gives that answer early and **MAIN MENU**
leaves for the boot scene; `R` / Start and Escape / B are the same two answers on
the keyboard and the pad.

The countdown is the default answer because the alternative — a panel that waits
for a button nobody presses — turns a death into a pause, and a prototype is
played in short bursts where waiting is the worst outcome. The world keeps
running behind the panel for the same reason: the fight is already lost, so
freezing it would only make the restart slower. `GameOver` raises
`respawn_requested` or `menu_requested` and nothing else; the HUD owns the scene
change, which is what lets a test press both answers without reloading the scene
it runs in.

The hull does not just vanish. `common/ship_explosion.gd` builds a `ShipExplosion`
where the ship died and frees it when it is done: an additive white core that peaks
in 0.18 s, three staggered fireball blobs, seven tumbling shards, additive sparks
that arc and fall, and dark smoke that outlives both. The layers are staggered on
purpose — one expanding sphere reads as a hit, not as a ship coming apart. The
effect is a world node rather than a child of the ship, so it stays where the wreck
was while the hidden model waits for the respawn, and it asks for a full-strength
camera kick on top of the one the killing hit already sent.

Enemies die the same way, because the blast is the game's word for "a hull came
apart" and a kill should not be a different event from a death. The turret, the
launcher and the interceptor all run the one `Enemy._die`: the hull and the aim
beam are hidden on the death frame, the same `ShipExplosion` opens where the enemy
was, the kill reaches the event bus with the hull's score value, and the enemy frees
itself. Only
the camera kick is scaled (`Enemy.DEATH_SHAKE`, 0.35): the explosion is identical,
but a kill is not the run ending.

The panel fades in over `FADE_IN` (0.5 s) instead of cutting to its backdrop on the
same frame. Its tint is dark enough to swallow the blast, and the countdown is
unaffected: it starts when the death event fires, exactly as before.

## Score

Every kill pays what the hull was worth: a turret 100, an interceptor 200 and the
launcher 250. The three are different fights rather than the same fight at different
speeds — the launcher is the toughest hull and the one that forces a decision, the
interceptor dies to one burst but the burst has to land on a moving target, and the
turret is the baseline the other two are priced against.

`Enemy._die` publishes the kill as `GlobalEventBus.enemy_killed(value)`, so the value
travels with the event and the total does not depend on which spawn path produced the
enemy. The arena owns the total: it adds the value and republishes
`score_changed(total)`, and the HUD prints it zero-padded in the top-right corner.
The arena is the run, so a respawn reloads the scene and the score starts again at
zero — a death ends the run's score the same way it ends the run. There is no high
score yet; it would need somewhere to persist, and the prototype has no save file.

## Audio

The game has a voice, and it is ours. Every sound in `audio/sfx/` is synthesized by
`tools/generate_sfx.gd`; nothing is sampled, ripped or downloaded from the anime.
"Inspired by Macross" is a character brief, not a source: the ship hums like a
turbine, the gunpod is a hard dry burst, a missile leaves the rail with an airy
whoosh, the lock answers with a rising two-pip sting, the transformation is servos
and a clunk, and an incoming guided shot is a two-tone alarm that must never be
mistaken for the player's own weapons. Re-running the generator reproduces every
WAV byte for byte, because its noise source is a seeded LCG instead of `randf()`.
Each sound seeds that LCG from its own name, so editing one builder never rewrites
the noise of the effects listed after it.

The palette is one place, `common/sfx.gd`, autoloaded as `Sfx`. Callers name a
sound and never touch a player node:

| Call | Used for | Why |
|------|----------|-----|
| `Sfx.play(key)` | the ship's own weapons, the lock tone, the interface | the camera is on the source, so distance and panning would only add noise |
| `Sfx.play_at(key, position)` | explosions, enemy fire, launches, the bomb, the decoy | the world is around the ship, and a turret on the nose should not sound like one behind it |
| `Sfx.engine(active, ratio)` | the hover hum | one continuous voice whose pitch and level follow the airspeed |

The non-positional side is a fixed pool of `VOICES` (16) players that steals the
oldest voice; a held trigger therefore cannot grow the scene. The positional side
creates an `AudioStreamPlayer3D` per event and frees it when the stream finishes,
capped at `MAX_SPATIAL` (24); past the cap it falls back to the flat pool rather
than dropping the sound. Everything routes through a `SFX` bus under `Master`, and
`Master` carries an `AudioEffectHardLimiter` so a full salvo plus an explosion sums
without clipping. Bus and limiter are built in `_ready` instead of a `.tres`: one
fewer asset to drift out of sync with the code that names the bus.

Cue discipline is part of the design, because the cheap version of every one of
these is a machine gun of noise:

- **One burst per vulcan shot**, not one per pellet. Five pellets are one gun.
- **One ignition per trigger pull for the beam.** The laser is a continuous stream,
  so `_laser_sounding` latches on the pull and clears on release; a zap per frame
  would be a wall of hiss.
- **One launch sound per missile**, with the pitch climbing `index * 0.04`, so a
  salvo reads as a sequence of whooshes instead of one long noise.
- **One lock tone per acquisition frame**, not per contact: three turrets entering
  the radar at once are one acquisition.
- **One warning per enemy salvo**, fired at the launch. The warning window is the
  moment the player has to act, so the alarm belongs to the launch, not to each
  missile in it.
- **The burner is an edge.** The ignition plays when `heat` crosses into the burner
  with hysteresis (`0.08` in, `0.02` out), so a ship riding the threshold does not
  stutter it every few frames.
- **The hum follows the hull.** `Sfx.engine(true, speed / BOOST_SPEED)` runs every
  frame; `_die` and `_exit_tree` stop it, so a restart or a return to the menu never
  leaves the engine running over the next scene.

The blasts are tuned by band, not by taste. An explosion that puts most of its
energy under 300 Hz is silent on a laptop speaker even at full volume: there is no
driver left to move it. `_explosion` therefore carries the hit in a bright crack
around 6.5 kHz over a mid body around 2.3 kHz, and the sub only adds weight
underneath. The same builder voices the ship's own death, pitched down.

Headless runs have no audio device, so the test asserts the wiring instead of
pretending to hear it: `Sfx.played(key)` counts plays per key, `Sfx.has(key)` proves
the palette is complete, and `Sfx.engine_active()` proves the hum starts and stops
with the ship. `reset_counts()` scopes each assertion so one event cannot satisfy
another's. The one check that looks at the signal itself reads
`audio/sfx/explosion.wav` and `player_death.wav` from disk and fails if less than 30%
of a blast's energy sits above 1 kHz. It reads the file rather than the resource on
purpose: Godot imports these WAVs as QOA, so `AudioStreamWAV.data` is not the PCM
that ships.

## What this build is meant to answer

1. **Does 360° aiming read clearly?** The aim line is there to check it, not to
   ship. If you cannot tell where you are shooting while moving the other way,
   P1 has a feedback problem, not a feature problem.
2. **Does the HP bar create tension instead of relief?** 6 segments, 1 damage
   per hit, 0.85 s of invulnerability. If you never feel threatened, the problem
   is the damage economy, not the bar.
3. **Are deaths attributable?** Every enemy attack is telegraphed — 0.42 s for the
   turret's two patterns, 0.72 s for the launcher's salvo — and the shapes are
   different on purpose:
   - **Ring** — 14 slow bullets. Dodge through the gaps. Tests reading space.
   - **Fan** — 5 fast aimed bullets. Dash or sidestep. Tests reaction.
   - **Salvo** — 2 guided missiles that outrun the hover's cruise. Spend the
     burner, transform, turn, dash, drop a decoy or shoot them down. Tests
     whether a warning window can be spent.
4. **Is the dash a decision or a reflex?** 0.12 s burst at 3.17x cruise, 0.85 s
   cooldown, and it grants invulnerability, so it doubles as an escape. The
   gesture is a double tap on the direction you want, so the way out and the way
   you asked for it are the same input.
5. **Can speed itself be a resource?** The afterburner is a tank, not a cooldown:
   holding it tops out at 42 instead of 26.8 and drains the reserve in about
   2.2 s, and the reserve only fills back while the burner is off (about 4.2 s
   from empty). Emptying it latches until the button is released, so holding the
   key at zero cannot stutter the ship between two speeds. The dash stays a
   separate tool: a 0.12 s invulnerable burst does something the burner does not.
6. **Does the arsenal change how the fight reads, or only how fast it ends?**
   The three primaries answer different aim problems — spread, tracking, one-shot
   alignment — so switching is a decision about the fight in front of you. The bomb
   is a resource tied to kills rather than a cooldown, which makes hoarding it a
   choice with a cost.
7. **Does flying over the planet read as a planet?** The ground is a real sphere,
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

8. **Does the mode change the fight, or only the speed?** FIGHTER is not a
   faster GERWALK: it removes strafing and free aim, doubles the price of a bad
   line, and hands back a turn arc, a jink and a cone that eats bullets.
   Transforming is the answer to "how do I get out of this" as often as it is the
   answer to "how do I get there". If it reads as a speed toggle, the mode has no
   reason to exist and the numbers are the wrong place to fix it.

## Tuning knobs

All values are named constants at the top of each script.

| Feel | File | Constant |
|------|------|----------|
| Movement weight | `entities/player/player.gd` | `MAX_SPEED`, `ACCELERATION`, `FRICTION` |
| Fine control | `entities/player/player.gd` | `MOVE_DEADZONE` |
| Hull turn and bank | `entities/player/player.gd` | `VISUAL_TURN_RATE`, `MAX_BANK`, `YAW_BANK`, `FIGHTER_BANK`, `BANK_RATE` |
| Camera spring and lead cap | `entities/player/player_camera.gd` | `LAG_SECONDS`, `LAG_RATE`, `LAG_MAX`, `MAX_OFFSET`, `DECAY_PER_SECOND` |
| Mode split | `entities/player/player.gd` | `FIGHTER_SPEED`, `FIGHTER_BOOST_SPEED`, `FIGHTER_ACCELERATION`, `FIGHTER_TURN_RATE` |
| Fighter flight model | `entities/player/player.gd` | `FIGHTER_STALL_SPEED` (glide floor), `FIGHTER_DRAG` (cruise to stall), `FIGHTER_GRIP` (course lag) |
| Transformation | `entities/player/player.gd` | `TRANSFORM_TIME`, `FIGHTER_NOSE_PITCH` |
| Yaw trim and barrel roll | `entities/player/player.gd` | `FIGHTER_TRIM_DEGREES`, `FIGHTER_YAW_TRIM`, `FIGHTER_ROLL_TIME`, `FIGHTER_ROLL_SPEED`, `FIGHTER_ROLL_ANIM_TIME` |
| Fighter gun profile | `combat/arsenal.gd` | `FIGHTER_RANGE_MULTIPLIER`, `FIGHTER_SPEED_MULTIPLIER`, `FIGHTER_VULCAN_SPREAD_DEGREES` |
| Weapon cadence and damage | `combat/arsenal.gd` | `VULCAN_*`, `LASER_*`, `PLASMA_*` (interval, damage, speed, spread, lock cone) |
| Missiles | `combat/arsenal.gd` | `MISSILE_*` (radar cone, load interval, max salvo, salvo cooldown, damage, turn rate, range, launch fan step and cap, weave amplitude/rate/hit range/fade) |
| Missile hardpoints | `entities/player/player_model.gd`, `entities/player/weapon_system.gd` | `WING_HARDPOINT`; `wing_anchors()` reads the span axis from `Bone.Wing.L/R`, and `MISSILE_CLEARANCE` keeps the shot off the pylon |
| Lock reticle | `combat/lock_reticle.gd` | `HALF_SIZE`, `ARM`, `THICKNESS`, `PIP`, `HEIGHT`, `COLOR`, `PULSE_SPEED`, `PULSE_DEPTH`, `GLOW`, `GLOW_DEPTH`, `LOCK_IN_SCALE`, `LOCK_IN_TIME`, `OVERSHOOT` |
| Radar scope | `ui/hud/radar.gd` | `DETECTION_RANGE`, `BLIP_RADIUS`, `SWEEP_PERIOD`, `SWEEP_ARC`; world-fixed, and every contact inside the range is drawn |
| Death countdown | `ui/hud/game_over.gd` | `RESPAWN_SECONDS`, `FADE_IN` |
| Death blast | `common/ship_explosion.gd` | `LIFETIME`, `CORE_*`, `FIRE_*`, `DEBRIS_DURATION`, `SPARK_LIFETIME`, `SMOKE_LIFETIME` |
| Missile trail | `combat/projectile.gd` | `TRAIL_INTERVAL`, `TRAIL_PUFF_LIFETIME`, `TRAIL_START_RADIUS`, `TRAIL_END_RADIUS`, `TRAIL_INHERIT` |
| Bomb economy and blast | `combat/arsenal.gd` | `BOMB_START_CHARGES`, `BOMB_MAX_CHARGES`, `BOMB_KILLS_PER_CHARGE`, `BOMB_RADIUS`, `BOMB_DAMAGE` |
| Decoy | `combat/arsenal.gd`, `combat/decoy.gd` | `DECOY_COOLDOWN`; `LIFETIME`, `CAPTURE_RADIUS` |
| Audio palette and mixing | `common/sfx.gd` | `VOICES`, `MAX_SPATIAL`, `SPATIAL_UNIT`, `SPATIAL_REACH`, `ENGINE_REST_DB`, `ENGINE_TOP_DB`, `SFX_BUS`, and the loaded `KEYS` |
| Sound synthesis | `tools/generate_sfx.gd` | `RATE`, `PEAK`, `SHAPE_SINE/SAW/SQUARE`, one builder per key in `_catalogue()`; each sound seeds the noise from its name, so the WAVs are reproducible and one builder cannot shift the others |
| Blast spectrum | `tools/generate_sfx.gd` | `_explosion` crack (~6.5 kHz), body (~2.3 kHz), sub and rumble; the suite requires at least 30% of the energy above 1 kHz |
| Weapon sound cues | `entities/player/weapon_system.gd` | one `Sfx.play` per shot; `_laser_sounding` gates the beam ignition; `missile_launch` pitch climbs with the salvo index |
| Ship sound cues | `entities/player/player.gd` | `Sfx.play` on `_start_transform`, `_start_dash` and `take_damage`; `_burning` hysteresis for the ignition; `Sfx.engine()` every frame |
| Enemy sound cues | `entities/enemy/*.gd` | `Sfx.play_at` on `_fire_pattern` (`enemy_fire`, `missile_warning`) and on `_spawn_explosion` (`explosion`) |
| Enemy score | `entities/enemy/*.gd` | `Enemy.SCORE_VALUE` (100), `FighterEnemy.KILL_SCORE` (200), `MissileEnemy.KILL_SCORE` (250); the arena sums them into the run total |
| Bomb shockwave look | `combat/bomb_wave.gd` | `RING_BAND`, `RING_COLOR`, `Arsenal.BOMB_WAVE_TIME` |
| Risk margin | `entities/player/player.gd` | `MAX_HP`, `IFRAME_DURATION` |
| Evasion | `entities/player/player.gd`, `combat/projectile.gd` | `DASH_SPEED`, `DASH_DURATION`, `DASH_COOLDOWN`; `Player.is_evading()` gates the early return in `Projectile._on_body_entered` |
| Afterburner speed | `entities/player/player.gd` | `BOOST_SPEED`, `BOOST_ACCELERATION`, `FOV_BOOST_KICK`, `FOV_RATE` |
| Turbo economy | `entities/player/player.gd` | `TURBO_MAX`, `TURBO_DRAIN_PER_SECOND`, `TURBO_RECHARGE_PER_SECOND` |
| Thruster plume and launch flash | `entities/player/player.gd` | `THRUST_KICK_DECAY`, flame lengths and alphas in `_update_afterburner_visual()`; the anchors come from the model's exhaust bones |
| Exhaust wake | `entities/player/player.gd` | `SMOKE_AMOUNT`, `SMOKE_LIFETIME`, `SMOKE_PUFF`, `SMOKE_DENSITY_HIGH`, `SMOKE_COLOR`; density follows the measured acceleration in `_update_smoke()`, so the nozzles are clean at a steady throttle |
| Wingtip vapour | `entities/player/player.gd`, `entities/player/player_model.gd` | `WINGTIP_WIDTH`, `WINGTIP_LIFETIME`, `WINGTIP_SPACING`, `WINGTIP_COLOR`, `WINGTIP_SPEED_FLOOR`, `WING_TIP_L`, `WING_TIP_R`; a ribbon rebuilt each frame from `wing_tips()`, which carries the measured mesh tip in the posed wing bone's frame, faded in by `_wingtip_vapour()` from the FIGHTER airspeed and wiped entirely outside FIGHTER |
| Airframe fill light | `entities/player/player.gd` | `FILL_ENERGY`, `FILL_COLOR`; it rides the camera rig and culls on `PlayerModel.AIRFRAME_LAYER` |
| Ship silhouette | `models/vf-1s/source/Vf-01_BRoid_ULa.glb` | the imported airframe: hull, wings, tails and canopy are model geometry, not code |
| Livery palette | `ui/menu/main_menu.gd` | `PALETTE`, `SWATCH_SIZE`; the first four swatches are the factory hull, stripe, canopy and lines, and the hull white is also the factory nose |
| Livery materials | `entities/player/player_model.gd` | `HULL_MATERIAL`, `TRIM_MATERIAL`, `LINE_MATERIAL` (name prefixes), `CANOPY_BONES`/`CANOPY_MESH` for the glass, `NOSE_MESH`/`NOSE_MATERIAL`/`NOSE_GAP` for the cone cut out of the forward fuselage; every other material keeps the file's paint |
| Livery preview | `ui/menu/livery_preview.gd` | `TURN_SPEED`, `CAMERA_POSITION`, `CAMERA_TARGET` |
| Wing sweep | `entities/player/player.gd` | `WING_SWEEP_FORWARD` (0 deg), `WING_SWEEP_CRUISE` (14 deg), `WING_SWEEP_BACK` (38 deg), `WING_SWEEP_RATE` (60 deg/s), applied to `Bone.Wing.L/R` in `player_model.gd` |
| GERWALK limbs | `entities/player/player_model.gd` | `THIGH_ANGLE`, `KNEE_ANGLE`, `LEG_SPLAY`, `ARM_ANGLE`, `ELBOW_ANGLE`, `ARM_SPLAY`; `GERWALK_LIFT` in the player |
| Model preview | `tools/model_view.gd` | `--view front\|side\|top\|quarter\|game`, `--fighter 1`, `--size`, `--nosun 1`, `--sunrot`, `--out` (orthographic turntable for silhouette and lighting checks) |
| Muzzle clears the nose | `entities/player/player.gd` | `MUZZLE_DISTANCE`, `BEAM_START` |
| Pattern cadence | `entities/enemy/turret.gd` | `TELEGRAPH_TIME`, `RECOVER_TIME` |
| Pattern shape | `entities/enemy/turret.gd` | `RING_BULLETS`, `RING_SPEED`, `FAN_BULLETS`, `FAN_CONVERGENCE`, `FAN_SPEED` |
| Planet scale and lap length | `levels/arena/arena.gd` | `PLANET_RADIUS` (lap = `2 * PI * PLANET_RADIUS`), `PLANET_SEGMENTS`, `PLANET_RINGS` |
| Islands and sea level | `levels/arena/planet_surface.gdshader` | `SEA_LEVEL`, `REGION_SCALE` (continents), `ISLAND_SCALE` (islands), `COAST_SCALE` (shoreline) |
| City districts | `levels/arena/planet_surface.gdshader` | `CITY_CELL` (density), `CITY_HALF` (district size), `CITY_BLOCK`, `CITY_ROAD`, `CITY_ROOF` (street and roof scale), `CITY_LIT` (share of lit roofs) |
| Ground height | `levels/arena/arena.gd` | `GROUND_Y` |
| Surface look | `levels/arena/planet_surface.gdshader` | noise scales, palette stops, contour count and strength |
| Camera framing | `entities/player/player.tscn` | `CameraRig` position, pitch, `Camera3D.fov` |
| Camera shake | `entities/player/player_camera.gd` | `MAX_OFFSET`, `DECAY_PER_SECOND` |
| Enemy engagement | `entities/enemy/turret.gd` | `AGGRO_RADIUS`, `LEASH_RADIUS`, `ORBIT_RADIUS`, `PURSUIT_SPEED`, `STRAFE_SPEED` |
| Missile launcher | `entities/enemy/missile_enemy.gd` | `LAUNCHER_HP`, `SALVO_MISSILES`, `MISSILE_SPEED`, `MISSILE_TURN_RATE`, `MISSILE_DAMAGE`, `MISSILE_LIFETIME`, `MISSILE_SPREAD_DEGREES`, `LAUNCH_TELEGRAPH`, `LAUNCH_RECOVER` |
| Launcher share of the population | `levels/arena/arena.gd` | `MISSILE_ENEMY_SHARE` |
| Interceptor flight | `entities/enemy/fighter_enemy.gd` | `FIGHTER_HP`, `TOP_SPEED` (34), `FLOOR_SPEED`, `ACCELERATION`, `TURN_RATE`, `CHASE_RADIUS`, `BREAK_OFF_RADIUS`, `ATTACK_RANGE`, `MIN_LAUNCH_RANGE`, `AIM_TOLERANCE_DEGREES` |
| Interceptor salvo | `entities/enemy/fighter_enemy.gd` | `SALVO`, `MISSILE_SPEED`, `MISSILE_TURN_RATE`, `MISSILE_DAMAGE`, `MISSILE_SPREAD_DEGREES`, `WARNING_TIME`, `EXTEND_TIME`, `RELOAD_TIME` |
| Interceptor share of the population | `levels/arena/arena.gd` | `FIGHTER_ENEMY_SHARE` |
| Enemy roaming | `entities/enemy/turret.gd` | `ROAM_SPEED`, `ROAM_LEG_MIN`, `ROAM_LEG_MAX`, `ROAM_LEG_TIME` |
| Encounter streaming | `levels/arena/arena.gd` | `MAX_ENEMIES`, `SPAWN_INTERVAL`, `SPAWN_DISTANCE_MIN/MAX`, `SPAWN_HEADING_SPREAD`, `DESPAWN_DISTANCE`, `FIRST_SPAWN_DISTANCE/ANGLE` |

## Architecture

```
common/global_event_bus.gd      lifecycle signals only (< 15 events)
common/sfx.gd                   autoload: palette, SFX bus + limiter, 2D voice pool, 3D events, engine hum
tools/generate_sfx.gd           deterministic synthesizer that writes audio/sfx/*.wav
audio/sfx/*.wav                 the committed palette (generated, never sampled)
common/hit_spark.*              self-freeing 3D impact flash
combat/arsenal.gd               weapon catalogue: every number a player feels
combat/projectile.*             one shared bullet, team decides layers + shape, guidance and interception here
combat/smoke_puff.gd            self-freeing trail puff, added to the scene, not the shot
combat/bomb_wave.gd             expanding shockwave, presentation only
combat/decoy.gd                 dropped flare: takes the lock of nearby guided shots, self-freeing
combat/lock_reticle.gd          world-space mark on a radar lock, dies with its turret
entities/player/                CharacterBody3D, camera rig, aim, dash, afterburner, HP
entities/player/weapon_system.gd  primaries, missiles, the bomb and the decoy, spawned per ship
entities/enemy/turret.gd        turret: roam -> engage -> telegraph -> pattern -> recover
entities/enemy/missile_enemy.gd launcher variant: the same movement, a guided salvo instead of patterns
entities/enemy/fighter_enemy.gd interceptor: the player's airframe and flight model, a missile pass and a break
ui/hud/                         event-fed bars; the radar polls the enemy group for bearings
ui/menu/                        boot menu: start, the display and livery settings, the controls reference
ui/menu/livery_preview.gd       SubViewport turntable of the same airframe, built when the panel opens
levels/arena/arena.gd           rolling planet sphere, stars, encounter streaming
```

Enemies, bullets and props are still built in code (`_build_visual()`) instead of
being serialised into the `.tscn` files, and placeholder geometry remains a swap
target: when the pre-rendered pipeline lands (D-02) each entity can drop in a mesh
or a sprite without touching the scene graph or the collision shapes. The player
is no longer a placeholder.

The player airframe is model geometry now. `PlayerModel` instantiates the imported
VF-1S, scales and yaws it into the capsule's slot, hides the deployed gear and the
crew, and drives the skeleton every frame. Everything the placeholder used to
build by hand — fuselage stations, wing outlines, tail surfaces, canopy, limbs —
ships inside the model, and the loft and extrude helpers went with it.

The swing wings are bones too: `Bone.Wing.L/R` rotate about the model's vertical
axis, and the sweep follows speed rather than the mode — the wings stay nearly
straight at the glide floor, contract `WING_SWEEP_CRUISE` (14 deg) as the ship
reaches `FIGHTER_SPEED` (`MAX_SPEED` in GERWALK), and sweep the rest of the way to
`WING_SWEEP_BACK` (38 deg) past it, which is where the burner lives. The low-speed
leg is eased (squared, not linear) so a slow fighter keeps its span and only folds
as it closes on cruise: at the stall floor the wings sit at about 2 deg, and
halfway to cruise they are still under 4. The angle is animated, not derived: the
wing travels at `WING_SWEEP_RATE` (60 deg/s), because the fighter reaches cruise in
a handful of frames and a derived angle snapped from straight to swept between two
of them. The thresholds come from the mode the switch is committing to, so a
transformation never makes them flap on the way. The afterburner cones are anchored to the exhaust
bones rather than to a fixed tail offset, so they stay on the engines when the
stance swings the nacelles forward. The muzzle distance still clears the nose, so
bullets leave the airframe instead of spawning inside it.

Weapons follow the same ownership rule. `WeaponSystem` holds the selected weapon,
the bomb rack, the missile radar and the decoy cooldown, and exposes only `select()`,
`cycle()`, `fire_bomb()`, `drop_decoy()`, `kind()`, `bomb_charges()`, `salvo_count()`
and `max_salvo()`; the player owns the input that drives it, and the HUD is a
projection of `player_weapon_changed`, `player_bombs_changed`,
`player_missile_salvo_changed` and `player_decoy_changed`. `Arsenal` holds the tuning
so no weapon hard-codes a cadence inside firing code.

Ownership rule: the player owns its HP and its turbo reserve, and only exposes
`take_damage()`. The HUD is a projection of `player_health_changed` and
`player_turbo_changed`. The arena owns the run's score for the same reason: the enemy
publishes the kill with its value, the arena adds it and republishes the total, and
the HUD only prints it. Nothing in the UI mutates gameplay. The turbo event fires
once per whole reserve unit rather than once per physics frame: the bar is 234 px
wide, so a unit is under 2.5 px and the bus stays quiet.

The radar scope in the bottom-right corner is the one HUD element that does not
listen to the bus. Health, mode and charges are transitions and fit a signal; a
contact's bearing changes every frame, and pushing two vectors through the bus
would add a per-frame allocation to say what a group query already says. It is
world-fixed rather than heading-up because the camera never yaws: screen up is
`-Z` and screen right is `+X` in every mode, so a scope that rotated with the nose
would put a contact on the opposite side of the screen from where it is drawn.
Detection is a 360 degree range (`Radar.DETECTION_RANGE`, 140 units), not the
missile radar's forward cone — the cone answers "what can I shoot", the scope
answers "what is around me" — and contacts past the range are not drawn at all
instead of pinned to the rim, because a blip on the rim claims a bearing the ship
cannot act on. The marker points along `Player.nose_direction()`, the vector the
airframe's yaw follows, so the scope shows where the ship is pointing rather than
where it happens to drift. The backdrop is nearly opaque for a reason: at the
first pass's 0.55 a turret flying under the corner showed through the disk and
read as a contact that was not on the scope.

## Checks

```sh
# Headless gameplay assertions (movement, firing, patterns, i-frames, score, death)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . tests/smoke_test.tscn

# Regenerate the sound palette from scratch (reproduces the committed WAVs byte for byte)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/generate_sfx.gd

# Render one real frame to /tmp/gerwalk_frame.png for visual review
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn

# Same, after travelling: the terrain must not match the resting frame
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --travel 180 --out /tmp/gerwalk_moved.png

# The death screen: the countdown, both answers and the shortcut hint
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --death 1 --out /tmp/gerwalk_death.png

# Review the bank: strafe across the nose and the hull must lean
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --strafe 30 --out /tmp/gerwalk_bank.png

# Review one weapon at a time (1 vulcan, 2 laser, 3 plasma) and the bomb ring
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --weapon 2 --out /tmp/gerwalk_laser.png
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --bomb 1 --out /tmp/gerwalk_bomb.png

# Review the missile rack: a contact ahead, the button held for a full load, then
# the release. `--salvo-delay N` waits N frames after the salvo leaves, which is
# where the fan has opened out and the guidance has not folded it back in yet.
# `--close 1 --zoom 1.7` hangs the camera nearer, since a missile is a few pixels long.
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --missile 100 --close 1 --zoom 1.7 --salvo-delay 10 --out /tmp/gerwalk_salvo.png

# Review the lock reticle: the same hold without the release. A short N catches the
# lock-in, a long one the settled box and its breathing emission.
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --lock 4 --out /tmp/gerwalk_lock_in.png
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --lock 40 --out /tmp/gerwalk_lock_settled.png

# Review the braid: the same salvo held longer, so the shots have woven a full wave
# and the trails read as curves instead of a fan of straight lines.
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --missile 100 --salvo-delay 26 --out /tmp/gerwalk_salvo_braid.png

# Review the airframe alone, orthographic, in both modes (silhouette debugging)
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/model_view.tscn \
    -- --view quarter --out /tmp/gerwalk_quarter.png
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/model_view.tscn \
    -- --view top --fighter 1 --out /tmp/fighter_top.png

# Review the modes: the swept FIGHTER silhouette, then the supersonic burst cone
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --fighter 26 --out /tmp/gerwalk_fighter.png
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --fighter 2 --boost 26 --out /tmp/gerwalk_burst.png

# Review the interceptor: it is spawned ahead of the ship and flown for N frames.
# A short hold catches it on the way in; 200 frames catches the aim beam and the
# salvo, because the approach, the warning and the reload take about three seconds.
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --interceptor 20 --out /tmp/gerwalk_interceptor.png
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --interceptor 200 --out /tmp/gerwalk_interceptor_salvo.png

# Review an enemy death blast: the interceptor is flown in, then killed 8 frames
# before the capture, which is where the fireball has opened
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --interceptor 40 --kill 1 --death-delay 8 --out /tmp/gerwalk_enemy_death.png

# Review a hull detail close up, and split a dark patch into its three causes:
# `--nosmoke` removes the wake, `--noshadow` the sun's shadow map, `--sunrot`
# swings the sun around the ship
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --close 1 --zoom 0.22 --out /tmp/gerwalk_detail.png
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/capture_frame.tscn \
    -- --close 1 --zoom 0.22 --nosmoke 1 --out /tmp/gerwalk_detail_nowake.png

# Same airframe, the game camera's 15 degrees off vertical, with and without the sun
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/model_view.tscn \
    -- --view game --nosun 1 --out /tmp/gerwalk_ambient.png
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

- **The laser does not pierce.** It stops at the first body it meets, which keeps
  the drawn beam honest; a piercing beam is a different weapon and needs its own
  damage model (per-target ticks) before it can ship.
- **Nothing is collected.** There is no pickup or power-level economy yet: the
  three archetypes are always available, and the bomb is fed by kills only. Raiden's
  weapon capsules would sit on top of this without touching the archetypes.
- **The gunpod does not fire.** Shots still leave the ship's centre along the aim
  direction, which is what keeps a twin-stick bullet-hell readable; the held GU-11
  is a silhouette prop, not a muzzle. Wiring the muzzle to the pod would put a
  parallax offset between the crosshair and the bullet.
- **The legs are as long as the hover height allows.** They hang 1.7 units below a
  hull that floats 1.5 above the ground, so the stance is a hovering GERWALK and
  never a mech standing on the terrain: the feet are levelled to the ground, not
  planted on it. A real landing pose needs a ground contact rule the movement code
  does not have.
- **The missile radar only looks forward.** A turret behind the nose is a contact
  for nothing, so a salvo is always a decision about where the ship points. The load
  is also not banked: turning away mid-hold stops it growing, and slipping all
  contacts drops the rack instead of saving it for the next release. With fewer
  missiles than contacts the nearest ones take the hits, because the spread runs
  from the head of the pool.
- **The bomb grants no invulnerability.** It cancels bullets inside its radius, so
  a pattern that arrives from outside the ring in the same frame still hurts.
- **The decoy only answers guidance.** Turret bullets ignore it, and it does not
  break the launcher's aim: the flare buys the flight time of the salvo already in
  the air, not a safe spot. Nothing draws a line between the flare and the missiles
  it pulled, so the player reads the turn itself.

- **Bullets are one node each.** At 400 concurrent bullets this will need a
  pooled manager or `PhysicsServer3D` (NFR-05). Not measured yet.
- **No audio.** Hit and dash feedback are visual only.
- **The afterburner outruns everything on purpose.** `BOOST_SPEED` (42) sits far
  above `PURSUIT_SPEED` (24) and above the launcher's missile (33), so a full
  reserve buys a clean disengage. The reserve is the price; if escaping stops
  feeling earned, raise the drain before lowering the speed.
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
- **No wave escalation.** A population of up to 3 enemies — one in three a missile
  launcher — is streamed around the ship, so the planet stays inhabited and the
  difficulty stays flat (FR-10 is still a proposal, not implemented).
- **The planet no longer shows a limb.** At `PLANET_RADIUS = 1600` the surface
  fills the frame, so the star field is effectively scenery and the "globe" read
  comes from rolling terrain, not from a visible edge. The star shell still sits
  at 320-430 units, which at this radius is inside the planet's silhouette; it was
  never visible anyway, but it is dead geometry.
- **The city chart leaves six seams.** Districts are placed on a cube-sphere
  chart, so along the six great circles where faces meet a district can change
  orientation or be cut in half. Accepted: the alternative was a tangent frame
  with two degenerate poles, which the roll crosses constantly.
- **Cities have no suburbs.** A district is a hard-edged square of asphalt that
  stops at the coastline, and nothing else on the surface is built up.
- **The skid has no airspeed cue.** During a hard turn the nose and the ground
  track diverge, and the divergence is only visible as the terrain drifting
  sideways. Nothing draws the velocity vector, so the drift is felt before it is
  understood.
- **i-frames and dash are prototypes of FR-09 and FR-11**, which remain
  unconfirmed product requirements — try them and decide, do not assume.
- **Sound is synthesized, not recorded.** The palette matches the *character* of
  the anime's cues, never their waveforms, and there is no music and no voice:
  shipping a track would need its own bus, a loop point and a licence decision.
- **The hum is one voice, not one per nozzle.** A stereo or per-thruster engine
  would need the nozzle anchors fed into the audio path; at prototype zoom the
  single loop reads as the ship, and the plumes carry the per-nozzle cue.
- **The positional path caps at 24 voices.** Past the cap, world sounds fall back
  to the flat pool instead of queueing, so in a heavier fight distant explosions
  lose their panning before they are dropped.
