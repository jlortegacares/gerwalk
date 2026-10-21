extends Node
## Global signal bus. Lifecycle and cross-scene events only.
## Presentation listens here; gameplay never reaches into the UI.

signal player_health_changed(current: int, maximum: int)
signal player_died
signal enemy_killed
signal camera_shake_requested(strength: float)
