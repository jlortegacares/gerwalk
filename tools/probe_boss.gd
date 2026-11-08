extends SceneTree
## Development helper: report what the boss GLB actually contains, so scale,
## orientation and node names are facts instead of guesses.
##
##   <godot> --headless --path . --script tools/probe_boss.gd
##
## Prints the hull's AABB (the numbers `Boss.MODEL_SIZE` and `Boss.MODEL_CENTER`
## copy), the surface/material count and the largest meshes. Run it again if the
## asset is replaced; the collision shape and the framing depend on these numbers.
##
## `global_transform` is unavailable outside the tree, and a SceneTree script
## cannot await a frame before measuring, so the probe accumulates the local
## transforms itself and measures in the model's own space.


func _initialize() -> void:
	var path: String = "res://models/boss-1/capital_mother_ship_class_two..glb"
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		print("LOAD FAILED")
		quit()
		return
	var root_node: Node = packed.instantiate()

	var found: Array = []
	_collect(root_node, Transform3D.IDENTITY, found)
	print("nodes with mesh: %d" % found.size())

	var total: AABB = AABB()
	var biggest: Array = []
	for entry in found:
		var box: AABB = entry[0]
		if biggest.is_empty():
			total = box
		else:
			total = total.merge(box)
		biggest.append([box.get_volume(), entry[1], box.size, box.get_center()])
	biggest.sort_custom(func(a, b): return a[0] > b[0])

	print("TOTAL aabb size=%s center=%s" % [total.size, total.get_center()])
	print("top 12 by volume:")
	for entry in biggest.slice(0, 12):
		print("  %s  size=%s  center=%s" % [entry[1], entry[2], entry[3]])

	print("first 12 in tree order:")
	for entry in found.slice(0, 12):
		print("  %s" % entry[1])

	var materials: Dictionary = {}
	var surfaces: int = 0
	for entry in found:
		var mesh_instance: MeshInstance3D = entry[2]
		surfaces += mesh_instance.mesh.get_surface_count()
		for index in mesh_instance.mesh.get_surface_count():
			var material: Material = mesh_instance.mesh.surface_get_material(index)
			materials[material.get_instance_id() if material != null else 0] = true
	print("surfaces=%d unique materials=%d" % [surfaces, materials.size()])

	print("root node: %s (%s)" % [root_node.name, root_node.get_class()])
	root_node.free()
	quit()


func _collect(node: Node, xform: Transform3D, out: Array) -> void:
	var here: Transform3D = xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh != null:
			out.append([here * mesh_instance.get_aabb(), str(node.name), mesh_instance])
	for child in node.get_children():
		_collect(child, here, out)
