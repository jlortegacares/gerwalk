extends CanvasLayer
## Stateless projection of gameplay state. Reads only from the event bus.

@onready var _health_bar: Control = %HealthBar
@onready var _turbo_bar: Control = %TurboBar
@onready var _weapon_label: Label = %WeaponLabel
@onready var _bomb_pips: Control = %BombPips
@onready var _game_over: Control = %GameOver

var _game_over_visible: bool = false


func _ready() -> void:
	_game_over.visible = false
	GlobalEventBus.player_health_changed.connect(_on_player_health_changed)
	GlobalEventBus.player_turbo_changed.connect(_on_player_turbo_changed)
	GlobalEventBus.player_weapon_changed.connect(_on_player_weapon_changed)
	GlobalEventBus.player_bombs_changed.connect(_on_player_bombs_changed)
	GlobalEventBus.player_died.connect(_on_player_died)


func _unhandled_input(event: InputEvent) -> void:
	if _game_over_visible and event.is_action_pressed(&"restart"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()


func _on_player_health_changed(current: int, maximum: int) -> void:
	_health_bar.set_health(current, maximum)


func _on_player_turbo_changed(current: float, maximum: float) -> void:
	_turbo_bar.set_turbo(current, maximum)


func _on_player_weapon_changed(weapon_name: String) -> void:
	_weapon_label.text = weapon_name


func _on_player_bombs_changed(current: int, maximum: int) -> void:
	_bomb_pips.set_bombs(current, maximum)


func _on_player_died() -> void:
	_game_over_visible = true
	_game_over.visible = true
