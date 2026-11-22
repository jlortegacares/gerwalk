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
## Encounters are streamed rather than placed: interceptors patrol the open air on
## their own and are spawned ahead of the ship, so travelling is how the player
## finds them and leaving them behind is how the planet stays worth crossing.

const SCENE_PATH: String = "res://levels/arena/arena.tscn"

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

## Encounters. The planet is far too large to hold a fixed set of contacts around
## the ship, so the arena streams them: a small population follows the player at
## a distance, spawning off screen ahead and freeing whoever was left behind.
##
## The sky belongs to one archetype. The turret and the launcher are city fights --
## they hold ground and the district gives them something to hold -- while the
## planet is open air, where the interceptor's chase is the only encounter the space
## can stage. So the arena spawns interceptors and nothing else; the mothership is
## the one other thing that arrives, and it arrives on its own trigger.
const MAX_ENEMIES: int = 3
const SPAWN_INTERVAL: float = 2.0
## The opening contact is deliberately out of the interceptor's chase radius (62)
## and well outside its attack range (46): a contact that starts inside them fires
## on a player who has not moved the stick yet.
const FIRST_SPAWN_DISTANCE: float = 70.0
const FIRST_SPAWN_ANGLE: float = 0.42
const SPAWN_DISTANCE_MIN: float = 85.0
const SPAWN_DISTANCE_MAX: float = 110.0
## Half-width of the cone around the ship's heading where new contacts appear.
const SPAWN_HEADING_SPREAD: float = 0.7
const DESPAWN_DISTANCE: float = 190.0
const SPAWN_SEED: int = 20261022

const FIGHTER_ENEMY_SCENE: PackedScene = preload("res://entities/enemy/fighter_enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://entities/enemy/boss.tscn")
## The final encounter arrives once the run has earned it. Twelve downed
## interceptors is enough for the player to have learned the chase and to carry
## the weapons it takes to hurt a capital ship, so the mothership is a climax
## instead of a wall.
const BOSS_KILL_THRESHOLD: int = 12
## Far enough ahead that the hull clears the horizon before it starts shooting.
const BOSS_SPAWN_DISTANCE: float = 150.0

const STAR_COUNT: int = 700
const STAR_MIN_DISTANCE: float = 320.0
const STAR_MAX_DISTANCE: float = 430.0
const STAR_SEED: int = 20261021

const SURFACE_SHADER: Shader = preload("res://levels/arena/planet_surface.gdshader")
const PLANET_FIELD: String = "res://levels/arena/planet_field.res"
const PLANET_DETAIL: String = "res://levels/arena/planet_detail.res"

var _planet: Node3D
var _sun: DirectionalLight3D
var _surface: ShaderMaterial
var _last_player_position: Vector3 = Vector3.ZERO
## The run: the score on the HUD and the kills the boss threshold counts. Owned by
## the level because the level is the run: reloading the scene on a death starts a
## fresh one at zero, and the pilot's record must never decide the arrival.
var _run: RunState = RunState.new()
## The stream of contacts. See `EncounterDirector`.
var _director: EncounterDirector = null
var _boss_spawned: bool = false
var _boss: Boss = null

@onready var _player: Player = %Player
@onready var _enemies: Node3D = %Enemies


func _ready() -> void:
	add_to_group(&"arena")
	GlobalEventBus.enemy_killed.connect(_on_enemy_killed)
	# A run remembers where it started, so CONTINUE can reopen it. The level owns
	# this fact; the menu only reads it.
	GameProgress.instance().remember_scenario(SCENE_PATH)
	# The planet must roll after the player has moved this physics frame, not
	# before it, or the terrain lags one frame behind the ship and shimmers.
	process_physics_priority = 100
	_build_environment()
	_build_stars()
	_build_planet()
	_build_clouds()

	_last_player_position = _player.global_position
	_director = EncounterDirector.new()
	_director.player = _player
	_director.container = _enemies
	# The planet has one archetype, so there is no roll here: every streamed
	# contact is an interceptor. The turret and the launcher stay in the city's
	# pool. The mothership is exempt from the despawn: it is the encounter.
	_director.set_roster([FIGHTER_ENEMY_SCENE])
	_director.spawn_interval = SPAWN_INTERVAL
	_director.max_enemies = MAX_ENEMIES
	_director.spawn_distance_min = SPAWN_DISTANCE_MIN
	_director.spawn_distance_max = SPAWN_DISTANCE_MAX
	_director.despawn_distance = DESPAWN_DISTANCE
	_director.heading_spread = SPAWN_HEADING_SPREAD
	_director.spawn_seed = SPAWN_SEED
	_director.keeper = func(enemy: Enemy) -> bool: return enemy is Boss
	_director.begin()
	# One contact in view so the prototype starts with a fight; the streaming
	# spawner brings the rest once the ship starts exploring. It is placed beyond
	# the interceptor's attack range on purpose: the opening pass is a chase the
	# player joins, not a salvo they eat while reading the HUD.
	_director.spawn_opening(
		FIGHTER_ENEMY_SCENE, FIRST_SPAWN_DISTANCE, FIRST_SPAWN_ANGLE
	)


func _physics_process(delta: float) -> void:
	var current: Vector3 = _player.global_position
	var movement: Vector3 = current - _last_player_position
	_last_player_position = current

	_planet.global_position = Vector3(current.x, GROUND_Y - PLANET_RADIUS, current.z)
	_roll_planet(movement)
	_update_sun()
	_director.maintain(delta)


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


## The relief normals and the painted shadows live in object space, so the shader
## needs the sun expressed in the planet's own frame. It changes every frame: the
## planet rolls under a sun that does not.
func _update_sun() -> void:
	if _sun == null or _surface == null:
		return
	var toward_sun: Vector3 = _sun.global_transform.basis.z
	var local_sun: Vector3 = (_planet.global_transform.basis.inverse() * toward_sun).normalized()
	_surface.set_shader_parameter("sun_direction", local_sun)


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
	_sun = sun


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

	# The terrain's macro structure is baked, because it needs the whole planet at
	# once: a drainage network cannot be computed per pixel, and neither can the
	# answer to "is this inland of a coast". Six faces, one cubemap, sampled by the
	# object-space direction so the field belongs to the planet and rolls with it.
	var field: Resource = load(PLANET_FIELD)
	if field != null:
		var cube: Cubemap = Cubemap.new()
		cube.create_from_images(field.faces)
		material.set_shader_parameter("planet_field", cube)
		material.set_shader_parameter("relief_units", field.relief_units)
		material.set_shader_parameter("river_max_distance", field.river_max_distance)
		_surface = material

	# The detail layer is baked for a different reason: not because it needs the
	# whole planet, but because it was a fifth of the frame. Its gradient and cavity
	# are precomputed, so the fragment reads them instead of synthesising a
	# three-chain ridged field three times.
	var detail: Resource = load(PLANET_DETAIL)
	if detail != null:
		var detail_cube: Cubemap = Cubemap.new()
		detail_cube.create_from_images(detail.faces)
		material.set_shader_parameter("planet_detail", detail_cube)
		material.set_shader_parameter("detail_slope_range", detail.slope_range)

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


## The cloud deck is a level feature, not a skybox: the ship flies through it and a
## dense bank is cover from guided missiles. It streams around the ship the same way
## the encounters do, because the planet is far too wide to hold a fixed deck.
func _build_clouds() -> void:
	var clouds: CloudField = CloudField.new()
	clouds.name = "Clouds"
	add_child(clouds)
	clouds.setup(_player)


## Every kill pays what the hull was worth. The enemy emits the event with its own
## value, so the total does not depend on which spawn path produced it. The kill
## also counts toward the arrival: the fighters already on the field stay when the
## mothership comes, because the boss escalates the run instead of resetting it.
func _on_enemy_killed(value: int) -> void:
	_run.add_kill(value)
	if not _boss_spawned and _run.kills >= BOSS_KILL_THRESHOLD:
		spawn_boss()


## The final encounter. It arrives once per run, ahead of the ship, and the fighters
## already on the field stay: the arrival escalates the run instead of resetting it.
## Public because the suite and the capture tool need it without farming a run's worth
## of kills.
func spawn_boss() -> Boss:
	if _boss_spawned:
		return _boss

	_boss_spawned = true
	_boss = BOSS_SCENE.instantiate() as Boss
	_enemies.add_child(_boss)

	var angle: float = _director.angle()
	var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * BOSS_SPAWN_DISTANCE
	_boss.setup_spawn(_player.global_position + offset)
	return _boss


## Read-only view of the ship, so the suite can assert on it without reaching into
## the container's children.
func boss() -> Boss:
	return _boss


## The contact stream, so a test or the capture tool can park it instead of writing
## a sentinel into a private timer.
func director() -> EncounterDirector:
	return _director


## The run's counters. The HUD reads the signal; this exists so the suite can drive
## the arrival threshold and assert the total without parsing labels.
func run_state() -> RunState:
	return _run


## Read-only view of the run's score.
func score() -> int:
	return _run.score
