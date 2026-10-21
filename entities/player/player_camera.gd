extends Camera3D
## Trauma-style shake. The camera is a child of the player so the player is
## always exactly centred; only the offsets move, never the target.

const MAX_OFFSET: float = 0.45
const DECAY_PER_SECOND: float = 2.4

var _shake: float = 0.0


func _ready() -> void:
	GlobalEventBus.camera_shake_requested.connect(_on_shake_requested)


func _process(delta: float) -> void:
	_shake = move_toward(_shake, 0.0, DECAY_PER_SECOND * delta)
	if _shake <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		return

	h_offset = randf_range(-1.0, 1.0) * MAX_OFFSET * _shake
	v_offset = randf_range(-1.0, 1.0) * MAX_OFFSET * _shake


func _on_shake_requested(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))
