class_name GameProgress
extends RefCounted
## The pilot's persistent record: how many enemies they have downed and which
## scenario they flew last.
##
## Only the kill count and the scenario are stored. The level and every bonus are
## derived from the count, so a save can never hold a level that disagrees with the
## kills that earned it. That is also what lets the curve be retuned later without
## migrating old files: an old save simply reads at the level its kills are worth
## today.
##
## The class keeps one cached instance because every kill writes the file and the
## HUD reads the same record: reloading the file per kill would put disk I/O on the
## firing path for no benefit.

const CONFIG_PATH: String = "user://progress.cfg"
const SECTION: String = "pilot"
const KILLS_KEY: String = "total_kills"
const SCENARIO_KEY: String = "last_scenario"
const VERSION_KEY: String = "version"
const VERSION: int = 1

const MAX_LEVEL: int = 100

## The path the cached instance was built from. Tests replace it before any scene
## loads, so a suite run never reads or writes the player's real progress.
static var _path: String = CONFIG_PATH
static var _cache: GameProgress = null

var total_kills: int = 0
var last_scenario: String = ""
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
## reads that file. Nothing in the game calls this; the smoke suite does.
static func use_path(path: String) -> void:
	_path = path
	_cache = null


## True when a save exists. The menu uses it to decide whether CONTINUE is offered:
## an absent file is not an empty save, it is no run to resume.
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
## scenario that wants to be resumable only has to call this.
func remember_scenario(scene_path: String) -> void:
	last_scenario = scene_path
	write_to_disk()


## Clears the record and deletes the file, so CONTINUE disappears. The cached
## instance stays alive at level 1, which is what the HUD must show right away.
func reset() -> void:
	total_kills = 0
	last_scenario = ""
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_emit()


func read_from_disk() -> void:
	total_kills = 0
	last_scenario = ""

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


func write_to_disk() -> void:
	# The load keeps any other section the file may hold, the same way GameSettings
	# keeps its own settings when it writes a livery.
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value(SECTION, KILLS_KEY, total_kills)
	config.set_value(SECTION, SCENARIO_KEY, last_scenario)
	config.set_value(SECTION, VERSION_KEY, VERSION)
	config.save(path)


func _emit() -> void:
	GlobalEventBus.pilot_progress_changed.emit(
		total_kills, level(), kills_into(), kills_to_next()
	)
