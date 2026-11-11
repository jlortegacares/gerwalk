class_name BossWeapon
extends Node3D
## One section's gun.
##
## The hull answers with a different weapon from each third: the bow sprays a vulcan
## burst, the middle launches a guided pair and the stern cuts a laser across the
## deck. They run on separate clocks on purpose. A capital ship that fired every gun
## on one beat would read as a single turret with three muzzles, and destroying a
## section has to remove a threat the player can name.
##
## The weapon sits at its section's centre on the play plane, not on the section body:
## bullets and missiles live on that plane, and a shot born at the deck height would
## fly over the player forever. It asks the boss whether its section is still alive on
## every tick, so a destroyed third goes silent without a second bookkeeping path.
##
## Every weapon telegraphs with the line it will fire along. The aim locks when the
## windup opens, so the line is a promise: a player who reads it can step off it. The
## laser keeps its line lit while it burns, because it is the one weapon whose shot
## *is* the line.

enum Kind { VULCAN, LASER, MISSILES }

enum State { READY, WINDUP, FIRING, RECOVER }

## The bow's gun. Four short volleys, then a real pause: the stream is what makes it
## a vulcan, and the pause is what keeps the bow from being a wall of orbs.
const VULCAN_WINDUP: float = 0.30
const VULCAN_BURST: int = 4
const VULCAN_INTERVAL: float = 0.11
const VULCAN_RECOVER: float = 0.9
const VULCAN_READY: float = 1.2
const VULCAN_PELLETS: int = 3
const VULCAN_SPREAD_DEGREES: float = 9.0
const VULCAN_SPEED: float = 34.0
const VULCAN_COLOR: Color = Color(1.0, 0.74, 0.34, 1.0)

## The stern's main gun. The line is shown for a second, then it burns for a third of
## a second along the line it showed. The aim does not track once it fires: the dodge
## is stepping off the line, not outrunning the ship.
const LASER_WINDUP: float = 0.95
const LASER_DURATION: float = 0.35
const LASER_RECOVER: float = 1.6
const LASER_READY: float = 1.4
const LASER_WIDTH: float = 1.7
## A little wider than the player's 1.0-unit capsule: the beam is read from the far
## end of a 96-unit hull, and a line that has to touch the exact centre would feel
## like a miss when it visibly crossed the ship.
const LASER_HIT_RADIUS: float = 1.9
const LASER_DAMAGE: int = 2
## The palette's own beam, dropped an octave: the player's laser is the same sound,
## and the ship's has to read as the bigger one without a new key.
const LASER_PITCH: float = 0.55
const LASER_COLOR: Color = Color(1.0, 0.34, 0.40, 1.0)

## The middle's launcher. The pair is the same threat the launcher enemy fires, so the
## counterplay — turn, dash, transform, decoy — does not change between the two.
const MISSILE_WINDUP: float = 0.85
const MISSILE_RECOVER: float = 2.0
const MISSILE_READY: float = 1.6
const MISSILE_SALVO: int = 2
const MISSILE_SPREAD_DEGREES: float = 9.0
const MISSILE_COLOR: Color = Color(1.0, 0.56, 0.22, 1.0)

## The windup line: thin and faint, so it reads as a promise instead of a shot.
const TELEGRAPH_WIDTH: float = 0.9
const TELEGRAPH_ALPHA: float = 0.30
## The second phase compresses the pauses, not the animations: the ship attacks more
## often without any weapon firing faster than the telegraph it has to show.
const PHASE_TWO_HURRY: float = 0.62

var _kind: int = Kind.VULCAN
var _state: State = State.READY
## The third of the hull this gun belongs to. The section owns two target points, so
## the gun stays alive while either point is, and goes silent when the pair falls.
var _section: int = 0
var _boss: Boss = null

## Section geometry, in world units: the keel length, the full beam and the height of
## the hull top above the play plane. The muzzle and the beam are derived from them.
var _length: float = 1.0
var _width: float = 1.0
var _top: float = 0.0

var _timer: float = 0.0
var _hurry: float = 1.0
var _aim: Vector3 = Vector3.RIGHT
var _target: Vector3 = Vector3.ZERO
var _shots_left: int = 0
var _burst_timer: float = 0.0
var _shots: int = 0

var _beam: MeshInstance3D = null
var _beam_material: StandardMaterial3D = null


## Built before the weapon enters the tree, so the first frame already has its beam
## and its geometry instead of an empty node for one.
func setup(
	kind: int,
	boss: Boss,
	section: int,
	length: float,
	width: float,
	top: float
) -> void:
	_kind = kind
	_boss = boss
	_section = section
	_length = length
	_width = width
	_top = top


## The delay before the first windup. The boss staggers its three guns with it, so the
## arrival opens with one threat instead of three at once.
func arm(delay: float) -> void:
	_timer = maxf(delay, 0.0)


func _ready() -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE

	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The line crosses the hull on its way to the player, and half of it would be
	# buried inside the opaque deck without this.
	_beam_material.no_depth_test = true
	_beam_material.albedo_color = _color()

	_beam = MeshInstance3D.new()
	_beam.name = "Telegraph"
	_beam.mesh = box
	_beam.material_override = _beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)


## One physics step. The section's own pool decides whether the gun exists at all, so
## a destroyed third is silent before any of its clock is read.
func tick(delta: float, player: Player, phase_two: bool) -> void:
	if is_silenced() or _boss == null:
		_hide_beam()
		return
	if not is_instance_valid(player):
		return

	_hurry = PHASE_TWO_HURRY if phase_two else 1.0

	match _state:
		State.READY:
			_timer -= delta
			if _timer <= 0.0:
				_open_windup(player)
		State.WINDUP:
			_timer -= delta
			_place_beam(_muzzle(), _target, TELEGRAPH_WIDTH, TELEGRAPH_ALPHA)
			if _timer <= 0.0:
				_fire(player)
		State.FIRING:
			_tick_firing(delta, player)
		State.RECOVER:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.READY
				_timer = _ready_time()


func kind() -> int:
	return _kind


## How many times this gun has answered: one per vulcan volley, one per laser shot,
## one per missile salvo. The suite reads it to prove a destroyed section goes quiet.
func shots_fired() -> int:
	return _shots


func is_silenced() -> bool:
	return _boss == null or _boss.is_section_destroyed(_section)


## The windup opens on the point the player occupies now, and the aim is stored, not
## re-read: the line the player sees is the line the shot takes.
func _open_windup(player: Player) -> void:
	_state = State.WINDUP
	_timer = _windup_time()
	_target = player.global_position
	_target.y = 0.0
	var offset: Vector3 = _target - global_position
	offset.y = 0.0
	if offset.length_squared() > 0.0001:
		_aim = offset.normalized()


func _fire(player: Player) -> void:
	match _kind:
		Kind.VULCAN:
			_state = State.FIRING
			_shots_left = VULCAN_BURST
			_burst_timer = 0.0
			_hide_beam()
		Kind.LASER:
			_state = State.FIRING
			_timer = LASER_DURATION
			Sfx.play_at(&"laser", _muzzle(), 0.0, LASER_PITCH)
		_:
			_launch(player)
			_state = State.RECOVER
			_timer = _recover_time()
			_hide_beam()


func _tick_firing(delta: float, player: Player) -> void:
	if _kind == Kind.LASER:
		_place_beam(_muzzle(), _target, LASER_WIDTH, 0.95)
		_burn(player)
		_timer -= delta
		if _timer <= 0.0:
			_state = State.RECOVER
			_timer = _recover_time()
			_hide_beam()
		return

	# The vulcan's burst: one volley per interval, then a real pause. A long frame
	# that owes two volleys pays two, so the burst is a count and not a frame rate.
	_burst_timer -= delta
	while _burst_timer <= 0.0 and _shots_left > 0:
		_fire_volley()
		_shots_left -= 1
		_burst_timer += VULCAN_INTERVAL
	if _shots_left <= 0:
		_state = State.RECOVER
		_timer = _recover_time()


func _fire_volley() -> void:
	var origin: Vector3 = _muzzle()
	for index in VULCAN_PELLETS:
		var offset: float = float(index) - float(VULCAN_PELLETS - 1) * 0.5
		var spread: float = deg_to_rad(VULCAN_SPREAD_DEGREES) * offset
		_boss.spawn_shot(
			origin, _aim.rotated(Vector3.UP, spread), VULCAN_SPEED, 1, VULCAN_COLOR
		)
	_shots += 1
	Sfx.play_at(&"enemy_fire", origin)


func _launch(player: Player) -> void:
	var origin: Vector3 = _muzzle()
	for index in MISSILE_SALVO:
		var offset: float = float(index) - float(MISSILE_SALVO - 1) * 0.5
		var spread: float = deg_to_rad(MISSILE_SPREAD_DEGREES) * offset
		_boss.spawn_missile(origin, _aim.rotated(Vector3.UP, spread), player)
	_shots += 1
	Sfx.play_at(&"missile_warning", origin)


## One hit per beam, not one per frame: the player's own i-frames turn the stream of
## calls into a single hit, and a tick counter here would be a second damage clock
## fighting the hull's.
func _burn(player: Player) -> void:
	var planar: Vector3 = player.global_position
	planar.y = 0.0
	var from: Vector3 = _planar_muzzle()
	if _distance_to_segment(planar, from, _target) > LASER_HIT_RADIUS:
		return
	player.take_damage(LASER_DAMAGE, from)


## Where the shot leaves the ship. The laser rakes from the deck top down onto the
## play plane, so the beam is visible over the hull; the guns fire from the section's
## silhouette edge on the plane the bullets live on.
func _muzzle() -> Vector3:
	if _kind == Kind.LASER:
		return to_global(Vector3(0.0, _top, 0.0))
	return _edge_point(_aim)


func _planar_muzzle() -> Vector3:
	var point: Vector3 = _muzzle()
	point.y = 0.0
	return point


## Where the aim direction leaves the section's own rectangle. Firing from the centre
## would hide the shot under the opaque deck until it cleared the hull, and a vulcan
## the player cannot see coming is not a vulcan.
func _edge_point(direction: Vector3) -> Vector3:
	var local: Vector3 = global_transform.basis.inverse() * direction
	local.y = 0.0
	if local.length_squared() < 0.0001:
		return global_position
	local = local.normalized()
	var reach: float = minf(
		_length * 0.5 / maxf(absf(local.x), 0.0001),
		_width * 0.5 / maxf(absf(local.z), 0.0001)
	)
	return to_global(local * reach)


func _place_beam(from: Vector3, to: Vector3, width: float, alpha: float) -> void:
	var span: Vector3 = to - from
	var length: float = span.length()
	if length <= 0.01:
		_hide_beam()
		return
	var direction: Vector3 = span / length
	# `look_at` refuses an up vector parallel to the line. A shot straight down the
	# ship's own column is the one case, and any perpendicular will do.
	var up: Vector3 = Vector3.UP
	if absf(direction.dot(Vector3.UP)) > 0.98:
		up = Vector3.RIGHT

	_beam.visible = true
	_beam.global_position = (from + to) * 0.5
	_beam.look_at(to, up)
	_beam.scale = Vector3(width, width, length)
	_beam_material.albedo_color.a = alpha


func _hide_beam() -> void:
	if _beam != null:
		_beam.visible = false


func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var span: Vector3 = b - a
	var length_squared: float = span.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(a + span * t)


func _color() -> Color:
	match _kind:
		Kind.VULCAN:
			return VULCAN_COLOR
		Kind.LASER:
			return LASER_COLOR
		_:
			return MISSILE_COLOR


func _windup_time() -> float:
	match _kind:
		Kind.VULCAN:
			return VULCAN_WINDUP
		Kind.LASER:
			return LASER_WINDUP
		_:
			return MISSILE_WINDUP


func _recover_time() -> float:
	var base: float = VULCAN_RECOVER
	match _kind:
		Kind.LASER:
			base = LASER_RECOVER
		Kind.MISSILES:
			base = MISSILE_RECOVER
	return base * _hurry


func _ready_time() -> float:
	var base: float = VULCAN_READY
	match _kind:
		Kind.LASER:
			base = LASER_READY
		Kind.MISSILES:
			base = MISSILE_READY
	return base * _hurry
