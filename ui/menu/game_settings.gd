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

## The livery the file ships: a slightly warm white hull with the blue stripe the
## VF-1S wears. Both are also the defaults the options palette offers, so "never
## touched" and "picked the factory swatch" end up the same ship. The floats are
## the ones the GLB stores, not a rounded reading of them: a default that is only
## close would paint a hull slightly off the file's own.
const DEFAULT_HULL: Color = Color(0.9063318, 0.9063318, 0.9063318, 1.0)
const DEFAULT_TRIM: Color = Color(0.027445495, 0.06274266, 0.83921564, 1.0)


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


## Both colours travel together because they are one decision: a hull and the
## stripe that cuts across it. Saving them separately would let a crash between
## the two writes leave a livery nobody asked for.
static func save_livery(hull: Color, trim: Color, path: String = CONFIG_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value(LIVERY_SECTION, HULL_KEY, hull)
	config.set_value(LIVERY_SECTION, TRIM_KEY, trim)
	config.save(path)


static func _load_color(path: String, key: String, fallback: Color) -> Color:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return fallback
	var stored: Variant = config.get_value(LIVERY_SECTION, key, fallback)
	if typeof(stored) != TYPE_COLOR:
		return fallback
	return stored as Color
