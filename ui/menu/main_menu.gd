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
## The controls reference lives in the same panel because a prototype is played by
## people who have not read the docs.

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

## Tests point this at a scratch file so a swatch click never rewrites the real
## settings. Nothing in the game changes it.
var settings_path: String = GameSettings.CONFIG_PATH

var _hull: Color = GameSettings.DEFAULT_HULL
var _nose: Color = GameSettings.DEFAULT_NOSE
var _trim: Color = GameSettings.DEFAULT_TRIM
var _canopy: Color = GameSettings.DEFAULT_CANOPY
var _lines: Color = GameSettings.DEFAULT_LINES
## The reset button is destructive, so it asks twice. The arm lives on the panel,
## not on a timer: closing the panel disarms it, which is the cancel.
var _reset_armed: bool = false

@onready var _start_button: Button = %StartButton
@onready var _city_button: Button = %CityButton
@onready var _continue_button: Button = %ContinueButton
@onready var _pilot_button: Button = %PilotButton
@onready var _options_button: Button = %OptionsButton
@onready var _options: Control = %Options
@onready var _pilot: Control = %Pilot
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


func _close_options() -> void:
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
