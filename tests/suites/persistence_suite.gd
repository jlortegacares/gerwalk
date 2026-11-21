class_name PersistenceSuite
extends SmokeSuite
## The six save cards and the pilot record: paths, migration, level
## derivation, reset.

## A save card is a pilot: the kills, the level derived from them, the scenario
## they flew last and when. The suite runs on scratch cards, so it can create,
## erase and migrate them freely.
func _test_save_slots() -> void:
	_check(SaveSlots.SLOT_COUNT == 6, "a memory card holds six pilots")

	SaveSlots.configure(TEST_SAVES, TEST_LEGACY)
	_clean_saves()
	SaveSlots.ensure(TEST_SETTINGS)
	_check(SaveSlots.active_slot(TEST_SETTINGS) == 1, "a fresh card is on slot 1")
	_check(not SaveSlots.summary(1)["occupied"], "a fresh card has no save")

	SaveSlots.select(2, TEST_SETTINGS)
	_check(SaveSlots.active_slot(TEST_SETTINGS) == 2, "picking a card makes it active")
	_check(
		GameProgress.instance().path == SaveSlots.path_for(2),
		"the record follows the card"
	)

	GameProgress.instance().total_kills = 40
	GameProgress.instance().remember_scenario(ARENA_SCENE)
	var slot2: Dictionary = SaveSlots.summary(2)
	_check(slot2["occupied"], "a flown card holds a save")
	_check(int(slot2["kills"]) == 40, "the card records the kills")
	_check(
		int(slot2["level"]) == GameProgress.level_for_kills(40),
		"the card derives the level"
	)
	_check(String(slot2["scenario"]) == ARENA_SCENE, "the card records the scenario")
	_check(int(slot2["played"]) > 0, "the card records when it was last flown")
	_check(not SaveSlots.summary(1)["occupied"], "the other cards stay empty")

	SaveSlots.select(1, TEST_SETTINGS)
	_check(GameProgress.instance().total_kills == 0, "another card starts at level 1")
	SaveSlots.select(2, TEST_SETTINGS)
	_check(GameProgress.instance().total_kills == 40, "coming back keeps the kills")

	SaveSlots.erase(2)
	_check(
		not FileAccess.file_exists(SaveSlots.path_for(2)),
		"deleting a card removes its file"
	)
	_check(not SaveSlots.summary(2)["occupied"], "and the card reads empty")
	_check(
		GameProgress.instance().total_kills == 0,
		"deleting the active card resets the pilot"
	)

	# The old single save lands on card 1 exactly once, and the original is renamed
	# so a later launch can neither import it twice nor resurrect an erased card.
	_clean_saves()
	SaveSlots.select(1, TEST_SETTINGS)
	GameProgress.instance().total_kills = 55
	GameProgress.instance().remember_scenario(City.SCENE_PATH)
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(SaveSlots.path_for(1)),
		ProjectSettings.globalize_path(TEST_LEGACY)
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSlots.path_for(1)))
	SaveSlots.ensure(TEST_SETTINGS)
	_check(int(SaveSlots.summary(1)["kills"]) == 55, "the old single save lands on card 1")
	_check(
		FileAccess.file_exists("%s.imported" % TEST_LEGACY),
		"the old save is kept as a backup"
	)
	_check(not FileAccess.file_exists(TEST_LEGACY), "and it is not left to be imported twice")
	GameProgress.instance().total_kills = 5
	GameProgress.instance().write_to_disk()
	SaveSlots.ensure(TEST_SETTINGS)
	_check(int(SaveSlots.summary(1)["kills"]) == 5, "a second launch does not import again")

	# A pointer outside the card range must not leave the game on a file nobody
	# can see.
	var config: ConfigFile = ConfigFile.new()
	config.load(TEST_SETTINGS)
	config.set_value(SaveSlots.SECTION, SaveSlots.ACTIVE_KEY, 99)
	config.save(TEST_SETTINGS)
	_check(
		SaveSlots.active_slot(TEST_SETTINGS) == SaveSlots.SLOT_COUNT,
		"an out of range card is clamped"
	)

	_clean_saves()
	SaveSlots.select(1, TEST_SETTINGS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))


## The pilot record is the one piece of state that survives a session, so it is
## tested as a model: the curve, the two save fields, the corrupt-file fallback and
## the kill hook. The suite ends this check on level 1 again, because every later
## speed, HP and turbo assertion was written against the base constants.
func _test_pilot_progression() -> void:
	_check(GameProgress.kills_for_level(1) == 0, "level 1 starts at zero kills")
	_check(GameProgress.kills_for_level(100) == 496, "level 100 is 496 kills")

	var monotonic: bool = true
	for level in range(2, GameProgress.MAX_LEVEL + 1):
		if GameProgress.kills_for_level(level) < GameProgress.kills_for_level(level - 1):
			monotonic = false
	_check(monotonic, "no level costs fewer kills than the one before it")

	# The ceiling can make two levels share a threshold, so the inverse is "the
	# threshold reaches at least this level, and one kill short does not".
	for level in [2, 10, 50, 99, 100]:
		var threshold: int = GameProgress.kills_for_level(level)
		_check(
			GameProgress.level_for_kills(threshold) >= level,
			"the curve reaches level %d at its own threshold" % level
		)
		_check(
			GameProgress.level_for_kills(threshold - 1) < level,
			"one kill short of level %d is a lower level" % level
		)
	_check(GameProgress.level_for_kills(0) == 1, "zero kills is level 1")
	_check(GameProgress.level_for_kills(10000) == 100, "the level caps at 100")

	var base: PilotStats = PilotStats.new(1)
	_check(is_equal_approx(base.speed_multiplier(), 1.0), "level 1 adds no speed")
	_check(base.max_hp(Player.MAX_HP) == Player.MAX_HP, "level 1 adds no HP")
	_check(is_equal_approx(base.turbo_capacity_multiplier(), 1.0), "level 1 adds no turbo")
	_check(is_equal_approx(base.primary_interval_multiplier(), 1.0), "level 1 adds no rate")

	var maxed: PilotStats = PilotStats.new(100)
	_check(is_equal_approx(maxed.speed_multiplier(), 1.2), "level 100 is +20% speed")
	_check(maxed.max_hp(Player.MAX_HP) == Player.MAX_HP + 8, "level 100 is +8 HP")
	_check(is_equal_approx(maxed.turbo_capacity_multiplier(), 1.8), "level 100 is +80% turbo")
	_check(is_equal_approx(maxed.turbo_recharge_multiplier(), 1.6), "level 100 is +60% recharge")
	_check(is_equal_approx(maxed.primary_interval_multiplier(), 0.85), "level 100 is -15% interval")
	_check(is_equal_approx(maxed.vulcan_spread_multiplier(), 0.8), "level 100 is -20% spread")
	_check(is_equal_approx(maxed.plasma_cone_multiplier(), 1.2), "level 100 is +20% lock cone")
	_check(is_equal_approx(maxed.laser_range_multiplier(), 1.2), "level 100 is +20% laser range")
	_check(
		Player.MAX_SPEED * maxed.speed_multiplier() < 34.0,
		"a maxed GERWALK still cannot outrun an interceptor"
	)

	# Kills, the scenario and its date are stored; the level comes back derived.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROGRESS))
	GameProgress.use_path(TEST_PROGRESS)
	var record: GameProgress = GameProgress.instance()
	record.total_kills = 37
	record.remember_scenario(City.SCENE_PATH)
	GameProgress.use_path(TEST_PROGRESS)
	var reloaded: GameProgress = GameProgress.instance()
	_check(reloaded.total_kills == 37, "the kill count survives a reload")
	_check(reloaded.last_scenario == City.SCENE_PATH, "the last scenario survives a reload")
	_check(reloaded.last_played > 0, "the last flight is dated")
	_check(
		reloaded.level() == GameProgress.level_for_kills(37),
		"the level is derived from the count, not stored"
	)
	var config: ConfigFile = ConfigFile.new()
	_check(config.load(TEST_PROGRESS) == OK, "the progress file is a config file")
	_check(
		int(config.get_value(GameProgress.SECTION, GameProgress.VERSION_KEY, 0))
		== GameProgress.VERSION,
		"the save carries its version"
	)

	# A corrupt file is a new pilot, and it is left on disk for inspection.
	var broken: FileAccess = FileAccess.open(TEST_PROGRESS, FileAccess.WRITE)
	if broken != null:
		broken.store_string("this is not a config file")
		broken.close()
	GameProgress.use_path(TEST_PROGRESS)
	var recovered: GameProgress = GameProgress.instance()
	_check(recovered.total_kills == 0, "a corrupt save falls back to level 1")
	_check(recovered.last_scenario.is_empty(), "a corrupt save has no scenario")
	_check(FileAccess.file_exists(TEST_PROGRESS), "the corrupt file is kept for inspection")

	# One enemy, one kill on the record, one event on the bus. The planet's own
	# population is left alone: the arena spawns its opening interceptor before this
	# test runs, and the streaming spawner is what later tests expect to find.
	GameProgress.use_path(TEST_PROGRESS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROGRESS))
	var events: Array[int] = []
	var listener: Callable = func(
		total: int, _level: int, _into: int, _next: int
	) -> void: events.append(total)
	GlobalEventBus.pilot_progress_changed.connect(listener)

	var turret: Enemy = _spawn_turret(Vector3(18.0, 0.0, 0.0))
	await get_tree().physics_frame
	if turret != null:
		turret.take_damage(turret.current_hp())
	_check(GameProgress.instance().total_kills == 1, "an enemy kill reaches the pilot record")
	_check(
		not events.is_empty() and events[events.size() - 1] == 1,
		"the kill reaches the HUD through the bus"
	)
	GlobalEventBus.pilot_progress_changed.disconnect(listener)

	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var level_label: Label = hud.get_node("%LevelLabel") as Label
	_check(
		level_label != null and level_label.text.begins_with("PILOT LV 2"),
		"the HUD shows the level a kill earned (%s)" % (level_label.text if level_label else "")
	)

	# Stats are captured when the run starts, so the same method the player calls
	# in `_ready` is what proves the caps reach the ship and the guns.
	GameProgress.instance().total_kills = 496
	_player._apply_pilot_stats()
	_check(
		is_equal_approx(float(_player.get("_max_speed")), Player.MAX_SPEED * 1.2),
		"a maxed pilot starts faster"
	)
	_check(int(_player.get("_max_hp")) == Player.MAX_HP + 8, "a maxed pilot starts tougher")
	_check(
		is_equal_approx(float(_player.get("_turbo_max")), Player.TURBO_MAX * 1.8),
		"a maxed pilot starts with a bigger tank"
	)
	_check(_player._weapons._stats.level == 100, "the weapons take the pilot's level too")

	# Back to the baseline every later assertion assumes.
	GameProgress.instance().reset()
	_player._apply_pilot_stats()
	_check(int(_player.get("_max_hp")) == Player.MAX_HP, "the suite returns to level 1")


