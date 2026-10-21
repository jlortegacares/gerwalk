extends Control
## Segmented HP bar (pillar P2). Draw-only: no theme dependency, no per-frame work.

const SEGMENT_WIDTH: float = 34.0
const SEGMENT_HEIGHT: float = 16.0
const SEGMENT_GAP: float = 6.0
const FILLED_COLOR: Color = Color(0.24, 0.9, 0.79, 1.0)
const EMPTY_COLOR: Color = Color(1, 1, 1, 0.1)
const BORDER_COLOR: Color = Color(1, 1, 1, 0.28)

var _current: int = 0
var _maximum: int = 6


func set_health(current: int, maximum: int) -> void:
	_maximum = maxi(maximum, 1)
	_current = clampi(current, 0, _maximum)
	custom_minimum_size = Vector2(
		float(_maximum) * (SEGMENT_WIDTH + SEGMENT_GAP) - SEGMENT_GAP, SEGMENT_HEIGHT
	)
	queue_redraw()


func _draw() -> void:
	for i in _maximum:
		var origin: Vector2 = Vector2(float(i) * (SEGMENT_WIDTH + SEGMENT_GAP), 0.0)
		var rect: Rect2 = Rect2(origin, Vector2(SEGMENT_WIDTH, SEGMENT_HEIGHT))
		var fill: Color = FILLED_COLOR if i < _current else EMPTY_COLOR
		draw_rect(rect, fill, true)
		draw_rect(rect, BORDER_COLOR, false, 1.0)
