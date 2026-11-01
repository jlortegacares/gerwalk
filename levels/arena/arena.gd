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
##
## Encounters are streamed rather than placed: turrets roam the surface on their
## own and are spawned ahead of the ship, so travelling is how the player finds
## them and leaving them behind is how the planet stays worth crossing.

## A lap is 2 * PI * PLANET_RADIUS, so this single number is "how much planet
## there is to cross". At 1600 a lap is about 10053 units, roughly 6 minutes at
## GERWALK cruise and 3.5 at FIGHTER cruise.
##
## It is also the curvature knob: the camera sits 51.5 units above the surface,
## and past a radius of about 100 the top of the screen meets the ground before
## the horizon, so the limb leaves the frame and the planet reads as a surface
## instead of a globe.
const PLANET_RADIUS: float = 1600.0
const GROUND_Y: float = -1.5

## Tessellation has to track the radius, or the ground bobs. The facets are
## chords, so the surface sits below the true sphere by roughly
## (vertex spacing)^2 / (8 * radius) at the centre of each triangle. With the old
## 400-unit planet and 96 segments that gap was 0.21 units; at 1600 the same
## segment count would make it 0.86 units and the terrain would visibly rise and
## fall under the ship as the facets roll past. Doubling both counts keeps the
## gap at 0.21 units for a quarter of the curvature.
const PLANET_SEGMENTS: int = 192
const PLANET_RINGS: int = 96

## Encounters. The planet is far too large to hold a fixed set of turrets around
## the ship, so the arena streams them: a small population follows the player at
## a distance, spawning off screen ahead and freeing whoever was left behind.
const MAX_ENEMIES: int = 3
const SPAWN_INTERVAL: float = 2.0
const FIRST_SPAWN_DISTANCE: float = 30.0
const FIRST_SPAWN_ANGLE: float = 0.42
const SPAWN_DISTANCE_MIN: float = 85.0
const SPAWN_DISTANCE_MAX: float = 110.0
## Half-width of the cone around the ship's heading where new turrets appear.
const SPAWN_HEADING_SPREAD: float = 0.7
const DESPAWN_DISTANCE: float = 190.0
const SPAWN_SEED: int = 20261022

const ENEMY_SCENE: PackedScene = preload("res://entities/enemy/turret.tscn")
const MISSILE_ENEMY_SCENE: PackedScene = preload("res://entities/enemy/missile_enemy.tscn")
const FIGHTER_ENEMY_SCENE: PackedScene = preload("res://entities/enemy/fighter_enemy.tscn")
## One launcher in three. It is a priority target, not the baseline pressure: a ring
## of them would turn every encounter into a missile-only fight.
const MISSILE_ENEMY_SHARE: float = 0.34
## And one interceptor in five. It is the only contact that chases the ship across
## the surface, so it stays a minority: a sky of them would make every fight the
## same chase, and the planet would stop being a place to explore.
const FIGHTER_ENEMY_SHARE: float = 0.20

const STAR_COUNT: int = 700
const STAR_MIN_DISTANCE: float = 320.0
const STAR_MAX_DISTANCE: float = 430.0
const STAR_SEED: int = 20261021

const SURFACE_SHADER: Shader = preload("res://levels/arena/planet_surface.gdshader")

var _spawn_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _planet: Node3D
var _last_player_position: Vector3 = Vector3.ZERO
## The run's score. The arena owns it because the arena is the run: reloading the
## scene on a death starts a fresh one at zero.
var _score: int = 0

@onready var _player: Player = %Player
@onready var _enemies: Node3D = %Enemies


func _ready() -> void:
	add_to_group(&"arena")
	GlobalEventBus.enemy_killed.connect(_on_enemy_killed)
	# The planet must roll after the player has moved this physics frame, not
	# before it, or the terrain lags one frame behind the ship and shimmers.
	process_physics_priority = 100
	_build_environment()
	_build_stars()
	_build_planet()

	_last_player_position = _player.global_position
	_rng.seed = SPAWN_SEED
	# One turret within engagement range so the prototype starts with a fight;
	# the streaming spawner brings the rest once the ship starts exploring. It is
	# forced to a turret on purpose: the opening contact is the one the player
	# learns the game on, and a chase or a launcher is not the first lesson.
	_spawn_timer = SPAWN_INTERVAL
	_spawn_enemy(FIRST_SPAWN_DISTANCE, FIRST_SPAWN_ANGLE, ENEMY_SCENE)


func _physics_process(delta: float) -> void:
	var current: Vector3 = _player.global_position
	var movement: Vector3 = current - _last_player_position
	_last_player_position = current

	_planet.global_position = Vector3(current.x, GROUND_Y - PLANET_RADIUS, current.z)
	_roll_planet(movement)
	_maintain_population(delta)


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
	# The city chart is measured in units, so the shader needs the radius to turn
	# its cube-sphere coordinates into distances.
	material.set_shader_parameter("planet_radius", PLANET_RADIUS)

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


## Keeps a small population of turrets around the ship. Whoever was left farther
## than the despawn radius is freed, which stops a long flight from piling up idle
## nodes, and the replacement spawns ahead of the ship so exploring keeps
## producing encounters instead of emptying the planet.
func _maintain_population(delta: float) -> void:
	_spawn_timer = maxf(_spawn_timer - delta, 0.0)

	var alive: int = 0
	for node in _enemies.get_children():
		var enemy: Enemy = node as Enemy
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if _planar_distance(enemy.global_position) > DESPAWN_DISTANCE:
			enemy.queue_free()
			continue
		alive += 1

	if alive >= MAX_ENEMIES or _spawn_timer > 0.0:
		return

	_spawn_timer = SPAWN_INTERVAL
	_spawn_enemy(
		_rng.randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX),
		_spawn_angle()
	)


func _planar_distance(point: Vector3) -> float:
	return Vector2(
		point.x - _player.global_position.x,
		point.z - _player.global_position.z
	).length()


## Bias new turrets to the hemisphere the ship is heading into. A plain ring
## would drop half of them behind the player, where they are despawned without
## ever being seen.
func _spawn_angle() -> float:
	var heading: Vector2 = Vector2(_player.velocity.x, _player.velocity.z)
	var base: float = _rng.randf() * TAU
	if heading.length() > 2.0:
		base = heading.angle()
	return base + _rng.randf_range(-SPAWN_HEADING_SPREAD, SPAWN_HEADING_SPREAD)


func _spawn_enemy(
	distance: float, angle: float, scene: PackedScene = null
) -> void:
	if scene == null:
		scene = _pick_enemy_scene()

	var enemy: Enemy = scene.instantiate()
	_enemies.add_child(enemy)

	var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * distance
	enemy.setup_spawn(_player.global_position + offset)


## One roll, three buckets: the share of the launcher and the interceptor are read
## against the same number so the two cannot drift out of tune with each other.
func _pick_enemy_scene() -> PackedScene:
	var roll: float = _rng.randf()
	if roll < MISSILE_ENEMY_SHARE:
		return MISSILE_ENEMY_SCENE
	if roll < MISSILE_ENEMY_SHARE + FIGHTER_ENEMY_SHARE:
		return FIGHTER_ENEMY_SCENE
	return ENEMY_SCENE


## Every kill pays what the hull was worth. The enemy emits the event with its own
## value, so the total does not depend on which spawn path produced it.
func _on_enemy_killed(value: int) -> void:
	_score += value
	GlobalEventBus.score_changed.emit(_score)


## Read-only view of the run's score. The HUD reads the signal; this exists so the
## smoke test can assert the total without parsing the label.
func score() -> int:
	return _score
