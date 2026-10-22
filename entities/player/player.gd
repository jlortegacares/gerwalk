class_name Player
extends CharacterBody3D
## Twin-stick player: movement and aim are fully independent.
## Left stick / WASD moves. Right stick or mouse aims. Fire is decoupled from facing.
##
## Everything the player does happens on the y = 0 play plane. The third dimension
## is presentation only, so hitboxes stay planar and bullet patterns keep the
## readability the genre depends on.
##
## The Camera3D is a child of this node and the rig never rotates, so the player
## is pinned to the exact centre of the screen no matter where it is on the
## planet's surface.

const MAX_SPEED: float = 26.8
const ACCELERATION: float = 260.0
const FRICTION: float = 300.0
const AIM_DEADZONE: float = 0.30

const MAX_HP: int = 6
const IFRAME_DURATION: float = 0.85

const DASH_SPEED: float = 64.0
const DASH_DURATION: float = 0.16
const DASH_COOLDOWN: float = 0.85

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

	_weapons = WeaponSystem.new()
	_weapons.name = "Weapons"
	_weapons.setup(bullet_scene)
	add_child(_weapons)

	GlobalEventBus.player_health_changed.emit.call_deferred(_hp, MAX_HP)
	GlobalEventBus.player_turbo_changed.emit.call_deferred(_turbo, TURBO_MAX)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not _alive:
		return

	if Input.is_action_just_pressed(&"dash") and _dash_cooldown <= 0.0:
		_start_dash()

	if _dash_time > 0.0:
		velocity = _dash_direction * DASH_SPEED
		velocity.y = 0.0
		move_and_slide()
	else:
		_move(delta)

	_update_aim()
	_update_weapons(delta)
	_update_afterburner_visual(delta)


func _move(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down"
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

	_layout_flames(_thruster_plumes, 0.35 + thrust * 1.65)
	_layout_flames(_thruster_cores, 0.28 + thrust * 1.00)

	# The wings follow the throttle: the tip swings aft as the ship gets faster,
	# which is the swing-wing signature and a free speed cue beside the flames.
	var sweep: float = deg_to_rad(lerpf(WING_SWEEP_FORWARD, WING_SWEEP_BACK, thrust))
	_wing_right.rotation.y = -sweep
	_wing_left.rotation.y = sweep

	_thruster_plumes_material.albedo_color = Color(
		lerpf(0.22, 0.5, heat), lerpf(0.6, 0.85, heat), 1.0, 0.08 + thrust * 0.24
	)
	_thruster_cores_material.albedo_color = Color(0.88, 0.98, 1.0, 0.18 + thrust * 0.45)

	if camera == null:
		return
	var target_fov: float = _base_fov + (FOV_BOOST_KICK if _boosting else 0.0)
	camera.fov = move_toward(camera.fov, target_fov, FOV_RATE * delta)


## The cone's tip trails behind the nozzle, so growing it must move it back by the
## same amount or the base would detach from the hull.
func _layout_flames(flames: Array[MeshInstance3D], length: float) -> void:
	for flame in flames:
		flame.scale = Vector3(1.0, length, 1.0)
		flame.position.x = THRUSTER_X - length * 0.5


func _start_dash() -> void:
	var input_direction: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down"
	)
	var flat: Vector3 = Vector3(input_direction.x, 0.0, input_direction.y)
	_dash_direction = flat.normalized() if flat.length_squared() > 0.0 else _aim_direction
	_dash_time = DASH_DURATION
	_dash_cooldown = DASH_COOLDOWN
	_spawn_impact()


func _update_aim() -> void:
	var stick_aim: Vector2 = Input.get_vector(
		&"aim_left", &"aim_right", &"aim_up", &"aim_down"
	)

	if stick_aim.length() > AIM_DEADZONE:
		_aim_direction = Vector3(stick_aim.x, 0.0, stick_aim.y).normalized()
	else:
		var to_mouse: Vector3 = _mouse_direction_on_plane()
		if to_mouse.length_squared() > 0.0001:
			_aim_direction = to_mouse

	_visual.rotation.y = atan2(-_aim_direction.z, _aim_direction.x)
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

	if Input.is_action_just_pressed(&"bomb"):
		_weapons.fire_bomb(global_position)

	var stick_aim: Vector2 = Input.get_vector(
		&"aim_left", &"aim_right", &"aim_up", &"aim_down"
	)
	var wants_fire: bool = Input.is_action_pressed(&"fire") or stick_aim.length() > AIM_DEADZONE

	_weapons.tick(
		delta,
		global_position,
		global_position + _aim_direction * MUZZLE_DISTANCE,
		_aim_direction,
		wants_fire
	)


func _tick_timers(delta: float) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_dash_time = maxf(_dash_time - delta, 0.0)

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
