# Player effects: the ship's wake leaves the ship

Branch: `main`.
Test runner: `/Applications/Godot.app/Contents/MacOS/Godot --headless tests/smoke_test.tscn`

## Specs

**S1.** The hull's presentation lives in `entities/player/player_effects.gd`
(`class_name PlayerEffects extends Node3D`): thruster plumes and cores, the exhaust
wake, the wingtip vapour ribbons, the aim beam, the burner's camera kick and the
wing-sweep mechanism.

**S2.** `player.gd` keeps the flight model, input, dash/transform/roll and i-frames,
HP, audio, the airframe build and the mode blend. It creates the effects node, hands
it the visual root and the model, and keeps the private forwarders the suite calls
by name.

**S3.** The dependency stays downward. `PlayerEffects` never names `Player`: the
sweep stops live where the pose applies them and `player.gd` aliases the constants
for the interceptor and the suite; the run's speeds and the acceleration arrive
through `set_speeds`; the pose is a `Callable` the ship installs, the same way the
city installs its `placer`.

**S4.** No behaviour change. The flames still follow the forward velocity, the kick
still decays at `THRUST_KICK_DECAY`, the burner ignition is still an edge with its
hysteresis, the wake density still answers acceleration rather than speed, the tips
still read airspeed with the roll jink subtracted, the vapour still clears outside
FIGHTER and mid-transform, and the beam still hangs in the ship's own space.

**S5.** The suite stops reading the private effects state: `effects().smoke` and
`effects().wingtip_trails` replace the `get("_smoke")` and `get("_wingtip_trails")`
pokes. Everything else keeps calling the same player methods.

**S6.** The suite is green on the final tree: 775 PASS, 0 FAIL, exit 0.

## Tasks

| ID | Spec | Status | Evidence |
|----|------|--------|----------|
| T1 | S1 | done | `entities/player/player_effects.gd`, 642 lines, 27 functions and the `WingtipTrail` class moved |
| T2 | S2, S3 | done | `player.gd` 1,556 → 1,103 lines; `effects()`, `set_speeds(...)`, the `pose` callable and six forwarders |
| T3 | S3 | done | no `Player.` reference remains in `player_effects.gd`; sweep stops aliased in `player.gd` |
| T4 | S5 | done | three call sites in `movement_suite.gd`, plus `tools/model_view.gd` and `tools/capture_frame.gd` |
| T5 | S4 | done | bodies compared against `HEAD`; the only rewrite is a field read becoming a parameter |
| T6 | S6 | done | 775 PASS / 0 FAIL / exit 0; only the turret roam distance, two lock timings and the camera px differ from the baseline |

## Log

**L1.** Request, verbatim: "sigue" — continuing the P1 movements after the arsenal
split.

**L2.** The seam is presentation, not physics. `player.gd` is 1,556 lines, but the
flight model and the action state machine are the parts every test pins with a
number; the wake, the vapour and the beam are pure output. Moving output first
shrinks the file without touching a single physics-timing assertion.

**L3.** The pose is a `Callable`, not a second owner. The wing sweep is a mechanism
with its own state (it travels at a fixed rate), so it belongs with the effects;
but what it moves is the hull — the nose pitch, the stance blend and the gunpod —
which the ship owns. `player.gd` installs `_apply_afterburner_pose` and the effects
calls it with the angle it computed. Same shape as the director's `placer`: the
thing that knows the rules does not own the thing the rules move.

**L4.** The first draft read `Player.MAX_SPEED`, `Player.ACCELERATION` and
`Player.WING_SWEEP_*` directly. That is an upward reference and a class cycle, so
the sweep stops moved to the effects file, the player aliases them for the
interceptor and the suite, and the speeds plus the acceleration became arguments.

**L5.** `_forward_speed`, `_burning`, `_wing_sweep` and `_base_fov` moved with the
wake: they are clocks for effects, not ship state. `_mode_blend` stayed, because it
is the pose the ship applies and the suite reads it.

**L6.** Not moved here: the airframe build (`_build_visual`, fill light, gunpod),
which is assembly rather than effect, and the bank, which also advances the roll.
Those are the next seams if `player.gd` keeps shrinking.
