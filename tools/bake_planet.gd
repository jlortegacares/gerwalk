extends Node
## Offline bake for the planet's terrain field.
##
## The planet is a 1600-unit sphere whose vertices sit ~52 units apart, so the
## mesh cannot carry terrain: every landform on screen is a shading effect. What
## the mesh also cannot give us is *global structure* -- where a range runs, which
## way a river drains, where a city could plausibly sit -- because all of that
## needs the whole planet at once. So it is computed here, once, and shipped as a
## six-face cube field the surface shader samples per pixel.
##
## Resolution is the thing to understand here. One texel of a 512-face is 6.25
## world units, and the camera sees a 128 x 72 unit patch, so a screenful is about
## 20 x 11 texels. That is enough for a coastline, a range or a river to cross the
## view; it is nowhere near enough to draw a hill. So this bakes only what needs
## the whole planet, and `planet_surface.gdshader` synthesises everything smaller.
##
## Run with:
##     ./run.sh --headless tools/bake_planet.tscn
##     ./run.sh --headless tools/bake_planet.tscn -- --dir-debug
##
## `--dir-debug` writes the object-space direction itself into the field instead of
## the terrain. Rendering the cube with it and comparing against the analytic
## formula proves the cubemap orientation convention, which is otherwise a silent
## source of mirrored faces and seams.

const N: int = 512
const CELLS: int = N * N
const TOTAL: int = CELLS * 6

const PLANET_RADIUS: float = 1600.0
## Peak relief in world units. Only a shading scale: the ground never moves.
const RELIEF_UNITS: float = 60.0
const RIVER_MAX_DISTANCE: float = 24.0
## Share of the surface that ends up underwater. The sea threshold is solved from
## this instead of being hand-tuned, so changing a noise parameter cannot quietly
## turn the planet into an ocean or a desert.
const WATER_FRACTION: float = 0.58
## Share of the land that becomes river channel. Rivers are the drainage network
## above this cut, not every gully: a planet where every slope has a stream has no
## rivers left, only texture.
const RIVER_SHARE: float = 0.022
## Share of the land that becomes a city site.
const CITY_SHARE: float = 0.035

const OUT_PATH: String = "res://levels/arena/planet_field.res"
const ResourceScript = preload("res://levels/arena/planet_field.gd")

# --- the detail layer -------------------------------------------------------
## The bake above carries what needs the whole planet. Everything shorter than one
## of its texels is synthesised, and that synthesis was the single most expensive
## thing in the surface shader: three evaluations of a three-chain ridged field per
## fragment, 72 hashes and 9 `pow`. Stubbing it out entirely measured 61.7 ms
## against 76.5 ms at 5120 x 2880, so a fifth of the frame was spent rebuilding the
## same values pixel by pixel.
##
## It is baked here instead. What the fragment actually needs from the detail is
## not its height -- nothing is displaced, the palette never reads it -- but two
## finite differences and one curvature term. So the field is differentiated here,
## at exactly the offsets the shader uses, and shipped as a tangent-plane gradient
## plus the cavity.
##
## 1024 per face is 3.1 world units per texel, against a 1.5-unit sample offset:
## fine enough that the gradient the shader reads is the gradient of the feature,
## not of the texel grid.
const DETAIL_N: int = 1024
const DETAIL_OUT_PATH: String = "res://levels/arena/planet_detail.res"
const DetailScript = preload("res://levels/arena/planet_detail.gd")

## These four mirror the constants of the same name in
## `levels/arena/planet_surface.gdshader`. They are the definition of the field,
## not tuning: change one there and the bake must be re-run, or the relief stops
## agreeing with the arithmetic it replaced.
const DETAIL_STEP: float = 1.5
const DETAIL_HEIGHT: float = 0.85
const CAVITY_GAIN: float = 38.4
## Detail slope, in world units per world unit, that maps to the top of the byte
## range. Measured with `--detail-stats`, not guessed: the field's `|g|` sits at a
## p99 of 1.14 and only 0.012 % of texels pass 2.0, so 2.0 spends the byte on the
## slopes that exist instead of on a tail nobody sees. A byte then resolves 0.0157
## of slope, which at `RELIEF_BOOST` is a shade under a degree of facet -- the same
## order as the 8-bit normal maps this replaces nothing but resembles. The 0.012 %
## that clips are the sharpest crests, where the normal is saturated anyway.
const DETAIL_SLOPE_RANGE: float = 2.0

## Image row 0 maps to +v (false) or -v (true). Settled by `--dir-debug`; do not
## guess, a wrong value mirrors every face and tears the field at the twelve edges.
const FLIP_V: bool = false

## Elevation priority queue, quantised. Filled heights only ever move up, so a
## monotone bucket queue replaces a binary heap.
const BUCKETS: int = 4096

## Width, in texels, of the ring that is feathered across a cube edge.
const SEAM_RING: int = 2

var _field: PackedFloat32Array
var _elev: PackedFloat32Array
var _filled: PackedFloat32Array
var _neighbours: PackedInt32Array
var _visited: PackedByteArray
var _parent: PackedInt32Array
var _flow: PackedFloat32Array
var _river: PackedFloat32Array
var _city: PackedFloat32Array
var _moisture: PackedFloat32Array

var _buckets: Array = []
var _level: int = 0
var _order: PackedInt32Array

var _basin: FastNoiseLite
var _mass: FastNoiseLite
var _wander: FastNoiseLite
var _ridge: FastNoiseLite
var _warp: FastNoiseLite
var _damp: FastNoiseLite
var _urban: FastNoiseLite

var _sea: float = 0.5
var _field_low: float = -1.0
var _field_high: float = 1.0
var _peak: float = 1.0


func _ready() -> void:
	if "--dir-debug" in OS.get_cmdline_user_args():
		_bake_direction_debug()
		get_tree().quit()
		return

	var t0: int = Time.get_ticks_msec()
	_make_noise()

	_build_field()
	print("field   %5d ms  water %.1f%%  sea %.4f" % [
		Time.get_ticks_msec() - t0, 100.0 * _water_share(), _sea
	])

	_neighbours_ready()
	_build_relief()
	_elev = _stitch(_elev, 2)
	print("relief  %5d ms  peak %.3f" % [Time.get_ticks_msec() - t0, _peak])
	_report_land()

	if "--detail-stats" in OS.get_cmdline_user_args():
		_detail_stats()
		get_tree().quit()
		return

	_drain()
	print("drain   %5d ms" % (Time.get_ticks_msec() - t0))

	_build_rivers()
	print("rivers  %5d ms  channel %.2f%% of the land" % [
		Time.get_ticks_msec() - t0, _channel_share()
	])

	_build_city_sites()
	print("cities  %5d ms  sites %.2f%% of the land" % [
		Time.get_ticks_msec() - t0, _city_share()
	])

	_build_moisture()
	_save()
	_build_detail()
	print("baked in %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


# --- cube face geometry -----------------------------------------------------

## Direction of the centre of one texel. `u` runs along the image's columns and
## `v` down its rows.
func _cell_dir(face: int, i: int, j: int) -> Vector3:
	return _cell_dir_at(face, i, j, N)


func _cell_dir_at(face: int, i: int, j: int, n: int) -> Vector3:
	var u: float = (float(i) + 0.5) / float(n) * 2.0 - 1.0
	var v: float = (float(j) + 0.5) / float(n) * 2.0 - 1.0
	if FLIP_V:
		v = -v
	return _raw_dir(face, u, v).normalized()


## The cube's face parameterisation, unnormalised and unclamped, so a coordinate
## outside [-1, 1] continues into the neighbouring face's direction. That is what
## makes the edge neighbours exact instead of a best guess.
func _raw_dir(face: int, u: float, v: float) -> Vector3:
	match face:
		0: return Vector3(1.0, -v, -u)
		1: return Vector3(-1.0, -v, u)
		2: return Vector3(u, 1.0, v)
		3: return Vector3(u, -1.0, -v)
		4: return Vector3(u, -v, 1.0)
		_: return Vector3(-u, -v, -1.0)


## Which texel a direction lands on. This is the cubemap hardware's own rule, so
## the neighbour graph lines up with the texels the shader will actually read.
func _encode(direction: Vector3) -> int:
	var ax: float = absf(direction.x)
	var ay: float = absf(direction.y)
	var az: float = absf(direction.z)

	var face: int
	var sc: float
	var tc: float
	if ax >= ay and ax >= az:
		if direction.x > 0.0:
			face = 0
			sc = -direction.z / ax
		else:
			face = 1
			sc = direction.z / ax
		tc = -direction.y / ax
	elif ay >= az:
		if direction.y > 0.0:
			face = 2
			tc = direction.z / ay
		else:
			face = 3
			tc = -direction.z / ay
		sc = direction.x / ay
	else:
		if direction.z > 0.0:
			face = 4
		else:
			face = 5
		sc = direction.x / az if direction.z > 0.0 else -direction.x / az
		tc = -direction.y / az

	var u: float = (sc + 1.0) * 0.5
	var v: float = (tc + 1.0) * 0.5
	if FLIP_V:
		v = 1.0 - v
	var i: int = clampi(int(u * float(N)), 0, N - 1)
	var j: int = clampi(int(v * float(N)), 0, N - 1)
	return face * CELLS + j * N + i


## Four neighbours per texel, in -u, +u, -v, +v order. Interior texels are index
## arithmetic; only the border ring pays for a direction encode.
func _neighbours_ready() -> void:
	_neighbours.resize(TOTAL * 4)
	var step: float = 2.0 / float(N)
	for face in 6:
		for j in N:
			var v01: float = (float(j) + 0.5) / float(N)
			for i in N:
				var cell: int = face * CELLS + j * N + i
				var base: int = cell * 4
				var uu: float = (float(i) + 0.5) * step - 1.0
				var vv: float = v01 * 2.0 - 1.0
				if i > 0:
					_neighbours[base] = cell - 1
				else:
					_neighbours[base] = _encode(_raw_dir(face, uu - step, vv))
				if i < N - 1:
					_neighbours[base + 1] = cell + 1
				else:
					_neighbours[base + 1] = _encode(_raw_dir(face, uu + step, vv))
				if j > 0:
					_neighbours[base + 2] = cell - N
				else:
					_neighbours[base + 2] = _encode(_raw_dir(face, uu, vv - step))
				if j < N - 1:
					_neighbours[base + 3] = cell + N
				else:
					_neighbours[base + 3] = _encode(_raw_dir(face, uu, vv + step))


# --- noise ------------------------------------------------------------------

func _make_noise() -> void:
	# Three scales, three jobs. Wavelengths, not frequencies, are what matter:
	# `basin` spans ~1100 units so the sea has somewhere to be open, `mass` spans
	# ~310 and is the landmass the ship actually crosses, `wander` spans ~90 and
	# only ruffles the shoreline. Nothing here is allowed to be fast: the field is
	# read at 6.25 units per texel, so a fast octave is speckle, and speckle at
	# that texel size is a coastline made of confetti.
	_basin = _noise(11, 2, 0.36)
	_mass = _noise(29, 3, 0.42)
	_wander = _noise(47, 2, 0.32)
	_ridge = _noise(83, 4, 0.46)
	_warp = _noise(97, 2, 0.40)
	_damp = _noise(131, 2, 0.40)
	_urban = _noise(163, 2, 0.40)
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED


func _noise(seed_value: int, octaves: int, gain: float) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.0
	return noise


# --- land field -------------------------------------------------------------

## The coastline. Three scales with the same jobs they always had: `basin`
## decides where there is open ocean at all, `mass` carves the landmass the ship
## crosses, and `wander` keeps the shoreline from being a smooth blob. Only the
## generator changed -- three octaves of value noise per scale was minutes of bake
## time -- and the scales were widened, because at the old ones a landmass was
## three texels and the planet read as noise.
func _build_field() -> void:
	_field.resize(TOTAL)
	var low: float = INF
	var high: float = -INF
	for face in 6:
		for j in N:
			for i in N:
				var cell: int = face * CELLS + j * N + i
				var p: Vector3 = _cell_dir(face, i, j) * PLANET_RADIUS
				var basin: float = _basin.get_noise_3dv(p * 0.0009)
				var mass: float = _mass.get_noise_3dv(p * 0.0032)
				var wander: float = _wander.get_noise_3dv(p * 0.0110)
				var value: float = basin * 0.62 + mass * 0.52 + wander * 0.12
				_field[cell] = value
				low = minf(low, value)
				high = maxf(high, value)

	# The sea cut is a percentile, so the water share is a design decision and not
	# an accident of how the amplitudes happened to land.
	_field_low = low
	_field_high = high
	_sea = _percentile(_field, WATER_FRACTION)
	print("        field range %.3f .. %.3f" % [low, high])


func _water_share() -> float:
	var water: int = 0
	for cell in TOTAL:
		if _field[cell] < _sea:
			water += 1
	return float(water) / float(TOTAL)


## Signed elevation: land rises from 0 at the waterline to 1 at the peak, water
## sinks to -1 at the trench. One channel, both meanings, never ambiguous.
func _build_relief() -> void:
	_elev.resize(TOTAL)
	var peak: float = 0.0
	for cell in TOTAL:
		var f: float = _field[cell]
		if f <= _sea:
			_elev[cell] = -clampf((_sea - f) / maxf(_sea - _field_low, 0.0001), 0.0, 1.0) * 0.85
			continue

		# Distance inland as a 0..1 value. The first stretch of it is coastal
		# plain, which is what actually surrounds most coastlines; the climb
		# starts once there is somewhere for it to climb from.
		var shore: float = (f - _sea) / maxf(_field_high - _sea, 0.0001)
		var plain: float = smoothstep(0.0, 0.62, shore) * 0.42

		var p: Vector3 = _direction_of(cell) * PLANET_RADIUS
		# Warp the sample before the ridge lookup: an unwarped ridged field is
		# isotropic and round, while ranges are long, thin and curved. The warp
		# amplitude is a good fraction of the range spacing on purpose.
		var w: float = _warp.get_noise_3dv(p * 0.0035) * 230.0
		var q: Vector3 = p + Vector3(w, w * 0.55, -w * 0.8)
		var ridge: float = clampf(_ridge.get_noise_3dv(q * 0.0052), 0.0, 1.0)
		# Cubing keeps the crest and drops the shoulders, so a range is a line of
		# peaks instead of a wide swell.
		ridge = ridge * ridge * ridge
		# Damping keeps whole regions low: without it the ranges cover the planet
		# evenly and every landmass is spiky.
		var damp: float = clampf(_damp.get_noise_3dv(p * 0.0021) * 0.5 + 0.72, 0.0, 1.0)
		var inland: float = smoothstep(0.04, 0.40, shore)

		var value: float = plain + ridge * inland * damp * 0.95
		_elev[cell] = value
		peak = maxf(peak, value)

	if peak > 0.0:
		for cell in TOTAL:
			if _elev[cell] > 0.0:
				_elev[cell] = _elev[cell] / peak
	_peak = peak


## Averages the outer ring of every face against its cross-edge neighbours.
##
## The six faces are baked independently, so the texels either side of a cube edge
## describe directions half a texel apart. The value itself is nearly the same; its
## *derivative* is not. The shader takes derivatives of this field to shade it, so
## the mismatch draws a perfectly straight crease across the ground wherever a face
## boundary crosses the view -- which is exactly what a 512-face cubemap does, once
## every 128 units, right in the middle of a camera that sees 128.
##
## Averaging across the edge removes the jump. Two passes are enough: the error is
## half a texel, and the ring is two texels wide, so the correction fades inward
## instead of stopping at a line one texel in.
func _stitch(values: PackedFloat32Array, passes: int) -> PackedFloat32Array:
	for _pass in passes:
		var next: PackedFloat32Array = values.duplicate()
		for face in 6:
			for j in N:
				for i in N:
					if i >= SEAM_RING and i < N - SEAM_RING and j >= SEAM_RING and j < N - SEAM_RING:
						continue
					var cell: int = face * CELLS + j * N + i
					var sum: float = values[cell]
					for k in 4:
						sum += values[_neighbours[cell * 4 + k]]
					next[cell] = sum / 5.0
		values = next
	return values


func _direction_of(cell: int) -> Vector3:
	var face: int = cell / CELLS
	var rest: int = cell - face * CELLS
	return _cell_dir(face, rest % N, rest / N)


## How the land is spread over the elevation range. A landmass whose heights are
## all in the first band has no mountains, whatever its maximum says, so this is
## printed on every bake.
func _report_land() -> void:
	var bins: PackedInt32Array = PackedInt32Array()
	bins.resize(10)
	bins.fill(0)
	var land: int = 0
	for cell in TOTAL:
		if _elev[cell] <= 0.0:
			continue
		land += 1
		bins[clampi(int(_elev[cell] * 10.0), 0, 9)] += 1
	var line: String = "        land by height:"
	for b in 10:
		line += " %.1f%%" % (100.0 * float(bins[b]) / maxf(float(land), 1.0))
	print(line)


# --- drainage ---------------------------------------------------------------

## Priority flood from the sea inward. Filling depressions as it goes means every
## land cell ends up with a parent it drains through, so the whole planet has a
## flow tree and rivers reach the coast instead of dying in a puddle.
func _drain() -> void:
	_filled = _elev.duplicate()
	_visited.resize(TOTAL)
	_visited.fill(0)
	_parent.resize(TOTAL)
	_parent.fill(-1)
	_flow.resize(TOTAL)
	_flow.fill(0.0)
	_order = PackedInt32Array()

	_buckets = []
	for b in BUCKETS:
		_buckets.append([])
	_level = 0

	for cell in TOTAL:
		if _elev[cell] >= 0.0:
			continue
		# Only the coastal ring seeds the flood. Pushing the whole ocean would put
		# a million cells in the queue to reach the same coastline.
		var base: int = cell * 4
		for k in 4:
			if _elev[_neighbours[base + k]] >= 0.0:
				_visited[cell] = 1
				_push(cell, _elev[cell])
				break

	while true:
		var cell: int = _pop()
		if cell < 0:
			break
		_order.append(cell)
		var level: float = _filled[cell]
		var base: int = cell * 4
		for k in 4:
			var next: int = _neighbours[base + k]
			if _visited[next] != 0:
				continue
			_visited[next] = 1
			_parent[next] = cell
			var raised: float = maxf(_elev[next], level)
			_filled[next] = raised
			_push(next, raised)

	for cell in TOTAL:
		_flow[cell] = 1.0 if _elev[cell] >= 0.0 else 0.0
	# Reverse fill order: a cell is queued only when its parent is popped, so every
	# child sits later in the order than its parent.
	for k in range(_order.size() - 1, -1, -1):
		var cell: int = _order[k]
		var parent: int = _parent[cell]
		if parent >= 0:
			_flow[parent] += _flow[cell]


func _push(cell: int, height: float) -> void:
	var bucket: int = int((height + 1.0) * 0.5 * float(BUCKETS - 1))
	bucket = clampi(bucket, _level, BUCKETS - 1)
	_buckets[bucket].append(cell)


func _pop() -> int:
	while _level < BUCKETS:
		var bucket: Array = _buckets[_level]
		if not bucket.is_empty():
			return bucket.pop_back()
		_level += 1
	return -1


# --- rivers -----------------------------------------------------------------

## Rivers are the drainage network above a size threshold, turned into a distance
## field measured in world units. The distance field is the point: a river is two
## units wide and a texel is six, so a mask could only ever draw a six-unit
## stroke, while a distance field reconstructs a two-unit channel between texels.
##
## The transform is an eight-direction chamfer, which is close enough to Euclidean
## for the width to stay honest in every direction. A four-connected flood would
## make a diagonal river one and a half times too wide.
func _build_rivers() -> void:
	var log_flow: PackedFloat32Array = PackedFloat32Array()
	log_flow.resize(TOTAL)
	for cell in TOTAL:
		log_flow[cell] = log(1.0 + _flow[cell]) if _elev[cell] >= 0.0 else 0.0

	# Only land takes part in the percentile. The sea holds most of the cells and
	# all of them are zero, so a cut taken over the whole surface silently means
	# something different every time the water share moves.
	var threshold: float = _percentile_land(log_flow, 1.0 - RIVER_SHARE)

	var texel: float = 2.0 * PLANET_RADIUS / float(N)
	var far: float = RIVER_MAX_DISTANCE
	_river.resize(TOTAL)
	_river.fill(far)

	var front: Array = []
	for cell in TOTAL:
		if _elev[cell] < 0.0 or log_flow[cell] < threshold:
			continue
		_river[cell] = 0.0
		front.append(cell)

	# Four-connected rings outward. That measures Manhattan distance, so a
	# diagonal channel is a dab wider than a straight one, which is invisible at
	# the width the shader draws. A true Euclidean transform would say the same
	# thing a few percent more precisely.
	var rings: int = int(ceil(far / texel))
	for ring in rings:
		var value: float = float(ring + 1) * texel
		var next: Array = []
		for cell in front:
			var base: int = cell * 4
			for k in 4:
				var neighbour: int = _neighbours[base + k]
				if _river[neighbour] <= value:
					continue
				_river[neighbour] = value
				next.append(neighbour)
		front = next
		if front.is_empty():
			break

	# No smoothing pass here, and that took a bake to learn: averaging a distance
	# field whose seeds are 0 pulls every seed up to its neighbours' mean, so the
	# whole channel disappears and only the spots where several seeds touch
	# survive. The rings are already the ramp the shader needs -- bilinear sampling
	# turns the 0-to-one-texel step into a channel a fraction of a texel wide.
	for cell in TOTAL:
		_river[cell] = clampf(_river[cell] / far, 0.0, 1.0)


func _channel_share() -> float:
	var channel: int = 0
	var land: int = 0
	for cell in TOTAL:
		if _elev[cell] <= 0.0:
			continue
		land += 1
		if _river[cell] < 0.5 * 2.0 * PLANET_RADIUS / float(N) / RIVER_MAX_DISTANCE:
			channel += 1
	return 100.0 * float(channel) / maxf(float(land), 1.0)


# --- cities and biomes ------------------------------------------------------

## Where a city could plausibly be: low, flat, near the coast, and in a cluster
## rather than sprinkled everywhere. The shader still draws the districts, but it
## asks this field whether there is a city at all.
func _build_city_sites() -> void:
	var texel: float = 2.0 * PLANET_RADIUS / float(N)

	# Distance to the sea, in world units, as a four-connected flood outward.
	var coast: PackedFloat32Array = PackedFloat32Array()
	coast.resize(TOTAL)
	coast.fill(120.0)
	var front: Array = []
	for cell in TOTAL:
		if _elev[cell] < 0.0:
			coast[cell] = 0.0
			front.append(cell)
	var travelled: float = 0.0
	while not front.is_empty() and travelled < 120.0:
		travelled += texel
		var next_front: Array = []
		for cell in front:
			var base: int = cell * 4
			for k in 4:
				var neighbour: int = _neighbours[base + k]
				if coast[neighbour] <= travelled:
					continue
				coast[neighbour] = travelled
				next_front.append(neighbour)
		front = next_front

	_city.resize(TOTAL)
	for cell in TOTAL:
		var height: float = _elev[cell]
		if height <= 0.0:
			_city[cell] = 0.0
			continue

		var base: int = cell * 4
		var slope: float = 0.0
		for k in 4:
			slope = maxf(slope, absf(_elev[_neighbours[base + k]] - height))
		# Slope is a per-texel difference, so dividing by the texel size turns it
		# into a real gradient and the thresholds stay meaningful if N changes.
		slope = slope * RELIEF_UNITS / texel

		var near_water: float = 1.0 - smoothstep(35.0, 140.0, coast[cell])
		# There has to be a shore to sail to and a hinterland to feed it. Without the
		# second term the best sites on the planet were sandbars: a fifty-unit island
		# is "low, flat and near the water" by every other measure, and a district is
		# twenty units wide, so the city landed in the sea on all sides.
		var hinterland: float = smoothstep(45.0, 85.0, coast[cell])
		var low: float = 1.0 - smoothstep(0.10, 0.34, height)
		var flat: float = 1.0 - smoothstep(0.10, 0.26, slope)
		var p: Vector3 = _direction_of(cell) * PLANET_RADIUS
		var cluster: float = smoothstep(-0.22, 0.28, _urban.get_noise_3dv(p * 0.0042))
		_city[cell] = near_water * hinterland * low * flat * cluster

	var threshold: float = _percentile_land(_city, 1.0 - CITY_SHARE)
	for cell in TOTAL:
		_city[cell] = smoothstep(threshold, threshold + 0.10, _city[cell])


func _city_share() -> float:
	var sites: int = 0
	var land: int = 0
	var districts: int = 0
	for cell in TOTAL:
		if _elev[cell] <= 0.0:
			continue
		land += 1
		if _city[cell] > 0.30:
			sites += 1
	districts = sites
	return 100.0 * float(sites) / maxf(float(land), 1.0)


## Moisture only picks a grass tone, so one low-frequency field is enough.
func _build_moisture() -> void:
	_moisture.resize(TOTAL)
	for cell in TOTAL:
		var p: Vector3 = _direction_of(cell) * PLANET_RADIUS
		_moisture[cell] = clampf(_basin.get_noise_3dv(p * 0.0026) * 1.9 + 0.5, 0.0, 1.0)


# --- detail layer -----------------------------------------------------------

## Chooses `DETAIL_SLOPE_RANGE` from the field itself, and times one pass of it.
##
## The byte range has to cover the tails: a crest that clips reads as a flat top,
## and the whole point of the layer is crests. It is read from the data rather than
## guessed, because the amplitude of a ridged field is not obvious from its weights
## -- `pow(n, 1.35)` spends most of its range near a value the derivative rarely
## reaches.
func _detail_stats() -> void:
	var n: int = 64
	var t0: int = Time.get_ticks_msec()
	var slope_x: PackedFloat32Array = PackedFloat32Array()
	var slope_y: PackedFloat32Array = PackedFloat32Array()
	var slope_z: PackedFloat32Array = PackedFloat32Array()
	var magnitude: PackedFloat32Array = PackedFloat32Array()
	var cavity_values: PackedFloat32Array = PackedFloat32Array()
	for face in 6:
		for j in n:
			for i in n:
				var detail: Vector4 = _detail_at(_cell_dir_at(face, i, j, n))
				slope_x.append(absf(detail.x))
				slope_y.append(absf(detail.y))
				slope_z.append(absf(detail.z))
				magnitude.append(Vector3(detail.x, detail.y, detail.z).length())
				cavity_values.append(detail.w)
	var ms: int = Time.get_ticks_msec() - t0
	print("detail stats over %d texels in %d ms  ->  %d x %d per face projects to %d s" % [
		n * n * 6, ms, DETAIL_N, DETAIL_N,
		int(ms * pow(float(DETAIL_N) / float(n), 2.0) / 1000.0),
	])
	for entry in [["|gx|", slope_x], ["|gy|", slope_y], ["|gz|", slope_z], ["|g| ", magnitude]]:
		print("        %s p50 %6.3f  p90 %6.3f  p99 %6.3f  p99.9 %6.3f  max %6.3f" % [
			entry[0],
			_stat(entry[1], 0.50), _stat(entry[1], 0.90), _stat(entry[1], 0.99),
			_stat(entry[1], 0.999), _stat(entry[1], 1.0),
		])
	print("        cavity min %6.3f  max %6.3f  p01 %6.3f  p99 %6.3f" % [
		_stat(cavity_values, 0.0), _stat(cavity_values, 1.0),
		_stat(cavity_values, 0.01), _stat(cavity_values, 0.99),
	])
	print("        |g| p99.99 %6.3f   above 1.5 %.3f%%   above 2.0 %.3f%%   above 2.5 %.3f%%" % [
		_stat(magnitude, 0.9999), _share_above(magnitude, 1.5),
		_share_above(magnitude, 2.0), _share_above(magnitude, 2.5),
	])


func _share_above(values: PackedFloat32Array, threshold: float) -> float:
	var hits: int = 0
	for value in values:
		if value > threshold:
			hits += 1
	return 100.0 * float(hits) / float(values.size())


func _stat(values: PackedFloat32Array, fraction: float) -> float:
	var sorted: PackedFloat32Array = values.duplicate()
	sorted.sort()
	var index: int = clampi(int(round(fraction * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return sorted[index]


## The detail layer as the fragment used to compute it, differentiated here.
##
## Returns the rise as a *tangent-plane vector in object space*, not as two
## components in the local frame. That distinction is the whole reason this bakes
## cleanly: the tangent frame the shader builds flips ninety degrees where
## `|up.y|` crosses 0.9, and a cubemap blends neighbouring texels. Stored as two
## frame-relative scalars, every texel on that circle would be averaged with a
## value measured in a rotated frame and the planet would carry a ring of wrong
## shading. Stored as a vector, the field is frame-free and the blend is honest.
##
## `w` is the cavity, kept as a channel rather than rederived at runtime from
## `rise_u + rise_v`: the identity is exact, but it only holds while both the gain
## and the offsets in the shader match this file, and a channel that is already
## being read costs nothing.
func _detail_at(direction: Vector3) -> Vector4:
	var p: Vector3 = direction * PLANET_RADIUS
	var tangent: Vector3 = _sphere_tangent(direction)
	var bitangent: Vector3 = direction.cross(tangent)
	var inland: float = smoothstep(0.03, 0.20, _sample_elev(direction))
	if inland <= 0.0:
		return Vector4.ZERO

	var base: float = _terrain_detail(p)
	var along_u: float = _terrain_detail(p + tangent * DETAIL_STEP)
	var along_v: float = _terrain_detail(p + bitangent * DETAIL_STEP)
	var rate: float = DETAIL_HEIGHT * RELIEF_UNITS / DETAIL_STEP
	var rise_u: float = (along_u - base) * DETAIL_HEIGHT * inland * rate
	var rise_v: float = (along_v - base) * DETAIL_HEIGHT * inland * rate

	var curvature: float = (along_u + along_v - base * 2.0) * DETAIL_HEIGHT * inland * CAVITY_GAIN
	var cavity: float = curvature / (1.0 + absf(curvature))

	var rise: Vector3 = tangent * rise_u + bitangent * rise_v
	return Vector4(rise.x, rise.y, rise.z, cavity)


func _build_detail() -> void:
	var t0: int = Time.get_ticks_msec()
	var faces: Array[Image] = []
	var texels: int = DETAIL_N * DETAIL_N
	for face in 6:
		var data: PackedByteArray = PackedByteArray()
		data.resize(texels * 4)
		for j in DETAIL_N:
			for i in DETAIL_N:
				var detail: Vector4 = _detail_at(_cell_dir_at(face, i, j, DETAIL_N))
				var at: int = (j * DETAIL_N + i) * 4
				data[at] = _byte_of_slope(detail.x)
				data[at + 1] = _byte_of_slope(detail.y)
				data[at + 2] = _byte_of_slope(detail.z)
				data[at + 3] = clampi(int(round((detail.w * 0.5 + 0.5) * 255.0)), 0, 255)
		# `use_mipmaps` here means "the data already carries them", not "generate
		# them": passing true makes `create_from_data` demand 1.33 x the bytes.
		var image: Image = Image.create_from_data(DETAIL_N, DETAIL_N, false, Image.FORMAT_RGBA8, data)
		image.generate_mipmaps()
		faces.append(image)

	var detail_field: Resource = DetailScript.new()
	detail_field.faces = faces
	detail_field.slope_range = DETAIL_SLOPE_RANGE
	# Compressed, not plain: the gradient field is smooth enough that PNG pays for
	# itself -- 33.6 MB become 8.8 MB -- and the format is lossless, so the bytes the
	# shader reads are the bytes measured here.
	var error: int = ResourceSaver.save(detail_field, DETAIL_OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	print("detail  %5d ms  %d x %d per face  slope range %.2f  %d bytes (error %d)" % [
		Time.get_ticks_msec() - t0, DETAIL_N, DETAIL_N, DETAIL_SLOPE_RANGE,
		FileAccess.get_file_as_bytes(DETAIL_OUT_PATH).size(), error,
	])


func _byte_of_slope(value: float) -> int:
	var unit: float = clampf(value / (DETAIL_SLOPE_RANGE * 2.0) + 0.5, 0.0, 1.0)
	return clampi(int(round(unit * 255.0)), 0, 255)


## The same tangent frame the shader builds: a global axis crossed with the normal,
## switching axis where the first choice would degenerate. Kept byte for byte
## identical because a different frame here would bake a gradient the fragment
## projects onto another one.
func _sphere_tangent(up: Vector3) -> Vector3:
	var axis: Vector3 = Vector3(0.0, 1.0, 0.0) if absf(up.y) < 0.9 else Vector3(1.0, 0.0, 0.0)
	return up.cross(axis).normalized()


## The baked elevation at an arbitrary direction, bilinearly sampled the way the
## hardware samples the cubemap. Only the `inland` mask needs it, but the mask is a
## multiplier on the whole layer: nearest-texel here would put a staircase under
## every coastline.
func _sample_elev(direction: Vector3) -> float:
	var face: int = 0
	var u: float = 0.0
	var v: float = 0.0
	var ax: float = absf(direction.x)
	var ay: float = absf(direction.y)
	var az: float = absf(direction.z)
	if ax >= ay and ax >= az:
		if direction.x > 0.0:
			face = 0
			u = -direction.z / direction.x
			v = -direction.y / direction.x
		else:
			face = 1
			u = -direction.z / direction.x
			v = direction.y / direction.x
	elif ay >= az:
		if direction.y > 0.0:
			face = 2
			u = direction.x / direction.y
			v = direction.z / direction.y
		else:
			face = 3
			u = -direction.x / direction.y
			v = direction.z / direction.y
	else:
		if direction.z > 0.0:
			face = 4
			u = direction.x / direction.z
			v = -direction.y / direction.z
		else:
			face = 5
			u = direction.x / direction.z
			v = -direction.y / direction.z
	if FLIP_V:
		v = -v

	var fx: float = (u + 1.0) * 0.5 * float(N) - 0.5
	var fy: float = (v + 1.0) * 0.5 * float(N) - 0.5
	var x0: int = clampi(int(floorf(fx)), 0, N - 1)
	var y0: int = clampi(int(floorf(fy)), 0, N - 1)
	var x1: int = mini(x0 + 1, N - 1)
	var y1: int = mini(y0 + 1, N - 1)
	var tx: float = clampf(fx - float(x0), 0.0, 1.0)
	var ty: float = clampf(fy - float(y0), 0.0, 1.0)
	var base: int = face * CELLS
	var top: float = lerpf(_elev[base + y0 * N + x0], _elev[base + y0 * N + x1], tx)
	var bottom: float = lerpf(_elev[base + y1 * N + x0], _elev[base + y1 * N + x1], tx)
	return lerpf(top, bottom, ty)


## The two crease shapes and the three-chain sum, transcribed from the shader.
## 64-bit floating point instead of 32 does not matter: this field *replaces* the
## analytic one, so it only has to agree with itself.
func _terrain_detail(p: Vector3) -> float:
	return (
		_terrain_crest(p * Vector3(0.013, 0.013, 0.024)) * 0.52
		+ _terrain_crest(p * Vector3(0.031, 0.031, 0.056)) * 0.26
		+ _terrain_ridge(p * 0.070) * 0.10
	)


func _terrain_ridge(p: Vector3) -> float:
	var n: float = 1.0 - absf(_value_noise3(p) * 2.0 - 1.0)
	return pow(n, 1.35)


func _terrain_crest(p: Vector3) -> float:
	var n: float = 1.0 - absf(_value_noise3(p) * 2.0 - 1.0)
	return pow(n, 1.10)


func _value_noise3(p: Vector3) -> float:
	var cell: Vector3 = p.floor()
	var local: Vector3 = p - cell
	var smoothed: Vector3 = local * local * (Vector3(3.0, 3.0, 3.0) - local * 2.0)

	var n000: float = _hash31(cell)
	var n100: float = _hash31(cell + Vector3(1.0, 0.0, 0.0))
	var n010: float = _hash31(cell + Vector3(0.0, 1.0, 0.0))
	var n110: float = _hash31(cell + Vector3(1.0, 1.0, 0.0))
	var n001: float = _hash31(cell + Vector3(0.0, 0.0, 1.0))
	var n101: float = _hash31(cell + Vector3(1.0, 0.0, 1.0))
	var n011: float = _hash31(cell + Vector3(0.0, 1.0, 1.0))
	var n111: float = _hash31(cell + Vector3(1.0, 1.0, 1.0))

	var x00: float = lerpf(n000, n100, smoothed.x)
	var x10: float = lerpf(n010, n110, smoothed.x)
	var x01: float = lerpf(n001, n101, smoothed.x)
	var x11: float = lerpf(n011, n111, smoothed.x)
	return lerpf(lerpf(x00, x10, smoothed.y), lerpf(x01, x11, smoothed.y), smoothed.z)


func _hash31(p: Vector3) -> float:
	var q: Vector3 = p * 0.1031
	q = Vector3(fposmod(q.x, 1.0), fposmod(q.y, 1.0), fposmod(q.z, 1.0))
	var spread: float = q.dot(Vector3(q.y + 33.33, q.z + 33.33, q.x + 33.33))
	q += Vector3(spread, spread, spread)
	return fposmod((q.x + q.y) * q.z, 1.0)


# --- output -----------------------------------------------------------------

func _save() -> void:
	var faces: Array[Image] = []
	for face in 6:
		var image: Image = Image.create_empty(N, N, false, Image.FORMAT_RGBAH)
		for j in N:
			for i in N:
				var cell: int = face * CELLS + j * N + i
				image.set_pixel(
					i,
					j,
					Color(_elev[cell], _river[cell], _city[cell], _moisture[cell])
				)
		faces.append(image)

	var field: Resource = ResourceScript.new()
	field.faces = faces
	field.relief_units = RELIEF_UNITS
	field.river_max_distance = RIVER_MAX_DISTANCE
	var error: int = ResourceSaver.save(field, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	print("saved %s (error %d) %d bytes" % [
		OUT_PATH, error, FileAccess.get_file_as_bytes(OUT_PATH).size()
	])


func _bake_direction_debug() -> void:
	var faces: Array[Image] = []
	for face in 6:
		var image: Image = Image.create_empty(N, N, false, Image.FORMAT_RGBAH)
		for j in N:
			for i in N:
				var direction: Vector3 = _cell_dir(face, i, j)
				image.set_pixel(
					i,
					j,
					Color(
						direction.x * 0.5 + 0.5,
						direction.y * 0.5 + 0.5,
						direction.z * 0.5 + 0.5,
						1.0
					)
				)
		faces.append(image)
	var field: Resource = ResourceScript.new()
	field.faces = faces
	print("direction debug saved (error %d)" % ResourceSaver.save(field, OUT_PATH))


# --- helpers ----------------------------------------------------------------

func _percentile(values: PackedFloat32Array, fraction: float) -> float:
	return _percentile_filtered(values, fraction, PackedByteArray())


## Percentile over the land cells only. `_elev` is the land mask used everywhere
## else in this file, so passing an empty mask means the whole surface.
func _percentile_land(values: PackedFloat32Array, fraction: float) -> float:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(TOTAL)
	for cell in TOTAL:
		mask[cell] = 1 if _elev[cell] > 0.0 else 0
	return _percentile_filtered(values, fraction, mask)


func _percentile_filtered(values: PackedFloat32Array, fraction: float, mask: PackedByteArray) -> float:
	var low: float = INF
	var high: float = -INF
	var count: int = 0
	for i in TOTAL:
		if mask.size() > 0 and mask[i] == 0:
			continue
		var value: float = values[i]
		low = minf(low, value)
		high = maxf(high, value)
		count += 1
	if count == 0 or high <= low:
		return low

	# A 2D histogram would be overkill: the values are log-flow or a suitability
	# score, both of which are smooth enough for a linear bucket to be exact to a
	# fraction of a texel's worth of distance.
	var bins: PackedInt32Array = PackedInt32Array()
	bins.resize(8192)
	bins.fill(0)
	var scale: float = 8191.0 / (high - low)
	for i in TOTAL:
		if mask.size() > 0 and mask[i] == 0:
			continue
		bins[clampi(int((values[i] - low) * scale), 0, 8191)] += 1

	var target: int = int(float(count) * fraction)
	var running: int = 0
	for b in 8192:
		running += bins[b]
		if running >= target:
			return low + float(b) / scale
	return high
