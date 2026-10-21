class_name Arena
extends Node3D
## Planetary arena: the planet's surface is the play field. The ship flies over it,
## the camera keeps the ship centred, and the planet rolls under it as the ship
## travels, so there is no boundary and the whole surface is reachable.
##
## Everything gameplay-relevant happens on the y = 0 plane. The ground sits just
## below that plane, so hitboxes stay planar while the curvature is scenery.
##
## Rolling model: the planet is a sphere whose centre tracks the ship's planar
## position and whose orientation accumulates one rotation of |movement| /
## PLANET_RADIUS about the axis perpendicular to the movement. A sphere is
## rotation-invariant, so the geometry and normals never change in world space -
## only the terrain painted in object space flows past. Travelling 2 * PI *
## PLANET_RADIUS brings the same terrain back under the ship, which is what makes
## the planet finite and circumnavigable without a wall at the edge.

const PLANET_RADIUS: float = 80.0
const GROUND_Y: float = -1.5
const PLANET_SEGMENTS: int = 96
const PLANET_RINGS: int = 48

## The orbit has to fit inside the visible ground. At the 75 degree camera pitch
## the bottom of the screen is only about 26 units behind the ship, so a wider
## orbit puts the turret below the frame while it keeps firing.
const PATROL_RADIUS: float = 22.0

const RESPAWN_DELAY: float = 1.2
const ENEMY_SCENE: PackedScene = preload("res://entities/enemy/turret.tscn")

const STAR_COUNT: int = 700
const STAR_MIN_DISTANCE: float = 320.0
const STAR_MAX_DISTANCE: float = 430.0
const STAR_SEED: int = 20261021

const SURFACE_SHADER: Shader = preload("res://levels/arena/planet_surface.gdshader")

var _spawn_index: int = 0
var _planet: Node3D
var _last_player_position: Vector3 = Vector3.ZERO

@onready var _player: Player = %Player
@onready var _enemies: Node3D = %Enemies


func _ready() -> void:
	add_to_group(&"arena")
	# The planet must roll after the player has moved this physics frame, not
	# before it, or the terrain lags one frame behind the ship and shimmers.
	process_physics_priority = 100
	_build_environment()
	_build_stars()
	_build_planet()
	_last_player_position = _player.global_position
	_spawn_enemy()


func _physics_process(_delta: float) -> void:
	var current: Vector3 = _player.global_position
	var movement: Vector3 = current - _last_player_position
	_last_player_position = current

	_planet.global_position = Vector3(current.x, GROUND_Y - PLANET_RADIUS, current.z)
	_roll_planet(movement)


## Rotates the planet so the surface moves opposite to the ship, by exactly the
## arc length travelled. Rolling without slipping: the ship covers d, the sphere
## turns d / radius.
func _roll_planet(movement: Vector3) -> void:
	var distance: float = Vector2(movement.x, movement.z).length()
	if distance <= 0.0001:
		return

	var axis: Vector3 = Vector3(-movement.z, 0.0, movement.x).normalized()
	var spin: Basis = Basis(axis, distance / PLANET_RADIUS)
	var basis: Basis = (spin * _planet.global_transform.basis).orthonormalized()
	_planet.global_transform = Transform3D(basis, _planet.global_position)


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
	# Parented to the player so the sky travels with the ship. A lap is wider than
	# the star shell, and stars anchored to the world origin would be left behind
	# as an empty sky after a few hundred units.
	_player.add_child(instance)


func _build_planet() -> void:
	var ground_mesh: SphereMesh = SphereMesh.new()
	ground_mesh.radius = PLANET_RADIUS
	ground_mesh.height = PLANET_RADIUS * 2.0
	ground_mesh.radial_segments = PLANET_SEGMENTS
	ground_mesh.rings = PLANET_RINGS

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SURFACE_SHADER

	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = ground_mesh
	ground.material_override = material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_planet = Node3D.new()
	_planet.name = "Planet"
	_planet.position = Vector3(0.0, GROUND_Y - PLANET_RADIUS, 0.0)
	_planet.add_child(ground)
	add_child(_planet)


func _spawn_enemy() -> void:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	_enemies.add_child(enemy)

	# Spawn beside the ship, alternating flanks, so the first pattern is readable
	# instead of arriving from outside the camera. The angle is relative to the
	# ship, not to the world: the world origin means nothing now that the planet
	# rolls and the ship can be anywhere.
	var flank: float = 0.62 if _spawn_index % 2 == 0 else -0.62
	_spawn_index += 1

	enemy.setup_orbit(PATROL_RADIUS, flank)
	enemy.killed.connect(_on_enemy_killed)


func _on_enemy_killed() -> void:
	GlobalEventBus.enemy_killed.emit()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if is_inside_tree():
		_spawn_enemy()
