extends Node
## Development harness for the adaptive half of the resolution governor.
##
##     ./run.sh tools/governor_probe.tscn                 scripted load profiles
##     ./run.sh tools/governor_probe.tscn -- --live 1     a machine slow enough
##
## The governor has one part that can be wrong without any GPU being involved --
## the decision -- and one part that can be wrong in ways only real rendering shows
## -- the composition with the pixel cap and the upscaler. Both are measured here.
##
## The scripted run simulates a frame time rather than feeding a constant: a GPU is
## modelled as a cost per pixel, so lowering the ladder makes the frame faster the
## way it really does and the governor has to find a fixed point instead of walking
## to the floor. The same model applies the vsync quantisation, because that is the
## signal the governor actually reads: a 16.2 ms frame arrives as one refresh
## interval and a 17 ms frame arrives as two.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
## A full 1280 x 720 frame of this game on this machine, in milliseconds. Every
## simulated GPU is a multiple of it.
const BASELINE_MS: float = 7.8
const DISPLAY_HZ: float = 60.0

## Load profiles, one after another. Between them they cover everything the
## controller has to get right: leave a comfortable machine at full quality, ignore
## a single bad frame, come down on a machine that cannot keep up, and climb back
## once it can.
const PHASES: Array[Dictionary] = [
	{"name": "an M2", "times": 1.0, "seconds": 6},
	{"name": "an M2, one hitch in 20", "times": 1.0, "seconds": 6, "spike_every": 20},
	{"name": "4x slower", "times": 4.0, "seconds": 14},
	{"name": "2x slower", "times": 2.0, "seconds": 10},
	{"name": "an M2 again", "times": 1.0, "seconds": 22},
]

var _last_delta: float = 0.0


func _process(delta: float) -> void:
	_last_delta = delta


func _argument(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1):
		if args[i] == "--" + name:
			return args[i + 1]
	return fallback


func _ready() -> void:
	var governor: Node = get_node("/root/RenderScale")
	governor.set("enabled", true)
	if _argument("live", "0") == "1":
		await _run_live(governor)
	else:
		_run_script(governor)
	get_tree().quit()


## The latency a frame of this duration is reported at: vsync rounds it up to a
## whole refresh interval, and never lets it read faster than one.
func _observed_ms(work_ms: float) -> float:
	var interval: float = 1000.0 / DISPLAY_HZ
	return interval * maxf(1.0, ceil(work_ms / interval))


## One line per simulated second, showing which rung of the ladder the governor sits
## on. The rung indexes `FACTORS`, so 0 is full quality and 4 is the floor.
func _run_script(governor: Node) -> void:
	var ladder: Array = governor.get("FACTORS")
	var window: Vector2i = get_window().size
	var widths: Array[String] = []
	for f in ladder:
		var w: int = governor.call("render_width_for", window, f)
		widths.append("%d x %d" % [w, int(float(w) * float(window.y) / float(window.x))])
	print("scripted profiles, window %d x %d, vsync %.0f Hz" % [
		window.x, window.y, DISPLAY_HZ,
	])
	print("ladder  %s" % str(ladder))
	print("renders %s" % " | ".join(widths))
	print()
	print("%-24s %s" % ["phase", "rung, one digit per simulated second"])
	for phase in PHASES:
		var times: float = phase["times"]
		var seconds: int = phase["seconds"]
		var spike_every: int = int(phase.get("spike_every", 0))
		var trace: String = ""
		var frame_index: int = 0
		for _second in seconds:
			var elapsed: float = 0.0
			while elapsed < 1000.0:
				var rung: int = int(governor.get("_factor"))
				var width: int = governor.call("render_width_for", window, ladder[rung])
				var area: float = float(width * int(float(width) * float(window.y) / float(window.x)))
				var base_area: float = float(window.x * window.y)
				var work: float = BASELINE_MS * times * (area / base_area)
				if spike_every > 0 and frame_index % spike_every == spike_every - 1:
					work *= 4.0
				frame_index += 1
				var observed: float = _observed_ms(work)
				governor.call("feed", observed)
				elapsed += observed
			trace += " %d" % int(governor.get("_factor"))
		print("%-24s %s" % [phase["name"], trace])
	print()


## The real thing: no pixel cap, a window big enough that the frame genuinely takes
## tens of milliseconds, and the governor left alone to react to it.
func _run_live(governor: Node) -> void:
	var parts: PackedStringArray = _argument("window", "3200x1560").split("x")
	DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
	governor.set("max_render_width", 100000)
	governor.call("apply")

	var arena: Node = load(ARENA_SCENE).instantiate()
	add_child(arena)
	for i in 90:
		await get_tree().process_frame

	print("live run, window %d x %d, cap %d, scale %.3f, buffer %d x %d" % [
		get_window().size.x, get_window().size.y, governor.get("max_render_width"),
		get_window().scaling_3d_scale,
		int(float(get_window().size.x) * get_window().scaling_3d_scale),
		int(float(get_window().size.y) * get_window().scaling_3d_scale),
	])
	print("display %.0f Hz, governor reference %.2f ms" % [
		DisplayServer.screen_get_refresh_rate(), governor.call("_reference_ms"),
	])
	print("%5s %-6s %-16s %-11s %s" % ["t", "rung", "render", "delta p50", "fps"])
	for second in 16:
		var deltas: Array[float] = []
		for i in 60:
			await get_tree().process_frame
			deltas.append(_last_delta * 1000.0)
		deltas.sort()
		var width: int = governor.call(
			"render_width_for", get_window().size,
			governor.call("current_factor"), governor.get("max_render_width")
		)
		print("%5d %-6d %-16s %-11.2f %.1f" % [
			second,
			int(governor.get("_factor")),
			"%d x %d" % [
				width,
				int(float(width) * get_window().size.y / get_window().size.x),
			],
			deltas[30],
			Engine.get_frames_per_second(),
		])
		print("      scale %.3f" % get_window().scaling_3d_scale)
