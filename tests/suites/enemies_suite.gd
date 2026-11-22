class_name EnemiesSuite
extends SmokeSuite
## The hostiles: turret patterns and roaming, the launcher, the
## interceptor, the death blasts and the mothership.

## S4, S5, S6, S8, S9, S13: the mothership arrives on the run threshold, is solid,
## is fought as three independently attackable sections, feeds its bar, escalates at
## 60 percent, and comes apart at the hull's own scale when the third section falls.
func _test_boss() -> void:
	_clear_enemies()
	_clear_projectiles()
	# The spawner is parked for the test: the arrival is what is under test, and a
	# fighter wandering into the set piece would make the projectile counts ambiguous.
	_arena.director().park()
	await get_tree().physics_frame

	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var boss_root: Control = hud.get_node("%BossRoot") as Control
	var boss_name: Label = hud.get_node("%BossName") as Label
	_check(boss_root != null, "the HUD has a boss bar container")
	if boss_root == null or boss_name == null:
		return
	_check(not boss_root.visible, "the boss bar starts hidden")

	var appeared: Array[String] = []
	var health: Array[Vector2i] = []
	# Arrays are captured by reference; a plain int would be copied into the lambda
	# and the count would never leave it.
	var defeats: Array[bool] = []
	var on_appeared: Callable = func(name: String, maximum: int) -> void:
		appeared.append("%s:%d" % [name, maximum])
	var on_health: Callable = func(current: int, maximum: int) -> void:
		health.append(Vector2i(current, maximum))
	var on_defeated: Callable = func() -> void:
		defeats.append(true)
	GlobalEventBus.boss_appeared.connect(on_appeared)
	GlobalEventBus.boss_health_changed.connect(on_health)
	GlobalEventBus.boss_defeated.connect(on_defeated)

	# Drive the real trigger: one kill short of the threshold, then a kill. The
	# suite parked the counter, so this is the only place the arrival path runs.
	_arena.run_state().kills = Arena.BOSS_KILL_THRESHOLD - 1
	var trigger: Enemy = _spawn_turret(_player.global_position + Vector3(24.0, 0.0, 0.0))
	# A fighter already in the stream has to survive the arrival: the ship escalates
	# the run instead of wiping the field. It sits in the stream's own container, which
	# is where the old arrival used to free everything.
	var stream: Node = _arena.get("_enemies") as Node
	var escort: Enemy = (
		load("res://entities/enemy/turret.tscn").instantiate() as Enemy
	)
	if stream != null and escort != null:
		stream.add_child(escort)
		escort.setup_spawn(_player.global_position + Vector3(-26.0, 0.0, 16.0))
	await get_tree().physics_frame
	if trigger != null:
		trigger.take_damage(trigger.current_hp())
	await get_tree().physics_frame

	var ship: Boss = _arena.boss()
	_check(ship != null, "the run threshold brings the mothership in")
	if ship == null:
		GlobalEventBus.boss_appeared.disconnect(on_appeared)
		GlobalEventBus.boss_health_changed.disconnect(on_health)
		GlobalEventBus.boss_defeated.disconnect(on_defeated)
		return

	_check(ship.is_in_group(&"boss"), "the mothership joins the boss group")

	# S15: the fighters already on the field stay when the ship arrives. The arrival
	# used to free every non-boss enemy, which reset the run at its climax.
	_check(
		is_instance_valid(escort) and not escort.is_queued_for_deletion(),
		"the fighters already on the field stay when the boss arrives"
	)
	if is_instance_valid(escort):
		escort.queue_free()
	await get_tree().physics_frame

	# S13/S15: the hull is three target points, one per section, not one pool. Each
	# point is a solid box on the world and enemy layers, so it blocks the player and
	# every shot finds it; each section owns exactly one of them, as wide as the beam.
	var parts: Array[BossPart] = ship.parts()
	_check(
		parts.size() == Boss.PART_COUNT,
		"the hull is three target points (%d)" % parts.size()
	)
	if parts.size() != Boss.PART_COUNT:
		GlobalEventBus.boss_appeared.disconnect(on_appeared)
		GlobalEventBus.boss_health_changed.disconnect(on_health)
		GlobalEventBus.boss_defeated.disconnect(on_defeated)
		return

	var section_length: float = (
		Boss.MODEL_SIZE.x * Boss.SCALE / float(Boss.SECTION_COUNT)
	)
	var part_width: float = Boss.MODEL_SIZE.z * Boss.SCALE

	# The encounter fires a laser and homing missiles from three sections now. This
	# test is about the ship's state, not about surviving it, so the player is made
	# untouchable for its duration and handed back clean at the end.
	_player.set("_invulnerable", 1.0e9)

	# S14: each section answers with a different weapon. The three guns are three
	# problems, not one broadside repeated, so destroying a section removes a threat
	# the player can name.
	var weapons: Array[BossWeapon] = ship.weapons()
	_check(
		weapons.size() == Boss.SECTION_COUNT,
		"each section carries its own gun (%d)" % weapons.size()
	)
	if weapons.size() == Boss.SECTION_COUNT:
		_check(
			weapons[0].kind() == BossWeapon.Kind.VULCAN
				and weapons[1].kind() == BossWeapon.Kind.MISSILES
				and weapons[2].kind() == BossWeapon.Kind.LASER,
			"the bow fires a vulcan, the middle missiles and the stern the laser"
		)
		for section in weapons.size():
			_check(
				is_zero_approx(weapons[section].position.y),
				"section %d fires from the play plane" % section
			)
			_check(
				is_equal_approx(
					weapons[section].position.x,
					parts[section].position.x
				),
				"section %d fires from its own place on the keel" % section
			)

	# S14: the missile lock has to be visible on a 96-unit hull AND sit on it. A
	# hull-sized frame hangs its corners over the water, which reads as a mark that
	# came off the ship; a turret-sized box disappears. The mark is a small box on
	# the hull, drawn over the model so the opaque ship cannot hide it.
	var mark: Vector3 = ship.lock_mark()
	var hull_top: float = Boss.GROUND_Y + Boss.MODEL_SIZE.y * Boss.SCALE
	_check(
		mark.x < Boss.MODEL_SIZE.x * Boss.SCALE * 0.2
			and mark.z < Boss.MODEL_SIZE.z * Boss.SCALE * 0.7,
		"the mothership's lock mark is a small box, not a frame around a third (%.1f x %.1f)"
		% [mark.x, mark.z]
	)
	_check(
		mark.y > Boss.GROUND_Y and mark.y < hull_top,
		"the lock mark sits on the hull instead of floating above it (%.1f)" % mark.y
	)
	_check(
		ship.lock_mark_on_hull(),
		"the lock mark is drawn over the hull it sits in"
	)

	# S17: the rack can be spent on any third of the hull. The ship offers one lock
	# anchor per section, on the hull's own height, and the radar turns that single
	# contact into three slots so the salvo splits over the bow, the middle and the
	# stern instead of piling on one mark.
	var anchors: Array[Node3D] = ship.lock_mark_anchors()
	_check(
		anchors.size() == Boss.SECTION_COUNT,
		"the ship offers one lock anchor per section (%d)" % anchors.size()
	)
	if anchors.size() == Boss.SECTION_COUNT:
		var anchor_x: Array[float] = []
		for section in anchors.size():
			var anchor: Node3D = anchors[section]
			_check(
				anchor.is_inside_tree() and anchor.get_parent() == ship,
				"lock anchor %d hangs from the ship" % section
			)
			if section < Boss.SECTION_COUNT:
				_check(
					is_equal_approx(
						anchor.position.x,
						parts[section].position.x
					),
					"lock anchor %d sits on its own section" % section
				)
			_check(
				is_equal_approx(
					anchor.position.y,
					Boss.GROUND_Y + Boss.MODEL_SIZE.y * Boss.SCALE * 0.5
				),
				"lock anchor %d sits at the hull's own height (%.1f)"
				% [section, anchor.position.y]
			)
			anchor_x.append(anchor.position.x)
		anchor_x.sort()
		_check(
			anchor_x[2] - anchor_x[0] > Boss.MODEL_SIZE.x * Boss.SCALE * 0.5,
			"the anchors spread along the keel, not on one spot (%.1f)"
			% (anchor_x[2] - anchor_x[0])
		)

		var lock_weapons: WeaponSystem = _player.get_node("Weapons") as WeaponSystem
		var bow_dir: Vector3 = Vector3(cos(ship.rotation.y), 0.0, -sin(ship.rotation.y))
		var radar_origin: Vector3 = ship.global_position + bow_dir * 20.0
		var pool: Array[LockSlot] = lock_weapons.radar().radar_pool(radar_origin, -bow_dir)
		var hull_slots: Array[LockSlot] = []
		for slot in pool:
			if slot.contact == ship:
				hull_slots.append(slot)
		_check(
			hull_slots.size() == Boss.SECTION_COUNT,
			"the radar sees the hull as three targets (%d)" % hull_slots.size()
		)
		if hull_slots.size() == Boss.SECTION_COUNT:
			var hosts: Array[Node3D] = []
			for slot in hull_slots:
				hosts.append(slot.host)
			_check(
				hosts.has(anchors[0]) and hosts.has(anchors[1]) and hosts.has(anchors[2]),
				"the pool is one slot per anchor"
			)
			# A full rack over three slots is the 3/3/2 split the marks promise,
			# and the missiles steer to the anchor, not to the hull's centre.
			lock_weapons.radar().set_loaded(Arsenal.MISSILE_MAX_SALVO)
			lock_weapons.radar().sync_marks(hull_slots)
			_check(
				_tally_texts() == ["×2", "×3", "×3"],
				"the three marks promise the 3/3/2 split (%s)" % str(_tally_texts())
			)
			var marked_after: Array[LockSlot] = lock_weapons.radar().marks()
			_check(
				marked_after.size() == Boss.SECTION_COUNT,
				"the rack carries one mark per anchor (%d)" % marked_after.size()
			)
			lock_weapons.radar().discharge()

	for index in parts.size():
		var part: BossPart = parts[index]
		var section: int = part.section_id
		_check(
			part.current_hp() == Boss.PART_HP,
			"point %d starts with its own pool (%d)" % [index, part.current_hp()]
		)
		_check(
			section == index,
			"point %d belongs to section %d" % [index, section]
		)
		_check(
			part.collision_layer == 9,
			"point %d sits on the world and enemy layers" % index
		)
		var collider: CollisionShape3D = part.get_node_or_null("Shape") as CollisionShape3D
		var shape: BoxShape3D = null
		if collider != null:
			shape = collider.shape as BoxShape3D
		_check(shape != null, "point %d has a box collider" % index)
		if shape != null:
			_check(
				is_equal_approx(shape.size.x, section_length),
				"point %d is a third of the hull long (%.1f)" % [index, shape.size.x]
			)
			_check(
				is_equal_approx(shape.size.y, Boss.MODEL_SIZE.y * Boss.SCALE),
				"point %d is as tall as the hull" % index
			)
			_check(
				is_equal_approx(shape.size.z, part_width),
				"point %d spans the beam (%.1f)" % [index, shape.size.z]
			)
		# The box is centred on the hull, not on the body origin: a shape at the
		# origin leaves the top decks outside the collision, where a shot can
		# visibly cross them and miss.
		_check(
			is_equal_approx(
				part.position.y,
				Boss.GROUND_Y + Boss.MODEL_SIZE.y * Boss.SCALE * 0.5
			),
			"point %d sits at the hull's centre, not on the play plane" % index
		)

	_check(
		parts[0].position.x > parts[1].position.x
			and parts[1].position.x > parts[2].position.x,
		"the sections run bow, middle, stern along the keel"
	)
	for section in Boss.SECTION_COUNT:
		_check(
			is_zero_approx(parts[section].position.z),
			"section %d's point sits on the keel, not on a half of the beam" % section
		)

	# S6: the bar arrives with the ship, named and full, fed only by the bus.
	_check(
		appeared.size() == 1 and appeared[0] == "%s:%d" % [Boss.BOSS_NAME, Boss.BOSS_HP],
		"the arrival names the ship and its pool (%s)" % str(appeared)
	)
	_check(boss_root.visible, "the boss bar appears with the ship")
	_check(boss_name.text == Boss.BOSS_NAME, "the bar carries the ship's name")

	# S2: it flies. The hull has to move on its own heading, not hold station.
	var before_position: Vector3 = ship.global_position
	for _i in 4:
		await get_tree().physics_frame
	_check(
		ship.global_position.distance_to(before_position) > 0.05,
		"the mothership flies instead of holding station"
	)

	# S7/S14: the first burst actually leaves the hull. The bow is the vulcan, so its
	# own windup, not a hull-wide telegraph, is what delays the shot. Waiting the real
	# clock is the only honest way to assert it.
	_clear_projectiles()
	await get_tree().create_timer(
		Boss.FIRST_BURST_DELAY + BossWeapon.VULCAN_WINDUP + 0.4
	).timeout
	_check(
		_count_projectiles(Projectile.Team.ENEMY) > 0,
		"the mothership's first burst leaves the hull"
	)
	_clear_projectiles()
	await get_tree().physics_frame

	# S13/S12/S15: a real player dart lands on the point it crosses. This is the
	# regression guard for "my shots do nothing on a ship this big", and the guard
	# that the points are actually independent: the other two stay untouched.
	var bow: Vector3 = Vector3(cos(ship.rotation.y), 0.0, -sin(ship.rotation.y))
	var shot_from: Vector3 = (
		ship.global_position
		+ bow * (Boss.MODEL_SIZE.x * Boss.SCALE * 0.5 + 5.0)
	)
	var bow_hp: int = parts[0].current_hp()
	var total_before: int = ship.current_hp()
	var shot: Projectile = (
		load("res://combat/projectile.tscn").instantiate() as Projectile
	)
	get_tree().current_scene.add_child(shot)
	shot.global_position = shot_from
	shot.setup(-bow, 80.0, Projectile.Team.PLAYER, 1)
	for _i in 12:
		await get_tree().physics_frame
	_check(
		parts[0].current_hp() < bow_hp,
		"a player shot wears down the point it crosses (%d -> %d)"
		% [bow_hp, parts[0].current_hp()]
	)
	var untouched: bool = true
	for index in range(1, parts.size()):
		if parts[index].current_hp() != Boss.PART_HP:
			untouched = false
	_check(untouched, "a shot only damages the point it crosses")
	_check(
		ship.current_hp() < total_before,
		"point damage reaches the hull's total (%d -> %d)"
		% [total_before, ship.current_hp()]
	)
	_clear_projectiles()
	await get_tree().physics_frame

	# S6/S7: damage is a bus event, and the pool the bar divides by is the starting
	# pool, not what is left.
	ship.take_damage(1)
	_check(
		not health.is_empty()
			and health[health.size() - 1] == Vector2i(ship.current_hp(), Boss.BOSS_HP),
		"damage reaches the bar through the bus (%s)" % str(health)
	)

	# S12: a hit has to be visible on a hull this large. The flash is a billboard,
	# and a billboarded instance discards its own scale, so the size must live in the
	# mesh or the flash renders one unit wide and never shows.
	var flash: MeshInstance3D = ship.get("_hull_flash") as MeshInstance3D
	var flash_quad: QuadMesh = ship.get("_hull_flash_quad") as QuadMesh
	_check(flash != null and flash.visible, "a hit flashes on the hull")
	_check(
		flash_quad != null and is_equal_approx(flash_quad.size.x, Boss.HIT_FLASH_SIZE),
		"the hit flash is hull-sized, not a one-unit billboard"
	)

	# S11: fire is local to the section that is wearing down. No fire at full health,
	# and a fire on the bow once the bow has taken a real hit.
	_check(ship.burning_fires() == 0, "the hull does not burn at full health")
	ship.take_damage(int(float(Boss.BOSS_HP) * 0.12))
	_check(ship.burning_fires() >= 1, "the first deck lights up after damage")

	# S13/S15: the bow falls when its point does. One point per section makes the
	# section and the point the same unit, so the gun goes quiet on that same hit.
	ship.take_damage(parts[0].current_hp())
	_check(parts[0].is_destroyed(), "the bow's target point falls")
	_check(
		ship.is_section_destroyed(0),
		"the bow section is destroyed with its only point"
	)
	_check(ship.destroyed_parts() == 1, "one of three target points is down")
	_check(ship.destroyed_sections() == 1, "one of three sections is down")
	_check(defeats.is_empty(), "one destroyed section does not end the fight")
	_check(
		ship.current_hp() == Boss.BOSS_HP - Boss.PART_HP,
		"the hull survives one section (%d)" % ship.current_hp()
	)
	_check(
		ship.section_hp(1) == Boss.PART_HP and ship.section_hp(2) == Boss.PART_HP,
		"the surviving sections keep their pools"
	)
	_check(
		ship.burning_fires() == 2,
		"a destroyed section burns at full intensity (%d lit)" % ship.burning_fires()
	)

	# S14: a destroyed section goes quiet. The gun reads its own section, so the bow's
	# vulcan is silenced without a second bookkeeping path, and the two surviving guns
	# keep answering.
	if weapons.size() == Boss.SECTION_COUNT:
		var silenced_shots: int = weapons[0].shots_fired()
		weapons[0].arm(0.0)
		for _i in 150:
			await get_tree().physics_frame
		_check(weapons[0].is_silenced(), "the destroyed bow's gun is silenced")
		_check(
			weapons[0].shots_fired() == silenced_shots,
			"the destroyed section never fires again (%d -> %d)" % [
				silenced_shots, weapons[0].shots_fired()
			]
		)
		_check(
			not weapons[1].is_silenced() and not weapons[2].is_silenced(),
			"the surviving sections keep their guns"
		)
		_clear_projectiles()

	# S8: the second phase is a health threshold, not a scripted beat. It reads the
	# sum of the sections, so it arrives when the ship as a whole is worn down.
	_check(not ship.is_phase_two(), "the ship is still in its first phase")
	var to_threshold: int = (
		ship.current_hp() - int(float(Boss.BOSS_HP) * Boss.PHASE_TWO_RATIO)
	)
	ship.take_damage(to_threshold)
	_check(
		ship.is_phase_two(),
		"below %d percent the ship enters its second phase (hp %d)"
		% [int(Boss.PHASE_TWO_RATIO * 100.0), ship.current_hp()]
	)
	_check(
		ship.burning_fires() >= 3,
		"more decks burn as the pool drains (%d lit)" % ship.burning_fires()
	)

	# S13/S15: the middle section falls when its point does; the ship is still alive
	# with the stern standing.
	ship.take_damage(ship.section_hp(1))
	_check(ship.is_section_destroyed(1), "the middle section falls on its own")
	_check(
		ship.destroyed_sections() == 2
			and ship.current_hp() == Boss.PART_HP,
		"two sections down leave one standing (%d)" % ship.current_hp()
	)
	_check(defeats.is_empty(), "two destroyed sections still do not end the fight")

	# S9/S13: the third section ends the fight, pays, hides the bar, and the wreck
	# frees itself after the break-up.
	var score_before: int = _arena.score()
	ship.take_damage(ship.section_hp(2))
	_check(ship.destroyed_parts() == Boss.PART_COUNT, "all three target points are destroyed")
	_check(ship.destroyed_sections() == Boss.SECTION_COUNT, "all three sections are destroyed")
	_check(defeats.size() == 1, "the defeat is announced once")
	_check(
		_arena.score() == score_before + Boss.BOSS_SCORE,
		"the kill pays %d points (score %d)" % [Boss.BOSS_SCORE, _arena.score()]
	)
	_check(not boss_root.visible, "the boss bar leaves with the ship")

	await get_tree().create_timer(
		Boss.DEATH_BLASTS * Boss.DEATH_STEP + 0.4
	).timeout
	_check(not is_instance_valid(ship), "the wreck frees itself after the cascade")

	# S13: the last detonation is sized to the hull, not to a fighter. The final
	# blast is the one that outlives the wreck at the ship's own scale.
	var biggest: float = 0.0
	for blast in _death_blasts():
		biggest = maxf(biggest, blast.scale_multiplier)
	_check(
		biggest >= Boss.FINAL_SCALE,
		"the final explosion is scaled to the hull (%.1f)" % biggest
	)

	_player.set("_invulnerable", 0.0)

	GlobalEventBus.boss_appeared.disconnect(on_appeared)
	GlobalEventBus.boss_health_changed.disconnect(on_health)
	GlobalEventBus.boss_defeated.disconnect(on_defeated)

	for blast in _death_blasts():
		blast.queue_free()
	await get_tree().physics_frame


## The turret's two halves are pinned here -- it engages on its own and it holds
## its ring -- and neither depends on what the arena streamed. The test spawns the
## turret itself: the planet streams interceptors now, and the stream is parked
## after `_test_planet_roster`.
func _test_enemy_patterns() -> void:
	_clear_enemies()
	await get_tree().physics_frame
	_player.velocity = Vector3.ZERO

	var contact: Enemy = _spawn_turret(_player.global_position + Vector3(30.0, 0.0, 0.0))
	_check(contact != null, "a contact is on the field for the pattern check")
	if contact == null:
		return

	var saw_enemy_bullets: bool = false
	for _i in 300:
		await get_tree().physics_frame
		if _count_projectiles(Projectile.Team.ENEMY) > 0:
			saw_enemy_bullets = true
			break

	_check(saw_enemy_bullets, "enemy emits a bullet pattern within 5 s")

	if is_instance_valid(contact):
		var distance: float = _flat_distance(
			contact.global_position, _player.global_position
		)
		_check(
			absf(distance - Turret.ORBIT_RADIUS) < 8.0,
			"the engaged turret holds the ring radius (%.1f units)" % distance
		)

	_clear_enemies()
	await get_tree().physics_frame


## The turret is a city enemy: the planet streams interceptors, and an interceptor
## chases by design. What is pinned here is the turret's own rule -- it patrols
## instead of following the ship, so travelling past it changes nothing -- because
## the district still spawns them. The test spawns one instead of taking whatever
## the arena happened to stream.
func _test_turret_roams_on_its_own() -> void:
	_clear_enemies()
	await get_tree().physics_frame
	_player.velocity = Vector3.ZERO

	var enemy: Enemy = _spawn_turret(_player.global_position + Vector3(30.0, 0.0, 0.0))
	if enemy == null:
		_check(false, "a turret is available for the roaming check")
		return

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
		"the turret roams on its own (%.1f units in 1.5 s)" % roamed
	)

	_clear_enemies()
	await get_tree().physics_frame


## The launcher is a new threat, not a new rule set: it has to be a real enemy, so
## the radar, the bomb and the player's own missiles all still see it, and its
## attack has to be a guided missile, because that is the thing the decoy answers.
func _test_missile_enemy() -> void:
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	var enemy: MissileEnemy = _spawn_missile_enemy(Vector3(18.0, 0.0, 0.0))
	_check(enemy != null, "the missile launcher spawns")
	if enemy == null:
		return
	_check(enemy.is_in_group(&"enemy"), "the launcher is a target like any other")
	_check(
		enemy.current_hp() == MissileEnemy.LAUNCHER_HP,
		"the launcher carries its own hull (%d hp)" % enemy.current_hp()
	)

	# The approach, the warning and the launch are the attack: wait for the first
	# missile instead of calling the fire function behind the state machine.
	var missile: Projectile = null
	for _i in 240:
		await get_tree().physics_frame
		for child in get_tree().current_scene.get_children():
			var shot: Projectile = child as Projectile
			if shot == null or shot.is_queued_for_deletion():
				continue
			if int(shot.get("_team")) != Projectile.Team.ENEMY:
				continue
			if int(shot.get("_style")) != Projectile.Style.MISSILE:
				continue
			missile = shot
			break
		if missile != null:
			break

	_check(missile != null, "the launcher fires a missile")
	if missile != null:
		_check(bool(missile.call("is_homing")), "the launcher's missile is guided")
		_check(
			missile.get("_target") == _player,
			"the launcher's missile chases the ship"
		)
		_check(
			int(missile.get("_damage")) == MissileEnemy.MISSILE_DAMAGE,
			"the launcher's missile carries its own warhead"
		)

	# Break the chase before it lands: this check is about the attack, not about
	# how much health the player has left at this point in the suite.
	_player.global_position = Vector3(0.0, 0.0, 120.0)
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame


## Every hostile salvo has to out-run the ship's level-1 escape routes, not just the
## hover: the player's own missile (42) and the burner (42). A straight line no
## longer shakes a salvo, so the counterplay is the turn, the dash, the decoy, the
## cloud and the transform. The ceiling matters as much as the floor -- both stay
## under FIGHTER cruise (48.2), so the next clean out still exists. The mothership
## keeps the launcher's number on purpose: which hull fired must not change the answer.
func _test_enemy_missile_pacing() -> void:
	var slowest: float = minf(MissileEnemy.MISSILE_SPEED, FighterEnemy.MISSILE_SPEED)
	var fastest: float = maxf(MissileEnemy.MISSILE_SPEED, FighterEnemy.MISSILE_SPEED)

	_check(
		MissileEnemy.MISSILE_SPEED > Player.BOOST_SPEED,
		"the launcher's salvo outruns the level-1 burner (%.0f > %.0f)"
		% [MissileEnemy.MISSILE_SPEED, Player.BOOST_SPEED]
	)
	_check(
		FighterEnemy.MISSILE_SPEED > Player.BOOST_SPEED,
		"the interceptor's salvo outruns the level-1 burner (%.0f > %.0f)"
		% [FighterEnemy.MISSILE_SPEED, Player.BOOST_SPEED]
	)
	_check(
		slowest > Arsenal.MISSILE_SPEED,
		"both salvos outrun the player's own missile (%.0f/%.0f > %.0f)"
		% [MissileEnemy.MISSILE_SPEED, FighterEnemy.MISSILE_SPEED, Arsenal.MISSILE_SPEED]
	)
	_check(
		is_equal_approx(Boss.BOSS_MISSILE_SPEED, MissileEnemy.MISSILE_SPEED),
		"the mothership fires the launcher's salvo (%.0f)" % Boss.BOSS_MISSILE_SPEED
	)
	_check(
		fastest < Player.FIGHTER_SPEED,
		"FIGHTER cruise still leaves a salvo behind (%.0f < %.0f)"
		% [fastest, Player.FIGHTER_SPEED]
	)


## The interceptor is a new flight model, not a new identity: it has to be an
## `Enemy` so the radar, the bomb and the player's missiles still see it, and it
## has to fly like the player's own fighter without ever becoming one. That is what
## this checks -- the airframe, the ceiling, the fact that it never poses into
## GERWALK, and a guided salvo that leaves the wings.
func _test_fighter_enemy() -> void:
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	var enemy: FighterEnemy = _spawn_fighter_enemy(Vector3(55.0, 0.0, 0.0))
	_check(enemy != null, "the interceptor spawns")
	if enemy == null:
		return
	_check(enemy.is_in_group(&"enemy"), "the interceptor is a target like any other")
	_check(
		enemy.current_hp() == FighterEnemy.FIGHTER_HP,
		"the interceptor carries its own hull (%d hp)" % enemy.current_hp()
	)

	var model: PlayerModel = enemy.get("_model") as PlayerModel
	_check(model != null, "the interceptor flies the player's airframe")

	# It accelerates into its ceiling and holds it. The ceiling is the brief's
	# medium speed, so this is also the check that it cannot reach the burner.
	var top: float = 0.0
	for _i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			break
		top = maxf(top, enemy.velocity.length())
	_check(
		top > FighterEnemy.FLOOR_SPEED + 1.0,
		"the interceptor accelerates off the patrol floor (%.1f u/s)" % top
	)
	_check(
		top <= FighterEnemy.TOP_SPEED + 0.5,
		"the interceptor never passes the medium ceiling (%.1f u/s)" % top
	)
	if model != null:
		_check(
			is_zero_approx(float(model.get("_last_gerwalk"))),
			"the interceptor never poses into GERWALK"
		)

	# The attack is the salvo, so wait for the state machine to commit instead of
	# calling the fire function behind its back.
	var salvo: Array[Projectile] = []
	for _i in 360:
		await get_tree().physics_frame
		for child in get_tree().current_scene.get_children():
			var shot: Projectile = child as Projectile
			if shot == null or shot.is_queued_for_deletion():
				continue
			if int(shot.get("_team")) != Projectile.Team.ENEMY:
				continue
			if int(shot.get("_style")) != Projectile.Style.MISSILE:
				continue
			salvo.append(shot)
		if not salvo.is_empty():
			break

	var missile: Projectile = null if salvo.is_empty() else salvo[0]
	_check(missile != null, "the interceptor launches a missile")
	if missile != null:
		_check(bool(missile.call("is_homing")), "the interceptor's missile is guided")
		_check(
			missile.get("_target") == _player,
			"the interceptor's missile chases the ship"
		)
		_check(
			int(missile.get("_damage")) == FighterEnemy.MISSILE_DAMAGE,
			"the interceptor's missile carries its own warhead"
		)
		# The interceptor's salvo is the player's salvo in hostile paint: same
		# weave, same tuning. Two paths would drift apart on the first tweak.
		_check(
			is_equal_approx(
				float(missile.get("_weave_amplitude")),
				Arsenal.MISSILE_WEAVE_AMPLITUDE
			),
			"the interceptor's missile weaves like the player's (%.2f)"
			% float(missile.get("_weave_amplitude"))
		)
		_check(
			is_equal_approx(float(missile.get("_weave_rate")), Arsenal.MISSILE_WEAVE_RATE),
			"the interceptor uses the player's weave rate, not a second tuning"
		)
		_check(
			float(missile.get("_turn_rate")) >= Arsenal.MISSILE_TURN_RATE - 0.001,
			"the interceptor's missile is agile enough for the weave (%.1f rad/s)"
			% float(missile.get("_turn_rate"))
		)
		var phases: Array[int] = []
		for shot in salvo:
			phases.append(int(round(float(shot.get("_weave_phase")) * 10.0)))
		_check(
			_unique_count(phases) == salvo.size(),
			"the pair braids instead of weaving in step (%s)" % [str(phases)]
		)

	# Break the chase before it lands: this check is about the attack, not about
	# how much health the player has left at this point in the suite.
	_player.global_position = Vector3(0.0, 0.0, 160.0)
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame



## The blast is the game's word for "a hull came apart", so every enemy speaks it
## too. The three kinds share the one death path in `Enemy`, and this drives each
## of them through it: the hull disappears, one blast appears where the enemy was,
## the kill still reaches the arena, and the enemy frees itself.
func _test_enemy_death_blast() -> void:
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	var kinds: Array[String] = ["turret", "launcher", "interceptor"]
	var enemies: Array[Enemy] = [
		_spawn_turret(Vector3(22.0, 0.0, 0.0)),
		_spawn_missile_enemy(Vector3(0.0, 0.0, 22.0)),
		_spawn_fighter_enemy(Vector3(-22.0, 0.0, 0.0)),
	]

	for index in enemies.size():
		var enemy: Enemy = enemies[index]
		var kind: String = kinds[index]
		if enemy == null:
			_check(false, "the %s spawns for the death check" % kind)
			continue

		var died_at: Vector3 = enemy.global_position
		var kills: Array[int] = [0]
		enemy.killed.connect(func() -> void: kills[0] += 1)

		enemy.take_damage(enemy.current_hp())

		_check(kills[0] == 1, "the %s reports exactly one kill" % kind)
		var hull: Node3D = enemy.get("_visual") as Node3D
		_check(
			hull != null and not hull.visible,
			"the %s hides its hull on the death frame" % kind
		)
		_check(
			enemy.is_queued_for_deletion(),
			"the %s frees itself after the blast" % kind
		)

		await get_tree().physics_frame

		# Matched by where the enemy died instead of by count: a blast from the
		# previous kind may still be leaving the tree on this frame.
		var blasts_at_death: int = 0
		var blast: ShipExplosion = null
		for candidate in _death_blasts():
			if candidate.global_position.distance_to(died_at) < 0.01:
				blasts_at_death += 1
				blast = candidate
		_check(
			blasts_at_death == 1,
			"the %s leaves one death blast (%d)" % [kind, blasts_at_death]
		)
		if blast != null:
			_check(
				is_equal_approx(blast.shake_strength, Enemy.DEATH_SHAKE),
				"the %s blast kicks the camera less than the ship's" % kind
			)
			_check(
				_wave_of(blast) != null,
				"the %s death leaves its shockwave" % kind
			)
			blast.queue_free()

	await get_tree().physics_frame


## A missile is a detonation, not a hit: its impact has to leave the shockwave, and
## the gunpod has to keep its spark. The blast is a world node that outlives the
## shot, so it is counted in the scene root the way the death blast is.
func _test_missile_impact_blast() -> void:
	_clear_projectiles()
	_clear_enemies()
	# Any effect still leaving an earlier test is cleared first: this check is about
	# the one impact it produces, not about the leftovers of the previous one.
	for spark in _hit_sparks():
		spark.queue_free()
	for blast in _impact_waves():
		blast.queue_free()
	# The wall sits away from the ship so the missile cannot meet the player on the
	# way in and the check stays about the impact.
	_player.global_position = Vector3(0.0, 0.0, 90.0)
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame

	# The wall is a body of the same kind the enemies are: the projectile's Area3D
	# detects a CharacterBody3D, and the check has to exercise the same pairing the
	# gun does in the fight. It carries both the player and the enemy layers so the
	# enemy missile and the player's dart can each meet it, exactly as they would
	# meet a real hull.
	var wall: CharacterBody3D = CharacterBody3D.new()
	wall.collision_layer = (
		(1 << Projectile.LAYER_PLAYER) | (1 << Projectile.LAYER_ENEMY)
	)
	wall.collision_mask = 0
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 6.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	wall.add_child(shape)
	get_tree().current_scene.add_child(wall)
	wall.global_position = Vector3(0.0, 0.0, -18.0)
	await get_tree().physics_frame

	var missile: Projectile = _spawn_enemy_missile(Vector3.ZERO, wall)
	for _i in 90:
		await get_tree().physics_frame
		if not is_instance_valid(missile):
			break

	var blasts: Array[ShockWave] = _impact_waves()
	_check(
		blasts.size() == 1,
		"a missile impact leaves one shockwave (%d)" % blasts.size()
	)
	if blasts.size() == 1:
		_check(
			blasts[0].global_position.distance_to(Vector3(0.0, 0.0, -15.0)) < 2.0,
			"the shockwave opens where the missile met the hull"
		)
	_check(
		_hit_sparks().is_empty(),
		"the missile impact replaces the bullet spark"
	)

	await get_tree().create_timer(ShockWave.RING_TIME + 0.2).timeout
	_check(_impact_waves().is_empty(), "the shockwave frees itself")

	# The same wall, hit by the gunpod, must keep the old spark: the wave belongs to
	# the missile, not to every impact in the game.
	_spawn_player_bullet(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
	for _i in 90:
		await get_tree().physics_frame
		if not _hit_sparks().is_empty():
			break
	_check(
		_hit_sparks().size() == 1,
		"a bullet impact keeps its spark (%d)" % _hit_sparks().size()
	)
	_check(
		_impact_waves().is_empty(),
		"a bullet impact does not leave the missile shockwave"
	)

	wall.queue_free()
	await get_tree().physics_frame


