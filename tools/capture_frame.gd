extends Node
## Development helper: renders a real frame to PNG so visuals can be reviewed
## without a human at the keyboard.
## Run: <godot> --path . tools/capture_frame.tscn

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
const OUTPUT_PATH: String = "/tmp/gerwalk_frame.png"
const WARMUP_FRAMES: int = 170


func _ready() -> void:
	var arena: Node = load(ARENA_SCENE).instantiate()
	add_child(arena)

	await get_tree().physics_frame
	await get_tree().physics_frame

	Input.action_press(&"aim_right")
	Input.action_press(&"fire")

	for _i in WARMUP_FRAMES:
		await get_tree().physics_frame

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(OUTPUT_PATH)
	if error == OK:
		print("Saved frame to ", OUTPUT_PATH)
	else:
		printerr("Could not save frame: ", error_string(error))

	get_tree().quit(0 if error == OK else 1)
