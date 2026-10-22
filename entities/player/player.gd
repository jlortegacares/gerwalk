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

## Angular game feel. Aim is instant, so the shot never lags the stick; the model
## turns at this rate so a flick reads as a snap roll instead of a teleport. At
## 1800 deg/s a 180 turn takes six frames.
const VISUAL_TURN_RATE: float = 1800.0
## Bank is presentation only: the capsule never rolls, so leaning 32 degrees
## cannot change what the player can graze. It is what sells a jet on a plane
## that has no banking at all.
const MAX_BANK: float = 32.0
const YAW_BANK: float = 10.0
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
## Constant world wind, in units/s, blowing towards +X (screen right). Below the
## stall speed, so even a coast straight into it still moves forwards, and 15% of
## cruise, so it is felt without taking the ship for a ride. Only FIGHTER answers
## to it: GERWALK is a ground-effect hover holding station, not an aircraft.
const WIND: Vector3 = Vector3(7.0, 0.0, 0.0)
## The transformation bleeds momentum at the old fighter drag, so the 0.28 s
## switch feels exactly as it did before the flight model grew a stall speed.
const TRANSFORM_DRAG: float = FIGHTER_SPEED / FIGHTER_STOP_TIME
const FIGHTER_TRIM_DEGREES: float = 8.0
const FIGHTER_YAW_TRIM: float = 60.0
const FIGHTER_ROLL_TIME: float = 0.20
const FIGHTER_ROLL_SPEED: float = 55.0
const FIGHTER_NOSE_PITCH: float = -5.0
const TRANSFORM_TIME: float = 0.28
const SHOCKWAVE_LENGTH: float = 7.0
const SHOCKWAVE_HALF_ANGLE: float = 30.0

const THRUSTER_X: float = -1.92
const THRUSTER_Z: float = 0.23

## The nose is long, so the muzzle and the aim beam start past its tip.
const MUZZLE_DISTANCE: float = 3.05
const BEAM_START: float = 2.60
const BEAM_LENGTH: float = 2.0

## Wing sweep in degrees: nearly straight at rest, swept back when the burner is
## lit. The wing already carries about 27 degrees of leading-edge sweep, so the
## tip ends up near 59 degrees at full burn.
const WING_SWEEP_FORWARD: float = 0.0
const WING_SWEEP_BACK: float = 32.0

## Desert airframe from the reference sheet: tan skin, maroon intakes and shrouds,
## a white nose cone and an olive canopy. Flat colours only, no textures.
const BODY_COLOR: Color = Color(0.78, 0.68, 0.47, 1.0)
const ACCENT_COLOR: Color = Color(0.34, 0.22, 0.17, 1.0)
const NOSE_COLOR: Color = Color(0.93, 0.94, 0.89, 1.0)
const CANOPY_COLOR: Color = Color(0.20, 0.27, 0.23, 1.0)
const BEAM_COLOR: Color = Color(0.24, 0.9, 0.8, 1.0)

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
var _alive: bool = true

var _visual_yaw: float = 0.0
var _visual_yaw_prev: float = 0.0
var _bank: float = 0.0
var _forward_speed: float = 0.0
var _thrust_kick: float = 0.0

var _mode: Mode = Mode.GERWALK
var _transform_time: float = 0.0
var _transform_target: Mode = Mode.GERWALK
var _mode_blend: float = 0.0
var _heading: Vector3 = Vector3.RIGHT
var _roll_side: float = 1.0
## The lateral push the barrel roll added last frame. It is not airspeed, so the
## flight model subtracts it before reading the air: otherwise every jink tops up
## the previous one and a 55 u/s roll ends up at 390.
var _roll_velocity: Vector3 = Vector3.ZERO
var _shockwave: Node3D

var _turbo: float = TURBO_MAX
var _boosting: bool = false
var _turbo_locked: bool = false
var _turbo_shown: float = TURBO_MAX
var _base_fov: float = 58.0

var _visual: Node3D
var _aim_beam: MeshInstance3D
var _body_material: StandardMaterial3D
var _accent_material: StandardMaterial3D
var _nose_material: StandardMaterial3D
var _canopy_material: StandardMaterial3D
var _wing_right: Node3D
var _wing_left: Node3D
var _thruster_plumes_material: StandardMaterial3D
var _thruster_cores_material: StandardMaterial3D
var _thruster_plumes: Array[MeshInstance3D] = []
var _thruster_cores: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(&"player")
	camera = %Camera
	_base_fov = camera.fov
	_build_visual()
	_build_thrusters()
	_build_aim_beam()
	_build_shockwave()

	_weapons = WeaponSystem.new()
	_weapons.name = "Weapons"
	_weapons.setup(bullet_scene)
	add_child(_weapons)

	GlobalEventBus.player_health_changed.emit.call_deferred(_hp, MAX_HP)
	GlobalEventBus.player_turbo_changed.emit.call_deferred(_turbo, TURBO_MAX)
	GlobalEventBus.player_mode_changed.emit.call_deferred(mode_name())


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not _alive:
		return

	if Input.is_action_just_pressed(&"transform") and _transform_time <= 0.0:
		_start_transform()

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
	_update_shockwave()


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
## velocity minus the wind, and it has two properties: where it points and how
## fast it goes. The throttle owns the speed and the airframe owns how quickly the
## course may follow the nose, which is the whole flight model in one line. Drive
## the two axes independently instead and a turn manufactures airspeed out of
## nothing.
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

	# Airspeed is the velocity through the air: the ground velocity minus the wind.
	# Tracking it as a course plus a magnitude is what lets wind slow a head-on run
	# and push a downwind one without ever being confused with thrust.
	var air: Vector3 = velocity - WIND - _roll_velocity
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

	# The barrel roll is a lateral push that ramps in and out, so it never snaps
	# the velocity sideways at either end of the jink.
	var push: Vector3 = Vector3.ZERO
	if _dash_time > 0.0:
		var progress: float = 1.0 - _dash_time / FIGHTER_ROLL_TIME
		push = right * _roll_side * sin(progress * PI) * FIGHTER_ROLL_SPEED

	velocity = Vector3(cos(course), 0.0, -sin(course)) * airspeed + push + WIND
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


func mode() -> Mode:
	return _mode


func is_fighter() -> bool:
	return _mode == Mode.FIGHTER


func mode_name() -> String:
	return "FIGHTER" if _mode == Mode.FIGHTER else "GERWALK"


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

	# A kick is a flash, not a speed curve: opening the throttle past a walk, or
	# punching the dash, spikes the plumes and then decays in about a third of a
	# second. It is the only cue that the ship has weight at all.
	var accel: float = (forward_speed - _forward_speed) / maxf(delta, 0.0001)
	_forward_speed = forward_speed
	_thrust_kick = maxf(_thrust_kick, clampf(accel / ACCELERATION, 0.0, 1.0))
	_thrust_kick = move_toward(_thrust_kick, 0.0, THRUST_KICK_DECAY * delta)
	var kick: float = _thrust_kick

	_layout_flames(_thruster_plumes, 0.35 + thrust * 1.65 + kick * 1.10)
	_layout_flames(_thruster_cores, 0.28 + thrust * 1.00 + kick * 0.70)

	# The silhouette is the mode read from above: FIGHTER locks the wings fully aft
	# and dips the nose, GERWALK holds them forward and level like a hovering
	# airframe. The blend rides the same 0.28 s as the switch, so the shape and the
	# rules arrive together.
	var target_blend: float = 1.0 if _mode == Mode.FIGHTER else 0.0
	_mode_blend = move_toward(_mode_blend, target_blend, delta / TRANSFORM_TIME)
	_visual.rotation.z = deg_to_rad(FIGHTER_NOSE_PITCH) * _mode_blend

	# In between modes the wings still answer the throttle, which keeps the sweep
	# continuous instead of snapping at the end of the transformation.
	var sweep_t: float = lerpf(thrust, 1.0, _mode_blend)
	var sweep: float = deg_to_rad(lerpf(WING_SWEEP_FORWARD, WING_SWEEP_BACK, sweep_t))
	_wing_right.rotation.y = -sweep
	_wing_left.rotation.y = sweep

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


## The supersonic burst: a cone in front of the nose that shreds enemy fire while
## the burner is lit. It is a rule, not an aura, so the cone the player sees is the
## cone that eats the shots. Every current enemy shot is "weak": the filter is
## geometry, not damage.
func _build_shockwave() -> void:
	_shockwave = Node3D.new()
	_shockwave.visible = false
	add_child(_shockwave)

	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = tan(deg_to_rad(SHOCKWAVE_HALF_ANGLE)) * SHOCKWAVE_LENGTH
	cone.height = SHOCKWAVE_LENGTH
	cone.radial_segments = 16
	cone.rings = 1

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(0.62, 0.95, 1.0, 0.16)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = cone
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# CylinderMesh runs along Y; tip it onto +X and push it out so the small radius
	# sits on the nose and the wide end is the far edge of the burst.
	mesh.rotation.z = -PI * 0.5
	mesh.position = Vector3(SHOCKWAVE_LENGTH * 0.5, 0.0, 0.0)
	_shockwave.add_child(mesh)


func _update_shockwave() -> void:
	var active: bool = _alive and _mode == Mode.FIGHTER and _boosting
	_shockwave.visible = active
	if not active:
		return

	_shockwave.rotation.y = atan2(-_heading.z, _heading.x)
	for node in get_tree().get_nodes_in_group(&"enemy_bullet"):
		var bullet: Node3D = node as Node3D
		if bullet == null or bullet.is_queued_for_deletion():
			continue
		var offset: Vector3 = bullet.global_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance < 0.01 or distance > SHOCKWAVE_LENGTH:
			continue
		if rad_to_deg(offset.angle_to(_heading)) <= SHOCKWAVE_HALF_ANGLE:
			bullet.queue_free()
			GlobalEventBus.camera_shake_requested.emit(0.1)


## The cone's tip trails behind the nozzle, so growing it must move it back by the
## same amount or the base would detach from the hull.
func _layout_flames(flames: Array[MeshInstance3D], length: float) -> void:
	for flame in flames:
		flame.scale = Vector3(1.0, length, 1.0)
		flame.position.x = THRUSTER_X - length * 0.5


func _start_dash() -> void:
	if _mode == Mode.FIGHTER:
		_start_barrel_roll()
		return

	var input_direction: Vector2 = Input.get_vector(
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
## sideways without changing where it points, and the airframe spins around its own
## nose. The capsule never spins, so it is a jink with i-frames, not a free turn.
func _start_barrel_roll() -> void:
	_roll_side = signf(Input.get_axis(&"aim_left", &"aim_right"))
	if is_zero_approx(_roll_side):
		_roll_side = 1.0
	_dash_time = FIGHTER_ROLL_TIME
	_dash_cooldown = DASH_COOLDOWN
	_thrust_kick = 1.0
	_spawn_impact()


## Banking is derived from the body, not from the input: lateral drift relative to
## the nose rolls the hull into that drift, and a fast nose turn adds a smaller
## lean into the turn. Both settle back to level once the movement stops.
func _update_bank(delta: float) -> void:
	var right: Vector3 = Vector3(-_aim_direction.z, 0.0, _aim_direction.x)
	var lateral: float = clampf(velocity.dot(right) / MAX_SPEED, -1.0, 1.0)
	var yaw_rate: float = 0.0
	if delta > 0.0:
		yaw_rate = clampf(
			angle_difference(_visual_yaw_prev, _visual_yaw)
			/ delta
			/ deg_to_rad(VISUAL_TURN_RATE),
			-1.0,
			1.0
		)
	_visual_yaw_prev = _visual_yaw

	# The barrel roll owns the roll axis for its 0.2 s; the bank would fight it.
	if _mode == Mode.FIGHTER and _dash_time > 0.0:
		_visual.rotation.x = (1.0 - _dash_time / FIGHTER_ROLL_TIME) * TAU
		_bank = 0.0
		return

	# A fighter leans into the turn with the whole wing, because in this mode the
	# entire bank comes from the turn: there is no lateral drift to read.
	var yaw_bank: float = MAX_BANK * 0.8 if _mode == Mode.FIGHTER else YAW_BANK
	var target: float = deg_to_rad(MAX_BANK * lateral - yaw_bank * yaw_rate)
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

	_weapons.tick(
		delta,
		global_position,
		global_position + _aim_direction * MUZZLE_DISTANCE,
		_aim_direction,
		wants_fire,
		_mode == Mode.FIGHTER
	)


func _tick_timers(delta: float) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_dash_time = maxf(_dash_time - delta, 0.0)

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


func take_damage(amount: int, source_position: Vector3 = Vector3.ZERO) -> void:
	if not _alive or _invulnerable > 0.0 or _dash_time > 0.0:
		return

	_hp = maxi(_hp - amount, 0)
	_invulnerable = IFRAME_DURATION
	GlobalEventBus.player_health_changed.emit(_hp, MAX_HP)
	GlobalEventBus.camera_shake_requested.emit(0.6)

	if source_position != Vector3.ZERO:
		var push: Vector3 = global_position - source_position
		push.y = 0.0
		if push.length_squared() > 0.0001:
			velocity += push.normalized() * 11.0

	_spawn_impact()

	if _hp <= 0:
		_die()


func _die() -> void:
	_alive = false
	velocity = Vector3.ZERO
	_visual.visible = false
	_aim_beam.visible = false
	GlobalEventBus.player_died.emit()


func _spawn_impact() -> void:
	if impact_scene == null:
		return
	var impact: Node3D = impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position


## A low-poly fighter in flat colours, matching the reference sheet: long pointed
## nose, cockpit, shoulder-mounted swing wings, twin canted tails and two engine
## nozzles. Hand-built like every other placeholder, so the pre-rendered asset
## pipeline (D-02) can still replace it later.
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_body_material = _ship_material(BODY_COLOR, 0.12)
	_accent_material = _ship_material(ACCENT_COLOR, 0.05)
	_nose_material = _ship_material(NOSE_COLOR, 0.20)
	_canopy_material = _ship_material(CANOPY_COLOR, 0.25)

	_build_fuselage()
	_build_wings()
	_build_empennage()
	_build_canopy()


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


## Stations run along +X and carry a half-width (Z) and a half-height (Y). Broad
## shoulders at the intakes and a narrow tail between the nozzles: that planform
## is what the player reads from a near-overhead camera.
func _build_fuselage() -> void:
	var nose: Array[Vector3] = [
		Vector3(2.25, 0.02, 0.02),
		Vector3(1.95, 0.10, 0.06),
		Vector3(1.55, 0.20, 0.11),
		Vector3(1.15, 0.30, 0.15),
	]
	var body: Array[Vector3] = [
		Vector3(1.15, 0.30, 0.15),
		Vector3(0.75, 0.40, 0.20),
		Vector3(0.10, 0.50, 0.25),
		Vector3(-0.60, 0.52, 0.26),
		Vector3(-1.25, 0.46, 0.24),
		Vector3(-1.85, 0.38, 0.21),
	]
	_visual.add_child(_loft(nose, _nose_material))
	_visual.add_child(_loft(body, _body_material))

	var intake: Array[Vector2] = [
		Vector2(0.80, 0.32), Vector2(-0.35, 0.32), Vector2(-0.48, 0.56), Vector2(0.60, 0.56),
	]
	for side in [-1.0, 1.0]:
		var duct: MeshInstance3D = _slab(intake, 0.20, _accent_material, float(side))
		duct.position.y = -0.02
		_visual.add_child(duct)


## The pivot sits at the wing root, so sweeping rotates the wing around the joint
## instead of sliding it through the fuselage.
func _build_wings() -> void:
	_wing_right = _build_wing(1.0)
	_wing_left = _build_wing(-1.0)


func _build_wing(side: float) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.position = Vector3(0.0, 0.05, 0.44 * side)
	_visual.add_child(pivot)

	var outline: Array[Vector2] = [
		Vector2(0.55, 0.02), Vector2(-0.35, 1.50), Vector2(-0.80, 1.50), Vector2(-0.90, 0.02),
	]
	pivot.add_child(_slab(outline, 0.07, _body_material, side))
	return pivot


## Twin tails and the tailplane. From a near-overhead camera the fins are almost
## edge-on, so they stay thin slivers; the tailplane carries the rear read.
func _build_empennage() -> void:
	var tailplane: Array[Vector2] = [
		Vector2(-1.15, 0.12), Vector2(-1.55, 0.86), Vector2(-1.78, 0.86), Vector2(-1.72, 0.12),
	]
	var fin: Array[Vector2] = [
		Vector2(0.36, 0.0), Vector2(-0.36, 0.0), Vector2(-0.54, 0.52), Vector2(-0.06, 0.52),
	]
	var nozzle_mesh: CylinderMesh = CylinderMesh.new()
	nozzle_mesh.top_radius = 0.15
	nozzle_mesh.bottom_radius = 0.19
	nozzle_mesh.height = 0.36
	nozzle_mesh.radial_segments = 10

	for side in [-1.0, 1.0]:
		var direction: float = float(side)

		var plane: MeshInstance3D = _slab(tailplane, 0.08, _body_material, direction)
		plane.position.y = 0.06
		_visual.add_child(plane)

		var tail: MeshInstance3D = _slab(fin, 0.07, _accent_material, direction)
		tail.rotation.x = -PI * 0.5
		tail.position = Vector3(-1.05, 0.16, 0.31 * direction)
		_visual.add_child(tail)

		var nozzle: MeshInstance3D = _mesh_node(nozzle_mesh, _accent_material)
		nozzle.rotation.z = PI * 0.5
		nozzle.position = Vector3(-1.72, 0.0, THRUSTER_Z * direction)
		_visual.add_child(nozzle)


func _build_canopy() -> void:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 6

	var canopy: MeshInstance3D = _mesh_node(mesh, _canopy_material)
	canopy.position = Vector3(0.62, 0.24, 0.0)
	canopy.scale = Vector3(0.95, 0.44, 0.40)
	_visual.add_child(canopy)


func _mesh_node(mesh: Mesh, material: StandardMaterial3D) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	# The ship is small and the directional light covers the whole planet, so its
	# shadow lands as a dotted smear instead of a silhouette. Better no shadow.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Lofts a closed fuselage from ring stations. The section is an octagon: a flat
## deck and chamfered sides read cleanly from above and cost a fraction of a
## smooth hull.
func _loft(stations: Array[Vector3], material: StandardMaterial3D) -> MeshInstance3D:
	var shape: Array[Vector2] = [
		Vector2(1.0, 0.0), Vector2(0.62, 0.78), Vector2(0.0, 1.0), Vector2(-0.62, 0.78),
		Vector2(-1.0, 0.0), Vector2(-0.62, -0.78), Vector2(0.0, -1.0), Vector2(0.62, -0.78),
	]

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for index in stations.size() - 1:
		var near: Vector3 = stations[index]
		var far: Vector3 = stations[index + 1]
		for corner in shape.size():
			var next: int = (corner + 1) % shape.size()
			var middle: Vector2 = (shape[corner] + shape[next]) * 0.5
			_quad(st,
				_station_point(near, shape[corner]),
				_station_point(near, shape[next]),
				_station_point(far, shape[next]),
				_station_point(far, shape[corner]),
				Vector3(0.0, middle.y, middle.x))

	_cap(st, stations[0], Vector3.RIGHT, shape)
	_cap(st, stations[stations.size() - 1], Vector3.LEFT, shape)
	st.generate_normals()
	return _mesh_node(st.commit(), material)


## A station is (x, half-width along Z, half-height along Y); a corner is a
## normalised (z, y) pair on the octagon.
func _station_point(station: Vector3, corner: Vector2) -> Vector3:
	return Vector3(station.x, corner.y * station.z, corner.x * station.y)


func _cap(st: SurfaceTool, station: Vector3, direction: Vector3, shape: Array[Vector2]) -> void:
	var centre: Vector3 = Vector3(station.x, 0.0, 0.0)
	for corner in shape.size():
		var next: int = (corner + 1) % shape.size()
		_face(st, centre,
			_station_point(station, shape[corner]),
			_station_point(station, shape[next]),
			direction)


## Extrudes a flat polygon that lives in the XZ plane into a slab: wings, tail
## surfaces and fins all come from here. `mirror` flips the polygon across the
## centreline, so one outline serves both sides.
func _slab(
	outline: Array[Vector2],
	thickness: float,
	material: StandardMaterial3D,
	mirror: float
) -> MeshInstance3D:
	var points: Array[Vector3] = []
	for point in outline:
		points.append(Vector3(point.x, 0.0, point.y * mirror))

	var centre: Vector3 = Vector3.ZERO
	for point in points:
		centre += point
	centre /= float(points.size())

	var up: Vector3 = Vector3.UP * thickness * 0.5
	var down: Vector3 = Vector3.DOWN * thickness * 0.5

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(PackedVector2Array(outline))
	for index in range(0, triangles.size(), 3):
		var a: Vector3 = points[triangles[index]]
		var b: Vector3 = points[triangles[index + 1]]
		var c: Vector3 = points[triangles[index + 2]]
		_face(st, a + up, b + up, c + up, Vector3.UP)
		_face(st, a + down, b + down, c + down, Vector3.DOWN)

	for corner in points.size():
		var next: int = (corner + 1) % points.size()
		var outward: Vector3 = (points[corner] + points[next]) * 0.5 - centre
		outward.y = 0.0
		_face(st, points[corner] + up, points[next] + up, points[next] + down, outward)
		_face(st, points[corner] + up, points[next] + down, points[corner] + down, outward)

	st.generate_normals()
	return _mesh_node(st.commit(), material)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_face(st, a, b, c, outward)
	_face(st, a, c, d, outward)


## Winding is decided per triangle by checking the face normal against the side it
## is supposed to face. It costs a dot product and removes the usual failure mode
## of a hand-built mesh: a face that comes out inside-out and lights like a hole.
func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
		return
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Two additive, unshaded cones per nozzle: a wide plume and a thin core. The
## materials are shared by both nozzles, so one colour update per frame is enough
## and the two sides can never drift apart.
func _build_thrusters() -> void:
	_thruster_plumes_material = _make_thruster_material(Color(0.22, 0.6, 1.0, 0.12))
	_thruster_cores_material = _make_thruster_material(Color(0.88, 0.98, 1.0, 0.25))

	_add_thruster(-THRUSTER_Z, 0.19, _thruster_plumes_material, _thruster_plumes)
	_add_thruster(THRUSTER_Z, 0.19, _thruster_plumes_material, _thruster_plumes)
	_add_thruster(-THRUSTER_Z, 0.09, _thruster_cores_material, _thruster_cores)
	_add_thruster(THRUSTER_Z, 0.09, _thruster_cores_material, _thruster_cores)

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
## about Z lays it along X, pointing away from the nose.
func _add_thruster(
	z_offset: float,
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
	flame.position = Vector3(THRUSTER_X, 0.0, z_offset)
	_visual.add_child(flame)
	into.append(flame)


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
