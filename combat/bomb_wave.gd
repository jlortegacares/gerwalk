class_name BombWave
extends Node3D
## Expanding ring for the screen-clear bomb. Presentation only: the damage and the
## bullet cancel already happened when this spawned, so the ring is the receipt,
## not the weapon. A three-second particle effect would claim otherwise.

const RING_COLOR: Color = Color(0.62, 0.95, 1.0, 0.6)
## World-space thickness of the band. Scaling a torus scales its tube too, which
## turns a shockwave into a fat painted hoop by the time it reaches the edge.
const RING_BAND: float = 0.5

var _time: float = Arsenal.BOMB_WAVE_TIME
var _torus: TorusMesh
var _ring: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_torus = TorusMesh.new()
	_torus.rings = 64
	_torus.ring_segments = 8

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_color = RING_COLOR

	_ring = MeshInstance3D.new()
	_ring.mesh = _torus
	_ring.material_override = _material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


## The ring expands on sqrt so it leaves fast and settles — the eye reads that as
## a shockwave, while a linear ramp reads as a growing UI circle. The inner radius
## is recomputed against the current scale so the band keeps its world thickness.
func _process(delta: float) -> void:
	_time -= delta
	var progress: float = clampf(1.0 - _time / Arsenal.BOMB_WAVE_TIME, 0.0, 1.0)
	var radius: float = lerpf(0.6, Arsenal.BOMB_RADIUS, sqrt(progress))

	_ring.scale = Vector3(radius, 1.0, radius)
	_torus.outer_radius = 1.0
	_torus.inner_radius = maxf(1.0 - RING_BAND / maxf(radius, 0.01), 0.02)
	_material.albedo_color.a = RING_COLOR.a * (1.0 - progress)

	if _time <= 0.0:
		queue_free()
