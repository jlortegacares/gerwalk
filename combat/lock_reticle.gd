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

## The lock-in. The box is born this much wider than its resting size and snaps
## down in LOCK_IN_TIME, so a new contact announces itself instead of blinking on.
const LOCK_IN_SCALE: float = 1.9
const LOCK_IN_TIME: float = 0.22
## Ease-out-back: the box passes its resting size and squeezes before it settles.
const OVERSHOOT: float = 1.70158

var _age: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"lock_reticle")
	position.y = HEIGHT
	_build_box()
	# The first frame is the widest one; `_process` closes from here.
	scale = Vector3.ONE * LOCK_IN_SCALE
	transparency = 1.0


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


## One arm of a bracket: a quad centred on `centre`, running `half` either way
## along `along` and THICKNESS across it, in the local XZ plane.
func _bar(
	box: ImmediateMesh, centre: Vector3, along: Vector3, half: float
) -> void:
	var across: Vector3 = Vector3(-along.z, 0.0, along.x) * (THICKNESS * 0.5)
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
	_material.emission_energy_multiplier = GLOW + breathe * GLOW_DEPTH


## Ease-out-back: overshoots past 1 and settles, which is the snap.
func _ease_out_back(t: float) -> float:
	var c: float = OVERSHOOT + 1.0
	return 1.0 + c * pow(t - 1.0, 3.0) + OVERSHOOT * pow(t - 1.0, 2.0)
