class_name Player
extends CharacterBody3D
## Twin-stick player: movement and aim are fully independent.
## Left stick / WASD moves. Right stick or mouse aims. Fire is decoupled from facing.
##
## Everything the player does happens on the y = 0 play plane. The third dimension
## is presentation only, so hitboxes stay planar and bullet patterns keep the
## readability the genre depends on.
##
## The ship has two modes. GERWALK is the twin-stick hover: translate in any
## direction, aim anywhere. FIGHTER is a nose-first interceptor: the stick asks
## for a heading, the hull takes a capped arc to it, thrust follows the nose and
## the gun is bolted to the airframe.
##
## The Camera3D is a child of this node and the rig never rotates, so the player
## sits in the middle of the screen no matter where it is on the planet's surface.
## The rig trails the body by a few pixels under thrust (a spring lag in
## player_camera.gd), which is the only time it leaves dead centre.

const MAX_SPEED: float = 26.8
## Snappy on purpose: cruise arrives in 26.8 / 420 = 0.064 s, inside the four
## frames a dense pattern gives you to read it and move. Long progressive
## acceleration is a flight sim luxury this genre cannot afford.
const ACCELERATION: float = 420.0
## Braking is heavier than thrust: 0.05 s from cruise to a full stop, three
## physics ticks. A ship that coasted would read as zero-gravity drift and make
## narrow gaps feel unfair.
const FRICTION: float = 540.0
const AIM_DEADZONE: float = 0.30
## Analog deadzone, deliberately low. At 0.10 a 20 percent tilt lands on roughly a
## tenth of cruise speed, which is the tap mode that threads a gap between bullets.
const MOVE_DEADZONE: float = 0.10

const MAX_HP: int = 6
const IFRAME_DURATION: float = 0.85

## Dash: 85 / 26.8 = 3.17x cruise, the middle of the 3.0-3.5 band. The duration
## drops to 0.12 s so the burst covers the same 10 units the old 64 speed did,
## only injected instantly instead of ramped.
const DASH_SPEED: float = 85.0
const DASH_DURATION: float = 0.12
const DASH_COOLDOWN: float = 0.85

## Double tap: a tap is the movement vector leaving the deadzone, so the gesture
## is two rising edges and needs no extra action or keyboard-only path. 0.28 s is
## a deliberate double tap; a longer window starts reading a direction change as
## one.
const DOUBLE_TAP_WINDOW: float = 0.28
## Both taps must point the same way, or a left-then-up flick would dash left
## instead of turning. 0.5 is a 60 degree cone, the width of a stick flick.
const DOUBLE_TAP_SIMILARITY: float = 0.5

## Angular game feel. Aim is instant, so the shot never lags the stick; the model
## turns at this rate so a flick reads as a snap roll instead of a teleport. At
## 1800 deg/s a 180 turn takes six frames.
const VISUAL_TURN_RATE: float = 1800.0
## Bank is presentation only: the capsule never rolls, so leaning 32 degrees
## cannot change what the player can graze. It is what sells a jet on a plane
## that has no banking at all.
const MAX_BANK: float = 32.0
const YAW_BANK: float = 10.0
## How far a fighter rolls into a full-rate turn. The airframe has no bank of its
## own, so this is the wing the player reads the turn from: a car yaws flat, a jet
## drops a wing and pulls.
const FIGHTER_BANK: float = 50.0
const BANK_RATE: float = 10.0
const THRUST_KICK_DECAY: float = 3.0

## Afterburner. Normal thrust tops out at MAX_SPEED; the burner trades reserve for
## a higher top speed, and the reserve only fills back while the burner is off.
const BOOST_SPEED: float = 42.0
const BOOST_ACCELERATION: float = 420.0
const TURBO_MAX: float = 100.0
const TURBO_DRAIN_PER_SECOND: float = 45.0
const TURBO_RECHARGE_PER_SECOND: float = 24.0
const FOV_BOOST_KICK: float = 5.0
const FOV_RATE: float = 18.0

## Thruster nozzles sit at the tail, one each side of the centreline.
## Modes. GERWALK keeps every number above. FIGHTER is the interceptor the spec
## calls "modo caza": 180% of the hover cruise, a capped turn and air drag instead
## of the snappy stop, because a fighter that stops on a dime is a hover with a
## different name.
enum Mode { GERWALK, FIGHTER }

const FIGHTER_SPEED: float = 48.2
const FIGHTER_BOOST_SPEED: float = 60.0
const FIGHTER_ACCELERATION: float = 900.0
## Spec band is 360-450 deg/s; the middle of the band leaves room for a trim nudge
## without ever exceeding the cap.
const FIGHTER_TURN_RATE: float = 400.0
const FIGHTER_STOP_TIME: float = 0.35
const FIGHTER_MIN_THROTTLE: float = 0.4
## A fighter never stalls to zero: with the stick released it keeps gliding at the
## throttle's own floor, so "no input" and "the lightest touch" are the same
## speed. 19.3 u/s, 40% of cruise.
const FIGHTER_STALL_SPEED: float = FIGHTER_SPEED * FIGHTER_MIN_THROTTLE
## Drag is derived, not tuned: the airspeed falls from cruise to the stall speed
## in the same 0.35 s the old full stop took, so the fade feels identical and only
## the floor moved. From the burner the same drag takes 0.44 s.
const FIGHTER_DRAG: float = (FIGHTER_SPEED - FIGHTER_STALL_SPEED) / FIGHTER_STOP_TIME
## How hard the airframe grips the air sideways, as a lateral acceleration. It
## caps how fast the course can follow the nose: 190 / airspeed at cruise is about
## 226 deg/s against a 400 deg/s nose, so a hard reversal opens a real skid, and
## at stall speed the same grip turns the course faster than the nose can.
const FIGHTER_GRIP: float = 190.0
## The airframe has no constant wind. A world-space breeze made one heading
## cruise 15% faster than its opposite and swept the wings on that heading alone,
## which reads as a bug in the flight model rather than as weather.
##
## The transformation bleeds momentum at the old fighter drag, so the 0.28 s
## switch feels exactly as it did before the flight model grew a stall speed.
const TRANSFORM_DRAG: float = FIGHTER_SPEED / FIGHTER_STOP_TIME
const FIGHTER_TRIM_DEGREES: float = 8.0
const FIGHTER_YAW_TRIM: float = 60.0
const FIGHTER_ROLL_TIME: float = 0.20
const FIGHTER_ROLL_SPEED: float = 55.0
## The jink and the roll are two clocks. 0.20 s is the rule: the sideways step and
## the i-frames it buys. The airframe's turn-over is presentation, and at 0.20 s it
## was twelve frames of blur that read as a teleport. 0.45 s is the same 360
## degrees at 2.25x the time, long enough to see the wings come over, and it
## changes nothing about the distance covered or how long the dodge protects.
const FIGHTER_ROLL_ANIM_TIME: float = 0.45
const FIGHTER_NOSE_PITCH: float = -5.0
const TRANSFORM_TIME: float = 0.28

## The nose is long, so the muzzle and the aim beam start past its tip.
const MUZZLE_DISTANCE: float = 3.05
const BEAM_START: float = 2.60
const BEAM_LENGTH: float = 2.0

## Wing sweep in degrees: nearly straight at rest, a clear contraction at cruise,
## and swept back when the burner is lit. The wing already carries about 27 degrees
## of leading-edge sweep, so the tip ends up near 65 degrees at full burn.
const WING_SWEEP_FORWARD: float = 0.0
const WING_SWEEP_CRUISE: float = 14.0
const WING_SWEEP_BACK: float = 38.0
## Degrees per second the wings travel between those stops. The throttle changes in
## a couple of frames, so the wing needs its own clock to read as a mechanism
## instead of a snap: 0 to full sweep takes a bit over half a second.
const WING_SWEEP_RATE: float = 60.0

## Desert airframe from the reference sheet: the gunpod is the only piece still
## built by hand, so only its two materials survive.
const ACCENT_COLOR: Color = Color(0.34, 0.22, 0.17, 1.0)
const BEAM_COLOR: Color = Color(0.24, 0.9, 0.8, 1.0)
## The GU-11 gunpod is the one near-black piece on the airframe. It is not pure
## black: at this scale the faces have to separate or the rifle reads as a smudge.
const GUNMETAL_COLOR: Color = Color(0.27, 0.28, 0.32, 1.0)

## GERWALK is the VF-1's bird-legged stance: the model's legs are the nacelles and
## the skeleton swings them down and out. They reach further below the hull than
## the placeholder's did, so the whole airframe rides higher in the stance to keep
## the feet off the planet.
const GERWALK_LIFT: float = 0.55

## Where the gunpod rides in FIGHTER: centreline, under the belly, which is where
## a VF-1 carries it.
const GUNPOD_STOWED: Vector3 = Vector3(0.48, -0.27, 0.0)
const GUNPOD_LENGTH: float = 0.90
const GUNPOD_BARREL: float = 0.46

## The exhaust wake. The puffs are dropped in world space and left behind, so the
## gap between them -- and therefore the length of the trail -- grows with the
## speed on its own. Only the density needs a knob: `amount_ratio` drops puffs
## without reallocating the buffer or restarting the emission.
##
## The density answers a change in speed, not the speed itself. A steady throttle
## leaves the nozzles clean, and what the wake marks is the ship climbing: a puff
## is born at the nozzle and stays there, so a burst during the climb leaves a
## short smear behind the hull and then nothing. That also keeps a standing ship
## from wearing its own trail -- from the game camera the near leg sat behind the
## plume, and a grey veil over a white leg reads as a shadow the other leg does
## not have.
const SMOKE_COLOR: Color = Color(0.74, 0.79, 0.85, 1.0)
const SMOKE_AMOUNT: int = 450
const SMOKE_LIFETIME: float = 0.50
const SMOKE_PUFF: float = 0.80
const SMOKE_DENSITY_HIGH: float = 0.95

## Wingtip vapour, the speed cue. The cone that used to point the way is gone; a
## pair of trails off the tips says "this is moving" without painting a shape over
## the arena.
##
## The trail is a ribbon, not a particle wake. Puffs can only ever be as dense as
## the rate they spawn at, and at 60 u/s that leaves visible gaps, so the tips read
## as a dotted line. A strip rebuilt through the tip's own history is continuous by
## construction: two vertices per sample, no gaps to tune away.
const WINGTIP_COLOR: Color = Color(0.52, 0.86, 1.0, 0.9)
const WINGTIP_WIDTH: float = 0.18
## Where the FIGHTER vapour starts, as a fraction of cruise. It cannot wait for the
## burner any more: from the middle of the throttle up the tips are already saying
## the ship is moving, and the burner is just the top of that range. FIGHTER is the
## only mode with a trail at all, so this is the only curve there is.
const WINGTIP_SPEED_FLOOR: float = 0.55
## Longer-lived than the exhaust wake on purpose: the two lines have to outlast the
## grey rope the nozzles drop, or they end inside it and there is nothing to see.
const WINGTIP_LIFETIME: float = 0.65
## Distance between samples. Below this the head is just moved instead of a new
## vertex being added, so a slow ship does not pile up points on one spot.
const WINGTIP_SPACING: float = 0.30

## The counter-light that keeps a mirrored airframe reading evenly. Level and tint
## only; where it points is `_build_fill_light`'s story. It is cool because it
## stands in for sky bounce rather than for a second sun.
const FILL_ENERGY: float = 0.45
const FILL_COLOR: Color = Color(0.62, 0.72, 0.95)

@export var bullet_scene: PackedScene
@export var impact_scene: PackedScene

var camera: Camera3D

var _weapons: WeaponSystem

var _hp: int = MAX_HP
var _aim_direction: Vector3 = Vector3.RIGHT
var _invulnerable: float = 0.0
var _dash_time: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector3 = Vector3.RIGHT
## Time left in the double-tap window and the direction of the tap that opened
## it. `_move_engaged` is the previous frame's stick state, which is what turns
## the polled vector into an edge.
var _tap_timer: float = 0.0
var _tap_direction: Vector2 = Vector2.ZERO
var _move_engaged: bool = false
var _alive: bool = true

var _visual_yaw: float = 0.0
var _visual_yaw_prev: float = 0.0
var _bank: float = 0.0
var _forward_speed: float = 0.0
var _thrust_kick: float = 0.0
## Whether the burner is already lit. The ignition is an edge, not a level: the
## sound belongs to crossing into the burner, not to every frame spent in it.
var _burning: bool = false
## Wing angle the pose was last built with. The wings travel to their target at a
## fixed rate instead of following the throttle frame by frame: the fighter reaches
## cruise in a handful of frames, so a derived angle would snap.
var _wing_sweep: float = 0.0

var _mode: Mode = Mode.GERWALK
var _transform_time: float = 0.0
var _transform_target: Mode = Mode.GERWALK
var _mode_blend: float = 0.0
var _heading: Vector3 = Vector3.RIGHT
## The side the last roll went to, kept between rolls. A neutral stick repeats it
## instead of snapping to the right, so the dodge is a direction the player
## remembers rather than one the stick has to re-state every time.
var _roll_side: float = 1.0
## The jink's step in the airframe's own frame at the moment it was asked for:
## x along the nose, y to the right. A double tap can point anywhere, so the push
## is composed from both every frame and still turns with the nose.
var _roll_local: Vector2 = Vector2(0.0, 1.0)
var _roll_anim_time: float = 0.0
## The lateral push the barrel roll added last frame. It is not airspeed, so the
## flight model subtracts it before reading the air: otherwise every jink tops up
## the previous one and a 55 u/s roll ends up at 390.
var _roll_velocity: Vector3 = Vector3.ZERO

var _turbo: float = TURBO_MAX
var _boosting: bool = false
var _turbo_locked: bool = false
var _turbo_shown: float = TURBO_MAX
var _base_fov: float = 58.0

var _visual: Node3D
var _aim_beam: MeshInstance3D
var _model: PlayerModel
var _accent_material: StandardMaterial3D
var _gunpod: Node3D
var _gunmetal_material: StandardMaterial3D
## Nozzle positions for the frame, in `_visual` space. They move with the legs,
## so the flames are rebuilt from them every frame instead of a fixed offset.
var _nozzle_anchors: Array[Vector3] = []
var _thruster_plumes_material: StandardMaterial3D
var _thruster_cores_material: StandardMaterial3D
var _thruster_plumes: Array[MeshInstance3D] = []
var _thruster_cores: Array[MeshInstance3D] = []
var _smoke: Array[GPUParticles3D] = []
var _wingtip_trails: Array[WingtipTrail] = []
var _wingtip_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"player")
	camera = %Camera
	_base_fov = camera.fov
	_build_visual()
	_build_thrusters()
	_build_smoke()
	_build_wingtip_trails()
	_build_aim_beam()

	_weapons = WeaponSystem.new()
	_weapons.name = "Weapons"
	_weapons.setup(bullet_scene)
	add_child(_weapons)

	GlobalEventBus.player_health_changed.emit.call_deferred(_hp, MAX_HP)
	GlobalEventBus.player_turbo_changed.emit.call_deferred(_turbo, TURBO_MAX)
	GlobalEventBus.player_mode_changed.emit.call_deferred(mode_name())


## The hum belongs to this ship, so it goes when the ship does: a restart or a
## return to the menu must not leave the engine running over the new scene.
func _exit_tree() -> void:
	Sfx.engine(false)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not _alive:
		return

	if Input.is_action_just_pressed(&"transform") and _transform_time <= 0.0:
		_start_transform()

	_tick_double_tap(delta)

	if Input.is_action_just_pressed(&"dash") and _dash_cooldown <= 0.0:
		_start_dash()

	if _dash_time > 0.0 and _mode == Mode.GERWALK:
		velocity = _dash_direction * DASH_SPEED
		velocity.y = 0.0
		move_and_slide()
	elif _transform_time > 0.0:
		# Mid-transformation the ship keeps its momentum but takes no thrust and
		# fires nothing: the switch is a commitment, not a free dodge or a reset.
		velocity = velocity.move_toward(Vector3.ZERO, TRANSFORM_DRAG * 0.35 * delta)
		velocity.y = 0.0
		move_and_slide()
	elif _mode == Mode.FIGHTER:
		_move_fighter(delta)
	else:
		_move_gerwalk(delta)

	_update_aim(delta)
	_update_bank(delta)
	_update_weapons(delta)
	_update_afterburner_visual(delta)
	_update_wingtip_trails(delta)
	# The hum follows the ship: one continuous voice whose pitch and level track the
	# airspeed, instead of a loop that restarts on every mode change.
	Sfx.engine(true, velocity.length() / BOOST_SPEED)


func _move_gerwalk(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down", MOVE_DEADZONE
	)
	var thrusting: bool = input_direction.length_squared() > 0.0
	_update_boost(delta, thrusting)

	var speed: float = BOOST_SPEED if _boosting else MAX_SPEED
	var acceleration: float = BOOST_ACCELERATION if _boosting else ACCELERATION
	# Screen up maps to -Z, so the ring reads the same as it did in 2D.
	var target: Vector3 = Vector3(input_direction.x, 0.0, input_direction.y) * speed

	if thrusting:
		velocity = velocity.move_toward(target, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, FRICTION * delta)

	velocity.y = 0.0
	move_and_slide()


## Fighter: the stick asks for a heading and the hull takes the short arc to it at
## a capped rate, so a reversal is a 0.45 s bank instead of a snap turn.
##
## The air, not the ground, is what the airframe answers to. Airspeed is the
## velocity minus the jink, and it has two properties: where it points and how
## fast it goes. The throttle owns the speed and the airframe owns how quickly the
## course may follow the nose, which is the whole flight model in one line. Drive
## the two axes independently instead and a turn manufactures airspeed out of
## nothing.
##
## Every heading flies the same speed. The model is deliberately free of a
## world-space wind: one made a tailwind run 15% faster than the same run upwind,
## and the visual read that as wings swept on one side of the screen only.
##
## Releasing the stick is not a stop: the speed settles at the stall speed, so the
## ship keeps gliding wherever its nose happens to point.
func _move_fighter(delta: float) -> void:
	var stick: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down", MOVE_DEADZONE
	)
	var throttle: float = clampf(stick.length(), 0.0, 1.0)
	var thrusting: bool = throttle > 0.0
	_update_boost(delta, thrusting)

	# The right stick is not an aiming device in this mode. It bends the requested
	# course by a few degrees, which is enough to line up a pass without ever
	# taking the gun off the nose.
	# A roll is a commitment: the trim must not steer the nose while the ship is
	# busy stepping sideways, or the jink bends the course it was dodging.
	var trim: float = 0.0
	if _dash_time <= 0.0:
		trim = Input.get_axis(&"aim_left", &"aim_right")
	var yaw: float = atan2(-_heading.z, _heading.x)

	if thrusting:
		var requested: Vector3 = Vector3(stick.x, 0.0, stick.y).normalized()
		var target_yaw: float = (
			atan2(-requested.z, requested.x) + deg_to_rad(FIGHTER_TRIM_DEGREES) * trim
		)
		var step: float = deg_to_rad(FIGHTER_TURN_RATE * throttle) * delta
		yaw += clampf(angle_difference(yaw, target_yaw), -step, step)
	elif not is_zero_approx(trim):
		# Coasting: the trim is the only thing steering, and it turns slowly.
		yaw += deg_to_rad(FIGHTER_YAW_TRIM) * trim * delta

	_heading = Vector3(cos(yaw), 0.0, -sin(yaw))
	var right: Vector3 = Vector3(-_heading.z, 0.0, _heading.x)

	# Airspeed is the velocity through the air: the ground velocity minus the jink,
	# which is a step the airframe takes rather than air it flies through. Tracking
	# it as a course plus a magnitude is what keeps the turn's own geometry from
	# being mistaken for thrust.
	var air: Vector3 = velocity - _roll_velocity
	var airspeed: float = air.length()
	var course: float = atan2(-air.z, air.x) if airspeed > 0.001 else yaw

	# The nose may outrun the course. The grip is a lateral acceleration, so it
	# turns the course faster at low speed and softer at cruise: that lag is the
	# skid, and it is why a reversal arcs instead of pivoting on the spot.
	var slew: float = (FIGHTER_GRIP / maxf(airspeed, 1.0)) * delta
	course += clampf(angle_difference(course, yaw), -slew, slew)

	var cruise: float = FIGHTER_BOOST_SPEED if _boosting else FIGHTER_SPEED
	# With the stick released there is still a floor: the ship glides, it does not
	# hang. It is the throttle's own minimum, so no input and a hair of input give
	# the same speed and there is no seam between them.
	var wanted: float = (
		cruise * (FIGHTER_MIN_THROTTLE + (1.0 - FIGHTER_MIN_THROTTLE) * throttle)
		if thrusting
		else FIGHTER_STALL_SPEED
	)
	var rate: float = FIGHTER_ACCELERATION if thrusting else FIGHTER_DRAG
	airspeed = move_toward(airspeed, wanted, rate * delta)

	# The jink is a push that ramps in and out, so it never snaps the velocity at
	# either end. It is composed from the airframe's own axes, so a lateral step
	# keeps turning with the nose and a forward one reads as a burst along it
	# without ever becoming airspeed: `_roll_velocity` is subtracted before the
	# air is measured.
	var push: Vector3 = Vector3.ZERO
	if _dash_time > 0.0:
		var progress: float = 1.0 - _dash_time / FIGHTER_ROLL_TIME
		var step: float = sin(progress * PI) * FIGHTER_ROLL_SPEED
		push = (_heading * _roll_local.x + right * _roll_local.y) * step

	velocity = Vector3(cos(course), 0.0, -sin(course)) * airspeed + push
	velocity.y = 0.0
	_roll_velocity = push
	move_and_slide()


## A transformation is two things at once: the silhouette changes and the rules
## change. Locking the gun and cutting thrust for 0.28 s is what stops a mode
## switch from being a free dodge on the same button as an escape.
func _start_transform() -> void:
	_transform_target = Mode.GERWALK if _mode == Mode.FIGHTER else Mode.FIGHTER
	_transform_time = TRANSFORM_TIME
	_thrust_kick = 1.0
	# A switch mid-roll must not leave the jink subtracted from the next frame's
	# airspeed.
	_roll_velocity = Vector3.ZERO
	_spawn_impact()
	GlobalEventBus.camera_shake_requested.emit(0.35)
	Sfx.play(&"transform")


func mode() -> Mode:
	return _mode


func is_fighter() -> bool:
	return _mode == Mode.FIGHTER


func mode_name() -> String:
	return "FIGHTER" if _mode == Mode.FIGHTER else "GERWALK"


## Where the nose points, in world axes. The visual yaw follows this vector, so a
## radar marker built from it shows where the ship is pointing rather than where
## the current carries it.
func nose_direction() -> Vector3:
	return _aim_direction


## The burner is a tank, not a cooldown: it drains while it is being used and
## fills back whenever it is not. It only burns when the ship is actually
## thrusting, so the reserve measures ground covered instead of button time.
## Emptying it latches until the button is released; re-arming on a partial
## refill would stutter the ship between two speeds while held.
func _update_boost(delta: float, thrusting: bool) -> void:
	var pressed: bool = Input.is_action_pressed(&"boost")
	if not pressed:
		_turbo_locked = false

	_boosting = pressed and thrusting and not _turbo_locked and _turbo > 0.0

	if _boosting:
		_turbo = maxf(_turbo - TURBO_DRAIN_PER_SECOND * delta, 0.0)
		if _turbo <= 0.0:
			_turbo_locked = true
			_boosting = false
	else:
		_turbo = minf(_turbo + TURBO_RECHARGE_PER_SECOND * delta, TURBO_MAX)

	_emit_turbo()


## One event per whole reserve unit instead of one per physics frame: the bar is
## 234 px wide, so a unit is under 2.5 px. Smooth to the eye, quiet on the bus.
func _emit_turbo() -> void:
	var shown: float = roundf(_turbo)
	if is_equal_approx(shown, _turbo_shown):
		return
	_turbo_shown = shown
	GlobalEventBus.player_turbo_changed.emit(_turbo, TURBO_MAX)


## The wake: two nested cones per nozzle, plus the wing sweep. The flame follows
## the forward component of the velocity, not the input: a ship strafing with its
## nose elsewhere is not burning towards its nose, and a flame that grew anyway
## would be a lie. The camera kicks out a little while burning, which reads as
## speed on a featureless surface.
func _update_afterburner_visual(delta: float) -> void:
	var forward_speed: float = maxf(velocity.dot(_aim_direction), 0.0)
	var thrust: float = clampf(forward_speed / BOOST_SPEED, 0.0, 1.0)
	var heat: float = clampf(
		(forward_speed - MAX_SPEED) / (BOOST_SPEED - MAX_SPEED), 0.0, 1.0
	)
	# The burner announces itself once, on the way in. Hysteresis, because a ship
	# riding the threshold would otherwise stutter the ignition every few frames.
	var burning: bool = heat > 0.08 if not _burning else heat > 0.02
	if burning and not _burning and delta > 0.0:
		Sfx.play(&"afterburner")
	_burning = burning

	# A kick is a flash, not a speed curve: opening the throttle past a walk, or
	# punching the dash, spikes the plumes and then decays in about a third of a
	# second. It is the only cue that the ship has weight at all.
	var accel: float = (forward_speed - _forward_speed) / maxf(delta, 0.0001)
	_forward_speed = forward_speed
	_thrust_kick = maxf(_thrust_kick, clampf(accel / ACCELERATION, 0.0, 1.0))
	_thrust_kick = move_toward(_thrust_kick, 0.0, THRUST_KICK_DECAY * delta)
	var kick: float = _thrust_kick

	# The silhouette is the mode read from above: FIGHTER dips the nose, GERWALK
	# holds it level like a hovering airframe. The blend follows the mode the switch
	# is committing *to*, not the mode the rules still use, so the shape finishes
	# changing exactly when the rules flip instead of one whole switch later.
	var visual_mode: Mode = _transform_target if _transform_time > 0.0 else _mode
	var target_blend: float = 1.0 if visual_mode == Mode.FIGHTER else 0.0
	_mode_blend = move_toward(_mode_blend, target_blend, delta / TRANSFORM_TIME)
	_visual.rotation.z = deg_to_rad(FIGHTER_NOSE_PITCH) * _mode_blend

	# The wings answer speed, not the mode: they contract as the ship reaches cruise
	# and sweep the rest of the way once it is pushed past it, which is where the
	# burner lives. The thresholds come from the mode being committed to, not from
	# the blend, so a transformation never makes the wings flap back and forth on
	# the way.
	var fighter: bool = visual_mode == Mode.FIGHTER
	var cruise: float = FIGHTER_SPEED if fighter else MAX_SPEED
	var ceiling: float = FIGHTER_BOOST_SPEED if fighter else BOOST_SPEED
	var target_sweep: float
	if forward_speed <= cruise:
		var approach: float = clampf(forward_speed / maxf(cruise, 0.001), 0.0, 1.0)
		# Squared, not linear: a swing wing keeps its span while it is slow and
		# folds only as it closes on cruise. Linear put the wings a third of the
		# way back at a walk, which read as the sweep answering the throttle
		# position rather than the speed.
		target_sweep = lerpf(WING_SWEEP_FORWARD, WING_SWEEP_CRUISE, approach * approach)
	else:
		var past: float = clampf(
			(forward_speed - cruise) / maxf(ceiling - cruise, 0.001), 0.0, 1.0
		)
		target_sweep = lerpf(WING_SWEEP_CRUISE, WING_SWEEP_BACK, past)
	# The angle is a mechanism, not a readout: the wing travels to the stop at
	# `WING_SWEEP_RATE` and the throttle is free to jump. A zero delta means "pose
	# the current speed", which is what the tools use for a still.
	if delta > 0.0:
		_wing_sweep = move_toward(_wing_sweep, target_sweep, WING_SWEEP_RATE * delta)
	else:
		_wing_sweep = target_sweep
	_update_mode_pose(_wing_sweep)

	# The flames hang off the nozzles, and the nozzles are the feet: the stance
	# swings them forward, so the anchors are read back after the pose.
	_nozzle_anchors = _model.nozzle_anchors() if _model != null else []
	_layout_flames(_thruster_plumes, 0.35 + thrust * 1.65 + kick * 1.10)
	_layout_flames(_thruster_cores, 0.28 + thrust * 1.00 + kick * 0.70)
	_update_smoke(accel)

	_thruster_plumes_material.albedo_color = Color(
		lerpf(0.22, 0.5, heat),
		lerpf(0.6, 0.85, heat),
		1.0,
		clampf(0.08 + thrust * 0.24 + kick * 0.30, 0.0, 0.8)
	)
	_thruster_cores_material.albedo_color = Color(
		0.88, 0.98, 1.0, clampf(0.18 + thrust * 0.45 + kick * 0.25, 0.0, 0.95)
	)

	if camera == null:
		return
	var target_fov: float = _base_fov + (FOV_BOOST_KICK if _boosting else 0.0)
	camera.fov = move_toward(camera.fov, target_fov, FOV_RATE * delta)


## The cone's tip trails behind the nozzle, so growing it must move it back by the
## same amount or the base would detach from the hull.
func _layout_flames(flames: Array[MeshInstance3D], length: float) -> void:
	for flame in flames:
		var nozzle: int = int(flame.get_meta("nozzle", 0))
		var anchor: Vector3 = Vector3.ZERO
		if nozzle < _nozzle_anchors.size():
			anchor = _nozzle_anchors[nozzle]
		flame.scale = Vector3(1.0, length, 1.0)
		flame.position = Vector3(anchor.x - length * 0.5, anchor.y, anchor.z)


## The dash gesture. A tap is the movement vector leaving the deadzone, so two
## rising edges inside the window are a double tap and the second one points
## where the dash goes. Reading the polled vector instead of `just_pressed` keeps
## the gesture analog: on a stick a tap is a short deflection, not a click.
func _tick_double_tap(delta: float) -> void:
	_tap_timer = maxf(_tap_timer - delta, 0.0)
	var stick: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down", MOVE_DEADZONE
	)
	var engaged: bool = stick.length_squared() > 0.0
	if engaged and not _move_engaged:
		var direction: Vector2 = stick.normalized()
		if _tap_timer > 0.0 and direction.dot(_tap_direction) >= DOUBLE_TAP_SIMILARITY:
			# The gesture is spent either way: a tap that lands on cooldown is a
			# dash the player already used, not one to queue.
			_tap_timer = 0.0
			_tap_dash(direction)
		else:
			_tap_timer = DOUBLE_TAP_WINDOW
			_tap_direction = direction
	_move_engaged = engaged


func _tap_dash(direction: Vector2) -> void:
	if _dash_cooldown > 0.0:
		return
	if _mode == Mode.FIGHTER:
		_start_barrel_roll(direction)
		return
	_start_dash(direction)


## `direction` is the stick that asked for the dash, already deadzoned. It is
## empty when the button fired on a centred stick, which is the "dash down the
## nose" case.
func _start_dash(direction: Vector2 = Vector2.ZERO) -> void:
	if _mode == Mode.FIGHTER:
		_start_barrel_roll()
		return

	Sfx.play(&"dash")
	var input_direction: Vector2 = direction
	if input_direction.length_squared() <= 0.0:
		input_direction = Input.get_vector(
			&"move_left", &"move_right", &"move_up", &"move_down", MOVE_DEADZONE
		)
	var flat: Vector3 = Vector3(input_direction.x, 0.0, input_direction.y)
	_dash_direction = flat.normalized() if flat.length_squared() > 0.0 else _aim_direction
	_dash_time = DASH_DURATION
	_dash_cooldown = DASH_COOLDOWN
	# The nozzle flash outlives the 0.12 s burst, then decays on its own.
	_thrust_kick = 1.0
	_spawn_impact()


## In Fighter the dash is the roll the spec puts on the right stick: the ship steps
## without changing where it points, and the airframe spins around its own nose.
## The capsule never spins, so it is a jink with i-frames, not a free turn.
##
## `tapped` is the stick a double tap asked for, in the same world axes the flight
## model reads, so any direction is a valid jink and diagonals are just a
## direction. It is converted to the airframe's own frame, which is what lets the
## step turn with the nose. Without a tap (the button) the aim axis picks the
## side, and a centred stick repeats the last one instead of defaulting right.
func _start_barrel_roll(tapped: Vector2 = Vector2.ZERO) -> void:
	Sfx.play(&"dash")
	var world: Vector3 = Vector3.ZERO
	if tapped.length_squared() > 0.0:
		world = Vector3(tapped.x, 0.0, tapped.y).normalized()
	var right: Vector3 = Vector3(-_heading.z, 0.0, _heading.x)
	if world.length_squared() <= 0.0:
		var side: float = signf(Input.get_axis(&"aim_left", &"aim_right"))
		if is_zero_approx(side):
			side = _roll_side
		_roll_side = side
		_roll_local = Vector2(0.0, side)
	else:
		_roll_local = Vector2(world.dot(_heading), world.dot(right))
		# The spin has to agree with the step. A straight-ahead jink has no side
		# of its own, so it keeps the one it last rolled to.
		var spin_side: float = signf(_roll_local.y)
		if not is_zero_approx(spin_side):
			_roll_side = spin_side
	_dash_time = FIGHTER_ROLL_TIME
	_roll_anim_time = FIGHTER_ROLL_ANIM_TIME
	_dash_cooldown = DASH_COOLDOWN
	_thrust_kick = 1.0
	_spawn_impact()


## Banking is derived from the body, not from the input: lateral drift relative to
## the nose rolls the hull into that drift, and a fast nose turn adds a smaller
## lean into the turn. Both settle back to level once the movement stops.
func _update_bank(delta: float) -> void:
	var fighter: bool = _mode == Mode.FIGHTER
	var right: Vector3 = Vector3(-_aim_direction.z, 0.0, _aim_direction.x)
	var lateral: float = clampf(velocity.dot(right) / MAX_SPEED, -1.0, 1.0)
	# The rate has to be read against the rate *this mode* can turn at. A fighter
	# noses round at 400 deg/s and the aiming ring at 1800, so normalising both
	# against the ring would leave the fighter banking a quarter as far as asked.
	var turn_rate: float = FIGHTER_TURN_RATE if fighter else VISUAL_TURN_RATE
	var yaw_rate: float = 0.0
	if delta > 0.0:
		yaw_rate = clampf(
			angle_difference(_visual_yaw_prev, _visual_yaw)
			/ delta
			/ deg_to_rad(turn_rate),
			-1.0,
			1.0
		)
	_visual_yaw_prev = _visual_yaw

	# The barrel roll owns the roll axis for its own 0.45 s, which outlives the
	# 0.20 s jink: the ship has already stepped aside before the airframe has
	# finished coming over, and the bank must not fight it. The sign follows the
	# side, so a left dodge rolls left and the animation agrees with the step.
	if _roll_anim_time > 0.0:
		var spun: float = 1.0 - _roll_anim_time / FIGHTER_ROLL_ANIM_TIME
		_visual.rotation.x = _roll_side * spun * TAU
		_bank = 0.0
		return

	# A fighter leans into the turn with the whole wing, because in this mode the
	# entire bank comes from the turn: the drift term would pick up the skid, which
	# is the course trailing the nose rather than the ship leaning, and bank twice
	# for one turn.
	var target: float
	if fighter:
		target = -deg_to_rad(FIGHTER_BANK) * yaw_rate
	else:
		target = deg_to_rad(MAX_BANK * lateral - YAW_BANK * yaw_rate)
	_bank = lerpf(_bank, target, 1.0 - exp(-BANK_RATE * delta))
	_visual.rotation.x = _bank


func _update_aim(delta: float) -> void:
	if _mode == Mode.FIGHTER:
		# The gun is bolted to the airframe: the stick angle, the mouse and the
		# right stick all stop aiming the moment the wings sweep back.
		_aim_direction = _heading
	else:
		var stick_aim: Vector2 = Input.get_vector(
			&"aim_left", &"aim_right", &"aim_up", &"aim_down"
		)

		if stick_aim.length() > AIM_DEADZONE:
			_aim_direction = Vector3(stick_aim.x, 0.0, stick_aim.y).normalized()
		else:
			var to_mouse: Vector3 = _mouse_direction_on_plane()
			if to_mouse.length_squared() > 0.0001:
				_aim_direction = to_mouse

	# The shot follows _aim_direction this same frame; only the model eases in.
	var target_yaw: float = atan2(-_aim_direction.z, _aim_direction.x)
	if delta > 0.0:
		# angle_difference keeps the turn on the short arc; a raw move_toward would
		# spin the long way around whenever the aim crosses the -X seam.
		var step: float = deg_to_rad(VISUAL_TURN_RATE) * delta
		_visual_yaw += clampf(angle_difference(_visual_yaw, target_yaw), -step, step)
		_visual_yaw = wrapf(_visual_yaw, -PI, PI)
	else:
		_visual_yaw = target_yaw
	_visual.rotation.y = _visual_yaw
	_aim_beam.position = _aim_direction * (BEAM_START + BEAM_LENGTH * 0.5)
	_aim_beam.rotation.y = atan2(_aim_direction.x, _aim_direction.z)


## Projects the mouse onto the orbital plane so aim works with a perspective
## camera. Returns a zero vector when the ray is parallel to the plane.
func _mouse_direction_on_plane() -> Vector3:
	var camera_node: Camera3D = get_viewport().get_camera_3d()
	if camera_node == null:
		return Vector3.ZERO

	var mouse: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera_node.project_ray_origin(mouse)
	var normal: Vector3 = camera_node.project_ray_normal(mouse)

	if absf(normal.y) < 0.0001:
		return Vector3.ZERO

	var distance: float = -origin.y / normal.y
	if distance <= 0.0:
		return Vector3.ZERO

	var point: Vector3 = origin + normal * distance
	var flat: Vector3 = point - global_position
	flat.y = 0.0
	return flat.normalized()


## Weapon selection lives here because the player owns its input; the numbers and
## the firing live in WeaponSystem. Selecting never interrupts fire: the next tick
## fires the new weapon immediately.
func _update_weapons(delta: float) -> void:
	if Input.is_action_just_pressed(&"weapon_1"):
		_weapons.select(Arsenal.Kind.VULCAN)
	elif Input.is_action_just_pressed(&"weapon_2"):
		_weapons.select(Arsenal.Kind.LASER)
	elif Input.is_action_just_pressed(&"weapon_3"):
		_weapons.select(Arsenal.Kind.PLASMA)
	elif Input.is_action_just_pressed(&"weapon_next"):
		_weapons.cycle(1)
	elif Input.is_action_just_pressed(&"weapon_prev"):
		_weapons.cycle(-1)

	var wants_fire: bool = Input.is_action_pressed(&"fire")
	if _mode == Mode.GERWALK:
		# The right stick doubles as fire in the hover, but in Fighter it is a
		# course correction and must never pull the trigger.
		var stick_aim: Vector2 = Input.get_vector(
			&"aim_left", &"aim_right", &"aim_up", &"aim_down"
		)
		wants_fire = wants_fire or stick_aim.length() > AIM_DEADZONE
	if _transform_time > 0.0:
		wants_fire = false

	if Input.is_action_just_pressed(&"bomb") and _transform_time <= 0.0:
		_weapons.fire_bomb(global_position)

	# The decoy is defensive, but it is still the ship acting: the transform lock
	# takes it offline with everything else so the switch keeps costing something.
	if Input.is_action_just_pressed(&"decoy") and _transform_time <= 0.0:
		_weapons.drop_decoy(global_position)

	# The missile rack is a hold, not a press: the button marks while it is down and
	# pays out when it comes up. Transform takes the rack offline with everything
	# else the ship fires.
	var wants_missile: bool = Input.is_action_pressed(&"missile") and _transform_time <= 0.0

	_weapons.tick(
		delta,
		global_position,
		global_position + _aim_direction * MUZZLE_DISTANCE,
		_aim_direction,
		wants_fire,
		_mode == Mode.FIGHTER,
		wants_missile,
		_wing_hardpoints()
	)


## The wing hardpoints in world space. Read from the model every frame, because the
## sweep moves them: a salvo fired with the wings folded leaves from the folded
## wing, not from where the wing was at cruise.
func _wing_hardpoints() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _model == null:
		return points
	for point in _model.wing_anchors():
		points.append(_visual.to_global(point))
	return points


func _tick_timers(delta: float) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_dash_time = maxf(_dash_time - delta, 0.0)
	# The spin keeps counting even through a transform: cutting it when the
	# airframe changes would snap the hull back from a half turn to level.
	_roll_anim_time = maxf(_roll_anim_time - delta, 0.0)

	if _transform_time > 0.0:
		_transform_time = maxf(_transform_time - delta, 0.0)
		if _transform_time <= 0.0:
			_mode = _transform_target
			if _mode == Mode.FIGHTER:
				# Enter the mode pointing where the ship is already going, so the
				# switch never teleports the velocity onto a new axis.
				_heading = (
					velocity.normalized() if velocity.length() > 1.0 else _aim_direction
				)
			GlobalEventBus.player_mode_changed.emit(mode_name())

	if _invulnerable > 0.0 and _alive:
		_invulnerable = maxf(_invulnerable - delta, 0.0)
		var blink_phase: float = fmod(_invulnerable, 0.14)
		_visual.visible = blink_phase >= 0.07
		if _invulnerable <= 0.0:
			_visual.visible = true


## True while the hull is mid-dash or mid-roll. The dash is a jink, not a screen
## clear: a shot that reaches the ship inside this window is evaded, so the
## projectile keeps flying instead of being spent on an invulnerable hull.
func is_evading() -> bool:
	return _alive and _dash_time > 0.0


func take_damage(amount: int, source_position: Vector3 = Vector3.ZERO) -> void:
	if not _alive or _invulnerable > 0.0 or _dash_time > 0.0:
		return

	_hp = maxi(_hp - amount, 0)
	_invulnerable = IFRAME_DURATION
	GlobalEventBus.player_health_changed.emit(_hp, MAX_HP)
	GlobalEventBus.camera_shake_requested.emit(0.6)
	# The hit is on the ship the camera is riding, so it is never positional: the
	# only thing distance would add is a quieter cue for the player's own damage.
	Sfx.play(&"hit")

	if source_position != Vector3.ZERO:
		var push: Vector3 = global_position - source_position
		push.y = 0.0
		if push.length_squared() > 0.0001:
			velocity += push.normalized() * 11.0

	if _hp <= 0:
		# The blast is the hit flash on the killing blow: a second teal sphere over
		# the fireball only muddies the frame the explosion needs.
		_die()
		return

	_spawn_impact()


func _die() -> void:
	_alive = false
	velocity = Vector3.ZERO
	Sfx.engine(false)
	_visual.visible = false
	_aim_beam.visible = false
	_clear_wingtip_trails()
	_spawn_explosion()
	GlobalEventBus.player_died.emit()


## The blast is a world node, not a child of the ship: it stays where the hull died
## and outlives it, while the hidden model sits there waiting for the respawn.
func _spawn_explosion() -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		return
	var blast: ShipExplosion = ShipExplosion.new()
	host.add_child(blast)
	blast.global_position = global_position
	# The ship's own death is the one sound that must not be positional: the
	# camera is on the wreck, so distance attenuation would only make it quieter.
	Sfx.play(&"player_death")


func _spawn_impact() -> void:
	if impact_scene == null:
		return
	var impact: Node3D = impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position


## The airframe is the imported VF-1S, posed by its own skeleton. Everything that
## used to be hand-built here (hull, wings, tails, canopy, limbs) ships inside the
## model; only the gunpod stays procedural, because the model carries none.
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_accent_material = _ship_material(ACCENT_COLOR, 0.05)
	_gunmetal_material = _ship_material(GUNMETAL_COLOR, 0.0)

	_model = PlayerModel.new()
	_model.name = "Model"
	# The livery is read once, at build: the ship the player flies is the ship the
	# options preview showed, and nothing in flight repaints it.
	_model.set_livery(
		GameSettings.load_hull(),
		GameSettings.load_trim(),
		GameSettings.load_canopy(),
		GameSettings.load_lines(),
		GameSettings.load_nose()
	)
	_visual.add_child(_model)
	_model.build()

	_build_fill_light()
	_gunpod = _build_gunpod()


## The arena is lit by a single sun from one side and the airframe is a mirror, so
## the two legs present opposite facets to it. One spine caught the sun and read as
## warm grey; its twin, turned away, crushed to black -- which from the game camera
## reads as one leg wearing a shadow the other does not have. That is what a single
## key light does to symmetric geometry, and no angle fixes it: a counter-light from
## the far side just makes the other leg the dark one.
##
## The fill therefore rides the camera rig, not the sun: the game camera is fixed
## behind and above the ship, so a light along its axis lands on exactly the facets
## the player can see, equally, whichever leg they belong to. It is shadowless and
## cool because it stands in for sky bounce, and `light_cull_mask` keeps it on the
## airframe's own render layer, so the planet, the stars and the enemies keep the
## single-sun look they were tuned with.
func _build_fill_light() -> void:
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.shadow_enabled = false
	fill.light_cull_mask = PlayerModel.AIRFRAME_LAYER_MASK
	camera.get_parent().add_child(fill)


func _ship_material(color: Color, glow: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	material.metallic = 0.15
	# The hull is hand-built, so a flipped face must never punch a hole in it.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow
	return material


## The GU-11. The origin is the grip, so placing the pod at the hand puts the
## receiver in front of it and the stock behind, exactly as it is carried.
func _build_gunpod() -> Node3D:
	var pod: Node3D = Node3D.new()
	_visual.add_child(pod)

	var body: MeshInstance3D = _block(
		Vector3(GUNPOD_LENGTH, 0.26, 0.26), _gunmetal_material
	)
	body.position = Vector3(GUNPOD_LENGTH * 0.5 - 0.30, 0.0, 0.0)
	pod.add_child(body)

	var barrel: MeshInstance3D = _block(
		Vector3(GUNPOD_BARREL, 0.11, 0.11), _gunmetal_material
	)
	barrel.position = Vector3(GUNPOD_LENGTH - 0.30 + GUNPOD_BARREL * 0.5, 0.0, 0.0)
	pod.add_child(barrel)

	var stock: MeshInstance3D = _block(Vector3(0.22, 0.18, 0.16), _accent_material)
	stock.position = Vector3(-0.40, 0.0, 0.0)
	pod.add_child(stock)

	var grip: MeshInstance3D = _block(Vector3(0.12, 0.22, 0.16), _accent_material)
	grip.position = Vector3(0.0, -0.18, 0.0)
	pod.add_child(grip)

	var sight: MeshInstance3D = _block(Vector3(0.24, 0.10, 0.10), _accent_material)
	sight.position = Vector3(0.08, 0.17, 0.0)
	pod.add_child(sight)

	return pod


## The mode switch is a pose, not a swap: the skeleton carries a FIGHTER keyframe
## (its own rest pose) and a GERWALK keyframe, and `_mode_blend` walks between them
## over the same 0.28 s the flight rules take. Nothing pops in or out, and the
## model's folded legs stay the nacelles the fighter silhouette already had.
func _update_mode_pose(sweep: float) -> void:
	var gerwalk: float = 1.0 - _mode_blend
	_visual.position.y = GERWALK_LIFT * gerwalk
	if _model != null:
		_model.pose_mode(gerwalk, sweep)

	# The pod rides the right hand in GERWALK and stows on the centreline in
	# FIGHTER. Reading the hand instead of re-deriving its position keeps the pod
	# glued to the grip while the arm is still swinging through the switch.
	if _gunpod == null:
		return
	var held: Vector3 = GUNPOD_STOWED
	if _model != null:
		held = _model.hand_anchor()
	_gunpod.position = GUNPOD_STOWED.lerp(held, gerwalk)


func _block(size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return _mesh_node(mesh, material)


func _mesh_node(mesh: Mesh, material: StandardMaterial3D) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	# The ship is small and the directional light covers the whole planet, so its
	# shadow lands as a dotted smear instead of a silhouette. Better no shadow.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Two additive, unshaded cones per nozzle: a wide plume and a thin core. The
## materials are shared by both nozzles, so one colour update per frame is enough
## and the two sides can never drift apart.
func _build_thrusters() -> void:
	_thruster_plumes_material = _make_thruster_material(Color(0.22, 0.6, 1.0, 0.12))
	_thruster_cores_material = _make_thruster_material(Color(0.88, 0.98, 1.0, 0.25))

	_nozzle_anchors = _model.nozzle_anchors() if _model != null else []
	for nozzle in _nozzle_anchors.size():
		_add_thruster(nozzle, 0.19, _thruster_plumes_material, _thruster_plumes)
		_add_thruster(nozzle, 0.09, _thruster_cores_material, _thruster_cores)

	_update_afterburner_visual(0.0)


func _make_thruster_material(tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	return material


## Cone with its tip trailing behind: the mesh axis is local Y, so a quarter turn
## about Z lays it along X, pointing away from the nose. Each flame remembers which
## nozzle it belongs to and is placed from that anchor every frame.
func _add_thruster(
	nozzle: int,
	base_radius: float,
	material: StandardMaterial3D,
	into: Array[MeshInstance3D]
) -> void:
	var flame_mesh: CylinderMesh = CylinderMesh.new()
	flame_mesh.top_radius = 0.0
	flame_mesh.bottom_radius = base_radius
	flame_mesh.height = 1.0
	flame_mesh.radial_segments = 8

	var flame: MeshInstance3D = MeshInstance3D.new()
	flame.mesh = flame_mesh
	flame.material_override = material
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.rotation.z = PI * 0.5
	flame.set_meta("nozzle", nozzle)
	_visual.add_child(flame)
	into.append(flame)


## One emitter per nozzle, built once with its worst case. The puffs are not
## carried along with the hull: `local_coords = false` leaves each one where it was
## born, which is what turns a burst into a trail.
func _build_smoke() -> void:
	for nozzle in _nozzle_anchors.size():
		var smoke: GPUParticles3D = GPUParticles3D.new()
		smoke.amount = SMOKE_AMOUNT
		smoke.lifetime = SMOKE_LIFETIME
		smoke.local_coords = false
		smoke.emitting = true
		# At the default 30 Hz the emitter lays the puffs down in batches and the
		# trail reads as a string of beads; the render rate closes the gaps.
		smoke.fixed_fps = 0
		smoke.amount_ratio = 0.0
		smoke.process_material = _make_smoke_process()
		smoke.draw_pass_1 = _make_smoke_puff()
		# The trail is world-space and the sun's shadow map covers the whole arena,
		# so a puff that drifts back over the hull drops a soft blob on it. From the
		# game camera that reads as one leg being in shadow and the other not, which
		# is exactly what a transparent billboard must not do: it is haze, not a
		# solid. Nothing else on the ship casts either (see `_prepare_meshes`).
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke.set_meta("nozzle", nozzle)
		_visual.add_child(smoke)
		_smoke.append(smoke)


## Density follows the climb, not the speed: a steady throttle leaves the nozzles
## clean, and what leaves a trail is the ship gaining speed. The puffs keep their
## own lifetime, so the burst outlives the acceleration by half a second and then
## clears itself. Nothing here has to rescale the emitters, and `amount_ratio`
## changes without restarting the emission.
func _update_smoke(accel: float) -> void:
	var density: float = clampf(accel / ACCELERATION, 0.0, 1.0) * SMOKE_DENSITY_HIGH
	for smoke in _smoke:
		var nozzle: int = int(smoke.get_meta("nozzle", 0))
		if nozzle < _nozzle_anchors.size():
			smoke.position = _nozzle_anchors[nozzle]
		smoke.amount_ratio = density


## One wingtip's ribbon: the tip positions it has visited, oldest first, plus the
## moment each was laid down. The strip is rebuilt from this every frame, so the
## vapour follows the wing exactly -- the sweep moves the tip and the ribbon head
## moves with it, with no frame of lag.
class WingtipTrail:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	## World-space samples, oldest first. The last one is the live tip.
	var points: Array[Vector3] = []
	## The trail's own clock at which each sample was laid down.
	var born: Array[float] = []
	var age: float = 0.0
	## How hard this tip is trailing right now, 0..1. It scales the strip's alpha,
	## so the vapour fades in as the ship picks up speed instead of popping on at
	## a threshold.
	var vapour: float = 0.0


## Two ribbons, one per tip. They are children of the hull but `top_level`, because
## the strip is built in world space from the tip's own history: inheriting the
## ship's yaw would swing the whole contrail around with every turn, and the roll
## animation would whip it around the airframe.
func _build_wingtip_trails() -> void:
	_wingtip_material = _make_wingtip_material()
	for _side in 2:
		var trail: WingtipTrail = WingtipTrail.new()
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = trail.mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.top_level = true
		instance.transform = Transform3D.IDENTITY
		add_child(instance)
		_wingtip_trails.append(trail)


func _update_wingtip_trails(delta: float) -> void:
	if _model == null:
		return
	# GERWALK is a hover, not a wing, and mid-transform the wings are folding. The
	# tips leave no vapour there at all: it is a wingtip effect and there is no
	# wingtip doing anything worth reading.
	if _mode != Mode.FIGHTER or _transform_time > 0.0:
		_clear_wingtip_trails()
		return
	var vapour: float = _wingtip_vapour()
	var tips: Array[Vector3] = _model.wing_tips()
	for index in _wingtip_trails.size():
		var trail: WingtipTrail = _wingtip_trails[index]
		var has_tip: bool = index < tips.size()
		var tip: Vector3 = _visual.global_transform * tips[index] if has_tip else Vector3.ZERO
		_advance_wingtip_trail(trail, tip, vapour if has_tip else 0.0, delta)


## How hard the tips are trailing, 0..1. FIGHTER only: GERWALK has no wingtip
## vapour at all, and the caller clears the strips there.
##
## It answers airspeed, not the burner: the vapour is the cue that the ship is
## moving, so it starts at the middle of the throttle and reaches full strength at
## cruise. The burner is simply the top of that range, which is also where the
## burst rule applies.
##
## It is the speed through the air, not the component along the nose. In a turn the
## nose outruns the course -- that lag is the skid -- so the forward component
## collapses while the wing is still moving through the air at cruise, and the tips
## went quiet exactly when the airframe was loaded. The jink is subtracted for the
## same reason the flight model subtracts it: it is a step the hull takes, not air
## it flies through.
func _wingtip_vapour() -> float:
	if not _alive or _mode != Mode.FIGHTER:
		return 0.0
	var airspeed: float = (velocity - _roll_velocity).length()
	var floor_speed: float = FIGHTER_SPEED * WINGTIP_SPEED_FLOOR
	return clampf(
		(airspeed - floor_speed) / maxf(FIGHTER_SPEED - floor_speed, 0.001), 0.0, 1.0
	)


## Lays down one frame of vapour and redraws the strip. While the tips are trailing
## the head tracks the tip; when the ship slows the head stays where it was and the
## tail is retired by age, so the line dissolves from its far end instead of
## vanishing.
func _advance_wingtip_trail(
	trail: WingtipTrail, tip: Vector3, vapour: float, delta: float
) -> void:
	trail.vapour = vapour
	trail.age += delta
	while not trail.born.is_empty() and trail.age - trail.born[0] > WINGTIP_LIFETIME:
		trail.born.pop_front()
		trail.points.pop_front()

	if vapour > 0.0:
		if trail.points.is_empty():
			trail.points.append(tip)
			trail.born.append(trail.age)
		else:
			var from: Vector3 = trail.points[-1]
			var gap: float = from.distance_to(tip)
			if gap < WINGTIP_SPACING:
				# Barely moved: move the head instead of stacking a vertex on it.
				trail.points[-1] = tip
				trail.born[-1] = trail.age
			else:
				# A frame at 60 u/s is a whole unit, so one vertex per frame would
				# show a turn as a corner. Split the step into even pieces.
				var steps: int = clampi(int(ceil(gap / WINGTIP_SPACING)), 1, 8)
				for step in steps:
					trail.points.append(from.lerp(tip, float(step + 1) / float(steps)))
					trail.born.append(trail.age)

	_rebuild_wingtip_ribbon(trail)


## Rebuilds the strip as a camera-facing band: each sample is split sideways along
## the sample's own direction, so the ribbon keeps its width however the ship turns.
## The head is bright and the tail fades to nothing, which is what reads as a
## contrail rather than as a drawn line.
func _rebuild_wingtip_ribbon(trail: WingtipTrail) -> void:
	trail.mesh.clear_surfaces()
	var count: int = trail.points.size()
	if count < 2:
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	trail.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _wingtip_material)
	for index in count:
		var point: Vector3 = trail.points[index]
		var before: Vector3 = trail.points[maxi(index - 1, 0)]
		var after: Vector3 = trail.points[mini(index + 1, count - 1)]
		var along: Vector3 = after - before
		if along.length_squared() < 0.000001:
			along = Vector3.RIGHT
		along = along.normalized()

		var view: Vector3 = Vector3.UP
		if camera != null:
			view = camera.global_position - point
		if view.length_squared() < 0.000001:
			view = Vector3.UP
		var side: Vector3 = along.cross(view)
		if side.length_squared() < 0.000001:
			side = along.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = along.cross(Vector3.RIGHT)
		side = side.normalized() * (WINGTIP_WIDTH * 0.5)

		var fade: float = float(index) / float(count - 1)
		var color: Color = Color(
			WINGTIP_COLOR.r,
			WINGTIP_COLOR.g,
			WINGTIP_COLOR.b,
			WINGTIP_COLOR.a * fade * fade * trail.vapour
		)
		trail.mesh.surface_set_color(color)
		trail.mesh.surface_add_vertex(point - side)
		trail.mesh.surface_set_color(color)
		trail.mesh.surface_add_vertex(point + side)
	trail.mesh.surface_end()


## The hull is hidden the moment the ship dies and `_physics_process` stops with
## it, so without this the last strip would stay painted in the arena forever. It
## also runs every frame outside FIGHTER, so an already-clean strip is skipped.
func _clear_wingtip_trails() -> void:
	for trail: WingtipTrail in _wingtip_trails:
		if trail.points.is_empty() and trail.born.is_empty():
			continue
		trail.points.clear()
		trail.born.clear()
		trail.mesh.clear_surfaces()


## Additive, unlike the exhaust wake: the tips have sky behind them, and a bright
## line against a dark arena is what makes the speed readable from the game camera.
func _make_wingtip_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_smoke_process() -> ParticleProcessMaterial:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.05
	# Local -X is aft: the emitter turns with the ship, the puff does not.
	process.direction = Vector3(-1.0, 0.0, 0.0)
	process.spread = 18.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.damping_min = 0.6
	process.damping_max = 1.6
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_min = 0.45
	process.scale_max = 1.15
	process.scale_curve = _make_smoke_curve()
	process.color = SMOKE_COLOR
	process.color_ramp = _make_smoke_ramp()
	return process


## Puffs grow as they age and fade out instead of vanishing, which is what keeps a
## short trail from reading as a dotted line.
func _make_smoke_curve() -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.7))
	curve.add_point(Vector2(1.0, 2.6))
	var texture: CurveTexture = CurveTexture.new()
	texture.curve = curve
	return texture


func _make_smoke_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.30))
	gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.18))
	gradient.set_color(2, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	return texture


## A radial fade generated in code, so a puff is a soft disc instead of a square
## and the repository does not have to carry art for one effect.
func _make_smoke_puff() -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SMOKE_PUFF, SMOKE_PUFF)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _make_smoke_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	return quad


func _make_smoke_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.75))
	gradient.set_color(2, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func _build_aim_beam() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.45)

	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(0.08, 0.08, 1.0)

	_aim_beam = MeshInstance3D.new()
	_aim_beam.mesh = beam_mesh
	_aim_beam.material_override = material
	_aim_beam.scale.z = BEAM_LENGTH
	_aim_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_beam)
