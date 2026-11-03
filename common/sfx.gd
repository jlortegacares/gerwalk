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

const SFX_DIR: String = "res://audio/sfx"
## Voices in the non-positional pool. A full salvo, a beam and an explosion at once
## is about eight; the rest is headroom for the lock tone and the interface.
const VOICES: int = 16
## Positional players are created per event and freed when they finish. The cap is
## what stops a bullet pattern from building a node per shot.
const MAX_SPATIAL: int = 24
const SPATIAL_UNIT: float = 16.0
const SPATIAL_REACH: float = 150.0
const SFX_BUS: StringName = &"SFX"
## Engine hum, in decibels, at rest and at full speed. Quiet enough to sit under the
## gun and loud enough that the ship never sounds switched off.
const ENGINE_REST_DB: float = -19.0
const ENGINE_TOP_DB: float = -8.0

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
## The pitch of the last play per key. The lock ladder is a sound that changes
## without changing key, so the count alone cannot prove it climbed.
var _pitches: Dictionary = {}


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


## The bus and its limiter are built here instead of in a `.tres`: one fewer asset
## to keep in sync with the code that names the bus.
func _ensure_buses() -> void:
	if AudioServer.get_bus_index(SFX_BUS) == -1:
		var index: int = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, SFX_BUS)
		AudioServer.set_bus_send(index, &"Master")
		AudioServer.set_bus_volume_db(index, -2.0)
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
	_pitches[key] = pitch
	_play_flat(key, volume_db, pitch)


## A sound that happened somewhere: explosions, enemy fire, launches, the bomb.
## Attenuated by distance and panned by the camera, so a turret on the nose is not
## the same sound as one behind the ship.
func play_at(
	key: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0
) -> void:
	if not _note(key):
		return
	_pitches[key] = pitch
	var host: Node = get_tree().current_scene
	if host == null or _spatial >= MAX_SPATIAL:
		_play_flat(key, volume_db, pitch)
		return

	var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	voice.stream = _streams[key]
	voice.bus = SFX_BUS
	voice.unit_size = SPATIAL_UNIT
	voice.max_distance = SPATIAL_REACH
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
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
	_engine.volume_db = lerpf(ENGINE_REST_DB, ENGINE_TOP_DB, ratio)


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


## The pitch of the last play of `key`, or 0 when it never played. The lock ladder
## rises per acquired contact, and this is how the smoke test sees that climb.
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


func _play_flat(key: StringName, volume_db: float, pitch: float) -> void:
	if _voices.is_empty():
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _streams[key]
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()
