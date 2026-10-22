extends Node
## Global signal bus. Lifecycle and cross-scene events only.
## Presentation listens here; gameplay never reaches into the UI.

signal player_health_changed(current: int, maximum: int)
signal player_turbo_changed(current: float, maximum: float)
signal player_weapon_changed(weapon_name: String)
signal player_mode_changed(mode_name: String)
signal player_bombs_changed(current: int, maximum: int)
signal player_died
signal enemy_killed
signal camera_shake_requested(strength: float)
