# Player visual: bone-driven VF-1S model

Replace the hand-built player hull with the imported VF-1S GLB, driven by its
skeleton so FIGHTER and GERWALK keep working. Branch: local feature commits on
`main`. Delivery: `ask-on-risk`. Test runner: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

S1. The player visual is the VF-1S at `models/vf-1s/source/Vf-01_BRoid_ULa.glb`,
    imported by Godot and instanced under `_visual`, which stays the node that
    carries yaw, bank, dash roll, nose pitch, GERWALK lift and the i-frame blink.
    User: "quisiera ver la posibilidad de importar el modelo glb en models/vf-1s
    y aplicarlo al player" / "vamos por B. Híbrido por huesos".

S2. Orientation and scale: the model faces -Z and the game reads +X as forward, so
    it is yawed -90 degrees. Scaled to the footprint of the current fighter (4.25
    units of length, ~3.0 of wingspan) and offset so it sits on the capsule origin
    instead of the model's own pivot.

S3. The FIGHTER <-> GERWALK switch (0.28 s) poses the skeleton from
    `_mode_blend`, continuously, with no pop and no limb going through the hull.
    Both keyframes are sampled from the clip the file ships -- fighter at frame
    zero, the GERWALK gunner hold at nine seconds -- instead of hand-measured
    angles. Revised in L8 and L9.

S4. Wing sweep follows speed, not the mode: the wings sit at `WING_SWEEP_FORWARD`
    (extended) at cruise and reach `WING_SWEEP_BACK` only above it, in both modes.
    The thresholds are `FIGHTER_SPEED`/`FIGHTER_BOOST_SPEED` in FIGHTER and
    `MAX_SPEED`/`BOOST_SPEED` in GERWALK, chosen by the mode being committed to.
    User, verbatim: "cuando el figther va a velocidad crusero que expanda las alas".

S5. The afterburner cones stay where the engines are: they are placed from the
    model's exhaust nozzles, not from `THRUSTER_X`/`THRUSTER_Z`, and still stretch
    with thrust and the acceleration kick.

S6. The model carries no gunpod, so the procedural GU-11 stays: it rides the
    right hand in GERWALK and stows on the centreline in FIGHTER, lerped the same
    way the pose is. Revised in L8 (fixed right-side mount while the stance stowed
    the arms) and again in L9, when the stance moved to the gunner hold and gave
    the pod a hand to follow.

S7. Nothing about the flight model, weapons, damage, i-frames, shockwave or aim
    beam changes. Only the visual construction changes.

S8. The model has to read from the actual game camera (50 units up, 75 degrees
    down): no z-fighting with the play plane, no silhouette lost at that distance.

S9. Import and load happen once. The headless smoke suite stays green and must not
    regress into loading the 47.8 MB model per test entity.

S10. The repository keeps only what the runtime needs: the GLB (textures are
     embedded) and no generated junk. `models/vf-1s/textures/` is dead weight and
     is not committed.

S11. The canopy reads as a cockpit: both of its panels carry the same celeste
     tint in FIGHTER and GERWALK, the tint never changes with the mode, and the
     frame and rib keep the materials the file ships. User, verbatim: "la
     ventanilla del piloto debe ser del mismo color de la que tiene el figther",
     then "la ventanilla del piloto podria ser verde?", then "mejor cambia a un
     celeste".

S12. Each nozzle leaves an exhaust trail whose length and density grow with
     speed: a hover is a wisp, fighter cruise reaches about 24 units, and the
     burner goes past 30. The emitters ride the nozzle anchors, so GERWALK drags
     the wake with its feet, and nothing about the flight model changes. User,
     verbatim: "ahora quiero que el avion deje una estela de humo desde sus
     propulsores y esta aumente segun su velocidad".

S13. Missiles leave from the wing hardpoints, alternating wings one shot at a
     time. The hardpoint is read from the wing bone's own span axis, so the
     sweep carries it, and consecutive missiles pick opposite sides. The launch
     point and the guidance curve agree: a missile angling out leaves from the
     wing it angles towards. User, verbatim: "quiero que los misiles salgan
     desde las alas de player intercalando uno a uno entre las alas".

S14. The barrel roll reads slower than the jink and repeats the side it last went
     to. The 0.20 s step and its i-frames stay exactly as they are; the 360 degree
     turn-over runs on its own 0.45 s clock, and a centred stick reuses the last
     side instead of defaulting right, with the spin following that side so the
     animation agrees with the step. User, verbatim: "quiero que la animación de
     evasión sea mas lenta y se ejecute en direccion de la ultimo lado ejecutado".

## Tasks

| ID | Spec | Route | Status | Evidence |
|----|------|-------|--------|----------|
| T1 | S3, S6 | inline | done | Bone map cached; splay axis measured: about model Y, not Z (feet ±0.30 with Z vs ±0.95 with Y) |
| T2 | S1, S2, S8 | inline | done | `player_model.gd`; holder `Basis(UP, -90°) * 0.21`, pivot rotated before it is cancelled; gear and crew hidden by node name |
| T3 | S3 | inline | done | Absolute pose composed on each bone's rest; GERWALK feet `(1.33, -0.32, ±0.95)`, FIGHTER `(-1.68, -0.16, ±0.29)` |
| T4 | S4 | inline | done | `Bone.Wing.L/R` about model Y, sweep taken from the throttle |
| T5 | S5 | inline | done | Flames re-anchored from `Exhaust.UPPER*` every frame |
| T6 | S6 | inline | done | Pod-to-hand distance `0.000` in GERWALK; stowed at `(0.48, -0.27, 0.00)` |
| T7 | S7, S10 | inline | done | `player.gd` 956 lines; loft/slab/limb builders deleted; extracted PNGs removed, only the GLB ships |
| T8 | S9 | inline | done | 156 PASS / 0 FAIL (`./run.sh --headless tests/smoke_test.tscn`); docs updated |
| T9 | S3, S6, S8 | inline | done | L8: clip frames sampled (fighter t=0, GERWALK t=7.0); canopy/gear frozen; airframe shadow off; 161 PASS / 0 FAIL; in-game captures clean |
| T10 | S3, S6 | inline | done | L9: GERWALK hold moved to 9.0 s (gunner arms); `hand_anchor()` on `Wrist_STATIC.R` puts the pod in the hand; silhouette test pins pod-to-hand < 0.05 and hands ahead |
| T11 | S11 | inline | done | L10: both canopy panels repainted celeste through per-surface overrides; identical in FIGHTER and GERWALK; 162 PASS / 0 FAIL |
| T12 | S12 | inline | done | L11: one GPU emitter per nozzle left in world space; density from speed via `amount_ratio`; 166 PASS / 0 FAIL; captures at cruise, boost and GERWALK |
| T13 | S13 | inline | done | L12: `wing_anchors()` reads the span axis from `Bone.Wing.L/R`; `_launch_missile` picks the hardpoint by side plus `MISSILE_CLEARANCE`; 177 PASS / 0 FAIL; fighter capture shows one missile leaving each wing |
| T14 | S14 | inline | done | L13: the spin moved to its own `FIGHTER_ROLL_ANIM_TIME = 0.45 s` timer, `_roll_side` survives a neutral stick and signs the spin; 182 PASS / 0 FAIL; `--roll N` captures at 6/12/20 frames |

Route note: no delegation trigger fired — one understood change, one writer, no
parallel units. Delivery: local commits on `main`, which is this repo's practice
(`git remote` is empty, so there is no PR to chain). |

## Log

L1: User, verbatim: "quisiera ver la posibilidad de importar el modelo glb en
models/vf-1s y aplicarlo al player. analiza si esto es posible". Then, verbatim:
"vamos por B. Híbrido por huesos". Chosen route: keep `player.gd` in charge of the
flight model and re-point the visual at the model's 85-bone skeleton, in the
tradition of the placeholder that D-02 was meant to replace.

L2: Measured before writing code: 47.8 MB GLB, 79 meshes / 137 surfaces / 204,576
vertices, 54 materials, 12 embedded images at 4096 or 2048 square (~382 MB of VRAM
before mipmaps), 1.3 s to load in a headless runtime, one 13.4 s clip
(`__ActionLegGERWALKgunner`) that only moves canopy and control surfaces. Nose sits
at z = -2.63 and the tail hook at z = +5.41, so the model faces -Z. Bounding box
17.97 x 6.51 x 19.57, so the scale to the current 4.25-unit fighter is ~0.21.

L3: Implemented `entities/player/player_model.gd` and re-pointed `_build_visual()`.
Two traps cost real time and are worth recording. First, a bone pose in Godot is
absolute: `set_bone_pose_rotation` replaces the rest pose, so writing identity
collapses the skeleton; every angle is composed on the rest and accumulated by
left-multiplication. Second, the holder offset must be rotated: the pivot lives in
model space, so `position = -(basis * PIVOT)`, not `-PIVOT * SCALE`. The wrong form
pushed the hull off centre and made the two nozzle anchors asymmetric
(-0.09 / +0.53 instead of +/-0.31).

L4: The splay axis was the other measurement that changed the design. Rolling the
legs about the fore-aft axis moves the feet only +/-0.30, because the leg points
forward and there is little vertical lever left; yawing about the model's vertical
opens them to +/-0.95 and puts them ahead of the wing leading edge, which is what
makes the stance visible from the 75 degree camera. `GERWALK_LIFT` rose from 0.35
to 0.55 because the model's nacelles hang lower than the placeholder's legs.

L5: Verified. Suite: 156 PASS / 0 FAIL. Renders from the game camera, pulled in
along its own forward axis so the angle matches, show FIGHTER as a swept-wing
fighter with the pod stowed and the plumes at the tail, and GERWALK as the same
airframe with both nacelles swung forward and out. Known cosmetic issue at 4x
zoom: a few dark slivers detach from the hull near the wing root in GERWALK, most
likely the `Text.003` decal mesh under `GUN.R`. They are 2-3 px at the real camera
distance, so they are recorded here rather than chased.

L6: WRONG on the first attempt, corrected here. Godot's glTF importer extracts the
embedded images to files next to the source, and the imported scene references
them by path, so the `[deps]` block listing only the `.scn` does NOT mean the
textures are embedded. Deleting the extracted PNGs made the model fail to load
mid-scene: the skeleton never resolved, `build()` returned with empty bone arrays
and the player went invisible (`Out of bounds get index '0'` on `Array[int]`). The
fix is to remove the `.import` and `.godot/imported/Vf-01_BRoid_ULa.glb-*`, let
Godot re-import, and commit the 12 regenerated textures with their `.import`
files. `build()` also guards its bone arrays now, so a failed load costs the model
and not the whole player.

L7: User, verbatim: "cuando el figther va a velocidad crusero que expanda las alas".
The old rule locked FIGHTER fully aft regardless of speed (`sweep_t` was forced to
1.0 by `_mode_blend`), so the wings only ever answered the throttle in GERWALK.
They now answer speed in both modes: 0 degrees at cruise, full sweep past it. The
thresholds are picked from the mode the switch is committing to instead of being
blended, because a blended cruise would swing the wings back and forth while the
ship decelerates through the transformation. `PlayerModel.sweep_degrees` exposes
the value so the suite pins it: 0.0 at cruise, 26.6 at 58 u/s.

L8: User, verbatim: "el player se ve raro ¿el fiel al gbl? analizalo". Compared the
game with the raw import from the same orthographic camera: FIGHTER was already
pixel-identical to the GLB, so the shape was never the problem -- the *pose* was.
Two defects, both ours:

1. The bare import is the bind pose, and the bind pose is not the fighter. Bone
   diff against the shipped clip at t=0: `Bone.JetPack` +168.5 deg,
   `Rudder.Wing.L/R` +145/+176, `GearDOOR*` +90..+120, `TailHOOK` +22.8. That is
   the fast pack flipped onto its back and the tail surfaces folded, which is what
   the floating grey and black blades were. Seeding those bones from frame zero
   removed them (verified in renders and in-game at 6x zoom).
2. The stance was hand-tuned (`THIGH_ANGLE -150`, `LEG_SPLAY 25`) and put the legs
   out to the sides; the asset's own GERWALK frame hangs them under the hull. The
   clip holds that stance from about 6 s to 8 s before it continues into Battroid,
   so `PlayerModel` now samples frame zero and the 7.0 s hold once at build and
   slerps between them per bone. Frame zero also parks the ship (gear down, canopy
   open, wings half folded), so only the bones the transformation owns keep the
   clip's value and the canopy/gear bones are frozen.

Also found: the dark dotted arc trailing the ship in game was its own shadowmap at
that scale, not debris. The airframe no longer casts a shadow, matching the gunpod.

Suite: 161 PASS / 0 FAIL. Three assertions pinned the old hand-made stance (leg
spread 0.95, feet ahead at x 1.33, pod handed to `Hand.R`); they now pin the
authored stance (spread 0.56, feet under the hull at x 0.04, pod on the fixed
right-side mount).

L9: User, verbatim: "perfecto pero en el modo gerwalk necesito que muestre los
brazos y el arma", then "pero los brazos deben estar adelante y uno sostenien do
el arma", then "en el glb ya existe esa pose". The user was right about the last
one, and it moved the keyframe: the clip plants the legs first and only then
brings the arms forward, so the 7.0 s hold I had sampled stops at the legs. The
hold that matches the request runs 8.5 to 10.0 s with the legs identical to the
7 second frame -- handR (0.77, -0.43, 0.56), handL (0.63, -0.70, -0.75) -- so
`GERWALK_TIME` became 9.0. That gave the pod a hand again: `hand_anchor()` reads
`Wrist_STATIC.R` ("Hand.R" is a different link, the one the clip turns, and the
mesh rides the wrist), and the fixed right-side mount was deleted. The silhouette
test now pins pod-to-hand distance below 0.05 with the hands ahead of the hull,
and the leg anchors barely moved. 162 PASS / 0 FAIL.

L10: User, verbatim: "la ventanilla del piloto debe ser del mismo color de la que
tiene el figther", then "la ventanilla del piloto podria ser verde?", then "mejor
cambia a un celeste". Measured before painting: the canopy is two stacked
meshes, a teal glass sheet (`Window.007/.008`, 0.43/0.63/0.63) on
`Bone.GLASScanopy` and a light grey shell (`Aircraft BASE color.004`, 0.91) on
`Bone.CanopyCover`, plus a dark rib. Painting the glass alone changed nothing on
screen -- the shell sits on top of it -- which a probe that painted the two
candidates magenta and yellow made obvious in one render. Both panels now take
the tint through a duplicated material and a per-surface override, so the rib and
the frame keep the file's trim and the colour cannot differ between modes. The
tint is written once at build.

Suite: 162 PASS / 0 FAIL. Verified with the same fixed heading and camera in both
modes: the canopy is the same celeste in FIGHTER and GERWALK.

L11: User, verbatim: "ahora quiero que el avion deje una estela de humo desde sus
propulsores y esta aumente segun su velocidad". Two emitters, one per nozzle,
built once with their worst case and left in world space: a puff that stays where
it was born is what turns a point emitter into a trail, and the gap between
puffs is the speed itself, so the wake grows with the throttle without anyone
rescaling it. Density is the one thing that needs a knob, and `amount_ratio`
turns it without restarting the emission. The anchors come from
`nozzle_anchors()`, which in GERWALK are the feet, so the stance drags a twin
trail with it.

Three passes were needed before the trail read as smoke. The first one laid the
puffs down in visible batches, which is Godot's default 30 Hz simulation: with
`fixed_fps = 0` they close into a ribbon. The second was a white pipe, because
thirty overlapping puffs at alpha 0.7 saturate: the per-particle alpha is 0.30
now and the ramp fades to nothing. The third was a string of beads at
`amount = 150`; 450 per emitter is where consecutive puffs overlap at 60 u/s.

Kept as a GPU emitter instead of reusing `SmokePuff`, and the reason is in the
docs: the missile trail needs puffs that outlive the shot and curve with it, so
it has to be nodes in the scene, while the ship needs a continuous ribbon at a
cadence no node budget would enjoy.

Suite: 166 PASS / 0 FAIL, with three assertions pinning the wake: one emitter
per nozzle, puffs in world space, and density climbing with speed (0.05 at rest,
0.95 flat out). Captures: cruise, fighter boost, GERWALK run and a hover that
leaves nothing behind.

L12: User, verbatim: "quiero que los misiles salgan desde las alas de player
intercalando uno a uno entre las alas". The hardpoint is read from the wing bone
instead of a hand-tuned offset: `wing_anchors()` takes the bone origin and walks
outboard along `pose.basis.y`, which is the axis the sweep turns, so a folded wing
launches from where the wing actually is. The span was measured first with a
throwaway probe (`Bone.Wing.L` origin (-1.89, 1.33, 0.57), `basis.y` (-0.73, 0.03,
0.69); `Bone.Wing.R` origin (2.25, 1.33, 0.59), `basis.y` (0.84, 0.03, 0.55)),
which is why the hardpoint is `WING_HARDPOINT = 0.55` along that axis.

The pair is chosen by side, not by index: `_launch_missile` already alternated the
launch angle with `_missiles_fired % 2`, and the sign of the offset against the
right vector is what says which wing is which. That keeps the launch point and the
curve in agreement. `MISSILE_CLEARANCE = 0.12` moves the shot a hand's width ahead
so it never spawns inside the pylon, and the old nose offset remains as the
fallback when the model reports no hardpoints.

The test reads both layers: the model's anchors are two and outboard, the player
reports the same pair in world space, the pair straddles the hull, and the missiles
in flight alternate sides. It passes with the hardpoints at -0.99 / 1.07 and the
shots at 0.91 / -0.88. Suite: 177 PASS / 0 FAIL.

Visual review took a few passes on the capture tool, not on the feature: the gun
also fires while the aim stick is off centre, so a missile capture has to release
both; the turret it needs for the radar was killing the ship, so it is spawned
inert; and FIGHTER always moves at its minimum throttle, so the contact is spawned
40 units out to stay inside the radar for the whole hold. With those, the fighter
capture shows one missile leaving each wing.

L13: User, verbatim: "quiero que la animación de evasión sea mas lenta y se
ejecute en direccion de la ultimo lado ejecutado". Two separate problems hid in
that sentence. The slow one was easy to get wrong: `_dash_time` is not just the
animation, it is the 55 u/s step and the i-frames that step buys, so stretching
it to 0.45 s would have doubled the distance and the protection window. The
turn-over got its own clock (`_roll_anim_time`), and `_dash_time` stayed at 0.20 s
so the dodge is unchanged and only what is seen changed.

The side was a bug, not a tuning knob: `_start_barrel_roll` read the aim axis
every time and fell back to `1.0`, so a centred stick always rolled right. It now
only re-reads a non-zero stick, keeps the last side otherwise, and the spin sign
follows `_roll_side` -- which also fixed the old spin, that turned right even when
the ship stepped left.

The test pins both: at the end of the 0.20 s jink the hull is still 160 degrees
into the roll and on the left side, a centred stick repeats that side and steps
left again (-7.1 units), and the spin settles back on the bank axis at 0.0 deg.
Suite: 182 PASS / 0 FAIL. `--roll N` was added to `capture_frame.gd` (with
`--close` now shared with the missile capture) and the 6/12/20 frame captures show
the hull coming over, upside down, and back. The spin keeps counting through a
transform on purpose: cutting it at the mode change snapped the hull from a half
turn back to level.
