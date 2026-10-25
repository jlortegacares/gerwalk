class_name GameSettings
extends RefCounted
## The display preference the build actually honours, kept in `user://` so the
## choice survives a restart.
##
## There is no audio in this build, so there is deliberately no volume knob here:
## a slider that changes nothing is worse than no slider.

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "display"
const FULLSCREEN_KEY: String = "fullscreen"
const LIVERY_SECTION: String = "livery"
const HULL_KEY: String = "hull"
const TRIM_KEY: String = "trim"
const CANOPY_KEY: String = "canopy"
const LINES_KEY: String = "lines"
const NOSE_KEY: String = "nose"

## The livery the file ships: a slightly warm white hull with the blue stripe the
## VF-1S wears. Both are also the defaults the options palette offers, so "never
## touched" and "picked the factory swatch" end up the same ship. The floats are
## the ones the GLB stores, not a rounded reading of them: a default that is only
## close would paint a hull slightly off the file's own.
const DEFAULT_HULL: Color = Color(0.9063318, 0.9063318, 0.9063318, 1.0)
const DEFAULT_TRIM: Color = Color(0.027445495, 0.06274266, 0.83921564, 1.0)
## The canopy glass has been tinted blue by the game since before it was an
## option, so that tint is the factory colour rather than the file's clear glass.
const DEFAULT_CANOPY: Color = Color(0.31, 0.70, 0.95, 1.0)
## The file's dark trim: the lines that cut the hull and the stripe into panels.
const DEFAULT_LINES: Color = Color(0.11997428, 0.11997428, 0.11997428, 1.0)
## The nose ships in the hull's own white, so the factory livery is unchanged by
## the nose having a colour of its own. It shares the hull default on purpose:
## "never touched" has to keep looking like the ship the file ships.
const DEFAULT_NOSE: Color = DEFAULT_HULL


## A missing or unreadable file means "windowed", which is the engine default and
## the safe answer on a machine the game has never run on.
static func load_fullscreen(path: String = CONFIG_PATH) -> bool:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return false
	return bool(config.get_value(SECTION, FULLSCREEN_KEY, false))


## The load keeps whatever else may live in the file, so adding a second setting
## later cannot silently erase the first.
static func save_fullscreen(enabled: bool, path: String = CONFIG_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value(SECTION, FULLSCREEN_KEY, enabled)
	config.save(path)


static func apply_fullscreen(enabled: bool) -> void:
	var mode: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if enabled
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(mode)


static func load_hull(path: String = CONFIG_PATH) -> Color:
	return _load_color(path, HULL_KEY, DEFAULT_HULL)


static func load_trim(path: String = CONFIG_PATH) -> Color:
	return _load_color(path, TRIM_KEY, DEFAULT_TRIM)


static func load_canopy(path: String = CONFIG_PATH) -> Color:
	return _load_color(path, CANOPY_KEY, DEFAULT_CANOPY)


static func load_lines(path: String = CONFIG_PATH) -> Color:
	return _load_color(path, LINES_KEY, DEFAULT_LINES)


static func load_nose(path: String = CONFIG_PATH) -> Color:
	return _load_color(path, NOSE_KEY, DEFAULT_NOSE)


## The five colours travel together because they are one decision: a hull, the
## stripe that cuts across it, the glass over the cockpit, the lines that separate
## the panels and the nose cone. Saving them separately would let a crash between
## the writes leave a livery nobody asked for.
static func save_livery(
	hull: Color,
	trim: Color,
	canopy: Color,
	lines: Color,
	nose: Color,
	path: String = CONFIG_PATH
) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value(LIVERY_SECTION, HULL_KEY, hull)
	config.set_value(LIVERY_SECTION, TRIM_KEY, trim)
	config.set_value(LIVERY_SECTION, CANOPY_KEY, canopy)
	config.set_value(LIVERY_SECTION, LINES_KEY, lines)
	config.set_value(LIVERY_SECTION, NOSE_KEY, nose)
	config.save(path)


static func _load_color(path: String, key: String, fallback: Color) -> Color:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return fallback
	var stored: Variant = config.get_value(LIVERY_SECTION, key, fallback)
	if typeof(stored) != TYPE_COLOR:
		return fallback
	return stored as Color
