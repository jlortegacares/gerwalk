extends Node
## Headless smoke test for the 3D combat prototype.
## Run: ./run.sh --headless tests/smoke_test.tscn
## Exits with code 1 if any assertion fails.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
## Every settings round trip uses this file, never the real `user://settings.cfg`:
## a test must not overwrite the choices of whoever runs it.
const TEST_SETTINGS: String = "user://test-settings.cfg"
## The same rule for the pilot record: the suite runs at level 1 and must never
## earn (or erase) levels on the machine that runs it.
const TEST_PROGRESS: String = "user://test-progress.cfg"
## And for the save cards: six scratch cards under their own directory, plus a
## scratch copy of the single save the migration imports from.
const TEST_SAVES: String = "user://test-saves"
const TEST_LEGACY: String = "user://test-saves/legacy.cfg"

var _failures: Array[String] = []
var _arena: Arena = null
var _player: Player = null
var _died_count: int = 0


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

	GlobalEventBus.player_died.connect(func() -> void: _died_count += 1)

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

	_test_player_is_centered()
	await _test_planet_roster()
	await _test_pilot_progression()
	_test_save_slots()
	_test_render_scale()
	await _test_main_menu()
	await _test_pad_bindings()
	await _test_livery_paint()
	await _test_movement()
	await _test_firing()
	await _test_enemy_patterns()
	await _test_turret_roams_on_its_own()
	await _test_missile_enemy()
	await _test_clouds()
	await _test_fighter_enemy()
	await _test_enemy_death_blast()
	await _test_missile_impact_blast()
	await _test_afterburner()
	await _test_exhaust_trail()
	_test_airframe_lighting()
	await _test_radar()
	await _test_arsenal()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_travel_is_unbounded()
	await _test_planet_rolls_with_the_player()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_maneuverability()
	await _test_double_tap_dash()
	await _test_transformation()
	await _test_gerwalk_silhouette()
	await _test_audio()
	await _test_hud_layout()
	await _test_pause_menu()
	await _test_score()
	await _test_boss()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_dash_evasion()
	await _test_damage_and_iframes()
	await _test_death()

	await _test_city_scene()

	# The scratch record is cleared too: a suite run must not leave a save behind
	# that the next run, or a real player, could read as progress.
	GameProgress.instance().reset()

	_report()


## The resolution governor is arithmetic over the window size plus a state machine
## over frame times. Both are tested here: neither needs a GPU, and the state machine
## is the part that can be wrong without anything looking wrong.
func _test_render_scale() -> void:
	_check(
		RenderScale.scale_for(Vector2i(1280, 720)) == 1.0,
		"a 720p window renders at its own resolution"
	)
	_check(
		RenderScale.scale_for(Vector2i(1600, 900)) == 1.0,
		"a window at the cap is not scaled at all"
	)
	_check(
		is_equal_approx(RenderScale.scale_for(Vector2i(2560, 1440)), 1600.0 / 2560.0),
		"a 1440p window renders 1600 pixels wide"
	)
	_check(
		RenderScale.render_width_for(Vector2i(3200, 1800)) == 1600,
		"a 1800p window renders 1600 pixels wide too"
	)
	_check(
		RenderScale.render_width_for(Vector2i(3840, 2160)) == 1600,
		"a 4K window is capped at 1600 rather than left at its own size"
	)
	_check(
		RenderScale.render_width_for(Vector2i(800, 450)) == 800,
		"a window narrower than the floor is never upscaled"
	)
	_check(
		RenderScale.scale_for(Vector2i(0, 0)) == 1.0,
		"a window that has not been sized yet is not scaled"
	)
	_check(
		RenderScale.render_width_for(Vector2i(1280, 720), 0.5) == 640,
		"the softest rung renders half of a 720p window"
	)
	for factor in RenderScale.FACTORS:
		_check(
			RenderScale.render_width_for(Vector2i(1280, 720), factor)
				>= RenderScale.MIN_RENDER_WIDTH,
			"no rung goes under the floor (%.2f)" % factor
		)

	_test_render_governor()


## The governor's decision, driven by a simulated GPU rather than the real one. The
## model is a cost per pixel, so lowering a rung makes the frame faster the way it
## really does, and the vsync quantisation is applied because that is the signal the
## governor reads.
func _test_render_governor() -> void:
	var governor: Node = load("res://common/render_scale.gd").new()
	add_child(governor)
	# The real node drives itself from the frame loop; this one is driven by hand.
	governor.set_process(false)
	governor.set("enabled", true)

	_simulate(governor, 1.0, 8.0)
	_check(
		int(governor.get("_factor")) == 0,
		"a machine that holds 60 fps is left at full quality"
	)

	var hitched: Node = _fresh_governor()
	_simulate(hitched, 1.0, 10.0, 20)
	_check(
		int(hitched.get("_factor")) == 0,
		"one bad frame in twenty is not a reason to soften the image"
	)

	_simulate(governor, 4.0, 14.0)
	_check(
		int(governor.get("_factor")) > 0,
		"a machine four times slower steps down the ladder"
	)
	var settled: int = int(governor.get("_factor"))
	_check(
		is_equal_approx(governor.call("current_factor"), RenderScale.FACTORS[settled]),
		"and it sits on a rung of the ladder, not between two"
	)

	_simulate(governor, 1.0, 40.0)
	_check(
		int(governor.get("_factor")) == 0,
		"and it climbs back to full quality once the frames are cheap again"
	)

	var floored: Node = _fresh_governor()
	_simulate(floored, 40.0, 40.0)
	_check(
		int(floored.get("_factor")) == RenderScale.FACTORS.size() - 1,
		"a machine that can never keep up lands on the floor"
	)


## A governor that is not fed by anything but the test.
func _fresh_governor() -> Node:
	var governor: Node = load("res://common/render_scale.gd").new()
	add_child(governor)
	governor.set_process(false)
	governor.set("enabled", true)
	return governor


## Feeds `seconds` of a machine `times` slower than this one. `spike_every` makes
## every Nth frame four times as expensive, which is how a hitch is modelled.
func _simulate(governor: Node, times: float, seconds: float, spike_every: int = 0) -> void:
	var interval: float = 1000.0 / 60.0
	var elapsed: float = 0.0
	var frame: int = 0
	while elapsed < seconds * 1000.0:
		var width: int = RenderScale.render_width_for(
			Vector2i(1280, 720), governor.call("current_factor")
		)
		var height: int = int(float(width) * 720.0 / 1280.0)
		var work: float = 7.8 * times * (float(width * height) / (1280.0 * 720.0))
		if spike_every > 0 and frame % spike_every == spike_every - 1:
			work *= 4.0
		frame += 1
		# Vsync rounds a frame up to a whole refresh interval, and never lets it read
		# faster than one.
		var observed: float = interval * maxf(1.0, ceil(work / interval))
		governor.call("feed", observed)
		elapsed += observed


func _test_main_menu() -> void:
	var scene: PackedScene = load("res://ui/menu/main_menu.tscn")
	_check(scene != null, "the boot menu scene loads")
	if scene == null:
		return

	# The menu writes every setting it edits, so it is handed a scratch file before
	# it enters the tree: a swatch click must never touch the real settings.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	# A saved livery has to come back selected, not merely applied.
	GameSettings.save_livery(
		MainMenu.PALETTE[4],
		MainMenu.PALETTE[5],
		MainMenu.PALETTE[6],
		MainMenu.PALETTE[7],
		MainMenu.PALETTE[8],
		TEST_SETTINGS
	)

	var menu: MainMenu = scene.instantiate() as MainMenu
	menu.settings_path = TEST_SETTINGS
	add_child(menu)
	await get_tree().process_frame

	var start_button: Button = menu.get_node("%StartButton") as Button
	var city_button: Button = menu.get_node("%CityButton") as Button
	var options_button: Button = menu.get_node("%OptionsButton") as Button
	var quit_button: Button = menu.get_node("%QuitButton") as Button
	var options: Control = menu.get_node("%Options") as Control
	var back_button: Button = menu.get_node("%BackButton") as Button
	var hull_row: HBoxContainer = menu.get_node("%HullRow") as HBoxContainer
	var nose_row: HBoxContainer = menu.get_node("%NoseRow") as HBoxContainer
	var trim_row: HBoxContainer = menu.get_node("%TrimRow") as HBoxContainer
	var canopy_row: HBoxContainer = menu.get_node("%CanopyRow") as HBoxContainer
	var lines_row: HBoxContainer = menu.get_node("%LinesRow") as HBoxContainer
	var preview: LiveryPreview = menu.get_node("%Preview") as LiveryPreview
	_check(start_button != null, "the menu offers a start button")
	_check(city_button != null, "the menu offers a second scenario")
	_check(options_button != null, "the menu offers an options button")
	_check(
		quit_button != null and quit_button.text == "QUIT",
		"the menu offers a way out of the build"
	)
	_check(options != null, "the menu carries an options panel")
	_check(
		ResourceLoader.exists(MainMenu.ARENA_SCENE),
		"the start button points at a scene that exists"
	)
	_check(
		ResourceLoader.exists(MainMenu.CITY_SCENE),
		"the second scenario points at a scene that exists"
	)
	if options == null:
		menu.queue_free()
		return

	_check(not options.visible, "the options panel starts hidden")
	_check(preview != null, "the panel carries a live livery preview")

	Sfx.reset_counts()
	options_button.pressed.emit()
	await get_tree().process_frame
	_check(options.visible, "the options button opens the panel")
	_check(Sfx.played(&"ui_select") == 1, "opening the options panel asks for a menu blip")

	# The controls table is the second half of the panel, so a row has to be there,
	# it has to name a control the build really has, and it has to offer the pad
	# button that control is on -- the table is the reference and the editor at once.
	var grid: GridContainer = menu.get_node("%ControlGrid") as GridContainer
	_check(grid != null, "the options panel lists the controls")
	if grid != null:
		_check(
			grid.get_child_count() == MainMenu.ROWS.size() * 3,
			"every control row has a name, its keys and its pad cell (%d cells)"
			% grid.get_child_count()
		)
		_check(
			_has_label_text(grid, "Decoy"),
			"the controls reference names the decoy"
		)
		var decoy_button: Button = _control_button(grid, "Decoy")
		_check(
			decoy_button != null and decoy_button.text == PadBindings.label_for(
				int(PadBindings.defaults()[&"decoy"])
			),
			"the decoy row is the button the decoy is on"
		)

	_check(
		hull_row != null
		and nose_row != null
		and trim_row != null
		and canopy_row != null
		and lines_row != null,
		"the panel carries all five colour rows"
	)
	if (
		hull_row != null
		and nose_row != null
		and trim_row != null
		and canopy_row != null
		and lines_row != null
	):
		_check(
			hull_row.get_child_count() == MainMenu.PALETTE.size(),
			"the hull row offers the whole palette (%d swatches)"
			% hull_row.get_child_count()
		)
		for row in [nose_row, trim_row, canopy_row, lines_row]:
			_check(
				(row as HBoxContainer).get_child_count() == MainMenu.PALETTE.size(),
				"every colour row offers the whole palette"
			)
		_check(
			_pressed_swatch(hull_row) == hull_row.get_child(4),
			"the saved hull comes back selected"
		)
		_check(
			_pressed_swatch(nose_row) == nose_row.get_child(8),
			"the saved nose comes back selected"
		)
		_check(
			_pressed_swatch(trim_row) == trim_row.get_child(5),
			"the saved stripe comes back selected"
		)
		_check(
			_pressed_swatch(canopy_row) == canopy_row.get_child(6),
			"the saved canopy comes back selected"
		)
		_check(
			_pressed_swatch(lines_row) == lines_row.get_child(7),
			"the saved lines come back selected"
		)
		var hull_button: Button = hull_row.get_child(0) as Button
		_check(
			hull_button != null and hull_button.button_group != null,
			"a colour row is one exclusive choice, not a pile of toggles"
		)

		# A click has to reach the file, because that is what the next launch and
		# the ship in the arena both read.
		(hull_row.get_child(2) as Button).pressed.emit()
		_check(
			GameSettings.load_hull(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[2]
			),
			"picking a hull swatch is saved"
		)
		(nose_row.get_child(6) as Button).pressed.emit()
		_check(
			GameSettings.load_nose(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[6]
			),
			"picking a nose swatch is saved"
		)
		(trim_row.get_child(8) as Button).pressed.emit()
		_check(
			GameSettings.load_trim(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[8]
			),
			"picking a stripe swatch is saved"
		)
		(canopy_row.get_child(3) as Button).pressed.emit()
		_check(
			GameSettings.load_canopy(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[3]
			),
			"picking a canopy swatch is saved"
		)
		(lines_row.get_child(1) as Button).pressed.emit()
		_check(
			GameSettings.load_lines(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[1]
			),
			"picking a line swatch is saved"
		)

	back_button.pressed.emit()
	await get_tree().process_frame
	_check(not options.visible, "the back button closes the panel")

	# Both settings share one file, so neither save may erase the other.
	GameSettings.save_fullscreen(true, TEST_SETTINGS)
	GameSettings.save_livery(
		MainMenu.PALETTE[2],
		MainMenu.PALETTE[8],
		MainMenu.PALETTE[3],
		MainMenu.PALETTE[1],
		MainMenu.PALETTE[6],
		TEST_SETTINGS
	)
	_check(
		GameSettings.load_fullscreen(TEST_SETTINGS),
		"the fullscreen choice is remembered"
	)
	_check(
		GameSettings.load_hull(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[2]),
		"and saving it keeps the hull"
	)
	_check(
		GameSettings.load_trim(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[8]),
		"and the stripe"
	)
	_check(
		GameSettings.load_canopy(TEST_SETTINGS).is_equal_approx(
			MainMenu.PALETTE[3]
		),
		"and the canopy"
	)
	_check(
		GameSettings.load_lines(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[1]),
		"and the lines"
	)
	_check(
		GameSettings.load_nose(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[6]),
		"and the nose"
	)
	GameSettings.save_fullscreen(false, TEST_SETTINGS)
	_check(
		not GameSettings.load_fullscreen(TEST_SETTINGS),
		"and the choice can be turned back off"
	)
	_check(
		GameSettings.load_lines(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[1]),
		"turning it off keeps the livery"
	)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	_check(
		GameSettings.load_hull(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_HULL
		),
		"a missing file falls back to the factory hull"
	)
	_check(
		GameSettings.load_trim(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_TRIM
		),
		"a missing file falls back to the factory stripe"
	)
	_check(
		GameSettings.load_canopy(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_CANOPY
		),
		"a missing file falls back to the factory canopy"
	)
	_check(
		GameSettings.load_lines(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_LINES
		),
		"a missing file falls back to the factory lines"
	)
	_check(
		GameSettings.load_nose(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_NOSE
		),
		"a missing file falls back to the factory nose"
	)

	# The save list and the pilot panel. CONTINUE is the door to the cards, so it
	# is offered even before any card has flown: an empty card is how a second
	# pilot is created. The arena that is already running wrote a card when it
	# started, so the empty state is built by clearing the scratch cards first.
	var continue_button: Button = menu.get_node("%ContinueButton") as Button
	var saves_panel: Control = menu.get_node("%Saves") as Control
	var slot_line: Label = menu.get_node("%SlotLine") as Label
	var slot_primary: Button = menu.get_node("%SlotPrimary") as Button
	var slot_secondary: Button = menu.get_node("%SlotSecondary") as Button
	var saves_back: Button = menu.get_node("%SavesBackButton") as Button
	var pilot_button: Button = menu.get_node("%PilotButton") as Button
	var pilot: Control = menu.get_node("%Pilot") as Control
	var pilot_level: Label = menu.get_node("%Level") as Label
	var pilot_tracks: Label = menu.get_node("%Tracks") as Label
	var reset_button: Button = menu.get_node("%ResetButton") as Button
	var pilot_back: Button = menu.get_node("%PilotBackButton") as Button
	_check(
		continue_button != null and continue_button.visible,
		"the menu always offers continue"
	)
	_check(saves_panel != null and not saves_panel.visible, "the save list starts hidden")
	_check(pilot_button != null, "the menu offers a pilot panel")
	_check(pilot != null and not pilot.visible, "the pilot panel starts hidden")

	_clean_saves()
	SaveSlots.select(1, TEST_SETTINGS)
	SaveSlots.select(2, TEST_SETTINGS)
	GameProgress.instance().total_kills = 37
	GameProgress.instance().remember_scenario(City.SCENE_PATH)
	SaveSlots.select(1, TEST_SETTINGS)
	menu.refresh()
	_check(
		slot_line.text.begins_with("SLOT 1") and slot_line.text.contains("NEW PILOT"),
		"the menu names the active card (%s)" % slot_line.text
	)

	continue_button.pressed.emit()
	await get_tree().process_frame
	_check(saves_panel.visible, "continue opens the save list")
	var card1: Button = menu.slot_button(1)
	var card2: Button = menu.slot_button(2)
	_check(
		card2 != null and card2.text.contains("37 KILLS") and card2.text.contains("CITY"),
		"a card names its pilot, kills and scenario"
	)
	_check(
		card1 != null and card1.text.contains("EMPTY SLOT"),
		"an unused card reads empty"
	)

	card2.pressed.emit()
	_check(slot_primary.text == "LOAD", "an occupied card offers a load")
	_check(slot_secondary.text == "DELETE", "and a delete")
	menu.slot_button(3).pressed.emit()
	_check(slot_primary.text == "START PLANET", "an empty card offers the first flight")
	_check(slot_secondary.text == "START CITY", "on either scenario")

	# The delete presses only run when the card really is occupied: on an empty
	# card the secondary button starts a run, and one squashed failure would take
	# the whole suite with it.
	var seeded: bool = FileAccess.file_exists(SaveSlots.path_for(2))
	_check(seeded, "the scratch card reaches the disk")
	if seeded:
		card2.pressed.emit()
		slot_secondary.pressed.emit()
		_check(
			FileAccess.file_exists(SaveSlots.path_for(2)),
			"the first delete press only arms the card"
		)
		slot_secondary.pressed.emit()
		_check(
			not FileAccess.file_exists(SaveSlots.path_for(2)),
			"the second delete press clears the card"
		)
		_check(menu.slot_button(2).text.contains("EMPTY SLOT"), "the cleared card reads empty")
	saves_back.pressed.emit()
	await get_tree().process_frame
	_check(not saves_panel.visible, "back closes the save list")

	# The pilot panel shows the active card, and its reset is that card's
	# two-press delete.
	SaveSlots.select(1, TEST_SETTINGS)
	GameProgress.instance().total_kills = 37
	GameProgress.instance().remember_scenario(City.SCENE_PATH)
	menu.refresh()
	pilot_button.pressed.emit()
	await get_tree().process_frame
	_check(pilot.visible, "the pilot button opens the panel")
	_check(
		pilot_level.text == "LEVEL %d" % GameProgress.level_for_kills(37),
		"the panel shows the level (%s)" % pilot_level.text
	)
	_check(pilot_tracks.text.contains("THRUSTERS"), "the panel lists the five tracks")

	reset_button.pressed.emit()
	_check(
		FileAccess.file_exists(SaveSlots.path_for(1)),
		"the first reset press only arms the button"
	)
	reset_button.pressed.emit()
	_check(
		not FileAccess.file_exists(SaveSlots.path_for(1)),
		"the second reset press clears the active card"
	)
	_check(pilot_level.text == "LEVEL 1", "the panel returns to level 1")

	pilot_back.pressed.emit()
	await get_tree().process_frame
	_check(not pilot.visible, "the pilot back button closes the panel")

	menu.queue_free()
	await get_tree().process_frame


## The pad is the one input the player can rearrange, so the contract has three
## halves: the factory map is the one the project ships, a bind never takes a key
## or a mouse button with it, and the file either describes a working pad or has
## no say at all. The suite keeps flying after this, so it ends on the factory pad.
func _test_pad_bindings() -> void:
	var factory: Dictionary = PadBindings.defaults()
	_check(
		int(factory[&"fire"]) == JOY_BUTTON_RIGHT_SHOULDER
		and int(factory[&"missile"]) == JOY_BUTTON_X
		and int(factory[&"dash"]) == JOY_BUTTON_LEFT_SHOULDER
		and int(factory[&"transform"]) == JOY_BUTTON_BACK
		and int(factory[&"bomb"]) == JOY_BUTTON_Y
		and int(factory[&"decoy"]) == JOY_BUTTON_GUIDE
		and int(factory[&"weapon_prev"]) == JOY_BUTTON_DPAD_LEFT
		and int(factory[&"weapon_next"]) == JOY_BUTTON_DPAD_RIGHT
		and int(factory[&"restart"]) == JOY_BUTTON_START,
		"the factory pad is the one the project ships"
	)

	PadBindings.apply(factory)
	var live: Dictionary = PadBindings.current()
	_check(
		int(live[&"fire"]) == JOY_BUTTON_RIGHT_SHOULDER
		and int(live[&"dash"]) == JOY_BUTTON_LEFT_SHOULDER,
		"applying the factory pad is what the engine reads"
	)

	# A pad remap may not take a key or a mouse button away from its action.
	var mouse_kept: bool = false
	var key_kept: bool = false
	for event: InputEvent in InputMap.action_get_events(&"fire"):
		if event is InputEventMouseButton:
			mouse_kept = true
	for event: InputEvent in InputMap.action_get_events(&"dash"):
		var key: InputEventKey = event as InputEventKey
		if key != null and key.physical_keycode == KEY_SPACE:
			key_kept = true
	_check(mouse_kept, "a pad bind keeps the fire mouse button")
	_check(key_kept, "a pad bind keeps Space on the dash")

	# The swap: fire takes the missile's button, and the missile inherits fire's.
	var swapped: Dictionary = PadBindings.defaults()
	PadBindings.assign(swapped, &"fire", JOY_BUTTON_X)
	_check(
		int(swapped[&"missile"]) == JOY_BUTTON_RIGHT_SHOULDER,
		"assigning a taken button swaps the other action"
	)
	_check(
		int(swapped[&"fire"]) == JOY_BUTTON_X,
		"the edited action keeps the button that was pressed"
	)
	_check(
		swapped.size() == PadBindings.ACTIONS.size(),
		"a swap never leaves an action without a button"
	)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	PadBindings.save_bindings(swapped, TEST_SETTINGS)
	var reloaded: Dictionary = PadBindings.load_bindings(TEST_SETTINGS)
	_check(
		int(reloaded[&"fire"]) == JOY_BUTTON_X
		and int(reloaded[&"missile"]) == JOY_BUTTON_RIGHT_SHOULDER,
		"a save round-trips through the settings file"
	)

	# The pad shares the file with the display and livery sections, so writing it
	# may not erase either of them.
	GameSettings.save_fullscreen(true, TEST_SETTINGS)
	GameSettings.save_livery(
		MainMenu.PALETTE[2],
		MainMenu.PALETTE[8],
		MainMenu.PALETTE[3],
		MainMenu.PALETTE[1],
		MainMenu.PALETTE[6],
		TEST_SETTINGS
	)
	_check(
		GameSettings.load_fullscreen(TEST_SETTINGS),
		"saving the pad keeps the fullscreen choice"
	)
	_check(
		GameSettings.load_hull(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[2]),
		"saving the pad keeps the livery"
	)

	# A file that cannot describe a working pad falls back instead of half working.
	var config: ConfigFile = ConfigFile.new()
	config.load(TEST_SETTINGS)
	config.set_value(PadBindings.SECTION, "dash", 999)
	config.save(TEST_SETTINGS)
	_check(
		int(PadBindings.load_bindings(TEST_SETTINGS)[&"dash"]) == JOY_BUTTON_LEFT_SHOULDER,
		"an out of range button falls back to the factory button"
	)
	config.set_value(PadBindings.SECTION, "dash", JOY_BUTTON_B)
	config.set_value(PadBindings.SECTION, "bomb", JOY_BUTTON_B)
	config.save(TEST_SETTINGS)
	var collided: Dictionary = PadBindings.load_bindings(TEST_SETTINGS)
	_check(
		int(collided[&"dash"]) == JOY_BUTTON_LEFT_SHOULDER
		and int(collided[&"bomb"]) == JOY_BUTTON_Y,
		"two actions on one button is not a pad worth trusting"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))

	# The editor is the controls table inside OPTIONS, so the panel is opened the
	# way a player opens it and the row is found where the panel draws it.
	var scene: PackedScene = load("res://ui/menu/main_menu.tscn")
	var menu: MainMenu = scene.instantiate() as MainMenu
	menu.settings_path = TEST_SETTINGS
	add_child(menu)
	await get_tree().process_frame

	var options_button: Button = menu.get_node("%OptionsButton") as Button
	var options: Control = menu.get_node("%Options") as Control
	var grid: GridContainer = menu.get_node("%ControlGrid") as GridContainer
	var hint: Label = menu.get_node("%ControlHint") as Label
	var reset: Button = menu.get_node("%PadResetButton") as Button
	var back: Button = menu.get_node("%BackButton") as Button
	var bomb_button: Button = _control_button(grid, "Bomb") if grid != null else null
	_check(options != null and not options.visible, "the pad editor lives inside options")
	_check(
		grid != null and grid.get_child_count() == MainMenu.ROWS.size() * 3,
		"the panel draws one row per control, pad cell included (%d cells)"
		% (grid.get_child_count() if grid != null else 0)
	)
	_check(bomb_button != null, "the panel has a row for the bomb")
	_check(
		bomb_button != null and bomb_button.text == "Y",
		"the row names the button the bomb is on"
	)
	if options_button == null or bomb_button == null:
		PadBindings.apply(PadBindings.defaults())
		menu.queue_free()
		return

	options_button.pressed.emit()
	await get_tree().process_frame
	_check(options.visible, "the options button opens the panel that holds the editor")
	_check(hint.text == MainMenu.IDLE_HINT, "the panel explains how to bind")

	bomb_button.pressed.emit()
	await get_tree().process_frame
	_check(
		bomb_button.text == "PRESS A BUTTON",
		"the row asks for a press once it is picked"
	)
	_check(hint.text.contains("Bomb"), "the hint names the action being bound")

	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	menu._input(press)
	await get_tree().process_frame
	_check(
		bomb_button.text == "A",
		"the pressed button becomes the action's button (%s)" % bomb_button.text
	)
	_check(
		int(PadBindings.load_bindings(TEST_SETTINGS)[&"bomb"]) == JOY_BUTTON_A,
		"the bind is written as soon as it is made"
	)
	_check(
		int(PadBindings.current()[&"bomb"]) == JOY_BUTTON_A,
		"and the run reads the new button"
	)

	# Escape cancels the next one instead of binding anything to it.
	bomb_button.pressed.emit()
	await get_tree().process_frame
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	menu._input(escape)
	await get_tree().process_frame
	_check(bomb_button.text == "A", "Escape leaves the binding alone")

	# Reset is a choice like any other: it restores and it writes.
	reset.pressed.emit()
	await get_tree().process_frame
	_check(bomb_button.text == "Y", "reset puts the factory button back")
	_check(
		int(PadBindings.load_bindings(TEST_SETTINGS)[&"bomb"]) == JOY_BUTTON_Y,
		"and reset is saved too"
	)

	# Closing the panel is the cancel: a listener that outlived the panel would eat
	# the next pad press in the main menu.
	bomb_button.pressed.emit()
	await get_tree().process_frame
	back.pressed.emit()
	await get_tree().process_frame
	_check(not options.visible, "the back button closes the panel")
	_check(hint.text == MainMenu.IDLE_HINT, "closing the panel drops the waiting bind")
	options_button.pressed.emit()
	await get_tree().process_frame
	_check(
		bomb_button.text == "Y",
		"and the row is not still asking for a press when the panel comes back"
	)

	menu.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	PadBindings.apply(PadBindings.defaults())
	_check(
		int(PadBindings.current()[&"fire"]) == JOY_BUTTON_RIGHT_SHOULDER,
		"the suite leaves the factory pad behind"
	)


## The livery has to land on the right surfaces and nowhere else: the hull is one
## family of materials, the stripe another, the lines a third, the nose its own,
## and the canopy is found by the bones it hangs from. The rest of the airframe is
## what makes it look like an aircraft instead of a painted brick.
func _test_livery_paint() -> void:
	var hull: Color = Color(0.85, 0.12, 0.10)
	var trim: Color = Color(0.10, 0.75, 0.35)
	var canopy: Color = Color(0.95, 0.45, 0.05)
	var lines: Color = Color(0.90, 0.10, 0.80)
	var nose: Color = Color(0.10, 0.25, 0.95)

	var model: PlayerModel = PlayerModel.new()
	add_child(model)
	model.set_livery(hull, trim, canopy, lines, nose)
	_check(model.build(), "the airframe builds wearing a livery")

	var hulls: Array[Color] = _material_colors(model, PlayerModel.HULL_MATERIAL)
	var trims: Array[Color] = _material_colors(model, PlayerModel.TRIM_MATERIAL)
	var dark: Array[Color] = _material_colors(model, PlayerModel.LINE_MATERIAL)
	var glass: Array[Color] = _canopy_colors(model)
	var cones: Array[Color] = _nose_colors(model)
	_check(hulls.size() > 0, "the hull sheets are painted (%d surfaces)" % hulls.size())
	_check(trims.size() > 0, "the stripe is painted (%d surfaces)" % trims.size())
	_check(dark.size() > 0, "the black lines are painted (%d surfaces)" % dark.size())
	_check(glass.size() > 0, "the canopy glass is painted (%d surfaces)" % glass.size())
	_check(cones.size() > 0, "the nose cone is painted (%d surfaces)" % cones.size())
	_check(_all_colors_are(hulls, hull), "every hull surface takes the hull colour")
	_check(_all_colors_are(trims, trim), "every stripe surface takes the stripe colour")
	_check(_all_colors_are(dark, lines), "every line surface takes the line colour")
	_check(_all_colors_are(glass, canopy), "every canopy panel takes the canopy colour")
	_check(_all_colors_are(cones, nose), "every nose surface takes the nose colour")

	# The canopy cover wears a hull-family material, so the hull pass must leave it
	# alone: otherwise the cockpit ends up painted with the hull colour.
	var cover: Array[Color] = _canopy_cover_colors(model)
	_check(cover.size() > 0, "the canopy cover is found (%d surfaces)" % cover.size())
	_check(
		_all_colors_are(cover, canopy),
		"the hull pass does not paint the canopy cover"
	)

	# The cone shares one hull sheet with the fuselage under the cockpit, so the
	# sheet is cut at the canopy: the front half takes the nose colour and the
	# section behind it stays hull. The lines that cross the nose are still lines.
	_check(
		_all_colors_are(cones, nose) and not _all_colors_are(cones, hull),
		"the hull pass does not paint the nose"
	)
	var under_canopy: Array[Color] = _nose_hull_colors(model)
	_check(
		under_canopy.size() > 0,
		"the fuselage under the canopy is still hull (%d surfaces)" % under_canopy.size()
	)
	_check(
		_all_colors_are(under_canopy, hull),
		"the section behind the nose takes the hull colour"
	)
	var cut: float = _canopy_front(model) + PlayerModel.NOSE_GAP
	var cone_span: Vector2 = _nose_surface_span(model, PlayerModel.NOSE_MATERIAL)
	var aft_span: Vector2 = _nose_surface_span(model, PlayerModel.HULL_MATERIAL)
	_check(
		cone_span.x >= cut - 0.01,
		"the nose paint starts a gap ahead of the canopy (%.2f vs %.2f)" % [cone_span.x, cut]
	)
	_check(
		aft_span.y <= cut + 0.01,
		"and the hull keeps the lip in front of it (%.2f)" % aft_span.y
	)
	_check(
		cone_span.y > aft_span.y,
		"the nose half carries the tip (%.2f vs %.2f)" % [cone_span.y, aft_span.y]
	)
	var nose_lines: Array[Color] = _nose_line_colors(model)
	_check(nose_lines.size() > 0, "the nose keeps its panel lines (%d surfaces)" % nose_lines.size())
	_check(
		_all_colors_are(nose_lines, lines),
		"the lines across the nose still take the line colour"
	)

	# A live repaint is what the options preview does on every click, so it has to
	# reach surfaces that are already overridden.
	var recoloured: Color = Color(0.20, 0.40, 0.90)
	model.set_livery(recoloured, trim, canopy, lines, nose)
	var after: Array[Color] = _material_colors(model, PlayerModel.HULL_MATERIAL)
	_check(after.size() == hulls.size(), "repainting keeps every hull surface")
	_check(_all_colors_are(after, recoloured), "a live repaint reaches the hull")
	model.set_livery(recoloured, trim, canopy, Color(0.0, 0.85, 0.95), nose)
	_check(
		_all_colors_are(_material_colors(model, PlayerModel.LINE_MATERIAL), Color(0.0, 0.85, 0.95)),
		"a live repaint reaches the lines"
	)
	model.set_livery(
		recoloured, trim, Color(0.95, 0.85, 0.10), Color(0.0, 0.85, 0.95), nose
	)
	_check(
		_all_colors_are(_canopy_colors(model), Color(0.95, 0.85, 0.10)),
		"a live repaint reaches the canopy"
	)
	model.set_livery(
		recoloured, trim, Color(0.95, 0.85, 0.10), Color(0.0, 0.85, 0.95),
		Color(0.95, 0.05, 0.35)
	)
	_check(
		_all_colors_are(_nose_colors(model), Color(0.95, 0.05, 0.35)),
		"a live repaint reaches the nose"
	)

	# The GLB is shared by every ship and by the preview, so the paint lives in
	# duplicated materials: a repainted file would recolour the next ship too.
	var pristine: Node3D = (
		(load(PlayerModel.MODEL_PATH) as PackedScene).instantiate() as Node3D
	)
	add_child(pristine)
	var factory: Array[Color] = _material_colors(pristine, PlayerModel.HULL_MATERIAL)
	_check(factory.size() > 0, "the file still carries its own hull material")
	_check(
		_all_colors_are(factory, GameSettings.DEFAULT_HULL),
		"painting a ship leaves the shared model untouched"
	)
	_check(
		_nose_colors(pristine).is_empty(),
		"and the split leaves the shared model with its single hull sheet"
	)
	_check(
		_all_colors_match_rgb(
			_material_colors(pristine, PlayerModel.LINE_MATERIAL), GameSettings.DEFAULT_LINES
		),
		"and leaves the file's own lines untouched"
	)
	pristine.queue_free()

	model.queue_free()


func _pressed_swatch(row: HBoxContainer) -> Button:
	for child in row.get_children():
		var button: Button = child as Button
		if button != null and button.button_pressed:
			return button
	return null


## Every surface colour under `root` whose material carries the name prefix. The
## file suffixes the name per mesh ("Aircraft BASE color.014"), so the match is on
## the prefix, the same rule the paint pass uses. The canopy panels are skipped:
## the cover wears a hull-family material and belongs to the canopy pass. The
## section of the forward fuselage behind the nose keeps the hull family, so it
## counts here as hull.
func _material_colors(root: Node, prefix: String) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if _is_canopy_panel(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material == null:
				continue
			if String(material.resource_name).begins_with(prefix):
				colors.append(material.albedo_color)
	return colors


## The colour of every canopy panel, found the same way the paint pass finds them.
func _canopy_colors(root: Node) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_canopy_panel(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material != null:
				colors.append(material.albedo_color)
	return colors


## Only the cover panel, which is the one that ships wearing a hull material.
func _canopy_cover_colors(root: Node) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var attachment: BoneAttachment3D = mesh.get_parent() as BoneAttachment3D
		if attachment == null or attachment.bone_name != "Bone.CanopyCover":
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material != null:
				colors.append(material.albedo_color)
	return colors


func _is_canopy_panel(mesh: MeshInstance3D) -> bool:
	var attachment: BoneAttachment3D = mesh.get_parent() as BoneAttachment3D
	if attachment == null or not PlayerModel.CANOPY_BONES.has(attachment.bone_name):
		return false
	var lower: String = String(mesh.name).to_lower()
	return lower.contains(PlayerModel.CANOPY_MESH) and not lower.contains("rib")


## The cone half of the forward fuselage sheet, which the split renames to the
## nose material. The section under the canopy keeps the hull name.
func _nose_colors(root: Node) -> Array[Color]:
	return _nose_family_colors(root, PlayerModel.NOSE_MATERIAL)


## The half of the forward fuselage sheet that stays hull: the section behind the
## canopy, which the nose colour must not swallow.
func _nose_hull_colors(root: Node) -> Array[Color]:
	return _nose_family_colors(root, PlayerModel.HULL_MATERIAL)


func _nose_family_colors(root: Node, prefix: String) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_nose_mesh(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material == null:
				continue
			if String(material.resource_name).begins_with(prefix):
				colors.append(material.albedo_color)
	return colors


## The forward-most triangle centroid of the nose surfaces wearing `material_name`,
## in the mesh's own space, and the furthest back one. The split is a cut along the
## fuselage, so the two halves must not overlap on that axis.
func _nose_surface_span(root: Node, material_name: String) -> Vector2:
	var low: float = INF
	var high: float = -INF
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_nose_mesh(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material == null:
				continue
			if not String(material.resource_name).begins_with(material_name):
				continue
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for corner in range(0, indices.size(), 3):
				var centroid: Vector3 = (
					vertices[indices[corner]]
					+ vertices[indices[corner + 1]]
					+ vertices[indices[corner + 2]]
				) / 3.0
				low = minf(low, centroid.z)
				high = maxf(high, centroid.z)
	return Vector2(low, high)


## The canopy's leading edge in the forward fuselage's space, measured from the
## panels rather than assumed, so the test checks the rule the paint pass follows.
func _canopy_front(root: Node) -> float:
	var nose: MeshInstance3D = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if _is_nose_mesh(mesh):
			nose = mesh
			break
	if nose == null:
		return INF
	var to_mesh: Transform3D = nose.global_transform.affine_inverse()
	var front: float = -INF
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var panel: MeshInstance3D = node as MeshInstance3D
		if not _is_canopy_panel(panel):
			continue
		var local: Transform3D = to_mesh * panel.global_transform
		for surface in panel.mesh.get_surface_count():
			var vertices: PackedVector3Array = (
				panel.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			)
			for point in vertices:
				front = maxf(front, (local * point).z)
	return front


## The lines that cross the nose: they share the mesh with the cone, so they are
## the check that the nose colour does not swallow them.
func _nose_line_colors(root: Node) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_nose_mesh(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material == null:
				continue
			if String(material.resource_name).begins_with(PlayerModel.LINE_MATERIAL):
				colors.append(material.albedo_color)
	return colors


func _is_nose_mesh(mesh: MeshInstance3D) -> bool:
	return String(mesh.name).to_lower().contains(PlayerModel.NOSE_MESH)


func _all_colors_are(colors: Array[Color], expected: Color) -> bool:
	for color in colors:
		if not color.is_equal_approx(expected):
			return false
	return true


## The file's own lines carry alpha zero, so comparing them to a picked colour has
## to ignore alpha.
func _all_colors_match_rgb(colors: Array[Color], expected: Color) -> bool:
	for color in colors:
		if (
			not is_equal_approx(color.r, expected.r)
			or not is_equal_approx(color.g, expected.g)
			or not is_equal_approx(color.b, expected.b)
		):
			return false
	return true


func _has_label_text(parent: Node, text: String) -> bool:
	for child in parent.get_children():
		var label: Label = child as Label
		if label != null and label.text == text:
			return true
	return false


## The controls table is three cells per row, so a row is found by the name in its
## first cell. A row the player cannot rearrange answers null, and so does the
## weapon row, whose third cell is a pair of buttons rather than one.
func _control_button(grid: GridContainer, action: String) -> Button:
	for index: int in range(0, grid.get_child_count(), 3):
		var label: Label = grid.get_child(index) as Label
		if label == null or label.text != action:
			continue
		return grid.get_child(index + 2) as Button
	return null


func _test_player_is_centered() -> void:
	var camera: Camera3D = _player.camera
	_check(camera != null, "player owns a Camera3D")
	if camera == null:
		return

	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = camera.unproject_position(_player.global_position)
	var offset: float = projected.distance_to(centre)
	_check(offset < 1.0, "player projects to the screen centre (off by %.2f px)" % offset)


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


## Six scratch cards and their scratch legacy file, removed without ever touching
## the player's real memory card.
func _clean_saves() -> void:
	for slot: int in range(1, SaveSlots.SLOT_COUNT + 1):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(SaveSlots.path_for(slot))
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LEGACY))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("%s.imported" % TEST_LEGACY))


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


## The maneuverability contract: cruise inside 0.08 s, a full stop inside 0.06 s,
## tap mode on a light tilt, a 3x dash that drops the old inertia, a model that
## banks and catches up without ever lagging the shot, and a camera that springs
## the ship back to centre once it stops.
func _test_maneuverability() -> void:
	_release_all_input()
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	var accel_frames: int = 0
	Input.action_press(&"move_right")
	while accel_frames < 15 and _flat_speed() < Player.MAX_SPEED * 0.98:
		await get_tree().physics_frame
		accel_frames += 1
	_check(
		accel_frames <= 4,
		"cruise arrives in %d frames (%.3f s)" % [accel_frames, accel_frames / 60.0]
	)

	var stop_frames: int = 0
	Input.action_release(&"move_right")
	while stop_frames < 15 and _flat_speed() > 0.01:
		await get_tree().physics_frame
		stop_frames += 1
	_check(
		stop_frames <= 3,
		"a full stop from cruise takes %d frames (%.3f s)"
		% [stop_frames, stop_frames / 60.0]
	)

	# Tap mode: a 20 percent tilt has to move the ship without giving it real
	# cruise speed, or threading a narrow gap becomes all or nothing.
	Input.action_press(&"move_right", 0.2)
	for _i in 20:
		await get_tree().physics_frame
	var tap_speed: float = _flat_speed()
	Input.action_release(&"move_right")
	_check(
		tap_speed > 0.5 and tap_speed < Player.MAX_SPEED * 0.25,
		"a light tilt moves the ship at tap speed (%.1f u/s)" % tap_speed
	)
	_player.velocity = Vector3.ZERO

	# Dash: the double tap is still the jink -- 3x cruise from the first frame, and
	# it must wipe the inertia it had.
	Input.action_press(&"move_left")
	for _i in 20:
		await get_tree().physics_frame
	var before_dash: float = _player.velocity.x
	Input.action_release(&"move_left")

	Input.action_press(&"move_right")
	# Input injected from a coroutine lands after the physics step, so the
	# just_pressed latch never reaches _physics_process; call the handler the
	# frame would.
	_player.call("_start_dash", Vector2.RIGHT)
	await get_tree().physics_frame
	var dash_speed: float = _flat_speed()
	var dash_x: float = _player.velocity.x
	_check(
		dash_speed >= Player.MAX_SPEED * 3.0,
		"the tapped dash injects %.2fx cruise on frame one" % (dash_speed / Player.MAX_SPEED)
	)
	_check(
		dash_x > 0.0 and before_dash < -Player.MAX_SPEED * 0.5,
		"the tapped dash cancels the inherited inertia (%.1f -> %.1f u/s)" % [before_dash, dash_x]
	)
	var tap_spin: float = float(_player.get("_roll_anim_time"))
	_check(tap_spin > 0.0, "the tapped dash also comes over (%.2f s)" % tap_spin)
	Input.action_release(&"move_right")

	# Space is the spin on its own: a key pressed to "come over" must not also shove
	# the ship somewhere, and the roll is what carries the i-frames. The side is the
	# aim axis, the same control the fighter's button reads.
	_player.velocity = Vector3.ZERO
	_player.set("_roll_anim_time", 0.0)
	_player.set("_dash_cooldown", 0.0)
	Input.action_press(&"aim_right")
	_player.call("_start_dash")
	await get_tree().physics_frame
	var spin_speed: float = _flat_speed()
	var gerwalk_spin: float = float(_player.get("_roll_anim_time"))
	var gerwalk_side: float = float(_player.get("_roll_side"))
	var gerwalk_roll: float = (_player.get("_visual") as Node3D).rotation.x
	_check(
		spin_speed < Player.MAX_SPEED * 0.25 and gerwalk_spin > 0.0,
		"a GERWALK button roll spins without dashing (%.1f u/s, %.2f s)"
		% [spin_speed, gerwalk_spin]
	)
	_check(
		gerwalk_side > 0.0 and gerwalk_roll > 0.0,
		"the GERWALK button roll comes over on the side the aim asked (side %+.0f, %.0f deg)"
		% [gerwalk_side, rad_to_deg(gerwalk_roll)]
	)
	_check(_player.is_evading(), "the GERWALK button roll still carries its i-frames")
	Input.action_release(&"aim_right")
	_player.set("_roll_anim_time", 0.0)

	# Aim is instant while the model eases in at 1800 deg/s: the shot never waits
	# for the animation, and the animation still finishes a 180 in about 0.1 s.
	Input.action_press(&"aim_left")
	for _i in 30:
		await get_tree().physics_frame
	Input.action_release(&"aim_left")
	Input.action_press(&"aim_right")
	await get_tree().physics_frame
	var shot_axis: float = _player.get("_aim_direction").x
	var catching_up: float = absf(rad_to_deg(_player.get("_visual").rotation.y))
	for _i in 8:
		await get_tree().physics_frame
	var settled_yaw: float = absf(rad_to_deg(_player.get("_visual").rotation.y))
	_check(shot_axis > 0.99, "the shot direction flips on the first frame (x %.2f)" % shot_axis)
	_check(
		catching_up > 60.0,
		"the model is still swinging one frame after the flick (%.0f deg to go)" % catching_up
	)
	_check(settled_yaw < 2.0, "the model completes the 180 in under 0.15 s (%.1f deg off)" % settled_yaw)
	Input.action_release(&"aim_right")

	# Banking: drift sideways across the nose and the hull leans; stop and it
	# levels out again.
	Input.action_press(&"aim_right")
	for _i in 10:
		await get_tree().physics_frame
	Input.action_press(&"move_up")
	for _i in 20:
		await get_tree().physics_frame
	var bank: float = rad_to_deg(_player.get("_visual").rotation.x)
	Input.action_release(&"move_up")
	Input.action_release(&"aim_right")
	for _i in 40:
		await get_tree().physics_frame
	var level: float = absf(rad_to_deg(_player.get("_visual").rotation.x))
	_check(absf(bank) >= 15.0 and absf(bank) <= 40.0, "strafing banks the hull (%.1f deg)" % bank)
	_check(level < 3.0, "the hull levels out when the drift stops (%.1f deg)" % level)

	# The camera spring settles the ship back to dead centre once it is still.
	_release_all_input()
	_player.velocity = Vector3.ZERO
	for _i in 30:
		await get_tree().physics_frame
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = _player.camera.unproject_position(_player.global_position)
	_check(
		projected.distance_to(centre) < 1.0,
		"the camera settles the ship back to centre at rest (%.2f px)"
		% projected.distance_to(centre)
	)


## The dash gesture: a double tap on the movement stick dashes the way it was
## tapped, one tap and two taps in different directions spend nothing, and in
## FIGHTER the jink follows the tap on both axes, diagonals included. The Space /
## L3 button stays as the alternative.
func _test_double_tap_dash() -> void:
	await _reset_dash_gesture()
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	Input.action_release(&"move_right")
	await get_tree().physics_frame
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	var tap_speed: float = _flat_speed()
	_check(
		float(_player.get("_dash_time")) > 0.0
		and tap_speed >= Player.MAX_SPEED * 3.0
		and _player.velocity.x > 0.0,
		"a double tap dashes the way it was tapped (%.1f u/s)" % tap_speed
	)
	Input.action_release(&"move_right")

	# One tap is a nudge, not a dash: the second tap is the whole gesture.
	await _reset_dash_gesture()
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	await get_tree().physics_frame
	_check(
		float(_player.get("_dash_time")) <= 0.0,
		"one tap moves the ship without spending the dash"
	)

	# Two taps that disagree are a direction change, not a dash. Left then up is
	# 90 degrees apart, well outside the cone.
	await _reset_dash_gesture()
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	Input.action_release(&"move_left")
	await get_tree().physics_frame
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	_check(
		float(_player.get("_dash_time")) <= 0.0,
		"two taps in different directions do not dash"
	)
	Input.action_release(&"move_up")

	# FIGHTER: the lateral double tap rolls to the tapped side. With the nose
	# up-screen, screen-left is the airframe's own left.
	await _reset_dash_gesture()
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the double-tap check starts in FIGHTER")
	await _reset_dash_gesture()
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	Input.action_release(&"move_left")
	await get_tree().physics_frame
	# The first tap is a heading request too, so the nose is reset between taps:
	# the jink is measured against the heading it was actually asked from.
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	var roll_side: float = float(_player.get("_roll_side"))
	_check(
		float(_player.get("_dash_time")) > 0.0 and roll_side < 0.0,
		"a lateral double tap rolls to the side that was tapped (%.0f)" % roll_side
	)
	Input.action_release(&"move_left")

	# In FIGHTER any direction is a jink, diagonals included. The stick is read in
	# the same world axes the flight model uses, so with the nose up-screen a tap
	# up is forward, down is backward, and up-right is the diagonal between them.
	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	for _i in 4:
		await get_tree().physics_frame
	var forward_push: Vector2 = _jink_push()
	_check(
		forward_push.x > 20.0 and absf(forward_push.y) < 2.0,
		"a double tap forward jinks along the nose (%.1f u/s)" % forward_push.x
	)
	Input.action_release(&"move_up")

	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_down")
	await get_tree().physics_frame
	Input.action_release(&"move_down")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_down")
	for _i in 4:
		await get_tree().physics_frame
	var back_push: Vector2 = _jink_push()
	_check(
		back_push.x < -20.0 and absf(back_push.y) < 2.0,
		"a double tap backward jinks against the nose (%.1f u/s)" % back_push.x
	)
	Input.action_release(&"move_down")

	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	Input.action_release(&"move_right")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	Input.action_press(&"move_right")
	for _i in 4:
		await get_tree().physics_frame
	var diagonal_push: Vector2 = _jink_push()
	_check(
		diagonal_push.x > 15.0 and diagonal_push.y > 15.0,
		"a diagonal double tap jinks on both axes (%.1f forward, %.1f right)"
		% [diagonal_push.x, diagonal_push.y]
	)
	Input.action_release(&"move_up")
	Input.action_release(&"move_right")

	# Leave the ship in GERWALK: the rest of the suite starts from the hover.
	await _reset_dash_gesture()
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(not _player.is_fighter(), "the double-tap check restores GERWALK")


## The transformation contract: two real modes, a switch that costs commitment,
## a fighter that flies at 180% on a stall-speed floor, a course that lags the
## nose into a skid, the same speed in every heading, a gun welded to the airframe,
## and a burner that shreds what it flies through.
func _test_transformation() -> void:
	_release_all_input()
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(not _player.is_fighter(), "the ship starts in GERWALK")

	# S1: the switch is a 0.28 s commitment, not an instant toggle.
	_player.call("_start_transform")
	await get_tree().physics_frame
	_check(not _player.is_fighter(), "the switch does not land in one frame")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the ship reaches FIGHTER after 0.28 s")

	# S3: 180% of the hover cruise, measured in airspeed, and the same whichever
	# way the ship is pointed.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 20.0
	Input.action_press(&"move_right")
	for _i in 20:
		await get_tree().physics_frame
	var fighter_speed: float = _player.velocity.length()
	_check(
		absf(fighter_speed / Player.MAX_SPEED - 1.8) < 0.05,
		"fighter cruise is %.0f%% of the hover's (%.1f u/s airspeed)"
		% [100.0 * fighter_speed / Player.MAX_SPEED, fighter_speed]
	)

	# FR-15 still holds at fighter speed: the camera lead saturates instead of
	# scaling with 180% of the hover cruise.
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = _player.camera.unproject_position(_player.global_position)
	_check(
		projected.distance_to(centre) < 16.0,
		"the camera keeps the fighter framed at 1.8x (%.1f px)" % projected.distance_to(centre)
	)

	# S4: the gun is bolted to the airframe. The right stick, which would aim in
	# GERWALK, must not move the shot off the nose.
	Input.action_press(&"aim_up")
	for _i in 2:
		await get_tree().physics_frame
	var nose: Vector3 = _player.get("_aim_direction")
	_check(nose.x > 0.99, "the gun stays on the nose in FIGHTER (x %.2f)" % nose.x)
	Input.action_release(&"aim_up")

	# S3: a reversal is an arc. One frame cannot turn 180 degrees, and the full
	# turn lands inside the 360-450 deg/s band.
	var before_turn: Vector3 = _player.get("_heading")
	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	var after_one: Vector3 = _player.get("_heading")
	_check(
		after_one.dot(before_turn) > 0.9,
		"one frame cannot reverse the heading (%.0f deg)"
		% rad_to_deg(after_one.angle_to(before_turn))
	)
	var yaw_before: float = atan2(-before_turn.z, before_turn.x)
	var peak_bank: float = 0.0
	var peak_lean: float = 0.0
	for _i in 30:
		await get_tree().physics_frame
		var roll: float = _player.get("_visual").rotation.x
		if absf(roll) > absf(peak_bank):
			peak_bank = roll
			var heading: Vector3 = _player.get("_heading")
			var right: Vector3 = Vector3(-heading.z, 0.0, heading.x)
			peak_lean = _player.get("_visual").global_transform.basis.y.dot(right)
	var reversed: Vector3 = _player.get("_heading")
	var turned: float = angle_difference(yaw_before, atan2(-reversed.z, reversed.x))
	_check(reversed.dot(before_turn) < -0.9, "the heading completes a 180 in about 0.45 s")
	Input.action_release(&"move_left")

	# The hull banks into the turn like a wing. A car yaws flat; a fighter drops
	# the wing on the inside of the turn and raises it when the stick centres, so
	# the airframe's own up vector leans the way the nose is going.
	_check(
		rad_to_deg(absf(peak_bank)) >= 35.0,
		"a fighter banks into the turn (%.1f deg)" % rad_to_deg(peak_bank)
	)
	_check(
		signf(peak_lean) == -signf(turned),
		"the wing drops on the inside of the turn (%.1f deg roll, %.0f deg turn)"
		% [rad_to_deg(peak_bank), rad_to_deg(turned)]
	)
	for _i in 40:
		await get_tree().physics_frame
	var levelled: float = absf(rad_to_deg(_player.get("_visual").rotation.x))
	_check(levelled < 4.0, "the fighter levels out when the turn ends (%.1f deg)" % levelled)

	# S4: fighter rounds leave faster, live 40% longer and keep a tight fan.
	var weapons: WeaponSystem = _player.get_node("Weapons")
	weapons.select(Arsenal.Kind.VULCAN)
	weapons.set("_cooldown", 0.0)
	_clear_projectiles()
	weapons.tick(0.016, _player.global_position, _player.global_position, reversed, true, true)
	var shots: Array[Projectile] = _player_projectiles()
	_check(shots.size() >= Arsenal.VULCAN_PELLETS, "the fighter vulcan still fans out")
	if shots.size() >= 2:
		var widest: float = 0.0
		for i in shots.size():
			for j in range(i + 1, shots.size()):
				var first: Vector3 = shots[i].get("_velocity")
				var second: Vector3 = shots[j].get("_velocity")
				widest = maxf(widest, rad_to_deg(first.angle_to(second)))
		var speed: float = shots[0].get("_velocity").length()
		var life: float = shots[0].get("_life")
		_check(
			absf(speed - Arsenal.VULCAN_SPEED * Arsenal.FIGHTER_SPEED_MULTIPLIER) < 1.0,
			"fighter rounds leave at %.0f u/s (1.35x)" % speed
		)
		_check(
			life > Arsenal.FIGHTER_RANGE_MULTIPLIER * Projectile.LIFETIME - 0.1,
			"fighter rounds carry 40%% more range (%.1f s of flight)" % life
		)
		_check(widest < 12.0, "the fighter fan closes to %.1f deg" % widest)

	# S4: and plasma loses the lock that makes it plasma in the hover.
	_clear_projectiles()
	var target: Enemy = _spawn_enemy(_player.global_position + reversed * 10.0)
	# The automatic battery would launch at that same target inside this tick and
	# look like a second plasma bolt, so park it while the count is measured.
	weapons.set("_missile_cooldown", 99.0)
	weapons.select(Arsenal.Kind.PLASMA)
	weapons.set("_cooldown", 0.0)
	weapons.tick(0.016, _player.global_position, _player.global_position, reversed, true, true)
	var bolts: Array[Projectile] = _player_projectiles()
	_check(bolts.size() == 1, "the fighter plasma still fires")
	if bolts.size() == 1:
		_check(bolts[0].get("_target") == null, "fighter plasma has no lock-on")
	weapons.set("_missile_cooldown", 0.0)
	_clear_projectiles()
	if target != null:
		target.queue_free()
	await get_tree().physics_frame

	# S5: the button is the spin on its own. Space must not step the ship -- a
	# dodge that teleports sideways under a key the player pressed to "come over"
	# is a movement they never asked for -- and the double tap is still the jink.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 30.0
	Input.action_press(&"aim_left")
	for _i in 2:
		await get_tree().physics_frame
	var heading_before: Vector3 = _player.get("_heading")
	var position_before: Vector3 = _player.global_position
	_player.call("_start_dash")
	for _i in 12:
		await get_tree().physics_frame
	var travelled: Vector3 = _player.global_position - position_before
	var lateral: float = travelled.dot(Vector3(-heading_before.z, 0.0, heading_before.x))
	var heading_after: Vector3 = _player.get("_heading")
	_check(
		absf(lateral) < 1.0,
		"the button roll spins without stepping the ship (%.1f units)" % lateral
	)
	_check(heading_after.dot(heading_before) > 0.99, "the roll leaves the nose where it was")
	_check(
		float(_player.get("_dash_time")) <= 0.0,
		"the button roll opens no jink window"
	)
	_check(_player.is_evading(), "the button roll still carries its i-frames")

	# The roll animation runs on its own, slower clock: it is still coming over,
	# and it is coming over to the side the aim picked.
	var spin: float = _player.get("_visual").rotation.x
	_check(
		spin < -1.0,
		"the roll is still turning when the spinner is done (%.0f deg)" % rad_to_deg(spin)
	)
	_check(
		float(_player.get("_roll_side")) < 0.0,
		"the roll remembers the side it went to"
	)

	# A tapped roll is still the jink: it steps to the side the tap asked for. The
	# tap is given in world axes, so with the nose on +X a stick pushed up-screen is
	# a step to the hull's own left. This is the entry the double-tap gesture calls.
	Input.action_release(&"aim_left")
	_player.set("_dash_cooldown", 0.0)
	_player.set("_roll_anim_time", 0.0)
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 30.0
	position_before = _player.global_position
	_player.call("_start_barrel_roll", Vector2.UP)
	_check(
		float(_player.get("_dash_time")) > 0.0,
		"a tapped roll opens the jink window"
	)
	for _i in 12:
		await get_tree().physics_frame
	travelled = _player.global_position - position_before
	lateral = travelled.dot(Vector3(-heading_before.z, 0.0, heading_before.x))
	_check(
		lateral < -2.0,
		"a tapped roll still steps left (%.1f units)" % lateral
	)

	# A centred stick repeats that side instead of defaulting to the right.
	_player.set("_dash_cooldown", 0.0)
	_player.set("_roll_anim_time", 0.0)
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 30.0
	_player.call("_start_dash")
	_check(
		float(_player.get("_roll_side")) < 0.0,
		"a neutral stick repeats the last side"
	)
	# And the slower spin lands back on the bank axis instead of parking a turn.
	for _i in 32:
		await get_tree().physics_frame
	var settle: float = _player.get("_visual").rotation.x
	_check(
		absf(settle) < 0.1,
		"the roll settles level when it ends (%.1f deg)" % rad_to_deg(settle)
	)

	# S6 was withdrawn: the burner no longer clears the sky in front of the nose.
	# The cone outlived its own mesh for a while, deleting projectiles nobody could
	# see a reason for, so this pins the absence instead of the rule.
	_player.set("_heading", Vector3.RIGHT)
	var front: Projectile = _spawn_enemy_bullet(_player.global_position + Vector3.RIGHT * 4.0)
	_player.set("_boosting", true)
	for _i in 2:
		await get_tree().physics_frame
	_check(
		front != null and is_instance_valid(front) and not front.is_queued_for_deletion(),
		"the burner no longer shreds enemy fire in front of the nose"
	)
	_player.set("_boosting", false)
	_clear_projectiles()
	await get_tree().physics_frame

	# S3: the fighter bleeds from cruise down to its stall speed in the old 0.35 s
	# and then keeps flying: drag, not a brake. The velocity is set to cruise along
	# the nose, so the airspeed starts at the spec number.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * Player.FIGHTER_SPEED
	var glide_speed: float = Player.FIGHTER_STALL_SPEED
	var stall_frames: int = 0
	while stall_frames < 40 and _flat_speed() > glide_speed + 0.6:
		await get_tree().physics_frame
		stall_frames += 1
	_check(
		absf(stall_frames / 60.0 - Player.FIGHTER_STOP_TIME) < 0.05,
		"fighter bleeds to stall speed in %.2f s" % (stall_frames / 60.0)
	)
	for _i in 6:
		await get_tree().physics_frame
	_check(
		absf(_flat_speed() - glide_speed) < 1.0,
		"the fighter glides at the stall floor (%.1f u/s)" % _flat_speed()
	)

	# S3: a coast still covers ground. If the floor regresses to zero, the ship
	# parks on the planet and the planet stops rolling.
	var glide_from: Vector3 = _player.global_position
	for _i in 30:
		await get_tree().physics_frame
	var glided: float = _flat_distance(_player.global_position, glide_from)
	_check(glided > 8.0, "coasting still covers ground (%.1f units in 0.5 s)" % glided)

	# S3: the nose turns faster than the air does. Asking for a reversal, the ship
	# keeps travelling the old way while the nose already points the new one.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * Player.FIGHTER_SPEED
	Input.action_press(&"move_left")
	for _i in 12:
		await get_tree().physics_frame
	var skid: float = _sideways_airspeed()
	_check(absf(skid) > 20.0, "a reversal skids across the nose (%.1f u/s)" % skid)
	Input.action_release(&"move_left")
	for _i in 60:
		await get_tree().physics_frame
	skid = _sideways_airspeed()
	_check(
		absf(skid) < 3.0,
		"the skid bleeds out once the nose settles (%.1f u/s)" % skid
	)

	# S3: every heading flies the same speed. A world-space wind used to make the
	# same run 15% faster downwind than upwind, and the wing sweep read that as
	# wings swept on one side of the screen only. The window is cleared of combat:
	# enemies draw from the global RNG and a hit pushes the ship 11 u/s, which
	# moved the measurement by more than the tolerance.
	_clear_enemies()
	_clear_projectiles()
	_player.set("_invulnerable", 1000.0)
	await get_tree().physics_frame
	var coast: Array[float] = []
	for heading in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		_player.set("_heading", heading)
		_player.velocity = Vector3.ZERO
		for _i in 60:
			await get_tree().physics_frame
		coast.append(_flat_speed())
	_player.set("_invulnerable", 0.0)
	_check(
		absf(coast[0] - Player.FIGHTER_STALL_SPEED) < 1.0,
		"the glide holds the stall floor (%.1f u/s)" % coast[0]
	)
	var spread: float = coast.max() - coast.min()
	_check(
		spread < 0.5,
		"the glide is the same in every heading (spread %.2f u/s)" % spread
	)

	# S1: back to the hover, and the gun is free the moment it lands.
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(not _player.is_fighter(), "the ship returns to GERWALK")

	# S3: the hover holds station. A push that the fighter would ride is killed by
	# the hover's friction, which is its whole reason to exist next to the fighter.
	_player.velocity = Vector3(21.0, 0.0, 0.0)
	for _i in 20:
		await get_tree().physics_frame
	_check(
		_flat_speed() < 0.2,
		"the hover holds station after a push (%.2f u/s)" % _flat_speed()
	)

	Input.action_press(&"aim_up")
	for _i in 3:
		await get_tree().physics_frame
	_check(
		_player.get("_aim_direction").z < -0.9,
		"the gun aims freely again in GERWALK"
	)
	Input.action_release(&"aim_up")
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame


## The GERWALK silhouette is a skeleton pose, not a second mesh: the nacelles swing
## down and outboard with the nozzles ahead of the wing root, where the near-overhead
## camera can see them, the gunpod rides in the right hand, and FIGHTER folds both
## back into the airframe without dropping anything through the planet.
func _test_gerwalk_silhouette() -> void:
	var model: PlayerModel = _player.get("_model") as PlayerModel
	var pod: Node3D = _player.get("_gunpod")
	var hull: Node3D = _player.get("_visual")
	_check(model != null, "the airframe is the imported model")
	if model == null or pod == null or hull == null:
		return

	var feet: Array[Vector3] = model.nozzle_anchors()
	_check(feet.size() == 2, "the airframe carries two legs")
	if feet.size() < 2:
		return
	_check(
		absf(feet[0].z + feet[1].z) < 0.05,
		"the legs splay symmetrically (z %.2f / %.2f)" % [feet[0].z, feet[1].z]
	)
	_check(absf(feet[0].z) > 0.45, "the legs stand wide (z %.2f)" % absf(feet[0].z))
	_check(feet[0].y < -0.2, "the legs hang below the hull (y %.2f)" % feet[0].y)
	_check(feet[0].x > -0.5, "the feet leave the tail fold (x %.2f)" % feet[0].x)
	var sole: float = hull.to_global(feet[0]).y - 0.15
	_check(
		sole > Arena.GROUND_Y + 0.2,
		"the soles stay clear of the ground (%.2f vs %.2f)" % [sole, Arena.GROUND_Y]
	)

	# The gunner hold brings the right arm out, so the pod has to be in the hand
	# and the hand in front of the wing root, not trailing the tail.
	var hand: Vector3 = model.to_global(model.hand_anchor())
	_check(
		pod.global_position.distance_to(hand) < 0.05,
		"the gunpod is in the right hand in GERWALK"
	)
	var held: Vector3 = hull.to_local(pod.global_position)
	_check(held.x > 0.3, "the gunpod reaches ahead of the wing root (x %.2f)" % held.x)
	_check(held.z > 0.1, "the gunpod rides the right side (z %.2f)" % held.z)

	# GERWALK is a hover, not a wing: it flies sideways and backwards as happily as
	# forwards, so a tip trail there would say nothing about anything. There is no
	# wingtip vapour in that mode at all, at any throttle. The measurement is driven
	# directly so the check does not depend on the flight model's timing.
	var frame: float = 1.0 / 60.0
	_player.velocity = Vector3.RIGHT * Player.MAX_SPEED
	_check(
		is_zero_approx(float(_player.call("_wingtip_vapour"))),
		"GERWALK leaves the tips clean at cruise"
	)
	_player.velocity = Vector3.RIGHT * (Player.MAX_SPEED + Player.ACCELERATION * frame)
	_check(
		is_zero_approx(float(_player.call("_wingtip_vapour"))),
		"GERWALK leaves the tips clean while it gains speed"
	)
	# The strips are wiped, not merely faded: a trail laid down in FIGHTER would
	# otherwise hang in the air for its whole lifetime after the switch.
	var gerwalk_trails: Array = _player.get("_wingtip_trails")
	for trail in gerwalk_trails:
		(trail.get("points") as Array).append(Vector3.ONE)
		(trail.get("born") as Array).append(0.0)
	_player.call("_update_wingtip_trails", frame)
	var wiped: bool = true
	for trail in gerwalk_trails:
		wiped = wiped and (trail.get("points") as Array).is_empty()
	_check(wiped, "the strips are wiped outside FIGHTER")
	_player.velocity = Vector3.ZERO

	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the silhouette test reaches FIGHTER")
	_check(
		float(_player.get("_mode_blend")) > 0.99,
		"the pose arrives with the rules (blend %.2f)" % float(_player.get("_mode_blend"))
	)
	var tucked: Vector3 = model.nozzle_anchors()[0]
	_check(tucked.x < -1.0, "FIGHTER folds the legs back along the fuselage (x %.2f)" % tucked.x)
	_check(tucked.y > -0.4, "FIGHTER lifts the feet into the tail (y %.2f)" % tucked.y)
	var stowed: Vector3 = hull.to_local(pod.global_position)
	_check(absf(stowed.z) < 0.15, "FIGHTER stows the gunpod on the centreline (z %.2f)" % stowed.z)
	_check(stowed.y < -0.2, "the stowed gunpod rides under the belly (y %.2f)" % stowed.y)

	# The wings answer speed, not the mode: nearly straight at the glide floor, a
	# clear contraction at cruise, and the rest of the sweep once the ship is
	# pushed past it. Driving the visual directly keeps the check out of the flight
	# model's hands, and a zero delta poses the current speed instead of animating.
	var aim: Vector3 = _player.get("_aim_direction")
	_player.velocity = aim * Player.FIGHTER_STALL_SPEED
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees < 4.0,
		"the wings stay nearly straight at the glide floor (%.1f deg)" % model.sweep_degrees
	)
	# Eased, not linear: halfway to cruise the wings are still well short of half
	# the cruise contraction, so the sweep reads as speed rather than as throttle.
	_player.velocity = aim * (Player.FIGHTER_SPEED * 0.5)
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees < Player.WING_SWEEP_CRUISE * 0.4,
		"the wings stay open at half cruise (%.1f deg)" % model.sweep_degrees
	)
	_player.velocity = aim * (Player.FIGHTER_SPEED - 1.0)
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees > 10.0 and model.sweep_degrees < 18.0,
		"the wings contract at cruise (%.1f deg)" % model.sweep_degrees
	)
	_player.velocity = aim * (Player.FIGHTER_BOOST_SPEED - 2.0)
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees > 30.0,
		"the wings sweep past cruise (%.1f deg)" % model.sweep_degrees
	)

	# The angle is a mechanism, not a readout: the throttle jumps in a couple of
	# frames and the wing still has to travel there.
	_player.velocity = aim * Player.FIGHTER_STALL_SPEED
	_player.call("_update_afterburner_visual", 0.0)
	var settled: float = model.sweep_degrees
	_player.velocity = aim * Player.FIGHTER_BOOST_SPEED
	_player.call("_update_afterburner_visual", 1.0 / 60.0)
	_check(
		model.sweep_degrees > settled
		and model.sweep_degrees < Player.WING_SWEEP_BACK - 10.0,
		"the wings travel to the stop instead of snapping (%.1f deg in one frame)"
		% model.sweep_degrees
	)
	_player.velocity = Vector3.ZERO

	# The speed cue is a ribbon off each tip. The wedge that used to draw the burst
	# is gone; the rule still eats enemy fire (S6), but nothing is painted in front
	# of the nose any more. The pose is pinned to cruise first: the wingtip is a
	# chord and which corner is outermost depends on the sweep, so the point is
	# calibrated -- and checked -- in the pose the vapour actually lives in.
	model.pose_mode(0.0, Player.WING_SWEEP_CRUISE)
	var tips: Array[Vector3] = model.wing_tips()
	var hardpoints: Array[Vector3] = model.wing_anchors()
	_check(tips.size() == 2, "the airframe carries two wingtips")
	if tips.size() == 2 and hardpoints.size() == 2:
		_check(
			tips[0].length() > hardpoints[0].length() + 0.2,
			"the vapour leaves from the tip, past the hardpoint"
		)
		# The point sits on the wing, not past it: the outer edge at cruise is where
		# the silhouette ends, and a corner measured at rest floats outside it.
		_check(
			tips[0].z < -1.6 and tips[1].z > 1.6,
			"the vapour leaves from the outer edge at cruise (z %.2f / %.2f)"
			% [tips[0].z, tips[1].z]
		)
	var trails: Array = _player.get("_wingtip_trails")
	_check(trails.size() == 2, "the fighter carries a ribbon on each tip")
	if trails.size() == 2 and tips.size() == 2:
		# The tips answer airspeed now, not the burner: the vapour is the cue that
		# the ship is moving, so it starts at the middle of the throttle.
		_player.call("_clear_wingtip_trails")
		_player.velocity = aim * Player.FIGHTER_SPEED * 0.5
		_check(
			is_zero_approx(float(_player.call("_wingtip_vapour"))),
			"the tips are clean at half throttle"
		)
		_player.velocity = aim * Player.FIGHTER_SPEED
		_check(
			float(_player.call("_wingtip_vapour")) > 0.9,
			"the tips vapour at cruise"
		)

		# A turn is the case the forward component got wrong: the nose outruns the
		# course, so the velocity points well off the nose while the wing is still
		# moving through the air at cruise. Reading the projection made the vapour
		# die at about 70 deg of skid, which is a hard turn, not a slow ship.
		_player.velocity = aim.rotated(Vector3.UP, deg_to_rad(70.0)) * Player.FIGHTER_SPEED
		_check(
			float(_player.call("_wingtip_vapour")) > 0.9,
			"the tips still trail through a turn's skid"
		)

		_player.velocity = aim * Player.FIGHTER_SPEED
		_player.call("_update_wingtip_trails", 1.0 / 60.0)
		var visual: Node3D = _player.get("_visual") as Node3D
		var tip: Vector3 = visual.global_transform * tips[0]
		var samples: Array = trails[0].get("points")
		var first: Vector3 = samples[0] if samples.size() > 0 else Vector3.ZERO
		_check(
			samples.size() == 1 and first.distance_to(tip) < 0.01,
			"the ribbon starts on the wingtip"
		)

		# Walk the tip along and watch the strip build: a particle wake could only
		# ever be as dense as its spawn rate, so what is checked is that the ribbon
		# is one surface ending exactly where the tip is.
		var head: Vector3 = tip
		for _i in 6:
			head += Vector3(0.0, 0.0, 1.0)
			_player.call("_advance_wingtip_trail", trails[0], head, 1.0, 1.0 / 60.0)
		var strip: ImmediateMesh = trails[0].get("mesh") as ImmediateMesh
		_check(
			strip != null and strip.get_surface_count() == 1,
			"the tip vapour is one continuous strip"
		)
		samples = trails[0].get("points")
		var last: Vector3 = samples[samples.size() - 1] if samples.size() > 0 else Vector3.ZERO
		_check(
			samples.size() >= 7 and last.distance_to(head) < 0.01,
			"the ribbon ends on the wingtip (%d samples)" % samples.size()
		)

		# Slowing down stops the head and retires the tail by age.
		for _i in 40:
			_player.call("_advance_wingtip_trail", trails[0], head, 0.0, 1.0 / 30.0)
		_check(
			(trails[0].get("points") as Array).is_empty(),
			"the ribbon dissolves once the ship slows"
		)
		_player.velocity = Vector3.ZERO

	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	var dropped: Vector3 = model.nozzle_anchors()[0]
	_check(
		not _player.is_fighter() and dropped.y < -0.2,
		"the switch back drops the legs again (y %.2f)" % dropped.y
	)


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
	weapons.set("_cooldown", 0.0)
	Sfx.reset_counts()
	weapons.tick(0.0, origin, origin, aim, true)
	_check(
		Sfx.played(&"vulcan") == 1,
		"the gunpod asks for one burst sound per shot (got %d)" % Sfx.played(&"vulcan")
	)
	_clear_projectiles()

	# Plasma: one zap per bolt.
	weapons.select(Arsenal.Kind.PLASMA)
	weapons.set("_cooldown", 0.0)
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
		weapons.set("_salvo", 2)
		weapons.set("_missile_cooldown", 0.0)
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
		weapons.set("_missile_cooldown", 0.0)
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
	weapons.set("_bombs", Arsenal.BOMB_MAX_CHARGES)
	Sfx.reset_counts()
	_check(weapons.fire_bomb(origin), "the bomb fires for the audio check")
	_check(Sfx.played(&"bomb") == 1, "the bomb asks for its blast")
	weapons.set("_decoy_cooldown", 0.0)
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
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)

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


## The left of the HUD is one column of readouts, so every row has to own its band.
## Two controls sharing a rect draw on top of each other, which is exactly how
## DECOY READY ended up printed over GERWALK: the decoy row was laid out at the
## mode row's offsets instead of the next slot down the stack.
##
## The rects are read from the live nodes rather than from the scene file, because
## the bug was a layout mistake and only the resolved geometry catches it. A
## degenerate rect would make every intersection trivially false, so the heights are
## checked first: the test has to fail for the right reason.
func _test_hud_layout() -> void:
	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var names: Array[String] = [
		"%LevelLabel",
		"%LevelBar",
		"%SalvoLabel",
		"%DecoyLabel",
		"%ModeLabel",
		"%WeaponLabel",
		"%TurboBar",
		"%HealthBar",
		"%BombPips",
	]
	var labels: Array[String] = []
	var rects: Array[Rect2] = []
	for name in names:
		var control: Control = hud.get_node(name) as Control
		_check(control != null, "the HUD has a %s readout" % name)
		if control == null:
			return
		labels.append(name)
		rects.append(control.get_global_rect())

	var flat: Array[String] = []
	for index in rects.size():
		if rects[index].size.y <= 0.0:
			flat.append(labels[index])
	_check(
		flat.is_empty(),
		"every readout has a band of its own (%s)" % ", ".join(flat)
	)

	var clashes: Array[String] = []
	for index in rects.size():
		for other in range(index + 1, rects.size()):
			if rects[index].intersects(rects[other]):
				clashes.append("%s over %s" % [labels[index], labels[other]])
	_check(
		clashes.is_empty(),
		"no two readouts share a band (%s)" % ", ".join(clashes)
	)


## The pause screen is the player's way out of a run that is still alive: Escape
## opens it at any moment, the world stops behind it, and RESUME hands the fight
## back exactly where it was left. The menu is the boot scene, so the test also pins
## the half of it a paused run must not offer: a destination that would throw the
## current arena away.
func _test_pause_menu() -> void:
	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	# The menu reads the pad and the livery when it is built, so it is pointed at the
	# scratch file before any press: the suite never reads the real settings.
	hud.set("pause_settings_path", TEST_SETTINGS)

	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true

	_check(not get_tree().paused, "a live run is not paused")

	hud._unhandled_input(cancel)
	await get_tree().process_frame

	var menu: MainMenu = _pause_overlay(hud)
	_check(menu != null, "escape opens the menu over the run")
	_check(get_tree().paused, "the menu stops the world behind it")
	if menu == null:
		# A menu that never arrived would leave the tree paused for every later test,
		# so the failure is repaired before the suite goes on.
		get_tree().paused = false
		return

	var resume: Button = menu.get_node("%ResumeButton") as Button
	var continue_button: Button = menu.get_node("%ContinueButton") as Button
	var start_button: Button = menu.get_node("%StartButton") as Button
	var options_button: Button = menu.get_node("%OptionsButton") as Button
	var options: Control = menu.get_node("%Options") as Control
	_check(menu.in_game, "the menu knows it was opened over a run")
	_check(
		resume != null and resume.visible and resume.has_focus(),
		"resume is the answer the pause screen offers first"
	)
	_check(
		continue_button != null and not continue_button.visible,
		"a paused run does not offer continue"
	)
	_check(
		start_button != null and not start_button.visible,
		"a paused run does not offer a fresh planet"
	)
	_check(options != null, "the pause screen keeps the options panel")

	# Stopped, not merely covered: the ship keeps the position it had when Escape
	# arrived, because nothing in the run processes while the tree is paused.
	var frozen_at: Vector3 = _player.global_position
	await get_tree().physics_frame
	_check(
		_player.global_position.is_equal_approx(frozen_at),
		"the ship does not fly while the menu is open"
	)

	options_button.pressed.emit()
	await get_tree().process_frame
	_check(options.visible, "options opens from the pause screen")
	menu._unhandled_input(cancel)
	await get_tree().process_frame
	_check(not options.visible, "escape closes the panel first")
	_check(
		get_tree().paused,
		"and the panel's escape does not resume the run"
	)

	if resume == null:
		menu.queue_free()
		get_tree().paused = false
		return
	resume.pressed.emit()
	await get_tree().process_frame
	_check(not get_tree().paused, "resume restarts the fight")
	_check(_pause_overlay(hud) == null, "and takes the menu with it")

	# The hum was silenced by hand when the menu opened, so the ship has to claim it
	# back on its first live frame rather than being left in a quiet cockpit. The
	# signal fires before the ship processes, so the second frame is the first one
	# that can observe the claim.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(Sfx.engine_active(), "the engine hum comes back with the ship")


## One menu at a time, and it is a child of the HUD because the HUD owns the run.
func _pause_overlay(hud: CanvasLayer) -> MainMenu:
	for child in hud.get_children():
		if child is MainMenu:
			return child
	return null


## The run pays for every kill, and the HUD projects the total. The three hulls are
## worth different amounts because they are different fights, not because of a
## global multiplier: a kill is worth what the target was.
func _test_score() -> void:
	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var label: Label = hud.get_node("%ScoreLabel") as Label
	_check(label != null, "the HUD shows the score")
	if label == null:
		return

	var totals: Array[int] = []
	var listener: Callable = func(total: int) -> void: totals.append(total)
	GlobalEventBus.score_changed.connect(listener)

	_clear_enemies()
	await get_tree().physics_frame

	var turret: Enemy = _spawn_turret(Vector3(20.0, 0.0, 0.0))
	var launcher: MissileEnemy = _spawn_missile_enemy(Vector3(0.0, 0.0, 24.0))
	var interceptor: FighterEnemy = _spawn_fighter_enemy(Vector3(-24.0, 0.0, 0.0))
	await get_tree().physics_frame

	var before: int = _arena.score()
	if turret != null:
		turret.take_damage(turret.current_hp())
		_check(
			_arena.score() == before + turret.score_value(),
			"a turret kill pays %d points (score %d)"
			% [turret.score_value(), _arena.score()]
		)
		before = _arena.score()

	if launcher != null:
		launcher.take_damage(launcher.current_hp())
		_check(
			_arena.score() == before + launcher.score_value(),
			"a launcher kill pays %d points (score %d)"
			% [launcher.score_value(), _arena.score()]
		)
		before = _arena.score()

	if interceptor != null:
		interceptor.take_damage(interceptor.current_hp())
		_check(
			_arena.score() == before + interceptor.score_value(),
			"an interceptor kill pays %d points (score %d)"
			% [interceptor.score_value(), _arena.score()]
		)

	_check(
		not totals.is_empty() and totals[totals.size() - 1] == _arena.score(),
		"the score reaches the HUD through the bus (last %d)" % _arena.score()
	)
	_check(
		label.text == "SCORE %06d" % _arena.score(),
		"the HUD prints the run's score (%s)" % label.text
	)
	GlobalEventBus.score_changed.disconnect(listener)

	for blast in _death_blasts():
		blast.queue_free()
	await get_tree().physics_frame


## S4, S5, S6, S8, S9, S13: the mothership arrives on the run threshold, is solid,
## is fought as three independently attackable sections, feeds its bar, escalates at
## 60 percent, and comes apart at the hull's own scale when the third section falls.
func _test_boss() -> void:
	_clear_enemies()
	_clear_projectiles()
	# The spawner is parked for the test: the arrival is what is under test, and a
	# fighter wandering into the set piece would make the projectile counts ambiguous.
	_arena.set("_spawn_timer", 1.0e9)
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
	_arena.set("_run_kills", Arena.BOSS_KILL_THRESHOLD - 1)
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
		var pool: Array[WeaponSystem.LockSlot] = lock_weapons.call(
			"_radar_pool", radar_origin, -bow_dir
		)
		var hull_slots: Array[WeaponSystem.LockSlot] = []
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
			lock_weapons.set("_salvo", Arsenal.MISSILE_MAX_SALVO)
			lock_weapons.call("_sync_marks", hull_slots)
			_check(
				_tally_texts() == ["×2", "×3", "×3"],
				"the three marks promise the 3/3/2 split (%s)" % str(_tally_texts())
			)
			var marked_after: Array = lock_weapons.get("_marked")
			_check(
				marked_after.size() == Boss.SECTION_COUNT,
				"the rack carries one mark per anchor (%d)" % marked_after.size()
			)
			lock_weapons.call("_discharge")

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


func _release_all_input() -> void:
	for action: StringName in [
		&"move_left", &"move_right", &"move_up", &"move_down",
		&"aim_left", &"aim_right", &"aim_up", &"aim_down",
		&"fire", &"boost", &"dash",
	]:
		Input.action_release(action)


## Puts the dash gesture back to a known state: no cooldown, no armed tap, and a
## released stick, so the next press is a rising edge.
func _reset_dash_gesture() -> void:
	_release_all_input()
	_player.velocity = Vector3.ZERO
	_player.set("_dash_cooldown", 0.0)
	_player.set("_dash_time", 0.0)
	# The spin clock outlives the step, so it has to be cleared too or the next
	# check would start mid-roll and read the previous roll's side.
	_player.set("_roll_anim_time", 0.0)
	_player.set("_tap_timer", 0.0)
	_player.set("_move_engaged", false)
	await get_tree().physics_frame


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
			absf(distance - Enemy.ORBIT_RADIUS) < 8.0,
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
		for child in get_children():
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


## The strongest dense point and the thinnest gap on a coarse grid outside the
## opening clearing. Scanning is what keeps the test honest about the current tuning.
func _find_cloud_point(field: CloudField, want_dense: bool) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_score: float = -INF
	for z in range(160, 521, 10):
		for x in range(-520, 521, 10):
			var point: Vector3 = Vector3(float(x), 0.0, float(z))
			var density: float = field.density_at(point)
			if want_dense and density < CloudField.DENSE_THRESHOLD:
				continue
			if not want_dense and density >= CloudField.DENSE_THRESHOLD:
				continue
			var score: float = density if want_dense else -density
			if score > best_score:
				best_score = score
				best = point
	return best


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
		for child in get_children():
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
	add_child(wall)
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


## The burner is a tank, not a cooldown, so this drives the whole cycle in one
## run: burn, coast, burn out, release and re-arm. Those four states are the
## mechanic; checking a single one of them would miss the transitions.
## The wake is a visual, but it is wired to the flight model: two emitters, one per
## nozzle, and the density has to answer a change in speed rather than a clock or
## the speed itself. The puffs are left in world space, which is what turns a point
## emitter into a trail.
func _test_exhaust_trail() -> void:
	var smoke: Array = _player.get("_smoke")
	_check(smoke.size() == 2, "the airframe carries one exhaust emitter per nozzle")
	if smoke.size() < 2:
		return
	var first: GPUParticles3D = smoke[0] as GPUParticles3D
	_check(first != null and not first.local_coords, "the puffs stay where they were dropped")
	_check(
		first.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the trail casts no shadow on the hull"
	)

	# The wake marks a change in speed, not the speed itself. A steady throttle
	# leaves the nozzles clean; a puff is born at the nozzle and stays there, so a
	# standing ship would otherwise wear its own trail.
	_player.call("_update_smoke", 0.0)
	var steady: float = first.amount_ratio
	_player.call("_update_smoke", Player.FIGHTER_ACCELERATION)
	var climbing: float = first.amount_ratio
	_player.call("_update_smoke", -Player.FIGHTER_ACCELERATION)
	var coasting: float = first.amount_ratio
	_check(is_zero_approx(steady), "a steady throttle leaves the nozzles clean")
	_check(
		climbing > steady and is_zero_approx(coasting),
		"the wake marks the climb, not the speed (%.2f climbing, %.2f coasting)"
		% [climbing, coasting]
	)

	var model: PlayerModel = _player.get("_model") as PlayerModel
	var anchor: Vector3 = model.nozzle_anchors()[0]
	_check(
		first.position.distance_to(anchor) < 0.01,
		"the emitter rides its nozzle"
	)


## The ship is a mirror lit by one sun, so the two legs present opposite facets and
## one spine crushed to black while its twin read warm grey: one leg wearing a
## shadow the other did not have. The fill rides the camera and culls on the
## airframe layer. Both halves matter -- a fill that lit the arena would change the
## scene, and meshes left off the layer would not receive it at all.
func _test_airframe_lighting() -> void:
	var rig: Node = _player.camera.get_parent()
	var fill: DirectionalLight3D = rig.get_node_or_null("FillLight") as DirectionalLight3D
	_check(fill != null, "the camera rig carries the airframe fill light")
	if fill == null:
		return
	_check(not fill.shadow_enabled, "the fill casts no shadow of its own")
	_check(
		fill.light_cull_mask == PlayerModel.AIRFRAME_LAYER_MASK,
		"the fill reaches the airframe layer and nothing else"
	)

	var model: PlayerModel = _player.get("_model") as PlayerModel
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	var on_layer: bool = not meshes.is_empty()
	for node in meshes:
		if (node as MeshInstance3D).layers != PlayerModel.AIRFRAME_LAYER_MASK:
			on_layer = false
			break
	_check(on_layer, "every airframe mesh sits on the layer the fill targets")


## The scope is the one HUD element that reads positions instead of events, so the
## test drives the real query: a turret placed off the starboard bow must paint
## right of the centre, one placed aft must paint below it, and a contact past the
## range must paint nothing. The world-fixed mapping is the part worth pinning: a
## heading-up scope would still pass a "one blip" check and be wrong on screen.
func _test_radar() -> void:
	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var radar: Radar = hud.get_node("%Radar") as Radar
	_check(radar != null, "the HUD carries a radar scope")
	if radar == null:
		return

	_check(
		radar.anchor_left == 1.0 and radar.anchor_top == 1.0,
		"the scope is anchored to the bottom-right corner"
	)

	# The streamer drops a turret every two seconds; one appearing mid-test would
	# be indistinguishable from the contact the test placed.
	var spawn_timer: float = float(_arena.get("_spawn_timer"))
	_arena.set("_spawn_timer", 999.0)
	_clear_enemies()
	await _wait_frames(2)
	_check(radar.contact_offsets().is_empty(), "an empty sky paints no blips")

	var contact: Enemy = _spawn_enemy(_player.global_position + Vector3(30.0, 0.0, 0.0))
	await _wait_frames(2)
	var offsets: Array[Vector2] = radar.contact_offsets()
	_check(offsets.size() == 1, "a contact inside the range paints one blip")
	if offsets.size() == 1:
		_check(
			offsets[0].x > 0.0 and absf(offsets[0].y) < 0.5,
			"a contact to starboard paints right of centre"
		)

	if contact != null:
		contact.global_position = _player.global_position + Vector3(0.0, 0.0, 20.0)
	await _wait_frames(1)
	offsets = radar.contact_offsets()
	_check(
		offsets.size() == 1 and offsets[0].y > 0.0,
		"a contact aft paints below centre"
	)

	_check(
		radar.detects(_player.global_position + Vector3(10.0, 0.0, 0.0)),
		"a point inside the range is detected"
	)
	_check(
		not radar.detects(
			_player.global_position + Vector3(0.0, 0.0, Radar.DETECTION_RANGE + 1.0)
		),
		"a point past the range is not detected"
	)

	var nose: Vector3 = _player.nose_direction()
	var expected: Vector2 = Vector2(nose.x, nose.z).normalized()
	_check(
		radar.marker_direction().distance_to(expected) < 0.01,
		"the marker points where the nose points"
	)

	_clear_enemies()
	_arena.set("_spawn_timer", spawn_timer)
	await _wait_frames(2)


func _test_afterburner() -> void:
	var turbo_events: Array = []
	var handler: Callable = func(current: float, maximum: float) -> void:
		turbo_events.append(Vector2(current, maximum))
	GlobalEventBus.player_turbo_changed.connect(handler)

	_check(
		is_equal_approx(float(_player.get("_turbo")), Player.TURBO_MAX),
		"the turbo reserve starts full"
	)

	Input.action_press(&"move_right")
	Input.action_press(&"boost")
	var base_fov: float = _player.camera.fov
	for _i in 90:
		await get_tree().physics_frame

	var boosting_fov: float = _player.camera.fov
	var boosting_speed: float = _flat_speed()
	var spent: float = float(_player.get("_turbo"))
	Input.action_release(&"boost")

	_check(
		boosting_speed > Player.MAX_SPEED * 1.1,
		"the afterburner beats normal top speed (%.1f u/s)" % boosting_speed
	)
	_check(
		boosting_fov > base_fov + 1.0,
		"burning widens the lens as a speed cue (%.1f -> %.1f)" % [base_fov, boosting_fov]
	)
	_check(
		spent < Player.TURBO_MAX,
		"the burner spends the reserve (%.0f left)" % spent
	)

	for _i in 60:
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	var refilled: float = float(_player.get("_turbo"))
	_check(
		refilled > spent,
		"the reserve refills off the burner (%.0f -> %.0f)" % [spent, refilled]
	)

	# Burnout: with almost nothing left the burner must cut out and hand the ship
	# back to normal thrust instead of holding the fast speed for free.
	_player.set("_turbo", 3.0)
	Input.action_press(&"move_right")
	Input.action_press(&"boost")
	for _i in 20:
		await get_tree().physics_frame
	var burnt_out_speed: float = _flat_speed()
	_check(
		burnt_out_speed <= Player.MAX_SPEED + 0.5,
		"burnout hands the ship back to normal speed (%.1f u/s)" % burnt_out_speed
	)

	# Re-arm: releasing the button clears the lockout, so a refilled reserve can
	# burn again on the next press.
	Input.action_release(&"boost")
	for _i in 60:
		await get_tree().physics_frame
	Input.action_press(&"boost")
	for _i in 30:
		await get_tree().physics_frame
	var rearmed_speed: float = _flat_speed()
	Input.action_release(&"boost")
	Input.action_release(&"move_right")

	_check(
		rearmed_speed > Player.MAX_SPEED * 1.1,
		"releasing the burner re-arms it (%.1f u/s)" % rearmed_speed
	)
	_check(not turbo_events.is_empty(), "turbo changes reach the event bus")

	GlobalEventBus.player_turbo_changed.disconnect(handler)
	for _i in 40:
		await get_tree().physics_frame


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
	var parked_cooldown: float = weapons.get("_missile_cooldown")
	weapons.set("_missile_cooldown", 99.0)
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
	weapons.set("_missile_cooldown", parked_cooldown)

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
	add_child(target)
	target.global_position = base + Vector3(0.0, 0.0, -32.0)

	var scene: PackedScene = load("res://combat/projectile.tscn")
	var missile: Projectile = scene.instantiate() as Projectile
	add_child(missile)
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
	add_child(host)
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
	weapons.set("_missile_cooldown", 0.0)

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
	var active: Variant = weapons.get("_active_mark")
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
	weapons.set("_missile_cooldown", 0.0)

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


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _unique_count(values: Array) -> int:
	var seen: Array = []
	for value in values:
		if not seen.has(value):
			seen.append(value)
	return seen.size()


## The tally each lock box shows, sorted. That text is the only thing on screen
## that promises how many missiles a contact will take, so the smoke test reads it
## the way the player does.
func _tally_texts() -> Array[String]:
	var texts: Array[String] = []
	for node in get_tree().get_nodes_in_group(&"lock_reticle"):
		var reticle: LockReticle = node as LockReticle
		var label: Label3D = reticle.get_node_or_null(^"LockNumber") as Label3D
		texts.append("?" if label == null else label.text)
	texts.sort()
	return texts


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


func _mesh_parts(node: Node) -> int:
	var total: int = 0
	for child in node.get_children():
		if child is MeshInstance3D:
			total += 1
		total += _mesh_parts(child)
	return total


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
		GlobalEventBus.enemy_killed.emit(Enemy.SCORE_VALUE)
	await get_tree().physics_frame
	_check(
		weapons.bomb_charges() == before + 1,
		"%d kills refund one charge (%d -> %d)"
		% [Arsenal.BOMB_KILLS_PER_CHARGE, before, weapons.bomb_charges()]
	)

	for _i in Arsenal.BOMB_KILLS_PER_CHARGE * Arsenal.BOMB_MAX_CHARGES:
		GlobalEventBus.enemy_killed.emit(Enemy.SCORE_VALUE)
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
	add_child(dummy)
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
	add_child(orb)
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


func _spawn_enemy(position: Vector3) -> Enemy:
	var scene: PackedScene = load("res://entities/enemy/turret.tscn")
	if scene == null:
		return null
	var enemy: Enemy = scene.instantiate() as Enemy
	_arena.add_child(enemy)
	enemy.global_position = position
	return enemy


func _spawn_enemy_bullet(position: Vector3) -> Projectile:
	var scene: PackedScene = load("res://combat/projectile.tscn")
	var bullet: Projectile = scene.instantiate() as Projectile
	add_child(bullet)
	bullet.global_position = position
	bullet.setup(Vector3(1.0, 0.0, 0.0), 20.0, Projectile.Team.ENEMY, 1)
	return bullet


## A player shot, built the way the vulcan builds one: same scene, same team, same
## layer the interception check depends on.
func _spawn_player_bullet(position: Vector3, direction: Vector3) -> Projectile:
	var scene: PackedScene = load("res://combat/projectile.tscn")
	var bullet: Projectile = scene.instantiate() as Projectile
	add_child(bullet)
	bullet.global_position = position
	bullet.setup(direction, 40.0, Projectile.Team.PLAYER, 1)
	return bullet


## A guided enemy shot, built the way the launcher builds one, so the decoy check
## exercises the same projectile contract the enemy actually fires.
func _spawn_enemy_missile(position: Vector3, target: Node3D) -> Projectile:
	var scene: PackedScene = load("res://combat/projectile.tscn")
	var missile: Projectile = scene.instantiate() as Projectile
	add_child(missile)
	missile.global_position = position
	var direction: Vector3 = target.global_position - position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = Vector3.FORWARD
	missile.setup(
		direction.normalized(),
		MissileEnemy.MISSILE_SPEED,
		Projectile.Team.ENEMY,
		MissileEnemy.MISSILE_DAMAGE,
		MissileEnemy.MISSILE_SIZE,
		target,
		MissileEnemy.MISSILE_TURN_RATE,
		Color(0.0, 0.0, 0.0, 0.0),
		MissileEnemy.MISSILE_LIFETIME,
		Projectile.Style.MISSILE
	)
	return missile


func _spawn_missile_enemy(position: Vector3) -> MissileEnemy:
	var scene: PackedScene = load("res://entities/enemy/missile_enemy.tscn")
	if scene == null:
		return null
	var enemy: MissileEnemy = scene.instantiate() as MissileEnemy
	_arena.add_child(enemy)
	enemy.global_position = position
	return enemy


func _spawn_fighter_enemy(position: Vector3) -> FighterEnemy:
	var scene: PackedScene = load("res://entities/enemy/fighter_enemy.tscn")
	if scene == null:
		return null
	var enemy: FighterEnemy = scene.instantiate() as FighterEnemy
	_arena.add_child(enemy)
	enemy.setup_spawn(position)
	return enemy


func _spawn_turret(position: Vector3) -> Enemy:
	var scene: PackedScene = load("res://entities/enemy/turret.tscn")
	if scene == null:
		return null
	var enemy: Enemy = scene.instantiate() as Enemy
	_arena.add_child(enemy)
	enemy.setup_spawn(position)
	return enemy


## Blasts live in the scene root, not under the enemy, so they outlive the hull.
## Counting them is how a death is told apart from a silent `queue_free`.
func _death_blasts() -> Array[ShipExplosion]:
	var found: Array[ShipExplosion] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return found
	for child in scene.get_children():
		if child is ShipExplosion:
			found.append(child)
	return found


## Impact effects also live in the scene root, not under the shot that produced them,
## so counting them is how a missile detonation is told apart from a bullet spark.
func _impact_waves() -> Array[ShockWave]:
	var found: Array[ShockWave] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return found
	for child in scene.get_children():
		if child is ShockWave:
			found.append(child)
	return found


## The death wave rides inside the death blast, so it frees with it. Looking for it
## as a child is what tells "the ring was added" apart from "some ring is around".
func _wave_of(blast: ShipExplosion) -> ShockWave:
	for child in blast.get_children():
		if child is ShockWave:
			return child
	return null


func _hit_sparks() -> Array[HitSpark]:
	var found: Array[HitSpark] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return found
	for child in scene.get_children():
		if child is HitSpark:
			found.append(child)
	return found


func _player_projectiles() -> Array[Projectile]:
	var found: Array[Projectile] = []
	for child in get_children():
		var bullet: Projectile = child as Projectile
		# A queued node is gone at the end of the frame but still a child now; a
		# count that included it would read a shot the test already cleared.
		if bullet == null or bullet.is_queued_for_deletion():
			continue
		if int(bullet.get("_team")) == Projectile.Team.PLAYER:
			found.append(bullet)
	return found


func _aim() -> Vector3:
	var aim: Vector3 = _player.get("_aim_direction")
	return aim


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
	# Lateral drift is not asserted here: turrets stream in along the heading, and
	# sliding around one is correct physics, not a broken play plane. Height is the
	# invariant — the ship never leaves y = 0 no matter what it meets.
	_check(
		absf(_player.global_position.y) < 0.1,
		"travelling keeps the player on the play plane (y %.3f)" % _player.global_position.y
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
		# The rig trails the body under thrust, so the ship leads the frame by a
		# bounded handful of pixels instead of sitting dead centre like a HUD icon.
		_check(
			offset < 16.0,
			"the camera leads the ship without losing it (off by %.2f px)" % offset
		)


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
		absf(angle - expected) < maxf(0.002, expected * 0.1),
		"the planet turns distance / radius (%.4f rad, expected %.4f)" % [angle, expected]
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


func _flat_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


## Airspeed across the nose: positive to the right of where the ship points.
func _sideways_airspeed() -> float:
	var heading: Vector3 = _player.get("_heading")
	var right: Vector3 = Vector3(-heading.z, 0.0, heading.x)
	return _player.velocity.dot(right)


## The fighter jink's push split on the airframe: x along the nose, y to its
## right. `_roll_velocity` is exactly the push applied on this frame, so the pair
## says which way the step goes with the steady flight left out.
func _jink_push() -> Vector2:
	var heading: Vector3 = _player.get("_heading")
	var right: Vector3 = Vector3(-heading.z, 0.0, heading.x)
	var push: Vector3 = _player.get("_roll_velocity")
	return Vector2(push.dot(heading), push.dot(right))


## The dash is a jink, not a screen clear. Enemy fire that reaches the hull mid-dash
## is evaded: no damage, no impact, and the shot keeps flying instead of being spent
## on the ship. The same bullet outside the window still costs health, which is what
## keeps the dash a decision instead of a free pass.
func _test_dash_evasion() -> void:
	_clear_projectiles()
	_clear_enemies()
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)
	_player.set("_dash_time", 0.0)
	_player.set("_roll_anim_time", 0.0)
	_player.set("_dash_cooldown", 0.0)
	await get_tree().physics_frame

	# Outside the window the shot is spent on the hit: the rule the dash is measured
	# against, and the behaviour a player still gets by dashing too late.
	var plain: Projectile = _spawn_enemy_bullet(
		_player.global_position - Vector3.RIGHT * 2.5
	)
	for _i in 12:
		await get_tree().physics_frame
	_check(
		int(_player.get("_hp")) == Player.MAX_HP - 1,
		"a bullet still hits a ship that is not dashing (hp %d)" % int(_player.get("_hp"))
	)
	_check(not is_instance_valid(plain), "a plain hit spends the bullet")

	# The window is held open with the burst direction zeroed, so the check is about
	# the rule and not about the hull outrunning the shot.
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)
	_player.set("_dash_direction", Vector3.ZERO)
	_player.set("_dash_time", 10.0)
	var evaded: Projectile = _spawn_enemy_bullet(
		_player.global_position - Vector3.RIGHT * 2.5
	)
	for _i in 12:
		await get_tree().physics_frame
	_check(
		int(_player.get("_hp")) == Player.MAX_HP,
		"a dashing ship takes no damage from the shot (hp %d)" % int(_player.get("_hp"))
	)
	_check(
		evaded != null and is_instance_valid(evaded) and not evaded.is_queued_for_deletion(),
		"the dash evades the shot instead of destroying it"
	)
	_player.set("_dash_time", 0.0)

	# The protection window is the animation, not the step. The button's fighter
	# spin sets no jink at all, so a hull that was only protected while
	# `_dash_time` ran would be shot halfway through the roll it can see itself
	# doing. A live spin clock alone must keep the ship evading.
	_player.set("_invulnerable", 0.0)
	_player.set("_dash_time", 0.0)
	_player.set("_roll_anim_time", Player.ROLL_ANIM_TIME * 0.5)
	_check(_player.is_evading(), "the spin alone still counts as evading")
	_player.set("_hp", Player.MAX_HP)
	var spun: Projectile = _spawn_enemy_bullet(
		_player.global_position - Vector3.RIGHT * 2.5
	)
	for _i in 12:
		await get_tree().physics_frame
	_check(
		int(_player.get("_hp")) == Player.MAX_HP,
		"a spinning ship takes no damage past the step (hp %d)" % int(_player.get("_hp"))
	)
	_check(
		spun != null and is_instance_valid(spun) and not spun.is_queued_for_deletion(),
		"the spin evades the shot past the step"
	)
	_player.set("_roll_anim_time", 0.0)

	_clear_projectiles()
	await get_tree().physics_frame


func _test_damage_and_iframes() -> void:
	# The encounter phase can legitimately land a hit, and this check is about
	# invulnerability frames, not about arriving at full health. The frames are
	# cleared too: an enemy hit a moment earlier would swallow the first one and
	# the test would pass or fail on timing.
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)

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
	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var game_over: GameOver = hud.get_node("%GameOver") as GameOver
	var counter: Label = hud.get_node("%Counter") as Label
	_check(not game_over.visible, "the death screen starts hidden")

	# The HUD turns both answers into a scene change, and reloading here would
	# restart the scene this test runs in. The answers are the unit under test, so
	# the HUD's handlers are detached for the rest of the check; the countdown is
	# detached too, because it would answer on its own five seconds in.
	for connection in game_over.respawn_requested.get_connections():
		game_over.respawn_requested.disconnect(connection["callable"])
	for connection in game_over.menu_requested.get_connections():
		game_over.menu_requested.disconnect(connection["callable"])

	# The death sound is counted from a clean slate: an earlier encounter is allowed
	# to have landed a killing hit in another test, and this check is about the
	# blast the drain below produces.
	Sfx.reset_counts()
	while int(_player.get("_hp")) > 0:
		_player.set("_invulnerable", 0.0)
		_player.take_damage(1)
		await get_tree().physics_frame

	_check(int(_player.get("_hp")) == 0, "health drains to zero")
	_check(_died_count > 0, "player_died reaches the event bus")
	_check(not bool(_player.get("_alive")), "player enters a dead state")
	_check(Sfx.played(&"player_death") == 1, "the death asks for the ship's blast")
	_check(not Sfx.engine_active(), "the hull's death silences the engine hum")

	# The blast is a world node at the hull's last position, not a child of the
	# ship: it has to outlive the hidden model and the respawn that follows it.
	var blasts: Array[ShipExplosion] = []
	for child in get_tree().current_scene.get_children():
		if child is ShipExplosion:
			blasts.append(child)
	_check(blasts.size() == 1, "death spawns one explosion")
	_check(
		blasts.size() == 1
		and blasts[0].global_position.distance_to(_player.global_position) < 0.01,
		"the explosion starts where the ship died"
	)
	_check(
		blasts.size() == 1 and _wave_of(blasts[0]) != null,
		"the ship's death leaves its shockwave"
	)

	# The panel waits for the blast to open, so the screen is still clear on the
	# death frame; the count starts when the panel arrives.
	_check(not game_over.visible, "the panel waits for the blast")
	for _i in int(GameOver.BLAST_DELAY * 60.0) + 4:
		await get_tree().physics_frame
	_check(game_over.visible, "death opens the game over screen")
	_check(
		game_over.remaining > 0.0 and game_over.remaining <= GameOver.RESPAWN_SECONDS,
		"the countdown starts full (%.2f of %.0f)" % [game_over.remaining, GameOver.RESPAWN_SECONDS]
	)
	_check(
		counter.text == "RESPAWN IN %d" % GameOver.RESPAWN_SECONDS,
		"the counter reads the full countdown (\"%s\")" % counter.text
	)

	var before: float = game_over.remaining
	await get_tree().physics_frame
	_check(game_over.remaining < before, "the countdown ticks down with the frame")
	_check(counter.text.begins_with("RESPAWN IN "), "the counter stays a countdown (\"%s\")" % counter.text)

	# Each answer is checked for the signal it raises; navigation stays with the HUD,
	# whose handlers were detached above.
	var respawns: Array[bool] = []
	var menus: Array[bool] = []
	game_over.respawn_requested.connect(func() -> void: respawns.append(true))
	game_over.menu_requested.connect(func() -> void: menus.append(true))

	var continue_button: Button = hud.get_node("%ContinueButton") as Button
	var menu_button: Button = hud.get_node("%MenuButton") as Button
	_check(continue_button.has_focus(), "the continue button takes the focus for a gamepad")

	continue_button.pressed.emit()
	_check(respawns.size() == 1, "CONTINUE asks for a respawn")
	_check(menus.is_empty(), "CONTINUE does not also ask for the menu")

	game_over.start()
	menu_button.pressed.emit()
	_check(menus.size() == 1, "MAIN MENU asks for the menu")
	_check(respawns.size() == 1, "MAIN MENU does not also ask for a respawn")

	game_over.start()
	var restart_event: InputEventAction = InputEventAction.new()
	restart_event.action = &"restart"
	restart_event.pressed = true
	game_over._unhandled_input(restart_event)
	_check(respawns.size() == 2, "R continues the run")

	game_over.start()
	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	game_over._unhandled_input(cancel_event)
	_check(menus.size() == 2, "ESC leaves for the menu")

	# Disarmed by the last answer: a live countdown would reload the arena while the
	# rest of the suite is still running.
	var stopped_at: float = game_over.remaining
	await get_tree().physics_frame
	_check(game_over.remaining == stopped_at, "one answer stops the countdown")

	# Nothing else owns the blast, so it has to clean itself up: a leaked node would
	# sit in the arena until the next scene change.
	for _i in int(ShipExplosion.LIFETIME * 60.0) + 10:
		await get_tree().physics_frame
	var leaked: bool = false
	for child in get_tree().current_scene.get_children():
		if child is ShipExplosion:
			leaked = true
	_check(not leaked, "the explosion frees itself")


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


## The RMS of a committed WAV in decibels. The mix table is checked against the files
## that ship, not against the table's own arithmetic: peak normalisation means two
## files at the same peak can still differ by 15 dB of loudness, and that gap is
## exactly what the mixer exists to close.
func _rms_db(path: String) -> float:
	var wav: Dictionary = _wav_pcm(path)
	if wav.is_empty():
		return -120.0
	var pcm: PackedByteArray = wav["data"]
	var frames: int = pcm.size() >> 1
	if frames == 0:
		return -120.0
	var total: float = 0.0
	for i in frames:
		var sample: float = float(pcm.decode_s16(i * 2)) / 32768.0
		total += sample * sample
	var rms: float = sqrt(total / float(frames))
	return 20.0 * log(maxf(rms, 0.000001)) / log(10.0)


## Share of a committed WAV's energy above `cutoff` Hz, as a one-pole high-pass.
## The palette is synthesized, so the only question is whether the bright band is
## there at all, not what its exact shape is.
##
## The file is read from disk on purpose: Godot imports these WAVs as QOA, so the
## resource's `data` is not the PCM that ships and cannot be decoded as samples.
func _high_band_energy(path: String, cutoff: float) -> float:
	var wav: Dictionary = _wav_pcm(path)
	if wav.is_empty():
		return 0.0
	var pcm: PackedByteArray = wav["data"]
	var rate: float = float(wav["rate"])
	var alpha: float = 1.0 / (1.0 + TAU * cutoff / rate)
	var previous_input: float = 0.0
	var previous_output: float = 0.0
	var high: float = 0.0
	var total: float = 0.0
	var frames: int = pcm.size() >> 1
	for i in frames:
		var sample: float = float(pcm.decode_s16(i * 2)) / 32768.0
		var filtered: float = alpha * (previous_output + sample - previous_input)
		previous_input = sample
		previous_output = filtered
		high += filtered * filtered
		total += sample * sample
	return high / total if total > 0.0 else 0.0


## The 16-bit mono PCM of a RIFF/WAVE file, with its sample rate.
func _wav_pcm(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_buffer(4).get_string_from_ascii() != "RIFF":
		return {}
	file.get_32()
	if file.get_buffer(4).get_string_from_ascii() != "WAVE":
		return {}
	var rate: int = 44100
	while file.get_position() + 8 <= file.get_length():
		var chunk: String = file.get_buffer(4).get_string_from_ascii()
		var size: int = file.get_32()
		if chunk == "fmt ":
			file.get_16()
			file.get_16()
			rate = file.get_32()
			file.seek(file.get_position() + size - 8 + (size & 1))
		elif chunk == "data":
			return {"rate": rate, "data": file.get_buffer(size)}
		else:
			file.seek(file.get_position() + size + (size & 1))
	return {}


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
	add_child(city)
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
		Building.MAX_HP >= Enemy.MAX_HP * 10,
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


## The first thing a world-layer ray meets, or null. Buildings are the only bodies
## on that layer, which is why the mask is the whole test.
func _world_hit(from: Vector3, to: Vector3) -> Object:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, 1 << Building.LAYER_WORLD
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(query)
	return hit.get("collider") as Object


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
