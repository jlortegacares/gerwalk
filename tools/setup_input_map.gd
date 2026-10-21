extends SceneTree
## One-shot maintenance tool. Writes the project input map through Godot's own
## serializer instead of hand-formatting InputEvent objects inside project.godot.
##
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       --script tools/setup_input_map.gd

const DEADZONE: float = 0.2


func _init() -> void:
	_add("move_left", [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add("move_right", [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add("move_up", [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add("move_down", [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])

	_add("aim_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_add("aim_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_add("aim_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_add("aim_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])

	_add("fire", [_mouse(MOUSE_BUTTON_LEFT), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	# Dash is a short invulnerable burst; boost is the sustained afterburner.
	_add("dash", [_key(KEY_SPACE), _button(JOY_BUTTON_LEFT_SHOULDER)])
	_add("boost", [_key(KEY_SHIFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add("restart", [_key(KEY_R), _button(JOY_BUTTON_START)])

	var error: Error = ProjectSettings.save()
	if error != OK:
		printerr("Could not save project settings: %s" % error_string(error))
	quit(0 if error == OK else 1)


func _add(action: String, events: Array) -> void:
	ProjectSettings.set_setting(
		"input/" + action, {"deadzone": DEADZONE, "events": events}
	)


func _key(code: int) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code as Key
	return event


func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis as JoyAxis
	event.axis_value = value
	return event


func _button(button: int) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button as JoyButton
	return event


func _mouse(button: int) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button as MouseButton
	return event
