class_name AudioSuite
extends SmokeSuite
## The synthesized palette and the mix: the committed WAVs are measured,
## not the table's own arithmetic.

func _test_audio() -> void:
	_check(Sfx != null, "the Sfx autoload is registered")
	if Sfx == null:
		return

	# The palette is the contract: every key the game can ask for has a stream.
	var missing: Array[String] = []
	for key in Sfx.KEYS:
		if not Sfx.has(key):
			missing.append(String(key))
	_check(missing.is_empty(), "the palette loads every sound (%s)" % [str(missing)])

	# The mix is a table, not a vibe: every key has a level, and the levels keep the
	# hierarchy the game needs. The generator normalises every file to the same peak,
	# so a file's loudness is its RMS plus this table — comparing raw gains would
	# compare nothing.
	var unmixed: Array[String] = []
	for key in Sfx.KEYS:
		if not Sfx.GAIN_DB.has(key):
			unmixed.append(String(key))
	_check(unmixed.is_empty(), "every sound has a level in the mix (%s)" % [str(unmixed)])

	var levels: Dictionary = {}
	for key in Sfx.KEYS:
		if key == &"engine_loop":
			# The hum has its own level envelope; comparing it here would call the
			# idle engine the loudest sound in the game.
			continue
		levels[key] = _rms_db("res://audio/sfx/%s.wav" % key) + Sfx.gain(key)
	_check(
		float(levels[&"ui_select"]) < float(levels[&"vulcan"]),
		"the interface sits under the weapons (%.1f vs %.1f dB)"
		% [float(levels[&"ui_select"]), float(levels[&"vulcan"])]
	)
	_check(
		float(levels[&"ui_select"]) < float(levels[&"vulcan"]) - 6.0,
		"the interface sits at least 6 dB under the gun"
	)
	_check(
		float(levels[&"vulcan"]) < float(levels[&"explosion"]),
		"the blast is louder than the gun (%.1f vs %.1f dB)"
		% [float(levels[&"explosion"]), float(levels[&"vulcan"])]
	)
	_check(
		float(levels[&"bomb"]) >= float(levels[&"explosion"]),
		"the bomb is not quieter than an ordinary blast (%.1f vs %.1f dB)"
		% [float(levels[&"bomb"]), float(levels[&"explosion"])]
	)
	_check(
		float(levels[&"missile_warning"]) > float(levels[&"explosion"]),
		"the alarm cuts through the blasts (%.1f vs %.1f dB)"
		% [float(levels[&"missile_warning"]), float(levels[&"explosion"])]
	)

	# The room is part of the palette: a dry bus reads as a folder of samples.
	var sfx_bus: int = AudioServer.get_bus_index(&"SFX")
	_check(
		sfx_bus >= 0 and AudioServer.get_bus_effect_count(sfx_bus) >= 1,
		"the SFX bus carries the room"
	)

	# Positional audio has to cover the fight, not only the ship. Enemies spawn at
	# 85-110 units and despawn at 190, so a reach shorter than the despawn ring makes
	# an edge kill happen in silence; and an explosion that falls off with distance
	# is buried under the engine exactly where most kills land.
	_check(
		Sfx.SPATIAL_REACH >= Arena.DESPAWN_DISTANCE,
		"positional sounds outlive the enemy despawn (%.0f vs %.0f)"
		% [Sfx.SPATIAL_REACH, Arena.DESPAWN_DISTANCE]
	)
	_check(
		Sfx.SPATIAL_FLAT.has(&"explosion"),
		"a kill keeps its level across the arena instead of fading into the engine"
	)

	# A repeated shot must not be the same sample twelve times a second. The jitter is
	# deterministic, so this sequence is the same on every run instead of a coin flip.
	Sfx.reset_counts()
	var shots: Array[float] = []
	for _i in 8:
		Sfx.play(&"vulcan")
		shots.append(Sfx.pitch(&"vulcan"))
	_check(
		_unique_count(shots) >= 5,
		"the gunpod varies its pitch between shots (%d of 8 distinct)"
		% _unique_count(shots)
	)
	var in_band: bool = true
	for value in shots:
		if value < 0.95 or value > 1.05:
			in_band = false
	_check(in_band, "the jitter stays inside its band (%s)" % [str(shots)])

	# An explosion has to be heard on a laptop speaker, not only felt on a sub. The
	# blasts carry the kill, so most of their energy must live in the bright band
	# instead of under 300 Hz where a small speaker reproduces nothing.
	for blast: String in ["explosion", "player_death"]:
		var bright: float = _high_band_energy("res://audio/sfx/%s.wav" % blast, 1000.0)
		_check(
			bright >= 0.30,
			"the %s blast is audible on small speakers (%.1f%% above 1 kHz)"
			% [blast, bright * 100.0]
		)

	# The hum follows the hull: the ship is alive here, so it must be running.
	_check(Sfx.engine_active(), "the hover engine hums while the ship is alive")

	var weapons: WeaponSystem = _player.get("_weapons") as WeaponSystem
	_check(weapons != null, "the player exposes its weapons for the audio check")
	if weapons == null:
		return

	var origin: Vector3 = _player.global_position
	var aim: Vector3 = _aim()

	# Gunpod: one burst per shot, never one per pellet.
	weapons.select(Arsenal.Kind.VULCAN)
	weapons.primary().set_cooldown(0.0)
	Sfx.reset_counts()
	weapons.tick(0.0, origin, origin, aim, true)
	_check(
		Sfx.played(&"vulcan") == 1,
		"the gunpod asks for one burst sound per shot (got %d)" % Sfx.played(&"vulcan")
	)
	_clear_projectiles()

	# Plasma: one zap per bolt.
	weapons.select(Arsenal.Kind.PLASMA)
	weapons.primary().set_cooldown(0.0)
	Sfx.reset_counts()
	weapons.tick(0.0, origin, origin, aim, true)
	_check(Sfx.played(&"plasma") == 1, "the plasma bolt asks for its zap")
	_clear_projectiles()

	# The beam is continuous: the trigger pull ignites it once, and a second pull
	# ignites it again. A zap per frame would be a machine-gun of hiss.
	weapons.select(Arsenal.Kind.LASER)
	Sfx.reset_counts()
	for _i in 3:
		weapons.tick(0.016, origin, origin, aim, true)
	_check(
		Sfx.played(&"laser") == 1,
		"the beam ignites once per trigger pull (got %d)" % Sfx.played(&"laser")
	)
	weapons.tick(0.016, origin, origin, aim, false)
	Sfx.reset_counts()
	weapons.tick(0.016, origin, origin, aim, true)
	_check(Sfx.played(&"laser") == 1, "releasing and pulling again re-ignites the beam")

	# The salvo: one whoosh per missile, so a pair reads as a sequence.
	_clear_enemies()
	await get_tree().physics_frame
	var target: Enemy = _spawn_enemy(origin + aim * 20.0)
	if target != null:
		weapons.radar().set_loaded(2)
		weapons.radar().set_cooldown(0.0)
		Sfx.reset_counts()
		weapons.tick(0.0, origin, origin, aim, false, false, false)
		_check(
			Sfx.played(&"missile_launch") == 2,
			"the salvo asks for one launch sound per missile (got %d)"
			% Sfx.played(&"missile_launch")
		)
	_clear_projectiles()

	# The lock: a new contact stings once, and a contact already held is silent.
	_clear_enemies()
	await get_tree().physics_frame
	var contact: Enemy = _spawn_enemy(origin + aim * 20.0)
	if contact != null:
		# The salvo above left the rack on cooldown, and a cooling rack never marks.
		weapons.radar().set_cooldown(0.0)
		Sfx.reset_counts()
		# The tone belongs to the first missile, not to the contact: an empty rack
		# marks nothing, so the hold has to load one before anything rings.
		weapons.tick(
			Arsenal.MISSILE_SALVO_INTERVAL, origin, origin, aim, false, false, true
		)
		_check(
			Sfx.played(&"lock_tone") == 1,
			"the radar rings a new contact with one lock tone (got %d)"
			% Sfx.played(&"lock_tone")
		)
		weapons.tick(0.0, origin, origin, aim, false, false, true)
		_check(Sfx.played(&"lock_tone") == 1, "an already held contact does not re-sting")
		# Let the rack go, so the next block does not inherit a loaded salvo.
		weapons.tick(0.0, origin, origin, aim, false, false, false)
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	# Bomb and decoy are world events, and they count on the positional path too.
	weapons.set_bomb_charges(Arsenal.BOMB_MAX_CHARGES)
	Sfx.reset_counts()
	_check(weapons.fire_bomb(origin), "the bomb fires for the audio check")
	_check(Sfx.played(&"bomb") == 1, "the bomb asks for its blast")
	weapons.reset_decoy()
	Sfx.reset_counts()
	_check(weapons.drop_decoy(origin), "the decoy drops for the audio check")
	_check(Sfx.played(&"decoy") == 1, "the decoy asks for its flare")
	for node in get_tree().get_nodes_in_group(&"decoy"):
		node.queue_free()
	await get_tree().physics_frame

	# The ship itself: servo on the switch, whoosh on the dash, impact on a hit.
	var mode_before: Player.Mode = _player.mode()
	Sfx.reset_counts()
	_player.call("_start_transform")
	_check(Sfx.played(&"transform") == 1, "the switch asks for the servo sound")
	# Undo the switch: the sound is the unit under test, not the mode change.
	_player.set("_transform_time", 0.0)
	_player.set("_mode", mode_before)

	Sfx.reset_counts()
	_player.call("_start_dash")
	_check(Sfx.played(&"dash") == 1, "the dash asks for its whoosh")
	_player.set("_dash_time", 0.0)
	_player.set("_roll_anim_time", 0.0)
	_player.set("_dash_cooldown", 0.0)

	# Heal first: a run that reaches this probe on its last hull point would die to
	# it and leave the later damage test with a dead ship.
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)
	Sfx.reset_counts()
	_player.take_damage(1)
	_check(Sfx.played(&"hit") == 1, "a hit asks for the hull impact")
	_park_ship()

	# Enemy weapons speak in their own voices, positioned at the shooter.
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	var turret: Enemy = _spawn_turret(Vector3(20.0, 0.0, 0.0))
	if turret != null:
		await get_tree().physics_frame
		Sfx.reset_counts()
		turret.call("_fire_pattern")
		_check(Sfx.played(&"enemy_fire") == 1, "the turret asks for its gun report")
		var hull: int = turret.current_hp()
		Sfx.reset_counts()
		turret.take_damage(hull)
		_check(Sfx.played(&"explosion") == 1, "a dying hull asks for its explosion")
	await get_tree().physics_frame

	var launcher: MissileEnemy = _spawn_missile_enemy(Vector3(0.0, 0.0, 24.0))
	if launcher != null:
		await get_tree().physics_frame
		Sfx.reset_counts()
		launcher.call("_fire_pattern")
		_check(
			Sfx.played(&"missile_warning") == 1,
			"the launcher warns before its salvo (got %d)"
			% Sfx.played(&"missile_warning")
		)
		# The blast belongs to the base class, so every hostile has to die with it:
		# a subclass that forgot to inherit `_die` would die silently, and the suite
		# only ever killed the turret.
		var blasts_before: int = _death_blasts().size()
		Sfx.reset_counts()
		launcher.take_damage(launcher.current_hp())
		_check(
			Sfx.played(&"explosion") == 1,
			"a dying launcher asks for its explosion (got %d)"
			% Sfx.played(&"explosion")
		)
		_check(
			_death_blasts().size() == blasts_before + 1,
			"a dying launcher leaves its blast in the world"
		)
	await get_tree().physics_frame

	var interceptor: FighterEnemy = _spawn_fighter_enemy(Vector3(-26.0, 0.0, 0.0))
	if interceptor != null:
		await get_tree().physics_frame
		Sfx.reset_counts()
		interceptor.call("_fire_pattern")
		_check(
			Sfx.played(&"missile_warning") == 1,
			"the interceptor warns before its salvo (got %d)"
			% Sfx.played(&"missile_warning")
		)
		Sfx.reset_counts()
		var blasts_before: int = _death_blasts().size()
		interceptor.take_damage(interceptor.current_hp())
		_check(
			Sfx.played(&"explosion") == 1,
			"a dying interceptor asks for its explosion (got %d)"
			% Sfx.played(&"explosion")
		)
		_check(
			_death_blasts().size() == blasts_before + 1,
			"a dying interceptor leaves its blast in the world"
		)

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	# The turret's wreck is a world node that outlives it. It is cleared here so the
	# death test later finds only the blast its own ship produced.
	for blast in _death_blasts():
		blast.queue_free()
	await get_tree().physics_frame


