class_name Projectile
extends Area3D
## Lightweight bullet. Travels in a straight line on the play plane, reports the
## hit, then frees. Prototype scale: node-per-bullet. If NFR-05 (400 concurrent)
## becomes the bottleneck, migrate to a pooled manager before adding content.
##
## Everything lives on the y = 0 plane. The third dimension is presentation, not
## gameplay: hitboxes stay planar so bullet patterns keep the readability the
## twin-stick genre depends on.

enum Team {
	PLAYER,
	ENEMY,
}

## Collision layers (1-based in the editor, bit index here).
const LAYER_WORLD: int = 0
const LAYER_PLAYER: int = 1
const LAYER_PLAYER_BULLET: int = 2
const LAYER_ENEMY: int = 3
const LAYER_ENEMY_BULLET: int = 4

const LIFETIME: float = 3.5
const PLAYER_COLOR: Color = Color(0.55, 0.98, 0.9, 1.0)
const ENEMY_COLOR: Color = Color(1.0, 0.42, 0.52, 1.0)

## Elongated on Z so a single Y rotation aligns the long axis with travel.
const DART_SIZE: Vector3 = Vector3(0.42, 0.34, 1.6)
const ORB_RADIUS: float = 0.55

@export var impact_scene: PackedScene

var _velocity: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _damage: int = 1
var _team: Team = Team.PLAYER
var _life: float = LIFETIME
var _target: Node3D = null
var _turn_rate: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if _team == Team.ENEMY:
		add_to_group(&"enemy_bullet")


## `tint` lets a player weapon keep its own colour (a warm missile, a plasma
## bolt) while the team still owns the shape and the collision layers. A
## transparent tint means "use the team colour".
func setup(
	direction: Vector3,
	speed: float,
	team: Team,
	damage: int = 1,
	size: Vector3 = DART_SIZE,
	target: Node3D = null,
	turn_rate: float = 0.0,
	tint: Color = Color(0.0, 0.0, 0.0, 0.0),
	lifetime: float = LIFETIME
) -> void:
	_team = team
	_damage = damage
	_speed = speed
	_target = target
	_turn_rate = turn_rate
	_life = lifetime
	# Enemy fire is tagged here rather than in _ready because callers add the node
	# to the tree before running setup, so the team is unknown at ready time.
	if _team == Team.ENEMY:
		add_to_group(&"enemy_bullet")
	else:
		remove_from_group(&"enemy_bullet")
	_velocity = Vector3(direction.x, 0.0, direction.z).normalized() * speed
	rotation.y = atan2(_velocity.x, _velocity.z)

	var color: Color = tint
	if color.a <= 0.0:
		color = PLAYER_COLOR if _team == Team.PLAYER else ENEMY_COLOR

	# Shape and tint both encode the team: colour alone fails NFR-08 under
	# bullet density, and shape survives a colour-blind pass. Guidance does not
	# change the shape, so a homing shot stays readable as a friendly dart.
	if _team == Team.PLAYER:
		collision_layer = 1 << LAYER_PLAYER_BULLET
		collision_mask = (1 << LAYER_WORLD) | (1 << LAYER_ENEMY)
		_build_visual(size, color, false)
	else:
		collision_layer = 1 << LAYER_ENEMY_BULLET
		collision_mask = (1 << LAYER_WORLD) | (1 << LAYER_PLAYER)
		_build_visual(Vector3.ONE * ORB_RADIUS, color, true)


func _build_visual(size: Vector3, color: Color, is_orb: bool) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	if is_orb:
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = size.x
		sphere.height = size.x * 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		mesh_instance.mesh = sphere
	else:
		var box: BoxMesh = BoxMesh.new()
		box.size = size
		mesh_instance.mesh = box

	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


func _physics_process(delta: float) -> void:
	_steer(delta)
	global_position += _velocity * delta
	_life -= delta

	# The planet has no edge, so lifetime is the only bound on a missed shot.
	if _life <= 0.0:
		queue_free()


## Homing shots keep their speed and turn towards the target at a fixed rate, so
## the curve is legible: snapping instantly would look like a second aim, and an
## unbounded turn would orbit the target instead of arriving. A freed target (it
## died mid-flight) simply leaves the shot flying straight.
func _steer(delta: float) -> void:
	if _turn_rate <= 0.0 or not is_instance_valid(_target):
		return

	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return

	var heading: Vector3 = _velocity.normalized()
	var angle: float = heading.signed_angle_to(to_target.normalized(), Vector3.UP)
	var step: float = clampf(angle, -_turn_rate * delta, _turn_rate * delta)
	_velocity = heading.rotated(Vector3.UP, step) * _speed
	rotation.y = atan2(_velocity.x, _velocity.z)


func _on_body_entered(body: Node3D) -> void:
	if body is Player and _team == Team.ENEMY:
		body.take_damage(_damage, global_position)
	elif body is Enemy and _team == Team.PLAYER:
		body.take_damage(_damage)

	_spawn_impact()
	queue_free()


func _spawn_impact() -> void:
	if impact_scene == null:
		return
	var impact: Node3D = impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position
