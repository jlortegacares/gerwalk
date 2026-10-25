class_name Decoy
extends Node3D
## A flare the ship drops behind itself. Enemy guidance is dumb enough to be
## fooled: a guided shot within `CAPTURE_RADIUS` of the flare takes it as its
## target, and when the flare burns out the shot is left with nothing and flies
## straight. The drop buys distance; it never kills the missile.
##
## The cooldown lives on the weapon system and the lifetime here, so the two
## together guarantee at most one flare alive at a time: the countermeasure is a
## read, not a state the player maintains.

const LIFETIME: float = 3.0
## How close a guided shot has to be for the flare to outrank the ship.
const CAPTURE_RADIUS: float = 30.0
## Everything is planar, but the flare floats a little so it is not swallowed by
## the ground the way a decal would be.
const FLOAT_HEIGHT: float = 0.65

const CORE_COLOR: Color = Color(1.0, 0.87, 0.45, 1.0)
const HALO_COLOR: Color = Color(1.0, 0.55, 0.20, 1.0)
const RING_COLOR: Color = Color(1.0, 0.72, 0.34, 0.85)

var _life: float = LIFETIME
var _pulse: float = 0.0
var _halo: MeshInstance3D
var _halo_material: StandardMaterial3D
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group(&"decoy")
	_build_visual()


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	# The pulse is the point: a static dot reads as scenery, a breathing one reads
	# as something that is actively spoofing.
	_pulse += delta * 9.0
	var beat: float = 0.5 + 0.5 * sin(_pulse)
	_halo.scale = Vector3.ONE * (0.80 + 0.45 * beat)
	_halo_material.albedo_color = Color(
		HALO_COLOR.r, HALO_COLOR.g, HALO_COLOR.b, 0.14 + 0.22 * beat
	)
	# The ring is tilted so the spin is visible: a flat torus is rotationally
	# symmetric and would sit still however fast it turned.
	_ring.rotate_y(delta * 3.2)


func _build_visual() -> void:
	var visual: Node3D = Node3D.new()
	visual.position = Vector3(0.0, FLOAT_HEIGHT, 0.0)
	add_child(visual)

	var core: MeshInstance3D = MeshInstance3D.new()
	var core_mesh: SphereMesh = SphereMesh.new()
	core_mesh.radius = 0.42
	core_mesh.height = 0.84
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	core.mesh = core_mesh
	core.material_override = _unshaded(CORE_COLOR, 3.4)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(core)

	_halo_material = _unshaded(HALO_COLOR, 1.8)
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo_material.albedo_color = Color(HALO_COLOR.r, HALO_COLOR.g, HALO_COLOR.b, 0.2)

	_halo = MeshInstance3D.new()
	var halo_mesh: SphereMesh = SphereMesh.new()
	halo_mesh.radius = 1.5
	halo_mesh.height = 3.0
	halo_mesh.radial_segments = 14
	halo_mesh.rings = 8
	_halo.mesh = halo_mesh
	_halo.material_override = _halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(_halo)

	_ring = MeshInstance3D.new()
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 1.05
	ring_mesh.outer_radius = 1.22
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 6
	_ring.mesh = ring_mesh
	_ring.material_override = _unshaded(RING_COLOR, 2.2)
	_ring.rotation.x = 0.32
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(_ring)


func _unshaded(color: Color, glow: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow
	return material
