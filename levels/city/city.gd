class_name City
extends Node3D
## The second scenario: a night district the ship has to thread, street by street.
##
## The planet is an open field, so the city is its opposite. The play plane, the
## ship and every weapon are unchanged; what changes is that the level has walls.
## A tower is a real collider on the world layer, so the ship cannot pass through
## it and neither can a shot. The street grid is therefore the level: the only
## ways across the district are the roads, and the only shortcut through a wall is
## to spend the fire to bring it down.
##
## Encounters stream the way the planet's do, with one difference: a spawn snaps to
## the nearest street crossing. A turret appearing inside a tower would have to be
## seen through it, and a launcher that starts a fight from behind a wall has no
## line to telegraph down.

## The block grid. A cell is a block and the gap between cells is the street. The
## camera shows about 128 x 72 units of the plane, so a 26-unit block is a third
## of the screen and a 12-unit street a sixth: the tightest grid that still lets a
## 2-unit-wide ship turn around.
const BLOCK: float = 26.0
const STREET: float = 12.0
const PITCH: float = BLOCK + STREET
## The tower is inset by the sidewalk on each side, so the curb line the ground
## shader paints and the wall the ship hits are the same line.
const SIDEWALK: float = 2.5
const FOOTPRINT: float = BLOCK - 2.0 * SIDEWALK
const BLOCKS: int = 8
## The player starts at the crossing between these two blocks, and the whole grid
## is placed so that crossing is the world origin.
const START_CELL: int = 3
const STREET_CENTRE: float = START_CELL * PITCH + BLOCK + STREET * 0.5
const GRID_ORIGIN: Vector2 = Vector2(-STREET_CENTRE, -STREET_CENTRE)

const GROUND_Y: float = -1.5
## The ground is wider than the district on purpose: the district edge is a wall
## of buildings, and the plane continues underneath so a breach shows road instead
## of the void.
const GROUND_SIZE: float = 900.0

const TOWER_HEIGHT_MIN: float = 9.0
const TOWER_HEIGHT_MAX: float = 26.0
const PERIMETER_HEIGHT_MIN: float = 26.0
const PERIMETER_HEIGHT_MAX: float = 34.0
## One interior block in seven is left empty as a plaza. A district of solid cells
## reads as a maze; the open corners are where a fight has room.
const PLAZA_CHANCE: float = 0.14
const LAYOUT_SEED: int = 20261104

## Encounters. Same streaming as the planet, on a shorter leash: the district is
## about 300 units across, so the planet's 190-unit despawn ring would reach past
## its wall.
const MAX_ENEMIES: int = 3
const SPAWN_INTERVAL: float = 2.2
const FIRST_SPAWN_DISTANCE: float = 34.0
const FIRST_SPAWN_ANGLE: float = 0.42
const SPAWN_DISTANCE_MIN: float = 70.0
const SPAWN_DISTANCE_MAX: float = 110.0
const SPAWN_HEADING_SPREAD: float = 0.7
## A crossing can land much closer than the requested distance when the ship is
## already near one. Below this separation the spawn is retried on another bearing.
const MIN_SPAWN_SEPARATION: float = 40.0
const SPAWN_ATTEMPTS: int = 6
const DESPAWN_DISTANCE: float = 170.0
const SPAWN_SEED: int = 20261105

## The camera hangs 65 units up and 17 behind, so a tower within about ten units
## of the ship on the camera side hides it. The sight line is traced every physics
## frame and every tower on it is dithered away.
const MAX_OCCLUDERS: int = 4
const WORLD_MASK: int = 1 << Building.LAYER_WORLD

const SCENE_PATH: String = "res://levels/city/city.tscn"
const ENEMY_SCENE: PackedScene = preload("res://entities/enemy/turret.tscn")
const MISSILE_ENEMY_SCENE: PackedScene = preload("res://entities/enemy/missile_enemy.tscn")
const FIGHTER_ENEMY_SCENE: PackedScene = preload("res://entities/enemy/fighter_enemy.tscn")
const MISSILE_ENEMY_SHARE: float = 0.34
const FIGHTER_ENEMY_SHARE: float = 0.20

const GROUND_SHADER: Shader = preload("res://levels/city/city_ground.gdshader")

var _spawn_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _layout_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The run's score, owned here for the same reason the arena owns its own: a
## reload starts a fresh run at zero.
var _score: int = 0
var _occluders: Array[Building] = []

@onready var _player: Player = %Player
@onready var _enemies: Node3D = %Enemies
@onready var _buildings: Node3D = %Buildings


func _ready() -> void:
	GlobalEventBus.enemy_killed.connect(_on_enemy_killed)
	# The city is resumable for the same reason the planet is: the level remembers
	# which scenario the run started, and the menu reads it.
	GameProgress.instance().remember_scenario(SCENE_PATH)
	_build_environment()
	_build_ground()
	_build_city()

	# The origin is the crossing the grid was centred on, so the first frame is a
	# street with room to turn instead of the inside of a block.
	_player.global_position = Vector3.ZERO
	_rng.seed = SPAWN_SEED
	_spawn_timer = SPAWN_INTERVAL
	# One turret at the nearest crossing, for the same reason the planet forces a
	# turret on load: the opening contact is the one the player learns on.
	_spawn_enemy(ENEMY_SCENE, _street_spawn(FIRST_SPAWN_ANGLE, FIRST_SPAWN_DISTANCE))


func _physics_process(delta: float) -> void:
	_maintain_population(delta)
	_update_occlusion()


func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.010, 0.012, 0.020)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.30, 0.38, 0.56)
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# The lit windows are the district's own light. Without a little bloom they are
	# flat orange rectangles; with it the streets read as a place at night.
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.0

	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var moon: DirectionalLight3D = DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	moon.light_energy = 0.75
	moon.light_color = Color(0.60, 0.70, 1.0)
	moon.light_angular_distance = 1.2
	moon.shadow_blur = 2.0
	moon.shadow_enabled = true
	add_child(moon)


func _build_ground() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GROUND_SHADER
	# The shader paints from world coordinates, so it needs the same grid the
	# towers are placed on or the curb would drift off the wall.
	material.set_shader_parameter("grid_origin", GRID_ORIGIN)
	material.set_shader_parameter("block", BLOCK)
	material.set_shader_parameter("street", STREET)
	material.set_shader_parameter("pitch", PITCH)
	material.set_shader_parameter("sidewalk", SIDEWALK)

	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position.y = GROUND_Y
	add_child(ground)


## The district is a grid of blocks with a solid outer ring. The ring is filled to
## the full pitch instead of the footprint, so neighbouring perimeter blocks touch
## and the district has no street-sized gap to leak through; the player can still
## make one by demolishing a block.
func _build_city() -> void:
	_layout_rng.seed = LAYOUT_SEED
	for row in BLOCKS:
		for column in BLOCKS:
			var perimeter: bool = (
				row == 0 or row == BLOCKS - 1 or column == 0 or column == BLOCKS - 1
			)
			if not perimeter and _layout_rng.randf() < PLAZA_CHANCE:
				continue

			var size: float = PITCH if perimeter else FOOTPRINT
			var height: float = (
				_layout_rng.randf_range(PERIMETER_HEIGHT_MIN, PERIMETER_HEIGHT_MAX)
				if perimeter
				else _layout_rng.randf_range(TOWER_HEIGHT_MIN, TOWER_HEIGHT_MAX)
			)

			var building: Building = Building.new()
			building.name = "Block_%d_%d" % [row, column]
			building.build(Vector2(size, size), height)
			building.position = Vector3(
				GRID_ORIGIN.x + column * PITCH + BLOCK * 0.5,
				GROUND_Y,
				GRID_ORIGIN.y + row * PITCH + BLOCK * 0.5
			)
			building.destroyed.connect(_on_building_destroyed)
			_buildings.add_child(building)


## True when the point is inside a street band on either axis, which is the whole
## test the level needs: a point is drivable when one of its axes is a road.
func is_street(point: Vector3) -> bool:
	return (
		_in_street_band(point.x, GRID_ORIGIN.x)
		or _in_street_band(point.z, GRID_ORIGIN.y)
	)


func _in_street_band(value: float, origin: float) -> bool:
	return fposmod(value - origin, PITCH) >= BLOCK


## Every tower on the segment, nearest first, up to MAX_OCCLUDERS. Public because
## the sight line is the one piece of the occlusion rule that can be checked
## without a camera and a rendered frame.
func occluders_between(from: Vector3, to: Vector3) -> Array[Building]:
	var found: Array[Building] = []
	var start: Vector3 = from
	for _index in MAX_OCCLUDERS:
		var hit: Dictionary = _ray(start, to)
		if hit.is_empty():
			break
		var building: Building = hit.get("collider") as Building
		if building == null:
			break
		found.append(building)
		# Step just past the face, so a second tower on the same line is found too.
		start = (hit["position"] as Vector3) + (to - start).normalized() * 0.05
	return found


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, WORLD_MASK
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _update_occlusion() -> void:
	var camera: Camera3D = _player.camera
	if camera == null:
		return

	var found: Array[Building] = occluders_between(
		camera.global_position, _player.global_position
	)
	for building in _occluders:
		if not found.has(building):
			building.set_ghosted(false)
	for building in found:
		building.set_ghosted(true)
	_occluders = found


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
	_spawn_enemy(_pick_enemy_scene(), _spawn_point())


## The spawn is snapped to a crossing, so it can land much nearer than asked. The
## bearings are retried before the nearest one is accepted, which keeps a contact
## from appearing on top of the ship.
func _spawn_point() -> Vector3:
	var angle: float = _spawn_angle()
	var point: Vector3 = Vector3.ZERO
	for _attempt in SPAWN_ATTEMPTS:
		point = _street_spawn(angle, _rng.randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX))
		if _planar_distance(point) >= MIN_SPAWN_SEPARATION:
			return point
		angle += TAU / float(SPAWN_ATTEMPTS)
	return point


func _street_spawn(angle: float, distance: float) -> Vector3:
	var wanted: Vector3 = (
		_player.global_position
		+ Vector3(cos(angle), 0.0, sin(angle)) * distance
	)
	return Vector3(
		_nearest_street_centre(wanted.x, GRID_ORIGIN.x),
		0.0,
		_nearest_street_centre(wanted.z, GRID_ORIGIN.y)
	)


## The centre of the street band nearest a coordinate, clamped to the streets that
## exist between blocks: the outer ring is solid, so there is no street outside it.
func _nearest_street_centre(value: float, origin: float) -> float:
	var index: int = int(roundf((value - origin - BLOCK - STREET * 0.5) / PITCH))
	index = clampi(index, 0, BLOCKS - 2)
	return origin + index * PITCH + BLOCK + STREET * 0.5


func _planar_distance(point: Vector3) -> float:
	return Vector2(
		point.x - _player.global_position.x,
		point.z - _player.global_position.z
	).length()


## Bias new contacts to the streets the ship is heading into, the same way the
## planet does: a plain ring would put half of them behind the ship.
func _spawn_angle() -> float:
	var heading: Vector2 = Vector2(_player.velocity.x, _player.velocity.z)
	var base: float = _rng.randf() * TAU
	if heading.length() > 2.0:
		base = heading.angle()
	return base + _rng.randf_range(-SPAWN_HEADING_SPREAD, SPAWN_HEADING_SPREAD)


func _spawn_enemy(scene: PackedScene, point: Vector3) -> void:
	var enemy: Enemy = scene.instantiate()
	_enemies.add_child(enemy)
	enemy.setup_spawn(point)


## One roll, three buckets, the same shares the planet uses so the two scenarios
## present the same threat mix.
func _pick_enemy_scene() -> PackedScene:
	var roll: float = _rng.randf()
	if roll < MISSILE_ENEMY_SHARE:
		return MISSILE_ENEMY_SCENE
	if roll < MISSILE_ENEMY_SHARE + FIGHTER_ENEMY_SHARE:
		return FIGHTER_ENEMY_SCENE
	return ENEMY_SCENE


func _on_enemy_killed(value: int) -> void:
	_add_score(value)


func _on_building_destroyed(value: int) -> void:
	_add_score(value)


func _add_score(value: int) -> void:
	_score += value
	GlobalEventBus.score_changed.emit(_score)


## Read-only view of the run's score, so the smoke test can assert a demolition
## pays without parsing the HUD label.
func score() -> int:
	return _score


## The towers, in build order. Read-only: the city owns placement.
func buildings() -> Array[Building]:
	var found: Array[Building] = []
	for node in _buildings.get_children():
		var building: Building = node as Building
		if building != null:
			found.append(building)
	return found
