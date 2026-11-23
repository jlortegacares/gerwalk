class_name SmokeSuite
extends Node
## Shared harness for the smoke suite.
##
## Everything that is not a test lives here: the world it boots, the assertions,
## the spawn and scan helpers, and the scratch paths. A domain suite is a child of
## the runner, gets the same world references injected, and shares the failures
## array, so a split run reports exactly like the single file did.
##
## The reason the harness is a class instead of a bag of statics: a suite has to
## keep running while the world it tests is frozen (the pause menu stops the tree),
## so it must be a node in the tree, and it must see the same mutable world.


func _ready() -> void:
	# A suite is added as a child of the runner, so it inherits its
	# `PROCESS_MODE_ALWAYS` and keeps running while the world it tests is frozen.
	GlobalEventBus.player_died.connect(func() -> void: _died_count += 1)


## Hand a suite the one world the whole run shares: the arena, the ship, and the
## failures array (the same instance, so appends are visible to `_report`).
func _install_suite(suite: SmokeSuite) -> SmokeSuite:
	suite._arena = _arena
	suite._player = _player
	suite._failures = _failures
	add_child(suite)
	return suite


const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
## Every settings round trip uses this file, never the real `user://settings.cfg`:
## a test must not overwrite the choices of whoever runs it.
const TEST_SETTINGS: String = "user://test-settings.cfg"
## The same rule for the pilot record: the suite runs at level 1 and must never
## earn (or erase) levels on the machine that runs it.
const TEST_PROGRESS: String = "user://test-progress.cfg"
## And for the save cards: six scratch cards under their own directory, plus a
## scratch copy of the single save the migration imports from.
const TEST_SAVES: String = "user://test-saves"
const TEST_LEGACY: String = "user://test-saves/legacy.cfg"

var _failures: Array[String] = []
var _arena: Arena = null
var _player: Player = null
var _died_count: int = 0

## The suite is one long run, and only the death test may end it. A stray shot that
## lands while a check has cleared the frames would kill the ship, stop the world for
## every later check, and hand the run to the death screen's countdown -- whose reload
## restarts the suite in the middle and reports the old run's tail from a fresh boot.
## A test that needs a vulnerable hull goes back under this sentinel when it is done.
const SUITE_INVULNERABLE: float = 1.0e9


## Puts the hull back at full health under the sentinel's frames, so the run keeps
## going after a check that had to take a real hit.
func _park_ship() -> void:
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", SUITE_INVULNERABLE)


## A governor that is not fed by anything but the test.
func _fresh_governor() -> Node:
	var governor: Node = load("res://common/render_scale.gd").new()
	get_tree().current_scene.add_child(governor)
	governor.set_process(false)
	governor.set("enabled", true)
	return governor


## Feeds `seconds` of a machine `times` slower than this one. `spike_every` makes
## every Nth frame four times as expensive, which is how a hitch is modelled.
func _simulate(governor: Node, times: float, seconds: float, spike_every: int = 0) -> void:
	var interval: float = 1000.0 / 60.0
	var elapsed: float = 0.0
	var frame: int = 0
	while elapsed < seconds * 1000.0:
		var width: int = RenderScale.render_width_for(
			Vector2i(1280, 720), governor.call("current_factor")
		)
		var height: int = int(float(width) * 720.0 / 1280.0)
		var work: float = 7.8 * times * (float(width * height) / (1280.0 * 720.0))
		if spike_every > 0 and frame % spike_every == spike_every - 1:
			work *= 4.0
		frame += 1
		# Vsync rounds a frame up to a whole refresh interval, and never lets it read
		# faster than one.
		var observed: float = interval * maxf(1.0, ceil(work / interval))
		governor.call("feed", observed)
		elapsed += observed


func _pressed_swatch(row: HBoxContainer) -> Button:
	for child in row.get_children():
		var button: Button = child as Button
		if button != null and button.button_pressed:
			return button
	return null


## Every surface colour under `root` whose material carries the name prefix. The
## file suffixes the name per mesh ("Aircraft BASE color.014"), so the match is on
## the prefix, the same rule the paint pass uses. The canopy panels are skipped:
## the cover wears a hull-family material and belongs to the canopy pass. The
## section of the forward fuselage behind the nose keeps the hull family, so it
## counts here as hull.
func _material_colors(root: Node, prefix: String) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if _is_canopy_panel(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material == null:
				continue
			if String(material.resource_name).begins_with(prefix):
				colors.append(material.albedo_color)
	return colors


## The colour of every canopy panel, found the same way the paint pass finds them.
func _canopy_colors(root: Node) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_canopy_panel(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material != null:
				colors.append(material.albedo_color)
	return colors


## Only the cover panel, which is the one that ships wearing a hull material.
func _canopy_cover_colors(root: Node) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var attachment: BoneAttachment3D = mesh.get_parent() as BoneAttachment3D
		if attachment == null or attachment.bone_name != "Bone.CanopyCover":
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material != null:
				colors.append(material.albedo_color)
	return colors


func _is_canopy_panel(mesh: MeshInstance3D) -> bool:
	var attachment: BoneAttachment3D = mesh.get_parent() as BoneAttachment3D
	if attachment == null or not PlayerModel.CANOPY_BONES.has(attachment.bone_name):
		return false
	var lower: String = String(mesh.name).to_lower()
	return lower.contains(PlayerModel.CANOPY_MESH) and not lower.contains("rib")


## The cone half of the forward fuselage sheet, which the split renames to the
## nose material. The section under the canopy keeps the hull name.
func _nose_colors(root: Node) -> Array[Color]:
	return _nose_family_colors(root, PlayerModel.NOSE_MATERIAL)


## The half of the forward fuselage sheet that stays hull: the section behind the
## canopy, which the nose colour must not swallow.
func _nose_hull_colors(root: Node) -> Array[Color]:
	return _nose_family_colors(root, PlayerModel.HULL_MATERIAL)


func _nose_family_colors(root: Node, prefix: String) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_nose_mesh(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material == null:
				continue
			if String(material.resource_name).begins_with(prefix):
				colors.append(material.albedo_color)
	return colors


## The forward-most triangle centroid of the nose surfaces wearing `material_name`,
## in the mesh's own space, and the furthest back one. The split is a cut along the
## fuselage, so the two halves must not overlap on that axis.
func _nose_surface_span(root: Node, material_name: String) -> Vector2:
	var low: float = INF
	var high: float = -INF
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_nose_mesh(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material == null:
				continue
			if not String(material.resource_name).begins_with(material_name):
				continue
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for corner in range(0, indices.size(), 3):
				var centroid: Vector3 = (
					vertices[indices[corner]]
					+ vertices[indices[corner + 1]]
					+ vertices[indices[corner + 2]]
				) / 3.0
				low = minf(low, centroid.z)
				high = maxf(high, centroid.z)
	return Vector2(low, high)


## The canopy's leading edge in the forward fuselage's space, measured from the
## panels rather than assumed, so the test checks the rule the paint pass follows.
func _canopy_front(root: Node) -> float:
	var nose: MeshInstance3D = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if _is_nose_mesh(mesh):
			nose = mesh
			break
	if nose == null:
		return INF
	var to_mesh: Transform3D = nose.global_transform.affine_inverse()
	var front: float = -INF
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var panel: MeshInstance3D = node as MeshInstance3D
		if not _is_canopy_panel(panel):
			continue
		var local: Transform3D = to_mesh * panel.global_transform
		for surface in panel.mesh.get_surface_count():
			var vertices: PackedVector3Array = (
				panel.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			)
			for point in vertices:
				front = maxf(front, (local * point).z)
	return front


## The lines that cross the nose: they share the mesh with the cone, so they are
## the check that the nose colour does not swallow them.
func _nose_line_colors(root: Node) -> Array[Color]:
	var colors: Array[Color] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_nose_mesh(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if material == null:
				continue
			if String(material.resource_name).begins_with(PlayerModel.LINE_MATERIAL):
				colors.append(material.albedo_color)
	return colors


func _is_nose_mesh(mesh: MeshInstance3D) -> bool:
	return String(mesh.name).to_lower().contains(PlayerModel.NOSE_MESH)


func _all_colors_are(colors: Array[Color], expected: Color) -> bool:
	for color in colors:
		if not color.is_equal_approx(expected):
			return false
	return true


## The file's own lines carry alpha zero, so comparing them to a picked colour has
## to ignore alpha.
func _all_colors_match_rgb(colors: Array[Color], expected: Color) -> bool:
	for color in colors:
		if (
			not is_equal_approx(color.r, expected.r)
			or not is_equal_approx(color.g, expected.g)
			or not is_equal_approx(color.b, expected.b)
		):
			return false
	return true


func _has_label_text(parent: Node, text: String) -> bool:
	for child in parent.get_children():
		var label: Label = child as Label
		if label != null and label.text == text:
			return true
	return false


## The controls table is three cells per row, so a row is found by the name in its
## first cell. A row the player cannot rearrange answers null, and so does the
## weapon row, whose third cell is a pair of buttons rather than one.
func _control_button(grid: GridContainer, action: String) -> Button:
	for index: int in range(0, grid.get_child_count(), 3):
		var label: Label = grid.get_child(index) as Label
		if label == null or label.text != action:
			continue
		return grid.get_child(index + 2) as Button
	return null


## Six scratch cards and their scratch legacy file, removed without ever touching
## the player's real memory card.
func _clean_saves() -> void:
	for slot: int in range(1, SaveSlots.SLOT_COUNT + 1):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(SaveSlots.path_for(slot))
		)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LEGACY))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("%s.imported" % TEST_LEGACY))


## One menu at a time, and it is a child of the HUD because the HUD owns the run.
func _pause_overlay(hud: CanvasLayer) -> MainMenu:
	for child in hud.get_children():
		if child is MainMenu:
			return child
	return null


func _release_all_input() -> void:
	for action: StringName in [
		&"move_left", &"move_right", &"move_up", &"move_down",
		&"aim_left", &"aim_right", &"aim_up", &"aim_down",
		&"fire", &"boost", &"dash",
	]:
		Input.action_release(action)


## Puts the dash gesture back to a known state: no cooldown, no armed tap, and a
## released stick, so the next press is a rising edge.
func _reset_dash_gesture() -> void:
	_release_all_input()
	_player.velocity = Vector3.ZERO
	_player.set("_dash_cooldown", 0.0)
	_player.set("_dash_time", 0.0)
	# The spin clock outlives the step, so it has to be cleared too or the next
	# check would start mid-roll and read the previous roll's side.
	_player.set("_roll_anim_time", 0.0)
	_player.set("_tap_timer", 0.0)
	_player.set("_move_engaged", false)
	await get_tree().physics_frame


## The strongest dense point and the thinnest *visible* bank on a coarse grid outside
## the opening clearing. A "thin gap" below `VISUAL_MIN_DENSITY` would be open sky,
## and a lock test against open sky proves nothing, so the fringe has to be cloud the
## player can actually see. Scanning is what keeps the test honest about the tuning.
func _find_cloud_point(field: CloudField, want_dense: bool) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_score: float = -INF
	for z in range(160, 521, 10):
		for x in range(-520, 521, 10):
			var point: Vector3 = Vector3(float(x), 0.0, float(z))
			var density: float = field.density_at(point)
			if want_dense and density < CloudField.DENSE_THRESHOLD:
				continue
			if not want_dense and density >= CloudField.DENSE_THRESHOLD:
				continue
			if not want_dense and density < CloudField.VISUAL_MIN_DENSITY:
				continue
			var score: float = density if want_dense else -density
			if score > best_score:
				best_score = score
				best = point
	return best


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _unique_count(values: Array) -> int:
	var seen: Array = []
	for value in values:
		if not seen.has(value):
			seen.append(value)
	return seen.size()


## The tally each lock box shows, sorted. That text is the only thing on screen
## that promises how many missiles a contact will take, so the smoke test reads it
## the way the player does.
func _tally_texts() -> Array[String]:
	var texts: Array[String] = []
	for node in get_tree().get_nodes_in_group(&"lock_reticle"):
		var reticle: LockReticle = node as LockReticle
		var label: Label3D = reticle.get_node_or_null(^"LockNumber") as Label3D
		texts.append("?" if label == null else label.text)
	texts.sort()
	return texts


func _mesh_parts(node: Node) -> int:
	var total: int = 0
	for child in node.get_children():
		if child is MeshInstance3D:
			total += 1
		total += _mesh_parts(child)
	return total


func _spawn_enemy(position: Vector3) -> Enemy:
	var scene: PackedScene = load("res://entities/enemy/turret.tscn")
	if scene == null:
		return null
	var enemy: Enemy = scene.instantiate() as Enemy
	_arena.add_child(enemy)
	enemy.global_position = position
	return enemy


func _spawn_enemy_bullet(position: Vector3) -> Projectile:
	var scene: PackedScene = load("res://combat/projectile.tscn")
	var bullet: Projectile = scene.instantiate() as Projectile
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = position
	bullet.setup(Vector3(1.0, 0.0, 0.0), 20.0, Projectile.Team.ENEMY, 1)
	return bullet


## A player shot, built the way the vulcan builds one: same scene, same team, same
## layer the interception check depends on.
func _spawn_player_bullet(position: Vector3, direction: Vector3) -> Projectile:
	var scene: PackedScene = load("res://combat/projectile.tscn")
	var bullet: Projectile = scene.instantiate() as Projectile
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = position
	bullet.setup(direction, 40.0, Projectile.Team.PLAYER, 1)
	return bullet


## A guided enemy shot, built the way the launcher builds one, so the decoy check
## exercises the same projectile contract the enemy actually fires.
func _spawn_enemy_missile(position: Vector3, target: Node3D) -> Projectile:
	var scene: PackedScene = load("res://combat/projectile.tscn")
	var missile: Projectile = scene.instantiate() as Projectile
	get_tree().current_scene.add_child(missile)
	missile.global_position = position
	var direction: Vector3 = target.global_position - position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = Vector3.FORWARD
	missile.setup(
		direction.normalized(),
		MissileEnemy.MISSILE_SPEED,
		Projectile.Team.ENEMY,
		MissileEnemy.MISSILE_DAMAGE,
		MissileEnemy.MISSILE_SIZE,
		target,
		MissileEnemy.MISSILE_TURN_RATE,
		Color(0.0, 0.0, 0.0, 0.0),
		MissileEnemy.MISSILE_LIFETIME,
		Projectile.Style.MISSILE
	)
	return missile


func _spawn_missile_enemy(position: Vector3) -> MissileEnemy:
	var scene: PackedScene = load("res://entities/enemy/missile_enemy.tscn")
	if scene == null:
		return null
	var enemy: MissileEnemy = scene.instantiate() as MissileEnemy
	_arena.add_child(enemy)
	enemy.global_position = position
	return enemy


func _spawn_fighter_enemy(position: Vector3) -> FighterEnemy:
	var scene: PackedScene = load("res://entities/enemy/fighter_enemy.tscn")
	if scene == null:
		return null
	var enemy: FighterEnemy = scene.instantiate() as FighterEnemy
	_arena.add_child(enemy)
	enemy.setup_spawn(position)
	return enemy


func _spawn_turret(position: Vector3) -> Enemy:
	var scene: PackedScene = load("res://entities/enemy/turret.tscn")
	if scene == null:
		return null
	var enemy: Enemy = scene.instantiate() as Enemy
	_arena.add_child(enemy)
	enemy.setup_spawn(position)
	return enemy


## Blasts live in the scene root, not under the enemy, so they outlive the hull.
## Counting them is how a death is told apart from a silent `queue_free`.
func _death_blasts() -> Array[ShipExplosion]:
	var found: Array[ShipExplosion] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return found
	for child in scene.get_children():
		if child is ShipExplosion:
			found.append(child)
	return found


## Impact effects also live in the scene root, not under the shot that produced them,
## so counting them is how a missile detonation is told apart from a bullet spark.
func _impact_waves() -> Array[ShockWave]:
	var found: Array[ShockWave] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return found
	for child in scene.get_children():
		if child is ShockWave:
			found.append(child)
	return found


## The death wave rides inside the death blast, so it frees with it. Looking for it
## as a child is what tells "the ring was added" apart from "some ring is around".
func _wave_of(blast: ShipExplosion) -> ShockWave:
	for child in blast.get_children():
		if child is ShockWave:
			return child
	return null


func _hit_sparks() -> Array[HitSpark]:
	var found: Array[HitSpark] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return found
	for child in scene.get_children():
		if child is HitSpark:
			found.append(child)
	return found


func _player_projectiles() -> Array[Projectile]:
	var found: Array[Projectile] = []
	for child in get_tree().current_scene.get_children():
		var bullet: Projectile = child as Projectile
		# A queued node is gone at the end of the frame but still a child now; a
		# count that included it would read a shot the test already cleared.
		if bullet == null or bullet.is_queued_for_deletion():
			continue
		if int(bullet.get("_team")) == Projectile.Team.PLAYER:
			found.append(bullet)
	return found


func _aim() -> Vector3:
	var aim: Vector3 = _player.get("_aim_direction")
	return aim


func _planet_offset(planet: Node3D) -> float:
	var offset: Vector3 = planet.global_position - _player.global_position
	return Vector2(offset.x, offset.z).length()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _flat_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


## Airspeed across the nose: positive to the right of where the ship points.
func _sideways_airspeed() -> float:
	var heading: Vector3 = _player.get("_heading")
	var right: Vector3 = Vector3(-heading.z, 0.0, heading.x)
	return _player.velocity.dot(right)


## The fighter jink's push split on the airframe: x along the nose, y to its
## right. `_roll_velocity` is exactly the push applied on this frame, so the pair
## says which way the step goes with the steady flight left out.
func _jink_push() -> Vector2:
	var heading: Vector3 = _player.get("_heading")
	var right: Vector3 = Vector3(-heading.z, 0.0, heading.x)
	var push: Vector3 = _player.get("_roll_velocity")
	return Vector2(push.dot(heading), push.dot(right))


func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group(&"enemy"):
		enemy.queue_free()


func _clear_projectiles() -> void:
	for child in get_tree().current_scene.get_children():
		if child is Projectile:
			child.queue_free()


func _count_projectiles(team: int) -> int:
	var total: int = 0
	for child in get_tree().current_scene.get_children():
		if child is Projectile and int(child.get("_team")) == team:
			total += 1
	return total


## The RMS of a committed WAV in decibels. The mix table is checked against the files
## that ship, not against the table's own arithmetic: peak normalisation means two
## files at the same peak can still differ by 15 dB of loudness, and that gap is
## exactly what the mixer exists to close.
func _rms_db(path: String) -> float:
	var wav: Dictionary = _wav_pcm(path)
	if wav.is_empty():
		return -120.0
	var pcm: PackedByteArray = wav["data"]
	var frames: int = pcm.size() >> 1
	if frames == 0:
		return -120.0
	var total: float = 0.0
	for i in frames:
		var sample: float = float(pcm.decode_s16(i * 2)) / 32768.0
		total += sample * sample
	var rms: float = sqrt(total / float(frames))
	return 20.0 * log(maxf(rms, 0.000001)) / log(10.0)


## Share of a committed WAV's energy above `cutoff` Hz, as a one-pole high-pass.
## The palette is synthesized, so the only question is whether the bright band is
## there at all, not what its exact shape is.
##
## The file is read from disk on purpose: Godot imports these WAVs as QOA, so the
## resource's `data` is not the PCM that ships and cannot be decoded as samples.
func _high_band_energy(path: String, cutoff: float) -> float:
	var wav: Dictionary = _wav_pcm(path)
	if wav.is_empty():
		return 0.0
	var pcm: PackedByteArray = wav["data"]
	var rate: float = float(wav["rate"])
	var alpha: float = 1.0 / (1.0 + TAU * cutoff / rate)
	var previous_input: float = 0.0
	var previous_output: float = 0.0
	var high: float = 0.0
	var total: float = 0.0
	var frames: int = pcm.size() >> 1
	for i in frames:
		var sample: float = float(pcm.decode_s16(i * 2)) / 32768.0
		var filtered: float = alpha * (previous_output + sample - previous_input)
		previous_input = sample
		previous_output = filtered
		high += filtered * filtered
		total += sample * sample
	return high / total if total > 0.0 else 0.0


## The 16-bit mono PCM of a RIFF/WAVE file, with its sample rate.
func _wav_pcm(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_buffer(4).get_string_from_ascii() != "RIFF":
		return {}
	file.get_32()
	if file.get_buffer(4).get_string_from_ascii() != "WAVE":
		return {}
	var rate: int = 44100
	while file.get_position() + 8 <= file.get_length():
		var chunk: String = file.get_buffer(4).get_string_from_ascii()
		var size: int = file.get_32()
		if chunk == "fmt ":
			file.get_16()
			file.get_16()
			rate = file.get_32()
			file.seek(file.get_position() + size - 8 + (size & 1))
		elif chunk == "data":
			return {"rate": rate, "data": file.get_buffer(size)}
		else:
			file.seek(file.get_position() + size + (size & 1))
	return {}


## The first thing a world-layer ray meets, or null. Buildings are the only bodies
## on that layer, which is why the mask is the whole test.
func _world_hit(from: Vector3, to: Vector3) -> Object:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, 1 << Building.LAYER_WORLD
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(query)
	return hit.get("collider") as Object


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
		return
	_failures.append(description)
	printerr("  FAIL  ", description)


