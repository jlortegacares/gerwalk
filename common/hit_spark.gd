extends Node3D
## Short-lived impact flash in 3D. Self-freeing, no pooling at prototype scale.
##
## Built in code instead of a .tscn because the mesh is a placeholder: when real
## art lands this node disappears behind a scene swap.

const START_RADIUS: float = 0.35
const END_SCALE: float = 4.5
const DURATION: float = 0.16
const COLOR: Color = Color(0.55, 0.98, 0.9, 1.0)


func _ready() -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = START_RADIUS
	sphere.height = START_RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = COLOR

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = sphere
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3.ONE * END_SCALE, DURATION)
	tween.tween_property(mesh_instance, "transparency", 1.0, DURATION)
	tween.chain().tween_callback(queue_free)
