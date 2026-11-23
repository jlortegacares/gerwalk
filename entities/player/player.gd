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

## Afterburner. Normal thrust tops out at MAX_SPEED; the burner trades reserve for
## a higher top speed, and the reserve only fills back while the burner is off.
const BOOST_SPEED: float = 42.0
const BOOST_ACCELERATION: float = 420.0
const TURBO_MAX: float = 100.0
const TURBO_DRAIN_PER_SECOND: float = 45.0
const TURBO_RECHARGE_PER_SECOND: float = 24.0

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
## How long the airframe takes to come over, shared by both modes. The turn-over is
## presentation, and at the fighter's own 0.20 s step it was twelve frames of blur
## that read as a teleport; 0.45 s is the same 360 degrees at 2.25x the time, long
## enough to see the wings come over. It is not only cosmetic: the button dash sets
## no step at all, so this clock is the whole of that dodge, and `is_evading()`
## follows it. A roll outliving a 0.12 s burst is the point -- the ship is seen
## spinning rather than blinking sideways.
const ROLL_ANIM_TIME: float = 0.45
const FIGHTER_NOSE_PITCH: float = -5.0
const TRANSFORM_TIME: float = 0.28

## The nose is long, so the muzzle and the aim beam start past its tip.
const MUZZLE_DISTANCE: float = 3.05

## Wing sweep in degrees: nearly straight at rest, a clear contraction at cruise,
## and swept back when the burner is lit. The wing already carries about 27 degrees
## of leading-edge sweep, so the tip ends up near 65 degrees at full burn.
## The stops live with the pose that applies them, in `PlayerEffects`; the names
## stay here because the interceptor's own sweep and the suite read them.
const WING_SWEEP_FORWARD: float = PlayerEffects.WING_SWEEP_FORWARD
const WING_SWEEP_CRUISE: float = PlayerEffects.WING_SWEEP_CRUISE
const WING_SWEEP_BACK: float = PlayerEffects.WING_SWEEP_BACK
## Degrees per second the wings travel between those stops. The throttle changes in
## a couple of frames, so the wing needs its own clock to read as a mechanism
## instead of a snap: 0 to full sweep takes a bit over half a second.
const WING_SWEEP_RATE: float = PlayerEffects.WING_SWEEP_RATE

## The gunpod's two materials and the airframe's fill light live in `PlayerHull`,
## with the geometry they dress.

## GERWALK is the VF-1's bird-legged stance: the model's legs are the nacelles and
## the skeleton swings them down and out. They reach further below the hull than
## the placeholder's did, so the whole airframe rides higher in the stance to keep
## the feet off the planet.
const GERWALK_LIFT: float = 0.55

## Where the gunpod rides in FIGHTER: centreline, under the belly, which is where
## a VF-1 carries it.
const GUNPOD_STOWED: Vector3 = Vector3(0.48, -0.27, 0.0)

@export var bullet_scene: PackedScene
@export var impact_scene: PackedScene

var camera: Camera3D

var _weapons: WeaponSystem

## The run's numbers. They are the base constants scaled by the pilot's level, and
## they are captured once in `_ready`: a level earned mid-fight must not change the
## ship under the player, so the next run is what carries the new numbers.
var _stats: PilotStats = PilotStats.new()
var _max_speed: float = MAX_SPEED
var _boost_speed: float = BOOST_SPEED
var _dash_speed: float = DASH_SPEED
var _fighter_speed: float = FIGHTER_SPEED
var _fighter_boost_speed: float = FIGHTER_BOOST_SPEED
var _fighter_stall_speed: float = FIGHTER_STALL_SPEED
var _fighter_drag: float = FIGHTER_DRAG
var _transform_drag: float = TRANSFORM_DRAG
var _max_hp: int = MAX_HP
var _turbo_max: float = TURBO_MAX
var _turbo_recharge: float = TURBO_RECHARGE_PER_SECOND

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
var _thrust_kick: float = 0.0

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

var _effects: PlayerEffects
var _visual: Node3D
var _model: PlayerModel
var _accent_material: StandardMaterial3D
var _gunpod: Node3D
var _gunmetal_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"player")
	_apply_pilot_stats()
	camera = %Camera
	_build_visual()

	_effects = PlayerEffects.new()
	_effects.name = "Effects"
	_effects.camera = camera
	_effects.pose = _apply_afterburner_pose
	_effects.set_speeds(
		_max_speed, _boost_speed, _fighter_speed, _fighter_boost_speed, ACCELERATION
	)
	add_child(_effects)
	_effects.build(_visual, _model)

	_weapons = WeaponSystem.new()
	_weapons.name = "Weapons"
	_weapons.setup(bullet_scene, _stats)
	add_child(_weapons)

	GlobalEventBus.player_health_changed.emit.call_deferred(_hp, _max_hp)
	GlobalEventBus.player_turbo_changed.emit.call_deferred(_turbo, _turbo_max)
	GlobalEventBus.player_mode_changed.emit.call_deferred(mode_name())


## Reads the pilot's record once and turns the level into this run's numbers. The
## derived constants follow their base, so the fighter's stall speed and drag stay
## the same fraction of cruise at every level instead of drifting apart from it.
func _apply_pilot_stats() -> void:
	_stats = PilotStats.new(GameProgress.instance().level())

	_max_speed = MAX_SPEED * _stats.speed_multiplier()
	_boost_speed = BOOST_SPEED * _stats.speed_multiplier()
	_dash_speed = DASH_SPEED * _stats.speed_multiplier()
	_fighter_speed = FIGHTER_SPEED * _stats.speed_multiplier()
	_fighter_boost_speed = FIGHTER_BOOST_SPEED * _stats.speed_multiplier()
	_fighter_stall_speed = _fighter_speed * FIGHTER_MIN_THROTTLE
	_fighter_drag = (_fighter_speed - _fighter_stall_speed) / FIGHTER_STOP_TIME
	_transform_drag = _fighter_speed / FIGHTER_STOP_TIME

	_max_hp = _stats.max_hp(MAX_HP)
	_hp = _max_hp
	_turbo_max = TURBO_MAX * _stats.turbo_capacity_multiplier()
	_turbo = _turbo_max
	_turbo_shown = _turbo_max
	_turbo_recharge = TURBO_RECHARGE_PER_SECOND * _stats.turbo_recharge_multiplier()

	# The weapons are built after this runs on the first frame, so the guard is the
	# first-run case; a later reapply reaches an existing arsenal.
	if _weapons != null:
		_weapons.set_stats(_stats)
	# Same seam as the arsenal: the wake reads the run's speeds, never the record.
	if _effects != null:
		_effects.set_speeds(
			_max_speed, _boost_speed, _fighter_speed, _fighter_boost_speed, ACCELERATION
		)


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
		velocity = _dash_direction * _dash_speed
		velocity.y = 0.0
		move_and_slide()
	elif _transform_time > 0.0:
		# Mid-transformation the ship keeps its momentum but takes no thrust and
		# fires nothing: the switch is a commitment, not a free dodge or a reset.
		velocity = velocity.move_toward(Vector3.ZERO, _transform_drag * 0.35 * delta)
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
	Sfx.engine(true, velocity.length() / _boost_speed)


func _move_gerwalk(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down", MOVE_DEADZONE
	)
	var thrusting: bool = input_direction.length_squared() > 0.0
	_update_boost(delta, thrusting)

	var speed: float = _boost_speed if _boosting else _max_speed
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
	# busy coming over, or the spin bends the course it was dodging. The button's
	# spin sets no jink at all, so the roll clock is the one that has to hold it.
	var trim: float = 0.0
	if _dash_time <= 0.0 and _roll_anim_time <= 0.0:
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

	var cruise: float = _fighter_boost_speed if _boosting else _fighter_speed
	# With the stick released there is still a floor: the ship glides, it does not
	# hang. It is the throttle's own minimum, so no input and a hair of input give
	# the same speed and there is no seam between them.
	var wanted: float = (
		cruise * (FIGHTER_MIN_THROTTLE + (1.0 - FIGHTER_MIN_THROTTLE) * throttle)
		if thrusting
		else _fighter_stall_speed
	)
	var rate: float = FIGHTER_ACCELERATION if thrusting else _fighter_drag
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


## The ship's presentation, as a node: the wake, the vapour and the aim beam.
func effects() -> PlayerEffects:
	return _effects


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
		_turbo = minf(_turbo + _turbo_recharge * delta, _turbo_max)

	_emit_turbo()


## One event per whole reserve unit instead of one per physics frame: the bar is
## 234 px wide, so a unit is under 2.5 px. Smooth to the eye, quiet on the bus.
func _emit_turbo() -> void:
	var shown: float = roundf(_turbo)
	if is_equal_approx(shown, _turbo_shown):
		return
	_turbo_shown = shown
	GlobalEventBus.player_turbo_changed.emit(_turbo, _turbo_max)


## The wake and the pose, fed this frame's numbers. The effects node owns the
## plumes, the smoke and the camera kick; the ship still owns the velocity, the
## burner tank and the run's speeds.
func _update_afterburner_visual(delta: float) -> void:
	var forward_speed: float = maxf(velocity.dot(_aim_direction), 0.0)
	var heat: float = clampf(
		(forward_speed - _max_speed) / (_boost_speed - _max_speed), 0.0, 1.0
	)
	var visual_mode: Mode = _transform_target if _transform_time > 0.0 else _mode
	_thrust_kick = _effects.update_afterburner(
		delta,
		_thrust_kick,
		forward_speed,
		_boosting,
		heat,
		visual_mode == Mode.FIGHTER
	)


## The airframe owns what the blend and the sweep move: the nose pitch, the stance
## and the gunpod are the pose, not the wake.
func _apply_afterburner_pose(delta: float, fighter: bool, sweep: float) -> void:
	# The silhouette is the mode read from above: FIGHTER dips the nose, GERWALK
	# holds it level like a hovering airframe. The blend follows the mode the switch
	# is committing *to*, not the mode the rules still use, so the shape finishes
	# changing exactly when the rules flip instead of one whole switch later.
	var target_blend: float = 1.0 if fighter else 0.0
	_mode_blend = move_toward(_mode_blend, target_blend, delta / TRANSFORM_TIME)
	_visual.rotation.z = deg_to_rad(FIGHTER_NOSE_PITCH) * _mode_blend
	_update_mode_pose(sweep)


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
	# The gesture always carries a direction: `_tick_double_tap` only arms a tap
	# on a deflected stick. That is what makes it the jink in both modes while a
	# bare button press is the spin.
	_start_dash(direction)


## `tapped` is the stick a double tap asked for, already deadzoned. It is empty
## when the button fired, which is the spin on its own.
func _start_dash(tapped: Vector2 = Vector2.ZERO) -> void:
	if _mode == Mode.FIGHTER:
		_start_barrel_roll(tapped)
		return
	_start_gerwalk_dash(tapped)


## GERWALK's half of the same contract the fighter follows: a gesture that chose a
## direction gets the 0.12 s burst, the button comes over without moving the ship.
## The spin itself is the dodge either way, and it is what carries the i-frames.
##
## The side is read against the aim -- the model's own nose, since this mode turns
## its nose independently of where it flies -- because that is the frame the roll
## axis lives in. A tap straight down the nose has no side of its own, so the aim
## stick picks one and a centred stick repeats the last one, exactly like a
## fighter jink.
func _start_gerwalk_dash(tapped: Vector2) -> void:
	Sfx.play(&"dash")
	var world: Vector3 = Vector3(tapped.x, 0.0, tapped.y)
	var stepping: bool = world.length_squared() > 0.0
	if stepping:
		_dash_direction = world.normalized()
	_dash_time = DASH_DURATION if stepping else 0.0
	var right: Vector3 = Vector3(-_aim_direction.z, 0.0, _aim_direction.x)
	var side: float = signf(_dash_direction.dot(right)) if stepping else 0.0
	if is_zero_approx(side):
		side = signf(Input.get_axis(&"aim_left", &"aim_right"))
	if is_zero_approx(side):
		side = _roll_side
	_roll_side = side
	_roll_anim_time = ROLL_ANIM_TIME
	_dash_cooldown = DASH_COOLDOWN
	# The nozzle flash outlives the 0.12 s burst, then decays on its own.
	_thrust_kick = 1.0
	_spawn_impact()


## In Fighter the dash is the roll the spec puts on the right stick: the ship spins
## around its own nose. The capsule never spins, so it is a jink with i-frames, not
## a free turn.
##
## The button and the gesture are two different dodges. Space is the spin on its
## own: the hull comes over, nothing else moves, and the i-frames the animation
## carries are the whole of it. A double tap is the jink, because the tap chose a
## direction and a step the player aimed is exactly what the gesture is for.
##
## `tapped` is the stick a double tap asked for, in the same world axes the flight
## model reads, so any direction is a valid jink and diagonals are just a
## direction. It is converted to the airframe's own frame, which is what lets the
## step turn with the nose. Without a tap (the button) the aim axis picks the
## side the spin goes, and a centred stick repeats the last one instead of
## defaulting right.
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
	# A tapped roll also steps; the button only spins. The step is what makes the
	# gesture a jink, and the spin is what makes the button a dodge: neither needs
	# the other's part.
	_dash_time = FIGHTER_ROLL_TIME if world.length_squared() > 0.0 else 0.0
	_roll_anim_time = ROLL_ANIM_TIME
	_dash_cooldown = DASH_COOLDOWN
	_thrust_kick = 1.0
	_spawn_impact()


## Banking is derived from the body, not from the input: lateral drift relative to
## the nose rolls the hull into that drift, and a fast nose turn adds a smaller
## lean into the turn. Both settle back to level once the movement stops.
func _update_bank(delta: float) -> void:
	var fighter: bool = _mode == Mode.FIGHTER
	var right: Vector3 = Vector3(-_aim_direction.z, 0.0, _aim_direction.x)
	var lateral: float = clampf(velocity.dot(right) / _max_speed, -1.0, 1.0)
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

	# The barrel roll owns the roll axis for its own 0.45 s, which outlives both the
	# fighter's 0.20 s jink and GERWALK's 0.12 s burst, and outlives the button's
	# spin by the whole 0.45 s. Whatever the ship is doing underneath, the bank must
	# not fight the turn-over. The sign follows the side, so a left dodge rolls left
	# and the animation agrees with the direction the ship went.
	if _roll_anim_time > 0.0:
		var spun: float = 1.0 - _roll_anim_time / ROLL_ANIM_TIME
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
	_effects.aim(_aim_direction)


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
##
## The window is the animation, not the distance. The spin outlives the step in
## every path -- 0.45 s against 0.12 s in GERWALK, against 0.20 s in a fighter
## jink, and against nothing at all when the button spins in place -- so a dodge
## the player can see is protected for as long as it is visible. Any shorter and
## the hull gets shot while it is visibly upside down.
func is_evading() -> bool:
	return _alive and (_dash_time > 0.0 or _roll_anim_time > 0.0)


func take_damage(amount: int, source_position: Vector3 = Vector3.ZERO) -> void:
	if not _alive or _invulnerable > 0.0 or is_evading():
		return

	_hp = maxi(_hp - amount, 0)
	_invulnerable = IFRAME_DURATION
	GlobalEventBus.player_health_changed.emit(_hp, _max_hp)
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
	_effects.hide_beam()
	_effects.clear_wingtip_trails()
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
## The airframe's construction is `PlayerHull`'s story. The ship keeps the handles
## because the mode pose, the i-frame blink and the pod all read them every frame.
func _build_visual() -> void:
	var hull: PlayerHull = PlayerHull.new()
	hull.build(self, camera.get_parent())
	_visual = hull.visual
	_model = hull.model
	_accent_material = hull.accent_material
	_gunmetal_material = hull.gunmetal_material
	_gunpod = hull.gunpod


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


## The wake, the vapour and the beam belong to the effects node; these keep the
## suite's names on the ship and feed them the ship's own state.
func _update_smoke(accel: float) -> void:
	_effects.update_smoke(accel)


func _update_wingtip_trails(delta: float) -> void:
	_effects.update_wingtips(
		delta,
		_mode == Mode.FIGHTER and _transform_time <= 0.0,
		(velocity - _roll_velocity).length()
	)


func _wingtip_vapour() -> float:
	return _effects.wingtip_vapour(
		_alive and _mode == Mode.FIGHTER, (velocity - _roll_velocity).length()
	)


func _advance_wingtip_trail(
	trail: PlayerEffects.WingtipTrail, tip: Vector3, vapour: float, delta: float
) -> void:
	_effects.advance_wingtip_trail(trail, tip, vapour, delta)


func _clear_wingtip_trails() -> void:
	_effects.clear_wingtip_trails()
