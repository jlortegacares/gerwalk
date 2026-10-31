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

## Shapes a tone can take. A gunpod burst and a lock tone want different edges.
const SHAPE_SINE: int = 0
const SHAPE_SAW: int = 1
const SHAPE_SQUARE: int = 2

const RATE: int = 44100
const OUT_DIR: String = "res://audio/sfx"
## Peak every file is normalised to, in linear amplitude. Leaves the bus headroom for
## a salvo plus an explosion to sum without clipping.
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
		["explosion", _explosion.bind(1.15, 1.0), false],
		["player_death", _explosion.bind(1.7, 0.75), false],
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

## The gunpod: a hard, dry burst. A crack of noise over a low thump, with a short
## metallic ring so it reads as a shell leaving a barrel instead of a drum hit.
func _vulcan() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.11)
	_noise(buf, 0.0, 0.11, 0.55, 7000.0, 34.0, 0.001)
	_tone(buf, 0.0, 0.10, 150.0, 70.0, 0.50, SHAPE_SINE, 28.0, 0.001)
	_tone(buf, 0.0, 0.09, 920.0, 780.0, 0.13, SHAPE_SQUARE, 46.0, 0.001)
	return buf


## The energy bolt: a short descending zap with a sub thump under it.
func _plasma() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.24)
	_tone(buf, 0.0, 0.22, 1100.0, 260.0, 0.42, SHAPE_SAW, 11.0, 0.003)
	_tone(buf, 0.0, 0.18, 220.0, 90.0, 0.30, SHAPE_SINE, 12.0, 0.002)
	_noise(buf, 0.0, 0.16, 0.18, 2600.0, 20.0, 0.002)
	return buf


## The beam: brighter and narrower than the bolt, with a wobble that reads as a
## sustained emission rather than a shot.
func _laser() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.30)
	_tone(buf, 0.0, 0.28, 1600.0, 520.0, 0.30, SHAPE_SQUARE, 8.0, 0.004, 22.0, 0.03)
	_tone(buf, 0.0, 0.26, 800.0, 260.0, 0.20, SHAPE_SAW, 7.0, 0.004)
	_noise(buf, 0.0, 0.20, 0.10, 4200.0, 24.0, 0.002)
	return buf


## The missile leaving the rail: the airy "shhhh" that opens a Macross salvo. A
## filtered noise body, a descending whoosh under it and a hiss that outlives both.
func _missile_launch() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.70)
	_noise(buf, 0.0, 0.55, 0.50, 1700.0, 5.0, 0.020)
	_tone(buf, 0.0, 0.50, 420.0, 90.0, 0.34, SHAPE_SAW, 3.4, 0.010)
	_tone(buf, 0.0, 0.45, 95.0, 45.0, 0.40, SHAPE_SINE, 4.0, 0.006)
	_noise(buf, 0.12, 0.55, 0.20, 3800.0, 3.0, 0.060)
	return buf


## The lock: two rising pips and a held tone, the anime "acquired" sting.
func _lock_tone() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.36)
	_tone(buf, 0.00, 0.06, 1200.0, 1200.0, 0.22, SHAPE_SQUARE, 20.0, 0.002)
	_tone(buf, 0.09, 0.06, 1600.0, 1600.0, 0.22, SHAPE_SQUARE, 20.0, 0.002)
	_tone(buf, 0.18, 0.16, 1900.0, 1900.0, 0.20, SHAPE_SQUARE, 6.0, 0.003, 0.0, 0.0)
	return buf


## The alarm for an incoming guided shot: two tones trading, which is the one sound
## the player must never mistake for their own weapons.
func _missile_warning() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.72)
	for beep in 5:
		var start: float = 0.02 + float(beep) * 0.14
		var freq: float = 880.0 if beep % 2 == 0 else 620.0
		_tone(buf, start, 0.09, freq, freq, 0.26, SHAPE_SQUARE, 8.0, 0.004)
	return buf


## Enemy fire: lower and duller than the player's gunpod, so a turret shot is
## audible as a different weapon coming the other way.
func _enemy_fire() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.16)
	_tone(buf, 0.0, 0.14, 320.0, 110.0, 0.45, SHAPE_SINE, 20.0, 0.002)
	_noise(buf, 0.0, 0.12, 0.26, 2000.0, 28.0, 0.002)
	_tone(buf, 0.0, 0.10, 520.0, 430.0, 0.10, SHAPE_SQUARE, 38.0, 0.002)
	return buf


# --- Impacts -------------------------------------------------------------------

## A hull coming apart: a bright crack over a mid body, a sub drop under it, and a
## scatter of crackles so the tail reads as debris instead of a reverb.
##
## The bright band is the point, not decoration. A blast that lives under 300 Hz is
## silent on a laptop speaker, so the crack carries the hit and the sub only adds
## weight underneath it.
func _explosion(seconds: float, pitch: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(seconds)
	_noise(buf, 0.0, minf(seconds * 0.5, 0.35), 0.95, 6500.0 * pitch, 20.0, 0.001)
	_noise(buf, 0.0, seconds * 0.70, 1.30, 2300.0 * pitch, 3.6, 0.003)
	_tone(buf, 0.0, seconds * 0.7, 118.0 * pitch, 34.0, 0.45, SHAPE_SINE, 3.0, 0.002)
	_noise(buf, 0.0, seconds, 0.30, 700.0 * pitch, 2.4, 0.004)
	_crackle(buf, 0.03, seconds * 0.55, 8, 0.36)
	return buf


## A round into the hull: metal first, thump under it. Short enough to fire often.
func _hit() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.26)
	_noise(buf, 0.0, 0.20, 0.45, 3000.0, 24.0, 0.001)
	_tone(buf, 0.0, 0.20, 700.0, 640.0, 0.16, SHAPE_SQUARE, 26.0, 0.001)
	_tone(buf, 0.0, 0.20, 930.0, 860.0, 0.14, SHAPE_SQUARE, 30.0, 0.001)
	_tone(buf, 0.0, 0.18, 1180.0, 1090.0, 0.11, SHAPE_SQUARE, 34.0, 0.001)
	_tone(buf, 0.0, 0.20, 110.0, 60.0, 0.50, SHAPE_SINE, 16.0, 0.001)
	return buf


# --- The ship ------------------------------------------------------------------

## The transformation: servos winding up, hydraulics hissing, then the clunk of the
## frame locking into the new pose. The two clunks are the point — a single one
## reads as a glitch, two read as a mechanism.
func _transform() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.86)
	_tone(buf, 0.0, 0.58, 180.0, 760.0, 0.22, SHAPE_SAW, 0.9, 0.05, 14.0, 0.02)
	_noise(buf, 0.02, 0.55, 0.16, 5200.0, 2.0, 0.04)
	_clunk(buf, 0.56, 0.60)
	_clunk(buf, 0.74, 0.34)
	return buf


## The burner lighting: a thump, then a roar that opens up instead of decaying.
func _afterburner() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.80)
	_tone(buf, 0.0, 0.30, 95.0, 40.0, 0.55, SHAPE_SINE, 10.0, 0.002)
	_noise(buf, 0.02, 0.76, 0.42, 1200.0, 2.4, 0.05)
	_tone(buf, 0.05, 0.72, 120.0, 380.0, 0.18, SHAPE_SAW, 2.2, 0.04)
	return buf


## The dash: air moving, nothing more. Short so it can fire on cooldown.
func _dash() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.34)
	_noise(buf, 0.0, 0.32, 0.40, 2600.0, 9.0, 0.010)
	_tone(buf, 0.0, 0.30, 500.0, 160.0, 0.24, SHAPE_SINE, 9.0, 0.006)
	return buf


## The bomb: a charge winding up, then the largest thing in the palette.
func _bomb() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(1.55)
	_tone(buf, 0.0, 0.26, 300.0, 900.0, 0.20, SHAPE_SQUARE, 0.6, 0.02)
	_noise(buf, 0.26, 1.20, 0.85, 700.0, 2.4, 0.002)
	_tone(buf, 0.26, 1.10, 110.0, 25.0, 0.85, SHAPE_SINE, 2.0, 0.002)
	_crackle(buf, 0.30, 0.90, 9, 0.26)
	return buf


## The decoy: a pop and a burning flare. Bright, short, unmistakably not a weapon.
func _decoy() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.60)
	_noise(buf, 0.0, 0.04, 0.55, 8000.0, 40.0, 0.001)
	_noise(buf, 0.02, 0.56, 0.24, 6000.0, 4.0, 0.010)
	_tone(buf, 0.0, 0.20, 1200.0, 900.0, 0.12, SHAPE_SINE, 18.0, 0.001)
	return buf


# --- Interface -----------------------------------------------------------------

## A menu blip: quiet, bright, and over before it can become annoying.
func _ui_select() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(0.09)
	_tone(buf, 0.0, 0.07, 1400.0, 1400.0, 0.18, SHAPE_SQUARE, 40.0, 0.002)
	_tone(buf, 0.0, 0.07, 700.0, 700.0, 0.10, SHAPE_SINE, 40.0, 0.002)
	return buf


## The hover engine: a turbine hum that loops forever. Every partial is an integer
## multiple of the loop length's reciprocal, so the loop point is silent by
## construction — no crossfade, no click.
func _engine_loop() -> PackedFloat32Array:
	var buf: PackedFloat32Array = _buffer(1.0)
	_tone(buf, 0.0, 1.0, 90.0, 90.0, 0.30, SHAPE_SAW, 0.0, 0.0, 6.0, 0.02)
	_tone(buf, 0.0, 1.0, 91.0, 91.0, 0.22, SHAPE_SAW, 0.0, 0.0, 6.0, 0.02)
	_tone(buf, 0.0, 1.0, 180.0, 180.0, 0.14, SHAPE_SINE, 0.0, 0.0)
	_tone(buf, 0.0, 1.0, 270.0, 270.0, 0.09, SHAPE_SINE, 0.0, 0.0)
	_tone(buf, 0.0, 1.0, 1080.0, 1080.0, 0.05, SHAPE_SINE, 0.0, 0.0, 3.0, 0.30)
	_tone(buf, 0.0, 1.0, 2160.0, 2160.0, 0.03, SHAPE_SINE, 0.0, 0.0, 2.0, 0.40)
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


## Adds low-passed noise. The gain is compensated for the filter, so `amp` means the
## same loudness as the same `amp` on a tone instead of quietly vanishing as the
## cutoff drops.
func _noise(
	buf: PackedFloat32Array,
	start: float,
	dur: float,
	amp: float,
	cutoff: float,
	decay: float,
	attack: float = 0.004
) -> void:
	var begin: int = int(start * RATE)
	var frames: int = int(dur * RATE)
	var coefficient: float = 1.0 - exp(-TAU * cutoff / float(RATE))
	var gain: float = sqrt((2.0 - coefficient) / coefficient)
	var low: float = 0.0
	for i in frames:
		var index: int = begin + i
		if index < 0:
			continue
		if index >= buf.size():
			break
		var t: float = float(i) / RATE
		low += coefficient * (_rand() - low)
		buf[index] += low * gain * amp * _env(t, dur, attack, decay, 0.0)


## A mechanical impact: a noise tick plus a low thud. The transformation is built
## out of these, and so is anything else that has to sound like metal meeting metal.
func _clunk(buf: PackedFloat32Array, start: float, amp: float) -> void:
	_noise(buf, start, 0.07, amp, 4200.0, 46.0, 0.001)
	_tone(buf, start, 0.10, 110.0, 55.0, amp * 0.8, SHAPE_SINE, 30.0, 0.001)
	_tone(buf, start, 0.06, 640.0, 600.0, amp * 0.2, SHAPE_SQUARE, 60.0, 0.001)


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
