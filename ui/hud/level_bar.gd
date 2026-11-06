extends Control
## Pilot progress towards the next level. Draw-only and event-fed, like the HP and
## turbo bars: the HUD owns no state, it projects what the bus tells it.
##
## At the level cap there is no next level, so the bar reads full instead of empty:
## the ladder is complete, not stuck at zero.

const BAR_SIZE: Vector2 = Vector2(234.0, 8.0)
const FILLED_COLOR: Color = Color(0.55, 0.98, 0.9, 1.0)
const SPENT_COLOR: Color = Color(1, 1, 1, 0.1)
const BORDER_COLOR: Color = Color(1, 1, 1, 0.28)

var _ratio: float = 0.0


func set_progress(kills_into_level: int, kills_for_next: int) -> void:
	if kills_for_next <= 0:
		_ratio = 1.0
	else:
		_ratio = clampf(float(kills_into_level) / float(kills_for_next), 0.0, 1.0)
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
