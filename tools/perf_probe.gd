extends Node
## Development helper: measures where a gameplay frame's time goes.
##
##     ./run.sh tools/perf_probe.tscn
##
## Booting the arena and timing it is the only honest way to answer "what is
## expensive", and every number below is attributable: each row removes one thing
## the arena draws and re-times the same parked ship over the same patch of planet.
##
## A 1280 x 720 frame on this machine is completely hidden by the display's
## refresh rate: every configuration reports the same 16.7 ms even with vsync
## asked off, because macOS still paces the loop to the screen. So the measurement
## runs twice: once at the shipping resolution as a control, and once at 2560 x
## 1440, where the frame falls below the refresh rate and the numbers become real.
## The two-resolutions ratio is also the direct evidence for "is this fragment
## bound", which is the question the whole optimisation turns on.
##
## Rows:
##   baseline          the scene as shipped
##   no clouds         the cloud deck hidden
##   no sun shadow     the directional light's shadow map off
##   no stars          the star shell hidden
##   half resolution   viewport.scaling_3d_scale = 0.5
##   all cheap         every row above applied together
##
## There used to be a `flat detail` row that rewrote the surface shader with the
## relief synthesis stubbed to a constant. It measured what baking that layer could
## be worth -- 61.7 ms against 76.5 ms at 5120 x 2880 -- and once the layer was
## baked there was nothing left for it to stub.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"

const WARMUP_FRAMES: int = 30
const SAMPLE_FRAMES: int = 60

## The shipping window size, and the size at which the frame stops being hidden by
## the refresh rate. Four times the pixels.
const BASE_SIZE: Vector2i = Vector2i(1280, 720)
const HEAVY_SIZE: Vector2i = Vector2i(2560, 1440)
## 3D render scales the shader ladder is timed at, relative to the shipping
## window. Supersampling instead of a bigger window keeps the window on screen:
## macOS throttles an occluded window to a crawl, and a 4K window on a 1080p
## display lands exactly there. All three are past the refresh-rate ceiling on
## purpose -- a frame that fits in 16.7 ms measures the display, not the shader.
const LADDER_SCALES: Array[float] = [1.0, 1.4, 2.0]
## Window sizes timed at 3D scale 1.0, to find which reported size the frame time
## actually tracks.
const WINDOW_LADDER: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3200, 1800),
]

var _arena: Node
var _viewport: Viewport
var _clouds: Node3D
var _stars: Node3D
var _sun: DirectionalLight3D
var _surface: ShaderMaterial

var _frames: int = 0
var _samples: PackedFloat32Array = PackedFloat32Array()
var _rows: Array[String] = []

var _configs: Array[Dictionary] = []
var _config_index: int = 0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_arena = load(ARENA_SCENE).instantiate()
	add_child(_arena)
	_viewport = get_viewport()

	_clouds = _arena.get_node_or_null("Clouds") as Node3D
	_stars = _find_star_shell()
	_sun = _find_sun()
	_surface = _find_surface()

	_print_machine()
	_measure_cloud_rebuild()
	_build_configs()
	if _configs.is_empty():
		get_tree().quit()
		return
	_apply(_configs[0])


## The cloud deck rebuilds itself whenever the ship crosses an 18-unit cell. That
## happens on a physics frame in the middle of play, so it does not show up in a
## frame average at all -- it shows up as a stutter every half second. Timed in
## isolation here, which is the only place it can be measured without flying.
func _measure_cloud_rebuild() -> void:
	var clouds: Node = _arena.get_node_or_null("Clouds")
	if clouds == null:
		print("cloud rebuild   no Clouds node")
		return
	var samples: PackedFloat32Array = PackedFloat32Array()
	for i in 12:
		var start: int = Time.get_ticks_usec()
		clouds.call("_rebuild")
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	# The first call is the cold one; the rest are what a cell crossing costs.
	samples.sort()
	print("cloud rebuild   first %.2f ms   warm %.2f ms   worst %.2f ms   %d puffs" % [
		samples[0], samples[int(float(samples.size()) * 0.5)], samples[samples.size() - 1],
		int(clouds.call("visible_puff_count")),
	])
	_measure_dense_cloud_rebuild(clouds)


## The ship starts inside the opening clearing, where the deck is nearly empty, so
## the first measurement is the cheapest rebuild there is. This one walks the ship
## to the densest bank it can find and times the same rebuild there, which is the
## number that matters: a rebuild in the middle of a fight happens in a bank.
func _measure_dense_cloud_rebuild(clouds: Node) -> void:
	var player: Node3D = _arena.get_node_or_null("Player") as Node3D
	if player == null:
		return
	var best: Vector3 = Vector3.ZERO
	var best_density: float = -1.0
	for iz in range(0, 40):
		for ix in range(0, 40):
			var point: Vector3 = Vector3(400.0 + float(ix) * 18.0, 0.0, 400.0 + float(iz) * 18.0)
			var density: float = clouds.call("density_at", point)
			if density > best_density:
				best_density = density
				best = point
	if best_density <= 0.0:
		return
	player.global_position = Vector3(best.x, 0.0, best.z)
	clouds.call("setup", player)

	var samples: PackedFloat32Array = PackedFloat32Array()
	for i in 12:
		var start: int = Time.get_ticks_usec()
		clouds.call("_rebuild")
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("cloud dense     first %.2f ms   warm %.2f ms   worst %.2f ms   %d puffs   density %.2f" % [
		samples[0], samples[int(float(samples.size()) * 0.5)], samples[samples.size() - 1],
		int(clouds.call("visible_puff_count")), best_density,
	])


func _print_machine() -> void:
	print("--- perf probe ---")
	print("engine        %s" % Engine.get_version_info().string)
	print("renderer      %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("adapter       %s (%s)" % [
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
	])
	print("cpu           %s" % OS.get_processor_name())
	print("os            %s %s" % [OS.get_name(), OS.get_version()])
	print("screen scale  %.2f" % DisplayServer.screen_get_scale())
	print("allow_hidpi   %s" % str(ProjectSettings.get_setting("display/window/dpi/allow_hidpi")))
	print("vsync mode    %d (0 disabled), max_fps 0" % DisplayServer.window_get_vsync_mode())
	print("surface       %s" % ("found" if _surface != null else "missing"))
	print("---")


func _build_configs() -> void:
	# Feature toggles, all at the same heavy resolution, so each row's delta is
	# the cost of exactly one thing.
	_configs.append(_config("baseline 1x", BASE_SIZE))
	_configs.append(_config("baseline 2x", HEAVY_SIZE))
	_configs.append(_config("no clouds 2x", HEAVY_SIZE, func() -> void:
		if _clouds != null:
			_clouds.visible = false))
	_configs.append(_config("no sun shadow 2x", HEAVY_SIZE, func() -> void:
		if _sun != null:
			_sun.shadow_enabled = false))
	_configs.append(_config("cheap shadow 2x", HEAVY_SIZE, func() -> void:
		if _sun != null:
			# The scene's only shadow casters are the ship and a handful of small
			# enemies, and the planet receives them over its whole visible face.
			# Two splits, a nearer far plane and a smaller blur keep the contact
			# shadow and drop the cascade work.
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_sun.directional_shadow_max_distance = 60.0
			_sun.shadow_blur = 1.0
			_sun.light_angular_distance = 1.0))
	_configs.append(_config("half res 2x", HEAVY_SIZE, func() -> void:
		_viewport.scaling_3d_scale = 0.5))

	_filter_rows()

	# The shader slope. Two points far apart on the pixel axis, both past the
	# refresh-rate ceiling, so the fitted cost per megapixel is not inferred from a
	# row that only measured the display.
	# Window-size ladder at 3D scale 1.0. The engine reports several different
	# "sizes" for the same window, and they disagree once a Retina display is
	# involved; whichever of them the frame time tracks is the one a resolution
	# governor has to divide by.
	for size in WINDOW_LADDER:
		_configs.append(_config("window %dx%d" % [size.x, size.y], size))
	# The resolution governor as shipped. The window is the variable here; the
	# render target is what the frame actually pays for, and it is reported in the
	# size column.
	_configs.append(_config("governed 2x", HEAVY_SIZE, _governor(true)))
	_configs.append(_config("governed 4k", Vector2i(3840, 2160), _governor(true)))

	_configs.append(_config("full shader 4x", BASE_SIZE, _scale(2.0)))
	_configs.append(_config("full shader 4k", HEAVY_SIZE, _scale(2.0)))


## `PERF_ROWS` narrows the run to the rows whose name contains the string. A full
## sweep recompiles the surface shader several times and takes minutes; a single
## setting is checked in seconds with the rest filtered out.
func _filter_rows() -> void:
	var only: String = OS.get_environment("PERF_ROWS")
	if only == "":
		return
	var kept: Array[Dictionary] = []
	for config in _configs:
		if str(config["name"]).contains(only):
			kept.append(config)
	_configs = kept


## Hands the 3D scale to the render-scale autoload for this row, pinned to the top
## rung: these rows measure the pixel cap, and the adaptive half would step down
## mid-row on any machine slow enough to be interesting.
func _governor(on: bool) -> Callable:
	return func() -> void:
		var node: Node = get_node_or_null("/root/RenderScale")
		if node == null:
			return
		# `enabled` stays true so the resize handler re-applies the pinned rung once
		# the OS has actually resized the window; `steering` is what stops the ladder
		# from moving mid-row.
		node.set("steering", false)
		node.set("_factor", 0)
		node.set("enabled", on)
		if on:
			node.call("apply")
		else:
			_viewport.scaling_3d_scale = 1.0


func _scale(scale: float) -> Callable:
	return func() -> void: _viewport.scaling_3d_scale = scale


## Runs two apply steps, because the ladder rows change the scale and the shader
## at once.
func _both(first: Callable, second: Callable) -> Callable:
	return func() -> void:
		first.call()
		second.call()


func _config(label: String, size: Vector2i, apply: Callable = Callable()) -> Dictionary:
	return {"name": label, "size": size, "apply": apply}


func _apply(config: Dictionary) -> void:
	# Each row starts from the shipping state, so a row never inherits the previous
	# row's deletions.
	if _clouds != null:
		_clouds.visible = true
	if _sun != null:
		_sun.shadow_enabled = true
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_sun.directional_shadow_max_distance = 100.0
		_sun.shadow_blur = 2.0
		_sun.light_angular_distance = 1.8
	if _stars != null:
		_stars.visible = true
	var governor: Node = get_node_or_null("/root/RenderScale")
	if governor != null:
		governor.set("enabled", false)
	_viewport.scaling_3d_scale = 1.0

	DisplayServer.window_set_size(config["size"])
	var apply: Callable = config["apply"]
	if apply.is_valid():
		apply.call()

	_samples.clear()
	_frames = 0
	print("measuring %s ..." % config["name"])
	print("  viewport %d x %d" % [
		_viewport.get_visible_rect().size.x, _viewport.get_visible_rect().size.y,
	])


func _process(delta: float) -> void:
	if _configs.is_empty():
		return
	_frames += 1
	if _frames <= WARMUP_FRAMES:
		return

	_samples.append(delta)

	if _samples.size() < SAMPLE_FRAMES:
		return

	_report(_configs[_config_index]["name"])
	_config_index += 1
	if _config_index >= _configs.size():
		_finish()
		return
	_apply(_configs[_config_index])


func _report(label: String) -> void:
	var ms: PackedFloat32Array = PackedFloat32Array()
	for value in _samples:
		ms.append(value * 1000.0)
	ms.sort()
	var mean: float = 0.0
	for value in ms:
		mean += value
	mean /= maxf(float(ms.size()), 1.0)
	var p50: float = ms[int(float(ms.size()) * 0.50)]
	var p95: float = ms[int(float(ms.size()) * 0.95)]
	var worst: float = ms[ms.size() - 1]
	# The window, not the viewport rect: with canvas_items stretch the 2D canvas
	# stays at 1280 x 720 while the 3D buffer follows the window, so the viewport
	# rect is exactly the number that would lie here.
	# Window size times the 3D scale: the stretch mode keeps the 2D canvas at
	# 1280 x 720 while the 3D buffer follows the window, so the visible rect is the
	# number that would lie here.
	var view: Vector2i = Vector2i(
		Vector2(DisplayServer.window_get_size()) * _viewport.scaling_3d_scale
	)
	var megapixels: float = float(view.x * view.y) / 1_000_000.0
	# Normalised cost, so a row measured behind the refresh-rate ceiling still says
	# something: it is a lower bound, not a number to compare against the others.
	_rows.append(
		"%-16s %7.2f ms  %6.1f fps  p50 %6.2f  p95 %6.2f  max %6.2f  %4d x %-4d  %5.2f ms/Mpx"
		% [label, mean, 1000.0 / mean, p50, p95, worst, view.x, view.y, mean / megapixels]
	)


func _finish() -> void:
	print("---")
	for row in _rows:
		print(row)
	print("---")
	get_tree().quit()


func _find_star_shell() -> Node3D:
	var player: Node3D = _arena.get_node_or_null("Player") as Node3D
	if player == null:
		return null
	for child in player.get_children():
		var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if instance != null:
			return instance
	return null


func _find_sun() -> DirectionalLight3D:
	for child in _arena.get_children():
		var light: DirectionalLight3D = child as DirectionalLight3D
		if light != null:
			return light
	return null


## The surface material lives on the planet's ground mesh, not on the arena root.
func _find_surface() -> ShaderMaterial:
	var planet: Node3D = _arena.get_node_or_null("Planet") as Node3D
	if planet == null:
		return null
	for child in planet.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null:
			continue
		var material: ShaderMaterial = mesh.material_override as ShaderMaterial
		if material == null:
			continue
		return material
	return null
