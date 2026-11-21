extends SmokeSuite
## Headless smoke test for the 3D combat prototype.
## Run: ./run.sh --headless tests/smoke_test.tscn
## Exits with code 1 if any assertion fails.
##
## This file is the runner only: it boots the one world the run shares, installs
## the domain suites, and drives them in the order the run depends on. The
## assertions live in `tests/suites/`; the harness they use is `smoke_suite.gd`.

var _render: RenderSuite = null
var _ui: UiSuite = null
var _persistence: PersistenceSuite = null
var _movement: MovementSuite = null
var _weapons: WeaponsSuite = null
var _enemies: EnemiesSuite = null
var _world: WorldSuite = null
var _audio: AudioSuite = null


func _ready() -> void:
	# The suite drives the pause menu, which stops the tree, so the suite itself has
	# to keep running while the world it tests is frozen. The arena is pinned back to
	# PAUSABLE below: an always-on suite must not make the world always-on with it.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The arena reads and writes the pilot record in its own `_ready`, so the
	# scratch card is installed before the scene enters the tree.
	SaveSlots.configure(TEST_SAVES, TEST_LEGACY)
	_clean_saves()
	SaveSlots.ensure(TEST_SETTINGS)

	super._ready()

	_arena = load(ARENA_SCENE).instantiate()
	# PAUSABLE is the absolute "stop when the tree stops" mode, so the world really
	# freezes even though its parent is always-on.
	_arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_arena)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_player = _arena.get_node("%Player")
	_check(_player != null, "arena exposes a Player")
	_check(_player is CharacterBody3D, "player is a CharacterBody3D")

	# The suite is one very long run that kills far more than the boss threshold,
	# so the run counter is parked below zero and only the boss test drives it up.
	# Without this the mothership would arrive mid-weapon-test and suppress the
	# stream every later test depends on.
	_arena.set("_run_kills", -1000)

	# One suite per domain, installed once and reused: the world is
	# mutable and shared, so a suite is a lens on the same run, not a
	# fresh boot.
	_render = preload("res://tests/suites/render_suite.gd").new() as RenderSuite
	_install_suite(_render)
	_ui = preload("res://tests/suites/ui_suite.gd").new() as UiSuite
	_install_suite(_ui)
	_persistence = preload("res://tests/suites/persistence_suite.gd").new() as PersistenceSuite
	_install_suite(_persistence)
	_movement = preload("res://tests/suites/movement_suite.gd").new() as MovementSuite
	_install_suite(_movement)
	_weapons = preload("res://tests/suites/weapons_suite.gd").new() as WeaponsSuite
	_install_suite(_weapons)
	_enemies = preload("res://tests/suites/enemies_suite.gd").new() as EnemiesSuite
	_install_suite(_enemies)
	_world = preload("res://tests/suites/world_suite.gd").new() as WorldSuite
	_install_suite(_world)
	_audio = preload("res://tests/suites/audio_suite.gd").new() as AudioSuite
	_install_suite(_audio)


	_movement._test_player_is_centered()
	await _world._test_planet_roster()
	await _persistence._test_pilot_progression()
	_persistence._test_save_slots()
	_render._test_render_scale()
	await _ui._test_main_menu()
	await _ui._test_pad_bindings()
	await _ui._test_livery_paint()
	await _movement._test_movement()
	await _weapons._test_firing()
	await _enemies._test_enemy_patterns()
	await _enemies._test_turret_roams_on_its_own()
	await _enemies._test_missile_enemy()
	_enemies._test_enemy_missile_pacing()
	await _world._test_clouds()
	await _enemies._test_fighter_enemy()
	await _enemies._test_enemy_death_blast()
	await _enemies._test_missile_impact_blast()
	await _movement._test_afterburner()
	await _movement._test_exhaust_trail()
	_movement._test_airframe_lighting()
	await _ui._test_radar()
	await _weapons._test_arsenal()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _movement._test_travel_is_unbounded()
	await _movement._test_planet_rolls_with_the_player()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _movement._test_maneuverability()
	await _movement._test_double_tap_dash()
	await _movement._test_transformation()
	await _movement._test_gerwalk_silhouette()
	await _audio._test_audio()
	await _ui._test_hud_layout()
	await _ui._test_pause_menu()
	await _ui._test_score()
	await _enemies._test_boss()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _movement._test_dash_evasion()
	await _movement._test_damage_and_iframes()
	await _movement._test_death()

	await _world._test_city_scene()

	# The scratch record is cleared too: a suite run must not leave a save behind
	# that the next run, or a real player, could read as progress.
	GameProgress.instance().reset()

	_report()



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
