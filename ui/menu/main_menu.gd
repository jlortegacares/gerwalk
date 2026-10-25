class_name MainMenu
extends Control
## Boot scene. It owns the two destinations the game has before a run: the arena,
## and a settings panel.
##
## The window mode is the one display option the build honours, so it is applied
## here and nowhere else: the arena inherits it, and `GameSettings` restores it on
## the next launch. The controls reference lives in the same panel because a
## prototype is played by people who have not read the docs.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"

@onready var _start_button: Button = %StartButton
@onready var _options_button: Button = %OptionsButton
@onready var _options: Control = %Options
@onready var _fullscreen: CheckButton = %Fullscreen
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_options.visible = false

	_start_button.pressed.connect(_on_start_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)

	var fullscreen: bool = GameSettings.load_fullscreen()
	GameSettings.apply_fullscreen(fullscreen)
	# The stored value is a state to display, not a decision to announce: applying
	# it must not fire the handler that saves it again.
	_fullscreen.set_pressed_no_signal(fullscreen)

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
	_back_button.grab_focus()


func _on_back_pressed() -> void:
	_close_options()


func _close_options() -> void:
	_options.visible = false
	_options_button.grab_focus()


func _on_fullscreen_toggled(enabled: bool) -> void:
	GameSettings.apply_fullscreen(enabled)
	GameSettings.save_fullscreen(enabled)
