extends Node
## Global signal bus. Lifecycle and cross-scene events only.
## Presentation listens here; gameplay never reaches into the UI.

signal player_health_changed(current: int, maximum: int)
signal player_turbo_changed(current: float, maximum: float)
signal player_weapon_changed(weapon_name: String)
signal player_mode_changed(mode_name: String)
signal player_bombs_changed(current: int, maximum: int)
signal player_missile_salvo_changed(current: int, maximum: int)
signal player_decoy_changed(ready: bool)
signal player_died
## A hostile died, and what the kill is worth. The value travels with the event so
## the run's score does not depend on who spawned the enemy.
signal enemy_killed(value: int)
signal score_changed(total: int)
## The pilot's persistent record changed. Kills and level travel together because
## the HUD draws them as one readout: a level with no progress bar would be half a
## fact, and `kills_for_next` is what turns the count into a bar.
signal pilot_progress_changed(
	total_kills: int, level: int, kills_into_level: int, kills_for_next: int
)
signal camera_shake_requested(strength: float)
