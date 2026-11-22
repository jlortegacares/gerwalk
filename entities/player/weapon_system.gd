class_name WeaponSystem
extends Node3D
## The player's arsenal, as a facade.
##
## The player node owns flight, aim and HP; this node owns what comes out of the
## nose, so `player.gd` keeps reading as "how the ship flies" instead of "how the
## ship flies plus three weapons".
##
## It keeps the things that belong to the ship as a whole: the loaded scene, the
## pilot's stats, the bomb rack, the decoy clock, and the one spawn path every shot
## goes through. The three primaries live in `PrimaryFire`; the missile rack lives
## in `MissileRadar`. Both are handed this node's spawn path and cone query, so the
## muzzle and the team cannot drift between weapons.

var _bullet_scene: PackedScene
## The run's pilot bonuses. The arsenal keeps its identity and the stats only scale
## the cadence and the handling, so a levelled pilot fires the same three weapons.
var _stats: PilotStats = PilotStats.new()

var _primary: PrimaryFire = null
var _radar: MissileRadar = null

## Fighter mode is a profile, not a different arsenal: the same three archetypes
## keep their identity and only lose the freedom to point anywhere but forward.
var _fighter: bool = false
## The wing hardpoints in world space, left first, refreshed by the player every
## frame because the sweep moves them. Empty means "fall back to the nose".
var _hardpoints: Array[Vector3] = []

var _bombs: int = Arsenal.BOMB_START_CHARGES
var _kills: int = 0
## Seconds until the next flare. The cooldown is the whole cost of the decoy.
var _decoy_cooldown: float = 0.0


func setup(bullet_scene: PackedScene, stats: PilotStats = PilotStats.new()) -> void:
	_bullet_scene = bullet_scene
	_stats = stats


## The player owns the run's stats and hands them over; the arsenal never reads the
## record itself. A run-start refresh replaces the object here.
func set_stats(stats: PilotStats) -> void:
	_stats = stats
	if _primary != null:
		_primary.stats = stats


func _ready() -> void:
	_primary = PrimaryFire.new()
	_primary.name = "Primaries"
	_primary.stats = _stats
	_primary.spawn = _spawn
	_primary.enemies_in_cone = _enemies_in_cone
	add_child(_primary)

	_radar = MissileRadar.new()
	_radar.spawn = _spawn
	_radar.enemies_in_cone = _enemies_in_cone

	GlobalEventBus.enemy_killed.connect(_on_enemy_killed)
	# Deferred so a HUD that connects in its own `_ready` still sees the start
	# state: the player must never sit with an empty weapon label.
	GlobalEventBus.player_weapon_changed.emit.call_deferred(Arsenal.NAMES[_primary.kind()])
	GlobalEventBus.player_bombs_changed.emit.call_deferred(_bombs, Arsenal.BOMB_MAX_CHARGES)
	GlobalEventBus.player_decoy_changed.emit.call_deferred(true)


func kind() -> Arsenal.Kind:
	return _primary.kind()


func bomb_charges() -> int:
	return _bombs


## The bomb rack's charges. Test API: the resource is earned by kills, which is a
## fight the suite does not need to stage.
func set_bomb_charges(count: int) -> void:
	_bombs = clampi(count, 0, Arsenal.BOMB_MAX_CHARGES)


## Clears the flare clock. Test API, same reason as the bomb charges.
func reset_decoy() -> void:
	_decoy_cooldown = 0.0


## Switching is instant and always legal: the weapons are a player choice, not a
## pickup economy.
func select(kind: Arsenal.Kind) -> void:
	if not _primary.select(kind):
		return
	GlobalEventBus.player_weapon_changed.emit(Arsenal.NAMES[_primary.kind()])


func cycle(step: int) -> void:
	var kinds: Array = Arsenal.Kind.values()
	var index: int = (kinds.find(_primary.kind()) + step + kinds.size()) % kinds.size()
	select(kinds[index])


func tick(
	delta: float,
	origin: Vector3,
	muzzle: Vector3,
	direction: Vector3,
	wants_fire: bool,
	fighter: bool = false,
	wants_missile: bool = false,
	hardpoints: Array[Vector3] = []
) -> void:
	_fighter = fighter
	_hardpoints = hardpoints
	_primary.fighter = fighter
	_radar.set_hardpoints(hardpoints)

	# The decoy reloads on its own clock whether or not anything else is firing:
	# it is a countermeasure, not a weapon the player has to be holding.
	if _decoy_cooldown > 0.0:
		_decoy_cooldown = maxf(_decoy_cooldown - delta, 0.0)
		if _decoy_cooldown <= 0.0:
			GlobalEventBus.player_decoy_changed.emit(true)

	_primary.tick(delta, muzzle, direction, wants_fire)
	_radar.tick(delta, origin, direction, wants_missile)


## How many missiles the hold has loaded.
func salvo_count() -> int:
	return _radar.salvo_count()


func max_salvo() -> int:
	return _radar.max_salvo()


## The three primaries, so a test can read their cadence without reaching into the
## node tree.
func primary() -> PrimaryFire:
	return _primary


## The missile rack, so a test can park its cooldown or read its marks instead of
## writing a private field by name.
func radar() -> MissileRadar:
	return _radar


## The bomb is the only weapon with a resource. It damages and cancels in the same
## frame, so what the player sees (the ring) and what happened (the clear) are one
## event and the ring can be pure presentation.
func fire_bomb(origin: Vector3) -> bool:
	if _bombs <= 0:
		return false

	_bombs -= 1
	GlobalEventBus.player_bombs_changed.emit(_bombs, Arsenal.BOMB_MAX_CHARGES)

	_clear_enemy_fire(origin)
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy: Enemy = node as Enemy
		if enemy == null:
			continue
		if _flat_distance(enemy.global_position, origin) <= Arsenal.BOMB_RADIUS:
			enemy.take_damage(Arsenal.BOMB_DAMAGE)

	_spawn_wave(origin)
	GlobalEventBus.camera_shake_requested.emit(1.4)
	Sfx.play_at(&"bomb", origin)
	return true


## Drops a flare where the ship is. It stays there while the ship flies on, which
## is the whole manoeuvre: the countermeasure only pays if the ship leaves the spot
## the missile was already heading for.
func drop_decoy(origin: Vector3) -> bool:
	if _decoy_cooldown > 0.0:
		return false

	var scene: Node = get_tree().current_scene
	if scene == null:
		return false

	_decoy_cooldown = Arsenal.DECOY_COOLDOWN
	var decoy: Decoy = Decoy.new()
	scene.add_child(decoy)
	decoy.global_position = origin
	GlobalEventBus.player_decoy_changed.emit(false)
	Sfx.play_at(&"decoy", origin)
	return true


## Radius-bound on purpose: "screen clear" is the intent, but a bullet far off the
## camera is not a threat the player is asking to erase.
func _clear_enemy_fire(origin: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for child in scene.get_children():
		var bullet: Projectile = child as Projectile
		if bullet == null:
			continue
		if int(bullet.get("_team")) != Projectile.Team.ENEMY:
			continue
		if _flat_distance(bullet.global_position, origin) <= Arsenal.BOMB_RADIUS:
			bullet.queue_free()


func _spawn_wave(origin: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var wave: BombWave = BombWave.new()
	scene.add_child(wave)
	wave.global_position = origin


## Charges come back on kills rather than on a timer: the resource rewards staying
## in the fight, and a full rack stops banking progress it cannot spend.
func _on_enemy_killed(_value: int) -> void:
	if _bombs >= Arsenal.BOMB_MAX_CHARGES:
		_kills = 0
		return

	_kills += 1
	if _kills < Arsenal.BOMB_KILLS_PER_CHARGE:
		return

	_kills = 0
	_bombs += 1
	GlobalEventBus.player_bombs_changed.emit(_bombs, Arsenal.BOMB_MAX_CHARGES)


## Every enemy inside the cone, nearest first. The plasma lock wants the head of
## the list; the missile radar wants the whole list, because a salvo is spread over
## it.
func _enemies_in_cone(
	origin: Vector3, direction: Vector3, max_range: float, cone_degrees: float
) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy: Enemy = node as Enemy
		if enemy == null:
			continue
		var to_enemy: Vector3 = enemy.global_position - origin
		to_enemy.y = 0.0
		var distance: float = to_enemy.length()
		if distance < 0.01 or distance > max_range:
			continue
		if cone_degrees < 180.0:
			var angle: float = rad_to_deg(direction.angle_to(to_enemy.normalized()))
			if angle > cone_degrees:
				continue
		found.append(enemy)

	found.sort_custom(
		func(a: Enemy, b: Enemy) -> bool:
			return (
				a.global_position.distance_squared_to(origin)
				< b.global_position.distance_squared_to(origin)
			)
	)
	return found


## One spawn path for every player shot, so the muzzle, the scene and the team can
## never drift between weapons. Returns the shot so a caller that needs to configure
## it further (the missile's guidance delay) does not have to search the scene.
func _spawn(
	position: Vector3,
	direction: Vector3,
	speed: float,
	damage: int,
	size: Vector3,
	color: Color,
	target: Node3D = null,
	turn_rate: float = 0.0,
	lifetime: float = Projectile.LIFETIME,
	style: Projectile.Style = Projectile.Style.DART
) -> Projectile:
	if _bullet_scene == null:
		return null

	var bullet: Projectile = _bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = position
	bullet.setup(
		direction, speed, Projectile.Team.PLAYER, damage, size, target, turn_rate, color,
		lifetime, style
	)
	return bullet


func _flat_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()
