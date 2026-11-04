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
## captures right after the salvo leaves, which is how the wing hardpoints and the
## fan of the salvo are reviewed. Add `--close` to hang the camera nearer the ship,
## since the game camera sits high enough that a missile is only a few pixels long.
## `--salvo-delay N` (default 4) waits N frames after the release, which is how the
## fan is read once the missiles have opened it out.
## `--lock N` is the same hold without the release: the rack is still loaded and the
## marks are up, which is how the lock reticle is reviewed. A short N catches the
## lock-in, a long one the settled spin. Add `--contacts N` to spread N turrets
## across the radar: the scan only reads against several, because the rack walks
## them nearest first and that order has to be visible.
## `--roll N` (with `--fighter 1`) starts a left barrel roll and captures N frames
## into it, which is how the slower turn-over and the roll's own side are
## reviewed. Add `--close` to read the hull coming over at the game camera's
## distance. `--zoom F` scales the close stand-off, so `--close 1 --zoom 0.4` fills
## the frame with the hull for a lighting or material check. `--nosmoke 1` hides
## the wake and `--noshadow 1` turns the sun's shadow map off, which is how a dark
## patch on the hull is told apart from the trail and from a cast shadow.
## `--out PATH` overrides the output file.
## `--settle N` waits N physics frames with the stick released before the capture,
## which is how a burst is told apart from a permanent trail.
## `--death 1` kills the ship right before the capture, which is how the death
## screen and its countdown are reviewed without waiting for a turret to land the
## last hit. `--death-delay N` waits N physics frames after the kill before
## capturing (default 2), which is how the explosion is reviewed mid-blast; 8 is
## about where the fireball opens.
## `--interceptor N --kill 1` ends the interceptor hold with a lethal hit, which is
## how an enemy death blast is reviewed.
## `--city 1` loads the city district instead of the planet, which is how the
## street grid, the towers and the night lighting are reviewed. Add `--nofire 1`
## to hold the trigger, since a vulcan stream washes the streets out and starts
## demolishing whatever it hits. `--ruin 1` collapses the tower nearest the ship
## right before the capture, which is how the rubble and the opened street are
## reviewed; `--chip N` leaves that tower N damage into its demolition instead, so
## the crack pass and the health bar can be seen mid-fight.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
const CITY_SCENE: String = "res://levels/city/city.tscn"
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
	var lock_frames: int = int(_argument("lock", "0"))
	var salvo_delay: int = int(_argument("salvo-delay", "4"))
	var roll_frames: int = int(_argument("roll", "0"))
	var close: bool = _argument("close", "0") == "1"
	var zoom: float = float(_argument("zoom", "1.0"))
	var no_smoke: bool = _argument("nosmoke", "0") == "1"
	var no_shadow: bool = _argument("noshadow", "0") == "1"
	var output_path: String = _argument("out", DEFAULT_OUTPUT)
	var death: bool = _argument("death", "0") == "1"
	var death_delay: int = int(_argument("death-delay", "2"))
	var kill_subject: bool = _argument("kill", "0") == "1"
	var no_fire: bool = _argument("nofire", "0") == "1"
	var ruin: bool = _argument("ruin", "0") == "1"
	var chip: int = int(_argument("chip", "0"))
	var city: bool = _argument("city", "0") == "1"

	var arena: Node = load(CITY_SCENE if city else ARENA_SCENE).instantiate()
	add_child(arena)

	await get_tree().physics_frame
	await get_tree().physics_frame

	# `--px F` / `--pz F` place the ship on the play plane before the warmup. A city
	# frame often needs a specific street: the sight line only passes through a
	# tower when the ship flies the half of the road nearest the camera-side block,
	# so the ghosting rule cannot be reviewed from a crossing.
	var place_x: String = _argument("px", "")
	var place_z: String = _argument("pz", "")
	if not place_x.is_empty() or not place_z.is_empty():
		var placed: Player = arena.get_node("%Player") as Player
		placed.global_position = Vector3(
			float(place_x) if not place_x.is_empty() else 0.0,
			0.0,
			float(place_z) if not place_z.is_empty() else 0.0
		)

	# Aiming right also holds the trigger, so `--nofire` has to leave the stick
	# alone: a city capture that streams bullets starts demolishing the street it
	# is meant to show, and the kill score hides the frame's subject.
	if not no_fire:
		Input.action_press(&"aim_right")
	if weapon != "1":
		Input.action_press("weapon_" + weapon)
		await get_tree().physics_frame
		Input.action_release("weapon_" + weapon)
	# The vulcan stream would hide the missiles leaving the wings, and it also
	# kills the turret the rack needs, so a missile capture flies unarmed.
	if missile_frames == 0 and lock_frames == 0 and not no_fire:
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

	# `--settle N` waits N physics frames with the stick released, which is how a
	# wake is told apart from a permanent trail: the exhaust and the vapour both
	# clear themselves a fraction of a second after the ship stops gaining speed.
	var settle_frames: int = int(_argument("settle", "0"))
	for _i in settle_frames:
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
	if missile_frames > 0 or lock_frames > 0:
		Input.action_release(&"fire")
		# The gun also fires whenever the aim stick is off centre, so both go up
		# before the hold. The last bullets need a moment to clear the frame.
		Input.action_release(&"aim_right")
		for _i in 60:
			await get_tree().physics_frame
		var aim: Vector3 = ship.get("_aim_direction")
		var turret_scene: PackedScene = load("res://entities/enemy/turret.tscn")
		# `--contacts N` spreads N turrets across the radar instead of one. The scan
		# is only reviewable against several contacts: the distances differ on
		# purpose, so nearest-first order and left-to-right order disagree and the
		# capture shows which one the rack follows. The default is the old single
		# contact at 40 units, straight down the aim.
		var contact_count: int = maxi(int(_argument("contacts", "1")), 1)
		# An explicit contact count makes the radar exact. The arena spawns one enemy
		# on load, and leaving it in turns a 3-contact 3/3/2 split into a 4-contact
		# 2/2/2 one. The default path is untouched, so the old single-contact capture
		# stays identical.
		if _argument("contacts", "") != "":
			var enemies: Node3D = arena.get_node("%Enemies") as Node3D
			for child in enemies.get_children():
				child.queue_free()
			for _i in 2:
				await get_tree().physics_frame
		var distances: Array[float] = [40.0, 30.0, 22.0, 34.0, 26.0, 18.0, 36.0, 20.0]
		var bearings: Array[float] = [0.0, 14.0, -14.0, 24.0, -24.0, 8.0, -8.0, 16.0]
		for index in contact_count:
			var turret: Node3D = turret_scene.instantiate() as Node3D
			arena.add_child(turret)
			var heading: Vector3 = aim.rotated(
				Vector3.UP, deg_to_rad(bearings[index % bearings.size()])
			)
			turret.global_position = (
				ship.global_position + heading * distances[index % distances.size()]
			)
			# The radar only needs a contact in the group; a turret that shoots would
			# blink the ship through its i-frames and spoil the frame.
			turret.set_process(false)
			turret.set_physics_process(false)
		for _i in 2:
			await get_tree().physics_frame
		Input.action_press(&"missile")
		for _i in (lock_frames if lock_frames > 0 else missile_frames):
			await get_tree().physics_frame
		# `--lock N` captures with the rack still loaded, which is the only way to
		# see the mark: a salvo capture releases and takes the reticles with it.
		if lock_frames == 0:
			Input.action_release(&"missile")
			# The fan is a few frames old at four: the missiles have cleared the wings
			# but the guidance has not bent them back onto the contact yet.
			for _i in salvo_delay:
				await get_tree().physics_frame
		# The hold is a salvo long, so the blink is cleared again on the last frame.
		ship.set("_invulnerable", 0.0)
		if visual != null:
			visual.visible = true

	# The interceptor is a moving subject, so it is spawned and flown for a fixed
	# number of frames instead of being placed: `--interceptor N` is the clock. A
	# short hold catches it on the way in; a long one catches the launch, because
	# the reload, the warning and the salvo together take about three seconds.
	var interceptor_frames: int = int(_argument("interceptor", "0"))
	var interceptor: FighterEnemy = null
	if interceptor_frames > 0:
		Input.action_release(&"fire")
		Input.action_release(&"aim_right")
		for _i in 20:
			await get_tree().physics_frame
		# One subject per capture: the streamer would otherwise drop a turret into
		# the same frame.
		var enemies: Node3D = arena.get_node("%Enemies") as Node3D
		for child in enemies.get_children():
			child.queue_free()
		arena.set("_spawn_timer", 9999.0)
		for _i in 2:
			await get_tree().physics_frame
		var forward: Vector3 = ship.get("_heading") as Vector3
		var interceptor_scene: PackedScene = load(
			"res://entities/enemy/fighter_enemy.tscn"
		)
		interceptor = interceptor_scene.instantiate() as FighterEnemy
		enemies.add_child(interceptor)
		interceptor.setup_spawn(ship.global_position + forward * 24.0)
		for _i in interceptor_frames:
			await get_tree().physics_frame
		# A missile that lands mid-hold would blink the hull out of the frame.
		ship.set("_invulnerable", 0.0)
		if visual != null:
			visual.visible = true

	# `--kill 1` ends the hold with a lethal hit, so the blast is reviewed on an
	# enemy: the same explosion the ship leaves, with the lighter camera kick.
	if kill_subject and is_instance_valid(interceptor):
		interceptor.take_damage(999)
		for _i in death_delay:
			await get_tree().physics_frame

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

	# A demolition is a decision, not a frame: `--ruin 1` takes a whole tower down
	# so the rubble and the street it opens are reviewed, and `--chip N` leaves one
	# N damage into its demolition so the crack pass and the health bar show. The
	# gun is released first, or the stream finishes the job on its own.
	if ruin or chip > 0:
		Input.action_release(&"fire")
		Input.action_release(&"aim_right")
		var nearest: Building = _nearest_building(arena, ship.global_position)
		if nearest != null:
			nearest.take_damage(Building.MAX_HP if ruin else chip)
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


## The tower nearest a point, planar distance. Only the city has buildings, so a
## planet capture with `--ruin` simply finds nothing.
func _nearest_building(level: Node, point: Vector3) -> Building:
	if not level.has_method("buildings"):
		return null
	var nearest: Building = null
	var best: float = INF
	for node in level.call("buildings") as Array:
		var building: Building = node as Building
		if building == null:
			continue
		var distance: float = Vector2(
			building.global_position.x - point.x,
			building.global_position.z - point.z
		).length()
		if distance < best:
			best = distance
			nearest = building
	return nearest


func _argument(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var flag: String = "--" + name
	for index in args.size():
		if args[index] == flag and index + 1 < args.size():
			return args[index + 1]
	return fallback
