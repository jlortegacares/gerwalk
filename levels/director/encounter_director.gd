class_name EncounterDirector
extends RefCounted
## Keeps the stream of hostiles alive around the ship.
##
## Both scenarios stream contacts, and the rules of the stream are the same in
## both: a population cap, a spawn distance band, bearings biased into the
## hemisphere the ship is heading toward, and a despawn once a contact has been
## left behind. Only the roster and the placement differ, so those two are
## configuration instead of two hand-synchronised copies of the same loop.
##
## Not a node: it holds a timer and an RNG, and the level drives it from its own
## `_physics_process`. The level still owns the tree, the player and the run.

## The ship the stream is built around. Everything is measured from its position
## and its heading.
var player: Player = null
## Where new contacts are parented. The level's `%Enemies` container.
var container: Node3D = null

## What may be spawned and the share of the stream each archetype gets. A roster
## with no matching `shares` is a single archetype: the first entry, every time.
var roster: Array[PackedScene] = []
var shares: Array[float] = []

var spawn_interval: float = 2.0
var max_enemies: int = 3
var spawn_distance_min: float = 85.0
var spawn_distance_max: float = 110.0
var despawn_distance: float = 190.0
var heading_spread: float = 0.7
var spawn_seed: int = 0

## Retries that keep a snapped spawn from landing on top of the ship: the first
## bearing is tried, then the next ones around the circle. One attempt means the
## first bearing is taken.
var min_spawn_separation: float = 0.0
var spawn_attempts: int = 1

## Optional `(angle, distance) -> Vector3` that snaps a spawn to level geometry.
## The city uses it to drop contacts on streets instead of inside a block; the
## planet has no geometry to snap to and leaves it unset.
var placer: Callable = Callable()

## Optional `(Enemy) -> bool`. Returning true exempts a hull from the despawn. The
## mothership is the encounter, not part of the stream, so freeing it for being far
## away would delete the fight the player is meant to chase.
var keeper: Callable = Callable()

var _spawn_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _parked: bool = false


## Set the roster and its shares together, in roster order, so the two parallel
## arrays cannot drift apart.
func set_roster(scenes: Array[PackedScene], weights: Array[float] = []) -> void:
	roster = scenes
	shares = weights


## Seed the stream and prime the timer. Called by the level once, after the
## configuration is in place and before the first frame.
func begin() -> void:
	_rng.seed = spawn_seed
	_spawn_timer = spawn_interval


## One contact, chosen by the caller. The opening spawn of a scenario is a lesson,
## so its hull is picked by hand instead of rolled, and it consumes no randomness.
func spawn_opening(scene: PackedScene, distance: float, angle: float) -> Enemy:
	var enemy: Enemy = scene.instantiate() as Enemy
	container.add_child(enemy)
	enemy.setup_spawn(_place(angle, distance))
	return enemy


## One ordinary stream contact: a rolled hull at a rolled bearing inside the band.
func spawn_next() -> Enemy:
	# The hull is rolled before the bearing so the seeded sequence is the same one
	# the single-file directors produced.
	var scene: PackedScene = _pick_scene()
	var point: Vector3 = spawn_point()
	var enemy: Enemy = scene.instantiate() as Enemy
	container.add_child(enemy)
	enemy.setup_spawn(point)
	return enemy


## Reset the timer and produce a contact now. The deterministic path: a test that
## needs a contact should not wait on a wall clock for one to arrive.
func spawn_now() -> Enemy:
	_spawn_timer = spawn_interval
	return spawn_next()


## One frame of streaming: cull what was left behind, then fill the gap if the
## timer allows it.
func maintain(delta: float) -> void:
	_spawn_timer = maxf(_spawn_timer - delta, 0.0)
	var alive: int = _cull()
	if _parked or alive >= max_enemies or _spawn_timer > 0.0:
		return
	_spawn_timer = spawn_interval
	spawn_next()


## Stop producing contacts. The cull keeps running: a test that parks the stream
## still wants strays cleaned up.
func park() -> void:
	_parked = true


func resume() -> void:
	_parked = false


func is_parked() -> bool:
	return _parked


## Planar range from the ship. Height is irrelevant: the arena is flat at the
## scale the stream works at, and a contact overhead is as near as one alongside.
func distance_to(point: Vector3) -> float:
	if player == null:
		return 0.0
	return Vector2(
		point.x - player.global_position.x,
		point.z - player.global_position.z
	).length()


## Bias a new contact into the hemisphere the ship is heading into. A plain ring
## would drop half of them behind the player, where they are culled without ever
## being seen.
func angle() -> float:
	var base: float = _rng.randf() * TAU
	if player != null:
		var heading: Vector2 = Vector2(player.velocity.x, player.velocity.z)
		if heading.length() > 2.0:
			base = heading.angle()
	return base + _rng.randf_range(-heading_spread, heading_spread)


## Where the next stream contact goes: a bearing in the band, snapped by the
## placer, retried around the circle if it landed closer than the separation.
func spawn_point() -> Vector3:
	var bearing: float = angle()
	var attempts: int = maxi(spawn_attempts, 1)
	var point: Vector3 = Vector3.ZERO
	for _attempt in attempts:
		point = _place(
			bearing, _rng.randf_range(spawn_distance_min, spawn_distance_max)
		)
		if distance_to(point) >= min_spawn_separation:
			return point
		bearing += TAU / float(attempts)
	return point


## Free whatever has been left behind, and report how many hulls are still here.
func _cull() -> int:
	var alive: int = 0
	for node in container.get_children():
		var enemy: Enemy = node as Enemy
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if keeper.is_valid() and keeper.call(enemy):
			alive += 1
			continue
		if distance_to(enemy.global_position) > despawn_distance:
			enemy.queue_free()
			continue
		alive += 1
	return alive


## One roll, one bucket. The shares are read in roster order, so the same numbers
## produce the same mix no matter which archetype sits first.
func _pick_scene() -> PackedScene:
	if roster.is_empty():
		push_error("EncounterDirector: the roster is empty")
		return null
	if shares.size() != roster.size():
		return roster[0]

	var roll: float = _rng.randf()
	var total: float = 0.0
	for index in roster.size():
		total += shares[index]
		if roll < total:
			return roster[index]
	return roster[roster.size() - 1]


func _place(bearing: float, distance: float) -> Vector3:
	if placer.is_valid():
		return placer.call(bearing, distance)
	if player == null:
		return Vector3.ZERO
	return player.global_position + Vector3(cos(bearing), 0.0, sin(bearing)) * distance
