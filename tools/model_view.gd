extends Node
## Development helper: renders the player's model alone, on a neutral backdrop,
## from a fixed orthographic angle. The game camera sits 15 degrees off vertical,
## which is the right read for play and the wrong one for judging a shape against
## a reference: it flattens everything below the wings into nothing.
##
##   ./run.sh tools/model_view.tscn -- --view side --out /tmp/side.png
##   ./run.sh tools/model_view.tscn -- --view quarter --fighter 1 --out /tmp/f.png
##
## `--view front|side|top|quarter|game` (default quarter) picks the camera.
## `--fighter 1` poses FIGHTER instead of GERWALK.
## `--size 900` sets the square render size.
## `--out PATH` overrides the output file.

const PLAYER_SCENE: String = "res://entities/player/player.tscn"
const DEFAULT_OUTPUT: String = "/tmp/gerwalk_model.png"
## Orthographic, so the three views share one scale and a dimension measured in
## one can be compared against another. 5.6 units covers the 4.15 m hull and the
## 3.0 m span with margin.
const FRAME_SIZE: float = 5.6
const TARGET: Vector3 = Vector3(0.15, 0.0, 0.0)
const VIEWS: Dictionary = {
	"front": Vector3(7.0, 0.0, 0.0),
	"side": Vector3(0.0, 0.0, 7.0),
	"top": Vector3(0.0, 7.0, 0.0),
	"quarter": Vector3(5.0, 3.4, 5.0),
	# The game camera sits 15 degrees off vertical (50 up, 13.4 back), so this is
	# the angle the model is actually judged from in play.
	"game": Vector3(0.0, 7.0, 1.88),
}

var _viewport: SubViewport


func _ready() -> void:
	var view: String = _argument("view", "quarter")
	var size: int = int(_argument("size", "900"))
	var fighter: bool = _argument("fighter", "0") == "1"
	var output: String = _argument("out", DEFAULT_OUTPUT)

	_build_stage(size, view)
	_build_model(fighter)

	# The model is static here, so the pose is set once and the physics step is
	# off: FIGHTER with no input would otherwise start gliding on its own.
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = _viewport.get_texture().get_image()
	var error: Error = image.save_png(output)
	if error == OK:
		print("Saved model view to ", output)
	else:
		printerr("Could not save model view: ", error_string(error))
	get_tree().quit(0 if error == OK else 1)


func _build_stage(size: int, view: String) -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(size, size)
	# A SubViewport that is not inside a container never becomes visible, so it
	# would never draw unless it is told to update unconditionally.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = FRAME_SIZE
	camera.near = 0.05
	camera.far = 100.0
	# Looking straight down, the up vector has to be horizontal or the camera has
	# no roll reference: RIGHT puts the nose up the frame.
	var up: Vector3 = Vector3.RIGHT if view == "top" else Vector3.UP
	camera.look_at_from_position(TARGET + (VIEWS[view] as Vector3), TARGET, up)
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
	key.rotation_degrees = Vector3(-48.0, float(_argument("sunrot", "-38.0")), 0.0)
	key.light_energy = 1.15
	# `--nosun 1` leaves only the ambient term, which is how a livery or normal
	# problem is told apart from a lighting one: ambient is uniform, so anything
	# still dark on one side is in the mesh or its material.
	if _argument("nosun", "0") == "1":
		key.light_energy = 0.0
	add_child(key)


func _build_model(fighter: bool) -> void:
	var player: Player = load(PLAYER_SCENE).instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	player.set("_mode", Player.Mode.FIGHTER if fighter else Player.Mode.GERWALK)
	player.set("_mode_blend", 1.0 if fighter else 0.0)
	player.call("_update_afterburner_visual", 0.0)

	# Nothing in this shot is in motion, so the engine plumes and the aim beam
	# only add noise to the silhouette.
	for flame in player.get("_thruster_plumes") as Array:
		(flame as MeshInstance3D).visible = false
	for core in player.get("_thruster_cores") as Array:
		(core as MeshInstance3D).visible = false
	# The wake is world-space and stays where it was born, so in a still it sits
	# on top of the hull it is supposed to trail behind.
	for smoke in player.get("_smoke") as Array:
		var puff: GPUParticles3D = smoke as GPUParticles3D
		puff.emitting = false
		puff.visible = false
	# The ship's counter-light would otherwise make `--nosun` a lie: with it on, the
	# frame still carries a directional term and the ambient-only check reads wrong.
	var fill: DirectionalLight3D = player.get_node_or_null("CameraRig/FillLight") as DirectionalLight3D
	if fill != null:
		fill.light_energy = 0.0
	var beam: MeshInstance3D = player.get("_aim_beam") as MeshInstance3D
	if beam != null:
		beam.visible = false


func _argument(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var flag: String = "--" + name
	for index in args.size():
		if args[index] == flag and index + 1 < args.size():
			return args[index + 1]
	return fallback
