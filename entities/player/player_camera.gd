extends Camera3D
## Trauma-style shake plus a spring lag on the rig. The camera hangs off the
## player, so the baseline is dead centre; under thrust the rig trails the body by
## a few pixels and the ship leads the frame, which is what gives the plane mass.

const MAX_OFFSET: float = 0.45
const DECAY_PER_SECOND: float = 2.4

## Steady-state lead is velocity * LAG_SECONDS: 0.54 units (about 6.5 px) at
## cruise and 0.84 at full burner. High rate means it settles in a couple of
## frames instead of wallowing.
const LAG_SECONDS: float = 0.02
const LAG_RATE: float = 26.0

var _shake: float = 0.0
var _base: Vector3 = Vector3.ZERO
var _lag: Vector3 = Vector3.ZERO


func _ready() -> void:
	GlobalEventBus.camera_shake_requested.connect(_on_shake_requested)
	var rig: Node3D = get_parent() as Node3D
	if rig != null:
		_base = rig.position


func _process(delta: float) -> void:
	_update_lag(delta)

	_shake = move_toward(_shake, 0.0, DECAY_PER_SECOND * delta)
	if _shake <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		return

	h_offset = randf_range(-1.0, 1.0) * MAX_OFFSET * _shake
	v_offset = randf_range(-1.0, 1.0) * MAX_OFFSET * _shake


## The body's velocity is in world axes and the player node itself never rotates,
## so the offset can be applied straight to the rig's local position. The rig is
## only pitched, which leaves its X and Z aligned with the plane.
func _update_lag(delta: float) -> void:
	var rig: Node3D = get_parent() as Node3D
	if rig == null or not (rig.get_parent() is CharacterBody3D):
		return
	var body: CharacterBody3D = rig.get_parent() as CharacterBody3D
	var target: Vector3 = -body.velocity * LAG_SECONDS
	_lag = _lag.lerp(target, 1.0 - exp(-LAG_RATE * delta))
	rig.position = _base + _lag


func _on_shake_requested(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))
