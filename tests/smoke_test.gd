extends Node
## Headless smoke test for the 3D combat prototype.
## Run: ./run.sh --headless tests/smoke_test.tscn
## Exits with code 1 if any assertion fails.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"

var _failures: Array[String] = []
var _arena: Arena = null
var _player: Player = null
var _died_count: int = 0


func _ready() -> void:
	GlobalEventBus.player_died.connect(func() -> void: _died_count += 1)

	_arena = load(ARENA_SCENE).instantiate()
	add_child(_arena)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_player = _arena.get_node("%Player")
	_check(_player != null, "arena exposes a Player")
	_check(_player is CharacterBody3D, "player is a CharacterBody3D")

	_test_player_is_centered()
	await _test_movement()
	await _test_firing()
	await _test_enemy_patterns()
	await _test_enemies_roam_the_planet()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_travel_is_unbounded()
	await _test_planet_rolls_with_the_player()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_damage_and_iframes()
	await _test_death()

	_report()


func _test_player_is_centered() -> void:
	var camera: Camera3D = _player.camera
	_check(camera != null, "player owns a Camera3D")
	if camera == null:
		return

	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = camera.unproject_position(_player.global_position)
	var offset: float = projected.distance_to(centre)
	_check(offset < 1.0, "player projects to the screen centre (off by %.2f px)" % offset)


func _test_movement() -> void:
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_right")
	for _i in 30:
		await get_tree().physics_frame
	Input.action_release(&"move_right")

	var travelled: float = _player.global_position.x - start.x
	_check(travelled > 5.0, "player moves right on the play plane (%.1f units)" % travelled)
	_check(
		absf(_player.global_position.z - start.z) < 0.1,
		"movement keeps the player on its plane"
	)


func _test_firing() -> void:
	var before: int = _count_projectiles(Projectile.Team.PLAYER)

	Input.action_press(&"aim_left")
	Input.action_press(&"fire")
	for _i in 20:
		await get_tree().physics_frame
	Input.action_release(&"fire")
	Input.action_release(&"aim_left")

	var after: int = _count_projectiles(Projectile.Team.PLAYER)
	_check(after > before, "firing spawns player projectiles (%d -> %d)" % [before, after])


func _test_enemy_patterns() -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	_check(enemies.size() >= 1, "the planet is populated (found %d)" % enemies.size())

	var saw_enemy_bullets: bool = false
	for _i in 300:
		await get_tree().physics_frame
		if _count_projectiles(Projectile.Team.ENEMY) > 0:
			saw_enemy_bullets = true
			break

	_check(saw_enemy_bullets, "enemy emits a bullet pattern within 5 s")

	if not enemies.is_empty():
		var enemy: Enemy = enemies[0] as Enemy
		var distance: float = _flat_distance(enemy.global_position, _player.global_position)
		_check(
			absf(distance - Enemy.ORBIT_RADIUS) < 8.0,
			"the engaged turret holds the ring radius (%.1f units)" % distance
		)


## A large planet is only worth exploring if enemies belong to it. A turret pinned
## to the ship would follow the player forever and the trip would change nothing,
## so this drives the ship away and asserts both halves of the behaviour: the
## turret is left behind, and it keeps moving on its own.
func _test_enemies_roam_the_planet() -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	if enemies.is_empty():
		_check(false, "an enemy is available for the roaming check")
		return

	var enemy: Enemy = enemies[0] as Enemy
	var start: Vector3 = enemy.global_position

	_player.global_position = enemy.global_position + Vector3(0.0, 0.0, 120.0)
	_player.velocity = Vector3.ZERO

	for _i in 90:
		await get_tree().physics_frame

	if not is_instance_valid(enemy):
		_check(false, "the turret survives the run")
		return

	var separation: float = _flat_distance(enemy.global_position, _player.global_position)
	var roamed: float = _flat_distance(enemy.global_position, start)

	_check(
		separation > 90.0,
		"the turret does not follow the ship (%.1f units behind)" % separation
	)
	_check(
		roamed > 1.0,
		"the turret roams the planet on its own (%.1f units in 1.5 s)" % roamed
	)


## The planet has no boundary any more: the surface under the ship is replaced as
## the planet rolls, so a straight line must keep going forever.
func _test_travel_is_unbounded() -> void:
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame

	var planet: Node3D = _arena.get_node("Planet")
	var worst_offset: float = 0.0

	Input.action_press(&"move_right")
	for _i in 300:
		await get_tree().physics_frame
		worst_offset = maxf(worst_offset, _planet_offset(planet))
	Input.action_release(&"move_right")

	_check(
		_player.global_position.x > 60.0,
		"the player keeps travelling with no boundary (x %.1f)" % _player.global_position.x
	)
	_check(
		absf(_player.global_position.z) < 0.1,
		"travelling keeps the player on the play plane"
	)
	# One frame of slack: the assertion may resume before this frame's physics
	# step, so at full speed the planet can legitimately be one step behind.
	_check(
		worst_offset < 1.0,
		"the planet stays under the player while travelling (worst offset %.2f)" % worst_offset
	)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var settled_offset: float = _planet_offset(planet)
	_check(
		settled_offset < 0.01,
		"the planet settles exactly under the player (offset %.4f)" % settled_offset
	)

	# The camera is a child of the player, so a drifting rig would show up here.
	var camera: Camera3D = _player.camera
	if camera != null:
		var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
		var projected: Vector2 = camera.unproject_position(_player.global_position)
		var offset: float = projected.distance_to(centre)
		_check(offset < 1.0, "player stays centred while travelling (off by %.2f px)" % offset)


## Rolling without slipping: the planet must turn exactly distance / radius, about
## the axis perpendicular to the movement, in the direction that makes the ground
## flow backwards under the ship.
func _test_planet_rolls_with_the_player() -> void:
	var planet: Node3D = _arena.get_node("Planet")

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	var start_basis: Basis = planet.global_transform.basis
	var start_position: Vector3 = _player.global_position

	Input.action_press(&"move_right")
	for _i in 90:
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	await get_tree().physics_frame

	var travelled: Vector3 = _player.global_position - start_position
	var distance: float = Vector2(travelled.x, travelled.z).length()
	_check(distance > 20.0, "the roll test covers ground (%.1f units)" % distance)

	# Movement is applied as a world-space pre-rotation, so current * start^-1 is
	# the accumulated spin itself.
	var spin: Basis = planet.global_transform.basis * start_basis.inverse()
	var rotation: Quaternion = spin.get_rotation_quaternion()
	var angle: float = rotation.get_angle()
	var axis: Vector3 = rotation.get_axis()
	var expected: float = distance / Arena.PLANET_RADIUS

	_check(
		absf(angle - expected) < 0.03,
		"the planet turns distance / radius (%.3f rad, expected %.3f)" % [angle, expected]
	)
	_check(
		axis.z > 0.95,
		"moving right rolls the planet about +Z so the ground flows left (%s)" % axis
	)

	# No input, no roll: the surface must not creep while the ship hovers.
	_player.velocity = Vector3.ZERO
	for _i in 3:
		await get_tree().physics_frame
	var idle_basis: Basis = planet.global_transform.basis
	for _i in 30:
		await get_tree().physics_frame
	var idle_spin: float = (planet.global_transform.basis * idle_basis.inverse())\
		.get_rotation_quaternion().get_angle()
	_check(idle_spin < 0.01, "the planet holds still while the ship hovers (%.4f rad)" % idle_spin)


func _planet_offset(planet: Node3D) -> float:
	var offset: Vector3 = planet.global_position - _player.global_position
	return Vector2(offset.x, offset.z).length()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _test_damage_and_iframes() -> void:
	# The encounter phase can legitimately land a hit, and this check is about
	# invulnerability frames, not about arriving at full health.
	_player.set("_hp", Player.MAX_HP)

	var event_bus_health: Array[int] = []
	GlobalEventBus.player_health_changed.connect(
		func(current: int, _maximum: int) -> void: event_bus_health.append(current)
	)

	_player.take_damage(1)
	await get_tree().physics_frame
	_player.take_damage(1)
	await get_tree().physics_frame

	var health: int = _player.get("_hp")
	_check(health == Player.MAX_HP - 1, "invulnerability frames block a second hit (hp %d)" % health)
	_check(
		not event_bus_health.is_empty(),
		"health changes reach the event bus for the HUD"
	)


func _test_death() -> void:
	while int(_player.get("_hp")) > 0:
		_player.set("_invulnerable", 0.0)
		_player.take_damage(1)
		await get_tree().physics_frame

	_check(int(_player.get("_hp")) == 0, "health drains to zero")
	_check(_died_count > 0, "player_died reaches the event bus")
	_check(not bool(_player.get("_alive")), "player enters a dead state")


func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group(&"enemy"):
		enemy.queue_free()


func _clear_projectiles() -> void:
	for child in get_children():
		if child is Projectile:
			child.queue_free()


func _count_projectiles(team: int) -> int:
	var total: int = 0
	for child in get_children():
		if child is Projectile and int(child.get("_team")) == team:
			total += 1
	return total


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
		return
	_failures.append(description)
	printerr("  FAIL  ", description)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		get_tree().quit(0)
		return

	printerr("SMOKE TEST FAILED (%d)" % _failures.size())
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)
