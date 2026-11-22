class_name WeaponsSuite
extends SmokeSuite
## The arsenal: primaries, the missile radar and its lock contract, the
## salvo, the bomb, the decoy and interception.

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


## The arsenal is three archetypes with different shapes of damage, so each one is
## asserted by its signature behaviour instead of by its numbers: tuning a weapon
## must not rewrite the test.
func _test_arsenal() -> void:
	var weapons: WeaponSystem = _player.get_node("Weapons") as WeaponSystem
	_check(weapons != null, "the player carries a weapon system")
	if weapons == null:
		return

	await _test_weapon_switch(weapons)
	await _test_vulcan(weapons)
	await _test_laser(weapons)
	await _test_plasma(weapons)
	await _test_missiles(weapons)
	await _test_bomb(weapons)
	await _test_bomb_refill(weapons)
	await _test_firing_costs_no_speed(weapons)
	await _test_decoy(weapons)
	await _test_missile_intercept()

	Input.action_release(&"aim_left")
	Input.action_release(&"fire")
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame


func _test_weapon_switch(weapons: WeaponSystem) -> void:
	var announced: Array[String] = []
	var handler: Callable = func(name: String) -> void: announced.append(name)
	GlobalEventBus.player_weapon_changed.connect(handler)

	Input.action_press(&"weapon_3")
	await get_tree().physics_frame
	Input.action_release(&"weapon_3")
	await get_tree().physics_frame

	_check(weapons.kind() == Arsenal.Kind.PLASMA, "key 3 selects the plasma")
	_check(announced.has("PLASMA"), "weapon changes reach the event bus")

	Input.action_press(&"weapon_next")
	await get_tree().physics_frame
	Input.action_release(&"weapon_next")
	await get_tree().physics_frame

	_check(
		weapons.kind() == Arsenal.Kind.VULCAN,
		"the D-pad cycles past the last weapon back to the first"
	)
	GlobalEventBus.player_weapon_changed.disconnect(handler)


func _test_vulcan(weapons: WeaponSystem) -> void:
	weapons.select(Arsenal.Kind.VULCAN)
	_clear_projectiles()
	await get_tree().physics_frame

	Input.action_press(&"aim_left")
	await get_tree().physics_frame
	Input.action_press(&"fire")
	await get_tree().physics_frame
	Input.action_release(&"fire")
	await get_tree().physics_frame

	var shots: Array[Projectile] = _player_projectiles()
	_check(
		shots.size() >= Arsenal.VULCAN_PELLETS,
		"vulcan opens with a %d-pellet fan (fired %d)" % [Arsenal.VULCAN_PELLETS, shots.size()]
	)

	var widest: float = 0.0
	for i in shots.size():
		for j in range(i + 1, shots.size()):
			var first: Vector3 = shots[i].get("_velocity")
			var second: Vector3 = shots[j].get("_velocity")
			widest = maxf(widest, rad_to_deg(first.normalized().angle_to(second.normalized())))
	_check(widest > 20.0, "the fan spreads across the aim (%.0f degrees)" % widest)
	_clear_projectiles()


## The beam is the only weapon with no travel time, so the test asks for the two
## things that only a hit-scan can do: damage without a projectile, and damage that
## lands while the target is still far away.
func _test_laser(weapons: WeaponSystem) -> void:
	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 12.0)
	_check(enemy != null, "spawned a target for the laser")
	if enemy == null:
		return

	weapons.select(Arsenal.Kind.LASER)
	# The automatic missile battery fires on its own schedule and would look like
	# a laser projectile, so park it for the measurement.
	var parked_cooldown: float = weapons.radar().cooldown()
	weapons.radar().set_cooldown(99.0)
	_clear_projectiles()
	var before: int = enemy.current_hp()

	Input.action_press(&"fire")
	for _i in 12:
		await get_tree().physics_frame
	Input.action_release(&"fire")
	await get_tree().physics_frame

	_check(
		enemy.current_hp() < before,
		"the laser burns the target it points at (%d -> %d hp)" % [before, enemy.current_hp()]
	)
	_check(_player_projectiles().is_empty(), "the laser emits no projectile (hit-scan)")
	weapons.radar().set_cooldown(parked_cooldown)

	_clear_enemies()
	await get_tree().physics_frame


## Plasma is the only weapon that ignores where the nose is pointing after the
## shot leaves, so the assertion is that the bolt acquired the off-axis turret and
## turned away from the aim to reach it.
func _test_plasma(weapons: WeaponSystem) -> void:
	var off_axis: Vector3 = _aim().rotated(Vector3.UP, deg_to_rad(24.0))
	var enemy: Enemy = _spawn_enemy(_player.global_position + off_axis * 18.0)
	_check(enemy != null, "spawned an off-axis target for the plasma")
	if enemy == null:
		return

	weapons.select(Arsenal.Kind.PLASMA)
	_clear_projectiles()
	var aim: Vector3 = _aim()

	Input.action_press(&"fire")
	await get_tree().physics_frame
	Input.action_release(&"fire")

	var bolts: Array[Projectile] = _player_projectiles()
	_check(bolts.size() >= 1, "plasma fires a bolt (fired %d)" % bolts.size())
	if bolts.is_empty():
		_clear_enemies()
		return

	var bolt: Projectile = bolts[0]
	_check(bolt.get("_target") == enemy, "the bolt locks the turret inside the cone")

	var curved: bool = false
	for _i in 6:
		await get_tree().physics_frame
	if not is_instance_valid(bolt):
		# It arrived: a bolt that covers 18 units in six frames had to turn.
		curved = true
	else:
		var heading: Vector3 = bolt.get("_velocity")
		curved = rad_to_deg(heading.normalized().angle_to(aim)) > 2.0
	_check(curved, "the bolt curves off the aim towards the lock")

	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame


## The rack is a radar and a charge: no button, no shot; held time loads the salvo;
## the radar decides how it is spread.
func _test_missiles(weapons: WeaponSystem) -> void:
	weapons.select(Arsenal.Kind.VULCAN)
	Input.action_release(&"aim_left")
	Input.action_release(&"missile")
	# With the stick centred the aim is read live from the mouse, and it keeps
	# drifting until the camera settles after the earlier weapon tests. Nothing is
	# placed against the aim until it stops moving: a target spawned against a
	# stale aim sits outside the radar and the lock looks broken.
	_clear_projectiles()
	_clear_enemies()
	await _wait_frames(45)

	await _test_missile_holds_fire(weapons)
	await _test_missile_load(weapons)
	await _test_missile_growth(weapons)
	await _test_missile_spread(weapons)
	await _test_missile_dead_contact(weapons)
	await _test_missile_radar_cone(weapons)
	await _test_missile_cap(weapons)
	await _test_missile_tap(weapons)
	await _test_missile_wings(weapons)
	await _test_missile_weave()
	await _test_lock_reticle()
	await _test_lock_scan(weapons)
	await _test_lock_reacquires_per_missile(weapons)

	Input.action_release(&"missile")
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame


## A turret in range buys nothing on its own: the button is the whole permission.
func _test_missile_holds_fire(weapons: WeaponSystem) -> void:
	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 20.0)
	_check(enemy != null, "spawned a target for the missiles")
	await _wait_frames(20)
	_check(
		_player_projectiles().is_empty(),
		"a turret in range never launches a missile on its own"
	)
	_check(weapons.salvo_count() == 0, "an idle rack holds no missiles")


## Held time loads the salvo: one missile per interval, fired only on release.
func _test_missile_load(weapons: WeaponSystem) -> void:
	_clear_enemies()
	await _wait_frames(2)
	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 20.0)
	_check(enemy != null, "spawned a turret ahead of the radar")
	if enemy == null:
		return
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(
		weapons.salvo_count() == 1,
		"an interval of hold loads a missile (loaded %d)" % weapons.salvo_count()
	)
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").size() == 1,
		"the radar rings the contact the salvo will chase"
	)

	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() == 1, "releasing fires the whole load (got %d)" % flight.size())
	_check(weapons.salvo_count() == 0, "a salvo empties the rack")
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").is_empty(),
		"the rings leave with the salvo"
	)
	if flight.is_empty():
		return

	var launched: Projectile = flight[0]
	_check(launched.get("_target") == enemy, "the missile chases the radar contact")
	_check(float(launched.get("_turn_rate")) > 0.0, "the missile is guided")
	await _test_missile_style(launched)
	await _test_missile_trail(launched)
	await _test_missile_orphans()
	_clear_projectiles()


## More hold, more missiles: one second loads four, and a lone contact takes the
## whole salvo instead of the load waiting for company.
func _test_missile_growth(weapons: WeaponSystem) -> void:
	_clear_enemies()
	await _wait_frames(30)
	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 18.0)
	_check(enemy != null, "spawned a lone turret for the load")
	if enemy == null:
		return
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(60)
	_check(
		weapons.salvo_count() == 4,
		"a second of hold loads four missiles (loaded %d)" % weapons.salvo_count()
	)

	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() == 4, "the whole salvo leaves together (got %d)" % flight.size())
	var targets: Array = []
	for missile in flight:
		targets.append(missile.get("_target"))
	_check(_unique_count(targets) == 1, "a lone contact takes every missile")
	_clear_projectiles()


## With more contacts than missiles spread evenly, the load is divided: three
## missiles over two turrets is 2/1, never 3/0 on the nearest one.
func _test_missile_spread(weapons: WeaponSystem) -> void:
	_clear_enemies()
	await _wait_frames(30)
	var aim: Vector3 = _aim()
	var near: Enemy = _spawn_enemy(_player.global_position + aim * 14.0)
	var far: Enemy = _spawn_enemy(_player.global_position + aim * 30.0)
	_check(near != null and far != null, "spawned two contacts inside the radar")
	if near == null or far == null:
		return
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(15)
	_check(
		weapons.salvo_count() == 1,
		"a quarter second loads one missile (loaded %d)" % weapons.salvo_count()
	)
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").size() == 1,
		"one loaded missile rings one contact, not the whole radar"
	)
	await _wait_frames(15)
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").size() == 2,
		"the second missile rings the second contact"
	)
	await _wait_frames(15)
	_check(
		weapons.salvo_count() == 3,
		"the load ignores how many contacts it is spread over (loaded %d)"
		% weapons.salvo_count()
	)

	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() == 3, "three loaded missiles leave (got %d)" % flight.size())
	var counts: Array[int] = [0, 0]
	for missile in flight:
		var target: Enemy = missile.get("_target") as Enemy
		if target == near:
			counts[0] += 1
		elif target == far:
			counts[1] += 1
	counts.sort()
	_check(
		counts[0] == 1 and counts[1] == 2,
		"three missiles over two contacts split 2/1 (%s)" % str(counts)
	)
	_clear_projectiles()


## A contact can die while it is ringed. Its mark has to leave with it without
## taking the rack with it: the salvo still fires at whatever is left.
func _test_missile_dead_contact(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	await _wait_frames(30)

	var aim: Vector3 = _aim()
	var doomed: Enemy = _spawn_enemy(_player.global_position + aim * 14.0)
	var survivor: Enemy = _spawn_enemy(_player.global_position + aim * 26.0)
	_check(survivor != null, "spawned two contacts, one of them doomed")
	if doomed == null or survivor == null:
		return
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(weapons.salvo_count() == 1, "the first missile loads against two contacts")

	doomed.take_damage(99)
	await _wait_frames(3)
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").size() == 1,
		"a dead contact takes its ring with it"
	)
	await _wait_frames(12)
	_check(
		weapons.salvo_count() == 2,
		"the load keeps growing after a contact dies (loaded %d)" % weapons.salvo_count()
	)

	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(
		flight.size() == 2,
		"the salvo still fires after a contact dies (got %d)" % flight.size()
	)
	_check(weapons.salvo_count() == 0, "the rack empties when a mark died mid-hold")
	_clear_projectiles()


## The radar looks forward. A turret behind the nose is neither a contact nor a
## target, no matter how close it is.
func _test_missile_radar_cone(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	await _wait_frames(30)

	var aim: Vector3 = _aim()
	var behind: Enemy = _spawn_enemy(_player.global_position - aim * 18.0)
	_check(behind != null, "spawned a turret behind the nose")
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(weapons.salvo_count() == 0, "a turret behind the nose loads nothing")
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").is_empty(),
		"an empty radar rings nothing"
	)
	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(_player_projectiles().is_empty(), "an empty radar releases nothing")


## Eight is the size of the rack: more held time does not buy a ninth, and the ninth
## turret is the one the radar drops.
func _test_missile_cap(weapons: WeaponSystem) -> void:
	await _wait_frames(30)
	var aim: Vector3 = _aim()
	var targets: Array[Enemy] = []
	for index in 9:
		targets.append(_spawn_enemy(_player.global_position + aim * float(14 + index * 4)))
	_check(targets.size() == 9, "spawned nine turrets, eight of them on the rack")
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(120)
	_check(
		weapons.salvo_count() == 8,
		"the rack caps at eight (loaded %d)" % weapons.salvo_count()
	)
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").size() == 8,
		"a full rack rings one contact per missile"
	)

	Input.action_release(&"missile")
	await _wait_frames(2)
	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() == 8, "eight loaded missiles leave (got %d)" % flight.size())

	# One target and one heading per missile: a full rack is eight separate chases,
	# not one target hit eight times.
	var chased: Array = []
	var lines: Array[int] = []
	for missile in flight:
		chased.append(missile.get("_target"))
		var shot: Vector3 = missile.get("_velocity")
		lines.append(int(round(rad_to_deg(atan2(shot.x, shot.z)) / 5.0)))
	_check(
		_unique_count(chased) == 8,
		"every missile of a full rack chases its own contact (%d)" % _unique_count(chased)
	)
	_check(
		_unique_count(lines) == 8,
		"a full rack still leaves on eight distinct lines (%s)" % str(lines)
	)

	# The cooldown right after a salvo: holding restarts nothing.
	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(
		weapons.salvo_count() == 0,
		"the salvo cooldown blocks the next charge (loaded %d)" % weapons.salvo_count()
	)
	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(
		_player_projectiles().size() == 8,
		"nothing leaves while the rack cools (got %d)" % _player_projectiles().size()
	)
	_clear_projectiles()


## A tap shorter than the load interval fires nothing at all: the hold is the
## weapon, not the press.
func _test_missile_tap(weapons: WeaponSystem) -> void:
	_clear_enemies()
	await _wait_frames(30)

	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 18.0)
	_check(enemy != null, "spawned a turret for the tap")
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(4)
	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(
		weapons.salvo_count() == 0,
		"a tap loads no missiles (loaded %d)" % weapons.salvo_count()
	)
	_check(_player_projectiles().is_empty(), "a tap fires nothing at all")

	# The same press, held past one interval, does load.
	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(
		weapons.salvo_count() == 1,
		"holding past the interval loads one (loaded %d)" % weapons.salvo_count()
	)
	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(_player_projectiles().size() == 1, "one loaded missile leaves")
	_clear_projectiles()


## The salvo leaves from the wings, one missile per wing and alternating sides. The
## hardpoint is read from the wing bone, so it rides the sweep instead of sitting at
## the nose, and consecutive missiles pick opposite sides.
func _test_missile_wings(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	await _wait_frames(40)

	var model: PlayerModel = _player.get("_model") as PlayerModel
	_check(model != null, "the airframe exposes its wing bones")
	if model == null:
		return
	var local: Array[Vector3] = model.wing_anchors()
	_check(local.size() == 2, "the airframe carries two wing hardpoints")
	if local.size() < 2:
		return

	var aim: Vector3 = _aim()
	var right: Vector3 = Vector3(-aim.z, 0.0, aim.x)
	var raw: Array = _player.call("_wing_hardpoints")
	var points: Array[Vector3] = []
	for item in raw:
		points.append(item)
	_check(points.size() == 2, "the player reports both wing hardpoints")
	if points.size() < 2:
		return

	var first: float = (points[0] - _player.global_position).dot(right)
	var second: float = (points[1] - _player.global_position).dot(right)
	_check(
		absf(first) > 0.5 and absf(second) > 0.5,
		"the hardpoints sit out on the wings (%.2f / %.2f off centre)" % [first, second]
	)
	_check(
		first * second < 0.0,
		"the hardpoints straddle the hull (%.2f / %.2f)" % [first, second]
	)

	var enemy: Enemy = _spawn_enemy(_player.global_position + aim * 18.0)
	_check(enemy != null, "spawned a contact for the wing salvo")
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(60)
	_check(
		weapons.salvo_count() >= 2,
		"the rack loads a pair for the wing salvo (loaded %d)" % weapons.salvo_count()
	)
	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() >= 2, "a pair of missiles leaves (got %d)" % flight.size())
	if flight.size() < 2:
		return

	var sides: Array[float] = []
	for missile in flight:
		sides.append((missile.global_position - _player.global_position).dot(right))
	_check(absf(sides[0]) > 0.5, "the first missile leaves from a wing (%.2f)" % sides[0])
	for index in range(1, sides.size()):
		_check(
			sides[index - 1] * sides[index] < 0.0,
			"consecutive missiles alternate wings (%.2f then %.2f)"
			% [sides[index - 1], sides[index]]
		)

	# A load is a spread, not a stream: every missile has to leave on its own line,
	# which is what makes the accumulated salvo read as a fan. The heading is read
	# off the shot two frames after launch, before guidance bends it far.
	var lines: Array[int] = []
	for missile in flight:
		var shot: Vector3 = missile.get("_velocity")
		var lateral: float = shot.dot(right) / maxf(shot.length(), 0.001)
		lines.append(int(round(rad_to_deg(asin(clampf(lateral, -1.0, 1.0))) / 5.0)))
	_check(
		_unique_count(lines) == flight.size(),
		"each missile of a salvo leaves on its own line (%s)" % [str(lines)]
	)
	_clear_projectiles()


## The salvo's trails braid: a shot spirals around its line of sight instead of
## tracking it dead straight, and still straightens out to hit what it locked.
func _test_missile_weave() -> void:
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame

	# Flown far from the arena: a queue_freed turret is still in the tree for the
	# tick that frees it, and a steering check that spawns at the origin can be
	# killed by a leftover contact from the test before it.
	var base: Vector3 = Vector3(400.0, 0.0, 400.0)
	var target: Node3D = Node3D.new()
	get_tree().current_scene.add_child(target)
	target.global_position = base + Vector3(0.0, 0.0, -32.0)

	var scene: PackedScene = load("res://combat/projectile.tscn")
	var missile: Projectile = scene.instantiate() as Projectile
	get_tree().current_scene.add_child(missile)
	missile.global_position = base
	missile.setup(
		Vector3(0.0, 0.0, -1.0),
		Arsenal.MISSILE_SPEED,
		Projectile.Team.PLAYER,
		Arsenal.MISSILE_DAMAGE,
		Arsenal.MISSILE_SIZE,
		target,
		Arsenal.MISSILE_TURN_RATE,
		Arsenal.MISSILE_COLOR,
		Projectile.LIFETIME,
		Projectile.Style.MISSILE
	)
	missile.set_weave(
		Arsenal.MISSILE_WEAVE_AMPLITUDE,
		Arsenal.MISSILE_WEAVE_RATE,
		0.0,
		Arsenal.MISSILE_WEAVE_HIT_RANGE,
		Arsenal.MISSILE_WEAVE_FADE
	)

	# The shot leaves down -Z towards the target, so its X is the distance off the
	# straight line: the weave has to open one, change side, and close it again.
	var swings: Array[int] = []
	var widest: float = 0.0
	var closest: float = INF
	for _i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(missile):
			break
		var offset: Vector3 = missile.global_position
		widest = maxf(widest, absf(offset.x - base.x))
		closest = minf(closest, offset.distance_to(target.global_position))
		var side: int = int(signf(offset.x - base.x))
		if swings.is_empty() or swings[-1] != side:
			swings.append(side)

	_check(widest > 1.5, "the shot spirals off the straight line (%.2f units)" % widest)
	_check(
		swings.size() >= 3,
		"the trail braids instead of bending once (%s)" % str(swings)
	)
	_check(
		closest < 2.5,
		"the shot straightens out and reaches its target (%.2f units)" % closest
	)

	target.queue_free()
	_clear_projectiles()
	await get_tree().physics_frame


## The mark is a lock, not a decal: it arrives wide and snaps down onto the
## contact, squeezing past its resting size before it settles.
func _test_lock_reticle() -> void:
	var host: Node3D = Node3D.new()
	get_tree().current_scene.add_child(host)
	var reticle: LockReticle = LockReticle.new()
	# S14: the box is size-parameterizable, so a capital ship frames its hull instead
	# of carrying the resting turret square. The extents are set before the mark
	# enters the tree, because `_ready` builds the mesh once.
	reticle.set_mark_size(Vector2(10.0, 3.0), 5.0)
	host.add_child(reticle)
	# Checked on the frame it is born: `_process` starts closing it from there.
	_check(
		reticle.scale.x > 1.2,
		"the mark arrives wider than its resting box (%.2f)" % reticle.scale.x
	)
	_check(
		is_equal_approx(reticle.position.y, 5.0),
		"a sized mark sits at its requested height (%.2f)" % reticle.position.y
	)
	# Four corner brackets are two quads each, plus the four triangles of the pip.
	var arrays: Array = (reticle.mesh as ImmediateMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(
		vertices.size() == 4 * 2 * 6 + 4 * 3,
		"the mark is four corner brackets and a centre pip (got %d vertices)"
		% vertices.size()
	)
	var bounds: AABB = (reticle.mesh as ImmediateMesh).get_aabb()
	_check(
		bounds.size.x > 19.0 and bounds.size.z > 5.0,
		"a sized mark frames the requested footprint (%.1f x %.1f)"
		% [bounds.size.x, bounds.size.z]
	)

	# The acquisition is more than a resize: a frame spins in, a burst leaves the
	# contact and a flash decays. Each one is driven by `_process`, so the test
	# samples them the way the screen does.
	var scan: MeshInstance3D = reticle.get_node_or_null(^"ScanFrame") as MeshInstance3D
	var burst: MeshInstance3D = reticle.get_node_or_null(^"Burst") as MeshInstance3D
	_check(scan != null and burst != null, "the lock has a scan frame and a burst")
	reticle.call("_process", 1.0 / 60.0)
	var start_spin: float = scan.rotation.y
	var start_burst: float = burst.scale.x
	var start_flash: float = (reticle.material_override as StandardMaterial3D).emission_energy_multiplier
	_check(
		start_flash > LockReticle.GLOW,
		"the lock arrives with a flash (%.2f)" % start_flash
	)
	_check(
		scan.transparency < 1.0,
		"the scan frame is drawn while the lock closes (%.2f)" % scan.transparency
	)

	# Driven frame by frame instead of by wall clock: the snap is an overshoot, and
	# a single sample after the fact misses the squeeze that makes it read as a snap.
	var lowest: float = reticle.scale.x
	for _i in 14:
		reticle.call("_process", 1.0 / 60.0)
		lowest = minf(lowest, reticle.scale.x)
	_check(
		lowest < 0.96,
		"the box squeezes past its resting size on the way in (%.2f)" % lowest
	)
	_check(
		absf(reticle.scale.x - 1.0) < 0.06,
		"the mark settles onto the contact (%.2f)" % reticle.scale.x
	)
	_check(
		reticle.transparency <= 0.05,
		"the mark is fully drawn once the lock has closed (%.2f)" % reticle.transparency
	)
	_check(
		scan.rotation.y > start_spin,
		"the scan frame spins into place (%.2f -> %.2f)" % [start_spin, scan.rotation.y]
	)
	_check(
		burst.scale.x > start_burst,
		"the burst leaves the contact (%.2f -> %.2f)" % [start_burst, burst.scale.x]
	)
	_check(
		(reticle.material_override as StandardMaterial3D).emission_energy_multiplier
		< start_flash,
		"the arrival flash decays"
	)
	_check(
		scan.transparency > 0.5,
		"the scan frame is gone once the lock settles (%.2f)" % scan.transparency
	)

	host.queue_free()
	await get_tree().process_frame


## The lock is a scan, not a paint job. The rack walks the contacts one at a time,
## so only the newest lock is still being acquired and every earlier one has
## settled back: that is what reads as a single reticle moving down the pool
## instead of eight boxes appearing at once.
##
## The number on each box is the missiles that contact will take, not the order it
## was locked: the salvo is spread round-robin over the pool, so the picture
## promises the split `_fire_salvo` will actually produce. Every assignment stings
## once, at the same pitch, so a full rack is eight sounds and not one.
func _test_lock_scan(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	Input.action_release(&"missile")
	await _wait_frames(30)
	# The previous block leaves the rack cooling, and a cooling rack never marks.
	weapons.radar().set_cooldown(0.0)

	var aim: Vector3 = _aim()
	var spawned: Array[Enemy] = []
	for index in 3:
		spawned.append(
			_spawn_enemy(_player.global_position + aim * float(16 + index * 5))
		)
	await _wait_frames(2)
	# Nearest first, the order the rack spreads the salvo over. Computed from the
	# contacts instead of assumed from the spawn loop, so the check follows the
	# radar and not the test's own order.
	var by_distance: Array[Enemy] = spawned.duplicate()
	by_distance.sort_custom(
		func(a: Enemy, b: Enemy) -> bool:
			return (
				a.global_position.distance_squared_to(_player.global_position)
				< b.global_position.distance_squared_to(_player.global_position)
			)
	)

	Sfx.reset_counts()
	Input.action_press(&"missile")
	var guard: int = 0
	while weapons.salvo_count() < 2 and guard < 120:
		await get_tree().physics_frame
		guard += 1
	_check(
		weapons.salvo_count() == 2,
		"the scan loads one missile per contact (loaded %d)" % weapons.salvo_count()
	)
	_check(
		Sfx.played(&"lock_tone") == 2,
		"every assignment stings once (%d)" % Sfx.played(&"lock_tone")
	)
	var first_pitch: float = Sfx.pitch(&"lock_tone")
	_check(
		_tally_texts() == ["×1", "×1"],
		"each marked contact shows the one missile it will take (%s)"
		% str(_tally_texts())
	)

	# Fill the rack. Three contacts over eight missiles is a 3/3/2 round-robin, so
	# the box showing ×2 is the one the salvo only chases twice.
	guard = 0
	while weapons.salvo_count() < Arsenal.MISSILE_MAX_SALVO and guard < 240:
		await get_tree().physics_frame
		guard += 1
	_check(
		weapons.salvo_count() == Arsenal.MISSILE_MAX_SALVO,
		"the hold fills the whole rack (%d)" % weapons.salvo_count()
	)
	_check(
		Sfx.played(&"lock_tone") == Arsenal.MISSILE_MAX_SALVO,
		"a full rack stings once per assignment (%d)" % Sfx.played(&"lock_tone")
	)
	_check(
		is_equal_approx(first_pitch, 1.0)
		and is_equal_approx(Sfx.pitch(&"lock_tone"), first_pitch),
		"the sting keeps one pitch for the whole rack (%.2f -> %.2f)"
		% [first_pitch, Sfx.pitch(&"lock_tone")]
	)
	_check(
		_tally_texts() == ["×2", "×3", "×3"],
		"the marks show the 3/3/2 split the salvo will produce (%s)"
		% str(_tally_texts())
	)

	var acquired: int = 0
	var settled: int = 0
	for node in get_tree().get_nodes_in_group(&"lock_reticle"):
		var reticle: LockReticle = node as LockReticle
		if reticle.scale.x > 0.95:
			acquired += 1
		elif reticle.scale.x < 0.9:
			settled += 1
	_check(
		acquired == 1,
		"only the newest lock is still being acquired (%d of 3)" % acquired
	)
	_check(settled == 2, "the earlier locks have settled back (%d of 3)" % settled)
	var active: LockSlot = weapons.radar().active_mark()
	_check(
		active != null and active.host == by_distance[1],
		"the scan ends on the contact the last missile takes"
	)

	Input.action_release(&"missile")
	await _wait_frames(2)
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame


## One contact, several missiles. The lock-in belongs to the assignment, not to the
## active target: with a single contact the scan never moves, so a target-only rule
## would announce the first missile and leave the other seven silent and still.
func _test_lock_reacquires_per_missile(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	Input.action_release(&"missile")
	await _wait_frames(30)
	weapons.radar().set_cooldown(0.0)

	var aim: Vector3 = _aim()
	_spawn_enemy(_player.global_position + aim * 18.0)
	await _wait_frames(2)

	Sfx.reset_counts()
	Input.action_press(&"missile")
	var guard: int = 0
	while weapons.salvo_count() < 2 and guard < 120:
		await get_tree().physics_frame
		guard += 1

	var reticle: LockReticle = null
	for node in get_tree().get_nodes_in_group(&"lock_reticle"):
		reticle = node as LockReticle
	_check(reticle != null, "the single contact carries a lock")
	_check(
		reticle.scale.x > 1.2,
		"the second missile re-runs the lock on the same contact (%.2f)"
		% reticle.scale.x
	)
	_check(
		_tally_texts() == ["×2"],
		"the single contact shows the two missiles it will take (%s)"
		% str(_tally_texts())
	)

	guard = 0
	while weapons.salvo_count() < 3 and guard < 120:
		await get_tree().physics_frame
		guard += 1
	_check(
		reticle.scale.x > 1.2,
		"the third missile re-runs the lock again (%.2f)" % reticle.scale.x
	)
	_check(
		Sfx.played(&"lock_tone") == 3,
		"each of the three assignments stings once (%d)" % Sfx.played(&"lock_tone")
	)

	Input.action_release(&"missile")
	await _wait_frames(2)
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame


## The shape is the weapon's identity on screen, so it is owned by the weapon style
## and not inferred from guidance: guidance stays a property of the flight.
func _test_missile_style(missile: Projectile) -> void:
	_check(
		int(missile.get("_style")) == Projectile.Style.MISSILE,
		"the player missile asks for the missile model"
	)
	_check(
		_mesh_parts(missile) >= 4,
		"the missile model is more than a box: body, nose, fins and exhaust"
	)


## The trail is read in motion, so it is checked in motion: puffs have to appear
## behind the shot, and they have to outlive it instead of vanishing with it.
func _test_missile_trail(missile: Projectile) -> void:
	for _i in 6:
		await get_tree().physics_frame

	var puffs: Array[Node] = get_tree().get_nodes_in_group(&"smoke_puff")
	_check(not puffs.is_empty(), "a missile leaves a smoke trail behind it")
	if puffs.is_empty():
		return

	var shot: Vector3 = missile.get("_velocity")
	var heading: Vector3 = shot.normalized()
	var sample: Node3D = null
	var behind: bool = true
	for node in puffs:
		var puff: Node3D = node as Node3D
		if puff == null:
			continue
		if (puff.global_position - missile.global_position).dot(heading) > 0.05:
			behind = false
		elif sample == null:
			sample = puff
	_check(behind, "every puff trails behind the missile, never ahead of it")

	if sample == null:
		return

	missile.queue_free()
	await get_tree().physics_frame
	_check(
		is_instance_valid(sample), "the smoke already in the air survives the missile"
	)

	for _i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(sample):
			break
	_check(not is_instance_valid(sample), "the puffs fade out and free themselves")


## The missile model is built on its own path, and that path used to allocate a
## MeshInstance3D it never parented: one orphan node per shot, which surfaces at
## exit as a leaked RID. The orphan counter is the cheap proof, and it has to stay
## flat across the spawn.
func _test_missile_orphans() -> void:
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var missile: Projectile = _spawn_enemy_missile(Vector3(0.0, 0.0, 30.0), _player)
	await get_tree().physics_frame
	var after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(
		after == before,
		"building a missile model leaves no orphan node (before %d, after %d)"
		% [before, after]
	)
	missile.queue_free()
	await get_tree().physics_frame


## The bomb is the emergency button, so it has to pay out in one frame: damage, the
## cancel, and the charge spent. A bomb that only cancels is a dodge, not a bomb.
func _test_bomb(weapons: WeaponSystem) -> void:
	var start: int = weapons.bomb_charges()
	_check(
		start == Arsenal.BOMB_START_CHARGES,
		"the bomb starts with %d charges (found %d)" % [Arsenal.BOMB_START_CHARGES, start]
	)

	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 10.0)
	var before: int = enemy.current_hp() if enemy != null else 0

	_clear_projectiles()
	await get_tree().physics_frame
	var first: Projectile = _spawn_enemy_bullet(_player.global_position + Vector3(2.0, 0.0, 2.0))
	var second: Projectile = _spawn_enemy_bullet(_player.global_position - Vector3(2.0, 0.0, 3.0))
	await get_tree().physics_frame

	Input.action_press(&"bomb")
	await get_tree().physics_frame
	Input.action_release(&"bomb")
	await get_tree().physics_frame

	_check(weapons.bomb_charges() == start - 1, "the bomb spends one charge")
	_check(
		not is_instance_valid(first) and not is_instance_valid(second),
		"the bomb cancels enemy fire around the ship"
	)
	_check(
		not is_instance_valid(enemy) or enemy.current_hp() < before,
		"the bomb damages enemies inside the blast"
	)

	_clear_enemies()
	await get_tree().physics_frame


## A resource that never comes back is a save-for-later item, not an emergency
## button: kills have to pay for it, and the rack has to stop at its cap.
func _test_bomb_refill(weapons: WeaponSystem) -> void:
	var before: int = weapons.bomb_charges()
	for _i in Arsenal.BOMB_KILLS_PER_CHARGE:
		GlobalEventBus.enemy_killed.emit(Turret.SCORE_VALUE)
	await get_tree().physics_frame
	_check(
		weapons.bomb_charges() == before + 1,
		"%d kills refund one charge (%d -> %d)"
		% [Arsenal.BOMB_KILLS_PER_CHARGE, before, weapons.bomb_charges()]
	)

	for _i in Arsenal.BOMB_KILLS_PER_CHARGE * Arsenal.BOMB_MAX_CHARGES:
		GlobalEventBus.enemy_killed.emit(Turret.SCORE_VALUE)
	await get_tree().physics_frame
	_check(
		weapons.bomb_charges() == Arsenal.BOMB_MAX_CHARGES,
		"the rack caps at %d charges (found %d)"
		% [Arsenal.BOMB_MAX_CHARGES, weapons.bomb_charges()]
	)


## The decoy is a countermeasure, not a weapon: the only thing it has to do is take
## a guided shot off the ship and leave it flying straight when the flare burns out.
func _test_decoy(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	var missile: Projectile = _spawn_enemy_missile(Vector3(0.0, 0.0, 14.0), _player)
	_check(bool(missile.call("is_homing")), "an enemy missile is a guided shot")
	_check(missile.get("_target") == _player, "a guided shot starts on the ship")

	_check(weapons.drop_decoy(Vector3.ZERO), "the ship drops a decoy")

	# The ship leaves the spot: the flare only pays if the missile is now heading
	# somewhere the player is not.
	_player.global_position = Vector3(30.0, 0.0, -20.0)
	for _i in 4:
		await get_tree().physics_frame

	var decoy: Node3D = null
	for node in get_tree().get_nodes_in_group(&"decoy"):
		decoy = node as Node3D
	_check(decoy != null, "the decoy joins the decoy group")
	_check(missile.get("_target") == decoy, "the decoy takes the missile's lock")
	_check(
		not weapons.drop_decoy(_player.global_position),
		"the decoy has a cooldown"
	)

	# A shot with nothing left to chase flies straight: the drop buys distance,
	# never a kill. The flare is set alight early instead of waiting the whole
	# three seconds, which is the same path the lifetime takes.
	if decoy != null:
		decoy.set("_life", 0.05)
	for _i in 8:
		await get_tree().physics_frame
	_check(not is_instance_valid(decoy), "the decoy burns out")

	if is_instance_valid(missile):
		var heading: Vector3 = missile.get("_velocity")
		for _i in 10:
			await get_tree().physics_frame
		var after: Vector3 = missile.get("_velocity")
		_check(
			after.is_equal_approx(heading),
			"the missile flies straight once the decoy is gone"
		)
	else:
		_check(false, "the missile survives the decoy")

	_clear_projectiles()
	for node in get_tree().get_nodes_in_group(&"decoy"):
		node.queue_free()
	await get_tree().physics_frame


## Interception is the second answer to a guided shot, and it is deliberately
## narrow: the missile is a target, a bullet from a pattern is not. Making every
## orb shootable would turn a bullet-hell pattern into a wall of props, so the two
## halves are checked together.
func _test_missile_intercept() -> void:
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	# Both shots are parked well off to the side and aimed at each other, so the
	# check is the interception and not a race against a missile reaching the ship.
	var dummy: Node3D = Node3D.new()
	get_tree().current_scene.add_child(dummy)
	dummy.global_position = Vector3(-40.0, 0.0, -60.0)

	var missile: Projectile = _spawn_enemy_missile(Vector3(-40.0, 0.0, 20.0), dummy)
	_spawn_player_bullet(Vector3(-40.0, 0.0, 10.0), Vector3(0.0, 0.0, 1.0))
	for _i in 30:
		await get_tree().physics_frame
		if not is_instance_valid(missile):
			break
	_check(
		not is_instance_valid(missile),
		"a player shot destroys an enemy missile"
	)

	var orb_scene: PackedScene = load("res://combat/projectile.tscn")
	var orb: Projectile = orb_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(orb)
	orb.global_position = Vector3(-40.0, 0.0, 20.0)
	orb.setup(Vector3(0.0, 0.0, -1.0), 20.0, Projectile.Team.ENEMY, 1)
	_spawn_player_bullet(Vector3(-40.0, 0.0, 10.0), Vector3(0.0, 0.0, 1.0))
	for _i in 30:
		await get_tree().physics_frame
	_check(
		is_instance_valid(orb),
		"a player shot passes through a bullet pattern"
	)

	dummy.queue_free()
	_clear_projectiles()
	await get_tree().physics_frame


func _test_firing_costs_no_speed(weapons: WeaponSystem) -> void:
	weapons.select(Arsenal.Kind.VULCAN)
	Input.action_press(&"move_right")
	Input.action_press(&"fire")
	for _i in 60:
		await get_tree().physics_frame
	var speed: float = _flat_speed()
	Input.action_release(&"fire")
	Input.action_release(&"move_right")

	_check(
		absf(speed - Player.MAX_SPEED) < 2.0,
		"firing costs no translation speed (%.1f u/s)" % speed
	)
	_clear_projectiles()
	await get_tree().physics_frame


