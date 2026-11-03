extends Node
## The game's voice. Autoloaded as `Sfx`.
##
## One place owns the palette: `play` for the ship's own weapons and the interface,
## `play_at` for anything that happens in the world, and `engine` for the hum that
## follows the ship. Callers name a sound; they never touch a player node.
##
## The palette is synthesized by `tools/generate_sfx.gd` into `audio/sfx/*.wav`.
## Nothing here is sampled from the anime: "Macross-inspired" is the character of the
## sounds — a turbine whine, a dry gunpod, the airy whoosh of a missile leaving the
## rail, a rising lock tone, servos — not their source.
##
## Timbre is the generator's job; level is this file's. The generator normalises every
## file to the same peak, which says nothing about loudness — a 0.09 s blip and a
## 1.3 s blast both peak at 0.70. `GAIN_DB` is the mix that makes them sit together,
## `PITCH_JITTER` keeps a repeated shot from sounding like a looped sample, and the
## stack window keeps eight missiles leaving one frame from summing into a clipped
## wall of noise.

const SFX_DIR: String = "res://audio/sfx"
## Voices in the non-positional pool. A full salvo, a beam and an explosion at once
## is about eight; the rest is headroom for the lock tone and the interface.
const VOICES: int = 16
## Positional players are created per event and freed when they finish. The cap is
## what stops a bullet pattern from building a node per shot.
const MAX_SPATIAL: int = 24
const SPATIAL_UNIT: float = 16.0
## Positional sounds are silenced past this distance. It has to cover the arena's
## despawn ring (190), or a kill at the edge of the fight happens in silence.
const SPATIAL_REACH: float = 220.0
## Keys that keep their level at any distance and only follow their direction. An
## explosion is punctuation, not ambience: most kills land 85-110 units out, where
## inverse-distance attenuation buries the blast under the engine hum. The room and
## the panning still tell the ear where it happened; only the falloff is skipped.
const SPATIAL_FLAT: Array[StringName] = [&"explosion"]
const SFX_BUS: StringName = &"SFX"
## Engine hum, in decibels, at rest and at full speed. Quiet enough to sit under the
## gun and loud enough that the ship never sounds switched off.
const ENGINE_REST_DB: float = -19.0
const ENGINE_TOP_DB: float = -8.0

## Per-sound mix, in decibels on top of whatever the caller asks for. The interface
## sits far under the weapons, the incoming-shot alarm cuts through them, and the
## blasts are the loudest thing in the palette. `KEYS` and this table are checked
## against each other by the smoke test, so a new sound cannot ship without a level.
const GAIN_DB: Dictionary = {
	&"vulcan": -2.5,
	&"plasma": -2.0,
	&"laser": -3.0,
	&"missile_launch": -2.0,
	&"lock_tone": -6.0,
	&"missile_warning": -5.0,
	&"enemy_fire": -3.0,
	&"explosion": 2.5,
	&"player_death": 3.0,
	&"hit": -1.0,
	&"transform": 2.0,
	&"afterburner": 0.0,
	&"dash": -4.0,
	&"bomb": 3.5,
	&"decoy": 0.0,
	&"ui_select": -16.0,
	&"engine_loop": 0.0,
}

## Per-sound pitch variation, as a fraction either side of the requested pitch. A
## gunpod that plays the identical sample twelve times a second is a machine gun of
## one sample; a few percent either way is what makes it read as a mechanism. The
## keys that carry information are absent on purpose: the lock tone and the alarm
## have to be the same pitch every time or they stop meaning anything.
const PITCH_JITTER: Dictionary = {
	&"vulcan": 0.035,
	&"plasma": 0.03,
	&"laser": 0.02,
	&"missile_launch": 0.04,
	&"enemy_fire": 0.05,
	&"explosion": 0.09,
	&"player_death": 0.04,
	&"hit": 0.06,
	&"transform": 0.02,
	&"afterburner": 0.03,
	&"dash": 0.05,
	&"bomb": 0.05,
	&"decoy": 0.04,
}

## Plays of the same key inside this window are one event, not a stack of events.
## Short enough that a held trigger still sounds like separate shots.
const STACK_WINDOW: float = 0.06

## Every key the palette can answer. Loading them at boot keeps the first shot of a
## run from stalling on a disk read.
const KEYS: Array[StringName] = [
	&"vulcan",
	&"plasma",
	&"laser",
	&"missile_launch",
	&"lock_tone",
	&"missile_warning",
	&"enemy_fire",
	&"explosion",
	&"player_death",
	&"hit",
	&"transform",
	&"afterburner",
	&"dash",
	&"bomb",
	&"decoy",
	&"ui_select",
	&"engine_loop",
]

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _spatial: int = 0
var _engine: AudioStreamPlayer = null
var _engine_on: bool = false
## Plays per key. The smoke test reads it to assert which sound an event asked for:
## without an audio device, the wiring is the only observable it has.
var _counts: Dictionary = {}
## The pitch of the last play per key. The smoke test reads it to pin the jitter
## band and to prove an informational sound was not transposed.
var _pitches: Dictionary = {}
## Recent play times per key, for the stack window. Seconds, from `Time`.
var _stack: Dictionary = {}
## Deterministic jitter source. `reset_counts` rewinds it, so a test that plays the
## same sequence hears the same pitches instead of a coin flip.
var _jitter_seed: int = 0x5eed1e55


func _ready() -> void:
	_ensure_buses()
	_load_palette()
	for _i in VOICES:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		# Sound is presentation: it keeps running while the tree is paused, and the
		# game-over countdown must not cut the blast that just killed the ship.
		voice.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice)
		_voices.append(voice)

	_engine = AudioStreamPlayer.new()
	_engine.bus = SFX_BUS
	_engine.stream = _streams.get(&"engine_loop")
	_engine.volume_db = -80.0
	_engine.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_engine)


## The bus, its room and the limiter are built here instead of in a `.tres`: one
## fewer asset to keep in sync with the code that names the bus.
func _ensure_buses() -> void:
	var index: int = AudioServer.get_bus_index(SFX_BUS)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, SFX_BUS)
		AudioServer.set_bus_send(index, &"Master")
		AudioServer.set_bus_volume_db(index, -2.0)
	# The room. Every sound in this game happens in the same sky, and a fully dry
	# palette reads as a folder of samples instead of a place. Kept low: the gun has
	# to stay sharp and the engine must not wash into its own tail.
	if AudioServer.get_bus_effect_count(index) == 0:
		var reverb: AudioEffectReverb = AudioEffectReverb.new()
		reverb.room_size = 0.45
		reverb.damping = 0.55
		reverb.spread = 0.8
		reverb.predelay_msec = 18.0
		reverb.dry = 1.0
		reverb.wet = 0.12
		AudioServer.add_bus_effect(index, reverb)
	# A salvo plus an explosion sums above full scale on a laptop speaker, and the
	# limiter is cheaper than mixing every sound down until nothing has weight.
	var master: int = AudioServer.get_bus_index(&"Master")
	if master >= 0 and AudioServer.get_bus_effect_count(master) == 0:
		var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, limiter)


func _load_palette() -> void:
	for key in KEYS:
		var stream: AudioStream = load("%s/%s.wav" % [SFX_DIR, key]) as AudioStream
		if stream == null:
			push_warning("Sfx: the palette is missing %s" % key)
			continue
		_streams[key] = stream


## A sound with no place in the world: the ship's own weapons, the lock tone, the
## interface. Steals the oldest voice when the pool is busy, which is what keeps a
## held trigger from growing the scene.
func play(key: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _note(key):
		return
	var played: float = pitch * _jitter(key)
	_pitches[key] = played
	_play_flat(key, volume_db + gain(key) + _stack_gain(key), played)


## A sound that happened somewhere: explosions, enemy fire, launches, the bomb.
## Attenuated by distance and panned by the camera, so a turret on the nose is not
## the same sound as one behind the ship.
func play_at(
	key: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0
) -> void:
	if not _note(key):
		return
	var played: float = pitch * _jitter(key)
	_pitches[key] = played
	var level: float = volume_db + gain(key) + _stack_gain(key)
	var host: Node = get_tree().current_scene
	if host == null or _spatial >= MAX_SPATIAL:
		_play_flat(key, level, played)
		return

	var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	voice.stream = _streams[key]
	voice.bus = SFX_BUS
	voice.unit_size = SPATIAL_UNIT
	voice.max_distance = SPATIAL_REACH
	if SPATIAL_FLAT.has(key):
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	voice.volume_db = level
	voice.pitch_scale = played
	host.add_child(voice)
	voice.global_position = position
	_spatial += 1
	voice.finished.connect(func() -> void:
		_spatial = maxi(_spatial - 1, 0)
		voice.queue_free())
	voice.play()


## The hover engine. Called every frame with the ship's speed ratio; the hum follows
## it instead of switching between two sounds, and stops dead when the hull does.
func engine(active: bool, speed_ratio: float = 0.0) -> void:
	if _engine == null:
		return
	if not active:
		if _engine_on:
			_engine_on = false
			_engine.stop()
		return
	var ratio: float = clampf(speed_ratio, 0.0, 1.0)
	if not _engine_on:
		_engine_on = true
		_engine.volume_db = -80.0
		_engine.play()
	_engine.pitch_scale = lerpf(0.82, 1.45, ratio)
	_engine.volume_db = lerpf(ENGINE_REST_DB, ENGINE_TOP_DB, ratio) + gain(&"engine_loop")


## Plays of one key, or of everything when `key` is empty. The smoke test's window
## into the wiring; nothing in the game reads it.
func played(key: StringName = &"") -> int:
	if key == &"":
		var total: int = 0
		for count in _counts.values():
			total += int(count)
		return total
	return int(_counts.get(key, 0))


func reset_counts() -> void:
	_counts.clear()
	_pitches.clear()
	_stack.clear()
	_jitter_seed = 0x5eed1e55


## The level this key sits at on top of whatever the caller asks for. Public so the
## smoke test can prove the mix covers every key and keeps its hierarchy.
func gain(key: StringName) -> float:
	return float(GAIN_DB.get(key, 0.0))


## The pitch of the last play of `key`, or 0 when it never played. The smoke test
## reads it to prove the lock tone keeps one pitch for the whole rack.
func pitch(key: StringName) -> float:
	return float(_pitches.get(key, 0.0))


## Whether a key is in the loaded palette. The smoke test asserts the palette is
## complete instead of trusting that every caller spelled its key right.
func has(key: StringName) -> bool:
	return _streams.has(key)


## Whether the hover hum is running. The test reads it to prove the loop follows
## the ship's life: it starts with the hull and stops when the hull does.
func engine_active() -> bool:
	return _engine_on


## Counts a play and answers whether the key is in the palette. One function so a
## missing sound is counted once, in one place, instead of in every caller.
func _note(key: StringName) -> bool:
	if not _streams.has(key):
		return false
	_counts[key] = int(_counts.get(key, 0)) + 1
	return true


## A small pitch variation, so the same sample played twelve times a second reads as
## a mechanism instead of a loop. Deterministic: the sequence is the same every run,
## which is what lets the test assert it without flaking.
func _jitter(key: StringName) -> float:
	var amount: float = float(PITCH_JITTER.get(key, 0.0))
	if amount <= 0.0:
		return 1.0
	_jitter_seed ^= (_jitter_seed << 13) & 0x7fffffff
	_jitter_seed ^= _jitter_seed >> 17
	_jitter_seed ^= (_jitter_seed << 5) & 0x7fffffff
	var unit: float = float(_jitter_seed & 0xffff) / 32768.0 - 1.0
	return 1.0 + unit * amount


## How much to duck a play because the same key is already sounding. Eight missiles
## leaving the same frame are one event: summing eight full-level copies clips the
## bus, and loudness does not add the way amplitude does. The correction is the power
## sum, so the stack keeps the level of one copy instead of eight.
func _stack_gain(key: StringName) -> float:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var times: Array = _stack.get(key, [])
	while not times.is_empty() and now - float(times[0]) > STACK_WINDOW:
		times.pop_front()
	var count: int = times.size() + 1
	times.append(now)
	_stack[key] = times
	if count <= 1:
		return 0.0
	return -10.0 * log(float(count)) / log(10.0)


func _play_flat(key: StringName, volume_db: float, pitch: float) -> void:
	if _voices.is_empty():
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _streams[key]
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()
