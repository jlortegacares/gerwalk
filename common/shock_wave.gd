class_name ShockWave
extends Node3D
## A detonation's shockwave: a white-hot flash and an expanding ring. Presentation
## only: the damage landed before this node spawned, so the wave is the receipt, not
## the weapon.
##
## Two callers use it, at two sizes. `Projectile` leaves one where a missile hit, and
## `ShipExplosion` adds one, scaled up and without the flash, to every hull that comes
## apart. That is the point of a shared node: a hit and a death have to read as the
## same kind of event at different magnitudes.
##
## Built in code for the same reason as `HitSpark` and `ShipExplosion`: the meshes are
## placeholders, so this node disappears behind a scene swap when real art lands.
##
## The ring lies on the play plane. Godot's `TorusMesh` is already built in XZ, so the
## angled camera reads it as a shockwave running along the ground instead of as a
## vertical hoop.

const FLASH_COLOR: Color = Color(1.0, 0.96, 0.88, 1.0)
const FLASH_START: float = 0.5
const FLASH_END: float = 3.4
const FLASH_TIME: float = 0.13

## White-hot at the core and orange at the edge: the ring cools as it travels, which
## is what separates a detonation from a coloured circle fading out.
const RING_HOT: Color = Color(1.0, 0.95, 0.78, 0.85)
const RING_COOL: Color = Color(1.0, 0.40, 0.06, 0.0)
const RING_START: float = 0.7
const RING_END_RADIUS: float = 7.5
const RING_TIME: float = 0.42
## World-space thickness of the band. Scaling a torus scales its tube too, which
## turns a shockwave into a fat painted hoop by the time it reaches the edge.
const RING_BAND: float = 0.30

## Read by `_ready`, so it has to be set before the node enters the tree. The death
## blast already opens with its own white core, so its wave carries only the ring:
## two flashes on one frame fight each other for the same white.
var flash_enabled: bool = true

var _time: float = 0.0
var _flash: MeshInstance3D
var _flash_material: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _torus: TorusMesh


func _ready() -> void:
	add_to_group(&"shock_wave")
	if flash_enabled:
		_build_flash()
	_build_ring()
	# Applied here, not on the first `_process`: the wave has to be at full
	# brightness on the frame it spawns, which is the frame the player is looking at.
	_apply(0.0)


func _process(delta: float) -> void:
	_time += delta
	_apply(_time)
	if _time >= RING_TIME:
		queue_free()


## Both layers expand on `sqrt`: the eye reads a fast start that settles as a
## shockwave, while a linear ramp reads as a growing UI circle.
func _apply(time: float) -> void:
	if _flash != null:
		var flash_progress: float = clampf(time / FLASH_TIME, 0.0, 1.0)
		var flash: float = lerpf(FLASH_START, FLASH_END, sqrt(flash_progress))
		_flash.scale = Vector3.ONE * flash
		# The alpha holds near full for the first third of the flash and then falls:
		# a straight fade spends the whole pop on the first frame and leaves a grey
		# smudge where the white should have been.
		_flash_material.albedo_color.a = 1.0 - smoothstep(0.35, 1.0, flash_progress)

	var ring_progress: float = clampf(time / RING_TIME, 0.0, 1.0)
	var radius: float = lerpf(RING_START, RING_END_RADIUS, sqrt(ring_progress))
	_ring.scale = Vector3(radius, 1.0, radius)
	# The inner radius is recomputed against the current scale so the band keeps its
	# world thickness instead of fattening with the ring.
	_torus.inner_radius = maxf(1.0 - RING_BAND / maxf(radius, 0.01), 0.02)
	_ring_material.albedo_color = RING_HOT.lerp(RING_COOL, ring_progress)


func _build_flash() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE

	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_material.albedo_color = FLASH_COLOR
	_flash_material.albedo_texture = _glow_texture()

	_flash = MeshInstance3D.new()
	_flash.mesh = quad
	_flash.material_override = _flash_material
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)


func _build_ring() -> void:
	_torus = TorusMesh.new()
	_torus.rings = 64
	_torus.ring_segments = 8
	_torus.outer_radius = 1.0

	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.albedo_color = RING_HOT

	_ring = MeshInstance3D.new()
	_ring.mesh = _torus
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


## Soft-edged radial glow generated in code: the repository carries no art, and a
## hard-edged quad would read as a white square the moment it grew.
func _glow_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
