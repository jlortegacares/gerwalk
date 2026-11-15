extends Node
## Development helper: renders the planet surface from fixed orientations, so the
## terrain look can be iterated without chasing the ship's random flight path.
##
##     ./run.sh tools/terrain_study.tscn
##     ./run.sh tools/terrain_study.tscn -- --roll 0,0,0 --out /tmp/one.png
##     ./run.sh tools/terrain_study.tscn -- --land 6 --out /tmp/land.png
##
## The game camera looks almost straight down and sees a 128 x 72 unit patch, so a
## single gameplay frame is a coin toss: it can land on open sea and tell you
## nothing. Two ways out. `--roll` fixes the planet's orientation, which is the
## same camera angle over one known patch. `--land` is the useful default while
## working on terrain: it reads the baked field, finds orientations that put land
## under the lens, and captures the most spread-out ones.
##
## The sun is left where the arena puts it. Its angle is part of what is being
## judged, so moving it would review a different scene.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
const WARMUP_FRAMES: int = 120
const SETTLE_FRAMES: int = 6

const FIELD_PATH: String = "res://levels/arena/planet_field.res"
const FACE_SIZE: int = 512
const CELLS: int = FACE_SIZE * FACE_SIZE

## Degrees. The first entry is the arena's own orientation; the rest walk the
## planet under the same patch of sky.
const ROLLS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 47.0, 0.0),
	Vector3(0.0, 94.0, 0.0),
	Vector3(0.0, 141.0, 0.0),
	Vector3(0.0, 188.0, 0.0),
	Vector3(38.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 38.0),
	Vector3(-38.0, 0.0, -38.0),
]

## Directions a land search may choose from, and the minimum angle between two
## chosen ones, so a sweep samples different places and not the same range six
## times. Angles, not distances: the candidates are unit vectors.
const SEARCH_POINTS: int = 3000
## Finer, because a city is a 20-unit feature and the lens is 128 across: at the
## land-search density the lattice straddles most districts.
const CITY_SEARCH_POINTS: int = 24000
const SITE_SPACING: float = 0.42
## The lens covers a 128 x 72 unit patch, about 2.3 degrees either side of centre.
const PATCH_RADIUS: float = 0.040

var _arena: Node
var _planet: Node3D
var _frames: int = 0
var _index: int = 0
var _wait: int = 0

var _rolls: Array[Vector3] = []
var _targets: Array[Vector3] = []
var _output: String = ""
var _faces: Array = []


func _ready() -> void:
	_output = _argument("out", "")

	_faces = _load_faces()

	var single: String = _argument("roll", "")
	if single != "":
		_rolls.clear()
		_rolls.append(_roll_of(single))

	# A sweep, so a whole planet can be surveyed in one boot: booting the arena
	# costs more than the eight captures put together.
	var sweep: PackedStringArray = _argument("rolls", "").split(";", false)
	if not sweep.is_empty():
		_rolls.clear()
		for entry in sweep:
			_rolls.append(_roll_of(entry))

	# A city site, so the district shader can be judged at all. They occupy 2.7% of
	# the land, so a random orientation almost never lands on one.
	var city_count: int = int(_argument("city", "0"))
	if city_count > 0:
		for direction in _city_sites(city_count):
			_targets.append(direction)

	_arena = load(ARENA_SCENE).instantiate()
	add_child(_arena)

	if _argument("noclouds", "0") == "1":
		var clouds: Node = _arena.get_node_or_null("Clouds")
		if clouds != null:
			clouds.visible = false


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return

	# The arena rebuilds nothing after start-up, but it does roll the planet with
	# the ship's movement; the ship is parked here, so this orientation is ours.
	_planet = _arena.get_node_or_null("Planet") as Node3D
	if _planet == null:
		print("no Planet node in the arena")
		get_tree().quit()
		return

	if _index == 0 and _wait == 0 and _rolls.is_empty() and _targets.is_empty():
		_prepare()
		if _targets.is_empty() and _rolls.is_empty():
			get_tree().quit()
			return

	_orient()
	_wait += 1
	if _wait < SETTLE_FRAMES:
		return
	_wait = 0

	var path: String = _output if _index == 0 and _output != "" else "/tmp/terrain_%d.png" % _index
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(path)
	print("%s (error %d) at %s" % [path, error, _where()])

	# Reading a colour off a screenshot by eye is guesswork, and the probes below
	# are the only way to know what the shader actually computed. `--probe "x,y;x,y"`
	# prints the pixel values as numbers instead.
	for point in _argument("probe", "").split(";", false):
		var parts: PackedStringArray = point.split(",")
		if parts.size() < 2:
			continue
		var x: int = clampi(int(parts[0]), 0, image.get_width() - 1)
		var y: int = clampi(int(parts[1]), 0, image.get_height() - 1)
		var colour: Color = image.get_pixel(x, y)
		print("  probe (%d, %d) = %.3f %.3f %.3f" % [x, y, colour.r, colour.g, colour.b])

	_index += 1
	if _index >= _rolls.size() + _targets.size():
		get_tree().quit()


func _orient() -> void:
	if _index < _targets.size():
		# Rotate the planet so the chosen object-space direction sits under the
		# lens. The ship is the pole of its own patch, so its up is the direction
		# the camera is looking at.
		_planet.quaternion = Quaternion(_targets[_index], _patch_normal())
	else:
		_planet.rotation_degrees = _rolls[_index - _targets.size()]


func _where() -> String:
	if _index < _targets.size():
		return "target %s" % _targets[_index]
	return "roll %s" % _rolls[_index - _targets.size()]


## The world direction the lens is pointing at: the ship's own "up" on the sphere.
func _patch_normal() -> Vector3:
	var player: Node3D = _arena.get_node_or_null("Player") as Node3D
	var from: Vector3 = player.global_position if player != null else get_viewport().get_camera_3d().global_position
	return (from - _planet.global_position).normalized()


# --- land search ------------------------------------------------------------

## Picks orientations that put terrain under the lens, spread around the planet.
## Without this, a sweep of fixed rolls spends most of its frames over open ocean
## and says nothing about the hills.
func _prepare() -> void:
	var count: int = int(_argument("land", "0"))
	if count <= 0 or _faces.is_empty():
		_rolls = ROLLS.duplicate()
		return

	# Highlands, not coastline. The first version scored a patch by how much of it
	# was above the waterline, which dutifully selected the flattest ground on the
	# planet: coastal plain, where the relief layer is faded out by design. What is
	# worth looking at is the far side of that ramp.
	var candidates: Array[Vector3] = []
	for i in SEARCH_POINTS:
		var direction: Vector3 = _fibonacci(i, SEARCH_POINTS)
		var score: float = _patch_score(direction)
		if score > 0.15:
			candidates.append(direction)

	# Greedy spread: the first land direction found, then whichever is farthest
	# from every one already taken. A sweep that samples the same range twice is a
	# waste of a capture.
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	for candidate in candidates:
		var far: bool = true
		for taken in _targets:
			if candidate.angle_to(taken) < SITE_SPACING:
				far = false
				break
		if not far:
			continue
		_targets.append(candidate)
		if _targets.size() >= count:
			break

	print("land sites: %d of %d candidates" % [_targets.size(), candidates.size()])
	for target in _targets:
		var heights: Array[float] = _patch_heights(target)
		print("  site %s  height %.3f .. %.3f  mean %.3f" % [
			target, heights[0], heights[1], heights[2]
		])


## Mean elevation of the patch around `direction`, or -1 when the patch is not
## solidly land. Sampled on a small grid, because a patch with a coast across it
## says nothing about how hills read.
func _patch_score(direction: Vector3) -> float:
	var reference: Vector3 = Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	var t1: Vector3 = reference.cross(direction).normalized()
	var t2: Vector3 = direction.cross(t1)
	var land: int = 0
	var total: int = 0
	var sum: float = 0.0
	for j in 5:
		for i in 5:
			var u: float = (float(i) / 4.0 - 0.5) * 2.0 * PATCH_RADIUS
			var v: float = (float(j) / 4.0 - 0.5) * 2.0 * PATCH_RADIUS
			var sample: Vector3 = (direction + t1 * u + t2 * v).normalized()
			var elevation: float = _elevation(sample)
			if elevation > 0.02:
				land += 1
				sum += elevation
			total += 1
	if land < total:
		return -1.0
	return sum / float(total)


## Min, max and mean baked elevation over the lens patch. Printed while choosing
## sites, because "this patch is land" says nothing about how high that land is,
## and it is the height that decides which palette band the capture will show.
func _patch_heights(direction: Vector3) -> Array[float]:
	var reference: Vector3 = Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	var t1: Vector3 = reference.cross(direction).normalized()
	var t2: Vector3 = direction.cross(t1)
	var low: float = INF
	var high: float = -INF
	var sum: float = 0.0
	var count: int = 0
	for j in 9:
		for i in 9:
			var u: float = (float(i) / 8.0 - 0.5) * 2.0 * PATCH_RADIUS
			var v: float = (float(j) / 8.0 - 0.5) * 2.0 * PATCH_RADIUS
			var elevation: float = _elevation((direction + t1 * u + t2 * v).normalized())
			low = minf(low, elevation)
			high = maxf(high, elevation)
			sum += elevation
			count += 1
	return [low, high, sum / float(count)]


## Orientations whose lens lands on a baked city district, best first. Scores on a
## small grid so the district sits inside the view and not half off the edge.
func _city_sites(count: int) -> Array[Vector3]:
	var scored: Array = []
	# One texel per point, not a patch average: a district is 20 units wide inside a
	# 128-unit lens, so a coarse grid walks right past most of them. The centre
	# sample is the whole test; the patch is wide enough to hold the district.
	for i in CITY_SEARCH_POINTS:
		var direction: Vector3 = _fibonacci(i, CITY_SEARCH_POINTS)
		var score: float = _sample(direction).b
		if score > 0.30:
			scored.append([score, direction])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])

	var sites: Array[Vector3] = []
	for entry in scored:
		var candidate: Vector3 = entry[1]
		var far: bool = true
		for taken in sites:
			if candidate.angle_to(taken) < SITE_SPACING:
				far = false
				break
		if not far:
			continue
		sites.append(candidate)
		if sites.size() >= count:
			break
	print("city sites: %d of %d" % [sites.size(), scored.size()])
	for site in sites:
		print("  city %s  suitability %.3f" % [site, _sample(site).b])
	return sites


## Share of the patch around `direction` that the bake marked as urban.
func _district_score(direction: Vector3) -> float:
	var reference: Vector3 = Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	var t1: Vector3 = reference.cross(direction).normalized()
	var t2: Vector3 = direction.cross(t1)
	var urban: int = 0
	var total: int = 0
	for j in 5:
		for i in 5:
			var u: float = (float(i) / 4.0 - 0.5) * 2.0 * PATCH_RADIUS
			var v: float = (float(j) / 4.0 - 0.5) * 2.0 * PATCH_RADIUS
			var sample: Vector3 = (direction + t1 * u + t2 * v).normalized()
			if _sample(sample).b > 0.30:
				urban += 1
			total += 1
	return float(urban) / float(total)


func _fibonacci(index: int, count: int) -> Vector3:
	var offset: float = 2.0 / float(count)
	var y: float = float(index) * offset - 1.0 + offset * 0.5
	var radius: float = sqrt(maxf(1.0 - y * y, 0.0))
	var theta: float = 2.399963 * float(index)
	return Vector3(cos(theta) * radius, y, sin(theta) * radius)


# --- field sampling ---------------------------------------------------------

func _load_faces() -> Array:
	var field: Resource = load(FIELD_PATH)
	if field == null:
		print("no field at ", FIELD_PATH, "; use --roll instead")
		return []
	return field.faces


## Nearest-texel field sample, using the same cube encoding as the cubemap itself.
func _elevation(direction: Vector3) -> float:
	return _sample(direction).r


func _sample(direction: Vector3) -> Color:
	if _faces.is_empty():
		return Color(0.0, 0.0, 0.0, 0.0)
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
		face = 4 if direction.z > 0.0 else 5
		sc = direction.x / az if direction.z > 0.0 else -direction.x / az
		tc = -direction.y / az

	var i: int = clampi(int((sc + 1.0) * 0.5 * float(FACE_SIZE)), 0, FACE_SIZE - 1)
	var j: int = clampi(int((tc + 1.0) * 0.5 * float(FACE_SIZE)), 0, FACE_SIZE - 1)
	var image: Image = _faces[face]
	return image.get_pixel(i, j)


# --- arguments --------------------------------------------------------------

func _roll_of(text: String) -> Vector3:
	var parts: PackedStringArray = text.split(",")
	return Vector3(
		float(parts[0]) if parts.size() > 0 else 0.0,
		float(parts[1]) if parts.size() > 1 else 0.0,
		float(parts[2]) if parts.size() > 2 else 0.0
	)


func _argument(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--" + name and i + 1 < args.size():
			return args[i + 1]
	return fallback
