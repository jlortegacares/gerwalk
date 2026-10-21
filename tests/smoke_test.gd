extends Node
## Headless smoke test for the 3D combat prototype.
## Run: ./run.sh --headless tests/smoke_test.tscn
## Exits with code 1 if any assertion fails.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"

var _failures: Array[String] = []
var _player: Player = null
var _died_count: int = 0


func _ready() -> void:
	GlobalEventBus.player_died.connect(func() -> void: _died_count += 1)

	var arena: Node = load(ARENA_SCENE).instantiate()
	add_child(arena)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_player = arena.get_node("%Player")
	_check(_player != null, "arena exposes a Player")
	_check(_player is CharacterBody3D, "player is a CharacterBody3D")

	_test_player_is_centered()
	await _test_movement()
	await _test_firing()
	await _test_enemy_patterns()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_arena_holds_player()
	await _test_cross_the_surface()

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
	_check(enemies.size() == 1, "one enemy is spawned (found %d)" % enemies.size())

	if not enemies.is_empty():
		var enemy: Enemy = enemies[0] as Enemy
		var position: Vector3 = enemy.global_position
		var radius: float = Vector2(position.x, position.z).length()
		_check(
			radius > 0.0 and radius < Arena.ARENA_RADIUS,
			"enemy is spawned on the planet surface (r %.0f)" % radius
		)

	var saw_enemy_bullets: bool = false
	for _i in 300:
		await get_tree().physics_frame
		if _count_projectiles(Projectile.Team.ENEMY) > 0:
			saw_enemy_bullets = true
			break

	_check(saw_enemy_bullets, "enemy emits a bullet pattern within 5 s")


func _test_arena_holds_player() -> void:
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame

	var furthest: float = 0.0
	Input.action_press(&"move_right")
	for _i in 240:
		await get_tree().physics_frame
		furthest = maxf(furthest, _radius_of(_player.global_position))
	Input.action_release(&"move_right")

	_check(
		furthest <= Arena.ARENA_RADIUS,
		"the planet edge holds the player inside (max r %.1f)" % furthest
	)
	_check(
		furthest > Arena.ARENA_RADIUS - 3.0,
		"the player reaches the planet edge (max r %.1f)" % furthest
	)

	# The camera is a child of the player, so the edge is exactly where a naive
	# rig drifts. Re-check the centring away from the spawn point.
	var camera: Camera3D = _player.camera
	if camera != null:
		var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
		var projected: Vector2 = camera.unproject_position(_player.global_position)
		var offset: float = projected.distance_to(centre)
		_check(offset < 1.0, "player stays centred at the planet edge (off by %.2f px)" % offset)


func _test_cross_the_surface() -> void:
	_player.global_position = Vector3(-40.0, 0.0, 0.0)
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame

	Input.action_press(&"move_right")
	for _i in 220:
		await get_tree().physics_frame
	Input.action_release(&"move_right")

	_check(
		_player.global_position.x > 40.0,
		"the player crosses the planet surface (x %.1f)" % _player.global_position.x
	)
	_check(
		absf(_player.global_position.z) < 0.1,
		"crossing the surface keeps the player on the play plane"
	)


func _test_damage_and_iframes() -> void:
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


func _radius_of(position: Vector3) -> float:
	return Vector2(position.x, position.z).length()


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
