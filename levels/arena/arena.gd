class_name Arena
extends Node3D
## Planetary arena: the planet's surface *is* the play field. The ship flies over
## it, the camera keeps the ship centred, and the orbital ring is gone.
##
## Everything gameplay-relevant happens on the y = 0 plane. The ground sits just
## below that plane and starts curving away just past the play boundary, so the
## surface reads as a planet without forcing the ship, the enemies or the bullets
## to follow a curved height field. Hitboxes stay planar; the curvature is scenery.
##
## Geometry note: the ground is a surface of revolution, flat out to ARENA_RADIUS
## and falling away on a quadratic profile to RIM_DROP at GROUND_OUTER_RADIUS.
## Beyond that radius the mesh simply ends, which is the planet's limb. Because the
## drop starts exactly at the play boundary, the player sees the surface roll away
## into space as they reach the edge - the visual confirmation that the planet ends
## there. The ship never walks that slope: the boundary clamp runs on the flat part
## only, and anything outside ARENA_RADIUS is scenery.

const ARENA_RADIUS: float = 55.0
const GROUND_Y: float = -1.5
const GROUND_FLAT_RADIUS: float = 55.0
const GROUND_OUTER_RADIUS: float = 96.0
const RIM_DROP: float = 50.0
const GROUND_RINGS: int = 64
const GROUND_SEGMENTS: int = 128

const BOUNDARY_RING_THICKNESS: float = 0.14
const BOUNDARY_RING_COLOR: Color = Color(0.24, 0.9, 0.79, 0.35)

const RESPAWN_DELAY: float = 1.2
const ENEMY_SCENE: PackedScene = preload("res://entities/enemy/turret.tscn")

const PATROL_RADIUS_RATIO: float = 0.55
const ENEMY_CLEARANCE: float = 8.0

const STAR_COUNT: int = 700
const STAR_MIN_DISTANCE: float = 320.0
const STAR_MAX_DISTANCE: float = 430.0
const STAR_SEED: int = 20261021

const SURFACE_SHADER: Shader = preload("res://levels/arena/planet_surface.gdshader")

var _spawn_index: int = 0

@onready var _player: Player = %Player
@onready var _enemies: Node3D = %Enemies


func _ready() -> void:
	add_to_group(&"arena")
	_build_environment()
	_build_stars()
	_build_ground()
	_build_boundary_ring()
	_spawn_enemy()


## Ring the turret patrols. It stays well inside the boundary so the player can
## always close the gap and the fight never drifts off the visible surface.
func patrol_radius() -> float:
	return ARENA_RADIUS * PATROL_RADIUS_RATIO


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.018, 0.03)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.44, 0.58)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_angular_distance = 1.8
	sun.shadow_blur = 2.0
	sun.shadow_enabled = true
	add_child(sun)


func _build_stars() -> void:
	var star_mesh: BoxMesh = BoxMesh.new()
	star_mesh.size = Vector3.ONE

	var star_material: StandardMaterial3D = StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.albedo_color = Color(0.78, 0.85, 0.96)

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = star_mesh
	multimesh.instance_count = STAR_COUNT

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = STAR_SEED

	for i in STAR_COUNT:
		var direction: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var distance: float = rng.randf_range(STAR_MIN_DISTANCE, STAR_MAX_DISTANCE)
		var size: float = rng.randf_range(0.5, 1.2)
		var basis: Basis = Basis().scaled(Vector3.ONE * size)
		multimesh.set_instance_transform(
			i,
			Transform3D(basis, direction * distance)
		)

	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = star_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _build_ground() -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var stride: int = GROUND_SEGMENTS + 1

	for ring in range(GROUND_RINGS + 1):
		var radius: float = GROUND_OUTER_RADIUS * float(ring) / float(GROUND_RINGS)
		var height: float = GROUND_Y + _ground_drop(radius)
		var slope: float = _ground_slope(radius)

		for segment in range(stride):
			var angle: float = TAU * float(segment) / float(GROUND_SEGMENTS)
			var cos_angle: float = cos(angle)
			var sin_angle: float = sin(angle)
			vertices.append(Vector3(cos_angle * radius, height, sin_angle * radius))
			# The profile is a surface of revolution, so the normal is analytic:
			# no normal generation pass can invert it on a winding mistake.
			normals.append(
				Vector3(-slope * cos_angle, 1.0, -slope * sin_angle).normalized()
			)

	for ring in range(GROUND_RINGS):
		for segment in range(GROUND_SEGMENTS):
			var near: int = ring * stride + segment
			var near_next: int = near + 1
			var far: int = near + stride
			var far_next: int = far + 1
			indices.append_array([near, far, near_next, near_next, far, far_next])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var ground_mesh: ArrayMesh = ArrayMesh.new()
	ground_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SURFACE_SHADER

	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = ground_mesh
	ground.material_override = material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## Height of the surface relative to the play plane: flat through the play area,
## then a quadratic roll-off. Starting the curve with zero slope is what keeps the
## seam between the flat disc and the curved rim invisible.
func _ground_drop(radius: float) -> float:
	if radius <= GROUND_FLAT_RADIUS:
		return 0.0
	var span: float = GROUND_OUTER_RADIUS - GROUND_FLAT_RADIUS
	var t: float = (radius - GROUND_FLAT_RADIUS) / span
	return -RIM_DROP * t * t


func _ground_slope(radius: float) -> float:
	if radius <= GROUND_FLAT_RADIUS:
		return 0.0
	var span: float = GROUND_OUTER_RADIUS - GROUND_FLAT_RADIUS
	var t: float = (radius - GROUND_FLAT_RADIUS) / span
	return -2.0 * RIM_DROP * t / span


## The play boundary is invisible in the ground itself, so it needs a line: an
## invisible wall on open terrain is the one failure the player cannot attribute.
func _build_boundary_ring() -> void:
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = ARENA_RADIUS - BOUNDARY_RING_THICKNESS
	mesh.outer_radius = ARENA_RADIUS + BOUNDARY_RING_THICKNESS
	mesh.rings = 128
	mesh.ring_segments = 6

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = BOUNDARY_RING_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "BoundaryRing"
	instance.mesh = mesh
	instance.material_override = material
	instance.position.y = GROUND_Y + 0.05
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _spawn_enemy() -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	_enemies.add_child(enemy)

	# Spawn on the player's side of the arena, alternating flanks. Spawning at a
	# fixed angle drops the enemy outside the camera on the first frame.
	var flank: float = 0.62 if _spawn_index % 2 == 0 else -0.62
	var player_angle: float = atan2(_player.global_position.z, _player.global_position.x)
	_spawn_index += 1

	enemy.setup_orbit(patrol_radius(), player_angle + flank, ARENA_RADIUS)
	enemy.killed.connect(_on_enemy_killed)


func _on_enemy_killed() -> void:
	GlobalEventBus.enemy_killed.emit()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if is_inside_tree():
		_spawn_enemy()
