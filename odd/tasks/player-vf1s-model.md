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

S3. The FIGHTER <-> GERWALK switch (0.28 s) poses the skeleton's leg and arm bones
    from `_mode_blend`, continuously, with no pop and no limb going through the
    hull. The existing angles (`LEG_THIGH_ANGLE`, `LEG_KNEE_ANGLE`, `LEG_SPLAY`,
    `ARM_*`) stay the tuning surface; only their axis mapping changes.

S4. Wing sweep follows speed, not the mode: the wings sit at `WING_SWEEP_FORWARD`
    (extended) at cruise and reach `WING_SWEEP_BACK` only above it, in both modes.
    The thresholds are `FIGHTER_SPEED`/`FIGHTER_BOOST_SPEED` in FIGHTER and
    `MAX_SPEED`/`BOOST_SPEED` in GERWALK, chosen by the mode being committed to.
    User, verbatim: "cuando el figther va a velocidad crusero que expanda las alas".

S5. The afterburner cones stay where the engines are: they are placed from the
    model's exhaust nozzles, not from `THRUSTER_X`/`THRUSTER_Z`, and still stretch
    with thrust and the acceleration kick.

S6. The model carries no gunpod, so the procedural GU-11 stays: held in the right
    hand in GERWALK, stowed on the centreline in FIGHTER. It is built as today and
    parented so the hand bone can move it.

S7. Nothing about the flight model, weapons, damage, i-frames, shockwave or aim
    beam changes. Only the visual construction changes.

S8. The model has to read from the actual game camera (50 units up, 75 degrees
    down): no z-fighting with the play plane, no silhouette lost at that distance.

S9. Import and load happen once. The headless smoke suite stays green and must not
    regress into loading the 47.8 MB model per test entity.

S10. The repository keeps only what the runtime needs: the GLB (textures are
     embedded) and no generated junk. `models/vf-1s/textures/` is dead weight and
     is not committed.

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
