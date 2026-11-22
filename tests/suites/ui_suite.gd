class_name UiSuite
extends SmokeSuite
## Menus, the HUD, the pad remap panel, the livery turntable and the pause
## overlay. Presentation only: nothing here mutates gameplay state.

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
	get_tree().current_scene.add_child(menu)
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
	get_tree().current_scene.add_child(menu)
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
	get_tree().current_scene.add_child(model)
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
	get_tree().current_scene.add_child(pristine)
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
	_arena.director().park()
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
	_arena.director().resume()
	await _wait_frames(2)


