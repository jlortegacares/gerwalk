extends CanvasLayer
## Stateless projection of gameplay state. The bars and labels read only from the
## event bus; `Radar` polls the enemy group for the one thing that is not an event,
## a contact's bearing.

@onready var _health_bar: Control = %HealthBar
@onready var _turbo_bar: Control = %TurboBar
@onready var _weapon_label: Label = %WeaponLabel
@onready var _mode_label: Label = %ModeLabel
@onready var _bomb_pips: Control = %BombPips
@onready var _salvo_label: Label = %SalvoLabel
@onready var _decoy_label: Label = %DecoyLabel
@onready var _game_over: Control = %GameOver

var _game_over_visible: bool = false


func _ready() -> void:
	_game_over.visible = false
	GlobalEventBus.player_health_changed.connect(_on_player_health_changed)
	GlobalEventBus.player_turbo_changed.connect(_on_player_turbo_changed)
	GlobalEventBus.player_weapon_changed.connect(_on_player_weapon_changed)
	GlobalEventBus.player_mode_changed.connect(_on_player_mode_changed)
	GlobalEventBus.player_bombs_changed.connect(_on_player_bombs_changed)
	GlobalEventBus.player_missile_salvo_changed.connect(_on_player_missile_salvo_changed)
	GlobalEventBus.player_decoy_changed.connect(_on_player_decoy_changed)
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


## The mode is the frame the rest of the HUD is read in, so it sits above the
## weapon name instead of competing with it.
func _on_player_mode_changed(mode_name: String) -> void:
	_mode_label.text = mode_name


func _on_player_bombs_changed(current: int, maximum: int) -> void:
	_bomb_pips.set_bombs(current, maximum)


## The hold decides how many missiles leave, so the loaded count has to be visible
## while the button is down.
func _on_player_missile_salvo_changed(current: int, maximum: int) -> void:
	_salvo_label.visible = current > 0
	_salvo_label.text = "SALVO %d / %d" % [current, maximum]


## The decoy has no count, only a cooldown, so the label is a state rather than a
## level: ready means the button will work, charging means it will not.
func _on_player_decoy_changed(ready: bool) -> void:
	_decoy_label.text = "DECOY READY" if ready else "DECOY CHARGING"
	_decoy_label.modulate = (
		Color(1.0, 1.0, 1.0, 1.0) if ready else Color(1.0, 1.0, 1.0, 0.35)
	)


func _on_player_died() -> void:
	_game_over_visible = true
	_game_over.visible = true
