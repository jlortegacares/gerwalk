class_name SaveSlots
extends RefCounted
## The pilot's save cards: six independent records, one file each, plus the card
## the game is currently flying.
##
## A card holds exactly what a single save used to hold -- the kill total, the
## scenario flown last and when it was flown -- because the level and every bonus
## stay derived from the kills. A card is therefore a pilot, not a saved mission:
## the arena regenerates and its enemies stream, so there is no midpoint to
## serialise and nothing here pretends otherwise.
##
## The active card lives in `settings.cfg` rather than in a file of its own: that
## file already keeps the display, livery and pad sections side by side, and its
## writers load before they save, so adding one more section cannot erase another.
##
## Nothing here knows about the menu. `GameProgress` still owns the record and its
## file; this class only decides which file that is and describes the rest.

const SLOT_COUNT: int = 6
const DIR: String = "user://saves"
const FILE_FORMAT: String = "%s/pilot_%d.cfg"
const SETTINGS_PATH: String = GameSettings.CONFIG_PATH
const SECTION: String = "save"
const ACTIVE_KEY: String = "active_slot"
const DEFAULT_SLOT: int = 1

## The single-save file this feature replaces. It is imported once and then
## renamed, never deleted, so a broken import can be inspected by hand.
const LEGACY_PATH: String = GameProgress.CONFIG_PATH

## The directory the cards live in. Only the smoke suite changes it, before any
## scene loads, so a suite run never touches the player's real saves.
static var _dir: String = DIR
static var _legacy_path: String = LEGACY_PATH
static var _backup_path: String = "%s.imported" % LEGACY_PATH


## The file a card is stored in. Slot numbers are one-based everywhere, in the
## file name, on the panel and in the settings file.
static func path_for(slot: int) -> String:
	return FILE_FORMAT % [_dir, clampi(slot, 1, SLOT_COUNT)]


## Test seam. Nothing in the game calls this: the suite points the cards at a
## scratch directory and a scratch legacy file before the first scene enters the
## tree, the same way it points `GameProgress` at a scratch record.
static func configure(dir: String, legacy: String) -> void:
	_dir = dir
	_legacy_path = legacy
	_backup_path = "%s.imported" % legacy


## The card the game is flying. A missing settings file, a value of the wrong
## type or a number outside the card range all read as the first card: the pointer
## can never name a file the panel cannot show.
static func active_slot(settings_path: String = SETTINGS_PATH) -> int:
	var config: ConfigFile = ConfigFile.new()
	if config.load(settings_path) != OK:
		return DEFAULT_SLOT
	var stored: Variant = config.get_value(SECTION, ACTIVE_KEY, DEFAULT_SLOT)
	if typeof(stored) != TYPE_INT:
		return DEFAULT_SLOT
	return clampi(int(stored), 1, SLOT_COUNT)


## Makes `slot` the card the game flies and points the record at its file. The
## cache is always dropped so the next `GameProgress.instance()` reads that card's
## file instead of trusting whatever was in memory, and the card is written before
## the record moves: a crash between the two leaves the pointer on the card that
## was chosen, which is the recoverable half of the pair.
static func select(slot: int, settings_path: String = SETTINGS_PATH) -> void:
	var chosen: int = clampi(slot, 1, SLOT_COUNT)
	_write_active(chosen, settings_path)
	_ensure_dir()
	GameProgress.use_path(path_for(chosen))


## What the card holds, read straight from its file so the panel can describe a
## card that is not active. An unreadable file still counts as occupied: the file
## exists, and calling it empty would invite the panel to overwrite a save that is
## merely damaged.
static func summary(slot: int) -> Dictionary:
	var path: String = path_for(slot)
	var entry: Dictionary = {
		"slot": clampi(slot, 1, SLOT_COUNT),
		"occupied": FileAccess.file_exists(path),
		"kills": 0,
		"level": 1,
		"scenario": "",
		"played": 0,
	}
	if not entry["occupied"]:
		return entry

	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return entry

	var stored_kills: Variant = config.get_value(
		GameProgress.SECTION, GameProgress.KILLS_KEY, 0
	)
	if typeof(stored_kills) == TYPE_INT:
		entry["kills"] = maxi(int(stored_kills), 0)
	entry["level"] = GameProgress.level_for_kills(int(entry["kills"]))

	var stored_scenario: Variant = config.get_value(
		GameProgress.SECTION, GameProgress.SCENARIO_KEY, ""
	)
	if typeof(stored_scenario) == TYPE_STRING:
		entry["scenario"] = String(stored_scenario)

	var stored_played: Variant = config.get_value(
		GameProgress.SECTION, GameProgress.LAST_PLAYED_KEY, 0
	)
	if typeof(stored_played) == TYPE_INT:
		entry["played"] = maxi(int(stored_played), 0)
	return entry


## Deletes a card. When the card being erased is the one in memory the record is
## reset too, because the HUD must not keep showing a pilot whose file is gone.
static func erase(slot: int) -> void:
	var path: String = path_for(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if GameProgress.instance().path == path:
		GameProgress.instance().reset()


## Points the record at the active card, importing the old single save on the
## first launch of this build. Called by the boot menu; the pause screen skips it
## because a run already owns a record that must not be reloaded underneath it.
static func ensure(settings_path: String = SETTINGS_PATH) -> void:
	_migrate()
	_ensure_dir()
	GameProgress.use_path(path_for(active_slot(settings_path)))


static func _write_active(slot: int, settings_path: String) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(settings_path)
	config.set_value(SECTION, ACTIVE_KEY, slot)
	var error: Error = config.save(settings_path)
	if error != OK:
		push_error(
			"Could not save the active card to %s: %s"
			% [settings_path, error_string(error)]
		)


## Idempotent by construction: the import only runs when the old file exists, no
## card exists and the backup does not. Once the backup exists the old file can
## never be imported again, which is what stops an erased card 1 from coming back.
static func _migrate() -> void:
	if not FileAccess.file_exists(_legacy_path):
		return

	if not _any_card_exists() and not FileAccess.file_exists(_backup_path):
		_ensure_dir()
		var copy: Error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(_legacy_path),
			ProjectSettings.globalize_path(path_for(DEFAULT_SLOT))
		)
		if copy != OK:
			push_error("Could not import the old save: %s" % error_string(copy))
			return

	if not FileAccess.file_exists(_backup_path):
		var moved: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(_legacy_path),
			ProjectSettings.globalize_path(_backup_path)
		)
		if moved != OK:
			push_error("Could not set the old save aside: %s" % error_string(moved))


static func _any_card_exists() -> bool:
	for slot: int in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(path_for(slot)):
			return true
	return false


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
