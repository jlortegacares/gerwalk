class_name Radar
extends Control
## Bottom-right scope: the play plane around the ship, with the ship at the centre.
##
## World-fixed, not heading-up, because the camera never yaws. The rig is pitched
## 75 degrees and stays behind the world's -Z, so screen up is -Z and screen right
## is +X in both modes. A scope that rotated with the nose would put a contact on
## the opposite side of the screen from where it is actually drawn, and "that one,
## over there" is the whole job of a radar in this game.
##
## Detection is a 360 degree range, not the missile radar's forward cone: the cone
## answers "what can I shoot", the scope answers "what is around me". Contacts past
## the range are not drawn at all instead of pinned to the rim, because a blip on
## the rim claims a bearing the ship cannot act on.
##
## This is the one HUD element that polls the scene instead of the event bus.
## Health, mode and charges are transitions and fit a signal; a contact's bearing
## changes every frame, and streaming two vectors through the bus would add a
## per-frame allocation to say what a group query already says.

const DETECTION_RANGE: float = 140.0

## Nearly opaque on purpose. At the 0.55 the first pass used, the world showed
## through the disk, and a turret flying under the corner read as a contact that
## was not on the scope at all. The backdrop is the scope's floor, not a tint.
const BACKDROP_COLOR: Color = Color(0.03, 0.05, 0.075, 0.95)
const RIM_COLOR: Color = Color(0.55, 0.85, 0.95, 0.45)
const GRID_COLOR: Color = Color(0.55, 0.85, 0.95, 0.10)
const SWEEP_COLOR: Color = Color(0.55, 0.95, 0.85, 0.12)
const SWEEP_EDGE_COLOR: Color = Color(0.55, 0.95, 0.85, 0.32)
const BLIP_COLOR: Color = Color(1.0, 0.32, 0.40, 1.0)
const BLIP_HALO_COLOR: Color = Color(1.0, 0.32, 0.40, 0.16)
const MARKER_COLOR: Color = Color(0.78, 1.0, 0.96, 1.0)

const BLIP_RADIUS: float = 3.0
const MARKER_LENGTH: float = 9.0
const MARKER_HALF_WIDTH: float = 4.6
## One sweep every couple of seconds: slow enough to read as a scan, fast enough
## that a contact does not sit unpainted for long under the beam.
const SWEEP_PERIOD: float = 2.6
const SWEEP_ARC: float = 0.5

var _sweep: float = 0.0
var _player: Player = null


func _process(delta: float) -> void:
	_sweep = fposmod(_sweep + TAU * delta / SWEEP_PERIOD, TAU)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = _scope_radius()

	draw_circle(center, radius, BACKDROP_COLOR)
	# One half-range ring is the only distance cue. A full ladder would clutter a
	# scope this small and cover the contacts it exists to show.
	draw_arc(center, radius * 0.5, 0.0, TAU, 48, GRID_COLOR, 1.0, true)
	draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), GRID_COLOR, 1.0, true)
	draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), GRID_COLOR, 1.0, true)

	_draw_sweep(center, radius)
	for offset in contact_offsets():
		var point: Vector2 = center + offset
		draw_circle(point, BLIP_RADIUS * 1.8, BLIP_HALO_COLOR)
		draw_circle(point, BLIP_RADIUS, BLIP_COLOR)

	_draw_marker(center)
	draw_arc(center, radius, 0.0, TAU, 64, RIM_COLOR, 1.5, true)


## The sweep is a fan of thin wedges instead of one flat polygon, so it fades away
## from its leading edge. Drawn under the contacts: a scan must never hide one.
func _draw_sweep(center: Vector2, radius: float) -> void:
	var slices: int = 12
	for index in slices:
		var near: float = _sweep - SWEEP_ARC * float(index) / float(slices)
		var far: float = _sweep - SWEEP_ARC * float(index + 1) / float(slices)
		var fade: float = 1.0 - float(index) / float(slices)
		var wedge: PackedVector2Array = PackedVector2Array([
			center,
			center + Vector2(cos(far), sin(far)) * radius,
			center + Vector2(cos(near), sin(near)) * radius,
		])
		draw_colored_polygon(wedge, Color(SWEEP_COLOR, SWEEP_COLOR.a * fade))
	draw_line(
		center,
		center + Vector2(cos(_sweep), sin(_sweep)) * radius,
		SWEEP_EDGE_COLOR,
		1.0,
		true
	)


func _draw_marker(center: Vector2) -> void:
	var direction: Vector2 = marker_direction()
	var forward: Vector2 = direction * MARKER_LENGTH
	var side: Vector2 = Vector2(-direction.y, direction.x) * MARKER_HALF_WIDTH
	draw_colored_polygon(
		PackedVector2Array([
			center + forward,
			center - forward * 0.6 + side,
			center - forward * 0.6 - side,
		]),
		MARKER_COLOR
	)


## Pixel offsets of every detected contact, relative to the centre. Public so the
## smoke test drives the same query and mapping the draw does instead of a copy of
## the arithmetic that could drift from it.
func contact_offsets() -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	var player: Player = _find_player()
	if player == null:
		return offsets

	var scale: float = (_scope_radius() - BLIP_RADIUS - 1.0) / DETECTION_RANGE
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy: Node3D = node as Node3D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var offset: Vector2 = _planar_offset(player, enemy.global_position)
		if offset.length() > DETECTION_RANGE:
			continue
		offsets.append(offset * scale)
	return offsets


## Whether a world point is inside the scope. The draw and the test read the same
## rule, so a blip can never appear outside the ring.
func detects(point: Vector3) -> bool:
	var player: Player = _find_player()
	if player == null:
		return false
	return _planar_offset(player, point).length() <= DETECTION_RANGE


## Unit vector the marker points along, in scope space. The airframe's yaw follows
## the nose, so this is where the ship points rather than where it drifts.
func marker_direction() -> Vector2:
	var player: Player = _find_player()
	if player == null:
		return Vector2.UP
	var nose: Vector3 = player.nose_direction()
	var flat: Vector2 = Vector2(nose.x, nose.z)
	if flat.length_squared() < 0.0001:
		return Vector2.UP
	return flat.normalized()


func _planar_offset(from: Node3D, to: Vector3) -> Vector2:
	return Vector2(
		to.x - from.global_position.x,
		to.z - from.global_position.z
	)


func _scope_radius() -> float:
	return minf(size.x, size.y) * 0.5 - 6.0


func _find_player() -> Player:
	if is_instance_valid(_player):
		return _player
	_player = null
	for node in get_tree().get_nodes_in_group(&"player"):
		if node is Player:
			_player = node as Player
			break
	return _player
