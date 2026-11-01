extends CanvasLayer
## Stateless projection of gameplay state. The bars and labels read only from the
## event bus; `Radar` polls the enemy group for the one thing that is not an event,
## a contact's bearing.
##
## The death screen is the exception: it asks the player a question, so its answers
## have to become scene changes somewhere, and the HUD is the node that already
## owns the run's lifetime.

## The boot scene, which is where the death screen's other answer goes.
const MENU_SCENE: String = "res://ui/menu/main_menu.tscn"

@onready var _health_bar: Control = %HealthBar
@onready var _turbo_bar: Control = %TurboBar
@onready var _weapon_label: Label = %WeaponLabel
@onready var _mode_label: Label = %ModeLabel
@onready var _bomb_pips: Control = %BombPips
@onready var _salvo_label: Label = %SalvoLabel
@onready var _decoy_label: Label = %DecoyLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _game_over: GameOver = %GameOver


func _ready() -> void:
	GlobalEventBus.player_health_changed.connect(_on_player_health_changed)
	GlobalEventBus.player_turbo_changed.connect(_on_player_turbo_changed)
	GlobalEventBus.player_weapon_changed.connect(_on_player_weapon_changed)
	GlobalEventBus.player_mode_changed.connect(_on_player_mode_changed)
	GlobalEventBus.player_bombs_changed.connect(_on_player_bombs_changed)
	GlobalEventBus.player_missile_salvo_changed.connect(_on_player_missile_salvo_changed)
	GlobalEventBus.player_decoy_changed.connect(_on_player_decoy_changed)
	GlobalEventBus.score_changed.connect(_on_score_changed)
	GlobalEventBus.player_died.connect(_on_player_died)
	_game_over.respawn_requested.connect(_restart_run)
	_game_over.menu_requested.connect(_back_to_menu)


## The countdown and the buttons both end a run the same way: the arena is rebuilt
## from the scene, so a death never leaves half a fight behind.
func _restart_run() -> void:
	get_tree().reload_current_scene()


func _back_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


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


## Zero-padded so the label keeps its width as the score climbs; a right-aligned
## number that changes digit count reads as a jitter.
func _on_score_changed(total: int) -> void:
	_score_label.text = "SCORE %06d" % total


func _on_player_died() -> void:
	# The blast gets the frame to itself: the panel is dark enough to hide it, so
	# the death screen arrives once the fireball has opened.
	await get_tree().create_timer(GameOver.BLAST_DELAY).timeout
	_game_over.start()
