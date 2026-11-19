class_name CloudField
extends Node3D
## The planet's cloud deck. One procedural density field drives both the billboards
## the ship flies through and the cover rule the missiles read, so a bank that looks
## dense is a bank that actually breaks a lock.
##
## The field is sampled in world space on the play plane. It is atmosphere, not
## terrain: the planet rolls underneath and the clouds stay put, which is what gives
## the ship a second layer of parallax against the surface.
##
## Dense cores are cover. An enemy missile whose target is inside one loses the
## ship and flies on straight; a thin fringe changes nothing. The opening patch
## around the origin is kept clear, because the first contact has to be readable.

## Feature size of a bank. At 26 units a second the ship crosses one in about three
## seconds, which is long enough to use as cover and short enough to read as weather.
const DENSITY_SCALE: float = 0.012
## Where a bank stops being scenery and starts breaking locks. Kept above the visual
## floor so the fringe is visible but harmless and only the core is cover. It sits
## in the field's top decile: cover is about a tenth of the map, rare enough to be
## an opportunity the player takes and common enough to find while crossing.
const DENSE_THRESHOLD: float = 0.68
## Below this the field is invisible. The threshold sits high in the field's
## distribution, so the deck covers an eighth of the map and the rest is open sky;
## the band between this and DENSE_THRESHOLD is the thin cloud that warns a core is
## coming.
const VISUAL_MIN_DENSITY: float = 0.65
## Where a bank reads at full weight. The midpoint of the visible band, so a core at
## the cover threshold still reads at half mass and anything denser is saturated.
const VISUAL_FULL_DENSITY: float = 0.71
## The opening clearing. The first contact spawns 70 units out, and the ring leaves
## that in clear sky, so the run still starts in the open; the deck begins past it.
const CLEAR_INNER: float = 45.0
const CLEAR_OUTER: float = 120.0

## The visual ring around the ship. The camera sees roughly 45 units ahead, so this
## is comfortably past the frame and still cheap to rebuild.
const STREAM_RADIUS: float = 150.0
const CELL_SIZE: float = 18.0
## Candidate puffs per cell, on a 4x4 jittered grid. A puff much smaller than the
## cell is the whole trick: with one 16-unit puff per 18-unit cell every cell is a
## visible disc, and the bank reads as a lattice of pale ovals instead of a mass.
const SUBGRID: int = 4
const MAX_PUFFS: int = 4000

## Detail puffs build the whole silhouette. There is no separate haze layer: a wide,
## faint quad drawn per cell was the deck's worst artefact. At 40-72 units across it
## is 450-800 pixels of soft radial falloff over the sea, which reads as a pale oval,
## and at 20-34 it still showed its square edges where two of them overlapped. Small
## overlapping puffs do the same blending job without ever being one visible shape.
const PUFF_MIN_SIZE: float = 3.5
const PUFF_MAX_SIZE: float = 14.0
const PUFF_MIN_Y: float = -1.5
const PUFF_MAX_Y: float = 1.5

const DETAIL_ALPHA_MIN: float = 0.14
const DETAIL_ALPHA_MAX: float = 0.62

const CLOUD_TINT: Color = Color(0.90, 0.93, 0.99, 1.0)
## One texture per variant. Eight irregular shapes are enough to stop the deck
## reading as one repeated stamp, and each MultiMesh is one draw call.
const PUFF_VARIANTS: int = 8
const PUFF_TEXTURE_SIZE: int = 256
const CLOUD_SEED: int = 20261106

var _noise: FastNoiseLite = null
var _multimeshes: Array[MultiMesh] = []
var _indices: PackedInt32Array = PackedInt32Array()
var _written: int = 0
var _player: Node3D = null
var _last_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _visible_puffs: int = 0


func _ready() -> void:
	add_to_group(&"cloud_field")
	_ensure_noise()
	_build_visual()


## Called by the level once the ship exists. The field follows the ship's cell, not
## its exact position: puffs are fixed in the world, so they must not jitter with
## every frame of travel.
func setup(player: Node3D) -> void:
	_player = player
	if _player == null:
		return
	_last_cell = _cell_of(_player.global_position)
	_rebuild()


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var cell: Vector2i = _cell_of(_player.global_position)
	if cell == _last_cell:
		return
	_last_cell = cell
	_rebuild()


## The density of the deck at a world point, in 0..1. Pure and deterministic: the
## visual stream and the missile cover rule read the same number.
func density_at(point: Vector3) -> float:
	_ensure_noise()
	var raw: float = _noise.get_noise_2d(point.x, point.z) * 0.5 + 0.5
	var density: float = clampf(raw, 0.0, 1.0)
	# The opening ring: zero inside CLEAR_INNER, full past CLEAR_OUTER. The planet
	# is circumnavigable, so this is a clearing, not a permanent hole in the sky.
	var distance: float = Vector2(point.x, point.z).length()
	return density * smoothstep(CLEAR_INNER, CLEAR_OUTER, distance)


## Whether a point sits in a bank dense enough to hide a ship from a guided shot.
func is_dense(point: Vector3) -> bool:
	return density_at(point) >= DENSE_THRESHOLD


## How many puffs the last rebuild drew. The smoke test reads it to prove the deck
## is populated instead of trusting the shader to look right.
func visible_puff_count() -> int:
	return _visible_puffs


func _ensure_noise() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = CLOUD_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5
	_noise.frequency = DENSITY_SCALE


func _build_visual() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE

	_multimeshes.clear()
	_indices.resize(PUFF_VARIANTS)
	_indices.fill(0)

	for variant in PUFF_VARIANTS:
		# A billboarded quad is the cheapest cloud there is: one draw call per
		# variant, and the soft texture carries the shape. `billboard_keep_scale`
		# is what lets one quad size per puff survive the billboard rotation.
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = _build_puff_texture(variant)
		# The instance colour carries the per-puff opacity, so the material can stay
		# at full alpha and every puff share the same variant set.
		material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.texture_repeat = false

		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = quad
		multimesh.instance_count = MAX_PUFFS
		multimesh.visible_instance_count = 0

		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.name = "Puffs%d" % variant
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_multimeshes.append(multimesh)


## A soft, irregular blob. A pure radial falloff reads as a stamp when it repeats;
## domain-warping the sampling coordinates and multiplying in a low-frequency lobe
## field bends the silhouette into something that billows. The texture carries a
## vertical light falloff too, so an unshaded billboard still reads as a volume:
## bright top, shaded base.
func _build_puff_texture(variant: int) -> ImageTexture:
	var size: int = PUFF_TEXTURE_SIZE
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	var shape: FastNoiseLite = FastNoiseLite.new()
	shape.seed = CLOUD_SEED + 17 + variant * 131
	shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape.fractal_type = FastNoiseLite.FRACTAL_FBM
	shape.fractal_octaves = 3
	shape.frequency = 0.018

	var warp: FastNoiseLite = FastNoiseLite.new()
	warp.seed = CLOUD_SEED + 71 + variant * 197
	warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp.fractal_type = FastNoiseLite.FRACTAL_FBM
	warp.fractal_octaves = 2
	warp.frequency = 0.012

	var detail: FastNoiseLite = FastNoiseLite.new()
	detail.seed = CLOUD_SEED + 113 + variant * 53
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 2
	detail.frequency = 0.055

	var half: float = float(size) * 0.5
	for y in size:
		for x in size:
			var u: float = (float(x) + 0.5 - half) / half
			var v: float = (float(y) + 0.5 - half) / half
			var fx: float = float(x)
			var fy: float = float(y)

			# Warp the circle before measuring it: the edge stops being a rim.
			var wu: float = u + warp.get_noise_2d(fx, fy) * 0.30
			var wv: float = v + warp.get_noise_2d(fx + 1000.0, fy - 500.0) * 0.30
			var radial: float = clampf(1.0 - sqrt(wu * wu + wv * wv), 0.0, 1.0)
			var body: float = smoothstep(0.0, 0.90, radial)

			# Lumps at the low end, grain at the high end: billow plus texture.
			var lobe: float = shape.get_noise_2d(fx, fy) * 0.5 + 0.5
			var grain: float = detail.get_noise_2d(fx, fy) * 0.5 + 0.5
			# The lobe multiplies the disc instead of merely dimming it, so it carves
			# the boundary. That is what stops a puff reading as a stamped circle: the
			# silhouette is decided by the noise, not by the radial falloff.
			var alpha: float = pow(body, 1.35) * (0.28 + 1.10 * lobe) * (0.78 + 0.22 * grain)

			# The warp can push density to the square's edge, so force the border
			# back to zero or the quad would show as a rectangle.
			var edge: float = minf(1.0 - abs(u), 1.0 - abs(v))
			alpha *= smoothstep(0.0, 0.12, edge)

			# Top lit, base shaded. In texture space y = 0 is the top row.
			var light: float = lerpf(1.0, 0.84, clampf((v + 1.0) * 0.5, 0.0, 1.0))
			image.set_pixel(x, y, Color(light, light, light, clampf(alpha, 0.0, 1.0)))

	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Rebuilds the visible ring from scratch. A cell that stays in the ring keeps the
## same seed, so its puffs do not move when the ship crosses a boundary; only the
## cells entering and leaving the ring change.
func _rebuild() -> void:
	if _multimeshes.is_empty() or _player == null:
		return

	var center: Vector2i = _cell_of(_player.global_position)
	var player_planar: Vector2 = Vector2(_player.global_position.x, _player.global_position.z)
	var reach: int = int(ceil(STREAM_RADIUS / CELL_SIZE))
	_indices.fill(0)
	_written = 0

	for cz in range(center.y - reach, center.y + reach + 1):
		if _written >= MAX_PUFFS:
			break
		for cx in range(center.x - reach, center.x + reach + 1):
			if _written >= MAX_PUFFS:
				break
			var cell_center: Vector2 = (Vector2(cx, cz) + Vector2(0.5, 0.5)) * CELL_SIZE
			if cell_center.distance_to(player_planar) > STREAM_RADIUS:
				continue

			var density: float = density_at(Vector3(cell_center.x, 0.0, cell_center.y))
			if density <= VISUAL_MIN_DENSITY:
				continue

			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = _cell_seed(cx, cz)

			# One candidate per sub-cell, placed on a jittered grid. Uniform scatter
			# inside the cell clumps and leaves holes, and with a hard density gate the
			# holes are what the eye sees: a lattice of separate discs.
			var step: float = CELL_SIZE / float(SUBGRID)
			var cell_origin: Vector2 = cell_center - Vector2(CELL_SIZE, CELL_SIZE) * 0.5
			for sz in SUBGRID:
				for sx in SUBGRID:
					var site: Vector2 = cell_origin + Vector2(
						(float(sx) + rng.randf()) * step,
						(float(sz) + rng.randf()) * step
					)
					# Density is read at the puff, never at the cell centre. Gating the
					# whole cell quantises the edge of a bank to 18 units, and the cells
					# that only just qualify draw a single disc each -- which is exactly
					# how the deck used to look over the water.
					var site_density: float = density_at(Vector3(site.x, 0.0, site.y))
					if site_density <= VISUAL_MIN_DENSITY:
						continue
					_add_puff(rng, site, site_density)

	for variant in _multimeshes.size():
		_multimeshes[variant].visible_instance_count = _indices[variant]
	_visible_puffs = _written


## Writes one detail puff into a variant's MultiMesh. Size and opacity both follow
## the local density, so the fringe stays wispy and a core builds up to solid as the
## puffs overlap. The variant is chosen per puff, so a cluster never repeats the same
## silhouette twice in a row.
func _add_puff(rng: RandomNumberGenerator, site: Vector2, density: float) -> void:
	if _written >= MAX_PUFFS:
		return
	var variant: int = rng.randi_range(0, PUFF_VARIANTS - 1)
	var index: int = _indices[variant]
	if index >= MAX_PUFFS:
		return

	var growth: float = smoothstep(VISUAL_MIN_DENSITY, VISUAL_FULL_DENSITY, density)
	var size: float = lerpf(PUFF_MIN_SIZE, PUFF_MAX_SIZE, growth) * rng.randf_range(0.80, 1.25)
	var height: float = rng.randf_range(PUFF_MIN_Y, PUFF_MAX_Y)
	var alpha: float = lerpf(DETAIL_ALPHA_MIN, DETAIL_ALPHA_MAX, growth)
	var tint: float = rng.randf_range(0.94, 1.03)
	var brightness: float = lerpf(0.92, 1.0, growth)
	var basis: Basis = Basis().scaled(Vector3(size, size, size))
	_multimeshes[variant].set_instance_transform(
		index, Transform3D(basis, Vector3(site.x, height, site.y))
	)
	_multimeshes[variant].set_instance_color(
		index,
		Color(
			CLOUD_TINT.r * tint * brightness,
			CLOUD_TINT.g * tint * brightness,
			CLOUD_TINT.b * tint * brightness,
			alpha
		)
	)
	_indices[variant] = index + 1
	_written += 1


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))


## Stable per-cell seed. The same cell draws the same puffs on every rebuild, which
## is what keeps the deck from boiling as the ship moves.
func _cell_seed(cx: int, cz: int) -> int:
	return (cx * 73856093) ^ (cz * 19349663) ^ CLOUD_SEED
