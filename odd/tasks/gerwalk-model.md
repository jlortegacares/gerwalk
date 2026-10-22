# GERWALK model: a faithful VF-1 silhouette

Branch: `main`. Delivery: unreviewed (runtime ineligible for immutable review).
Tests: `./run.sh --headless tests/smoke_test.tscn`.

## Specs

S1. **The GERWALK model follows the reference photos.** "quiero el el player en
el modo gerwalk se use un modelo fiel a las imagenes adjuntas". The five attached
photos show a VF-1 Valkyrie in GERWALK: forward fuselage with the canopy, wings
level, two thick legs splayed down and outboard with the knees forward and large
forward-pointing feet, a long dark gunpod held beside and below the nose, tan
airframe with an off-white nose and pads and dark accents. FIGHTER behaviour is
out of scope and must not change.

S2. **The legs are nacelles, not hidden parts.** Each leg is a hip / knee / ankle
chain: a 0.34 x 0.42 thigh, a white collar at the knee, a 0.22 x 0.26 shin and a
0.58 x 0.42 white foot plus a dark heel. Total 1.70 units on a 4.15 hull (41%).
GERWALK swings them down and out with `LEG_THIGH_ANGLE = 46`, `LEG_KNEE_ANGLE = 24`
and `LEG_SPLAY = 28`, and the ankle plus a sole pivot level the plates so the feet
stay flat to the ground.

S3. **The feet and the pod are what the camera can see.** With the near-overhead
camera the wing plate hides anything inside its footprint, so the feet have to
land ahead of the leading edge: hips sit forward at `x 0.10` and the thigh reaches
forward as it drops, putting the ankles at `x 1.02, z +-1.05`, clear of the wing
and outboard of the 0.50 half-width hull. The gunpod rides in the right hand at
`x 0.91, z 0.62`, outboard and ahead of the shoulder, barrel reaching the nose.

S4. **The stance fits the hover height.** Legs 1.70 long cannot hang from a ship
that hovers 1.5 above the ground, so GERWALK lifts the whole airframe by
`GERWALK_LIFT = 0.35` and the soles keep a 0.45 clearance: measured at `-1.05`
against `GROUND_Y = -1.5`. A 32 degree bank is the worst case and still clears.

S5. **FIGHTER keeps the fighter.** The same legs fold straight back
(`hip.rotation.y = PI`, knee and ankle at zero) as the fuselage nacelles, feet
under the tail, and the gunpod stows on the centreline under the belly. No mesh is
swapped or hidden: every joint has a FIGHTER keyframe and a GERWALK keyframe and
`_mode_blend` carries them across.

S6. **The shape arrives with the rules.** The blend follows the mode the switch is
committing to, so the pose finishes changing exactly when `_mode` flips, not one
whole `TRANSFORM_TIME` later.

S7. **Nothing else regresses.** The smoke test's 99 pre-existing assertions stay
green and the 18 new silhouette checks join them, so the suite runs 117.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S2 | done | `_build_leg` / `_build_arm` / `_build_gunpod` + `_update_mode_pose` |
| T2 | S3 | done | ankles `x 1.02, z +-1.05`; pod `x 0.91, z 0.62` |
| T3 | S4 | done | `GERWALK_LIFT`; soles `-1.05` vs ground `-1.50` |
| T4 | S5 | done | FIGHTER fold `x -1.60`; pod stowed `z 0.00` |
| T5 | S6 | done | `visual_mode` in `_update_afterburner_visual`; blend 1.00 at the flip |
| T6 | S7 | done | smoke test green; `tools/model_view` renders the four views |
| T7 | S1 | done | 4 orthographic views + in-game capture reviewed against the photos |

## Log

L1. Request, verbatim: "quiero el el player en el modo gerwalk se use un modelo
fiel a las imagenes adjuntas". Five reference photos of a VF-1 GERWALK.

L2. Decisions taken while matching the photos. The legs are kept as the airframe's
nacelles instead of adding a separate mech body, because FIGHTER has to keep its
silhouette. The hip sits forward of the wing root on purpose: a bird-legged stance
whose feet land behind the wing's leading edge is invisible from a 75 degree
camera. The gunpod is a child of the visual, lerped between a stowed belly
position and the live right-hand position, so it never pops or re-parents. Gunmetal
is `(0.27, 0.28, 0.32)` rather than near-black: at this scale black faces merge
into a smudge.

L3. Bug found while testing the silhouette. `_mode_blend` targeted `_mode`, and
`_mode` only flips when `_transform_time` reaches zero, so the visual switch
started after the 0.28 s rule switch and finished at 0.56 s. The ship changed
rules while still looking like the old mode. The blend now targets
`_transform_target` while the transform runs and the test asserts the pose and the
rules land together.

L4. Iterations against the renders. Several passes through
`./run.sh tools/model_view.tscn -- --view quarter|side|front|top` thickened the
legs, added the white knee collar, flattened the feet with a sole pivot that
cancels the splay's roll, and grew the gunpod until it read as a rifle rather than
an antenna. `./run.sh tools/capture_frame.tscn` was the final judge, because the
ship is about 100 px in game.

L5. Verification. 117 assertions, green three times; the silhouette block checks
symmetry, stance width, leg drop, forward feet, ground clearance, the pod in the
hand, the FIGHTER fold, the stowed pod and the return to GERWALK. The longer
silhouette test exposed a pre-existing flake: `_test_damage_and_iframes` reset the
health but not `_invulnerable`, so a hit landed moments earlier swallowed the
first hit and the check passed or failed on timing. It now clears the frames too.

L6. Docs. `docs/combat-prototype.md` gains the GERWALK airframe section, the limb
and preview rows in the file map, the preview commands, and two known gaps
replacing the old "no legs" one (the pod does not drive the muzzle, and leg length
is bounded by the hover height).

L7. Risk: none. Geometry and posing only, no data, security, contract, concurrency
or delivery surface; FIGHTER's flight model is untouched and asserted unchanged.
