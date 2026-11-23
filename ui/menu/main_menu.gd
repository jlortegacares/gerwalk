class_name MainMenu
extends Control
## Boot scene. It owns the destinations the game has before a run -- the planet
## arena, the city district -- the save cards and a settings panel.
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
##
## The same scene is also the pause screen. A run that is interrupted needs a way
## back more than it needs a way to start another fight, so `in_game` swaps the
## destinations for RESUME and leaves the panel untouched: the pad and the livery
## are the same decisions whether the player came from the boot screen or from a
## frozen fight.
##
## CONTINUE is the door to the save cards: the panel lists the six pilots, and the
## card chosen there is the one PLANET, CITY and CONTINUE itself fly. A boot menu
## therefore never hides CONTINUE -- an empty card is how a second pilot starts --
## while the pause screen does, because a run already belongs to a card.

## Raised by RESUME (and by Escape on the pause screen) so the run that opened the
## menu is the one that closes it: the menu asks, the HUD owns the tree's pause.
signal resume_requested

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
## The controls table owns its own colours, widths and rows; the names stay here
## because the suite reads them to describe the panel.
const LISTEN_COLOR: Color = PadPanel.LISTEN_COLOR
const BINDING_COLOR: Color = PadPanel.BINDING_COLOR
const BINDING_WIDTH: float = PadPanel.BINDING_WIDTH
const PAIR_WIDTH: float = PadPanel.PAIR_WIDTH
const IDLE_HINT: String = PadPanel.IDLE_HINT
## A save card names a pilot in three lines, so it needs room for the date and
## the scenario without making the panel taller than the window.
const SLOT_CARD_SIZE: Vector2 = Vector2(232, 84)
## The active card is the one PLANET, CITY and CONTINUE fly, so it is the one card
## in the accent colour and the only one that says ACTIVE.
const ACTIVE_CARD_COLOR: Color = Color(0.55, 0.98, 0.9, 1.0)
const CARD_COLOR: Color = Color(1, 1, 1, 0.92)

## The controls table, top to bottom: the name a player reads, the inputs that are
## not a pad button, and the pad actions the row edits. A row with no action is a
## control the player cannot rearrange -- the sticks, the trigger, the number keys
## -- and it draws an empty third cell so the table stays three columns wide.
## `label` is spelled out only where the row is not one movable action; the rest
## take their name from `PadBindings`, so the table and the hint cannot disagree.
## The table itself lives in `PadPanel`; the name stays here for the suite.
const ROWS: Array = PadPanel.ROWS

## Tests point this at a scratch file so a swatch click never rewrites the real
## settings. Nothing in the game changes it.
var settings_path: String = GameSettings.CONFIG_PATH
## True when the menu was opened over a running fight instead of at boot. It is set
## by whoever instantiates the menu and read once in `_ready`, because the entries
## it hides are hidden for the menu's whole lifetime.
var in_game: bool = false

var _hull: Color = GameSettings.DEFAULT_HULL
var _nose: Color = GameSettings.DEFAULT_NOSE
var _trim: Color = GameSettings.DEFAULT_TRIM
var _canopy: Color = GameSettings.DEFAULT_CANOPY
var _lines: Color = GameSettings.DEFAULT_LINES
## The controls table and its listening state live in the panel; the menu owns the
## nodes it draws into and forwards the input while OPTIONS is open.
var _pad: PadPanel = PadPanel.new()
## The progress reset is the one destructive button in the menu, so it asks twice.
## The arm lives on the panel, not on a timer: closing it disarms, which is the
## cancel. The pad reset is not armed -- a remap is cheap to make again.
var _reset_armed: bool = false
## The card the save panel is acting on. A press only moves the selection; LOAD
## or START is what makes it active and opens the scene, which is what leaves
## DELETE reachable for a card nobody is flying yet.
var _slot_focus: int = SaveSlots.DEFAULT_SLOT
var _delete_armed: bool = false
var _slot_buttons: Dictionary = {}

@onready var _start_button: Button = %StartButton
@onready var _city_button: Button = %CityButton
@onready var _resume_button: Button = %ResumeButton
@onready var _continue_button: Button = %ContinueButton
@onready var _pilot_button: Button = %PilotButton
@onready var _options_button: Button = %OptionsButton
@onready var _quit_button: Button = %QuitButton
@onready var _options: Control = %Options
@onready var _pilot: Control = %Pilot
@onready var _pilot_level: Label = %Level
@onready var _pilot_kills: Label = %Kills
@onready var _pilot_tracks: Label = %Tracks
@onready var _reset_button: Button = %ResetButton
@onready var _pilot_back_button: Button = %PilotBackButton
@onready var _slot_line: Label = %SlotLine
@onready var _saves: Control = %Saves
@onready var _slots: GridContainer = %Slots
@onready var _slot_primary: Button = %SlotPrimary
@onready var _slot_secondary: Button = %SlotSecondary
@onready var _saves_back_button: Button = %SavesBackButton
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
	_saves.visible = false
	# The boot menu is where a card is chosen, so it is also where the record is
	# pointed at that card's file. The pause screen is looking at a record already
	# in flight and must not reload it underneath the run.
	if not in_game:
		SaveSlots.ensure(settings_path)
	_build_slot_cards()

	_start_button.pressed.connect(_on_start_pressed)
	_city_button.pressed.connect(_on_city_pressed)
	_resume_button.pressed.connect(_on_resume_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_pilot_button.pressed.connect(_on_pilot_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_pilot_back_button.pressed.connect(_on_pilot_back_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_slot_primary.pressed.connect(_on_slot_primary_pressed)
	_slot_secondary.pressed.connect(_on_slot_secondary_pressed)
	_saves_back_button.pressed.connect(_on_saves_back_pressed)

	refresh()

	var fullscreen: bool = GameSettings.load_fullscreen(settings_path)
	GameSettings.apply_fullscreen(fullscreen)
	# The stored value is a state to display, not a decision to announce: applying
	# it must not fire the handler that saves it again.
	_fullscreen.set_pressed_no_signal(fullscreen)

	# The pad is applied before the first run can start, and the table is built
	# from the same dictionary, so what the menu shows is what the ship reads.
	_pad.settings_path = settings_path
	_pad.build(%ControlGrid, %ControlHint, %PadResetButton, _binding_style)

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

	# A paused run has one obvious answer, and it is not a new fight: the two
	# destinations that replace the current arena are hidden rather than left to
	# throw the run away by accident.
	_resume_button.visible = in_game
	_start_button.visible = not in_game
	_city_button.visible = not in_game

	if in_game:
		_resume_button.grab_focus()
	else:
		_start_button.grab_focus()


## Repaints the pilot readout, the active-card line and the save panel. Public
## because the panels call it after a change and the smoke suite calls it after
## writing a save; nothing in the run loop needs it.
func refresh() -> void:
	var progress: GameProgress = GameProgress.instance()
	var stats: PilotStats = PilotStats.new(progress.level())

	# CONTINUE is the door to the card list, so it is offered even when the active
	# card has never flown. Only the pause screen hides it: a run there belongs to
	# a card and is not swapped in flight.
	_continue_button.visible = not in_game
	_slot_line.text = _slot_line_text()
	_pilot_level.text = "LEVEL %d" % progress.level()
	_pilot_kills.text = "%d KILLS   ·   %s" % [
		progress.total_kills,
		"MAX LEVEL" if progress.kills_to_next() <= 0 else "%d TO NEXT" % progress.kills_to_next(),
	]
	_pilot_tracks.text = _track_report(stats)
	_disarm_reset()
	_refresh_slots()


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


## The line under the tagline. Without it the active card is invisible, and a
## player who picked card 3 in the list could not tell it from card 1.
func _slot_line_text() -> String:
	var summary: Dictionary = SaveSlots.summary(SaveSlots.active_slot(settings_path))
	var name: String = "SLOT %d" % int(summary["slot"])
	if not summary["occupied"]:
		return "%s · NEW PILOT" % name
	return "%s · LV %d · %d KILLS · %s" % [
		name,
		int(summary["level"]),
		int(summary["kills"]),
		_scenario_name(String(summary["scenario"])),
	]


## The cards are built once and only repainted: the panel opens and closes many
## times in one session, and a rebuilt grid would drop the focus every time.
func _build_slot_cards() -> void:
	for slot: int in range(1, SaveSlots.SLOT_COUNT + 1):
		var card: Button = Button.new()
		card.custom_minimum_size = SLOT_CARD_SIZE
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_theme_font_size_override(&"font_size", 14)
		card.add_theme_color_override(&"font_color", CARD_COLOR)
		card.add_theme_color_override(&"font_hover_color", ACTIVE_CARD_COLOR)
		card.add_theme_color_override(&"font_focus_color", ACTIVE_CARD_COLOR)
		card.add_theme_color_override(&"font_pressed_color", Color(0.02, 0.03, 0.05, 1.0))
		for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
			card.add_theme_stylebox_override(
				state, _compact_style(_back_button.get_theme_stylebox(state))
			)
		card.pressed.connect(_on_slot_pressed.bind(slot))
		_slots.add_child(card)
		_slot_buttons[slot] = card


## The card the smoke suite presses. The grid is built in code, so there is no
## scene node to look up by name.
func slot_button(slot: int) -> Button:
	return _slot_buttons.get(slot) as Button


## The controls table builds its own buttons from the menu's style, and this is how
## it asks for one: the table knows its cells, the menu knows its theme.
func _binding_style(slot: StringName) -> StyleBox:
	return _compact_style(_back_button.get_theme_stylebox(slot))


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


func _refresh_slots() -> void:
	if _slot_buttons.is_empty():
		return
	var active: int = SaveSlots.active_slot(settings_path)
	for slot: int in _slot_buttons:
		var card: Button = _slot_buttons[slot] as Button
		var summary: Dictionary = SaveSlots.summary(slot)
		card.text = _card_text(summary, slot == active)
		card.add_theme_color_override(
			&"font_color", ACTIVE_CARD_COLOR if slot == active else CARD_COLOR
		)
	_refresh_slot_actions()


func _card_text(summary: Dictionary, active: bool) -> String:
	var name: String = "SLOT %d" % int(summary["slot"])
	if active:
		name += "  ·  ACTIVE"
	if not summary["occupied"]:
		return "%s\nEMPTY SLOT" % name
	return "%s\nLV %d  ·  %d KILLS\n%s  ·  %s" % [
		name,
		int(summary["level"]),
		int(summary["kills"]),
		_scenario_name(String(summary["scenario"])),
		_date_label(int(summary["played"])),
	]


## The action row is two buttons whose meaning follows the chosen card: a card
## that has flown offers LOAD and DELETE, an empty one offers the two scenarios
## the new pilot can start on. Hiding and showing buttons instead would make the
## panel jump every time the selection crossed an empty card.
func _refresh_slot_actions() -> void:
	var occupied: bool = bool(SaveSlots.summary(_slot_focus)["occupied"])
	if occupied:
		_slot_primary.text = "LOAD"
		_slot_secondary.text = "PRESS AGAIN TO CONFIRM" if _delete_armed else "DELETE"
	else:
		_slot_primary.text = "START PLANET"
		_slot_secondary.text = "START CITY"


func _scenario_name(path: String) -> String:
	match path:
		CITY_SCENE:
			return "CITY"
		ARENA_SCENE:
			return "ARENA"
		"":
			return "NO RUN YET"
	return path.get_file().get_basename().to_upper()


func _date_label(unix: int) -> String:
	if unix <= 0:
		return "NEVER FLOWN"
	return Time.get_date_string_from_unix_time(unix)


## A press only moves the selection. Nothing is loaded and nothing becomes active
## until LOAD or START is pressed, which is what leaves DELETE reachable for a
## card nobody is flying.
func _on_slot_pressed(slot: int) -> void:
	Sfx.play(&"ui_select")
	_slot_focus = slot
	_delete_armed = false
	_refresh_slots()


func _on_slot_primary_pressed() -> void:
	Sfx.play(&"ui_select")
	var summary: Dictionary = SaveSlots.summary(_slot_focus)
	SaveSlots.select(_slot_focus, settings_path)
	if not summary["occupied"]:
		_open_scene(ARENA_SCENE)
		return
	var scene: String = String(summary["scenario"])
	if scene.is_empty() or not ResourceLoader.exists(scene):
		scene = ARENA_SCENE
	_open_scene(scene)


## The right button is DELETE for a card that has flown and CITY for an empty one:
## starting on the night district is the other way a new pilot's first flight
## creates the file.
func _on_slot_secondary_pressed() -> void:
	Sfx.play(&"ui_select")
	var occupied: bool = bool(SaveSlots.summary(_slot_focus)["occupied"])
	if not occupied:
		SaveSlots.select(_slot_focus, settings_path)
		_open_scene(CITY_SCENE)
		return
	if not _delete_armed:
		_delete_armed = true
		_refresh_slot_actions()
		return
	SaveSlots.erase(_slot_focus)
	_delete_armed = false
	refresh()


func _open_saves() -> void:
	_slot_focus = SaveSlots.active_slot(settings_path)
	_delete_armed = false
	refresh()
	_saves.visible = true
	var card: Button = _slot_buttons.get(_slot_focus) as Button
	if card != null:
		card.grab_focus()


func _on_saves_back_pressed() -> void:
	Sfx.play(&"ui_select")
	_close_saves()


func _close_saves() -> void:
	_saves.visible = false
	_delete_armed = false
	_continue_button.grab_focus()


## The panel's listener has to see the press before the button under the cursor
## does, which is why the forwarding lives here and not in `_unhandled_input`: GUI
## input runs between the two, so a focused binding button would swallow its own bind.
func _input(event: InputEvent) -> void:
	if not _options.visible:
		return
	# The table reads the press first, because a focused binding button would
	# otherwise swallow the bind it is waiting for.
	if _pad.handle_input(event):
		get_viewport().set_input_as_handled()


## Escape is the way out of the panel, the same way it is out of every other panel
## a player has ever opened. On the pause screen it is also the way back into the
## fight, so the key that opened the menu is the key that closes it: the panel gets
## the first press, the run gets the second.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if _pilot.visible:
			get_viewport().set_input_as_handled()
			_close_pilot()
		elif _saves.visible:
			get_viewport().set_input_as_handled()
			_close_saves()
		elif _options.visible:
			get_viewport().set_input_as_handled()
			_close_options()
		elif in_game:
			get_viewport().set_input_as_handled()
			_on_resume_pressed()


func _on_start_pressed() -> void:
	Sfx.play(&"ui_select")
	_open_scene(ARENA_SCENE)


func _on_city_pressed() -> void:
	Sfx.play(&"ui_select")
	_open_scene(CITY_SCENE)


## The pause screen has no scene of its own to open: the run that paused is still
## there, and the HUD is the node that owns it, so the menu only asks.
func _on_resume_pressed() -> void:
	Sfx.play(&"ui_select")
	resume_requested.emit()


## CONTINUE opens the save list. The card chosen there decides what loads, so the
## button is the door to the six pilots rather than a shortcut past them.
func _on_continue_pressed() -> void:
	Sfx.play(&"ui_select")
	_open_saves()


## Both destinations are one decision -- which run to start -- so they take the
## same path and report a missing scene the same way. A pause screen can reach this
## path too, and a scene change requested while the tree is paused would build the
## new arena frozen, so the tree is always running before the switch.
func _open_scene(path: String) -> void:
	get_tree().paused = false
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
	_pad.cancel()
	_options.visible = false
	_options_button.grab_focus()


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
