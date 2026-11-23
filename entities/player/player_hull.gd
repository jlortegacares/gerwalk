class_name PlayerHull
extends RefCounted
## Builds the airframe into the ship: the visual root, the two hand-built materials
## of the GU-11, the imported model wearing the saved livery, the camera-axis fill
## light, and the pod itself.
##
## The ship keeps the handles rather than the construction: the mode pose moves the
## root every frame, the i-frame blink hides it, and the pod follows the model's
## hand. So the builder hands its parts back and stays a step, like the effects node
## and the controls table -- it owns no node that outlives `build`.

## Desert airframe from the reference sheet: the gunpod is the only piece still
## built by hand, so only its two materials survive.
const ACCENT_COLOR: Color = Color(0.34, 0.22, 0.17, 1.0)
## The GU-11 gunpod is the one near-black piece on the airframe. It is not pure
## black: at this scale the faces have to separate or the rifle reads as a smudge.
const GUNMETAL_COLOR: Color = Color(0.27, 0.28, 0.32, 1.0)

const GUNPOD_LENGTH: float = 0.90
const GUNPOD_BARREL: float = 0.46

## The counter-light that keeps a mirrored airframe reading evenly. Level and tint
## only; where it points is `_build_fill_light`'s story. It is cool because it
## stands in for sky bounce rather than for a second sun.
const FILL_ENERGY: float = 0.45
const FILL_COLOR: Color = Color(0.62, 0.72, 0.95)

var visual: Node3D
var model: PlayerModel
var accent_material: StandardMaterial3D
var gunmetal_material: StandardMaterial3D
var gunpod: Node3D


## `light_parent` is the camera rig. The fill rides it instead of the sun, and the
## ship is what knows where its rig is.
func build(ship: Node3D, light_parent: Node3D) -> void:
	visual = Node3D.new()
	ship.add_child(visual)

	accent_material = _ship_material(ACCENT_COLOR, 0.05)
	gunmetal_material = _ship_material(GUNMETAL_COLOR, 0.0)

	model = PlayerModel.new()
	model.name = "Model"
	# The livery is read once, at build: the ship the player flies is the ship the
	# options preview showed, and nothing in flight repaints it.
	model.set_livery(
		GameSettings.load_hull(),
		GameSettings.load_trim(),
		GameSettings.load_canopy(),
		GameSettings.load_lines(),
		GameSettings.load_nose()
	)
	visual.add_child(model)
	model.build()

	_build_fill_light(light_parent)
	gunpod = _build_gunpod()


## The arena is lit by a single sun from one side and the airframe is a mirror, so
## the two legs present opposite facets to it. One spine caught the sun and read as
## warm grey; its twin, turned away, crushed to black -- which from the game camera
## reads as one leg wearing a shadow the other does not have. That is what a single
## key light does to symmetric geometry, and no angle fixes it: a counter-light from
## the far side just makes the other leg the dark one.
##
## The fill therefore rides the camera rig, not the sun: the game camera is fixed
## behind and above the ship, so a light along its axis lands on exactly the facets
## the player can see, equally, whichever leg they belong to. It is shadowless and
## cool because it stands in for sky bounce, and `light_cull_mask` keeps it on the
## airframe's own render layer, so the planet, the stars and the enemies keep the
## single-sun look they were tuned with.
func _build_fill_light(parent: Node3D) -> void:
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.shadow_enabled = false
	fill.light_cull_mask = PlayerModel.AIRFRAME_LAYER_MASK
	parent.add_child(fill)


func _ship_material(color: Color, glow: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	material.metallic = 0.15
	# The hull is hand-built, so a flipped face must never punch a hole in it.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow
	return material


## The GU-11. The origin is the grip, so placing the pod at the hand puts the
## receiver in front of it and the stock behind, exactly as it is carried.
func _build_gunpod() -> Node3D:
	var pod: Node3D = Node3D.new()
	visual.add_child(pod)

	var body: MeshInstance3D = _block(
		Vector3(GUNPOD_LENGTH, 0.26, 0.26), gunmetal_material
	)
	body.position = Vector3(GUNPOD_LENGTH * 0.5 - 0.30, 0.0, 0.0)
	pod.add_child(body)

	var barrel: MeshInstance3D = _block(
		Vector3(GUNPOD_BARREL, 0.11, 0.11), gunmetal_material
	)
	barrel.position = Vector3(GUNPOD_LENGTH - 0.30 + GUNPOD_BARREL * 0.5, 0.0, 0.0)
	pod.add_child(barrel)

	var stock: MeshInstance3D = _block(Vector3(0.22, 0.18, 0.16), accent_material)
	stock.position = Vector3(-0.40, 0.0, 0.0)
	pod.add_child(stock)

	var grip: MeshInstance3D = _block(Vector3(0.12, 0.22, 0.16), accent_material)
	grip.position = Vector3(0.0, -0.18, 0.0)
	pod.add_child(grip)

	var sight: MeshInstance3D = _block(Vector3(0.24, 0.10, 0.10), accent_material)
	sight.position = Vector3(0.08, 0.17, 0.0)
	pod.add_child(sight)

	return pod


func _block(size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return _mesh_node(mesh, material)


func _mesh_node(mesh: Mesh, material: StandardMaterial3D) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	# The ship is small and the directional light covers the whole planet, so its
	# shadow lands as a dotted smear instead of a silhouette. Better no shadow.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
