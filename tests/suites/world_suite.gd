class_name WorldSuite
extends SmokeSuite
## The scenarios: the planet roster, the cloud deck and the city
## district.

## The planet's sky belongs to one archetype: the turret and the launcher are city
## fights, so the arena streams interceptors and nothing else. The mothership is
## the one other hull that arrives, and it arrives on its own trigger. This pins
## the roster at both ends -- the opening contact and the stream -- because a
## rebalance that quietly re-adds a turret would only show up as a difficulty
## change nobody asked for.
func _test_planet_roster() -> void:
	var enemies: Node3D = _arena.get_node("Enemies") as Node3D
	var opening: Node = enemies.get_child(0) if enemies.get_child_count() > 0 else null
	_check(opening is FighterEnemy, "the planet opens with an interceptor")

	_clear_enemies()
	await get_tree().physics_frame
	for _spawn: int in range(Arena.MAX_ENEMIES):
		_arena.set("_spawn_timer", 0.0)
		_arena.call("_maintain_population", 1.0)

	var impostors: Array[String] = []
	for node in enemies.get_children():
		if not (node is FighterEnemy):
			impostors.append(String(node.name))
	_check(
		enemies.get_child_count() > 0 and impostors.is_empty(),
		"the planet streams nothing but interceptors (%d contact(s))"
		% enemies.get_child_count()
	)

	_clear_enemies()
	await get_tree().physics_frame

	# The stream is parked for the rest of the suite. An interceptor chases and
	# fires a guided pair, so three of them shoot a stationary run down long before
	# the last test -- and this suite is stationary by design. What the streamer
	# does was just proven above by driving it directly, which is also the
	# deterministic way to check it: no test waits on a wall clock for a contact to
	# arrive. `_test_radar` parks it the same way for its own bookkeeping.
	_arena.set("_spawn_timer", 1.0e9)


## The cloud deck is cover, not scenery. One density field drives both the puffs the
## ship flies through and the cover rule, so a bank that looks thick has to be a bank
## that breaks a lock. The test finds the points at runtime instead of hardcoding
## coordinates: retuning the field must not silently point the check at open sky.
func _test_clouds() -> void:
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	var field: CloudField = get_tree().get_first_node_in_group(&"cloud_field") as CloudField
	_check(field != null, "the planet carries a cloud field")
	if field == null:
		return

	var probe: Vector3 = Vector3(240.0, 0.0, 180.0)
	_check(
		is_equal_approx(field.density_at(probe), field.density_at(probe)),
		"cloud density is deterministic"
	)
	_check(
		not field.is_dense(Vector3.ZERO),
		"the opening patch is clear of dense cloud"
	)

	var dense: Vector3 = _find_cloud_point(field, true)
	var thin: Vector3 = _find_cloud_point(field, false)
	_check(dense != Vector3.INF, "the deck has dense banks")
	_check(thin != Vector3.INF, "the deck has thin gaps")
	if dense == Vector3.INF or thin == Vector3.INF:
		return
	_check(
		field.density_at(thin) >= CloudField.VISUAL_MIN_DENSITY,
		"the thin gap is visible weather, not open sky (%.3f)"
		% field.density_at(thin)
	)

	# The visual stream has to populate the deck where the gameplay says it is
	# dense, or the cover would be invisible.
	_player.global_position = dense
	_player.velocity = Vector3.ZERO
	for _i in 3:
		await get_tree().physics_frame
	_check(
		field.visible_puff_count() > 0,
		"a dense bank draws puffs (%d)" % field.visible_puff_count()
	)

	# A guided shot loses the ship inside the core. The missile is parked far enough
	# away that the check is the lock and not a race against its warhead.
	var hidden: Projectile = _spawn_enemy_missile(
		dense + Vector3(0.0, 0.0, 40.0), _player
	)
	_check(hidden.get("_target") == _player, "a missile starts locked on the ship")
	for _i in 4:
		await get_tree().physics_frame
	_check(hidden.get("_target") == null, "a dense bank breaks the missile's lock")
	var heading: Vector3 = hidden.get("_velocity")
	for _i in 8:
		await get_tree().physics_frame
	_check(
		(hidden.get("_velocity") as Vector3).is_equal_approx(heading),
		"a missile that lost the lock flies straight"
	)

	# The fringe is weather, not cover: only the core hides the ship.
	_player.global_position = thin
	for _i in 3:
		await get_tree().physics_frame
	var chasing: Projectile = _spawn_enemy_missile(
		thin + Vector3(0.0, 0.0, 40.0), _player
	)
	for _i in 4:
		await get_tree().physics_frame
	_check(
		chasing.get("_target") == _player,
		"a thin cloud leaves the missile's lock alone"
	)

	_clear_projectiles()
	_clear_enemies()
	_player.global_position = Vector3.ZERO
	await get_tree().physics_frame


## The second scenario: a district of streets and towers. It is a separate scene,
## so the arena is retired first. Two live players would both answer `%Player`, and
## two streamers would fill one world with contacts from two levels.
func _test_city_scene() -> void:
	# The suite has been killing enemies for minutes, and a new scene captures the
	# pilot's level on its own `_ready`. Reset first so the city's player is built
	# on the same level-1 baseline as the arena's.
	GameProgress.instance().reset()
	if _arena != null:
		_arena.queue_free()
		_arena = null
	_player = null
	await get_tree().physics_frame
	await get_tree().physics_frame

	var packed: PackedScene = load(City.SCENE_PATH)
	_check(packed != null, "the city scene loads")
	if packed == null:
		return

	var city: City = packed.instantiate() as City
	get_tree().current_scene.add_child(city)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Player = city.get_node("%Player") as Player
	var enemies: Node3D = city.get_node("%Enemies") as Node3D
	var buildings: Node3D = city.get_node("%Buildings") as Node3D
	var hud: CanvasLayer = city.get_node("%HUD") as CanvasLayer
	_check(player != null, "the city exposes a Player")
	_check(enemies != null, "the city exposes an Enemies container")
	_check(buildings != null, "the city exposes a Buildings container")
	_check(hud != null, "the city carries the HUD")

	var towers: Array[Building] = city.buildings()
	_check(towers.size() >= 40, "the district is built (%d towers)" % towers.size())
	if towers.is_empty():
		city.queue_free()
		return

	# The streets are the level because the geometry is real. Both halves matter: the
	# ship starts on a road, and a tower stands where a road is not.
	_check(
		city.is_street(player.global_position),
		"the ship starts on a street instead of inside a block"
	)
	_check(
		not city.is_street(towers[0].global_position),
		"a tower stands on a block, not on a street"
	)
	for child in enemies.get_children():
		var spawned: Enemy = child as Enemy
		if spawned == null:
			continue
		_check(
			city.is_street(spawned.global_position),
			"an encounter starts on a street, not inside a tower"
		)

	# A tower is a wall. The vertical ray is the cheapest proof that the box is a
	# real collider on the layer the ship and every projectile already use.
	var tower: Building = towers[0]
	var ray_from: Vector3 = tower.global_position + Vector3(0.0, 60.0, 0.0)
	var ray_to: Vector3 = tower.global_position
	_check(_world_hit(ray_from, ray_to) == tower, "a tower is solid from above")
	_check(
		Building.MAX_HP >= Turret.MAX_HP * 10,
		"a demolition costs at least ten turrets' worth of fire (%d HP)" % Building.MAX_HP
	)

	# The price is the design: one hit short of the last, the tower is still a wall.
	var score_before: int = city.score()
	tower.take_damage(Building.MAX_HP - 1)
	_check(tower.current_hp() == 1, "a tower survives all but its last hit")
	_check(not tower.is_destroyed(), "the last hit is the one that brings it down")
	_check(_world_hit(ray_from, ray_to) == tower, "a damaged tower still blocks the street")

	tower.take_damage(1)
	_check(tower.is_destroyed(), "the last hit demolishes the tower")
	_check(
		city.score() == score_before + Building.SCORE_VALUE,
		"a demolition pays its own score (+%d)" % Building.SCORE_VALUE
	)
	# The collision change is deferred out of the `body_entered` callback, so the
	# street only opens on the next physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(
		_world_hit(ray_from, ray_to) == null,
		"a demolished tower stops blocking, so the street opens"
	)

	# Player fire is what chips a tower. The shot is built the way the vulcan builds
	# one and aimed at a second tower's side face.
	var target: Building = towers[1]
	var shot_from: Vector3 = target.global_position + Vector3(
		0.0, 0.0, -(target.footprint().y * 0.5 + 5.0)
	)
	var bullet: Projectile = _spawn_player_bullet(shot_from, Vector3(0.0, 0.0, 1.0))
	for _i in 30:
		await get_tree().physics_frame
		if target.current_hp() < Building.MAX_HP:
			break
	_check(
		target.current_hp() == Building.MAX_HP - 1,
		"a player shot damages a tower (%d HP left)" % target.current_hp()
	)
	if is_instance_valid(bullet):
		bullet.queue_free()

	# Camera occlusion. The camera sits 65 units up, so the sight line only crosses a
	# tower when the ship flies the half of the street nearest the camera-side block;
	# the ship is placed there instead of being flown there, because the rule is
	# about geometry and not about speed.
	var occluder: Building = towers[2]
	var probe: Vector3 = Vector3(
		occluder.global_position.x,
		0.0,
		occluder.global_position.z - occluder.footprint().y * 0.5 - 4.0
	)
	_check(city.is_street(probe), "the occlusion probe is somewhere the ship can fly")
	player.global_position = probe
	for _i in 10:
		await get_tree().physics_frame
	var camera: Camera3D = player.camera
	var on_the_line: Array[Building] = city.occluders_between(
		camera.global_position, player.global_position
	)
	_check(
		on_the_line.has(occluder),
		"a tower between the camera and the ship is found"
	)
	_check(
		occluder.is_ghosted(),
		"the tower on the sight line is dithered out instead of hiding the ship"
	)

	city.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


