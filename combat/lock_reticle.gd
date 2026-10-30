class_name LockReticle
extends MeshInstance3D
## World-space mark on an enemy the forward radar has locked.
##
## It is parented to the enemy on purpose: a mark dies with its target instead of
## lingering over a dead unit, and it follows the turret while it moves. The ring
## lies flat on the play plane above the body, which is what an angled camera
## reads as a ring around the unit instead of a line through it.
##
## The mark is a lock, not a decal. It arrives wide and closes onto the contact
## while it fades in, and then keeps turning. The ring is drawn as arcs instead of
## a torus for that reason: a closed ring is rotationally symmetric, so a spin on
## it is invisible and the mark reads as painted on.

const RADIUS: float = 2.3
const THICKNESS: float = 0.14
const HEIGHT: float = 1.5
const COLOR: Color = Color(1.0, 0.85, 0.45, 1.0)
const PULSE_SPEED: float = 7.0
const PULSE_DEPTH: float = 0.05
const GLOW: float = 1.8
const GLOW_DEPTH: float = 0.45

## The lock-in. The ring is born this much wider than its resting size and closes
## in LOCK_IN_TIME, so a new contact announces itself instead of blinking on.
const LOCK_IN_SCALE: float = 1.9
const LOCK_IN_TIME: float = 0.24
## Degrees per second. The ring whips round while the lock is closing and then
## settles into a slow idle turn, which is the difference between "acquiring" and
## "acquired".
const LOCK_IN_SPIN: float = 9.0
const SPIN_SPEED: float = 1.4

## Four arcs leave four gaps, and the gaps are what make the turn readable.
const ARCS: int = 4
const ARC_DEGREES: float = 58.0
const ARC_STEPS: int = 8

var _age: float = 0.0
var _spin: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"lock_reticle")
	position.y = HEIGHT
	_build_ring()
	# The first frame is the widest one; `_process` closes from here.
	scale = Vector3.ONE * LOCK_IN_SCALE
	transparency = 1.0


func _build_ring() -> void:
	var ring: ImmediateMesh = ImmediateMesh.new()
	ring.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var gap: float = 360.0 / float(ARCS)
	var inner: float = RADIUS - THICKNESS
	for arc in ARCS:
		_arc(ring, inner, RADIUS, float(arc) * gap, ARC_DEGREES)
	ring.surface_end()
	mesh = ring

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


## One dash: a quad strip swept along the arc, in the local XZ plane.
func _arc(
	ring: ImmediateMesh, inner: float, outer: float, start_deg: float, sweep_deg: float
) -> void:
	for step in ARC_STEPS:
		var a0: float = deg_to_rad(start_deg + sweep_deg * float(step) / float(ARC_STEPS))
		var a1: float = deg_to_rad(
			start_deg + sweep_deg * float(step + 1) / float(ARC_STEPS)
		)
		var in0: Vector3 = Vector3(cos(a0), 0.0, sin(a0)) * inner
		var out0: Vector3 = Vector3(cos(a0), 0.0, sin(a0)) * outer
		var in1: Vector3 = Vector3(cos(a1), 0.0, sin(a1)) * inner
		var out1: Vector3 = Vector3(cos(a1), 0.0, sin(a1)) * outer
		ring.surface_add_vertex(in0)
		ring.surface_add_vertex(out0)
		ring.surface_add_vertex(in1)
		ring.surface_add_vertex(out0)
		ring.surface_add_vertex(out1)
		ring.surface_add_vertex(in1)


func _process(delta: float) -> void:
	_age += delta
	var closing: float = clampf(_age / LOCK_IN_TIME, 0.0, 1.0)
	# Ease-out: the ring covers most of the distance early, which is what reads as
	# a snap onto the contact instead of a slow zoom.
	var settle: float = 1.0 - pow(1.0 - closing, 3.0)

	# Fading in while closing is what turns the arrival into a lock instead of a pop.
	transparency = 1.0 - settle
	rotation.y = _spin
	_spin += delta * lerpf(LOCK_IN_SPIN, SPIN_SPEED, settle)

	var pulse: float = sin(_age * PULSE_SPEED)
	scale = Vector3.ONE * lerpf(LOCK_IN_SCALE, 1.0, settle) * (1.0 + pulse * PULSE_DEPTH)
	_material.emission_energy_multiplier = GLOW + pulse * GLOW_DEPTH
