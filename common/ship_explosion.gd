class_name ShipExplosion
extends Node3D
## The death blast: a white core, a fireball, debris, sparks and smoke.
## Self-freeing, no pooling at prototype scale.
##
## The ship uses it when it dies and every enemy uses it too, so the blast is the
## one thing in the game that means "a hull came apart". Only the camera kick is
## scaled: a kill is not the run ending.
##
## Built in code for the same reason as `HitSpark`: the meshes are placeholders, so
## this node disappears behind a scene swap when real art lands. It is one node with
## staggered layers instead of a single burst, because a ship breaking up needs a
## flash that peaks first, fire that opens after it, and smoke that outlives both.
## One expanding sphere reads as a hit, not as a hull coming apart.
##
## The fire layers are billboarded quads carrying a radial gradient rather than
## spheres. An unshaded sphere is the same brightness everywhere, so its silhouette
## is a hard circle with visible facets, and a sphere that expands into another
## sphere draws two hard edges through each other. A soft quad fades to nothing at
## its edge, which is what lets three of them overlap into one fireball.

const LIFETIME: float = 2.6
const CORE_DURATION: float = 0.14
const CORE_START: float = 1.6
const CORE_END: float = 7.0
const FIRE_DURATION: float = 0.7
const FIRE_START: float = 2.4
const FIRE_END: float = 9.0
const DEBRIS_DURATION: float = 0.95
const SPARK_LIFETIME: float = 1.0
## The smoke is held back: fire and smoke opening on the same frame turns the blast
## into one grey cloud with orange edges, and the fire is what has to read first.
const SMOKE_DELAY: float = 0.3
const SMOKE_LIFETIME: float = 2.0
const CORE_COLOR: Color = Color(1.0, 0.95, 0.84, 0.85)
const FIRE_COLOR: Color = Color(1.0, 0.46, 0.08, 0.55)
const DEBRIS_COLOR: Color = Color(0.3, 0.29, 0.31, 1.0)
## Each fireball lobe is a fraction of the stop above, so the three of them read as
## a shape with a hot middle instead of three discs of the same size.
const FIRE_LOBES: Array[float] = [1.0, 0.72, 0.5]

## Read by `_ready`, so it has to be set before the node enters the tree.
var shake_strength: float = 1.0


func _ready() -> void:
	_add_core()
	_add_fireball()
	_add_debris()
	_add_sparks()
	_add_smoke()
	# The hull is gone in one frame, so the only cue that something big happened is
	# the camera: a kick on top of the one the killing hit asked for.
	GlobalEventBus.camera_shake_requested.emit(shake_strength)

	var tween: Tween = create_tween()
	tween.tween_interval(LIFETIME)
	tween.tween_callback(queue_free)


## The flash is additive and very short: it is what makes the frame read as a
## detonation instead of an orange ball growing out of the ground.
func _add_core() -> void:
	var flash: MeshInstance3D = _glow(CORE_START, CORE_COLOR, true)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * (CORE_END / CORE_START), CORE_DURATION)
	tween.tween_property(flash, "transparency", 1.0, CORE_DURATION)


## Three overlapping blobs with a small offset each, so the fireball has a shape
## and a direction instead of being a perfect circle. The largest opens first and
## the smaller two arrive on top of it, which is what gives it a hot middle.
func _add_fireball() -> void:
	for index in FIRE_LOBES.size():
		var lobe: float = FIRE_LOBES[index]
		var blob: MeshInstance3D = _glow(FIRE_START * lobe, FIRE_COLOR, true)
		blob.position = Vector3(
			randf_range(-0.8, 0.8), randf_range(-0.2, 0.7), randf_range(-0.8, 0.8)
		)
		var delay: float = index * 0.06
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(
			blob, "scale", Vector3.ONE * (FIRE_END / FIRE_START), FIRE_DURATION
		).set_delay(delay)
		tween.tween_property(blob, "transparency", 1.0, FIRE_DURATION).set_delay(delay)


## Dark shards on the gunmetal palette: they are the only layer that says the ship
## was made of something solid.
func _add_debris() -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.5, 0.22, 0.75)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = DEBRIS_COLOR
	material.metallic = 0.5
	material.roughness = 0.6
	mesh.material = material

	for _index in 7:
		var shard: MeshInstance3D = MeshInstance3D.new()
		shard.mesh = mesh
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.scale = Vector3.ONE * randf_range(0.45, 1.0)
		add_child(shard)

		var out: Vector3 = Vector3(
			randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)
		).normalized()
		var travel: Vector3 = out * randf_range(2.5, 5.0)
		travel.y -= 1.6
		var spin: Vector3 = Vector3(
			randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)
		)
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", travel, DEBRIS_DURATION).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", spin, DEBRIS_DURATION)
		# The shard is gone before it lands, which keeps it from reading as litter
		# left on the ground after the explosion has finished.
		tween.tween_property(
			shard, "scale", Vector3.ONE * 0.01, DEBRIS_DURATION * 0.5
		).set_delay(DEBRIS_DURATION * 0.5)


func _add_sparks() -> void:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.8
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 6.0
	process.initial_velocity_max = 16.0
	process.gravity = Vector3(0.0, -16.0, 0.0)
	process.damping_min = 1.0
	process.damping_max = 3.0
	process.scale_min = 0.5
	process.scale_max = 1.2
	process.scale_curve = _shrink_curve()
	process.color_ramp = _spark_ramp()

	var sparks: GPUParticles3D = _burst(36, SPARK_LIFETIME, 1.0, process, _quad(0.22, true))
	add_child(sparks)
	sparks.emitting = true


func _add_smoke() -> void:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.1
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 1.6
	process.initial_velocity_max = 5.5
	process.gravity = Vector3(0.0, 1.2, 0.0)
	process.damping_min = 0.6
	process.damping_max = 1.8
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_min = 0.7
	process.scale_max = 1.4
	process.scale_curve = _grow_curve()
	process.color_ramp = _smoke_ramp()

	# Explosiveness is lower than the sparks: smoke that appears all at once looks
	# like a sprite popping, and the puff has to keep arriving while the fire dies.
	# The puff is small enough that the column reads as puffs instead of one grey
	# disc once they have all grown.
	var smoke: GPUParticles3D = _burst(24, SMOKE_LIFETIME, 0.85, process, _quad(1.8, false))
	add_child(smoke)
	var tween: Tween = create_tween()
	tween.tween_interval(SMOKE_DELAY)
	tween.tween_callback(func() -> void: smoke.emitting = true)


func _burst(
	amount: int,
	lifetime: float,
	explosiveness: float,
	process: ParticleProcessMaterial,
	mesh: QuadMesh
) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = explosiveness
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.process_material = process
	particles.draw_pass_1 = mesh
	return particles


## A soft disc that always faces the camera: the fireball unit. `size` is the full
## width, and the gradient eats the outer half of it, so the visible blob is about
## half of `size` across and has no edge to see.
func _glow(size: float, color: Color, additive: bool = false) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.albedo_texture = _puff_texture()
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## Billboarded, soft-edged quad generated in code: the repository carries no art
## for a particle, and a square spark is a very obvious square spark.
func _quad(size: float, additive: bool) -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _puff_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = material
	return quad


func _puff_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	# A single stop between the centre and the edge leaves a plateau with a visible
	# rim, which is the one thing a glow must not have. Three stops fall off evenly.
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


func _shrink_curve() -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var texture: CurveTexture = CurveTexture.new()
	texture.curve = curve
	return texture


func _grow_curve() -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.8))
	curve.add_point(Vector2(1.0, 2.6))
	var texture: CurveTexture = CurveTexture.new()
	texture.curve = curve
	return texture


func _spark_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 0.92, 0.62, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.55, 0.15, 0.9))
	gradient.set_color(2, Color(0.9, 0.2, 0.05, 0.0))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	return texture


func _smoke_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	# Particle ramps are read as linear, so these look far brighter on screen than
	# their numbers suggest: 0.06 lands at about a third of white, which is a grey
	# puff instead of the pale cloud 0.32 produced.
	gradient.set_color(0, Color(0.06, 0.055, 0.05, 0.75))
	gradient.add_point(0.4, Color(0.07, 0.065, 0.06, 0.5))
	gradient.set_color(2, Color(0.09, 0.085, 0.08, 0.0))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	return texture
