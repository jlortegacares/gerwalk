extends Node
## Development helper: renders the boss GLB alone, from fixed orthographic angles,
## so scale and bow are read from the asset instead of guessed from the node names.
## The in-game camera sits high and looks almost straight down, which is the right
## read for play and the wrong one for judging the hull.
##
##   <godot> --path . tools/boss_view.tscn -- --view top --out /tmp/boss_top.png
##
## `--view top|side|front|quarter` (default quarter) picks the camera.
## `--size 900` sets the square render size.
## `--out PATH` overrides the output file.
##
## The framing constants come from `tools/probe_boss.gd`; rerun that probe and
## update them if the asset is replaced.

const MODEL_PATH: String = "res://models/boss-1/capital_mother_ship_class_two..glb"
const DEFAULT_OUTPUT: String = "/tmp/boss_view.png"
## Measured AABB of the whole hull, used to frame every view at one scale.
const HULL_SIZE: Vector3 = Vector3(6.945099, 1.779842, 1.358975)
const HULL_CENTER: Vector3 = Vector3(5.859949, 2.026372, 1.097977)
const VIEWS: Dictionary = {
	"front": Vector3(12.0, 0.0, 0.0),
	"side": Vector3(0.0, 0.0, 12.0),
	"top": Vector3(0.0, 12.0, 0.0),
	"quarter": Vector3(8.0, 6.0, 8.0),
}

var _viewport: SubViewport


func _ready() -> void:
	var view: String = _argument("view", "quarter")
	var size: int = int(_argument("size", "900"))
	var output: String = _argument("out", DEFAULT_OUTPUT)

	_build_stage(size, view)
	_build_model()

	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = _viewport.get_texture().get_image()
	var error: Error = image.save_png(output)
	if error == OK:
		print("Saved boss view to ", output)
	else:
		printerr("Could not save boss view: ", error_string(error))
	get_tree().quit(0 if error == OK else 1)


func _build_stage(size: int, view: String) -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(size, size)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(HULL_SIZE.x, maxf(HULL_SIZE.y, HULL_SIZE.z)) * 1.25
	camera.near = 0.05
	camera.far = 100.0
	var up: Vector3 = Vector3.RIGHT if view == "top" else Vector3.UP
	camera.look_at_from_position(VIEWS[view] as Vector3, Vector3.ZERO, up)
	_viewport.add_child(camera)

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.16, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.81, 0.88)
	environment.ambient_light_energy = 0.55
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	key.light_energy = 1.15
	add_child(key)


func _build_model() -> void:
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	var model: Node3D = packed.instantiate() as Node3D
	# Centre the hull on the origin so every view shares one frame.
	model.position = -HULL_CENTER
	add_child(model)


func _argument(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var flag: String = "--" + name
	for index in args.size():
		if args[index] == flag and index + 1 < args.size():
			return args[index + 1]
	return fallback
