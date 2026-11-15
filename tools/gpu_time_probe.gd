extends Node
## Development helper: does the engine report a GPU frame time worth steering by?
##
##     ./run.sh tools/gpu_time_probe.tscn
##
## An adaptive resolution governor has to know whether it has headroom, and the
## frame delta cannot answer that: with vsync on, a frame that could run at 200 fps
## and a frame that only just makes 60 both report 16.67 ms. The engine can measure
## the GPU time itself through `RenderingServer.viewport_get_measured_render_time_gpu`,
## but that is a driver timestamp query, and whether it works is a per-platform
## question. This prints delta and GPU time side by side across a ladder of render
## scales: if the GPU column falls as the scale falls while the delta column stays
## pinned at the refresh interval, the signal is real and usable.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
const SCALES: Array[float] = [1.0, 0.8, 0.65, 0.5]
## Frames thrown away after a scale change: the first ones after an upscaler switch
## include the pipeline rebuild, which is not the steady state we are measuring.
const WARMUP: int = 45
const SAMPLES: int = 90

var _delta: float = 0.0


func _process(delta: float) -> void:
	_delta = delta


func _ready() -> void:
	print("vsync         %d   max_fps %d" % [
		DisplayServer.window_get_vsync_mode(), Engine.max_fps,
	])

	var arena: Node = load(ARENA_SCENE).instantiate()
	add_child(arena)
	await get_tree().process_frame

	var viewport: Viewport = get_viewport()
	var rid: RID = viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)

	# The arena builds a cubemap and compiles the terrain shader in its first
	# frames, which is not representative of anything.
	for i in 120:
		await get_tree().process_frame

	print("%-8s %-12s %-10s %-10s %-14s %s" % [
		"scale", "render", "delta p50", "gpu p50", "gpu p95", "cpu p50",
	])
	for scale in SCALES:
		viewport.scaling_3d_scale = scale
		for i in WARMUP:
			await get_tree().process_frame

		var deltas: Array[float] = []
		var gpus: Array[float] = []
		var cpus: Array[float] = []
		for i in SAMPLES:
			await get_tree().process_frame
			deltas.append(_delta * 1000.0)
			gpus.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			cpus.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		deltas.sort()
		gpus.sort()
		cpus.sort()

		var size: Vector2 = viewport.get_visible_rect().size * scale
		print("%-8.2f %-12s %-10.2f %-10.2f %-14.2f %.2f" % [
			scale,
			"%d x %d" % [int(size.x), int(size.y)],
			deltas[SAMPLES / 2],
			gpus[SAMPLES / 2],
			gpus[int(float(SAMPLES) * 0.95)],
			cpus[SAMPLES / 2],
		])

	get_tree().quit()
