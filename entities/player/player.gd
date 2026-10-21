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

const FIRE_INTERVAL: float = 0.08
const BULLET_SPEED: float = 78.0

const DASH_SPEED: float = 64.0
const DASH_DURATION: float = 0.16
const DASH_COOLDOWN: float = 0.85

const BODY_RADIUS: float = 1.1
const MUZZLE_DISTANCE: float = 1.8
const BEAM_START: float = 2.4
const BEAM_LENGTH: float = 2.0

const BODY_COLOR: Color = Color(0.24, 0.9, 0.8, 1.0)
const CORE_COLOR: Color = Color(0.05, 0.11, 0.14, 1.0)

@export var bullet_scene: PackedScene
@export var impact_scene: PackedScene

var camera: Camera3D

var _hp: int = MAX_HP
var _aim_direction: Vector3 = Vector3.RIGHT
var _fire_cooldown: float = 0.0
var _invulnerable: float = 0.0
var _dash_time: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_direction: Vector3 = Vector3.RIGHT
var _alive: bool = true

var _visual: Node3D
var _visual_material: StandardMaterial3D
var _aim_beam: MeshInstance3D


func _ready() -> void:
	add_to_group(&"player")
	camera = %Camera
	_build_visual()
	_build_aim_beam()
	GlobalEventBus.player_health_changed.emit.call_deferred(_hp, MAX_HP)


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
	_update_firing()


func _move(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down"
	)
	# Screen up maps to -Z, so the ring reads the same as it did in 2D.
	var target: Vector3 = Vector3(input_direction.x, 0.0, input_direction.y) * MAX_SPEED

	if target.length_squared() > 0.0:
		velocity = velocity.move_toward(target, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, FRICTION * delta)

	velocity.y = 0.0
	move_and_slide()


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


func _update_firing() -> void:
	if _fire_cooldown > 0.0:
		return

	var stick_aim: Vector2 = Input.get_vector(
		&"aim_left", &"aim_right", &"aim_up", &"aim_down"
	)
	var wants_fire: bool = Input.is_action_pressed(&"fire") or stick_aim.length() > AIM_DEADZONE

	if wants_fire:
		_fire()
		_fire_cooldown = FIRE_INTERVAL


func _fire() -> void:
	if bullet_scene == null:
		return

	var bullet: Projectile = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position + _aim_direction * MUZZLE_DISTANCE
	bullet.setup(_aim_direction, BULLET_SPEED, Projectile.Team.PLAYER, 1)


func _tick_timers(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
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


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_visual_material = StandardMaterial3D.new()
	_visual_material.albedo_color = BODY_COLOR
	_visual_material.emission_enabled = true
	_visual_material.emission = BODY_COLOR
	_visual_material.emission_energy_multiplier = 1.4
	_visual_material.roughness = 0.4

	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius = BODY_RADIUS
	body_mesh.bottom_radius = BODY_RADIUS
	body_mesh.height = 0.55
	body_mesh.radial_segments = 8

	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = _visual_material
	_visual.add_child(body)

	# Nose on +X: the visual rotates so +X follows the aim vector.
	var nose_mesh: BoxMesh = BoxMesh.new()
	nose_mesh.size = Vector3(1.1, 0.35, 1.7)

	var nose: MeshInstance3D = MeshInstance3D.new()
	nose.mesh = nose_mesh
	nose.material_override = _visual_material
	nose.position = Vector3(1.05, 0.0, 0.0)
	_visual.add_child(nose)

	var core_material: StandardMaterial3D = StandardMaterial3D.new()
	core_material.albedo_color = CORE_COLOR
	core_material.roughness = 1.0

	var core_mesh: CylinderMesh = CylinderMesh.new()
	core_mesh.top_radius = 0.42
	core_mesh.bottom_radius = 0.42
	core_mesh.height = 0.58
	core_mesh.radial_segments = 8

	var core: MeshInstance3D = MeshInstance3D.new()
	core.mesh = core_mesh
	core.material_override = core_material
	_visual.add_child(core)


func _build_aim_beam() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b, 0.45)

	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(0.08, 0.08, 1.0)

	_aim_beam = MeshInstance3D.new()
	_aim_beam.mesh = beam_mesh
	_aim_beam.material_override = material
	_aim_beam.scale.z = BEAM_LENGTH
	_aim_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_beam)
