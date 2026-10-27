extends Node
## Development helper: renders a real frame to PNG so visuals can be reviewed
## without a human at the keyboard.
##
##   <godot> --path . tools/capture_frame.tscn
##   <godot> --path . tools/capture_frame.tscn -- --travel 180 --out /tmp/moved.png
##
## `--travel N` holds move_right for N physics frames before the capture, which is
## how the rolling planet is checked: the terrain under the ship must change.
## `--strafe N` holds move_up with the nose locked right for N frames, which is how
## the bank angle and the level-out are reviewed.
## `--boost N` holds move_right and boost for N frames and captures while still
## burning, which is how the thruster plume and the turbo bar are reviewed.
## `--weapon N` selects weapon 1 (vulcan), 2 (laser) or 3 (plasma) before the
## capture, which is how each archetype's fire is reviewed.
## `--bomb 1` drops one bomb just before the capture, which is how the bomb ring is
## reviewed.
## `--fighter N` transforms into FIGHTER, waits for the switch, then holds
## move_right for N frames: the swept silhouette and the nose-locked gun. Add
## `--boost N` to capture the supersonic burst cone instead of a plain run.
## `--missile N` spawns a contact ahead, holds the missile rack for N frames and
## captures right after the salvo leaves, which is how the wing hardpoints are
## reviewed. Add `--close` to hang the camera nearer the ship, since the game
## camera sits high enough that a missile is only a few pixels long.
## `--roll N` (with `--fighter 1`) starts a left barrel roll and captures N frames
## into it, which is how the slower turn-over and the roll's own side are
## reviewed. Add `--close` to read the hull coming over at the game camera's
## distance. `--zoom F` scales the close stand-off, so `--close 1 --zoom 0.4` fills
## the frame with the hull for a lighting or material check. `--nosmoke 1` hides
## the wake and `--noshadow 1` turns the sun's shadow map off, which is how a dark
## patch on the hull is told apart from the trail and from a cast shadow.
## `--out PATH` overrides the output file.
## `--death 1` kills the ship right before the capture, which is how the death
## screen and its countdown are reviewed without waiting for a turret to land the
## last hit. `--death-delay N` waits N physics frames after the kill before
## capturing (default 2), which is how the explosion is reviewed mid-blast.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
const DEFAULT_OUTPUT: String = "/tmp/gerwalk_frame.png"
const WARMUP_FRAMES: int = 170


func _ready() -> void:
	var travel_frames: int = int(_argument("travel", "0"))
	var strafe_frames: int = int(_argument("strafe", "0"))
	var boost_frames: int = int(_argument("boost", "0"))
	var weapon: String = _argument("weapon", "1")
	var drop_bomb: bool = _argument("bomb", "0") == "1"
	var fighter_frames: int = int(_argument("fighter", "0"))
	var missile_frames: int = int(_argument("missile", "0"))
	var roll_frames: int = int(_argument("roll", "0"))
	var close: bool = _argument("close", "0") == "1"
	var zoom: float = float(_argument("zoom", "1.0"))
	var no_smoke: bool = _argument("nosmoke", "0") == "1"
	var no_shadow: bool = _argument("noshadow", "0") == "1"
	var output_path: String = _argument("out", DEFAULT_OUTPUT)
	var death: bool = _argument("death", "0") == "1"
	var death_delay: int = int(_argument("death-delay", "2"))

	var arena: Node = load(ARENA_SCENE).instantiate()
	add_child(arena)

	await get_tree().physics_frame
	await get_tree().physics_frame

	Input.action_press(&"aim_right")
	if weapon != "1":
		Input.action_press("weapon_" + weapon)
		await get_tree().physics_frame
		Input.action_release("weapon_" + weapon)
	# The vulcan stream would hide the missiles leaving the wings, and it also
	# kills the turret the rack needs, so a missile capture flies unarmed.
	if missile_frames == 0:
		Input.action_press(&"fire")

	if fighter_frames > 0:
		# The transform latch has to be driven from the handler: an action pressed
		# from a coroutine lands after the physics step and never reads as just
		# pressed, the same reason the smoke test calls the method directly.
		var player: Player = arena.get_node("%Player") as Player
		Input.action_release(&"aim_right")
		player.call("_start_transform")
		for _i in 18:
			await get_tree().physics_frame
		Input.action_press(&"move_right")
		if missile_frames > 0:
			# A missile capture needs the contact to stay in the radar, and a
			# fighter at speed would pass it before the rack loads.
			Input.action_release(&"move_right")
		elif roll_frames > 0:
			# The side is read from the stick when the roll starts, so it is held
			# first; the latch problem is the transform's, so the method is called
			# directly instead of pressing `dash`.
			Input.action_release(&"move_right")
			# A stream of bullets would cross the hull mid-roll.
			Input.action_release(&"fire")
			Input.action_press(&"aim_left")
			for _i in 2:
				await get_tree().physics_frame
			player.call("_start_dash")
			Input.action_release(&"aim_left")
			for _i in roll_frames:
				await get_tree().physics_frame
		elif boost_frames > 0:
			Input.action_press(&"boost")
			for _i in boost_frames:
				await get_tree().physics_frame
		else:
			for _i in fighter_frames:
				await get_tree().physics_frame
	elif strafe_frames > 0:
		Input.action_press(&"move_up")
		for _i in strafe_frames:
			await get_tree().physics_frame
	elif travel_frames <= 0 and boost_frames <= 0:
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

	# Presentation-only setup for the capture: `--close` hangs the camera nearer the
	# hull, and the hull is forced visible because an i-frame blink hides it on half
	# the frames. Both go through the nodes the game actually reads, so a close
	# capture is framed the same way every run.
	var ship: Player = arena.get_node("%Player") as Player
	# Lighting diagnostics: `--nosmoke` hides the wake, `--noshadow` turns the sun's
	# shadow map off. Between them, a dark patch on the hull can be pinned on the
	# trail, on a cast shadow, or on neither.
	if no_smoke:
		for smoke in ship.get("_smoke") as Array:
			var puff: GPUParticles3D = smoke as GPUParticles3D
			puff.emitting = false
			puff.visible = false
	if no_shadow:
		for child in arena.get_children():
			if child is DirectionalLight3D:
				(child as DirectionalLight3D).shadow_enabled = false
	# `--sunrot DEG` swings the sun around the vertical axis, which is how a shading
	# asymmetry is told apart from a livery one: if the dark side swaps with it, the
	# light is the cause; if it stays put, the mesh is.
	var sun_yaw: String = _argument("sunrot", "")
	if not sun_yaw.is_empty():
		for child in arena.get_children():
			if child is DirectionalLight3D:
				var light: DirectionalLight3D = child as DirectionalLight3D
				light.rotation_degrees = Vector3(
					light.rotation_degrees.x, float(sun_yaw), light.rotation_degrees.z
				)
	# `--fillenergy E` retunes the airframe fill without a code edit, which is how
	# its level is picked against the arena's sun.
	var fill_energy: String = _argument("fillenergy", "")
	if not fill_energy.is_empty():
		var fill: DirectionalLight3D = ship.get_node_or_null("CameraRig/FillLight") as DirectionalLight3D
		if fill != null:
			fill.light_energy = float(fill_energy)
	if close:
		# The camera rig is reset every frame from its captured base, so the new
		# stand-off goes through `_base` instead of the node alone. `--zoom` scales
		# that stand-off without changing the 75 degree angle.
		var rig: Node3D = ship.get_node("CameraRig") as Node3D
		var cam: Camera3D = ship.get_node("CameraRig/Camera") as Camera3D
		rig.position = Vector3(0.0, 16.0, 4.3) * zoom
		cam.set("_base", rig.position)
	ship.set("_invulnerable", 0.0)
	var visual: Node3D = ship.get("_visual") as Node3D
	if visual != null:
		visual.visible = true

	# A salvo needs a contact: the rack only loads against the radar. The turret is
	# dropped right before the hold so it sits inside the cone. The gun is silenced
	# for the shot, otherwise its stream of bullets hides the missiles leaving the
	# wings.
	if missile_frames > 0:
		Input.action_release(&"fire")
		# The gun also fires whenever the aim stick is off centre, so both go up
		# before the hold. The last bullets need a moment to clear the frame.
		Input.action_release(&"aim_right")
		for _i in 60:
			await get_tree().physics_frame
		var aim: Vector3 = ship.get("_aim_direction")
		var turret_scene: PackedScene = load("res://entities/enemy/turret.tscn")
		var turret: Node3D = turret_scene.instantiate() as Node3D
		arena.add_child(turret)
		turret.global_position = ship.global_position + aim * 40.0
		# The radar only needs a contact in the group; a turret that shoots would
		# blink the ship through its i-frames and spoil the frame.
		turret.set_process(false)
		turret.set_physics_process(false)
		for _i in 2:
			await get_tree().physics_frame
		Input.action_press(&"missile")
		for _i in missile_frames:
			await get_tree().physics_frame
		Input.action_release(&"missile")
		for _i in 4:
			await get_tree().physics_frame
		# The hold is a salvo long, so the blink is cleared again on the last frame.
		ship.set("_invulnerable", 0.0)
		if visual != null:
			visual.visible = true

	# The death screen is a UI state, so the ship is killed outright here and the
	# countdown is captured on its first frame, where it still reads the full five.
	if death:
		Input.action_release(&"fire")
		Input.action_release(&"aim_right")
		# One lethal hit instead of a loop of 1-damage pokes: the loop stacked a
		# HitSpark per poke on the same spot, which is not what the death frame
		# looks like in play.
		ship.set("_invulnerable", 0.0)
		ship.take_damage(999)
		for _i in death_delay:
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
