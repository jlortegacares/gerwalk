class_name PadBindings
extends RefCounted
## The pad buttons the player is allowed to move, and where they land.
##
## The nine actions here are the ones the build reads from a single button. The
## sticks move and aim, the boost trigger is an axis, and the keyboard and mouse
## keep their own events, so none of those appear: they are the shape of the
## ship's control rather than a preference, and moving them would mean capturing
## axes and duplicating every action across devices.
##
## Nothing here knows about the menu. The panel edits a dictionary, `apply` pushes
## it into `InputMap`, and the run loop keeps reading the same action names it
## always read.

const CONFIG_PATH: String = GameSettings.CONFIG_PATH
const SECTION: String = "pad"

## The order is also the order the panel draws, so the two most-used buttons sit
## at the top and the two weapon-paging buttons at the bottom.
const ACTIONS: Array[StringName] = [
	&"fire",
	&"missile",
	&"dash",
	&"transform",
	&"bomb",
	&"decoy",
	&"weapon_prev",
	&"weapon_next",
	&"restart",
]

## What `project.godot` ships. A binding that never reaches the file, or a file
## that cannot be trusted, falls back to exactly this pad.
const DEFAULTS: Dictionary = {
	&"fire": JOY_BUTTON_RIGHT_SHOULDER,
	&"missile": JOY_BUTTON_X,
	&"dash": JOY_BUTTON_LEFT_SHOULDER,
	&"transform": JOY_BUTTON_BACK,
	&"bomb": JOY_BUTTON_Y,
	&"decoy": JOY_BUTTON_GUIDE,
	&"weapon_prev": JOY_BUTTON_DPAD_LEFT,
	&"weapon_next": JOY_BUTTON_DPAD_RIGHT,
	&"restart": JOY_BUTTON_START,
}

const LABELS: Dictionary = {
	&"fire": "Fire",
	&"missile": "Missile salvo",
	&"dash": "Dash",
	&"transform": "Transform",
	&"bomb": "Bomb",
	&"decoy": "Decoy",
	&"weapon_prev": "Weapon previous",
	&"weapon_next": "Weapon next",
	&"restart": "Restart",
}

## Godot names the face buttons by the Xbox arrangement: bottom is A, right is B,
## left is X, top is Y. The names are printed as-is so the label and the engine's
## own reading cannot drift apart; a pad that prints a different letter is the
## physical button in the same place, which is what the player is choosing.
const BUTTON_LABELS: Dictionary = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}


## A fresh copy, because every caller edits it and a shared constant would leak
## one panel's edit into the next launch.
static func defaults() -> Dictionary:
	return DEFAULTS.duplicate()


## The pad the game is reading right now. `InputMap` is the source rather than the
## file, so a hand-edited settings file and a live session agree on one answer.
static func current() -> Dictionary:
	var pad: Dictionary = defaults()
	for action: StringName in ACTIONS:
		for event: InputEvent in InputMap.action_get_events(action):
			var button: InputEventJoypadButton = event as InputEventJoypadButton
			if button != null:
				pad[action] = button.button_index
				break
	return pad


## Factory bindings when the file is missing, this section is absent, or the
## stored pad cannot be trusted. An out of range button costs that one action its
## choice; two actions sharing one button means the file no longer describes a
## working pad, so all of it is discarded rather than half honoured.
static func load_bindings(path: String = CONFIG_PATH) -> Dictionary:
	var pad: Dictionary = defaults()
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return pad
	var seen: Dictionary = {}
	for action: StringName in ACTIONS:
		var key: String = String(action)
		if not config.has_section_key(SECTION, key):
			continue
		var button: int = int(config.get_value(SECTION, key))
		if button < 0 or button >= JOY_BUTTON_MAX:
			continue
		if seen.has(button):
			return defaults()
		seen[button] = true
		pad[action] = button
	return pad


## The load keeps whatever else lives in the file, so the display and livery
## sections survive a pad edit the same way each of them survives the other.
static func save_bindings(pad: Dictionary, path: String = CONFIG_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	for action: StringName in ACTIONS:
		config.set_value(SECTION, String(action), int(pad.get(action, DEFAULTS[action])))
	var error: Error = config.save(path)
	if error != OK:
		push_error("Could not save pad bindings to %s: %s" % [path, error_string(error)])


## Points one action at a button, and any action that already held it gets the
## button this one used to hold. Everything else stays put, so the pad is always a
## complete one-button-per-action map and no control can be lost by remapping.
static func assign(pad: Dictionary, action: StringName, button: int) -> void:
	if not DEFAULTS.has(action):
		return
	var previous: int = int(pad.get(action, DEFAULTS[action]))
	for other: StringName in ACTIONS:
		if other != action and int(pad.get(other, DEFAULTS[other])) == button:
			pad[other] = previous
	pad[action] = button


## Rewrites the pad events and keeps every other event the action had, because
## `action_erase_events` drops keyboard and mouse alike. `fire` keeps its mouse
## button, `dash` keeps Space, and a pad remap never takes a key away.
static func apply(pad: Dictionary) -> void:
	for action: StringName in ACTIONS:
		var kept: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			if not event is InputEventJoypadButton:
				kept.append(event)
		InputMap.action_erase_events(action)
		for event: InputEvent in kept:
			InputMap.action_add_event(action, event)
		var button: InputEventJoypadButton = InputEventJoypadButton.new()
		button.button_index = int(pad.get(action, DEFAULTS[action]))
		InputMap.action_add_event(action, button)


static func label_for(button: int) -> String:
	return BUTTON_LABELS.get(button, "Button %d" % button)


static func action_label(action: StringName) -> String:
	return LABELS.get(action, String(action))
