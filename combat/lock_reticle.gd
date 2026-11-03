class_name LockReticle
extends MeshInstance3D
## World-space mark on an enemy the forward radar has locked.
##
## It is parented to the enemy on purpose: a mark dies with its target instead of
## lingering over a dead unit, and it follows the turret while it moves. It lies
## flat on the play plane above the body, which is what an angled camera reads as
## a box around the unit instead of a line through it.
##
## The shape is the anime lock, not a ring: four corner brackets around the
## contact and a pip on its centre. A bracket box says "this one, here" while
## leaving the target itself visible, which a closed circle does not.
##
## The mark is a lock, not a decal. It arrives wide and fades in while it snaps
## down onto the contact, overshooting slightly before it settles. That squeeze is
## what reads as a lock instead of a zoom.
##
## A lock has two states. The one the scan is on right now is being acquired: a
## frame spins into place around it, a burst leaves the contact and the box snaps
## down with a flash. Every lock the rack already holds is settled — same box, calmer
## and a touch smaller — with only a faint frame turning slowly, because the eye
## should follow the newest lock, not read the whole salvo as one flat field. That is
## the multi-lock read: one box walking the contacts, leaving held locks behind it.

const HALF_SIZE: float = 2.6
const ARM: float = 1.05
const THICKNESS: float = 0.24
const HEIGHT: float = 1.5
const PIP: float = 0.36
const COLOR: Color = Color(1.0, 0.85, 0.45, 1.0)
const PULSE_SPEED: float = 6.0
const PULSE_DEPTH: float = 0.035
const GLOW: float = 1.9
const GLOW_DEPTH: float = 0.5

## The outer scan frame: a thin square that spins into place while the lock closes,
## so the acquisition reads as a targeting computer sweeping the contact instead of
## a box that only grows.
const SCAN_HALF: float = HALF_SIZE * 1.22
const SCAN_THICKNESS: float = 0.09
const SCAN_SPIN: float = PI * 0.5
const SCAN_ALPHA: float = 0.85

## The burst: a square that leaves the contact and fades as the lock closes. It is
## the punctuation that says the acquisition finished.
const BURST_HALF: float = HALF_SIZE * 1.02
const BURST_THICKNESS: float = 0.07
const BURST_SCALE: float = 1.8
const BURST_TIME: float = 0.3

## The flash: emission spikes on arrival and decays, so the new lock is the
## brightest thing on screen for a heartbeat.
const FLASH_GLOW: float = 2.4
const FLASH_DECAY: float = 14.0

## A settled lock keeps a faint frame turning, slowly enough to read as tracking
## and not as another acquisition.
const HELD_SCAN_ALPHA: float = 0.22
const HELD_SPIN_SPEED: float = 0.7

## The tally pops when it grows, so an extra missile is visible on the number too.
const LABEL_POP: float = 0.35
const LABEL_POP_DECAY: float = 9.0

## A settled lock. Smaller and dimmer than the one being acquired, so the eye goes
## to the newest box instead of reading the whole salvo as one flat field.
const HELD_SCALE: float = 0.82
const HELD_GLOW: float = 0.55

## The lock-in. The box is born this much wider than its resting size and snaps
## down in LOCK_IN_TIME, so a new contact announces itself instead of blinking on.
const LOCK_IN_SCALE: float = 1.9
const LOCK_IN_TIME: float = 0.22
## Ease-out-back: the box passes its resting size and squeezes before it settles.
const OVERSHOOT: float = 1.70158

var _age: float = 0.0
var _material: StandardMaterial3D
var _held: bool = false
var _number_label: Label3D = null
var _scan: MeshInstance3D = null
var _burst: MeshInstance3D = null
var _label_pop: float = 0.0


func _ready() -> void:
	add_to_group(&"lock_reticle")
	position.y = HEIGHT
	_build_box()
	_build_effects()
	# The first frame is the widest one; `_process` closes from here.
	scale = Vector3.ONE * LOCK_IN_SCALE
	transparency = 1.0


## Whether the box is settled. The salvo sync reads it to avoid re-holding a mark
## that already settled, which would restart the faint frame's slow turn.
func is_held() -> bool:
	return _held


## Settles the box: an earlier lock, waiting for the salvo. It keeps its place on
## the contact and stops competing with the one the scan is on now. The faint frame
## keeps turning, so a held lock reads as tracking instead of a dead sticker.
func hold() -> void:
	_held = true
	_age = LOCK_IN_TIME
	scale = Vector3.ONE * HELD_SCALE
	transparency = 0.0
	if _material != null:
		_material.emission_energy_multiplier = GLOW * HELD_GLOW
	if _scan != null:
		_scan.visible = true
		_scan.rotation.y = 0.0
		_scan.transparency = 1.0 - HELD_SCAN_ALPHA
	if _burst != null:
		_burst.visible = false


## Takes the box back from settled and runs the lock-in again. The scan feeds a
## contact round-robin, so a box that receives another missile is being acquired
## once more: it snaps, flashes and throws a burst like the newest lock, which is
## what makes the extra assignment visible instead of a silent counter bump.
func acquire() -> void:
	_held = false
	_age = 0.0
	scale = Vector3.ONE * LOCK_IN_SCALE
	transparency = 1.0
	if _material != null:
		_material.emission_energy_multiplier = GLOW
	if _scan != null:
		_scan.visible = true
		_scan.rotation.y = 0.0
		_scan.transparency = 1.0
	if _burst != null:
		_burst.visible = true
		_burst.scale = Vector3.ONE
		_burst.transparency = 0.0


## The missiles this contact will take, counted from one. It is a tally, not a
## rank: the salvo is spread round-robin over the pool, so a box reading "×3" is a
## contact the load will chase three times, not the third one locked.
func set_missiles(value: int) -> void:
	if _number_label == null:
		_number_label = Label3D.new()
		_number_label.name = "LockNumber"
		_number_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_number_label.no_depth_test = true
		_number_label.font_size = 64
		_number_label.pixel_size = 0.02
		_number_label.outline_size = 10
		_number_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		_number_label.modulate = COLOR
		# Above the box on screen: the reticle lies flat, and screen up is -Z.
		_number_label.position = Vector3(0.0, 0.05, -HALF_SIZE - 1.3)
		add_child(_number_label)
	# The tally is rewritten every sync because the pool order can change under it;
	# a Label3D rebuilds its geometry on assignment, so only touch it when it moves.
	var text: String = "×%d" % value
	if _number_label.text != text:
		_number_label.text = text
		# The tally grew: pop the number so the extra missile is visible on the
		# counter too, not only on the box.
		_label_pop = 1.0


func _build_box() -> void:
	var box: ImmediateMesh = ImmediateMesh.new()
	box.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = [
		Vector3(-HALF_SIZE, 0.0, -HALF_SIZE),
		Vector3(HALF_SIZE, 0.0, -HALF_SIZE),
		Vector3(HALF_SIZE, 0.0, HALF_SIZE),
		Vector3(-HALF_SIZE, 0.0, HALF_SIZE),
	]
	for corner in corners:
		# Each bracket is an L pointing inwards, so the four corners frame the
		# contact without closing a box around it.
		var sx: float = signf(corner.x)
		var sz: float = signf(corner.z)
		_bar(box, corner + Vector3(-sx * ARM * 0.5, 0.0, 0.0), Vector3.RIGHT, ARM * 0.5)
		_bar(box, corner + Vector3(0.0, 0.0, -sz * ARM * 0.5), Vector3.BACK, ARM * 0.5)
	_pip(box)
	box.surface_end()
	mesh = box

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = COLOR
	_material.emission_enabled = true
	_material.emission = COLOR
	_material.emission_energy_multiplier = GLOW
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _material

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The two extra meshes: a frame that spins into place while the lock closes and a
## square that bursts out of the contact as it does. They share the box material, so
## the arrival flash lights them with it.
func _build_effects() -> void:
	_scan = MeshInstance3D.new()
	_scan.name = "ScanFrame"
	_scan.mesh = _build_outline(SCAN_HALF, SCAN_THICKNESS)
	_scan.material_override = _material
	_scan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scan.transparency = 1.0
	add_child(_scan)

	_burst = MeshInstance3D.new()
	_burst.name = "Burst"
	_burst.mesh = _build_outline(BURST_HALF, BURST_THICKNESS)
	_burst.material_override = _material
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst.transparency = 1.0
	add_child(_burst)


## A thin square outline in the local XZ plane: the scan frame and the burst are
## the same shape at different sizes, so one builder serves both.
func _build_outline(half: float, thickness: float) -> ImmediateMesh:
	var outline: ImmediateMesh = ImmediateMesh.new()
	outline.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = [
		Vector3(-half, 0.0, -half),
		Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half),
		Vector3(-half, 0.0, half),
	]
	for index in corners.size():
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % corners.size()]
		var centre: Vector3 = (a + b) * 0.5
		var along: Vector3 = (b - a).normalized()
		_bar(outline, centre, along, (b - a).length() * 0.5, thickness)
	outline.surface_end()
	return outline


## One arm of a bracket: a quad centred on `centre`, running `half` either way
## along `along` and `thickness` across it, in the local XZ plane.
func _bar(
	box: ImmediateMesh,
	centre: Vector3,
	along: Vector3,
	half: float,
	thickness: float = THICKNESS
) -> void:
	var across: Vector3 = Vector3(-along.z, 0.0, along.x) * (thickness * 0.5)
	var tip: Vector3 = along * half
	box.surface_add_vertex(centre - tip - across)
	box.surface_add_vertex(centre - tip + across)
	box.surface_add_vertex(centre + tip + across)
	box.surface_add_vertex(centre - tip - across)
	box.surface_add_vertex(centre + tip + across)
	box.surface_add_vertex(centre + tip - across)


## The centre pip: the dot the brackets point at, and the thing the eye tracks
## while the box is still closing.
func _pip(box: ImmediateMesh) -> void:
	var points: Array[Vector3] = [
		Vector3(PIP, 0.0, 0.0),
		Vector3(0.0, 0.0, PIP),
		Vector3(-PIP, 0.0, 0.0),
		Vector3(0.0, 0.0, -PIP),
	]
	for index in points.size():
		var next: int = (index + 1) % points.size()
		box.surface_add_vertex(Vector3.ZERO)
		box.surface_add_vertex(points[index])
		box.surface_add_vertex(points[next])


func _process(delta: float) -> void:
	_age += delta
	_decay_label(delta)
	if _held:
		_settle()
		return
	_lock_in()


## A held lock: the box rests, the frame keeps turning faintly. The salvo will
## move, not the mark, so the box must not compete with the one being acquired.
func _settle() -> void:
	scale = Vector3.ONE * HELD_SCALE
	transparency = 0.0
	if _material != null:
		_material.emission_energy_multiplier = GLOW * HELD_GLOW
	if _scan != null:
		_scan.visible = true
		_scan.rotation.y = _age * HELD_SPIN_SPEED
		_scan.transparency = 1.0 - HELD_SCAN_ALPHA
	if _burst != null:
		_burst.visible = false


## The acquisition: the box snaps down, the frame spins into place, the burst
## leaves the contact and the flash decays. Each of the four carries one beat of
## the arrival, so the lock reads as a system taking the target, not a box growing.
func _lock_in() -> void:
	var closing: float = clampf(_age / LOCK_IN_TIME, 0.0, 1.0)
	# The fade is a plain ease-out, but the size uses an ease-out-back: the box has
	# to pass its resting size and squeeze to read as a snap.
	var fade: float = 1.0 - pow(1.0 - closing, 3.0)
	var snap: float = _ease_out_back(closing)

	# Fading in while closing is what turns the arrival into a lock instead of a pop.
	transparency = 1.0 - fade
	var breathe: float = sin(_age * PULSE_SPEED) * closing
	scale = (
		Vector3.ONE
		* lerpf(LOCK_IN_SCALE, 1.0, snap)
		* (1.0 + breathe * PULSE_DEPTH)
	)
	# The flash is the arrival: brightest the frame the lock starts and gone in a
	# heartbeat, so the new contact is the one the eye lands on.
	var flash: float = FLASH_GLOW * exp(-_age * FLASH_DECAY)
	_material.emission_energy_multiplier = GLOW + breathe * GLOW_DEPTH + flash

	if _scan != null:
		_scan.visible = true
		_scan.rotation.y = SCAN_SPIN * snap
		# sin(pi*t) appears and disappears at the ends, so the frame never pops.
		_scan.transparency = 1.0 - sin(PI * closing) * SCAN_ALPHA

	if _burst != null:
		var burst_t: float = clampf(_age / BURST_TIME, 0.0, 1.0)
		_burst.visible = burst_t < 1.0
		var burst_ease: float = 1.0 - pow(1.0 - burst_t, 3.0)
		_burst.scale = Vector3.ONE * lerpf(1.0, BURST_SCALE, burst_ease)
		_burst.transparency = burst_t


## Pops the tally when it grows, then lets it settle. A number that changes without
## a beat is easy to miss while the box is already moving.
func _decay_label(delta: float) -> void:
	if _number_label == null:
		return
	_label_pop = maxf(_label_pop - delta * LABEL_POP_DECAY, 0.0)
	_number_label.scale = Vector3.ONE * (1.0 + _label_pop * LABEL_POP)


## Ease-out-back: overshoots past 1 and settles, which is the snap.
func _ease_out_back(t: float) -> float:
	var c: float = OVERSHOOT + 1.0
	return 1.0 + c * pow(t - 1.0, 3.0) + OVERSHOOT * pow(t - 1.0, 2.0)
