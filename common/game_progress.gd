class_name GameProgress
extends RefCounted
## The pilot's persistent record: how many enemies they have downed, which
## scenario they flew last and when they last flew it.
##
## Only the kill count, the scenario and the timestamp are stored. The level and
## every bonus are derived from the count, so a save can never hold a level that
## disagrees with the kills that earned it. That is also what lets the curve be
## retuned later without migrating old files: an old save simply reads at the
## level its kills are worth today.
##
## The file this record reads is one save card, chosen by `SaveSlots`. The class
## keeps one cached instance because every kill writes the file and the HUD reads
## the same record: reloading the file per kill would put disk I/O on the firing
## path for no benefit. `CONFIG_PATH` is the single save the first build shipped,
## kept as the source `SaveSlots` imports from.

const CONFIG_PATH: String = "user://progress.cfg"
const SECTION: String = "pilot"
const KILLS_KEY: String = "total_kills"
const SCENARIO_KEY: String = "last_scenario"
const LAST_PLAYED_KEY: String = "last_played"
const VERSION_KEY: String = "version"
const VERSION: int = 2

const MAX_LEVEL: int = 100

## The path the cached instance was built from. Tests replace it before any scene
## loads, so a suite run never reads or writes the player's real progress.
static var _path: String = CONFIG_PATH
static var _cache: GameProgress = null

var total_kills: int = 0
var last_scenario: String = ""
## Unix seconds of the last scenario start. It dates the save card; it is not
## read by anything in the run loop.
var last_played: int = 0
var path: String = CONFIG_PATH


## The one live record. The first call reads the file; every later call returns the
## same instance, which is what makes a kill visible to the HUD on the same frame.
static func instance() -> GameProgress:
	if _cache == null:
		_cache = GameProgress.new()
		_cache.path = _path
		_cache.read_from_disk()
	return _cache


## Points the record at another file and drops the cache, so the next `instance()`
## reads that file. `SaveSlots` calls it when the player picks a card; the smoke
## suite calls it to keep the player's real saves out of the run.
static func use_path(path: String) -> void:
	_path = path
	_cache = null


## True when the active card has a file. Nothing in the game gates on it any more
## -- CONTINUE opens the card list whether or not one has flown -- but it stays
## as the direct answer to "has this record ever been written".
static func has_save() -> bool:
	return FileAccess.file_exists(_path)


## The kills needed to reach `level`. Level 1 is the floor and costs nothing; the
## curve is a gentle linear start and a quadratic tail, so the first levels arrive
## inside the first fight and the last ones are a long climb.
static func kills_for_level(level: int) -> int:
	var steps: int = clampi(level, 1, MAX_LEVEL) - 1
	return ceili(0.045 * float(steps * steps) + 0.55 * float(steps))


## The level a total is worth. A loop of at most 100 steps is cheaper to read than
## the closed form and has no boundary rounding to get wrong.
static func level_for_kills(total: int) -> int:
	var level: int = 1
	while level < MAX_LEVEL and kills_for_level(level + 1) <= total:
		level += 1
	return level


func level() -> int:
	return level_for_kills(total_kills)


## Kills banked since the current level began.
func kills_into() -> int:
	return maxi(total_kills - kills_for_level(level()), 0)


## Kills still needed for the next level. Zero at the cap.
func kills_to_next() -> int:
	if level() >= MAX_LEVEL:
		return 0
	return kills_for_level(level() + 1) - total_kills


## One enemy destroyed. The write is per kill because the whole point of the save
## is that closing the game never costs progress; a kill is seconds apart, so the
## file is small and the write is not on a hot path.
func register_kill() -> void:
	total_kills += 1
	write_to_disk()
	_emit()


## The scenario a run is starting. Called by the level itself, so any future
## scenario that wants to be resumable only has to call this. The timestamp is
## taken here rather than on every kill: a card is dated by its last flight, not
## by its last kill.
func remember_scenario(scene_path: String) -> void:
	last_scenario = scene_path
	last_played = int(Time.get_unix_time_from_system())
	write_to_disk()


## Clears the record and deletes the file, so CONTINUE disappears. The cached
## instance stays alive at level 1, which is what the HUD must show right away.
func reset() -> void:
	total_kills = 0
	last_scenario = ""
	last_played = 0
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_emit()


func read_from_disk() -> void:
	total_kills = 0
	last_scenario = ""
	last_played = 0

	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		# A missing or corrupt file is a new pilot, not an error: the file is left
		# alone so a broken save can be inspected instead of silently rewritten.
		return

	var stored_kills: Variant = config.get_value(SECTION, KILLS_KEY, 0)
	if typeof(stored_kills) == TYPE_INT:
		total_kills = maxi(stored_kills, 0)

	var stored_scenario: Variant = config.get_value(SECTION, SCENARIO_KEY, "")
	if typeof(stored_scenario) == TYPE_STRING:
		last_scenario = stored_scenario

	var stored_played: Variant = config.get_value(SECTION, LAST_PLAYED_KEY, 0)
	if typeof(stored_played) == TYPE_INT:
		last_played = maxi(stored_played, 0)


func write_to_disk() -> void:
	# The load keeps any other section the file may hold, the same way GameSettings
	# keeps its own settings when it writes a livery.
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value(SECTION, KILLS_KEY, total_kills)
	config.set_value(SECTION, SCENARIO_KEY, last_scenario)
	config.set_value(SECTION, LAST_PLAYED_KEY, last_played)
	config.set_value(SECTION, VERSION_KEY, VERSION)
	config.save(path)


func _emit() -> void:
	GlobalEventBus.pilot_progress_changed.emit(
		total_kills, level(), kills_into(), kills_to_next()
	)
