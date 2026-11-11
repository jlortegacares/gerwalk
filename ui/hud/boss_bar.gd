extends Control
## The mothership's health. One continuous bar instead of the ship's segments: the
## hull is fought as three pools, but the bar reads their sum, and a segmented bar
## would read as "six hits left" when the fight is a minute long.
##
## Draw-only and event-fed, like every other bar in the HUD: the boss owns the
## number, the bus carries it, this node projects it.

const BAR_SIZE: Vector2 = Vector2(520.0, 14.0)
const FILLED_COLOR: Color = Color(1.0, 0.42, 0.52, 1.0)
const SPENT_COLOR: Color = Color(1, 1, 1, 0.1)
const BORDER_COLOR: Color = Color(1, 1, 1, 0.32)

var _ratio: float = 1.0


func set_health(current: int, maximum: int) -> void:
	_ratio = clampf(float(current) / float(maxi(maximum, 1)), 0.0, 1.0)
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
