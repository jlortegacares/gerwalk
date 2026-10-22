class_name LockReticle
extends MeshInstance3D
## World-space mark on an enemy the forward radar has locked.
##
## It is parented to the enemy on purpose: a mark dies with its target instead of
## lingering over a dead unit, and it follows the turret while it moves. The ring
## lies flat on the play plane above the body, which is what an angled camera
## reads as a ring around the unit instead of a line through it.

const RADIUS: float = 2.3
const THICKNESS: float = 0.14
const HEIGHT: float = 1.5
const COLOR: Color = Color(1.0, 0.85, 0.45, 1.0)
const PULSE_SPEED: float = 7.0
const PULSE_DEPTH: float = 0.05

var _age: float = 0.0


func _ready() -> void:
	add_to_group(&"lock_reticle")
	position.y = HEIGHT

	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = RADIUS - THICKNESS
	torus.outer_radius = RADIUS
	torus.rings = 12
	torus.ring_segments = 24
	mesh = torus

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 1.8
	material_override = material

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_age += delta
	# The pulse is the difference between a live mark and a piece of scenery.
	scale = Vector3.ONE * (1.0 + sin(_age * PULSE_SPEED) * PULSE_DEPTH)
