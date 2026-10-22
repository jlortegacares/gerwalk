extends Control
## Bomb charges. Segmented on purpose: unlike the turbo reserve these are discrete
## uses, so the player has to count them at a glance instead of reading a level.
## Draw-only and event-fed, like the HP and turbo bars.

const PIP_SIZE: Vector2 = Vector2(18.0, 10.0)
const PIP_GAP: float = 5.0
const FILLED_COLOR: Color = Color(0.62, 0.95, 1.0, 1.0)
const SPENT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.10)
const BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.28)

var _current: int = 0
var _maximum: int = 1


func set_bombs(current: int, maximum: int) -> void:
	_current = current
	_maximum = maxi(maximum, 1)
	queue_redraw()


## Always draws the full rack, spent pips included: the size of the rack is
## information too, and a bar that shrinks hides how much a refill is worth.
func _draw() -> void:
	for index in _maximum:
		var rect: Rect2 = Rect2(
			Vector2(index * (PIP_SIZE.x + PIP_GAP), 0.0), PIP_SIZE
		)
		draw_rect(rect, FILLED_COLOR if index < _current else SPENT_COLOR)
		draw_rect(rect, BORDER_COLOR, false, 1.0)
