class_name SmokePuff
extends MeshInstance3D
## One puff of a missile's exhaust trail. It drifts, grows and fades, then frees
## itself.
##
## It is a node in the scene rather than a child of the missile on purpose: the
## smoke already in the air has to stay there when the missile hits something and
## frees itself, otherwise every impact would delete its own trail.

const BASE_COLOR: Color = Color(0.82, 0.80, 0.76, 0.55)

var _life: float = 0.0
var _max_life: float = 0.6
var _start_radius: float = 0.1
var _end_radius: float = 0.4
var _velocity: Vector3 = Vector3.ZERO
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"smoke_puff")

	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	mesh = sphere

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = BASE_COLOR
	material_override = _material

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3.ONE * _start_radius


## Called right after the node joins the tree. `velocity` is a fraction of the
## missile's own, so the trail curves with it instead of drawing a straight line
## behind a guided shot.
func launch(
	velocity: Vector3, start_radius: float, end_radius: float, lifetime: float
) -> void:
	_velocity = velocity
	_start_radius = start_radius
	_end_radius = end_radius
	_max_life = maxf(lifetime, 0.01)
	_life = _max_life
	scale = Vector3.ONE * _start_radius
	_apply_fade(0.0)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	global_position += _velocity * delta
	# The puff loses its speed almost at once: it should sit in the air the shot
	# just crossed, not race the missile.
	_velocity *= maxf(1.0 - 2.4 * delta, 0.0)

	var age: float = 1.0 - _life / _max_life
	scale = Vector3.ONE * lerpf(_start_radius, _end_radius, sqrt(age))
	_apply_fade(age)


func _apply_fade(age: float) -> void:
	if _material == null:
		return
	var color: Color = BASE_COLOR
	color.a *= 1.0 - age
	_material.albedo_color = color
