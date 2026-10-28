class_name Enemy
extends CharacterBody3D
## Planet turret. It lives on the planet: it roams the surface on its own until
## the ship comes close, then it chases the ship, orbits it and fires. Fly far
## enough and it loses interest and goes back to roaming, which is what lets the
## player leave an encounter behind and find another one.
##
## Alternates a slow dense ring with a fast narrow fan, and telegraphs before each
## pattern so deaths stay attributable.
##
## Positions are computed on the y = 0 play plane, so hitboxes stay planar. The
## turret keeps its own world position instead of deriving it from the ship: the
## planet is large enough to explore, and an enemy pinned to the ship would make
## exploring pointless.

enum State {
	ROAM,
	ENGAGED,
	TELEGRAPH,
	RECOVER,
	DEAD,
}

enum Pattern {
	RING,
	FAN,
}

const MAX_HP: int = 10

## Engagement. Pursuit speed is deliberately below the ship's top speed (26.8):
## the player must always be able to break away instead of being towed forever.
const AGGRO_RADIUS: float = 46.0
const LEASH_RADIUS: float = 78.0
const ORBIT_RADIUS: float = 22.0
const PURSUIT_SPEED: float = 24.0
const STRAFE_SPEED: float = 7.0
## Delay between noticing the ship and the first telegraph. Without it the first
## pattern arrives before the player can read the new threat.
const APPROACH_TIME: float = 1.2

## Roaming. The turret crosses the surface on its own between waypoints, so the
## planet is inhabited rather than populated by static props.
const ROAM_SPEED: float = 7.5
const ROAM_LEG_MIN: float = 12.0
const ROAM_LEG_MAX: float = 38.0
const ROAM_LEG_TIME: float = 5.0
const ROAM_ARRIVAL_DISTANCE: float = 0.8

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
var _state: State = State.ROAM
var _pattern: Pattern = Pattern.RING
var _timer: float = 0.0
var _player: Player = null
var _hit_flash: float = 0.0

var _roam_target: Vector3 = Vector3.ZERO
var _roam_timer: float = 0.0
var _strafe_direction: float = 1.0

## Per-variant presentation and timing. They live here instead of being read
## straight from the constants so a variant can repaint itself and commit longer
## without copying the state machine.
var _base_color: Color = BASE_COLOR
var _telegraph_time: float = TELEGRAPH_TIME
var _recover_time: float = RECOVER_TIME

var _visual: Node3D
var _material: StandardMaterial3D
var _aim_beam: MeshInstance3D


func _ready() -> void:
	add_to_group(&"enemy")
	_player = _find_player()
	_build_visual()
	_build_aim_beam()


## Called by the arena right after the turret enters the tree.
func setup_spawn(spawn_position: Vector3) -> void:
	global_position = spawn_position
	_pick_roam_target()


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_visual.scale = Vector3.ONE * (1.0 + _hit_flash * 3.0)

	if not is_instance_valid(_player):
		_player = _find_player()

	if _player == null:
		return

	var distance: float = _planar_distance_to(_player.global_position)
	if _state == State.ROAM:
		if distance < AGGRO_RADIUS:
			_enter_engaged()
	elif distance > LEASH_RADIUS:
		_enter_roam()
		return

	_timer -= delta

	match _state:
		State.ROAM:
			_tick_roam(delta)
		State.ENGAGED:
			_tick_engaged(delta)
			if _timer <= 0.0:
				_enter_telegraph()
		State.TELEGRAPH:
			_tick_engaged(delta)
			_tick_telegraph()
			if _timer <= 0.0:
				_fire_pattern()
				_enter_recover()
		State.RECOVER:
			_tick_engaged(delta)
			if _timer <= 0.0:
				_enter_telegraph()


func _tick_roam(delta: float) -> void:
	_roam_timer -= delta
	var to_target: Vector3 = _roam_target - global_position
	to_target.y = 0.0

	if _roam_timer <= 0.0 or to_target.length() < ROAM_ARRIVAL_DISTANCE:
		_pick_roam_target()
		return

	global_position += to_target.normalized() * ROAM_SPEED * delta


func _pick_roam_target() -> void:
	var angle: float = randf() * TAU
	var distance: float = randf_range(ROAM_LEG_MIN, ROAM_LEG_MAX)
	_roam_target = global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	_roam_timer = ROAM_LEG_TIME


## Holding the ring: chase when far, back off when the player dashes in, strafe
## in between. Steering in world space (instead of recomputing the position from
## the ship) is what makes the leash possible at all.
func _tick_engaged(delta: float) -> void:
	var offset: Vector3 = _player.global_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance < 0.001:
		return

	var to_player: Vector3 = offset / distance
	var step: Vector3
	if distance > ORBIT_RADIUS * 1.2:
		step = to_player * PURSUIT_SPEED
	elif distance < ORBIT_RADIUS * 0.8:
		step = -to_player * PURSUIT_SPEED
	else:
		step = Vector3(-to_player.z, 0.0, to_player.x) * (STRAFE_SPEED * _strafe_direction)

	global_position += step * delta


func _enter_engaged() -> void:
	_state = State.ENGAGED
	_timer = APPROACH_TIME
	_strafe_direction = 1.0 if randf() < 0.5 else -1.0


func _enter_roam() -> void:
	_state = State.ROAM
	_aim_beam.visible = false
	_set_body_color(_base_color)
	_pick_roam_target()


func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = _telegraph_time
	_aim_beam.visible = _pattern == Pattern.FAN


func _tick_telegraph() -> void:
	var progress: float = 1.0 - clampf(_timer / _telegraph_time, 0.0, 1.0)
	_set_body_color(_base_color.lerp(TELEGRAPH_COLOR, progress))

	var offset: Vector3 = _player.global_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > 0.001:
		_aim_beam.position = offset * 0.5
		_aim_beam.rotation.y = atan2(offset.x, offset.z)
		_aim_beam.scale.z = distance


func _enter_recover() -> void:
	_state = State.RECOVER
	_timer = _recover_time
	_set_body_color(_base_color)
	_aim_beam.visible = false


func _fire_pattern() -> void:
	if bullet_scene == null:
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


## Read-only view of the pool. The player still owns damage; this exists so the
## smoke test can assert what a weapon actually did to a target.
func current_hp() -> int:
	return _hp


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


func _planar_distance_to(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


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
	_material.albedo_color = _base_color
	_material.emission_enabled = true
	_material.emission = _base_color
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
