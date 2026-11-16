class_name MainMenu
extends Control
## Boot scene. It owns the destinations the game has before a run -- the planet
## arena, the city district -- and a settings panel.
##
## The window mode is the one display option the build honours, so it is applied
## here and nowhere else: the level inherits it, and `GameSettings` restores it on
## the next launch. The livery is the one option the player sees in flight, so it
## is previewed on a live copy of the airframe instead of on a colour chip: a chip
## does not say how a colour will land on the panels, the glass or the lines.
##
## The panel carries the controls reference because a prototype is played by people
## who have not read the docs, and the pad editor is that same table: the reference
## and the remap are one list read two ways, so a rebind cannot leave the panel
## naming a button the ship no longer answers to.
##
## The pad is the one input the player rearranges: the menu owns the listening
## state and the file, and `PadBindings` owns everything the run loop needs. A
## bind is written as soon as it is made, so a crash after the press still leaves
## the pad the player chose.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
const CITY_SCENE: String = "res://levels/city/city.tscn"

## One palette, offered five times. The hull, the nose, the stripe, the glass and
## the lines are the same decision -- what colour is this ship -- so they get the
## same nine colours instead of five curated lists nobody asked for. The first four
## entries are the colours the file ships, which makes "factory" a swatch a player
## can come back to rather than a hidden reset; the nose shares the hull's white,
## so the same swatch is the factory nose too.
const PALETTE: Array[Color] = [
	GameSettings.DEFAULT_HULL,
	GameSettings.DEFAULT_TRIM,
	GameSettings.DEFAULT_CANOPY,
	GameSettings.DEFAULT_LINES,
	Color(0.80, 0.14, 0.16),
	Color(0.93, 0.72, 0.18),
	Color(0.10, 0.62, 0.60),
	Color(0.25, 0.47, 0.85),
	Color(0.86, 0.42, 0.12),
]
const SWATCH_SIZE: float = 30.0
## The listening row is the one thing in the panel asking for an input instead of
## answering one, so it is the one thing in warning amber.
const LISTEN_COLOR: Color = Color(1, 0.72, 0.34, 1.0)
const BINDING_COLOR: Color = Color(1, 1, 1, 0.92)
## Wide enough for the longest pad name and for "PRESS A BUTTON", so listening
## never resizes the column the row already set.
const BINDING_WIDTH: float = 132.0
## The weapon pair shares one row, so each half is narrower than a full row's
## button and the two together stay close to one.
const PAIR_WIDTH: float = 100.0
const IDLE_HINT: String = "Click a pad button, then press the one you want."

## The controls table, top to bottom: the name a player reads, the inputs that are
## not a pad button, and the pad actions the row edits. A row with no action is a
## control the player cannot rearrange -- the sticks, the trigger, the number keys
## -- and it draws an empty third cell so the table stays three columns wide.
## `label` is spelled out only where the row is not one movable action; the rest
## take their name from `PadBindings`, so the table and the hint cannot disagree.
const ROWS: Array = [
	{"label": "Move", "keys": "WASD / left stick", "actions": []},
	{"label": "Aim", "keys": "Mouse / right stick", "actions": []},
	{"keys": "Left mouse", "actions": [&"fire"]},
	{"keys": "Right mouse / F", "actions": [&"missile"]},
	{"label": "Weapon", "keys": "1 - 3", "actions": [&"weapon_prev", &"weapon_next"]},
	{"keys": "E", "actions": [&"bomb"]},
	{"keys": "C", "actions": [&"decoy"]},
	{"label": "Afterburner", "keys": "Shift / right trigger", "actions": []},
	{"keys": "Space / double tap", "actions": [&"dash"]},
	{"keys": "Q", "actions": [&"transform"]},
	{"keys": "R", "actions": [&"restart"]},
]

## Tests point this at a scratch file so a swatch click never rewrites the real
## settings. Nothing in the game changes it.
var settings_path: String = GameSettings.CONFIG_PATH

var _hull: Color = GameSettings.DEFAULT_HULL
var _nose: Color = GameSettings.DEFAULT_NOSE
var _trim: Color = GameSettings.DEFAULT_TRIM
var _canopy: Color = GameSettings.DEFAULT_CANOPY
var _lines: Color = GameSettings.DEFAULT_LINES
## The empty string is "not listening". A button name cannot be empty, so the
## listening state and the action it is waiting for are the same value.
var _listening: StringName = &""
var _bindings: Dictionary = PadBindings.defaults()
var _binding_buttons: Dictionary = {}
## The progress reset is the one destructive button in the menu, so it asks twice.
## The arm lives on the panel, not on a timer: closing it disarms, which is the
## cancel. The pad reset is not armed -- a remap is cheap to make again.
var _reset_armed: bool = false

@onready var _start_button: Button = %StartButton
@onready var _city_button: Button = %CityButton
@onready var _continue_button: Button = %ContinueButton
@onready var _pilot_button: Button = %PilotButton
@onready var _options_button: Button = %OptionsButton
@onready var _quit_button: Button = %QuitButton
@onready var _options: Control = %Options
@onready var _pilot: Control = %Pilot
@onready var _control_grid: GridContainer = %ControlGrid
@onready var _control_hint: Label = %ControlHint
@onready var _pad_reset_button: Button = %PadResetButton
@onready var _pilot_level: Label = %Level
@onready var _pilot_kills: Label = %Kills
@onready var _pilot_tracks: Label = %Tracks
@onready var _reset_button: Button = %ResetButton
@onready var _pilot_back_button: Button = %PilotBackButton
@onready var _fullscreen: CheckButton = %Fullscreen
@onready var _back_button: Button = %BackButton
@onready var _preview: LiveryPreview = %Preview
@onready var _hull_row: HBoxContainer = %HullRow
@onready var _nose_row: HBoxContainer = %NoseRow
@onready var _trim_row: HBoxContainer = %TrimRow
@onready var _canopy_row: HBoxContainer = %CanopyRow
@onready var _lines_row: HBoxContainer = %LinesRow


func _ready() -> void:
	_options.visible = false
	_pilot.visible = false

	_start_button.pressed.connect(_on_start_pressed)
	_city_button.pressed.connect(_on_city_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_pilot_button.pressed.connect(_on_pilot_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_pad_reset_button.pressed.connect(_on_pad_reset_pressed)
	_pilot_back_button.pressed.connect(_on_pilot_back_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)

	refresh()

	var fullscreen: bool = GameSettings.load_fullscreen(settings_path)
	GameSettings.apply_fullscreen(fullscreen)
	# The stored value is a state to display, not a decision to announce: applying
	# it must not fire the handler that saves it again.
	_fullscreen.set_pressed_no_signal(fullscreen)

	# The pad is applied before the first run can start, and the table is built
	# from the same dictionary, so what the menu shows is what the ship reads.
	_bindings = PadBindings.load_bindings(settings_path)
	PadBindings.apply(_bindings)
	_build_control_rows()
	_refresh_control_rows()

	_hull = GameSettings.load_hull(settings_path)
	_nose = GameSettings.load_nose(settings_path)
	_trim = GameSettings.load_trim(settings_path)
	_canopy = GameSettings.load_canopy(settings_path)
	_lines = GameSettings.load_lines(settings_path)
	# The preview is a view: it is told the livery before it ever builds, so the
	# airframe cannot appear in one colour and switch to another a frame later.
	_preview.set_livery(_hull, _trim, _canopy, _lines, _nose)
	_build_swatches(_hull_row, _hull, _on_hull_picked)
	_build_swatches(_nose_row, _nose, _on_nose_picked)
	_build_swatches(_trim_row, _trim, _on_trim_picked)
	_build_swatches(_canopy_row, _canopy, _on_canopy_picked)
	_build_swatches(_lines_row, _lines, _on_lines_picked)

	_start_button.grab_focus()


## Repaints the pilot readout and decides whether CONTINUE is offered. Public
## because the panel calls it after a reset and the smoke suite calls it after
## writing a save; nothing in the run loop needs it.
func refresh() -> void:
	var progress: GameProgress = GameProgress.instance()
	var stats: PilotStats = PilotStats.new(progress.level())

	_continue_button.visible = GameProgress.has_save()
	_pilot_level.text = "LEVEL %d" % progress.level()
	_pilot_kills.text = "%d KILLS   ·   %s" % [
		progress.total_kills,
		"MAX LEVEL" if progress.kills_to_next() <= 0 else "%d TO NEXT" % progress.kills_to_next(),
	]
	_pilot_tracks.text = _track_report(stats)
	_disarm_reset()


## One line per track, with the bonus the level has already bought. A level-1
## pilot reads five zeroes, which is the honest answer and the reason the panel is
## read-only: there is nothing to choose.
func _track_report(stats: PilotStats) -> String:
	var speed: int = roundi((stats.speed_multiplier() - 1.0) * 100.0)
	var armor: int = stats.max_hp(0)
	var capacity: int = roundi((stats.turbo_capacity_multiplier() - 1.0) * 100.0)
	var recharge: int = roundi((stats.turbo_recharge_multiplier() - 1.0) * 100.0)
	var interval: int = roundi((1.0 - stats.primary_interval_multiplier()) * 100.0)
	var spread: int = roundi((1.0 - stats.vulcan_spread_multiplier()) * 100.0)
	var cone: int = roundi((stats.plasma_cone_multiplier() - 1.0) * 100.0)
	var reach: int = roundi((stats.laser_range_multiplier() - 1.0) * 100.0)
	return "\n".join([
		"THRUSTERS    +%d%% SPEED" % speed,
		"ARMOR        +%d HP" % armor,
		"REACTOR      +%d%% TURBO   +%d%% RECHARGE" % [capacity, recharge],
		"AUTOLOADER   -%d%% INTERVAL" % interval,
		"GUNNERY      -%d%% SPREAD   +%d%% LOCK   +%d%% RANGE" % [spread, cone, reach],
	])


## The listening state has to see the press before the button under the cursor
## does, which is why it lives here and not in `_unhandled_input`: GUI input runs
## between the two, so a focused binding button would swallow its own bind.
func _input(event: InputEvent) -> void:
	if _listening == &"" or not _options.visible:
		return
	# Escape cancels without becoming a binding. It is read as a key rather than
	# through `ui_cancel` because the pad's own cancel button is a perfectly good
	# thing to put on an action, and reading the action would make it unbindable.
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel_listening()
		return
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if pad == null or not pad.pressed:
		return
	get_viewport().set_input_as_handled()
	var action: StringName = _listening
	PadBindings.assign(_bindings, action, pad.button_index)
	PadBindings.apply(_bindings)
	PadBindings.save_bindings(_bindings, settings_path)
	Sfx.play(&"ui_select")
	_listening = &""
	_refresh_control_rows()
	_binding_buttons[action].grab_focus()


## Escape is the way out of the panel, the same way it is out of every other panel
## a player has ever opened.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if _pilot.visible:
			get_viewport().set_input_as_handled()
			_close_pilot()
		elif _options.visible:
			get_viewport().set_input_as_handled()
			_close_options()


func _on_start_pressed() -> void:
	Sfx.play(&"ui_select")
	_open_scene(ARENA_SCENE)


func _on_city_pressed() -> void:
	Sfx.play(&"ui_select")
	_open_scene(CITY_SCENE)


## CONTINUE reopens the scenario the last run started. The path comes from the
## save, so a future scenario only has to call `remember_scenario` to be
## resumable; an unknown path falls back to the planet rather than to a dead
## button.
func _on_continue_pressed() -> void:
	Sfx.play(&"ui_select")
	var scene: String = GameProgress.instance().last_scenario
	if scene.is_empty() or not ResourceLoader.exists(scene):
		scene = ARENA_SCENE
	_open_scene(scene)


## Both destinations are one decision -- which run to start -- so they take the
## same path and report a missing scene the same way.
func _open_scene(path: String) -> void:
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("Could not open %s: %s" % [path, error_string(error)])


## QUIT is the one entry on the menu that does not open anything: the window is
## the whole build, so leaving the tree is leaving the game.
func _on_quit_pressed() -> void:
	Sfx.play(&"ui_select")
	get_tree().quit()


func _on_options_pressed() -> void:
	Sfx.play(&"ui_select")
	_options.visible = true
	_preview.ensure_built()
	# The panel opens on the colours, so the focus lands on the chosen hull: a pad
	# player arrives on the thing they came for, and BACK is one d-pad press away.
	# Reading the row instead of remembering the last click keeps the focus and the
	# highlight the same button even when the choice came from the mouse.
	var focus_target: Button = _pressed_swatch(_hull_row)
	if focus_target == null:
		focus_target = _back_button
	focus_target.grab_focus()


func _on_back_pressed() -> void:
	Sfx.play(&"ui_select")
	_close_options()


## Leaving the panel drops any half-finished bind: a listener that outlived the
## close would eat the next pad press in the main menu.
func _close_options() -> void:
	_listening = &""
	_refresh_control_rows()
	_options.visible = false
	_options_button.grab_focus()


## The factory pad is a choice like any other, so it is written the same way: the
## next launch has to come back to it without the panel being opened first.
func _on_pad_reset_pressed() -> void:
	Sfx.play(&"ui_select")
	_listening = &""
	_bindings = PadBindings.defaults()
	PadBindings.apply(_bindings)
	PadBindings.save_bindings(_bindings, settings_path)
	_refresh_control_rows()
	_binding_buttons[PadBindings.ACTIONS[0]].grab_focus()


## The table is built by code because it is a table: the third cell is a button
## only where the player may move the action, the weapon row owns two of them, and
## the pad labels come from the run's bindings rather than from the factory ones.
func _build_control_rows() -> void:
	for row: Dictionary in ROWS:
		var name_label: Label = Label.new()
		name_label.text = _row_label(row)
		name_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.78))
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Absorbing the slack is what keeps the pad column flush right, so every
		# button lands on the same edge no matter how long the row's name is.
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_control_grid.add_child(name_label)

		var keys_label: Label = Label.new()
		keys_label.text = String(row["keys"])
		keys_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.5))
		keys_label.add_theme_font_size_override(&"font_size", 12)
		keys_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_control_grid.add_child(keys_label)

		var actions: Array = row["actions"]
		if actions.is_empty():
			# A control the player cannot rearrange still occupies its cell, or the
			# pad buttons below it would slide into the middle column.
			_control_grid.add_child(Control.new())
			continue
		# The two halves of the weapon decision share one row instead of spending a
		# row each, so the table adds no height the panel does not have.
		var cell: Control = _make_binding_button(
			actions[0], PAIR_WIDTH if actions.size() > 1 else BINDING_WIDTH
		)
		if actions.size() > 1:
			var pair: HBoxContainer = HBoxContainer.new()
			pair.add_theme_constant_override(&"separation", 6)
			pair.add_child(cell)
			pair.add_child(_make_binding_button(actions[1], PAIR_WIDTH))
			cell = pair
		_control_grid.add_child(cell)


## A row is named after the action it edits when it edits exactly one; only the
## fixed rows and the weapon pair need a name written out.
func _row_label(row: Dictionary) -> String:
	var actions: Array = row["actions"]
	if actions.size() == 1:
		return PadBindings.action_label(actions[0])
	return String(row.get("label", ""))


## The button is the panel's own styling with the padding squeezed: the shared
## style is built for a full-width menu button, and its 12 px of vertical padding
## would make an eleven-row table taller than the panel that holds it.
func _make_binding_button(action: StringName, width: float = BINDING_WIDTH) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(width, 0)
	button.add_theme_font_size_override(&"font_size", 14)
	button.add_theme_color_override(&"font_color", BINDING_COLOR)
	button.add_theme_color_override(&"font_hover_color", Color(0.55, 0.98, 0.9, 1.0))
	button.add_theme_color_override(&"font_pressed_color", Color(0.02, 0.03, 0.05, 1.0))
	for slot: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		button.add_theme_stylebox_override(
			slot, _compact_style(_back_button.get_theme_stylebox(slot))
		)
	button.pressed.connect(_on_binding_pressed.bind(action))
	_binding_buttons[action] = button
	return button


## A copy with the padding squeezed: the menu's own colours, border and radius
## survive, and only the 12 px of vertical padding -- built for a full-width menu
## button -- is what the table cannot afford.
func _compact_style(source: StyleBox) -> StyleBox:
	var style: StyleBoxFlat = source.duplicate() as StyleBoxFlat
	if style == null:
		return source
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _on_binding_pressed(action: StringName) -> void:
	Sfx.play(&"ui_select")
	_listening = action
	_refresh_control_rows()


func _cancel_listening() -> void:
	var action: StringName = _listening
	_listening = &""
	_refresh_control_rows()
	_binding_buttons[action].grab_focus()


## The row being listened to says so in words and in amber; the rest keep naming
## the button they are on, so the table is readable at a glance while it waits.
func _refresh_control_rows() -> void:
	for action: StringName in PadBindings.ACTIONS:
		var button: Button = _binding_buttons.get(action) as Button
		if button == null:
			continue
		if action == _listening:
			button.text = "PRESS A BUTTON"
			_set_binding_color(button, LISTEN_COLOR)
		else:
			button.text = PadBindings.label_for(int(_bindings[action]))
			_set_binding_color(button, BINDING_COLOR)
	_control_hint.text = (
		"Press the pad button for %s. Escape cancels." % PadBindings.action_label(_listening)
		if _listening != &""
		else IDLE_HINT
	)


## A focused button draws its label with `font_focus_color`, not `font_color`, so
## the listening row has to override both or the amber only appears after focus
## moves away from the row the player is looking at.
func _set_binding_color(button: Button, color: Color) -> void:
	button.add_theme_color_override(&"font_color", color)
	button.add_theme_color_override(&"font_focus_color", color)


## The pilot panel is read-only except for the reset, which is the one action that
## belongs to the record rather than to a run.
func _on_pilot_pressed() -> void:
	Sfx.play(&"ui_select")
	refresh()
	_pilot.visible = true
	_pilot_back_button.grab_focus()


func _on_pilot_back_pressed() -> void:
	Sfx.play(&"ui_select")
	_close_pilot()


func _close_pilot() -> void:
	_pilot.visible = false
	_disarm_reset()
	_pilot_button.grab_focus()


func _on_reset_pressed() -> void:
	Sfx.play(&"ui_select")
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "PRESS AGAIN TO CONFIRM"
		return
	GameProgress.instance().reset()
	refresh()


func _disarm_reset() -> void:
	_reset_armed = false
	_reset_button.text = "RESET PROGRESS"


func _on_fullscreen_toggled(enabled: bool) -> void:
	GameSettings.apply_fullscreen(enabled)
	GameSettings.save_fullscreen(enabled, settings_path)


func _on_hull_picked(color: Color) -> void:
	_hull = color
	_push_livery()


func _on_nose_picked(color: Color) -> void:
	_nose = color
	_push_livery()


func _on_trim_picked(color: Color) -> void:
	_trim = color
	_push_livery()


func _on_canopy_picked(color: Color) -> void:
	_canopy = color
	_push_livery()


func _on_lines_picked(color: Color) -> void:
	_lines = color
	_push_livery()


## Every swatch is the same decision, so it takes the same two steps: show the
## ship the new colour, then make it the ship the next launch builds.
func _push_livery() -> void:
	Sfx.play(&"ui_select")
	_preview.set_livery(_hull, _trim, _canopy, _lines, _nose)
	GameSettings.save_livery(_hull, _trim, _canopy, _lines, _nose, settings_path)


## Builds one row of colour buttons and marks the one that matches the stored
## colour. The group is what makes the row a choice instead of a pile of toggles:
## pressing a swatch releases the previous one, and the last one cannot be
## released, so the ship always has a hull and always has a stripe.
func _build_swatches(row: HBoxContainer, current: Color, pick: Callable) -> void:
	var group: ButtonGroup = ButtonGroup.new()
	group.allow_unpress = false
	for color in PALETTE:
		var swatch: Button = Button.new()
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		swatch.add_theme_stylebox_override(
			&"normal", _swatch_style(color, Color(1.0, 1.0, 1.0, 0.18), 1)
		)
		swatch.add_theme_stylebox_override(
			&"hover", _swatch_style(color, Color(0.55, 0.98, 0.9, 0.9), 2)
		)
		swatch.add_theme_stylebox_override(
			&"pressed", _swatch_style(color, Color(0.55, 0.98, 0.9, 1.0), 3)
		)
		swatch.add_theme_stylebox_override(&"focus", _focus_style())
		# `pressed` and not `toggled`: releasing the previous swatch also emits
		# `toggled`, and painting the old colour on the way out would fight the
		# pick that is about to arrive.
		swatch.pressed.connect(pick.bind(color))
		row.add_child(swatch)
		if _colors_match(color, current):
			swatch.set_pressed_no_signal(true)


func _pressed_swatch(row: HBoxContainer) -> Button:
	for child in row.get_children():
		var button: Button = child as Button
		if button != null and button.button_pressed:
			return button
	return null


func _swatch_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_border_width_all(width)
	style.border_color = border
	style.set_corner_radius_all(4)
	return style


## The focus ring sits outside the swatch so it never hides the colour it marks.
func _focus_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.98, 0.9, 0.9)
	style.set_corner_radius_all(6)
	style.expand_margin_left = 3.0
	style.expand_margin_top = 3.0
	style.expand_margin_right = 3.0
	style.expand_margin_bottom = 3.0
	return style


## Alpha is not compared: a swatch is a colour, and the stored alpha is always one.
func _colors_match(a: Color, b: Color) -> bool:
	return (
		is_equal_approx(a.r, b.r)
		and is_equal_approx(a.g, b.g)
		and is_equal_approx(a.b, b.b)
	)
