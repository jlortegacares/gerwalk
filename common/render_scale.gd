extends Node
## Keeps the 3D render target inside a pixel budget and a frame budget, and leaves
## the 2D canvas alone.
##
## Two limits, in that order:
##
## * A **pixel cap**. `canvas_items` stretch hands the 3D viewport whatever window the
##   OS gives it, so the same scene costs four times as much on a Retina display as
##   it does at 1280 x 720. The cap stops the game paying for pixels the eye cannot
##   resolve at flight altitude.
## * A **frame budget**. The cap is a constant but the hardware is not: the same
##   1280 x 720 window that costs 7.8 ms on this machine costs about 31 ms on a GPU
##   four times slower, and the cap does nothing there because the window is already
##   under it. When frames start missing, this walks the render width down a quality
##   ladder until they stop.
##
## The two compose: a 4K window is capped first and then stepped down, so a weak GPU
## on a big screen converges instead of dying.
##
## ## Why this does not steer by GPU time
##
## The obvious signal would be the GPU frame time, and the engine can report it --
## `RenderingServer.viewport_get_measured_render_time_gpu`. On Metal it reports 0.00
## at every render scale (`tools/gpu_time_probe.tscn`), so it is not a signal here.
## What is left is the frame delta, which vsync pins at the refresh interval: it
## cannot tell a GPU with three times the headroom from one that just scrapes by,
## because both report 16.67 ms.
##
## It can tell one thing, and that is the thing worth acting on: a *missed*
## refresh. A frame that needs 17 ms does not run at 17 ms under vsync, it runs at
## 33.3 -- it shows up as one delta of double the interval. A GPU with headroom
## never produces one. So this steps down on misses, and steps up only after a long
## run with none, accepting that "no misses" is evidence of headroom rather than a
## measurement of it.

## Render width the 3D pass is allowed to reach at full quality. Past this the
## terrain stops gaining detail the eye can resolve at flight altitude and starts
## costing frames for nothing.
const MAX_RENDER_WIDTH: int = 1600
## Never below this many pixels across, whatever the ladder says. 640 wide is the
## half of a 720p window, which the terrain survives; below it the fine grain and the
## city blocks dissolve into the water.
const MIN_RENDER_WIDTH: int = 640

## Quality steps, best first. Each multiplies the capped render width. The ladder is
## coarse on purpose: every step is a visible change, so a controller that could move
## by two percent would spend the whole game inching around.
const FACTORS: Array[float] = [1.0, 0.85, 0.72, 0.6, 0.5]

## Frames of history the decision reads, which at 60 fps is about a second and a
## half: long enough that one hitch is not a verdict, short enough that a player does
## not sit through seconds of stutter before the image softens.
const SAMPLE_COUNT: int = 90
## The history is also bounded by time, because a frame count is the wrong unit
## exactly where it matters: on the machine this exists for, 90 frames of 60 ms is
## five seconds, and the ladder would take half a minute to come down. A decision
## needs a second of wall clock, however many frames that is.
const WINDOW_MS: float = 1000.0
## And never fewer frames than this, or a miss ratio is one sample pretending to be
## a statistic.
const MIN_SAMPLES: int = 12
## A frame slower than this multiple of the refresh interval counts as a missed
## refresh. Just over 1.0 because a frame that exactly makes it still reports a hair
## over the nominal interval -- but not much over, because this is the whole
## definition of "smooth" the governor has: at 1.35 it accepts 17.8 ms frames, which
## are 56 fps on a 60 Hz display and visible as a stutter every few seconds.
const MISS_INTERVAL: float = 1.06
## Share of the history that may be misses before stepping down. There is no
## average-frame-time test beside it on purpose: under vsync every slow frame arrives
## as a miss, and an average over a window that contains one 33 ms frame reads 17.5
## ms for a machine that is fine. Ratio only.
const MISS_RATIO_LIMIT: float = 0.08

## Seconds of frames discarded after a step up. The frame that switches upscaler is
## not a frame of the new resolution, and the history that describes the old one is
## gone; this covers the rebuild before sampling starts again.
const UP_BLIND: float = 1.0
## The same after stepping down, which costs the player less to get wrong.
const DOWN_BLIND: float = 0.5
## Seconds of clean frames before trying one step better.
const UP_STEADY: float = 2.5
## A step-up undone within this window was a step too far, and that quality level is
## remembered as unsafe. Long enough to cover the blind period plus a full history.
const REVERT_WINDOW: float = 5.0
## How long a rung that failed is kept off the ladder, doubling each time it fails
## again. The cost of the scene changes as the ship leaves a cloud bank, so a failed
## rung is worth retrying eventually -- but not often enough to flicker.
const LOCKOUT_MIN: float = 20.0
const LOCKOUT_MAX: float = 600.0

## Whether this node owns `scaling_3d_scale` at all. A tool that takes the scale over
## sets this false and drives the viewport itself.
var enabled: bool = true
## Whether the adaptive half may move the ladder. A tool that wants the capped scale
## pinned -- the perf probe's rows, a capture -- leaves `enabled` true and sets this
## false, so a window change still re-applies the pinned rung but no measurement is
## disturbed mid-row.
var steering: bool = true
## The pixel cap, as a variable only so a tool can raise it and reproduce a machine
## slow enough to need the ladder. Production never writes it.
var max_render_width: int = MAX_RENDER_WIDTH

## Position on `FACTORS`. 0 is full quality; larger is softer.
var _factor: int = 0
## Lowest rung the governor has proven unsafe, and how long it stays off the ladder.
var _safe_floor: int = 0
var _lockout: float = 0.0
## How long the next lockout will be. Doubles with each revert and is only cleared
## when a climb holds, so it survives the lockout expiring.
var _backoff: float = 0.0
var _blind: float = 0.0
var _steady: float = 0.0
## Seconds left in which a step-down after a step-up counts as a revert.
var _revert_guard: float = 0.0

var _samples: PackedFloat32Array = PackedFloat32Array()
var _cursor: int = 0
var _filled: int = 0
var _sum: float = 0.0
var _slow: int = 0


func _ready() -> void:
	# A resize has to land even while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# No frame pacing to steer without a display; the smoke test runs headless.
	if DisplayServer.get_name() == "headless":
		enabled = false
	# FSR over bilinear: this is a low-frequency, organic surface, which is the case
	# a spatial upscaler handles well, and it keeps its edges where bilinear would
	# soften them further. FSR2 would be sharper still but it is temporal, and a
	# planet that rolls under a fast ship is exactly what makes temporal upscalers
	# ghost.
	get_window().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	get_window().size_changed.connect(_on_window_resized)
	_samples.resize(SAMPLE_COUNT)
	_samples.fill(0.0)
	apply()


func _process(delta: float) -> void:
	if not enabled or not steering or get_tree().paused:
		return
	feed(delta * 1000.0)


## Advances the governor by one frame of this duration, in milliseconds.
##
## Public because the decision is the part worth testing and it does not need a
## real GPU to be wrong: `tools/governor_probe.tscn` drives it through scripted load
## profiles, and the smoke suite drives it through a slow machine it does not have.
func feed(frame_ms: float) -> void:
	if not steering or frame_ms <= 0.0 or _samples.is_empty():
		return

	var seconds: float = frame_ms / 1000.0
	_lockout = maxf(_lockout - seconds, 0.0)
	if _lockout == 0.0:
		_safe_floor = 0
	if _revert_guard > 0.0:
		_revert_guard = maxf(_revert_guard - seconds, 0.0)
		# Surviving the guard without falling back means the climb was real, so
		# everything that was ruled out before it is worth trying again.
		if _revert_guard == 0.0:
			_safe_floor = 0
			_backoff = 0.0
			_lockout = 0.0
	if _blind > 0.0:
		_blind = maxf(_blind - seconds, 0.0)
		return

	var old: float = _samples[_cursor]
	_sum += frame_ms - old
	if _is_miss(old):
		_slow -= 1
	_samples[_cursor] = frame_ms
	if _is_miss(frame_ms):
		_slow += 1
	_cursor = (_cursor + 1) % SAMPLE_COUNT
	_filled = mini(_filled + 1, SAMPLE_COUNT)

	if _filled < MIN_SAMPLES:
		return
	# Enough to judge: either the ring cycled, or a second of frames went by.
	if _filled < SAMPLE_COUNT and _sum < WINDOW_MS:
		return

	# Both ratios divide by the samples actually collected. Dividing by the ring size
	# would read a half-filled history as twice as fast as it is.
	var miss_ratio: float = float(_slow) / float(_filled)
	if miss_ratio > MISS_RATIO_LIMIT:
		_step_down()
		return
	if miss_ratio == 0.0:
		_steady += seconds
		if _steady >= UP_STEADY:
			_step_up()
		return
	# Partly clean: not proof of headroom, but no longer a reason to fall further.
	_steady = 0.0


## Recomputes the render width and hands it to the viewport.
##
## Deliberately not gated on `enabled`: the measurement tools switch the steering
## off and then call this to pin the capped scale for a row.
func apply() -> void:
	var window: Window = get_window()
	if window == null or window.size.x <= 0:
		return
	var width: int = render_width_for(window.size, FACTORS[_factor], max_render_width)
	window.scaling_3d_scale = clampf(float(width) / float(window.size.x), 0.0, 1.0)


## Where the governor currently sits, for the tools and the docs.
func current_factor() -> float:
	return FACTORS[_factor]


## The render width a window of this size gets at a given ladder step.
##
## Static and free of engine state on purpose: this arithmetic is the part worth
## testing, and the suite runs headless where there is no window to ask.
static func render_width_for(
	size: Vector2i,
	factor: float = 1.0,
	cap: int = MAX_RENDER_WIDTH
) -> int:
	if size.x <= 0 or cap <= 0:
		return 0
	var capped: int = mini(size.x, cap)
	# A window narrower than the floor renders at its own size: this scales down,
	# it never upscales.
	if capped <= MIN_RENDER_WIDTH:
		return capped
	return clampi(int(round(float(capped) * factor)), MIN_RENDER_WIDTH, capped)


## The 3D scale for a window of this size at a given ladder step.
static func scale_for(
	size: Vector2i,
	factor: float = 1.0,
	cap: int = MAX_RENDER_WIDTH
) -> float:
	if size.x <= 0:
		return 1.0
	return float(render_width_for(size, factor, cap)) / float(size.x)


## The interval a frame has to fit in, in milliseconds. Never tighter than 60 fps:
## a 120 Hz display is allowed to present a 60 fps frame twice rather than make the
## game soften itself chasing a rate it was not asked for.
func _reference_ms() -> float:
	var refresh: float = DisplayServer.screen_get_refresh_rate()
	if refresh <= 0.0:
		refresh = 60.0
	return 1000.0 / minf(refresh, 60.0)


func _is_miss(frame_ms: float) -> bool:
	return frame_ms > _reference_ms() * MISS_INTERVAL


func _step_down() -> void:
	_steady = 0.0
	var reverted: bool = _revert_guard > 0.0
	_revert_guard = 0.0
	if _factor < FACTORS.size() - 1:
		_factor += 1
		_flush(DOWN_BLIND)
	if reverted:
		# The rung just left could not hold its frames, so it comes off the ladder --
		# and each repeat failure keeps it off for longer, so a marginal machine does
		# not flicker between two rungs for the whole session.
		_safe_floor = maxi(_safe_floor, _factor)
		_backoff = clampf(maxf(_backoff, LOCKOUT_MIN * 0.5) * 2.0, LOCKOUT_MIN, LOCKOUT_MAX)
		_lockout = _backoff


func _step_up() -> void:
	_steady = 0.0
	if _factor <= _safe_floor:
		return
	_factor -= 1
	_revert_guard = REVERT_WINDOW
	_flush(UP_BLIND)


## Drops the history and the frames that follow it. Every sample in the ring
## describes the resolution this call is about to change, so keeping any of it would
## make the next verdict a second step forced by evidence that no longer applies.
func _flush(blind_seconds: float) -> void:
	_samples.fill(0.0)
	_cursor = 0
	_filled = 0
	_sum = 0.0
	_slow = 0
	_blind = blind_seconds
	apply()


func _on_window_resized() -> void:
	# The pixel count changed, so the history describes a window that no longer
	# exists. The ladder position still means something relative to the new cap.
	_samples.fill(0.0)
	_cursor = 0
	_filled = 0
	_sum = 0.0
	_slow = 0
	_blind = 0.0
	_steady = 0.0
	_safe_floor = 0
	_lockout = 0.0
	_backoff = 0.0
	# A tool that has taken the scale over must keep it: the window ladder in the
	# perf probe resizes on purpose and would otherwise be measured at the cap.
	if enabled:
		apply()
