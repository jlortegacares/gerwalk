class_name Enemy
extends CharacterBody3D
## Orbital turret. Circles the arena at a fixed radius, so it can never wedge
## itself against the boundary. Alternates a slow dense ring with a fast narrow
## fan, and telegraphs before each pattern so deaths stay attributable.
##
## Positions are computed on the y = 0 play plane. The arena root sits at the
## world origin, so the arena centre is the origin too.

enum State {
	APPROACH,
	TELEGRAPH,
	RECOVER,
	DEAD,
}

enum Pattern {
	RING,
	FAN,
}

const MAX_HP: int = 10
const ORBIT_SPEED: float = 0.30
const FLEE_DISTANCE: float = 23.0
const FLEE_LOCK_TIME: float = 1.4
## The turret cannot wander further than this from the player's angle. Without a
## leash it orbits out of view and shoots from off-screen, which breaks failure
## attribution: the player cannot name what hit them.
const ANGULAR_LEASH: float = 1.25
## Keep the orbit clear of the planet edge so the turret is never clamped on top
## of the boundary line.
const EDGE_CLEARANCE: float = 8.0
const APPROACH_TIME: float = 1.2
const TELEGRAPH_TIME: float = 0.42
const RECOVER_TIME: float = 1.85

const RING_BULLETS: int = 14
const RING_SPEED: float = 17.8
const FAN_BULLETS: int = 5
const FAN_CONVERGENCE: float = 0.34
const FAN_SPEED: float = 33.0

const BODY_RADIUS: float = 1.9
const CORE_RADIUS: float = 0.9

const BASE_COLOR: Color = Color(0.93, 0.36, 0.48, 1.0)
const TELEGRAPH_COLOR: Color = Color(1.0, 0.93, 0.72, 1.0)

signal killed

@export var bullet_scene: PackedScene

var _hp: int = MAX_HP
var _state: State = State.APPROACH
var _pattern: Pattern = Pattern.RING
var _timer: float = APPROACH_TIME
var _player: Player = null
var _hit_flash: float = 0.0

var _orbit_radius: float = 30.0
var _angle: float = 0.0
var _angular_direction: float = 1.0
var _flee_lock: float = 0.0

var _visual: Node3D
var _material: StandardMaterial3D
var _aim_beam: MeshInstance3D


func _ready() -> void:
	add_to_group(&"enemy")
	_build_visual()
	_build_aim_beam()


func setup_orbit(radius: float, angle: float, arena_radius: float) -> void:
	_orbit_radius = clampf(radius, EDGE_CLEARANCE, arena_radius - EDGE_CLEARANCE)
	_angle = angle
	_sync_position()


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_visual.scale = Vector3.ONE * (1.0 + _hit_flash * 3.0)

	if not is_instance_valid(_player):
		_player = _find_player()

	_timer -= delta
	_flee_lock = maxf(_flee_lock - delta, 0.0)

	match _state:
		State.APPROACH:
			_tick_orbit(delta)
			if _timer <= 0.0:
				_enter_telegraph()
		State.TELEGRAPH:
			_tick_telegraph()
			if _timer <= 0.0:
				_fire_pattern()
				_enter_recover()
		State.RECOVER:
			if _timer <= 0.0:
				_enter_telegraph()


func _tick_orbit(delta: float) -> void:
	if _player != null and _flee_lock <= 0.0:
		if global_position.distance_to(_player.global_position) < FLEE_DISTANCE:
			_angular_direction *= -1.0
			_flee_lock = FLEE_LOCK_TIME

	if _player != null:
		var player_angle: float = atan2(_player.global_position.z, _player.global_position.x)
		var angle_gap: float = wrapf(player_angle - _angle, -PI, PI)
		if absf(angle_gap) > ANGULAR_LEASH:
			_angular_direction = signf(angle_gap)

	_angle = wrapf(_angle + _angular_direction * ORBIT_SPEED * delta, 0.0, TAU)
	_sync_position()


func _sync_position() -> void:
	global_position = Vector3(cos(_angle), 0.0, sin(_angle)) * _orbit_radius


func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = TELEGRAPH_TIME
	_aim_beam.visible = _pattern == Pattern.FAN


func _tick_telegraph() -> void:
	var progress: float = 1.0 - clampf(_timer / TELEGRAPH_TIME, 0.0, 1.0)
	_set_body_color(BASE_COLOR.lerp(TELEGRAPH_COLOR, progress))

	if _player != null:
		var offset: Vector3 = _player.global_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > 0.001:
			_aim_beam.position = offset * 0.5
			_aim_beam.rotation.y = atan2(offset.x, offset.z)
			_aim_beam.scale.z = distance


func _enter_recover() -> void:
	_state = State.RECOVER
	_timer = RECOVER_TIME
	_set_body_color(BASE_COLOR)
	_aim_beam.visible = false


func _fire_pattern() -> void:
	if _player == null or bullet_scene == null:
		return

	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var aim_at_player: Vector3 = to_player.normalized()

	match _pattern:
		Pattern.RING:
			for i in RING_BULLETS:
				var angle: float = TAU * float(i) / float(RING_BULLETS)
				_spawn_bullet(Vector3(cos(angle), 0.0, sin(angle)), RING_SPEED)
		Pattern.FAN:
			for i in FAN_BULLETS:
				var offset_index: float = float(i) - float(FAN_BULLETS - 1) * 0.5
				var offset: float = offset_index * FAN_CONVERGENCE
				_spawn_bullet(aim_at_player.rotated(Vector3.UP, offset), FAN_SPEED)

	_pattern = Pattern.FAN if _pattern == Pattern.RING else Pattern.RING


func _spawn_bullet(direction: Vector3, speed: float) -> void:
	var bullet: Projectile = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position
	bullet.setup(direction, speed, Projectile.Team.ENEMY, 1)


func take_damage(amount: int) -> void:
	if _state == State.DEAD:
		return

	_hp -= amount
	_hit_flash = 0.12

	if _hp <= 0:
		_die()


func _die() -> void:
	_state = State.DEAD
	killed.emit()
	queue_free()


func _find_player() -> Player:
	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	for node in players:
		if node is Player:
			return node
	return null


func _set_body_color(color: Color) -> void:
	_material.albedo_color = color
	_material.emission = color


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_material = StandardMaterial3D.new()
	_material.albedo_color = BASE_COLOR
	_material.emission_enabled = true
	_material.emission = BASE_COLOR
	_material.emission_energy_multiplier = 0.8
	_material.roughness = 0.5

	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius = BODY_RADIUS
	body_mesh.bottom_radius = BODY_RADIUS
	body_mesh.height = 0.7
	body_mesh.radial_segments = 6

	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = body_mesh
	body.material_override = _material
	_visual.add_child(body)

	var core_material: StandardMaterial3D = StandardMaterial3D.new()
	core_material.albedo_color = Color(0.12, 0.05, 0.08, 1.0)
	core_material.roughness = 1.0

	var core_mesh: CylinderMesh = CylinderMesh.new()
	core_mesh.top_radius = CORE_RADIUS
	core_mesh.bottom_radius = CORE_RADIUS
	core_mesh.height = 0.8
	core_mesh.radial_segments = 6

	var core: MeshInstance3D = MeshInstance3D.new()
	core.mesh = core_mesh
	core.material_override = core_material
	_visual.add_child(core)


func _build_aim_beam() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.43, 0.52, 0.45)

	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(0.14, 0.05, 1.0)

	_aim_beam = MeshInstance3D.new()
	_aim_beam.mesh = beam_mesh
	_aim_beam.material_override = material
	_aim_beam.visible = false
	_aim_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_beam)
