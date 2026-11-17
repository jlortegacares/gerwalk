extends CanvasLayer
## Stateless projection of gameplay state. The bars and labels read only from the
## event bus; `Radar` polls the enemy group for the one thing that is not an event,
## a contact's bearing.
##
## The death screen is the exception: it asks the player a question, so its answers
## have to become scene changes somewhere, and the HUD is the node that already
## owns the run's lifetime.
##
## The same ownership makes it the pause screen's host. Escape can arrive at any
## moment of a live run, and the answer is always the same node: a lazily built
## menu over a frozen tree, so an interrupted fight costs nothing until the player
## asks for it.

## The boot scene, which is where the death screen's other answer goes. The pause
## screen is the same scene with `in_game` set, so the two never drift apart.
const MENU_SCENE: String = "res://ui/menu/main_menu.tscn"

@onready var _health_bar: Control = %HealthBar
@onready var _turbo_bar: Control = %TurboBar
@onready var _weapon_label: Label = %WeaponLabel
@onready var _mode_label: Label = %ModeLabel
@onready var _bomb_pips: Control = %BombPips
@onready var _salvo_label: Label = %SalvoLabel
@onready var _decoy_label: Label = %DecoyLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _level_label: Label = %LevelLabel
@onready var _level_bar: Control = %LevelBar
@onready var _hint: Label = %HintLabel
@onready var _boss_root: Control = %BossRoot
@onready var _boss_name: Label = %BossName
@onready var _boss_bar: Control = %BossBar
@onready var _game_over: GameOver = %GameOver

## The menu currently open over the run, or null. One at a time: a second Escape
## is the pause menu's key to close, not a reason to build a second menu.
var _pause: MainMenu = null
## A dead pilot has no run to come back to, so Escape belongs to the death screen
## and never opens the pause.
var _dead: bool = false
## Tests point the pause menu at a scratch file, the same way they point the boot
## menu's `settings_path`. Nothing in the game changes it.
var pause_settings_path: String = GameSettings.CONFIG_PATH


func _ready() -> void:
	GlobalEventBus.player_health_changed.connect(_on_player_health_changed)
	GlobalEventBus.player_turbo_changed.connect(_on_player_turbo_changed)
	GlobalEventBus.player_weapon_changed.connect(_on_player_weapon_changed)
	GlobalEventBus.player_mode_changed.connect(_on_player_mode_changed)
	GlobalEventBus.player_bombs_changed.connect(_on_player_bombs_changed)
	GlobalEventBus.player_missile_salvo_changed.connect(_on_player_missile_salvo_changed)
	GlobalEventBus.player_decoy_changed.connect(_on_player_decoy_changed)
	GlobalEventBus.score_changed.connect(_on_score_changed)
	GlobalEventBus.pilot_progress_changed.connect(_on_pilot_progress_changed)
	GlobalEventBus.boss_appeared.connect(_on_boss_appeared)
	GlobalEventBus.boss_health_changed.connect(_on_boss_health_changed)
	GlobalEventBus.boss_defeated.connect(_on_boss_defeated)
	GlobalEventBus.player_died.connect(_on_player_died)
	_game_over.respawn_requested.connect(_restart_run)
	_game_over.menu_requested.connect(_back_to_menu)

	# The record already exists when the run starts, and no kill may happen before
	# the first frame, so reading it here is the run's opening state instead of
	# waiting for a signal that only fires on the next kill.
	_show_pilot(GameProgress.instance())
	_refresh_controls_hint()


## The hint is the flight reference, so it names the buttons the pad is on right
## now. Reading `InputMap` instead of the settings file keeps it honest even if the
## file was edited by hand after the menu loaded the pad.
func _refresh_controls_hint() -> void:
	var pad: Dictionary = PadBindings.current()
	_hint.text = (
		"WASD / left stick: move    mouse or right stick: aim    %s: fire    "
		+ "1-3 or %s/%s: weapon    hold RMB / %s: missile salvo    E / %s: bomb    "
		+ "C / %s: decoy    Shift / RT: afterburner    Space / %s: dash    "
		+ "Q / %s: transform    R: restart"
	) % [
		PadBindings.label_for(int(pad[&"fire"])),
		PadBindings.label_for(int(pad[&"weapon_prev"])),
		PadBindings.label_for(int(pad[&"weapon_next"])),
		PadBindings.label_for(int(pad[&"missile"])),
		PadBindings.label_for(int(pad[&"bomb"])),
		PadBindings.label_for(int(pad[&"decoy"])),
		PadBindings.label_for(int(pad[&"dash"])),
		PadBindings.label_for(int(pad[&"transform"])),
	]


## Escape is the player's own key, so it is read while the run is live rather than
## through a menu button. The pause is the only thing that stops the tree here: the
## death screen asks its question on a world that keeps flying, and the pause does
## not take that screen's key away.
func _unhandled_input(event: InputEvent) -> void:
	if _dead or is_instance_valid(_pause):
		return
	if event.is_action_pressed(&"ui_cancel"):
		# The press is consumed before the menu is built: the node that just
		# appeared must not be handed the same Escape and resume on its first frame.
		get_viewport().set_input_as_handled()
		_open_pause()


## The menu is built on the first Escape and lives only while the run is stopped.
## It is the one node in the run that keeps processing: everything else, the ship
## included, inherits the pause. The engine hum is silenced by hand because the
## audio voices are always-on so a menu blip still plays.
func _open_pause() -> void:
	var scene: PackedScene = load(MENU_SCENE)
	if scene == null:
		return
	var pause: MainMenu = scene.instantiate() as MainMenu
	if pause == null:
		return
	pause.in_game = true
	pause.settings_path = pause_settings_path
	pause.process_mode = Node.PROCESS_MODE_ALWAYS
	pause.resume_requested.connect(_close_pause)
	_pause = pause
	add_child(pause)
	Sfx.engine(false)
	get_tree().paused = true


## The menu goes away before the tree resumes, so the frame that unpauses is the
## frame that already shows the fight. The hum comes back on its own: the ship's
## next frame sets it from the speed it is actually flying at.
func _close_pause() -> void:
	if _pause == null:
		return
	var pause: MainMenu = _pause
	_pause = null
	if is_instance_valid(pause):
		pause.hide()
		pause.queue_free()
	get_tree().paused = false


## The countdown and the buttons both end a run the same way: the arena is rebuilt
## from the scene, so a death never leaves half a fight behind.
func _restart_run() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _back_to_menu() -> void:
	get_tree().paused = false
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


## The level and its progress are one readout: the label names the rank, the bar
## says how far the next one is. At the cap there is no next rank, so the label says
## MAX and the bar fills.
func _on_pilot_progress_changed(
	total_kills: int, level: int, kills_into_level: int, kills_for_next: int
) -> void:
	_render_pilot(total_kills, level, kills_into_level, kills_for_next)


func _show_pilot(progress: GameProgress) -> void:
	_render_pilot(
		progress.total_kills, progress.level(), progress.kills_into(), progress.kills_to_next()
	)


func _render_pilot(
	total_kills: int, level: int, kills_into_level: int, kills_for_next: int
) -> void:
	var next_text: String = "MAX" if kills_for_next <= 0 else "%d TO NEXT" % kills_for_next
	_level_label.text = "PILOT LV %d   %d KILLS   %s" % [level, total_kills, next_text]
	_level_bar.set_progress(kills_into_level, kills_for_next)


## The bar arrives with the ship and leaves with it. A boss bar parked at zero
## after the kill would keep the fight on screen after it ended.
func _on_boss_appeared(boss_name: String, maximum: int) -> void:
	_boss_name.text = boss_name
	_boss_bar.set_health(maximum, maximum)
	_boss_root.visible = true


func _on_boss_health_changed(current: int, maximum: int) -> void:
	_boss_bar.set_health(current, maximum)


func _on_boss_defeated() -> void:
	_boss_root.visible = false


func _on_player_died() -> void:
	# The pause is closed to the dead: the run cannot be resumed, so Escape belongs
	# to the screen that offers the two real answers.
	_dead = true
	# The blast gets the frame to itself: the panel is dark enough to hide it, so
	# the death screen arrives once the fireball has opened.
	await get_tree().create_timer(GameOver.BLAST_DELAY).timeout
	_game_over.start()
