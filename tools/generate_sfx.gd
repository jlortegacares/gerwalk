extends SceneTree
## Synthesizes every sound effect in `audio/sfx/`.
##
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##       -s tools/generate_sfx.gd
##
## Macross-inspired, never Macross audio: nothing here is sampled or ripped. Each
## effect is a small stack of tones and filtered noise, so the palette lives in code
## next to the rest of the tuning and the repository ships no third-party audio.
## Re-running the script reproduces the committed WAVs byte for byte, because the
## noise source is a seeded generator instead of `randf()`. Each sound gets its own
## seed derived from its name, so editing one builder never rewrites the others.
##
## The palette is built in layers on purpose. A single noise burst reads as a clap; a
## crack over a body over a sub reads as a machine failing. The mixer in
## `common/sfx.gd` is the other half: this file decides the timbre, that file decides
## how loud each timbre sits against the rest.

## Shapes a tone can take. A gunpod burst and a lock tone want different edges.
const SHAPE_SINE: int = 0
const SHAPE_SAW: int = 1
const SHAPE_SQUARE: int = 2

## Noise filter modes. A one-pole filter has no resonance, so these are wide shapes:
## `LOW` is body and rumble, `HIGH` is air and crack.
const FILTER_LOW: int = 0
const FILTER_HIGH: int = 1

const RATE: int = 44100
const OUT_DIR: String = "res://audio/sfx"
## Peak every file is normalised to, in linear amplitude. Leaves the bus headroom for
## a salvo plus an explosion to sum without clipping. Peak is only headroom: the mix
## that makes these sounds sit together lives in `common/sfx.gd`, because two files
## that peak at 0.70 can still differ by 15 dB of loudness.
const PEAK: float = 0.7

var _seed: int = 0x2f6e2b1


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var written: Array[String] = []
	for entry in _catalogue():
		_seed = _seed_for(entry[0])
		written.append(_save(entry[0], entry[1].call(), entry[2]))
	print("generated %d sounds: %s" % [written.size(), ", ".join(PackedStringArray(written))])
	quit()


## Every effect, in one list: name, builder, loop. The builder is a Callable so the
## noise seed can be set per sound before it runs. Keeping the catalogue in one place
## is what makes "what sounds does the game have" a single readable answer.
func _catalogue() -> Array:
	return [
		["vulcan", _vulcan, false],
		["plasma", _plasma, false],
		["laser", _laser, false],
		["missile_launch", _missile_launch, false],
		["lock_tone", _lock_tone, false],
		["missile_warning", _missile_warning, false],
		["enemy_fire", _enemy_fire, false],
		["explosion", _explosion.bind(1.30, 1.0), false],
		["player_death", _explosion.bind(1.90, 0.72), false],
		["hit", _hit, false],
		["transform", _transform, false],
		["afterburner", _afterburner, false],
		["dash", _dash, false],
		["bomb", _bomb, false],
		["decoy", _decoy, false],
		["ui_select", _ui_select, false],
		["engine_loop", _engine_loop, true],
	]


# --- Weapons -------------------------------------------------------------------

## The gunpod: a hard, dry burst with real weight behind it. The crack is the shell
## leaving the barrel, the thump is the charge, and the inharmonic ring is the
## receiver answering. Three layers, because a single noise burst reads as a clap.
func _vulcan() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.15)
	# The crack: broadband, gone in a few dozen milliseconds.
	_noise(buf, 0.0, 0.06, 0.75, 9000.0, 55.0, 0.0005)
	# The charge: the body the crack sits on.
	_tone(buf, 0.0, 0.14, 190.0, 68.0, 0.62, SHAPE_SINE, 26.0, 0.001)
	_tone(buf, 0.0, 0.12, 96.0, 46.0, 0.40, SHAPE_SINE, 20.0, 0.001)
	# The receiver: metal ringing just under the shot.
	_ring(buf, 0.0, 0.09, 1450.0, 0.13, 46.0, [1.0, 1.47, 2.09])
	# The bolt: the action cycling after the round has gone.
	_noise(buf, 0.055, 0.05, 0.14, 4200.0, 70.0, 0.001)
	return buf


## The energy bolt: a capacitor dumping into the emitter. The pre-blip is the charge
## letting go, the descending saw is the bolt, and the sub is the punch under it.
func _plasma() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.30)
	_tone(buf, 0.0, 0.035, 2400.0, 2800.0, 0.14, SHAPE_SQUARE, 50.0, 0.001)
	_tone(buf, 0.0, 0.26, 1450.0, 240.0, 0.46, SHAPE_SAW, 9.0, 0.002, 34.0, 0.025)
	_tone(buf, 0.0, 0.22, 250.0, 82.0, 0.34, SHAPE_SINE, 11.0, 0.002)
	_noise(buf, 0.0, 0.20, 0.18, 1800.0, 18.0, 0.002, 700.0)
	return buf


## The beam: a sustained emission, not a shot. Two oscillators a few Hz apart beat
## against each other, which is what makes a held tone sound like a device running
## instead of a note being played.
func _laser() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.34)
	_tone(buf, 0.0, 0.32, 1750.0, 620.0, 0.26, SHAPE_SQUARE, 7.0, 0.004, 26.0, 0.03)
	_tone(buf, 0.0, 0.32, 1762.0, 628.0, 0.16, SHAPE_SQUARE, 7.0, 0.004, 26.0, 0.03)
	_tone(buf, 0.0, 0.30, 880.0, 310.0, 0.20, SHAPE_SAW, 6.0, 0.004)
	_noise(buf, 0.0, 0.22, 0.10, 5200.0, 22.0, 0.002, 2600.0, FILTER_HIGH)
	return buf


## The missile leaving the rail. This is the Macross sound: the clamp lets go, the
## motor lights, and the whoosh opens from bright to dark as the round pulls away.
func _missile_launch() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.95)
	# The rail clamp.
	_noise(buf, 0.0, 0.04, 0.35, 5200.0, 60.0, 0.0005)
	_tone(buf, 0.0, 0.10, 130.0, 62.0, 0.34, SHAPE_SINE, 28.0, 0.001)
	# The motor lighting.
	_tone(buf, 0.04, 0.16, 90.0, 48.0, 0.42, SHAPE_SINE, 14.0, 0.004)
	# The whoosh: a noise band sweeping down as the round gets away.
	_noise(buf, 0.01, 0.80, 0.52, 6000.0, 2.4, 0.020, 850.0)
	# The air it leaves behind, thin and high.
	_noise(buf, 0.10, 0.70, 0.16, 5200.0, 3.0, 0.060, 3200.0, FILTER_HIGH)
	# The rocket rumble, climbing out of the frame.
	_tone(buf, 0.05, 0.70, 300.0, 105.0, 0.26, SHAPE_SAW, 2.8, 0.030, 22.0, 0.05)
	return buf


## The lock: the targeting computer answering, in the voice of a 1990s console. The
## brief is VF-X2's lock beep, not its audio: two fast high pips and a held answer,
## hard-edged and dry, with the sample-and-hold grit of the era's sound chip. No
## reverb, no long tail — a lock has to cut through the gun without becoming a sting.
## Every lock plays this same tone: the caller does not climb it, because the number
## of stings already says how many missiles were assigned.
func _lock_tone() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.30)
	# Two pips, each a little higher than the last. They are short on purpose: a long
	# beep sits on top of the gunpod instead of cutting through it.
	for pip in 2:
		var at: float = float(pip) * 0.055
		var hz: float = 2050.0 + 280.0 * float(pip)
		_tone(buf, at, 0.040, hz, hz * 1.05, 0.36, SHAPE_SQUARE, 62.0, 0.0006)
		_tone(buf, at, 0.036, hz * 0.5, hz * 0.5, 0.13, SHAPE_SINE, 62.0, 0.0006)
		# The click of the sample starting, which is half of what makes the era's
		# sounds read as digital instead of merely bright.
		_noise(buf, at, 0.004, 0.12, 12000.0, 220.0, 0.0002)
	# The confirmation: a held tone with a detuned partner, so it settles on a
	# decision instead of being a third beep.
	_tone(buf, 0.135, 0.145, 2450.0, 2380.0, 0.28, SHAPE_SQUARE, 13.0, 0.001)
	_tone(buf, 0.135, 0.145, 2459.0, 2389.0, 0.15, SHAPE_SQUARE, 13.0, 0.001)
	_tone(buf, 0.135, 0.145, 1225.0, 1190.0, 0.11, SHAPE_SINE, 13.0, 0.001)
	# The console texture, applied last so the whole sting shares one grain: a low
	# hold rate for the era's shimmer and 8-bit steps for the grit under it.
	_crush(buf, 0.0, 0.30, 14000.0, 256.0)
	return buf


## The incoming-shot alarm: two tones trading, faster than a lock so it reads as
## urgency, with a low body that carries it over the engine.
func _missile_warning() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.80)
	for beep in 6:
		var start: float = 0.02 + float(beep) * 0.125
		var freq: float = 980.0 if beep % 2 == 0 else 660.0
		_tone(buf, start, 0.085, freq, freq, 0.24, SHAPE_SQUARE, 9.0, 0.003)
		_tone(buf, start, 0.085, freq * 0.5, freq * 0.5, 0.10, SHAPE_SINE, 9.0, 0.003)
	return buf


## Enemy fire: a duller, lower report than the gunpod, so a shot coming the other
## way is a different voice and not just a quieter one.
func _enemy_fire() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.20)
	_tone(buf, 0.0, 0.16, 340.0, 105.0, 0.48, SHAPE_SINE, 18.0, 0.001)
	_noise(buf, 0.0, 0.14, 0.24, 1900.0, 24.0, 0.001, 900.0)
	_tone(buf, 0.0, 0.12, 540.0, 430.0, 0.10, SHAPE_SQUARE, 34.0, 0.001)
	_ring(buf, 0.0, 0.08, 620.0, 0.05, 40.0, [1.0, 1.63])
	return buf


# --- Impacts -------------------------------------------------------------------

## A hull coming apart. Four layers, because one noise burst is a clap: the crack is
## the frame failing, the body is the fireball, the sub is the weight, and the
## crackle is the debris falling out of it.
##
## The bright band is the point, not decoration. A blast that lives under 300 Hz is
## silent on a laptop speaker, so the crack carries the hit and the sub only adds
## weight underneath it.
func _explosion(seconds: float, pitch: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(seconds)
	# The crack: bright, immediate, and short.
	_noise(
		buf, 0.0, minf(seconds * 0.35, 0.42), 0.95,
		7000.0 * pitch, 16.0, 0.001, 3600.0 * pitch, FILTER_HIGH
	)
	# The body: the fireball opening up.
	_noise(
		buf, 0.0, seconds * 0.70, 1.15,
		2400.0 * pitch, 3.2, 0.003, 900.0 * pitch
	)
	# The weight.
	_tone(buf, 0.0, seconds * 0.75, 120.0 * pitch, 32.0, 0.55, SHAPE_SINE, 2.6, 0.002)
	# The rumble that outlives the flash.
	_noise(buf, 0.0, seconds, 0.34, 520.0 * pitch, 1.9, 0.004, 180.0 * pitch)
	_crackle(buf, 0.03, seconds * 0.60, 12, 0.34)
	return buf


## A round into the hull: metal first, thump under it, ring after. Short enough to
## fire often without turning a bullet pattern into a drum solo.
func _hit() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.30)
	_noise(buf, 0.0, 0.10, 0.45, 4200.0, 30.0, 0.0005, 2000.0, FILTER_HIGH)
	_ring(buf, 0.0, 0.22, 820.0, 0.16, 22.0, [1.0, 1.63, 2.31, 3.17])
	_tone(buf, 0.0, 0.20, 135.0, 55.0, 0.52, SHAPE_SINE, 16.0, 0.001)
	return buf


# --- The ship ------------------------------------------------------------------

## The transformation: the VF's signature. The servos wind up, the hydraulics hiss,
## the frame grinds through the throw, and then two clunks seat it in the new pose.
## The two clunks are the point — a single one reads as a glitch, two read as a
## mechanism.
func _transform() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(1.10)
	# Servos winding up.
	_tone(buf, 0.0, 0.66, 170.0, 820.0, 0.22, SHAPE_SAW, 0.9, 0.05, 16.0, 0.02)
	# Hydraulics.
	_noise(buf, 0.02, 0.62, 0.16, 5600.0, 1.8, 0.04, 3200.0, FILTER_HIGH)
	# The frame grinding through the middle of the throw.
	_noise(buf, 0.18, 0.46, 0.12, 1400.0, 1.2, 0.02, 900.0)
	# The lock seating.
	_clunk(buf, 0.64, 0.62)
	_ring(buf, 0.64, 0.20, 640.0, 0.10, 18.0, [1.0, 1.51, 2.13])
	_clunk(buf, 0.84, 0.36)
	return buf


## The burner lighting: the charge, then a roar that opens up instead of decaying.
func _afterburner() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(1.00)
	_tone(buf, 0.0, 0.30, 105.0, 38.0, 0.60, SHAPE_SINE, 9.0, 0.001)
	_noise(buf, 0.02, 0.94, 0.46, 500.0, 1.8, 0.05, 2200.0)
	_tone(buf, 0.04, 0.88, 120.0, 340.0, 0.20, SHAPE_SAW, 1.8, 0.04, 2.0, 0.02)
	_noise(buf, 0.10, 0.70, 0.12, 4200.0, 2.2, 0.08, 6000.0, FILTER_HIGH)
	return buf


## The dash: air moving, nothing more. Short so it can fire on cooldown.
func _dash() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.38)
	_noise(buf, 0.0, 0.34, 0.42, 3400.0, 7.0, 0.008, 800.0)
	_tone(buf, 0.0, 0.32, 520.0, 150.0, 0.24, SHAPE_SINE, 8.0, 0.005)
	_noise(buf, 0.02, 0.24, 0.08, 7000.0, 5.0, 0.01, 4000.0, FILTER_HIGH)
	return buf


## The bomb: a charge winding up, then the largest thing in the palette. It has to
## sit above the ordinary blast, so it is the same four layers with a longer tail.
func _bomb() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(1.80)
	# The charge.
	_tone(buf, 0.0, 0.28, 260.0, 1100.0, 0.20, SHAPE_SQUARE, 0.6, 0.02, 30.0, 0.04)
	# The blast.
	_noise(buf, 0.28, 0.55, 1.00, 7500.0, 12.0, 0.001, 3800.0, FILTER_HIGH)
	_noise(buf, 0.28, 1.30, 1.20, 2400.0, 2.4, 0.003, 650.0)
	_tone(buf, 0.28, 1.30, 115.0, 26.0, 0.85, SHAPE_SINE, 1.8, 0.002)
	_noise(buf, 0.28, 1.52, 0.36, 480.0, 1.5, 0.004, 160.0)
	_crackle(buf, 0.32, 1.05, 14, 0.28)
	return buf


## The decoy: a pop and a burning flare. Bright, short, unmistakably not a weapon.
func _decoy() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.70)
	_noise(buf, 0.0, 0.035, 0.60, 9000.0, 45.0, 0.0005)
	_noise(buf, 0.02, 0.62, 0.24, 6200.0, 3.4, 0.010, 4200.0, FILTER_HIGH)
	_tone(buf, 0.0, 0.22, 1300.0, 920.0, 0.12, SHAPE_SINE, 16.0, 0.001)
	return buf


# --- Interface -----------------------------------------------------------------

## A menu blip: quiet, bright, and over before it can become annoying. Quiet is the
## mixer's job; this file only has to be short.
func _ui_select() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.09)
	_tone(buf, 0.0, 0.07, 1500.0, 1500.0, 0.16, SHAPE_SQUARE, 40.0, 0.002)
	_tone(buf, 0.0, 0.07, 750.0, 750.0, 0.10, SHAPE_SINE, 40.0, 0.002)
	return buf


## The hover engine: a turbine hum that loops forever. Every partial is an integer
## multiple of the loop length's reciprocal, and every vibrato is an integer too, so
## the loop point is silent by construction — no crossfade, no click.
func _engine_loop() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(1.0)
	_tone(buf, 0.0, 1.0, 90.0, 90.0, 0.26, SHAPE_SAW, 0.0, 0.0, 6.0, 0.02)
	_tone(buf, 0.0, 1.0, 91.0, 91.0, 0.18, SHAPE_SAW, 0.0, 0.0, 6.0, 0.02)
	_tone(buf, 0.0, 1.0, 180.0, 180.0, 0.16, SHAPE_SINE, 0.0, 0.0)
	_tone(buf, 0.0, 1.0, 270.0, 270.0, 0.11, SHAPE_SINE, 0.0, 0.0)
	_tone(buf, 0.0, 1.0, 360.0, 360.0, 0.08, SHAPE_SINE, 0.0, 0.0)
	_tone(buf, 0.0, 1.0, 540.0, 540.0, 0.06, SHAPE_SINE, 0.0, 0.0)
	_tone(buf, 0.0, 1.0, 1080.0, 1080.0, 0.06, SHAPE_SINE, 0.0, 0.0, 3.0, 0.10)
	_tone(buf, 0.0, 1.0, 1800.0, 1800.0, 0.035, SHAPE_SINE, 0.0, 0.0, 2.0, 0.08)
	_tone(buf, 0.0, 1.0, 2700.0, 2700.0, 0.02, SHAPE_SINE, 0.0, 0.0, 1.0, 0.05)
	return buf


# --- Primitives ----------------------------------------------------------------

func _buffer(seconds: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	buf.fill(0.0)
	return buf


## Adds one voice: a wave whose pitch glides `f0 -> f1` over `dur`, with an
## exponential decay and an optional vibrato. `decay` is in 1/s, so 0 is a sustain.
func _tone(
	buf: PackedFloat32Array,
	start: float,
	dur: float,
	f0: float,
	f1: float,
	amp: float,
	shape: int = SHAPE_SINE,
	decay: float = 12.0,
	attack: float = 0.004,
	vibrato_hz: float = 0.0,
	vibrato: float = 0.0
) -> void:
	var begin: int = int(start * RATE)
	var frames: int = int(dur * RATE)
	var phase: float = 0.0
	for i in frames:
		var index: int = begin + i
		if index < 0:
			continue
		if index >= buf.size():
			break
		var t: float = float(i) / RATE
		var freq: float = lerpf(f0, f1, t / dur)
		if vibrato_hz > 0.0:
			freq *= 1.0 + sin(TAU * vibrato_hz * t) * vibrato
		phase += TAU * freq / RATE
		buf[index] += _wave(shape, phase) * amp * _env(t, dur, attack, decay, 0.0)


## Adds filtered noise. `cutoff` is where the filter starts and `cutoff_end` where it
## ends, so a whoosh is a band moving through the spectrum instead of a fixed hiss.
## The gain is compensated per sample for the filter, so `amp` means the same
## loudness as the same `amp` on a tone instead of quietly vanishing as the cutoff
## drops — or exploding as a high-pass narrows.
func _noise(
	buf: PackedFloat32Array,
	start: float,
	dur: float,
	amp: float,
	cutoff: float,
	decay: float,
	attack: float = 0.004,
	cutoff_end: float = -1.0,
	mode: int = FILTER_LOW
) -> void:
	var begin: int = int(start * RATE)
	var frames: int = int(dur * RATE)
	var end: float = cutoff if cutoff_end < 0.0 else cutoff_end
	var low: float = 0.0
	for i in frames:
		var index: int = begin + i
		if index < 0:
			continue
		if index >= buf.size():
			break
		var t: float = float(i) / RATE
		var hz: float = lerpf(cutoff, end, t / dur)
		var coefficient: float = 1.0 - exp(-TAU * hz / float(RATE))
		var white: float = _rand()
		low += coefficient * (white - low)
		var sample: float = low
		var gain: float = sqrt((2.0 - coefficient) / coefficient)
		if mode == FILTER_HIGH:
			# The residual of the same noise the low-pass is tracking, not a second
			# draw: subtracting an independent noise source would double the variance
			# and call it a filter.
			sample = white - low
			# Variance of `white - low` for a one-pole low: the residual shrinks as
			# the cutoff climbs, so the high-pass needs the inverse of that.
			var residual: float = 1.0 - 2.0 * coefficient + coefficient / (2.0 - coefficient)
			gain = 1.0 / sqrt(maxf(residual, 0.02))
		buf[index] += sample * gain * amp * _env(t, dur, attack, decay, 0.0)


## A struck-metal ring: a stack of inharmonic partials over a short downward glide.
## Integer ratios would read as a musical note, and a hull does not ring in tune.
func _ring(
	buf: PackedFloat32Array,
	start: float,
	dur: float,
	base: float,
	amp: float,
	decay: float,
	ratios: Array = []
) -> void:
	if ratios.is_empty():
		ratios = [1.0, 1.47, 2.09]
	for index in ratios.size():
		var ratio: float = float(ratios[index])
		var weight: float = 1.0 / (1.0 + float(index) * 0.9)
		_tone(
			buf, start, dur, base * ratio, base * ratio * 0.97,
			amp * weight, SHAPE_SINE, decay * (1.0 + float(index) * 0.35), 0.001
		)


## Sample-and-hold plus quantisation: the grain of a 1990s console. The sound chip
## ran short samples at a low rate, so the aliasing and the stepped amplitude are
## part of the character, not a defect to filter out. `hold_hz` is the rate the
## buffer is resampled at and `levels` is how many steps the amplitude keeps.
func _crush(
	buf: PackedFloat32Array, start: float, dur: float, hold_hz: float, levels: float
) -> void:
	var begin: int = int(start * RATE)
	var frames: int = int(dur * RATE)
	var step: int = maxi(int(float(RATE) / maxf(hold_hz, 1.0)), 1)
	var held: float = 0.0
	for i in frames:
		var index: int = begin + i
		if index < 0:
			continue
		if index >= buf.size():
			break
		if i % step == 0:
			held = round(buf[index] * levels) / levels
		buf[index] = held


## A mechanical impact: a noise tick plus a low thud. The transformation is built
## out of these, and so is anything else that has to sound like metal meeting metal.
func _clunk(buf: PackedFloat32Array, start: float, amp: float) -> void:
	_noise(buf, start, 0.07, amp, 4600.0, 42.0, 0.0005)
	_tone(buf, start, 0.12, 115.0, 52.0, amp * 0.85, SHAPE_SINE, 26.0, 0.001)
	_tone(buf, start, 0.06, 660.0, 610.0, amp * 0.18, SHAPE_SQUARE, 55.0, 0.001)


## Scattered debris: `count` short noise ticks at deterministic offsets, so the tail
## of an explosion has texture without the file changing on every regeneration.
func _crackle(
	buf: PackedFloat32Array, start: float, span: float, count: int, amp: float
) -> void:
	for i in count:
		var at: float = start + span * float(i) / float(count)
		at += absf(_rand()) * span / float(count) * 0.6
		_noise(buf, at, 0.035, amp * (1.0 - float(i) / float(count + 1)), 5000.0, 60.0, 0.001)


func _wave(shape: int, phase: float) -> float:
	match shape:
		SHAPE_SAW:
			return fmod(phase, TAU) / PI - 1.0
		SHAPE_SQUARE:
			return 1.0 if fmod(phase, TAU) < PI else -1.0
		_:
			return sin(phase)


## Attack ramp, exponential decay, and an optional release over the last `fade`
## seconds. A sustain is `decay = 0`; the engine loop uses the attack ramp only.
func _env(t: float, dur: float, attack: float, decay: float, fade: float) -> float:
	# A zero attack is a sustain, not a 0.5 ms ramp: a looping buffer has to start at
	# full level or the loop point clicks every time it wraps.
	var level: float = 1.0 if attack <= 0.0 else clampf(t / attack, 0.0, 1.0)
	if decay > 0.0:
		level *= exp(-decay * t)
	if fade > 0.0:
		level *= clampf((dur - t) / fade, 0.0, 1.0)
	return level


## FNV-1a over the sound's name: a stable seed per effect, so a change to one
## builder never shifts the noise of the sounds listed after it.
func _seed_for(name: String) -> int:
	var hash: int = 0x811c9dc5
	for i in name.length():
		hash = ((hash ^ name.unicode_at(i)) * 0x01000193) & 0xffffffff
	return hash if hash != 0 else 0x2f6e2b1


func _rand() -> float:
	_seed ^= (_seed << 13) & 0x7fffffff
	_seed ^= _seed >> 17
	_seed ^= (_seed << 5) & 0x7fffffff
	return float(_seed & 0xffff) / 32768.0 - 1.0


## Normalises the buffer to PEAK, writes 16-bit PCM and returns the file name.
func _save(name: String, buf: PackedFloat32Array, loop: bool) -> String:
	var peak: float = 0.0
	for value in buf:
		peak = maxf(peak, absf(value))
	var scale: float = PEAK / maxf(peak, 0.0001)

	var data: PackedByteArray = PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		var sample: int = int(clampf(buf[i] * scale, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = buf.size()

	var path: String = "%s/%s.wav" % [OUT_DIR, name]
	var err: int = wav.save_to_wav(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("generate_sfx: could not write %s (error %d)" % [path, err])
	return name
