extends Node
## Headless smoke test for the 3D combat prototype.
## Run: ./run.sh --headless tests/smoke_test.tscn
## Exits with code 1 if any assertion fails.

const ARENA_SCENE: String = "res://levels/arena/arena.tscn"
## Every settings round trip uses this file, never the real `user://settings.cfg`:
## a test must not overwrite the choices of whoever runs it.
const TEST_SETTINGS: String = "user://test-settings.cfg"

var _failures: Array[String] = []
var _arena: Arena = null
var _player: Player = null
var _died_count: int = 0


func _ready() -> void:
	GlobalEventBus.player_died.connect(func() -> void: _died_count += 1)

	_arena = load(ARENA_SCENE).instantiate()
	add_child(_arena)

	await get_tree().physics_frame
	await get_tree().physics_frame

	_player = _arena.get_node("%Player")
	_check(_player != null, "arena exposes a Player")
	_check(_player is CharacterBody3D, "player is a CharacterBody3D")

	_test_player_is_centered()
	await _test_main_menu()
	await _test_livery_paint()
	await _test_movement()
	await _test_firing()
	await _test_enemy_patterns()
	await _test_enemies_roam_the_planet()
	await _test_missile_enemy()
	await _test_afterburner()
	await _test_exhaust_trail()
	_test_airframe_lighting()
	await _test_radar()
	await _test_arsenal()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_travel_is_unbounded()
	await _test_planet_rolls_with_the_player()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_maneuverability()
	await _test_double_tap_dash()
	await _test_transformation()
	await _test_gerwalk_silhouette()

	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	await _test_damage_and_iframes()
	await _test_death()

	_report()


func _test_main_menu() -> void:
	var scene: PackedScene = load("res://ui/menu/main_menu.tscn")
	_check(scene != null, "the boot menu scene loads")
	if scene == null:
		return

	# The menu writes every setting it edits, so it is handed a scratch file before
	# it enters the tree: a swatch click must never touch the real settings.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	# A saved livery has to come back selected, not merely applied.
	GameSettings.save_livery(
		MainMenu.PALETTE[4],
		MainMenu.PALETTE[5],
		MainMenu.PALETTE[6],
		MainMenu.PALETTE[7],
		MainMenu.PALETTE[8],
		TEST_SETTINGS
	)

	var menu: MainMenu = scene.instantiate() as MainMenu
	menu.settings_path = TEST_SETTINGS
	add_child(menu)
	await get_tree().process_frame

	var start_button: Button = menu.get_node("%StartButton") as Button
	var options_button: Button = menu.get_node("%OptionsButton") as Button
	var options: Control = menu.get_node("%Options") as Control
	var back_button: Button = menu.get_node("%BackButton") as Button
	var hull_row: HBoxContainer = menu.get_node("%HullRow") as HBoxContainer
	var nose_row: HBoxContainer = menu.get_node("%NoseRow") as HBoxContainer
	var trim_row: HBoxContainer = menu.get_node("%TrimRow") as HBoxContainer
	var canopy_row: HBoxContainer = menu.get_node("%CanopyRow") as HBoxContainer
	var lines_row: HBoxContainer = menu.get_node("%LinesRow") as HBoxContainer
	var preview: LiveryPreview = menu.get_node("%Preview") as LiveryPreview
	_check(start_button != null, "the menu offers a start button")
	_check(options_button != null, "the menu offers an options button")
	_check(options != null, "the menu carries an options panel")
	_check(
		ResourceLoader.exists(MainMenu.ARENA_SCENE),
		"the start button points at a scene that exists"
	)
	if options == null:
		menu.queue_free()
		return

	_check(not options.visible, "the options panel starts hidden")
	_check(preview != null, "the panel carries a live livery preview")

	options_button.pressed.emit()
	await get_tree().process_frame
	_check(options.visible, "the options button opens the panel")

	# The controls reference is the second half of the panel, so a row has to be
	# there and it has to name a control the build really has.
	var grid: GridContainer = options.get_node(
		"Center/Panel/Margin/Body/Columns/Right/Grid"
	) as GridContainer
	_check(grid != null, "the options panel lists the controls")
	if grid != null:
		_check(
			grid.get_child_count() == 22,
			"every control row has an action and its keys (%d cells)"
			% grid.get_child_count()
		)
		_check(
			_has_label_text(grid, "Decoy"),
			"the controls reference names the decoy"
		)

	_check(
		hull_row != null
		and nose_row != null
		and trim_row != null
		and canopy_row != null
		and lines_row != null,
		"the panel carries all five colour rows"
	)
	if (
		hull_row != null
		and nose_row != null
		and trim_row != null
		and canopy_row != null
		and lines_row != null
	):
		_check(
			hull_row.get_child_count() == MainMenu.PALETTE.size(),
			"the hull row offers the whole palette (%d swatches)"
			% hull_row.get_child_count()
		)
		for row in [nose_row, trim_row, canopy_row, lines_row]:
			_check(
				(row as HBoxContainer).get_child_count() == MainMenu.PALETTE.size(),
				"every colour row offers the whole palette"
			)
		_check(
			_pressed_swatch(hull_row) == hull_row.get_child(4),
			"the saved hull comes back selected"
		)
		_check(
			_pressed_swatch(nose_row) == nose_row.get_child(8),
			"the saved nose comes back selected"
		)
		_check(
			_pressed_swatch(trim_row) == trim_row.get_child(5),
			"the saved stripe comes back selected"
		)
		_check(
			_pressed_swatch(canopy_row) == canopy_row.get_child(6),
			"the saved canopy comes back selected"
		)
		_check(
			_pressed_swatch(lines_row) == lines_row.get_child(7),
			"the saved lines come back selected"
		)
		var hull_button: Button = hull_row.get_child(0) as Button
		_check(
			hull_button != null and hull_button.button_group != null,
			"a colour row is one exclusive choice, not a pile of toggles"
		)

		# A click has to reach the file, because that is what the next launch and
		# the ship in the arena both read.
		(hull_row.get_child(2) as Button).pressed.emit()
		_check(
			GameSettings.load_hull(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[2]
			),
			"picking a hull swatch is saved"
		)
		(nose_row.get_child(6) as Button).pressed.emit()
		_check(
			GameSettings.load_nose(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[6]
			),
			"picking a nose swatch is saved"
		)
		(trim_row.get_child(8) as Button).pressed.emit()
		_check(
			GameSettings.load_trim(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[8]
			),
			"picking a stripe swatch is saved"
		)
		(canopy_row.get_child(3) as Button).pressed.emit()
		_check(
			GameSettings.load_canopy(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[3]
			),
			"picking a canopy swatch is saved"
		)
		(lines_row.get_child(1) as Button).pressed.emit()
		_check(
			GameSettings.load_lines(TEST_SETTINGS).is_equal_approx(
				MainMenu.PALETTE[1]
			),
			"picking a line swatch is saved"
		)

	back_button.pressed.emit()
	await get_tree().process_frame
	_check(not options.visible, "the back button closes the panel")

	# Both settings share one file, so neither save may erase the other.
	GameSettings.save_fullscreen(true, TEST_SETTINGS)
	GameSettings.save_livery(
		MainMenu.PALETTE[2],
		MainMenu.PALETTE[8],
		MainMenu.PALETTE[3],
		MainMenu.PALETTE[1],
		MainMenu.PALETTE[6],
		TEST_SETTINGS
	)
	_check(
		GameSettings.load_fullscreen(TEST_SETTINGS),
		"the fullscreen choice is remembered"
	)
	_check(
		GameSettings.load_hull(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[2]),
		"and saving it keeps the hull"
	)
	_check(
		GameSettings.load_trim(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[8]),
		"and the stripe"
	)
	_check(
		GameSettings.load_canopy(TEST_SETTINGS).is_equal_approx(
			MainMenu.PALETTE[3]
		),
		"and the canopy"
	)
	_check(
		GameSettings.load_lines(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[1]),
		"and the lines"
	)
	_check(
		GameSettings.load_nose(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[6]),
		"and the nose"
	)
	GameSettings.save_fullscreen(false, TEST_SETTINGS)
	_check(
		not GameSettings.load_fullscreen(TEST_SETTINGS),
		"and the choice can be turned back off"
	)
	_check(
		GameSettings.load_lines(TEST_SETTINGS).is_equal_approx(MainMenu.PALETTE[1]),
		"turning it off keeps the livery"
	)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	_check(
		GameSettings.load_hull(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_HULL
		),
		"a missing file falls back to the factory hull"
	)
	_check(
		GameSettings.load_trim(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_TRIM
		),
		"a missing file falls back to the factory stripe"
	)
	_check(
		GameSettings.load_canopy(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_CANOPY
		),
		"a missing file falls back to the factory canopy"
	)
	_check(
		GameSettings.load_lines(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_LINES
		),
		"a missing file falls back to the factory lines"
	)
	_check(
		GameSettings.load_nose(TEST_SETTINGS).is_equal_approx(
			GameSettings.DEFAULT_NOSE
		),
		"a missing file falls back to the factory nose"
	)

	menu.queue_free()
	await get_tree().process_frame


## The livery has to land on the right surfaces and nowhere else: the hull is one
## family of materials, the stripe another, the lines a third, the nose its own,
## and the canopy is found by the bones it hangs from. The rest of the airframe is
## what makes it look like an aircraft instead of a painted brick.
func _test_livery_paint() -> void:
	var hull: Color = Color(0.85, 0.12, 0.10)
	var trim: Color = Color(0.10, 0.75, 0.35)
	var canopy: Color = Color(0.95, 0.45, 0.05)
	var lines: Color = Color(0.90, 0.10, 0.80)
	var nose: Color = Color(0.10, 0.25, 0.95)

	var model: PlayerModel = PlayerModel.new()
	add_child(model)
	model.set_livery(hull, trim, canopy, lines, nose)
	_check(model.build(), "the airframe builds wearing a livery")

	var hulls: Array[Color] = _material_colors(model, PlayerModel.HULL_MATERIAL)
	var trims: Array[Color] = _material_colors(model, PlayerModel.TRIM_MATERIAL)
	var dark: Array[Color] = _material_colors(model, PlayerModel.LINE_MATERIAL)
	var glass: Array[Color] = _canopy_colors(model)
	var cones: Array[Color] = _nose_colors(model)
	_check(hulls.size() > 0, "the hull sheets are painted (%d surfaces)" % hulls.size())
	_check(trims.size() > 0, "the stripe is painted (%d surfaces)" % trims.size())
	_check(dark.size() > 0, "the black lines are painted (%d surfaces)" % dark.size())
	_check(glass.size() > 0, "the canopy glass is painted (%d surfaces)" % glass.size())
	_check(cones.size() > 0, "the nose cone is painted (%d surfaces)" % cones.size())
	_check(_all_colors_are(hulls, hull), "every hull surface takes the hull colour")
	_check(_all_colors_are(trims, trim), "every stripe surface takes the stripe colour")
	_check(_all_colors_are(dark, lines), "every line surface takes the line colour")
	_check(_all_colors_are(glass, canopy), "every canopy panel takes the canopy colour")
	_check(_all_colors_are(cones, nose), "every nose surface takes the nose colour")

	# The canopy cover wears a hull-family material, so the hull pass must leave it
	# alone: otherwise the cockpit ends up painted with the hull colour.
	var cover: Array[Color] = _canopy_cover_colors(model)
	_check(cover.size() > 0, "the canopy cover is found (%d surfaces)" % cover.size())
	_check(
		_all_colors_are(cover, canopy),
		"the hull pass does not paint the canopy cover"
	)

	# The cone shares one hull sheet with the fuselage under the cockpit, so the
	# sheet is cut at the canopy: the front half takes the nose colour and the
	# section behind it stays hull. The lines that cross the nose are still lines.
	_check(
		_all_colors_are(cones, nose) and not _all_colors_are(cones, hull),
		"the hull pass does not paint the nose"
	)
	var under_canopy: Array[Color] = _nose_hull_colors(model)
	_check(
		under_canopy.size() > 0,
		"the fuselage under the canopy is still hull (%d surfaces)" % under_canopy.size()
	)
	_check(
		_all_colors_are(under_canopy, hull),
		"the section behind the nose takes the hull colour"
	)
	var cut: float = _canopy_front(model) + PlayerModel.NOSE_GAP
	var cone_span: Vector2 = _nose_surface_span(model, PlayerModel.NOSE_MATERIAL)
	var aft_span: Vector2 = _nose_surface_span(model, PlayerModel.HULL_MATERIAL)
	_check(
		cone_span.x >= cut - 0.01,
		"the nose paint starts a gap ahead of the canopy (%.2f vs %.2f)" % [cone_span.x, cut]
	)
	_check(
		aft_span.y <= cut + 0.01,
		"and the hull keeps the lip in front of it (%.2f)" % aft_span.y
	)
	_check(
		cone_span.y > aft_span.y,
		"the nose half carries the tip (%.2f vs %.2f)" % [cone_span.y, aft_span.y]
	)
	var nose_lines: Array[Color] = _nose_line_colors(model)
	_check(nose_lines.size() > 0, "the nose keeps its panel lines (%d surfaces)" % nose_lines.size())
	_check(
		_all_colors_are(nose_lines, lines),
		"the lines across the nose still take the line colour"
	)

	# A live repaint is what the options preview does on every click, so it has to
	# reach surfaces that are already overridden.
	var recoloured: Color = Color(0.20, 0.40, 0.90)
	model.set_livery(recoloured, trim, canopy, lines, nose)
	var after: Array[Color] = _material_colors(model, PlayerModel.HULL_MATERIAL)
	_check(after.size() == hulls.size(), "repainting keeps every hull surface")
	_check(_all_colors_are(after, recoloured), "a live repaint reaches the hull")
	model.set_livery(recoloured, trim, canopy, Color(0.0, 0.85, 0.95), nose)
	_check(
		_all_colors_are(_material_colors(model, PlayerModel.LINE_MATERIAL), Color(0.0, 0.85, 0.95)),
		"a live repaint reaches the lines"
	)
	model.set_livery(
		recoloured, trim, Color(0.95, 0.85, 0.10), Color(0.0, 0.85, 0.95), nose
	)
	_check(
		_all_colors_are(_canopy_colors(model), Color(0.95, 0.85, 0.10)),
		"a live repaint reaches the canopy"
	)
	model.set_livery(
		recoloured, trim, Color(0.95, 0.85, 0.10), Color(0.0, 0.85, 0.95),
		Color(0.95, 0.05, 0.35)
	)
	_check(
		_all_colors_are(_nose_colors(model), Color(0.95, 0.05, 0.35)),
		"a live repaint reaches the nose"
	)

	# The GLB is shared by every ship and by the preview, so the paint lives in
	# duplicated materials: a repainted file would recolour the next ship too.
	var pristine: Node3D = (
		(load(PlayerModel.MODEL_PATH) as PackedScene).instantiate() as Node3D
	)
	add_child(pristine)
	var factory: Array[Color] = _material_colors(pristine, PlayerModel.HULL_MATERIAL)
	_check(factory.size() > 0, "the file still carries its own hull material")
	_check(
		_all_colors_are(factory, GameSettings.DEFAULT_HULL),
		"painting a ship leaves the shared model untouched"
	)
	_check(
		_nose_colors(pristine).is_empty(),
		"and the split leaves the shared model with its single hull sheet"
	)
	_check(
		_all_colors_match_rgb(
			_material_colors(pristine, PlayerModel.LINE_MATERIAL), GameSettings.DEFAULT_LINES
		),
		"and leaves the file's own lines untouched"
	)
	pristine.queue_free()

	model.queue_free()


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


func _test_player_is_centered() -> void:
	var camera: Camera3D = _player.camera
	_check(camera != null, "player owns a Camera3D")
	if camera == null:
		return

	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = camera.unproject_position(_player.global_position)
	var offset: float = projected.distance_to(centre)
	_check(offset < 1.0, "player projects to the screen centre (off by %.2f px)" % offset)


func _test_movement() -> void:
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_right")
	for _i in 30:
		await get_tree().physics_frame
	Input.action_release(&"move_right")

	var travelled: float = _player.global_position.x - start.x
	_check(travelled > 5.0, "player moves right on the play plane (%.1f units)" % travelled)
	_check(
		absf(_player.global_position.z - start.z) < 0.1,
		"movement keeps the player on its plane"
	)


## The maneuverability contract: cruise inside 0.08 s, a full stop inside 0.06 s,
## tap mode on a light tilt, a 3x dash that drops the old inertia, a model that
## banks and catches up without ever lagging the shot, and a camera that springs
## the ship back to centre once it stops.
func _test_maneuverability() -> void:
	_release_all_input()
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	var accel_frames: int = 0
	Input.action_press(&"move_right")
	while accel_frames < 15 and _flat_speed() < Player.MAX_SPEED * 0.98:
		await get_tree().physics_frame
		accel_frames += 1
	_check(
		accel_frames <= 4,
		"cruise arrives in %d frames (%.3f s)" % [accel_frames, accel_frames / 60.0]
	)

	var stop_frames: int = 0
	Input.action_release(&"move_right")
	while stop_frames < 15 and _flat_speed() > 0.01:
		await get_tree().physics_frame
		stop_frames += 1
	_check(
		stop_frames <= 3,
		"a full stop from cruise takes %d frames (%.3f s)"
		% [stop_frames, stop_frames / 60.0]
	)

	# Tap mode: a 20 percent tilt has to move the ship without giving it real
	# cruise speed, or threading a narrow gap becomes all or nothing.
	Input.action_press(&"move_right", 0.2)
	for _i in 20:
		await get_tree().physics_frame
	var tap_speed: float = _flat_speed()
	Input.action_release(&"move_right")
	_check(
		tap_speed > 0.5 and tap_speed < Player.MAX_SPEED * 0.25,
		"a light tilt moves the ship at tap speed (%.1f u/s)" % tap_speed
	)
	_player.velocity = Vector3.ZERO

	# Dash: 3x cruise from the first frame, and it must wipe the inertia it had.
	Input.action_press(&"move_left")
	for _i in 20:
		await get_tree().physics_frame
	var before_dash: float = _player.velocity.x
	Input.action_release(&"move_left")

	Input.action_press(&"move_right")
	# Input injected from a coroutine lands after the physics step, so the
	# just_pressed latch never reaches _physics_process; call the handler the
	# frame would.
	_player.call("_start_dash")
	await get_tree().physics_frame
	var dash_speed: float = _flat_speed()
	var dash_x: float = _player.velocity.x
	_check(
		dash_speed >= Player.MAX_SPEED * 3.0,
		"the dash injects %.2fx cruise on frame one" % (dash_speed / Player.MAX_SPEED)
	)
	_check(
		dash_x > 0.0 and before_dash < -Player.MAX_SPEED * 0.5,
		"the dash cancels the inherited inertia (%.1f -> %.1f u/s)" % [before_dash, dash_x]
	)
	Input.action_release(&"move_right")

	# A neutral stick dashes down the nose instead of guessing a direction.
	Input.action_press(&"aim_up")
	for _i in 60:
		await get_tree().physics_frame
	_player.velocity = Vector3.ZERO
	_player.call("_start_dash")
	await get_tree().physics_frame
	var nose_speed: float = _flat_speed()
	_check(
		nose_speed >= Player.MAX_SPEED * 3.0 and _player.velocity.z < -Player.MAX_SPEED * 2.0,
		"a neutral stick dashes down the nose (%.1f u/s)" % nose_speed
	)
	Input.action_release(&"aim_up")

	# Aim is instant while the model eases in at 1800 deg/s: the shot never waits
	# for the animation, and the animation still finishes a 180 in about 0.1 s.
	Input.action_press(&"aim_left")
	for _i in 30:
		await get_tree().physics_frame
	Input.action_release(&"aim_left")
	Input.action_press(&"aim_right")
	await get_tree().physics_frame
	var shot_axis: float = _player.get("_aim_direction").x
	var catching_up: float = absf(rad_to_deg(_player.get("_visual").rotation.y))
	for _i in 8:
		await get_tree().physics_frame
	var settled_yaw: float = absf(rad_to_deg(_player.get("_visual").rotation.y))
	_check(shot_axis > 0.99, "the shot direction flips on the first frame (x %.2f)" % shot_axis)
	_check(
		catching_up > 60.0,
		"the model is still swinging one frame after the flick (%.0f deg to go)" % catching_up
	)
	_check(settled_yaw < 2.0, "the model completes the 180 in under 0.15 s (%.1f deg off)" % settled_yaw)
	Input.action_release(&"aim_right")

	# Banking: drift sideways across the nose and the hull leans; stop and it
	# levels out again.
	Input.action_press(&"aim_right")
	for _i in 10:
		await get_tree().physics_frame
	Input.action_press(&"move_up")
	for _i in 20:
		await get_tree().physics_frame
	var bank: float = rad_to_deg(_player.get("_visual").rotation.x)
	Input.action_release(&"move_up")
	Input.action_release(&"aim_right")
	for _i in 40:
		await get_tree().physics_frame
	var level: float = absf(rad_to_deg(_player.get("_visual").rotation.x))
	_check(absf(bank) >= 15.0 and absf(bank) <= 40.0, "strafing banks the hull (%.1f deg)" % bank)
	_check(level < 3.0, "the hull levels out when the drift stops (%.1f deg)" % level)

	# The camera spring settles the ship back to dead centre once it is still.
	_release_all_input()
	_player.velocity = Vector3.ZERO
	for _i in 30:
		await get_tree().physics_frame
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = _player.camera.unproject_position(_player.global_position)
	_check(
		projected.distance_to(centre) < 1.0,
		"the camera settles the ship back to centre at rest (%.2f px)"
		% projected.distance_to(centre)
	)


## The dash gesture: a double tap on the movement stick dashes the way it was
## tapped, one tap and two taps in different directions spend nothing, and in
## FIGHTER the jink follows the tap on both axes, diagonals included. The Space /
## L3 button stays as the alternative.
func _test_double_tap_dash() -> void:
	await _reset_dash_gesture()
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	Input.action_release(&"move_right")
	await get_tree().physics_frame
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	var tap_speed: float = _flat_speed()
	_check(
		float(_player.get("_dash_time")) > 0.0
		and tap_speed >= Player.MAX_SPEED * 3.0
		and _player.velocity.x > 0.0,
		"a double tap dashes the way it was tapped (%.1f u/s)" % tap_speed
	)
	Input.action_release(&"move_right")

	# One tap is a nudge, not a dash: the second tap is the whole gesture.
	await _reset_dash_gesture()
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	await get_tree().physics_frame
	_check(
		float(_player.get("_dash_time")) <= 0.0,
		"one tap moves the ship without spending the dash"
	)

	# Two taps that disagree are a direction change, not a dash. Left then up is
	# 90 degrees apart, well outside the cone.
	await _reset_dash_gesture()
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	Input.action_release(&"move_left")
	await get_tree().physics_frame
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	_check(
		float(_player.get("_dash_time")) <= 0.0,
		"two taps in different directions do not dash"
	)
	Input.action_release(&"move_up")

	# FIGHTER: the lateral double tap rolls to the tapped side. With the nose
	# up-screen, screen-left is the airframe's own left.
	await _reset_dash_gesture()
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the double-tap check starts in FIGHTER")
	await _reset_dash_gesture()
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	Input.action_release(&"move_left")
	await get_tree().physics_frame
	# The first tap is a heading request too, so the nose is reset between taps:
	# the jink is measured against the heading it was actually asked from.
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	var roll_side: float = float(_player.get("_roll_side"))
	_check(
		float(_player.get("_dash_time")) > 0.0 and roll_side < 0.0,
		"a lateral double tap rolls to the side that was tapped (%.0f)" % roll_side
	)
	Input.action_release(&"move_left")

	# In FIGHTER any direction is a jink, diagonals included. The stick is read in
	# the same world axes the flight model uses, so with the nose up-screen a tap
	# up is forward, down is backward, and up-right is the diagonal between them.
	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	for _i in 4:
		await get_tree().physics_frame
	var forward_push: Vector2 = _jink_push()
	_check(
		forward_push.x > 20.0 and absf(forward_push.y) < 2.0,
		"a double tap forward jinks along the nose (%.1f u/s)" % forward_push.x
	)
	Input.action_release(&"move_up")

	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_down")
	await get_tree().physics_frame
	Input.action_release(&"move_down")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_down")
	for _i in 4:
		await get_tree().physics_frame
	var back_push: Vector2 = _jink_push()
	_check(
		back_push.x < -20.0 and absf(back_push.y) < 2.0,
		"a double tap backward jinks against the nose (%.1f u/s)" % back_push.x
	)
	Input.action_release(&"move_down")

	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	Input.action_release(&"move_right")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	Input.action_press(&"move_right")
	for _i in 4:
		await get_tree().physics_frame
	var diagonal_push: Vector2 = _jink_push()
	_check(
		diagonal_push.x > 15.0 and diagonal_push.y > 15.0,
		"a diagonal double tap jinks on both axes (%.1f forward, %.1f right)"
		% [diagonal_push.x, diagonal_push.y]
	)
	Input.action_release(&"move_up")
	Input.action_release(&"move_right")

	# Leave the ship in GERWALK: the rest of the suite starts from the hover.
	await _reset_dash_gesture()
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(not _player.is_fighter(), "the double-tap check restores GERWALK")


## The transformation contract: two real modes, a switch that costs commitment,
## a fighter that flies at 180% on a stall-speed floor, a course that lags the
## nose into a skid, a constant wind that moves it, a gun welded to the airframe,
## and a burner that shreds what it flies through.
func _test_transformation() -> void:
	_release_all_input()
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(not _player.is_fighter(), "the ship starts in GERWALK")

	# S1: the switch is a 0.28 s commitment, not an instant toggle.
	_player.call("_start_transform")
	await get_tree().physics_frame
	_check(not _player.is_fighter(), "the switch does not land in one frame")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the ship reaches FIGHTER after 0.28 s")

	# S3: 180% of the hover cruise, measured in airspeed. The ship is flying
	# downwind here, so the ground speed is the airspeed plus the wind and is not
	# the spec number.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 20.0
	Input.action_press(&"move_right")
	for _i in 20:
		await get_tree().physics_frame
	var fighter_speed: float = (_player.velocity - Player.WIND).length()
	_check(
		absf(fighter_speed / Player.MAX_SPEED - 1.8) < 0.05,
		"fighter cruise is %.0f%% of the hover's (%.1f u/s airspeed)"
		% [100.0 * fighter_speed / Player.MAX_SPEED, fighter_speed]
	)

	# FR-15 still holds at fighter speed: the camera lead saturates instead of
	# scaling with 180% of the hover cruise.
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = _player.camera.unproject_position(_player.global_position)
	_check(
		projected.distance_to(centre) < 16.0,
		"the camera keeps the fighter framed at 1.8x (%.1f px)" % projected.distance_to(centre)
	)

	# S4: the gun is bolted to the airframe. The right stick, which would aim in
	# GERWALK, must not move the shot off the nose.
	Input.action_press(&"aim_up")
	for _i in 2:
		await get_tree().physics_frame
	var nose: Vector3 = _player.get("_aim_direction")
	_check(nose.x > 0.99, "the gun stays on the nose in FIGHTER (x %.2f)" % nose.x)
	Input.action_release(&"aim_up")

	# S3: a reversal is an arc. One frame cannot turn 180 degrees, and the full
	# turn lands inside the 360-450 deg/s band.
	var before_turn: Vector3 = _player.get("_heading")
	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	var after_one: Vector3 = _player.get("_heading")
	_check(
		after_one.dot(before_turn) > 0.9,
		"one frame cannot reverse the heading (%.0f deg)"
		% rad_to_deg(after_one.angle_to(before_turn))
	)
	var yaw_before: float = atan2(-before_turn.z, before_turn.x)
	var peak_bank: float = 0.0
	var peak_lean: float = 0.0
	for _i in 30:
		await get_tree().physics_frame
		var roll: float = _player.get("_visual").rotation.x
		if absf(roll) > absf(peak_bank):
			peak_bank = roll
			var heading: Vector3 = _player.get("_heading")
			var right: Vector3 = Vector3(-heading.z, 0.0, heading.x)
			peak_lean = _player.get("_visual").global_transform.basis.y.dot(right)
	var reversed: Vector3 = _player.get("_heading")
	var turned: float = angle_difference(yaw_before, atan2(-reversed.z, reversed.x))
	_check(reversed.dot(before_turn) < -0.9, "the heading completes a 180 in about 0.45 s")
	Input.action_release(&"move_left")

	# The hull banks into the turn like a wing. A car yaws flat; a fighter drops
	# the wing on the inside of the turn and raises it when the stick centres, so
	# the airframe's own up vector leans the way the nose is going.
	_check(
		rad_to_deg(absf(peak_bank)) >= 35.0,
		"a fighter banks into the turn (%.1f deg)" % rad_to_deg(peak_bank)
	)
	_check(
		signf(peak_lean) == -signf(turned),
		"the wing drops on the inside of the turn (%.1f deg roll, %.0f deg turn)"
		% [rad_to_deg(peak_bank), rad_to_deg(turned)]
	)
	for _i in 40:
		await get_tree().physics_frame
	var levelled: float = absf(rad_to_deg(_player.get("_visual").rotation.x))
	_check(levelled < 4.0, "the fighter levels out when the turn ends (%.1f deg)" % levelled)

	# S4: fighter rounds leave faster, live 40% longer and keep a tight fan.
	var weapons: WeaponSystem = _player.get_node("Weapons")
	weapons.select(Arsenal.Kind.VULCAN)
	weapons.set("_cooldown", 0.0)
	_clear_projectiles()
	weapons.tick(0.016, _player.global_position, _player.global_position, reversed, true, true)
	var shots: Array[Projectile] = _player_projectiles()
	_check(shots.size() >= Arsenal.VULCAN_PELLETS, "the fighter vulcan still fans out")
	if shots.size() >= 2:
		var widest: float = 0.0
		for i in shots.size():
			for j in range(i + 1, shots.size()):
				var first: Vector3 = shots[i].get("_velocity")
				var second: Vector3 = shots[j].get("_velocity")
				widest = maxf(widest, rad_to_deg(first.angle_to(second)))
		var speed: float = shots[0].get("_velocity").length()
		var life: float = shots[0].get("_life")
		_check(
			absf(speed - Arsenal.VULCAN_SPEED * Arsenal.FIGHTER_SPEED_MULTIPLIER) < 1.0,
			"fighter rounds leave at %.0f u/s (1.35x)" % speed
		)
		_check(
			life > Arsenal.FIGHTER_RANGE_MULTIPLIER * Projectile.LIFETIME - 0.1,
			"fighter rounds carry 40%% more range (%.1f s of flight)" % life
		)
		_check(widest < 12.0, "the fighter fan closes to %.1f deg" % widest)

	# S4: and plasma loses the lock that makes it plasma in the hover.
	_clear_projectiles()
	var target: Enemy = _spawn_enemy(_player.global_position + reversed * 10.0)
	# The automatic battery would launch at that same target inside this tick and
	# look like a second plasma bolt, so park it while the count is measured.
	weapons.set("_missile_cooldown", 99.0)
	weapons.select(Arsenal.Kind.PLASMA)
	weapons.set("_cooldown", 0.0)
	weapons.tick(0.016, _player.global_position, _player.global_position, reversed, true, true)
	var bolts: Array[Projectile] = _player_projectiles()
	_check(bolts.size() == 1, "the fighter plasma still fires")
	if bolts.size() == 1:
		_check(bolts[0].get("_target") == null, "fighter plasma has no lock-on")
	weapons.set("_missile_cooldown", 0.0)
	_clear_projectiles()
	if target != null:
		target.queue_free()
	await get_tree().physics_frame

	# S5: the dash becomes a jink: it steps sideways and keeps the nose.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 30.0
	Input.action_press(&"aim_left")
	for _i in 2:
		await get_tree().physics_frame
	var heading_before: Vector3 = _player.get("_heading")
	var position_before: Vector3 = _player.global_position
	_player.call("_start_dash")
	for _i in 12:
		await get_tree().physics_frame
	var travelled: Vector3 = _player.global_position - position_before
	var lateral: float = travelled.dot(Vector3(-heading_before.z, 0.0, heading_before.x))
	var heading_after: Vector3 = _player.get("_heading")
	_check(
		lateral < -2.0,
		"the barrel roll steps left on command (%.1f units)" % lateral
	)
	_check(heading_after.dot(heading_before) > 0.99, "the roll leaves the nose where it was")

	# The roll animation runs on its own, slower clock: when the 0.20 s jink is
	# over the airframe is still coming over, and it is coming over to the side
	# the step went to.
	var spin: float = _player.get("_visual").rotation.x
	_check(
		spin < -1.0,
		"the roll is still turning after the jink (%.0f deg)" % rad_to_deg(spin)
	)
	_check(
		float(_player.get("_roll_side")) < 0.0,
		"the roll remembers the side it went to"
	)

	# A centred stick repeats that side instead of defaulting to the right.
	Input.action_release(&"aim_left")
	_player.set("_dash_cooldown", 0.0)
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 30.0
	position_before = _player.global_position
	_player.call("_start_dash")
	_check(
		float(_player.get("_roll_side")) < 0.0,
		"a neutral stick repeats the last side"
	)
	for _i in 12:
		await get_tree().physics_frame
	travelled = _player.global_position - position_before
	lateral = travelled.dot(Vector3(-heading_before.z, 0.0, heading_before.x))
	_check(
		lateral < -2.0,
		"the repeat roll still steps left (%.1f units)" % lateral
	)
	# And the slower spin lands back on the bank axis instead of parking a turn.
	for _i in 20:
		await get_tree().physics_frame
	var settle: float = _player.get("_visual").rotation.x
	_check(
		absf(settle) < 0.1,
		"the roll settles level when it ends (%.1f deg)" % rad_to_deg(settle)
	)

	# S6: the burner makes the nose a plow. Fire in the cone dies; fire behind
	# the ship is untouched.
	_player.set("_heading", Vector3.RIGHT)
	var front: Projectile = _spawn_enemy_bullet(_player.global_position + Vector3.RIGHT * 4.0)
	var behind: Projectile = _spawn_enemy_bullet(_player.global_position - Vector3.RIGHT * 4.0)
	_player.set("_boosting", true)
	_player.call("_update_shockwave")
	_check(
		front == null or front.is_queued_for_deletion(),
		"the shockwave shreds enemy fire in front of the nose"
	)
	_check(
		behind != null and not behind.is_queued_for_deletion(),
		"enemy fire behind the ship survives the burst"
	)
	_player.set("_boosting", false)
	_clear_projectiles()
	await get_tree().physics_frame

	# S3: the fighter bleeds from cruise down to its stall speed in the old 0.35 s
	# and then keeps flying: drag, not a brake. The airspeed is set to cruise, so
	# the ground velocity is that plus the wind.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * Player.FIGHTER_SPEED + Player.WIND
	var glide_speed: float = Player.FIGHTER_STALL_SPEED + Player.WIND.length()
	var stall_frames: int = 0
	while stall_frames < 40 and _flat_speed() > glide_speed + 0.6:
		await get_tree().physics_frame
		stall_frames += 1
	_check(
		absf(stall_frames / 60.0 - Player.FIGHTER_STOP_TIME) < 0.05,
		"fighter bleeds to stall speed in %.2f s" % (stall_frames / 60.0)
	)
	for _i in 6:
		await get_tree().physics_frame
	_check(
		absf(_flat_speed() - glide_speed) < 1.0,
		"the fighter glides at the stall floor (%.1f u/s)" % _flat_speed()
	)

	# S3: a coast still covers ground. If the floor regresses to zero, the ship
	# parks on the planet and the planet stops rolling.
	var glide_from: Vector3 = _player.global_position
	for _i in 30:
		await get_tree().physics_frame
	var glided: float = _flat_distance(_player.global_position, glide_from)
	_check(glided > 8.0, "coasting still covers ground (%.1f units in 0.5 s)" % glided)

	# S3: the nose turns faster than the air does. Asking for a reversal, the ship
	# keeps travelling the old way while the nose already points the new one.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * Player.FIGHTER_SPEED + Player.WIND
	Input.action_press(&"move_left")
	for _i in 12:
		await get_tree().physics_frame
	var skid: float = _sideways_airspeed()
	_check(absf(skid) > 20.0, "a reversal skids across the nose (%.1f u/s)" % skid)
	Input.action_release(&"move_left")
	for _i in 60:
		await get_tree().physics_frame
	skid = _sideways_airspeed()
	_check(
		absf(skid) < 3.0,
		"the skid bleeds out once the nose settles (%.1f u/s)" % skid
	)

	# S3: wind is a world vector. The same coast rides it downwind and fights it
	# upwind, so ground speed is not airspeed.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.ZERO
	for _i in 90:
		await get_tree().physics_frame
	var downwind: float = _player.velocity.x
	_check(
		absf(downwind - (Player.FIGHTER_STALL_SPEED + Player.WIND.x)) < 1.0,
		"downwind the glide rides the wind (%.1f u/s over ground)" % downwind
	)
	_player.set("_heading", Vector3.LEFT)
	_player.velocity = Vector3.ZERO
	for _i in 90:
		await get_tree().physics_frame
	var upwind: float = _player.velocity.x
	_check(
		absf(upwind + (Player.FIGHTER_STALL_SPEED - Player.WIND.x)) < 1.0,
		"upwind the same glide is slower over ground (%.1f u/s)" % upwind
	)

	# S1: back to the hover, and the gun is free the moment it lands.
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(not _player.is_fighter(), "the ship returns to GERWALK")

	# S3: the hover does not answer to the wind. Holding station is its whole
	# reason to exist next to the fighter.
	_player.velocity = Player.WIND * 3.0
	for _i in 20:
		await get_tree().physics_frame
	_check(
		_flat_speed() < 0.2,
		"the wind does not carry the hover (%.2f u/s)" % _flat_speed()
	)

	Input.action_press(&"aim_up")
	for _i in 3:
		await get_tree().physics_frame
	_check(
		_player.get("_aim_direction").z < -0.9,
		"the gun aims freely again in GERWALK"
	)
	Input.action_release(&"aim_up")
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame


## The GERWALK silhouette is a skeleton pose, not a second mesh: the nacelles swing
## down and outboard with the nozzles ahead of the wing root, where the near-overhead
## camera can see them, the gunpod rides in the right hand, and FIGHTER folds both
## back into the airframe without dropping anything through the planet.
func _test_gerwalk_silhouette() -> void:
	var model: PlayerModel = _player.get("_model") as PlayerModel
	var pod: Node3D = _player.get("_gunpod")
	var hull: Node3D = _player.get("_visual")
	_check(model != null, "the airframe is the imported model")
	if model == null or pod == null or hull == null:
		return

	var feet: Array[Vector3] = model.nozzle_anchors()
	_check(feet.size() == 2, "the airframe carries two legs")
	if feet.size() < 2:
		return
	_check(
		absf(feet[0].z + feet[1].z) < 0.05,
		"the legs splay symmetrically (z %.2f / %.2f)" % [feet[0].z, feet[1].z]
	)
	_check(absf(feet[0].z) > 0.45, "the legs stand wide (z %.2f)" % absf(feet[0].z))
	_check(feet[0].y < -0.2, "the legs hang below the hull (y %.2f)" % feet[0].y)
	_check(feet[0].x > -0.5, "the feet leave the tail fold (x %.2f)" % feet[0].x)
	var sole: float = hull.to_global(feet[0]).y - 0.15
	_check(
		sole > Arena.GROUND_Y + 0.2,
		"the soles stay clear of the ground (%.2f vs %.2f)" % [sole, Arena.GROUND_Y]
	)

	# The gunner hold brings the right arm out, so the pod has to be in the hand
	# and the hand in front of the wing root, not trailing the tail.
	var hand: Vector3 = model.to_global(model.hand_anchor())
	_check(
		pod.global_position.distance_to(hand) < 0.05,
		"the gunpod is in the right hand in GERWALK"
	)
	var held: Vector3 = hull.to_local(pod.global_position)
	_check(held.x > 0.3, "the gunpod reaches ahead of the wing root (x %.2f)" % held.x)
	_check(held.z > 0.1, "the gunpod rides the right side (z %.2f)" % held.z)

	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the silhouette test reaches FIGHTER")
	_check(
		float(_player.get("_mode_blend")) > 0.99,
		"the pose arrives with the rules (blend %.2f)" % float(_player.get("_mode_blend"))
	)
	var tucked: Vector3 = model.nozzle_anchors()[0]
	_check(tucked.x < -1.0, "FIGHTER folds the legs back along the fuselage (x %.2f)" % tucked.x)
	_check(tucked.y > -0.4, "FIGHTER lifts the feet into the tail (y %.2f)" % tucked.y)
	var stowed: Vector3 = hull.to_local(pod.global_position)
	_check(absf(stowed.z) < 0.15, "FIGHTER stows the gunpod on the centreline (z %.2f)" % stowed.z)
	_check(stowed.y < -0.2, "the stowed gunpod rides under the belly (y %.2f)" % stowed.y)

	# The wings answer speed, not the mode: extended at cruise, swept only once the
	# ship is pushed past it. Driving the visual directly keeps the check out of the
	# flight model's hands.
	var aim: Vector3 = _player.get("_aim_direction")
	_player.velocity = aim * (Player.FIGHTER_SPEED - 1.0)
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees < 2.0,
		"the wings stay extended at cruise (%.1f deg)" % model.sweep_degrees
	)
	_player.velocity = aim * (Player.FIGHTER_BOOST_SPEED - 2.0)
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees > 25.0,
		"the wings sweep past cruise (%.1f deg)" % model.sweep_degrees
	)
	_player.velocity = Vector3.ZERO

	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	var dropped: Vector3 = model.nozzle_anchors()[0]
	_check(
		not _player.is_fighter() and dropped.y < -0.2,
		"the switch back drops the legs again (y %.2f)" % dropped.y
	)


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
	_player.set("_tap_timer", 0.0)
	_player.set("_move_engaged", false)
	await get_tree().physics_frame


func _test_firing() -> void:
	var before: int = _count_projectiles(Projectile.Team.PLAYER)

	Input.action_press(&"aim_left")
	Input.action_press(&"fire")
	for _i in 20:
		await get_tree().physics_frame
	Input.action_release(&"fire")
	Input.action_release(&"aim_left")

	var after: int = _count_projectiles(Projectile.Team.PLAYER)
	_check(after > before, "firing spawns player projectiles (%d -> %d)" % [before, after])


func _test_enemy_patterns() -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	_check(enemies.size() >= 1, "the planet is populated (found %d)" % enemies.size())

	var saw_enemy_bullets: bool = false
	for _i in 300:
		await get_tree().physics_frame
		if _count_projectiles(Projectile.Team.ENEMY) > 0:
			saw_enemy_bullets = true
			break

	_check(saw_enemy_bullets, "enemy emits a bullet pattern within 5 s")

	if not enemies.is_empty():
		var enemy: Enemy = enemies[0] as Enemy
		var distance: float = _flat_distance(enemy.global_position, _player.global_position)
		_check(
			absf(distance - Enemy.ORBIT_RADIUS) < 8.0,
			"the engaged turret holds the ring radius (%.1f units)" % distance
		)


## A large planet is only worth exploring if enemies belong to it. A turret pinned
## to the ship would follow the player forever and the trip would change nothing,
## so this drives the ship away and asserts both halves of the behaviour: the
## turret is left behind, and it keeps moving on its own.
func _test_enemies_roam_the_planet() -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	if enemies.is_empty():
		_check(false, "an enemy is available for the roaming check")
		return

	var enemy: Enemy = enemies[0] as Enemy
	var start: Vector3 = enemy.global_position

	_player.global_position = enemy.global_position + Vector3(0.0, 0.0, 120.0)
	_player.velocity = Vector3.ZERO

	for _i in 90:
		await get_tree().physics_frame

	if not is_instance_valid(enemy):
		_check(false, "the turret survives the run")
		return

	var separation: float = _flat_distance(enemy.global_position, _player.global_position)
	var roamed: float = _flat_distance(enemy.global_position, start)

	_check(
		separation > 90.0,
		"the turret does not follow the ship (%.1f units behind)" % separation
	)
	_check(
		roamed > 1.0,
		"the turret roams the planet on its own (%.1f units in 1.5 s)" % roamed
	)


## The launcher is a new threat, not a new rule set: it has to be a real enemy, so
## the radar, the bomb and the player's own missiles all still see it, and its
## attack has to be a guided missile, because that is the thing the decoy answers.
func _test_missile_enemy() -> void:
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	var enemy: MissileEnemy = _spawn_missile_enemy(Vector3(18.0, 0.0, 0.0))
	_check(enemy != null, "the missile launcher spawns")
	if enemy == null:
		return
	_check(enemy.is_in_group(&"enemy"), "the launcher is a target like any other")
	_check(
		enemy.current_hp() == MissileEnemy.LAUNCHER_HP,
		"the launcher carries its own hull (%d hp)" % enemy.current_hp()
	)

	# The approach, the warning and the launch are the attack: wait for the first
	# missile instead of calling the fire function behind the state machine.
	var missile: Projectile = null
	for _i in 240:
		await get_tree().physics_frame
		for child in get_children():
			var shot: Projectile = child as Projectile
			if shot == null or shot.is_queued_for_deletion():
				continue
			if int(shot.get("_team")) != Projectile.Team.ENEMY:
				continue
			if int(shot.get("_style")) != Projectile.Style.MISSILE:
				continue
			missile = shot
			break
		if missile != null:
			break

	_check(missile != null, "the launcher fires a missile")
	if missile != null:
		_check(bool(missile.call("is_homing")), "the launcher's missile is guided")
		_check(
			missile.get("_target") == _player,
			"the launcher's missile chases the ship"
		)
		_check(
			int(missile.get("_damage")) == MissileEnemy.MISSILE_DAMAGE,
			"the launcher's missile carries its own warhead"
		)

	# Break the chase before it lands: this check is about the attack, not about
	# how much health the player has left at this point in the suite.
	_player.global_position = Vector3(0.0, 0.0, 120.0)
	_clear_enemies()
	_clear_projectiles()
	await get_tree().physics_frame


## The burner is a tank, not a cooldown, so this drives the whole cycle in one
## run: burn, coast, burn out, release and re-arm. Those four states are the
## mechanic; checking a single one of them would miss the transitions.
## The wake is a visual, but it is wired to the flight model: two emitters, one per
## nozzle, and the density has to answer the speed rather than a clock. The puffs
## are left in world space, which is what turns a point emitter into a trail.
func _test_exhaust_trail() -> void:
	var smoke: Array = _player.get("_smoke")
	_check(smoke.size() == 2, "the airframe carries one exhaust emitter per nozzle")
	if smoke.size() < 2:
		return
	var first: GPUParticles3D = smoke[0] as GPUParticles3D
	_check(first != null and not first.local_coords, "the puffs stay where they were dropped")
	_check(
		first.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the trail casts no shadow on the hull"
	)

	# A puff born at the nozzle stays there until the ship outruns it, so the floor
	# is zero. With a floor the standing ship wore its own plume: from the game
	# camera the near leg sat behind it, and a grey veil over a white leg reads as
	# a shadow the other leg does not have.
	_player.call("_update_smoke", 0.0, 0.0)
	var idle: float = first.amount_ratio
	_player.call("_update_smoke", Player.FIGHTER_BOOST_SPEED * 0.25, 0.0)
	var cruise: float = first.amount_ratio
	_player.call("_update_smoke", Player.FIGHTER_BOOST_SPEED, 0.0)
	var flat_out: float = first.amount_ratio
	_check(is_zero_approx(idle), "a standing ship leaves no trail on its hull")
	_check(
		cruise > idle and flat_out > cruise,
		"the trail thickens with speed (%.2f at rest, %.2f cruising, %.2f flat out)"
		% [idle, cruise, flat_out]
	)

	var model: PlayerModel = _player.get("_model") as PlayerModel
	var anchor: Vector3 = model.nozzle_anchors()[0]
	_check(
		first.position.distance_to(anchor) < 0.01,
		"the emitter rides its nozzle"
	)


## The ship is a mirror lit by one sun, so the two legs present opposite facets and
## one spine crushed to black while its twin read warm grey: one leg wearing a
## shadow the other did not have. The fill rides the camera and culls on the
## airframe layer. Both halves matter -- a fill that lit the arena would change the
## scene, and meshes left off the layer would not receive it at all.
func _test_airframe_lighting() -> void:
	var rig: Node = _player.camera.get_parent()
	var fill: DirectionalLight3D = rig.get_node_or_null("FillLight") as DirectionalLight3D
	_check(fill != null, "the camera rig carries the airframe fill light")
	if fill == null:
		return
	_check(not fill.shadow_enabled, "the fill casts no shadow of its own")
	_check(
		fill.light_cull_mask == PlayerModel.AIRFRAME_LAYER_MASK,
		"the fill reaches the airframe layer and nothing else"
	)

	var model: PlayerModel = _player.get("_model") as PlayerModel
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	var on_layer: bool = not meshes.is_empty()
	for node in meshes:
		if (node as MeshInstance3D).layers != PlayerModel.AIRFRAME_LAYER_MASK:
			on_layer = false
			break
	_check(on_layer, "every airframe mesh sits on the layer the fill targets")


## The scope is the one HUD element that reads positions instead of events, so the
## test drives the real query: a turret placed off the starboard bow must paint
## right of the centre, one placed aft must paint below it, and a contact past the
## range must paint nothing. The world-fixed mapping is the part worth pinning: a
## heading-up scope would still pass a "one blip" check and be wrong on screen.
func _test_radar() -> void:
	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var radar: Radar = hud.get_node("%Radar") as Radar
	_check(radar != null, "the HUD carries a radar scope")
	if radar == null:
		return

	_check(
		radar.anchor_left == 1.0 and radar.anchor_top == 1.0,
		"the scope is anchored to the bottom-right corner"
	)

	# The streamer drops a turret every two seconds; one appearing mid-test would
	# be indistinguishable from the contact the test placed.
	var spawn_timer: float = float(_arena.get("_spawn_timer"))
	_arena.set("_spawn_timer", 999.0)
	_clear_enemies()
	await _wait_frames(2)
	_check(radar.contact_offsets().is_empty(), "an empty sky paints no blips")

	var contact: Enemy = _spawn_enemy(_player.global_position + Vector3(30.0, 0.0, 0.0))
	await _wait_frames(2)
	var offsets: Array[Vector2] = radar.contact_offsets()
	_check(offsets.size() == 1, "a contact inside the range paints one blip")
	if offsets.size() == 1:
		_check(
			offsets[0].x > 0.0 and absf(offsets[0].y) < 0.5,
			"a contact to starboard paints right of centre"
		)

	if contact != null:
		contact.global_position = _player.global_position + Vector3(0.0, 0.0, 20.0)
	await _wait_frames(1)
	offsets = radar.contact_offsets()
	_check(
		offsets.size() == 1 and offsets[0].y > 0.0,
		"a contact aft paints below centre"
	)

	_check(
		radar.detects(_player.global_position + Vector3(10.0, 0.0, 0.0)),
		"a point inside the range is detected"
	)
	_check(
		not radar.detects(
			_player.global_position + Vector3(0.0, 0.0, Radar.DETECTION_RANGE + 1.0)
		),
		"a point past the range is not detected"
	)

	var nose: Vector3 = _player.nose_direction()
	var expected: Vector2 = Vector2(nose.x, nose.z).normalized()
	_check(
		radar.marker_direction().distance_to(expected) < 0.01,
		"the marker points where the nose points"
	)

	_clear_enemies()
	_arena.set("_spawn_timer", spawn_timer)
	await _wait_frames(2)


func _test_afterburner() -> void:
	var turbo_events: Array = []
	var handler: Callable = func(current: float, maximum: float) -> void:
		turbo_events.append(Vector2(current, maximum))
	GlobalEventBus.player_turbo_changed.connect(handler)

	_check(
		is_equal_approx(float(_player.get("_turbo")), Player.TURBO_MAX),
		"the turbo reserve starts full"
	)

	Input.action_press(&"move_right")
	Input.action_press(&"boost")
	var base_fov: float = _player.camera.fov
	for _i in 90:
		await get_tree().physics_frame

	var boosting_fov: float = _player.camera.fov
	var boosting_speed: float = _flat_speed()
	var spent: float = float(_player.get("_turbo"))
	Input.action_release(&"boost")

	_check(
		boosting_speed > Player.MAX_SPEED * 1.1,
		"the afterburner beats normal top speed (%.1f u/s)" % boosting_speed
	)
	_check(
		boosting_fov > base_fov + 1.0,
		"burning widens the lens as a speed cue (%.1f -> %.1f)" % [base_fov, boosting_fov]
	)
	_check(
		spent < Player.TURBO_MAX,
		"the burner spends the reserve (%.0f left)" % spent
	)

	for _i in 60:
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	var refilled: float = float(_player.get("_turbo"))
	_check(
		refilled > spent,
		"the reserve refills off the burner (%.0f -> %.0f)" % [spent, refilled]
	)

	# Burnout: with almost nothing left the burner must cut out and hand the ship
	# back to normal thrust instead of holding the fast speed for free.
	_player.set("_turbo", 3.0)
	Input.action_press(&"move_right")
	Input.action_press(&"boost")
	for _i in 20:
		await get_tree().physics_frame
	var burnt_out_speed: float = _flat_speed()
	_check(
		burnt_out_speed <= Player.MAX_SPEED + 0.5,
		"burnout hands the ship back to normal speed (%.1f u/s)" % burnt_out_speed
	)

	# Re-arm: releasing the button clears the lockout, so a refilled reserve can
	# burn again on the next press.
	Input.action_release(&"boost")
	for _i in 60:
		await get_tree().physics_frame
	Input.action_press(&"boost")
	for _i in 30:
		await get_tree().physics_frame
	var rearmed_speed: float = _flat_speed()
	Input.action_release(&"boost")
	Input.action_release(&"move_right")

	_check(
		rearmed_speed > Player.MAX_SPEED * 1.1,
		"releasing the burner re-arms it (%.1f u/s)" % rearmed_speed
	)
	_check(not turbo_events.is_empty(), "turbo changes reach the event bus")

	GlobalEventBus.player_turbo_changed.disconnect(handler)
	for _i in 40:
		await get_tree().physics_frame


## The arsenal is three archetypes with different shapes of damage, so each one is
## asserted by its signature behaviour instead of by its numbers: tuning a weapon
## must not rewrite the test.
func _test_arsenal() -> void:
	var weapons: WeaponSystem = _player.get_node("Weapons") as WeaponSystem
	_check(weapons != null, "the player carries a weapon system")
	if weapons == null:
		return

	await _test_weapon_switch(weapons)
	await _test_vulcan(weapons)
	await _test_laser(weapons)
	await _test_plasma(weapons)
	await _test_missiles(weapons)
	await _test_bomb(weapons)
	await _test_bomb_refill(weapons)
	await _test_firing_costs_no_speed(weapons)
	await _test_decoy(weapons)
	await _test_missile_intercept()

	Input.action_release(&"aim_left")
	Input.action_release(&"fire")
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame


func _test_weapon_switch(weapons: WeaponSystem) -> void:
	var announced: Array[String] = []
	var handler: Callable = func(name: String) -> void: announced.append(name)
	GlobalEventBus.player_weapon_changed.connect(handler)

	Input.action_press(&"weapon_3")
	await get_tree().physics_frame
	Input.action_release(&"weapon_3")
	await get_tree().physics_frame

	_check(weapons.kind() == Arsenal.Kind.PLASMA, "key 3 selects the plasma")
	_check(announced.has("PLASMA"), "weapon changes reach the event bus")

	Input.action_press(&"weapon_next")
	await get_tree().physics_frame
	Input.action_release(&"weapon_next")
	await get_tree().physics_frame

	_check(
		weapons.kind() == Arsenal.Kind.VULCAN,
		"the D-pad cycles past the last weapon back to the first"
	)
	GlobalEventBus.player_weapon_changed.disconnect(handler)


func _test_vulcan(weapons: WeaponSystem) -> void:
	weapons.select(Arsenal.Kind.VULCAN)
	_clear_projectiles()
	await get_tree().physics_frame

	Input.action_press(&"aim_left")
	await get_tree().physics_frame
	Input.action_press(&"fire")
	await get_tree().physics_frame
	Input.action_release(&"fire")
	await get_tree().physics_frame

	var shots: Array[Projectile] = _player_projectiles()
	_check(
		shots.size() >= Arsenal.VULCAN_PELLETS,
		"vulcan opens with a %d-pellet fan (fired %d)" % [Arsenal.VULCAN_PELLETS, shots.size()]
	)

	var widest: float = 0.0
	for i in shots.size():
		for j in range(i + 1, shots.size()):
			var first: Vector3 = shots[i].get("_velocity")
			var second: Vector3 = shots[j].get("_velocity")
			widest = maxf(widest, rad_to_deg(first.normalized().angle_to(second.normalized())))
	_check(widest > 20.0, "the fan spreads across the aim (%.0f degrees)" % widest)
	_clear_projectiles()


## The beam is the only weapon with no travel time, so the test asks for the two
## things that only a hit-scan can do: damage without a projectile, and damage that
## lands while the target is still far away.
func _test_laser(weapons: WeaponSystem) -> void:
	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 12.0)
	_check(enemy != null, "spawned a target for the laser")
	if enemy == null:
		return

	weapons.select(Arsenal.Kind.LASER)
	# The automatic missile battery fires on its own schedule and would look like
	# a laser projectile, so park it for the measurement.
	var parked_cooldown: float = weapons.get("_missile_cooldown")
	weapons.set("_missile_cooldown", 99.0)
	_clear_projectiles()
	var before: int = enemy.current_hp()

	Input.action_press(&"fire")
	for _i in 12:
		await get_tree().physics_frame
	Input.action_release(&"fire")
	await get_tree().physics_frame

	_check(
		enemy.current_hp() < before,
		"the laser burns the target it points at (%d -> %d hp)" % [before, enemy.current_hp()]
	)
	_check(_player_projectiles().is_empty(), "the laser emits no projectile (hit-scan)")
	weapons.set("_missile_cooldown", parked_cooldown)

	_clear_enemies()
	await get_tree().physics_frame


## Plasma is the only weapon that ignores where the nose is pointing after the
## shot leaves, so the assertion is that the bolt acquired the off-axis turret and
## turned away from the aim to reach it.
func _test_plasma(weapons: WeaponSystem) -> void:
	var off_axis: Vector3 = _aim().rotated(Vector3.UP, deg_to_rad(24.0))
	var enemy: Enemy = _spawn_enemy(_player.global_position + off_axis * 18.0)
	_check(enemy != null, "spawned an off-axis target for the plasma")
	if enemy == null:
		return

	weapons.select(Arsenal.Kind.PLASMA)
	_clear_projectiles()
	var aim: Vector3 = _aim()

	Input.action_press(&"fire")
	await get_tree().physics_frame
	Input.action_release(&"fire")

	var bolts: Array[Projectile] = _player_projectiles()
	_check(bolts.size() >= 1, "plasma fires a bolt (fired %d)" % bolts.size())
	if bolts.is_empty():
		_clear_enemies()
		return

	var bolt: Projectile = bolts[0]
	_check(bolt.get("_target") == enemy, "the bolt locks the turret inside the cone")

	var curved: bool = false
	for _i in 6:
		await get_tree().physics_frame
	if not is_instance_valid(bolt):
		# It arrived: a bolt that covers 18 units in six frames had to turn.
		curved = true
	else:
		var heading: Vector3 = bolt.get("_velocity")
		curved = rad_to_deg(heading.normalized().angle_to(aim)) > 2.0
	_check(curved, "the bolt curves off the aim towards the lock")

	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame


## The rack is a radar and a charge: no button, no shot; held time loads the salvo;
## the radar decides how it is spread.
func _test_missiles(weapons: WeaponSystem) -> void:
	weapons.select(Arsenal.Kind.VULCAN)
	Input.action_release(&"aim_left")
	Input.action_release(&"missile")
	# With the stick centred the aim is read live from the mouse, and it keeps
	# drifting until the camera settles after the earlier weapon tests. Nothing is
	# placed against the aim until it stops moving: a target spawned against a
	# stale aim sits outside the radar and the lock looks broken.
	_clear_projectiles()
	_clear_enemies()
	await _wait_frames(45)

	await _test_missile_holds_fire(weapons)
	await _test_missile_load(weapons)
	await _test_missile_growth(weapons)
	await _test_missile_spread(weapons)
	await _test_missile_dead_contact(weapons)
	await _test_missile_radar_cone(weapons)
	await _test_missile_cap(weapons)
	await _test_missile_tap(weapons)
	await _test_missile_wings(weapons)

	Input.action_release(&"missile")
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame


## A turret in range buys nothing on its own: the button is the whole permission.
func _test_missile_holds_fire(weapons: WeaponSystem) -> void:
	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 20.0)
	_check(enemy != null, "spawned a target for the missiles")
	await _wait_frames(20)
	_check(
		_player_projectiles().is_empty(),
		"a turret in range never launches a missile on its own"
	)
	_check(weapons.salvo_count() == 0, "an idle rack holds no missiles")


## Held time loads the salvo: one missile per interval, fired only on release.
func _test_missile_load(weapons: WeaponSystem) -> void:
	_clear_enemies()
	await _wait_frames(2)
	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 20.0)
	_check(enemy != null, "spawned a turret ahead of the radar")
	if enemy == null:
		return
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(
		weapons.salvo_count() == 1,
		"an interval of hold loads a missile (loaded %d)" % weapons.salvo_count()
	)
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").size() == 1,
		"the radar rings the contact the salvo will chase"
	)

	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() == 1, "releasing fires the whole load (got %d)" % flight.size())
	_check(weapons.salvo_count() == 0, "a salvo empties the rack")
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").is_empty(),
		"the rings leave with the salvo"
	)
	if flight.is_empty():
		return

	var launched: Projectile = flight[0]
	_check(launched.get("_target") == enemy, "the missile chases the radar contact")
	_check(float(launched.get("_turn_rate")) > 0.0, "the missile is guided")
	await _test_missile_style(launched)
	await _test_missile_trail(launched)
	await _test_missile_orphans()
	_clear_projectiles()


## More hold, more missiles: one second loads three, and a lone contact takes the
## whole salvo instead of the load waiting for company.
func _test_missile_growth(weapons: WeaponSystem) -> void:
	_clear_enemies()
	await _wait_frames(30)
	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 18.0)
	_check(enemy != null, "spawned a lone turret for the load")
	if enemy == null:
		return
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(60)
	_check(
		weapons.salvo_count() == 3,
		"a second of hold loads three missiles (loaded %d)" % weapons.salvo_count()
	)

	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() == 3, "the whole salvo leaves together (got %d)" % flight.size())
	var targets: Array = []
	for missile in flight:
		targets.append(missile.get("_target"))
	_check(_unique_count(targets) == 1, "a lone contact takes every missile")
	_clear_projectiles()


## With more contacts than missiles spread evenly, the load is divided: three
## missiles over two turrets is 2/1, never 3/0 on the nearest one.
func _test_missile_spread(weapons: WeaponSystem) -> void:
	_clear_enemies()
	await _wait_frames(30)
	var aim: Vector3 = _aim()
	var near: Enemy = _spawn_enemy(_player.global_position + aim * 14.0)
	var far: Enemy = _spawn_enemy(_player.global_position + aim * 30.0)
	_check(near != null and far != null, "spawned two contacts inside the radar")
	if near == null or far == null:
		return
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(30)
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").size() == 2,
		"the radar rings both contacts"
	)
	await _wait_frames(30)
	_check(
		weapons.salvo_count() == 3,
		"the load ignores how many contacts it is spread over (loaded %d)"
		% weapons.salvo_count()
	)

	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() == 3, "three loaded missiles leave (got %d)" % flight.size())
	var counts: Array[int] = [0, 0]
	for missile in flight:
		var target: Enemy = missile.get("_target") as Enemy
		if target == near:
			counts[0] += 1
		elif target == far:
			counts[1] += 1
	counts.sort()
	_check(
		counts[0] == 1 and counts[1] == 2,
		"three missiles over two contacts split 2/1 (%s)" % str(counts)
	)
	_clear_projectiles()


## A contact can die while it is ringed. Its mark has to leave with it without
## taking the rack with it: the salvo still fires at whatever is left.
func _test_missile_dead_contact(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	await _wait_frames(30)

	var aim: Vector3 = _aim()
	var doomed: Enemy = _spawn_enemy(_player.global_position + aim * 14.0)
	var survivor: Enemy = _spawn_enemy(_player.global_position + aim * 26.0)
	_check(survivor != null, "spawned two contacts, one of them doomed")
	if doomed == null or survivor == null:
		return
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(weapons.salvo_count() == 1, "the first missile loads against two contacts")

	doomed.take_damage(99)
	await _wait_frames(3)
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").size() == 1,
		"a dead contact takes its ring with it"
	)
	await _wait_frames(20)
	_check(
		weapons.salvo_count() == 2,
		"the load keeps growing after a contact dies (loaded %d)" % weapons.salvo_count()
	)

	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(
		flight.size() == 2,
		"the salvo still fires after a contact dies (got %d)" % flight.size()
	)
	_check(weapons.salvo_count() == 0, "the rack empties when a mark died mid-hold")
	_clear_projectiles()


## The radar looks forward. A turret behind the nose is neither a contact nor a
## target, no matter how close it is.
func _test_missile_radar_cone(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	await _wait_frames(30)

	var aim: Vector3 = _aim()
	var behind: Enemy = _spawn_enemy(_player.global_position - aim * 18.0)
	_check(behind != null, "spawned a turret behind the nose")
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(weapons.salvo_count() == 0, "a turret behind the nose loads nothing")
	_check(
		get_tree().get_nodes_in_group(&"lock_reticle").is_empty(),
		"an empty radar rings nothing"
	)
	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(_player_projectiles().is_empty(), "an empty radar releases nothing")


## Six is the size of the rack: more held time does not buy a seventh, and the
## seventh turret sits past the radar range on purpose.
func _test_missile_cap(weapons: WeaponSystem) -> void:
	await _wait_frames(30)
	var aim: Vector3 = _aim()
	var targets: Array[Enemy] = []
	for index in 7:
		targets.append(_spawn_enemy(_player.global_position + aim * float(14 + index * 6)))
	_check(targets.size() == 7, "spawned seven turrets around the radar edge")
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(120)
	_check(
		weapons.salvo_count() == 6,
		"the rack caps at six (loaded %d)" % weapons.salvo_count()
	)

	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(
		_player_projectiles().size() == 6,
		"six loaded missiles leave (got %d)" % _player_projectiles().size()
	)

	# The cooldown right after a salvo: holding restarts nothing.
	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(
		weapons.salvo_count() == 0,
		"the salvo cooldown blocks the next charge (loaded %d)" % weapons.salvo_count()
	)
	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(
		_player_projectiles().size() == 6,
		"nothing leaves while the rack cools (got %d)" % _player_projectiles().size()
	)
	_clear_projectiles()


## A tap shorter than the load interval fires nothing at all: the hold is the
## weapon, not the press.
func _test_missile_tap(weapons: WeaponSystem) -> void:
	_clear_enemies()
	await _wait_frames(30)

	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 18.0)
	_check(enemy != null, "spawned a turret for the tap")
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(4)
	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(
		weapons.salvo_count() == 0,
		"a tap loads no missiles (loaded %d)" % weapons.salvo_count()
	)
	_check(_player_projectiles().is_empty(), "a tap fires nothing at all")

	# The same press, held past one interval, does load.
	Input.action_press(&"missile")
	await _wait_frames(20)
	_check(
		weapons.salvo_count() == 1,
		"holding past the interval loads one (loaded %d)" % weapons.salvo_count()
	)
	Input.action_release(&"missile")
	await _wait_frames(2)
	_check(_player_projectiles().size() == 1, "one loaded missile leaves")
	_clear_projectiles()


## The salvo leaves from the wings, one missile per wing and alternating sides. The
## hardpoint is read from the wing bone, so it rides the sweep instead of sitting at
## the nose, and consecutive missiles pick opposite sides.
func _test_missile_wings(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	await _wait_frames(40)

	var model: PlayerModel = _player.get("_model") as PlayerModel
	_check(model != null, "the airframe exposes its wing bones")
	if model == null:
		return
	var local: Array[Vector3] = model.wing_anchors()
	_check(local.size() == 2, "the airframe carries two wing hardpoints")
	if local.size() < 2:
		return

	var aim: Vector3 = _aim()
	var right: Vector3 = Vector3(-aim.z, 0.0, aim.x)
	var raw: Array = _player.call("_wing_hardpoints")
	var points: Array[Vector3] = []
	for item in raw:
		points.append(item)
	_check(points.size() == 2, "the player reports both wing hardpoints")
	if points.size() < 2:
		return

	var first: float = (points[0] - _player.global_position).dot(right)
	var second: float = (points[1] - _player.global_position).dot(right)
	_check(
		absf(first) > 0.5 and absf(second) > 0.5,
		"the hardpoints sit out on the wings (%.2f / %.2f off centre)" % [first, second]
	)
	_check(
		first * second < 0.0,
		"the hardpoints straddle the hull (%.2f / %.2f)" % [first, second]
	)

	var enemy: Enemy = _spawn_enemy(_player.global_position + aim * 18.0)
	_check(enemy != null, "spawned a contact for the wing salvo")
	await _wait_frames(2)

	Input.action_press(&"missile")
	await _wait_frames(60)
	_check(
		weapons.salvo_count() >= 2,
		"the rack loads a pair for the wing salvo (loaded %d)" % weapons.salvo_count()
	)
	Input.action_release(&"missile")
	await _wait_frames(2)

	var flight: Array[Projectile] = _player_projectiles()
	_check(flight.size() >= 2, "a pair of missiles leaves (got %d)" % flight.size())
	if flight.size() < 2:
		return

	var sides: Array[float] = []
	for missile in flight:
		sides.append((missile.global_position - _player.global_position).dot(right))
	_check(absf(sides[0]) > 0.5, "the first missile leaves from a wing (%.2f)" % sides[0])
	for index in range(1, sides.size()):
		_check(
			sides[index - 1] * sides[index] < 0.0,
			"consecutive missiles alternate wings (%.2f then %.2f)"
			% [sides[index - 1], sides[index]]
		)
	_clear_projectiles()


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _unique_count(values: Array) -> int:
	var seen: Array = []
	for value in values:
		if not seen.has(value):
			seen.append(value)
	return seen.size()


## The shape is the weapon's identity on screen, so it is owned by the weapon style
## and not inferred from guidance: guidance stays a property of the flight.
func _test_missile_style(missile: Projectile) -> void:
	_check(
		int(missile.get("_style")) == Projectile.Style.MISSILE,
		"the player missile asks for the missile model"
	)
	_check(
		_mesh_parts(missile) >= 4,
		"the missile model is more than a box: body, nose, fins and exhaust"
	)


## The trail is read in motion, so it is checked in motion: puffs have to appear
## behind the shot, and they have to outlive it instead of vanishing with it.
func _test_missile_trail(missile: Projectile) -> void:
	for _i in 6:
		await get_tree().physics_frame

	var puffs: Array[Node] = get_tree().get_nodes_in_group(&"smoke_puff")
	_check(not puffs.is_empty(), "a missile leaves a smoke trail behind it")
	if puffs.is_empty():
		return

	var shot: Vector3 = missile.get("_velocity")
	var heading: Vector3 = shot.normalized()
	var sample: Node3D = null
	var behind: bool = true
	for node in puffs:
		var puff: Node3D = node as Node3D
		if puff == null:
			continue
		if (puff.global_position - missile.global_position).dot(heading) > 0.05:
			behind = false
		elif sample == null:
			sample = puff
	_check(behind, "every puff trails behind the missile, never ahead of it")

	if sample == null:
		return

	missile.queue_free()
	await get_tree().physics_frame
	_check(
		is_instance_valid(sample), "the smoke already in the air survives the missile"
	)

	for _i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(sample):
			break
	_check(not is_instance_valid(sample), "the puffs fade out and free themselves")


## The missile model is built on its own path, and that path used to allocate a
## MeshInstance3D it never parented: one orphan node per shot, which surfaces at
## exit as a leaked RID. The orphan counter is the cheap proof, and it has to stay
## flat across the spawn.
func _test_missile_orphans() -> void:
	var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var missile: Projectile = _spawn_enemy_missile(Vector3(0.0, 0.0, 30.0), _player)
	await get_tree().physics_frame
	var after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(
		after == before,
		"building a missile model leaves no orphan node (before %d, after %d)"
		% [before, after]
	)
	missile.queue_free()
	await get_tree().physics_frame


func _mesh_parts(node: Node) -> int:
	var total: int = 0
	for child in node.get_children():
		if child is MeshInstance3D:
			total += 1
		total += _mesh_parts(child)
	return total


## The bomb is the emergency button, so it has to pay out in one frame: damage, the
## cancel, and the charge spent. A bomb that only cancels is a dodge, not a bomb.
func _test_bomb(weapons: WeaponSystem) -> void:
	var start: int = weapons.bomb_charges()
	_check(
		start == Arsenal.BOMB_START_CHARGES,
		"the bomb starts with %d charges (found %d)" % [Arsenal.BOMB_START_CHARGES, start]
	)

	var enemy: Enemy = _spawn_enemy(_player.global_position + _aim() * 10.0)
	var before: int = enemy.current_hp() if enemy != null else 0

	_clear_projectiles()
	await get_tree().physics_frame
	var first: Projectile = _spawn_enemy_bullet(_player.global_position + Vector3(2.0, 0.0, 2.0))
	var second: Projectile = _spawn_enemy_bullet(_player.global_position - Vector3(2.0, 0.0, 3.0))
	await get_tree().physics_frame

	Input.action_press(&"bomb")
	await get_tree().physics_frame
	Input.action_release(&"bomb")
	await get_tree().physics_frame

	_check(weapons.bomb_charges() == start - 1, "the bomb spends one charge")
	_check(
		not is_instance_valid(first) and not is_instance_valid(second),
		"the bomb cancels enemy fire around the ship"
	)
	_check(
		not is_instance_valid(enemy) or enemy.current_hp() < before,
		"the bomb damages enemies inside the blast"
	)

	_clear_enemies()
	await get_tree().physics_frame


## A resource that never comes back is a save-for-later item, not an emergency
## button: kills have to pay for it, and the rack has to stop at its cap.
func _test_bomb_refill(weapons: WeaponSystem) -> void:
	var before: int = weapons.bomb_charges()
	for _i in Arsenal.BOMB_KILLS_PER_CHARGE:
		GlobalEventBus.enemy_killed.emit()
	await get_tree().physics_frame
	_check(
		weapons.bomb_charges() == before + 1,
		"%d kills refund one charge (%d -> %d)"
		% [Arsenal.BOMB_KILLS_PER_CHARGE, before, weapons.bomb_charges()]
	)

	for _i in Arsenal.BOMB_KILLS_PER_CHARGE * Arsenal.BOMB_MAX_CHARGES:
		GlobalEventBus.enemy_killed.emit()
	await get_tree().physics_frame
	_check(
		weapons.bomb_charges() == Arsenal.BOMB_MAX_CHARGES,
		"the rack caps at %d charges (found %d)"
		% [Arsenal.BOMB_MAX_CHARGES, weapons.bomb_charges()]
	)


## The decoy is a countermeasure, not a weapon: the only thing it has to do is take
## a guided shot off the ship and leave it flying straight when the flare burns out.
func _test_decoy(weapons: WeaponSystem) -> void:
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	var missile: Projectile = _spawn_enemy_missile(Vector3(0.0, 0.0, 14.0), _player)
	_check(bool(missile.call("is_homing")), "an enemy missile is a guided shot")
	_check(missile.get("_target") == _player, "a guided shot starts on the ship")

	_check(weapons.drop_decoy(Vector3.ZERO), "the ship drops a decoy")

	# The ship leaves the spot: the flare only pays if the missile is now heading
	# somewhere the player is not.
	_player.global_position = Vector3(30.0, 0.0, -20.0)
	for _i in 4:
		await get_tree().physics_frame

	var decoy: Node3D = null
	for node in get_tree().get_nodes_in_group(&"decoy"):
		decoy = node as Node3D
	_check(decoy != null, "the decoy joins the decoy group")
	_check(missile.get("_target") == decoy, "the decoy takes the missile's lock")
	_check(
		not weapons.drop_decoy(_player.global_position),
		"the decoy has a cooldown"
	)

	# A shot with nothing left to chase flies straight: the drop buys distance,
	# never a kill. The flare is set alight early instead of waiting the whole
	# three seconds, which is the same path the lifetime takes.
	if decoy != null:
		decoy.set("_life", 0.05)
	for _i in 8:
		await get_tree().physics_frame
	_check(not is_instance_valid(decoy), "the decoy burns out")

	if is_instance_valid(missile):
		var heading: Vector3 = missile.get("_velocity")
		for _i in 10:
			await get_tree().physics_frame
		var after: Vector3 = missile.get("_velocity")
		_check(
			after.is_equal_approx(heading),
			"the missile flies straight once the decoy is gone"
		)
	else:
		_check(false, "the missile survives the decoy")

	_clear_projectiles()
	for node in get_tree().get_nodes_in_group(&"decoy"):
		node.queue_free()
	await get_tree().physics_frame


## Interception is the second answer to a guided shot, and it is deliberately
## narrow: the missile is a target, a bullet from a pattern is not. Making every
## orb shootable would turn a bullet-hell pattern into a wall of props, so the two
## halves are checked together.
func _test_missile_intercept() -> void:
	_clear_projectiles()
	_clear_enemies()
	await get_tree().physics_frame

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	# Both shots are parked well off to the side and aimed at each other, so the
	# check is the interception and not a race against a missile reaching the ship.
	var dummy: Node3D = Node3D.new()
	add_child(dummy)
	dummy.global_position = Vector3(-40.0, 0.0, -60.0)

	var missile: Projectile = _spawn_enemy_missile(Vector3(-40.0, 0.0, 20.0), dummy)
	_spawn_player_bullet(Vector3(-40.0, 0.0, 10.0), Vector3(0.0, 0.0, 1.0))
	for _i in 30:
		await get_tree().physics_frame
		if not is_instance_valid(missile):
			break
	_check(
		not is_instance_valid(missile),
		"a player shot destroys an enemy missile"
	)

	var orb_scene: PackedScene = load("res://combat/projectile.tscn")
	var orb: Projectile = orb_scene.instantiate() as Projectile
	add_child(orb)
	orb.global_position = Vector3(-40.0, 0.0, 20.0)
	orb.setup(Vector3(0.0, 0.0, -1.0), 20.0, Projectile.Team.ENEMY, 1)
	_spawn_player_bullet(Vector3(-40.0, 0.0, 10.0), Vector3(0.0, 0.0, 1.0))
	for _i in 30:
		await get_tree().physics_frame
	_check(
		is_instance_valid(orb),
		"a player shot passes through a bullet pattern"
	)

	dummy.queue_free()
	_clear_projectiles()
	await get_tree().physics_frame


func _test_firing_costs_no_speed(weapons: WeaponSystem) -> void:
	weapons.select(Arsenal.Kind.VULCAN)
	Input.action_press(&"move_right")
	Input.action_press(&"fire")
	for _i in 60:
		await get_tree().physics_frame
	var speed: float = _flat_speed()
	Input.action_release(&"fire")
	Input.action_release(&"move_right")

	_check(
		absf(speed - Player.MAX_SPEED) < 2.0,
		"firing costs no translation speed (%.1f u/s)" % speed
	)
	_clear_projectiles()
	await get_tree().physics_frame


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
	add_child(bullet)
	bullet.global_position = position
	bullet.setup(Vector3(1.0, 0.0, 0.0), 20.0, Projectile.Team.ENEMY, 1)
	return bullet


## A player shot, built the way the vulcan builds one: same scene, same team, same
## layer the interception check depends on.
func _spawn_player_bullet(position: Vector3, direction: Vector3) -> Projectile:
	var scene: PackedScene = load("res://combat/projectile.tscn")
	var bullet: Projectile = scene.instantiate() as Projectile
	add_child(bullet)
	bullet.global_position = position
	bullet.setup(direction, 40.0, Projectile.Team.PLAYER, 1)
	return bullet


## A guided enemy shot, built the way the launcher builds one, so the decoy check
## exercises the same projectile contract the enemy actually fires.
func _spawn_enemy_missile(position: Vector3, target: Node3D) -> Projectile:
	var scene: PackedScene = load("res://combat/projectile.tscn")
	var missile: Projectile = scene.instantiate() as Projectile
	add_child(missile)
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


func _player_projectiles() -> Array[Projectile]:
	var found: Array[Projectile] = []
	for child in get_children():
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


## The planet has no boundary any more: the surface under the ship is replaced as
## the planet rolls, so a straight line must keep going forever.
func _test_travel_is_unbounded() -> void:
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame

	var planet: Node3D = _arena.get_node("Planet")
	var worst_offset: float = 0.0

	Input.action_press(&"move_right")
	for _i in 300:
		await get_tree().physics_frame
		worst_offset = maxf(worst_offset, _planet_offset(planet))
	Input.action_release(&"move_right")

	_check(
		_player.global_position.x > 60.0,
		"the player keeps travelling with no boundary (x %.1f)" % _player.global_position.x
	)
	# Lateral drift is not asserted here: turrets stream in along the heading, and
	# sliding around one is correct physics, not a broken play plane. Height is the
	# invariant — the ship never leaves y = 0 no matter what it meets.
	_check(
		absf(_player.global_position.y) < 0.1,
		"travelling keeps the player on the play plane (y %.3f)" % _player.global_position.y
	)
	# One frame of slack: the assertion may resume before this frame's physics
	# step, so at full speed the planet can legitimately be one step behind.
	_check(
		worst_offset < 1.0,
		"the planet stays under the player while travelling (worst offset %.2f)" % worst_offset
	)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var settled_offset: float = _planet_offset(planet)
	_check(
		settled_offset < 0.01,
		"the planet settles exactly under the player (offset %.4f)" % settled_offset
	)

	# The camera is a child of the player, so a drifting rig would show up here.
	var camera: Camera3D = _player.camera
	if camera != null:
		var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
		var projected: Vector2 = camera.unproject_position(_player.global_position)
		var offset: float = projected.distance_to(centre)
		# The rig trails the body under thrust, so the ship leads the frame by a
		# bounded handful of pixels instead of sitting dead centre like a HUD icon.
		_check(
			offset < 16.0,
			"the camera leads the ship without losing it (off by %.2f px)" % offset
		)


## Rolling without slipping: the planet must turn exactly distance / radius, about
## the axis perpendicular to the movement, in the direction that makes the ground
## flow backwards under the ship.
func _test_planet_rolls_with_the_player() -> void:
	var planet: Node3D = _arena.get_node("Planet")

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	var start_basis: Basis = planet.global_transform.basis
	var start_position: Vector3 = _player.global_position

	Input.action_press(&"move_right")
	for _i in 90:
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	await get_tree().physics_frame

	var travelled: Vector3 = _player.global_position - start_position
	var distance: float = Vector2(travelled.x, travelled.z).length()
	_check(distance > 20.0, "the roll test covers ground (%.1f units)" % distance)

	# Movement is applied as a world-space pre-rotation, so current * start^-1 is
	# the accumulated spin itself.
	var spin: Basis = planet.global_transform.basis * start_basis.inverse()
	var rotation: Quaternion = spin.get_rotation_quaternion()
	var angle: float = rotation.get_angle()
	var axis: Vector3 = rotation.get_axis()
	var expected: float = distance / Arena.PLANET_RADIUS

	_check(
		absf(angle - expected) < maxf(0.002, expected * 0.1),
		"the planet turns distance / radius (%.4f rad, expected %.4f)" % [angle, expected]
	)
	_check(
		axis.z > 0.95,
		"moving right rolls the planet about +Z so the ground flows left (%s)" % axis
	)

	# No input, no roll: the surface must not creep while the ship hovers.
	_player.velocity = Vector3.ZERO
	for _i in 3:
		await get_tree().physics_frame
	var idle_basis: Basis = planet.global_transform.basis
	for _i in 30:
		await get_tree().physics_frame
	var idle_spin: float = (planet.global_transform.basis * idle_basis.inverse())\
		.get_rotation_quaternion().get_angle()
	_check(idle_spin < 0.01, "the planet holds still while the ship hovers (%.4f rad)" % idle_spin)


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
	return (_player.velocity - Player.WIND).dot(right)


## The fighter jink's push split on the airframe: x along the nose, y to its
## right. `_roll_velocity` is exactly the push applied on this frame, so the pair
## says which way the step goes with the steady flight left out.
func _jink_push() -> Vector2:
	var heading: Vector3 = _player.get("_heading")
	var right: Vector3 = Vector3(-heading.z, 0.0, heading.x)
	var push: Vector3 = _player.get("_roll_velocity")
	return Vector2(push.dot(heading), push.dot(right))


func _test_damage_and_iframes() -> void:
	# The encounter phase can legitimately land a hit, and this check is about
	# invulnerability frames, not about arriving at full health. The frames are
	# cleared too: an enemy hit a moment earlier would swallow the first one and
	# the test would pass or fail on timing.
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)

	var event_bus_health: Array[int] = []
	GlobalEventBus.player_health_changed.connect(
		func(current: int, _maximum: int) -> void: event_bus_health.append(current)
	)

	_player.take_damage(1)
	await get_tree().physics_frame
	_player.take_damage(1)
	await get_tree().physics_frame

	var health: int = _player.get("_hp")
	_check(health == Player.MAX_HP - 1, "invulnerability frames block a second hit (hp %d)" % health)
	_check(
		not event_bus_health.is_empty(),
		"health changes reach the event bus for the HUD"
	)


func _test_death() -> void:
	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var game_over: GameOver = hud.get_node("%GameOver") as GameOver
	var counter: Label = hud.get_node("%Counter") as Label
	_check(not game_over.visible, "the death screen starts hidden")

	# The HUD turns both answers into a scene change, and reloading here would
	# restart the scene this test runs in. The answers are the unit under test, so
	# the HUD's handlers are detached for the rest of the check; the countdown is
	# detached too, because it would answer on its own five seconds in.
	for connection in game_over.respawn_requested.get_connections():
		game_over.respawn_requested.disconnect(connection["callable"])
	for connection in game_over.menu_requested.get_connections():
		game_over.menu_requested.disconnect(connection["callable"])

	while int(_player.get("_hp")) > 0:
		_player.set("_invulnerable", 0.0)
		_player.take_damage(1)
		await get_tree().physics_frame

	_check(int(_player.get("_hp")) == 0, "health drains to zero")
	_check(_died_count > 0, "player_died reaches the event bus")
	_check(not bool(_player.get("_alive")), "player enters a dead state")

	# The screen opens on the death event and starts the count on the same frame,
	# so a frame of `_process` has already run by the time the loop above returns.
	_check(game_over.visible, "death opens the game over screen")
	_check(
		game_over.remaining > 0.0 and game_over.remaining <= GameOver.RESPAWN_SECONDS,
		"the countdown starts full (%.2f of %.0f)" % [game_over.remaining, GameOver.RESPAWN_SECONDS]
	)
	_check(
		counter.text == "RESPAWN IN %d" % GameOver.RESPAWN_SECONDS,
		"the counter reads the full countdown (\"%s\")" % counter.text
	)

	var before: float = game_over.remaining
	await get_tree().physics_frame
	_check(game_over.remaining < before, "the countdown ticks down with the frame")
	_check(counter.text.begins_with("RESPAWN IN "), "the counter stays a countdown (\"%s\")" % counter.text)

	# Each answer is checked for the signal it raises; navigation stays with the HUD,
	# whose handlers were detached above.
	var respawns: Array[bool] = []
	var menus: Array[bool] = []
	game_over.respawn_requested.connect(func() -> void: respawns.append(true))
	game_over.menu_requested.connect(func() -> void: menus.append(true))

	var continue_button: Button = hud.get_node("%ContinueButton") as Button
	var menu_button: Button = hud.get_node("%MenuButton") as Button
	_check(continue_button.has_focus(), "the continue button takes the focus for a gamepad")

	continue_button.pressed.emit()
	_check(respawns.size() == 1, "CONTINUE asks for a respawn")
	_check(menus.is_empty(), "CONTINUE does not also ask for the menu")

	game_over.start()
	menu_button.pressed.emit()
	_check(menus.size() == 1, "MAIN MENU asks for the menu")
	_check(respawns.size() == 1, "MAIN MENU does not also ask for a respawn")

	game_over.start()
	var restart_event: InputEventAction = InputEventAction.new()
	restart_event.action = &"restart"
	restart_event.pressed = true
	game_over._unhandled_input(restart_event)
	_check(respawns.size() == 2, "R continues the run")

	game_over.start()
	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	game_over._unhandled_input(cancel_event)
	_check(menus.size() == 2, "ESC leaves for the menu")

	# Disarmed by the last answer: a live countdown would reload the arena while the
	# rest of the suite is still running.
	var stopped_at: float = game_over.remaining
	await get_tree().physics_frame
	_check(game_over.remaining == stopped_at, "one answer stops the countdown")


func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group(&"enemy"):
		enemy.queue_free()


func _clear_projectiles() -> void:
	for child in get_children():
		if child is Projectile:
			child.queue_free()


func _count_projectiles(team: int) -> int:
	var total: int = 0
	for child in get_children():
		if child is Projectile and int(child.get("_team")) == team:
			total += 1
	return total


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
		return
	_failures.append(description)
	printerr("  FAIL  ", description)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("SMOKE TEST PASSED")
		get_tree().quit(0)
		return

	printerr("SMOKE TEST FAILED (%d)" % _failures.size())
	for failure in _failures:
		printerr("  - ", failure)
	get_tree().quit(1)
