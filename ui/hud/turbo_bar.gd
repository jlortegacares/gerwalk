extends Control
## Afterburner reserve. Continuous, not segmented: the reserve drains and refills
## on every frame, so segments would quantise a value that has no natural steps.
## Draw-only and event-fed, like the HP bar.

const BAR_SIZE: Vector2 = Vector2(234.0, 10.0)
const FILLED_COLOR: Color = Color(1.0, 0.72, 0.32, 1.0)
const SPENT_COLOR: Color = Color(1, 1, 1, 0.1)
const BORDER_COLOR: Color = Color(1, 1, 1, 0.28)

var _ratio: float = 1.0


func set_turbo(current: float, maximum: float) -> void:
	_ratio = clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var frame: Rect2 = Rect2(Vector2.ZERO, BAR_SIZE)
	draw_rect(frame, SPENT_COLOR, true)
	if _ratio > 0.0:
		draw_rect(
			Rect2(frame.position, Vector2(BAR_SIZE.x * _ratio, BAR_SIZE.y)),
			FILLED_COLOR,
			true
		)
	draw_rect(frame, BORDER_COLOR, false, 1.0)
