extends Node
## Development helper: renders a real frame to PNG so visuals can be reviewed
## without a human at the keyboard.
##
##   <godot> --path . tools/capture_frame.tscn
##   <godot> --path . tools/capture_frame.tscn -- --travel 180 --out /tmp/moved.png
##
## `--travel N` holds move_right for N physics frames before the capture, which is
## how the rolling planet is checked: the terrain under the ship must change.
## `--boost N` holds move_right and boost for N frames and captures while still
## burning, which is how the thruster plume and the turbo bar are reviewed.
## `--weapon N` selects weapon 1 (vulcan), 2 (laser) or 3 (plasma) before the
## capture, which is how each archetype's fire is reviewed.
## `--bomb 1` drops one bomb just before the capture, which is how the shockwave is
## reviewed.
## `--out PATH` overrides the output file.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
const DEFAULT_OUTPUT: String = "/tmp/gerwalk_frame.png"
const WARMUP_FRAMES: int = 170


func _ready() -> void:
	var travel_frames: int = int(_argument("travel", "0"))
	var boost_frames: int = int(_argument("boost", "0"))
	var weapon: String = _argument("weapon", "1")
	var drop_bomb: bool = _argument("bomb", "0") == "1"
	var output_path: String = _argument("out", DEFAULT_OUTPUT)

	var arena: Node = load(ARENA_SCENE).instantiate()
	add_child(arena)

	await get_tree().physics_frame
	await get_tree().physics_frame

	Input.action_press(&"aim_right")
	if weapon != "1":
		Input.action_press("weapon_" + weapon)
		await get_tree().physics_frame
		Input.action_release("weapon_" + weapon)
	Input.action_press(&"fire")

	if travel_frames <= 0 and boost_frames <= 0:
		for _i in WARMUP_FRAMES:
			await get_tree().physics_frame
	elif boost_frames > 0:
		Input.action_press(&"move_right")
		Input.action_press(&"boost")
		for _i in boost_frames:
			await get_tree().physics_frame
	else:
		Input.action_press(&"move_right")
		for _i in travel_frames:
			await get_tree().physics_frame
		Input.action_release(&"move_right")
		for _i in 4:
			await get_tree().physics_frame

	# The wave only lives for a fraction of a second, so it is dropped right before
	# the capture instead of at the start of the warmup.
	if drop_bomb:
		Input.action_press(&"bomb")
		await get_tree().physics_frame
		Input.action_release(&"bomb")
		for _i in 6:
			await get_tree().physics_frame

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(output_path)
	if error == OK:
		print("Saved frame to ", output_path)
	else:
		printerr("Could not save frame: ", error_string(error))

	get_tree().quit(0 if error == OK else 1)


func _argument(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var flag: String = "--" + name
	for index in args.size():
		if args[index] == flag and index + 1 < args.size():
			return args[index + 1]
	return fallback
