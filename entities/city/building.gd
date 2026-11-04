class_name Building
extends StaticBody3D
## A city tower: solid to the ship and to fire, and expensive to bring down.
##
## Everything gameplay-relevant in this game lives on the y = 0 plane, so a tower
## is one box standing on the ground. That box sits on the world collision layer,
## which is the layer the ship's capsule and every projectile already collide
## with: the streets are the level because the walls are real, not because the
## level script forbids anything.
##
## The price is the design. A turret is 10 HP and dies to a second of gunfire; a
## tower is MAX_HP and survives several full missile racks, so a demolition is a
## commitment the player chooses instead of a shortcut they stumble into. When it
## finally comes down it stops blocking and leaves rubble, so the street opens
## where the wall was.

signal destroyed(value: int)

## Collision layers, 1-based in the editor and bit index here, matching
## `Projectile`'s constants.
const LAYER_WORLD: int = 0

## About eight seconds of sustained vulcan fire (35 damage per second), fifteen of
## laser, or nine full missile salvos. A tower is a wall you can remove, not cover
## you clear while flying past.
const MAX_HP: int = 300
## More than a turret (100) because it costs about thirty times the fire, less
## than an interceptor (200) because it is not a threat.
const SCORE_VALUE: int = 150

const HIT_FLASH_TIME: float = 0.12
## The bar appears on the first hit and leaves a couple of seconds after the last
## one, so it is a progress readout rather than a label over every roof.
const BAR_LINGER: float = 2.5
const BAR_HEIGHT: float = 2.2
const BAR_WIDTH: float = 7.0
const BAR_THICKNESS: float = 0.62
const HEALTHY_COLOR: Color = Color(0.55, 0.98, 0.9)
const CRITICAL_COLOR: Color = Color(1.0, 0.42, 0.35)

## The collapse is the same detonation every hull gets, scaled to the footprint:
## a 21-unit tower gets a 2.3x blast, a 38-unit perimeter block the 3.4 cap.
const BLAST_SCALE_PER_UNIT: float = 0.11
const BLAST_SCALE_MIN: float = 1.6
const BLAST_SCALE_MAX: float = 3.4
const COLLAPSE_SHAKE: float = 0.85
const RUBBLE_HEIGHT: float = 1.1
const RUBBLE_CHUNKS: int = 5
## How much of the tower the dither removes when the camera is looking past it.
## Enough to see the ship, not so much that the tower stops reading as a wall.
const GHOST_AMOUNT: float = 0.86

const SHADER: Shader = preload("res://entities/city/building.gdshader")

var _hp: int = MAX_HP
var _size: Vector3 = Vector3.ONE
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _bar_root: Node3D
var _bar_fill: MeshInstance3D
var _bar_fill_material: StandardMaterial3D
var _bar_timer: float = 0.0
var _flash: float = 0.0
var _destroyed: bool = false
var _ghosted: bool = false


func _ready() -> void:
	set_process(false)


## Builds the box, its collider and its readout. The city calls this before the
## node enters the tree, so the tower exists complete on its first frame instead
## of showing an empty body for one.
func build(footprint: Vector2, height: float) -> void:
	_size = Vector3(footprint.x, height, footprint.y)
	collision_layer = 1 << LAYER_WORLD
	collision_mask = 0

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = _size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	# The body's origin is the base, which is the point a collapse starts from.
	collider.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(collider)

	_material = ShaderMaterial.new()
	_material.shader = SHADER

	var box: BoxMesh = BoxMesh.new()
	box.size = _size
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.material_override = _material
	_mesh.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(_mesh)

	_build_bar(height)
	_paint()


func _process(delta: float) -> void:
	var busy: bool = false
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		busy = true
	if _bar_timer > 0.0:
		_bar_timer = maxf(_bar_timer - delta, 0.0)
		busy = true
	_paint()
	if not busy:
		set_process(false)


## Only the player damages a tower. Enemy fire is absorbed by the wall, which is
## what makes a street a corridor: the return fire stops at the corner.
func take_damage(amount: int) -> void:
	if _destroyed or amount <= 0:
		return

	_hp = maxi(_hp - amount, 0)
	_flash = HIT_FLASH_TIME
	_bar_timer = BAR_LINGER
	set_process(true)
	_paint()

	if _hp <= 0:
		_collapse()


func current_hp() -> int:
	return _hp


func is_destroyed() -> bool:
	return _destroyed


func is_ghosted() -> bool:
	return _ghosted


func footprint() -> Vector2:
	return Vector2(_size.x, _size.z)


func height() -> float:
	return _size.y


## The camera hangs 65 units up and 17 behind, so a tower in that band hides the
## ship completely. The city traces the sight line every physics frame and asks
## every tower on it to step aside; the shader dithers the geometry out instead of
## blending it, so the tower keeps writing depth while the ship shows through.
func set_ghosted(value: bool) -> void:
	if _ghosted == value or _material == null:
		return
	_ghosted = value
	_material.set_shader_parameter("ghost", GHOST_AMOUNT if value else 0.0)
	if _mesh != null:
		_mesh.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if value
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)


func _paint() -> void:
	var fraction: float = float(_hp) / float(MAX_HP)
	if _material != null:
		_material.set_shader_parameter("damage", 1.0 - fraction)
		# The wash is squared so it snaps rather than glows: a tower covers a third
		# of the screen, and a linear fade keeps the whole wall white for a tenth of
		# a second, which reads as a rendering fault instead of a hit.
		_material.set_shader_parameter(
			"flash", pow(clampf(_flash / HIT_FLASH_TIME, 0.0, 1.0), 2.6)
		)
	if _bar_root == null:
		return

	_bar_root.visible = not _destroyed and _bar_timer > 0.0
	if not _bar_root.visible:
		return
	# The fill is anchored on its left edge, so the bar empties towards the left
	# instead of shrinking towards the middle.
	_bar_fill.scale.x = maxf(fraction, 0.0001)
	_bar_fill.position.x = -BAR_WIDTH * 0.5 * (1.0 - fraction)
	_bar_fill_material.albedo_color = HEALTHY_COLOR.lerp(CRITICAL_COLOR, 1.0 - fraction)


func _collapse() -> void:
	_destroyed = true
	_bar_root.visible = false
	_mesh.visible = false
	# `take_damage` runs inside a `body_entered` callback, so the collision change
	# has to wait for the end of the physics step.
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	_build_rubble()
	_spawn_explosion()
	destroyed.emit(SCORE_VALUE)


## Rubble is scenery: it has no collider, so the street is open the moment the
## tower stops being a wall. Five chunks break the flat slab up enough to read as
## a collapsed building from the game camera.
func _build_rubble() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.195, 0.21)
	material.roughness = 0.96

	var slab: BoxMesh = BoxMesh.new()
	slab.size = Vector3(_size.x * 0.94, RUBBLE_HEIGHT, _size.z * 0.94)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	floor_mesh.mesh = slab
	floor_mesh.material_override = material
	floor_mesh.position.y = RUBBLE_HEIGHT * 0.5
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)

	for index in RUBBLE_CHUNKS:
		var chunk: BoxMesh = BoxMesh.new()
		chunk.size = Vector3(
			randf_range(1.4, 3.2),
			randf_range(0.8, 2.6),
			randf_range(1.4, 3.2)
		)
		var piece: MeshInstance3D = MeshInstance3D.new()
		piece.mesh = chunk
		piece.material_override = material
		piece.position = Vector3(
			randf_range(-_size.x * 0.38, _size.x * 0.38),
			RUBBLE_HEIGHT + chunk.size.y * 0.35,
			randf_range(-_size.z * 0.38, _size.z * 0.38)
		)
		piece.rotation.y = randf() * TAU
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)


## The same blast every hull gets, scaled to the footprint. The shockwave comes
## with it: `ShipExplosion` adds one to every death, and a tower is the biggest
## death in the game.
func _spawn_explosion() -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		return

	var blast: ShipExplosion = ShipExplosion.new()
	blast.shake_strength = COLLAPSE_SHAKE
	blast.scale = Vector3.ONE * clampf(
		_size.x * BLAST_SCALE_PER_UNIT, BLAST_SCALE_MIN, BLAST_SCALE_MAX
	)
	host.add_child(blast)
	blast.global_position = global_position
	Sfx.play_at(&"explosion", global_position)


func _build_bar(height: float) -> void:
	_bar_root = Node3D.new()
	_bar_root.position = Vector3(0.0, height + BAR_HEIGHT, 0.0)
	_bar_root.visible = false
	add_child(_bar_root)

	var backdrop_material: StandardMaterial3D = _bar_material(Color(0.02, 0.03, 0.05, 0.72))
	_bar_root.add_child(_bar_quad(BAR_WIDTH + 0.3, BAR_THICKNESS + 0.3, backdrop_material))

	_bar_fill_material = _bar_material(HEALTHY_COLOR)
	_bar_fill = _bar_quad(BAR_WIDTH, BAR_THICKNESS, _bar_fill_material)
	_bar_root.add_child(_bar_fill)


## Unshaded, billboarded and always on top: a progress readout that a roof or a
## neighbouring tower can hide is not a readout.
func _bar_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material


func _bar_quad(width: float, thickness: float, material: StandardMaterial3D) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(width, thickness)
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
