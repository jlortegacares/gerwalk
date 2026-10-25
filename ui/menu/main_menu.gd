class_name MainMenu
extends Control
## Boot scene. It owns the two destinations the game has before a run: the arena,
## and a settings panel.
##
## The window mode is the one display option the build honours, so it is applied
## here and nowhere else: the arena inherits it, and `GameSettings` restores it on
## the next launch. The livery is the one option the player sees in flight, so it
## is previewed on a live copy of the airframe instead of on a colour chip: the
## hull is a texture, and a chip does not say how a colour will land on it.
##
## The controls reference lives in the same panel because a prototype is played by
## people who have not read the docs.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"

## One palette, offered twice. The hull and the stripe are the same decision, so
## they get the same eight colours instead of two curated lists nobody asked for.
## The first two entries are the colours the file ships, which makes "factory" a
## swatch a player can come back to rather than a hidden reset.
const PALETTE: Array[Color] = [
	GameSettings.DEFAULT_HULL,
	GameSettings.DEFAULT_TRIM,
	Color(0.80, 0.14, 0.16),
	Color(0.93, 0.72, 0.18),
	Color(0.10, 0.62, 0.60),
	Color(0.13, 0.14, 0.17),
	Color(0.25, 0.47, 0.85),
	Color(0.86, 0.42, 0.12),
]
const SWATCH_SIZE: float = 34.0

## Tests point this at a scratch file so a swatch click never rewrites the real
## settings. Nothing in the game changes it.
var settings_path: String = GameSettings.CONFIG_PATH

var _hull: Color = GameSettings.DEFAULT_HULL
var _trim: Color = GameSettings.DEFAULT_TRIM

@onready var _start_button: Button = %StartButton
@onready var _options_button: Button = %OptionsButton
@onready var _options: Control = %Options
@onready var _fullscreen: CheckButton = %Fullscreen
@onready var _back_button: Button = %BackButton
@onready var _preview: LiveryPreview = %Preview
@onready var _hull_row: HBoxContainer = %HullRow
@onready var _trim_row: HBoxContainer = %TrimRow


func _ready() -> void:
	_options.visible = false

	_start_button.pressed.connect(_on_start_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)

	var fullscreen: bool = GameSettings.load_fullscreen(settings_path)
	GameSettings.apply_fullscreen(fullscreen)
	# The stored value is a state to display, not a decision to announce: applying
	# it must not fire the handler that saves it again.
	_fullscreen.set_pressed_no_signal(fullscreen)

	_hull = GameSettings.load_hull(settings_path)
	_trim = GameSettings.load_trim(settings_path)
	# The preview is a view: it is told the livery before it ever builds, so the
	# airframe cannot appear in one colour and switch to another a frame later.
	_preview.set_livery(_hull, _trim)
	_build_swatches(_hull_row, _hull, _on_hull_picked)
	_build_swatches(_trim_row, _trim, _on_trim_picked)

	_start_button.grab_focus()


## Escape is the way out of the panel, the same way it is out of every other panel
## a player has ever opened.
func _unhandled_input(event: InputEvent) -> void:
	if _options.visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_options()


func _on_start_pressed() -> void:
	var error: Error = get_tree().change_scene_to_file(ARENA_SCENE)
	if error != OK:
		push_error("Could not open %s: %s" % [ARENA_SCENE, error_string(error)])


func _on_options_pressed() -> void:
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
	_close_options()


func _close_options() -> void:
	_options.visible = false
	_options_button.grab_focus()


func _on_fullscreen_toggled(enabled: bool) -> void:
	GameSettings.apply_fullscreen(enabled)
	GameSettings.save_fullscreen(enabled, settings_path)


func _on_hull_picked(color: Color) -> void:
	_hull = color
	_preview.set_livery(_hull, _trim)
	GameSettings.save_livery(_hull, _trim, settings_path)


func _on_trim_picked(color: Color) -> void:
	_trim = color
	_preview.set_livery(_hull, _trim)
	GameSettings.save_livery(_hull, _trim, settings_path)


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
