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
