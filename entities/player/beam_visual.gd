class_name BeamVisual
extends Node3D
## The laser's drawn line: two nested additive boxes, scaled along the holder's own
## Z so the length is one number and each box keeps its width.
##
## Presentation only. The beam stops where the raycast says it stops, so what is
## drawn is the truth about what the shot can hit.

func _ready() -> void:
	visible = false
	add_child(_box(Arsenal.LASER_GLOW, Arsenal.LASER_COLOR, 0.55))
	add_child(_box(Arsenal.LASER_CORE, Color(0.92, 1.0, 1.0), 0.75))


func hide_beam() -> void:
	visible = false


## A slow pulse on the width: a perfectly static beam at this scale reads as a debug
## line, and the pulse costs one sine per frame.
func show_beam(from: Vector3, to: Vector3) -> void:
	var span: Vector3 = to - from
	var length: float = span.length()
	if length < 0.05:
		return
	var pulse: float = 1.0 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.05)
	visible = true
	global_position = from + span * 0.5
	rotation.y = atan2(span.x, span.z)
	scale = Vector3(pulse, pulse, length)


func _box(width: float, color: Color, alpha: float) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(width, width, 1.0)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, alpha)

	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = box
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
