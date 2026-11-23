class_name PadPanel
extends RefCounted
## The controls table inside OPTIONS: one row per action, the keys the build
## already has, and the pad cell that edits the binding.
##
## The panel owns no node of its own. [MainMenu] hands it the three nodes it draws
## into, the style lookup for the menu's own buttons, and the settings path, then
## forwards the raw input while the panel is open. What is left here is the table
## and the one piece of state that makes it an editor: the action waiting for a
## press.

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

## Where the bindings are read from and written to. The menu sets it before
## `build`, and the suite points it at a scratch file.
var settings_path: String = ""
var bindings: Dictionary = PadBindings.defaults()

var _grid: GridContainer
var _hint: Label
var _reset: Button
var _style: Callable
## The empty string is "not listening". A button name cannot be empty, so the
## listening state and the action it is waiting for are the same value.
var _listening: StringName = &""
var _binding_buttons: Dictionary = {}


## Loads the pad, applies it before the first run can start, and draws the table
## from the same dictionary, so what the menu shows is what the ship reads.
## `style` answers one theme slot with the menu's own compacted button style.
func build(
	grid: GridContainer, hint: Label, reset: Button, style: Callable
) -> void:
	_grid = grid
	_hint = hint
	_reset = reset
	_style = style
	_reset.pressed.connect(_on_reset_pressed)
	bindings = PadBindings.load_bindings(settings_path)
	PadBindings.apply(bindings)
	_build_control_rows()
	_refresh_control_rows()


## Reads the raw press while the panel is open and answers whether it was used.
##
## The listening state has to see the press before the button under the cursor
## does, which is why the menu calls this from `_input` and not from
## `_unhandled_input`: GUI input runs between the two, so a focused binding button
## would swallow its own bind.
func handle_input(event: InputEvent) -> bool:
	if _listening == &"":
		return false
	# Escape cancels without becoming a binding. It is read as a key rather than
	# through `ui_cancel` because the pad's own cancel button is a perfectly good
	# thing to put on an action, and reading the action would make it unbindable.
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_cancel_listening()
		return true
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if pad == null or not pad.pressed:
		return false
	var action: StringName = _listening
	PadBindings.assign(bindings, action, pad.button_index)
	PadBindings.apply(bindings)
	PadBindings.save_bindings(bindings, settings_path)
	Sfx.play(&"ui_select")
	_listening = &""
	_refresh_control_rows()
	_binding_buttons[action].grab_focus()
	return true


## Leaving the panel drops any half-finished bind: a listener that outlived the
## close would eat the next pad press in the main menu. The focus stays wherever
## the player left it, because the panel is closing.
func cancel() -> void:
	_listening = &""
	_refresh_control_rows()


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
		_grid.add_child(name_label)

		var keys_label: Label = Label.new()
		keys_label.text = String(row["keys"])
		keys_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.5))
		keys_label.add_theme_font_size_override(&"font_size", 12)
		keys_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_grid.add_child(keys_label)

		var actions: Array = row["actions"]
		if actions.is_empty():
			# A control the player cannot rearrange still occupies its cell, or the
			# pad buttons below it would slide into the middle column.
			_grid.add_child(Control.new())
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
		_grid.add_child(cell)


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
		button.add_theme_stylebox_override(slot, _style.call(slot))
	button.pressed.connect(_on_binding_pressed.bind(action))
	_binding_buttons[action] = button
	return button


func _on_binding_pressed(action: StringName) -> void:
	Sfx.play(&"ui_select")
	_listening = action
	_refresh_control_rows()


func _cancel_listening() -> void:
	var action: StringName = _listening
	_listening = &""
	_refresh_control_rows()
	_binding_buttons[action].grab_focus()


## The factory pad is a choice like any other, so it is written the same way: the
## next launch has to come back to it without the panel being opened first.
func _on_reset_pressed() -> void:
	Sfx.play(&"ui_select")
	_listening = &""
	bindings = PadBindings.defaults()
	PadBindings.apply(bindings)
	PadBindings.save_bindings(bindings, settings_path)
	_refresh_control_rows()
	_binding_buttons[PadBindings.ACTIONS[0]].grab_focus()


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
			button.text = PadBindings.label_for(int(bindings[action]))
			_set_binding_color(button, BINDING_COLOR)
	_hint.text = (
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
