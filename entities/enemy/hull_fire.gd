class_name HullFire
extends Node3D
## One persistent fire on the mothership's hull. The ship does not explode and
## then burn: it catches fire where the hull is worn down, and the blaze grows as
## the pool drains. The hull's own surface becomes the health bar the player reads
## without looking at the HUD.
##
## Built from billboarded, soft-edged quads like `ShipExplosion`'s fireball, but
## looping instead of one-shot: a capital ship that is coming apart keeps burning
## until it breaks up. The repository carries no particle art, so the texture and
## the quad are generated here the same way the explosion does.
##
## The fire is parented to the hull, so it turns with the ship and hides with it
## when the wreck comes apart.
##
## Size lives in the `QuadMesh`, never in the instance transform: a billboarded
## instance ignores its own scale, so a scaled quad renders at its one-unit mesh
## size no matter what the transform says. Growth therefore resizes the mesh, and
## the per-frame flicker rides on the material alpha instead of the scale.

const FLAME_COLOR: Color = Color(1.0, 0.38, 0.05, 0.72)
const CORE_COLOR: Color = Color(1.0, 0.72, 0.28, 0.6)
## Full-size flames. The radial gradient eats the outer half of the quad, so the
## visible blob is about half of this; the hull is 96 units long and the camera sees
## about 75 units vertically, so a fire smaller than this is a speck on the deck.
const FLAME_SIZE: float = 14.0
const CORE_SIZE: float = 6.0
## A round quad reads as a glow. Fire is taller than it is wide, so the flame quad
## is stretched on its vertical axis and lifted so its base sits on the deck.
const FLAME_ASPECT: float = 1.9

## The plume is what makes the fire read at gameplay distance: a flame alone is a
## bright dot, while smoke rising off the deck is unmistakable.
const SMOKE_AMOUNT: int = 20
const SMOKE_LIFETIME: float = 1.6

var _intensity: float = 0.0
var _phase: float = 0.0
var _flame: MeshInstance3D
var _core: MeshInstance3D
var _flame_mesh: QuadMesh
var _core_mesh: QuadMesh
var _flame_material: StandardMaterial3D
var _core_material: StandardMaterial3D
var _smoke: GPUParticles3D


func _ready() -> void:
	_phase = randf() * TAU
	_flame = _glow(FLAME_COLOR, false, FLAME_SIZE, FLAME_ASPECT)
	_core = _glow(CORE_COLOR, true, CORE_SIZE, 1.0)
	_flame_mesh = _flame.mesh as QuadMesh
	_core_mesh = _core.mesh as QuadMesh
	_flame_material = _flame.material_override as StandardMaterial3D
	_core_material = _core.material_override as StandardMaterial3D
	_smoke = _build_smoke()
	add_child(_smoke)
	ignite(0.0)


## `intensity` is 0 for "not burning" and grows toward 1 as the hull is worn down.
## Called on every hit, so it stays cheap: the mesh is resized, nothing is rebuilt.
func ignite(intensity: float) -> void:
	var next: float = clampf(intensity, 0.0, 1.0)
	var was_burning: bool = _intensity > 0.0
	_intensity = next
	if not was_burning and _intensity > 0.0:
		_smoke.emitting = true
	visible = _intensity > 0.0
	_resize()


func is_burning() -> bool:
	return _intensity > 0.0


func _process(delta: float) -> void:
	if _intensity <= 0.0:
		return
	_phase += delta * (5.0 + _intensity * 5.0)
	_flicker()


func _resize() -> void:
	if _flame_mesh == null:
		return
	var grow: float = 0.35 + 0.65 * _intensity
	var height: float = FLAME_SIZE * FLAME_ASPECT * grow
	_flame_mesh.size = Vector2(FLAME_SIZE * grow, height)
	# The quad is centred on the anchor, which is the deck; lifting it by a quarter
	# of its height puts the base on the deck and the tongue above it.
	_flame.position.y = height * 0.25
	_core_mesh.size = Vector2.ONE * CORE_SIZE * grow


## Two out-of-step sines: one sine reads as a pulse, and fire does not pulse, it
## wavers. The second factor is what keeps the flicker irregular. Alpha, not scale,
## because a billboarded instance ignores its own scale.
func _flicker() -> void:
	var flicker: float = 0.82 + 0.18 * sin(_phase) * sin(_phase * 1.63 + 1.1)
	_flame_material.albedo_color.a = FLAME_COLOR.a * flicker
	_core_material.albedo_color.a = CORE_COLOR.a * (0.8 + 0.2 * flicker)


## A soft disc that always faces the camera. `size` is the full width and it lives
## in the mesh, because a billboarded instance ignores its own scale. `aspect`
## stretches it vertically for the flame.
func _glow(color: Color, additive: bool, size: float, aspect: float) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size * aspect)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.albedo_texture = _puff_texture()
	# The flame sits on the deck, so it must draw over it: depth-testing a billboard
	# whose centre is on the hull buries half of it inside the opaque model, and the
	# flame reads as a faint sliver on the silhouette.
	material.no_depth_test = true
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _build_smoke() -> GPUParticles3D:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.0
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 3.5
	# Smoke rises instead of falling: a hull fire is not a ground fire.
	process.gravity = Vector3(0.0, 0.8, 0.0)
	process.damping_min = 0.4
	process.damping_max = 1.0
	process.scale_min = 0.8
	process.scale_max = 1.6
	process.scale_curve = _grow_curve()
	process.color_ramp = _smoke_ramp()

	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.amount = SMOKE_AMOUNT
	particles.lifetime = SMOKE_LIFETIME
	# World space: the ship keeps flying and the plume has to stay where it was
	# made instead of riding the hull.
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.process_material = process
	particles.draw_pass_1 = _quad(4.5)
	particles.emitting = false
	return particles


func _quad(size: float) -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _puff_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	return quad


## Billboarded, soft-edged radial gradient generated in code. Three stops fall off
## evenly; a single stop between centre and edge leaves a visible rim.
func _puff_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.3, Color(1.0, 1.0, 1.0, 0.55))
	gradient.add_point(0.65, Color(1.0, 1.0, 1.0, 0.16))
	gradient.set_color(3, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func _grow_curve() -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.8))
	curve.add_point(Vector2(1.0, 2.6))
	var texture: CurveTexture = CurveTexture.new()
	texture.curve = curve
	return texture


func _smoke_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	# Particle ramps are read as linear, so these look far brighter on screen than
	# their numbers suggest: 0.2 lands at about half of white.
	gradient.set_color(0, Color(0.2, 0.18, 0.16, 0.72))
	gradient.add_point(0.4, Color(0.15, 0.14, 0.13, 0.45))
	gradient.set_color(2, Color(0.1, 0.095, 0.09, 0.0))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	return texture
