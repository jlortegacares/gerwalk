class_name GameOver
extends Control
## The death screen: how long until the run restarts, and the two ways to answer
## that question early.
##
## The countdown is the default answer, so a player who puts the controller down
## still gets a fresh run instead of a frozen wreck. It does not pause the world:
## the ship is already gone and the fight behind the panel keeps flying, which is
## what the arena did before this screen had a counter.
##
## The screen asks, its owner navigates. `respawn_requested` and `menu_requested`
## are the two answers and the HUD turns them into a scene change, which is what
## lets a test press the buttons without reloading the scene it is running in.

signal respawn_requested
signal menu_requested

## Long enough to read the panel and change your mind, short enough that a death
## does not read as a pause.
const RESPAWN_SECONDS: float = 5.0

@onready var _counter: Label = %Counter
@onready var _continue_button: Button = %ContinueButton
@onready var _menu_button: Button = %MenuButton

## Seconds left on the countdown. Public so the rules can be checked without
## waiting the whole five seconds out.
var remaining: float = 0.0
## One answer per death: the countdown fires once, and a button pressed on the
## same frame as the last tick cannot ask for two scene changes.
var _armed: bool = false


func _ready() -> void:
	_continue_button.pressed.connect(_continue_run)
	_menu_button.pressed.connect(_back_to_menu)


## Opens the screen and starts the count. Called once, from the death event.
func start() -> void:
	_armed = true
	remaining = RESPAWN_SECONDS
	_paint()
	visible = true
	# Focus, not a hover: the same two answers have to work on a gamepad.
	_continue_button.grab_focus()


func _process(delta: float) -> void:
	if not _armed:
		return
	remaining = maxf(remaining - delta, 0.0)
	_paint()
	if remaining <= 0.0:
		_continue_run()


## The keys are shortcuts for the buttons, not a second way to play the screen.
func _unhandled_input(event: InputEvent) -> void:
	if not _armed:
		return
	if event.is_action_pressed(&"restart"):
		get_viewport().set_input_as_handled()
		_continue_run()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_back_to_menu()


func _continue_run() -> void:
	if not _armed:
		return
	_armed = false
	respawn_requested.emit()


func _back_to_menu() -> void:
	if not _armed:
		return
	_armed = false
	menu_requested.emit()


## Whole seconds, rounded up: the panel reads "5" for the whole first second
## instead of showing 4 while there is still a full second to go.
func _paint() -> void:
	_counter.text = "RESPAWN IN %d" % ceili(remaining)
