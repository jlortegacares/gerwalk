class_name Projectile
extends Area3D
## Lightweight bullet. Travels in a straight line on the play plane, reports the
## hit, then frees. Prototype scale: node-per-bullet. If NFR-05 (400 concurrent)
## becomes the bottleneck, migrate to a pooled manager before adding content.
##
## Everything lives on the y = 0 plane. The third dimension is presentation, not
## gameplay: hitboxes stay planar so bullet patterns keep the readability the
## twin-stick genre depends on.

enum Team {
	PLAYER,
	ENEMY,
}

## Shape is chosen by the weapon, not inferred from guidance: a homing shot and a
## straight dart both exist, and the model is presentation the caller owns.
enum Style {
	DART,
	ORB,
	MISSILE,
}

## Collision layers (1-based in the editor, bit index here).
const LAYER_WORLD: int = 0
const LAYER_PLAYER: int = 1
const LAYER_PLAYER_BULLET: int = 2
const LAYER_ENEMY: int = 3
const LAYER_ENEMY_BULLET: int = 4

const LIFETIME: float = 3.5
const PLAYER_COLOR: Color = Color(0.55, 0.98, 0.9, 1.0)
const ENEMY_COLOR: Color = Color(1.0, 0.42, 0.52, 1.0)

## Elongated on Z so a single Y rotation aligns the long axis with travel.
const DART_SIZE: Vector3 = Vector3(0.42, 0.34, 1.6)
const ORB_RADIUS: float = 0.55

## Exhaust trail. Puffs are dropped into the scene, not parented to the missile, so
## the smoke already in the air survives the impact that frees the shot.
##
## The spacing at the missile's speed is what decides smoke versus dotted line: one
## puff every TRAIL_INTERVAL has to overlap the last one, so the interval stays
## tight and the puffs grow past the gap between them.
const TRAIL_INTERVAL: float = 0.022
const TRAIL_PUFF_LIFETIME: float = 0.62
const TRAIL_START_RADIUS: float = 0.10
const TRAIL_END_RADIUS: float = 0.55
## A fraction of the missile's speed: enough to curl with a guided turn, little
## enough that the shot instantly outruns its own smoke.
const TRAIL_INHERIT: float = 0.18

@export var impact_scene: PackedScene

var _velocity: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _damage: int = 1
var _team: Team = Team.PLAYER
var _life: float = LIFETIME
var _target: Node3D = null
var _turn_rate: float = 0.0
var _style: Style = Style.DART
var _trail_offset: float = 0.0
var _trail_timer: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if _team == Team.ENEMY:
		add_to_group(&"enemy_bullet")


## `tint` lets a player weapon keep its own colour (a warm missile, a plasma
## bolt) while the team still owns the shape and the collision layers. A
## transparent tint means "use the team colour".
func setup(
	direction: Vector3,
	speed: float,
	team: Team,
	damage: int = 1,
	size: Vector3 = DART_SIZE,
	target: Node3D = null,
	turn_rate: float = 0.0,
	tint: Color = Color(0.0, 0.0, 0.0, 0.0),
	lifetime: float = LIFETIME,
	style: Style = Style.DART
) -> void:
	_team = team
	_damage = damage
	_speed = speed
	_target = target
	_turn_rate = turn_rate
	_life = lifetime
	_style = style
	# Enemy fire is tagged here rather than in _ready because callers add the node
	# to the tree before running setup, so the team is unknown at ready time.
	if _team == Team.ENEMY:
		add_to_group(&"enemy_bullet")
	else:
		remove_from_group(&"enemy_bullet")
	_velocity = Vector3(direction.x, 0.0, direction.z).normalized() * speed
	rotation.y = atan2(_velocity.x, _velocity.z)

	var color: Color = tint
	if color.a <= 0.0:
		color = PLAYER_COLOR if _team == Team.PLAYER else ENEMY_COLOR

	# Shape and tint both encode the team: colour alone fails NFR-08 under
	# bullet density, and shape survives a colour-blind pass. Guidance does not
	# change the shape, so a homing shot stays readable as a friendly dart.
	if _team == Team.PLAYER:
		collision_layer = 1 << LAYER_PLAYER_BULLET
		collision_mask = (1 << LAYER_WORLD) | (1 << LAYER_ENEMY)
		_build_visual(size, color)
	else:
		collision_layer = 1 << LAYER_ENEMY_BULLET
		collision_mask = (1 << LAYER_WORLD) | (1 << LAYER_PLAYER)
		# Enemy fire is the orb silhouette whatever the caller asked for: the team
		# read outranks the weapon's own preference.
		_style = Style.ORB
		_build_visual(Vector3.ONE * ORB_RADIUS, color)

	_trail_offset = size.z * 0.5


func _build_visual(size: Vector3, color: Color) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	if _style == Style.ORB:
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = size.x
		sphere.height = size.x * 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		mesh_instance.mesh = sphere
		mesh_instance.material_override = _flat_material(color, 1.6)
	elif _style == Style.MISSILE:
		_build_missile(size, color)
		return
	else:
		var box: BoxMesh = BoxMesh.new()
		box.size = size
		mesh_instance.mesh = box
		mesh_instance.material_override = _flat_material(color, 1.6)

	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


## A missile reads as a missile from any angle the camera can see it: a pointed
## nose, a body with a warhead band, four fins and a lit exhaust cone. Built along
## +Z because `rotation.y` maps +Z onto the flight vector.
func _build_missile(size: Vector3, color: Color) -> void:
	var length: float = maxf(size.z, 0.6)
	var radius: float = clampf(size.x * 0.5, 0.06, 0.32)
	var half: float = length * 0.5
	var nose_length: float = length * 0.24
	var body_length: float = length * 0.70

	var body_material: StandardMaterial3D = _flat_material(Color(0.88, 0.87, 0.83), 0.15)
	var band_material: StandardMaterial3D = _flat_material(color, 1.8)
	var fin_material: StandardMaterial3D = _flat_material(Color(0.26, 0.27, 0.31), 0.1)

	var body: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius = radius
	body_mesh.bottom_radius = radius * 0.94
	body_mesh.height = body_length
	body_mesh.radial_segments = 10
	body_mesh.rings = 1
	body.mesh = body_mesh
	body.rotation.x = PI * 0.5
	body.position.z = half - nose_length - body_length * 0.5
	body.material_override = body_material
	_add_part(body)

	var nose: MeshInstance3D = MeshInstance3D.new()
	var nose_mesh: CylinderMesh = CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = radius
	nose_mesh.height = nose_length
	nose_mesh.radial_segments = 10
	nose_mesh.rings = 1
	nose.mesh = nose_mesh
	nose.rotation.x = PI * 0.5
	nose.position.z = half - nose_length * 0.5
	nose.material_override = band_material
	_add_part(nose)

	# The warhead band sits just behind the nose join and picks up the weapon tint,
	# so a player missile still reads warm at a glance.
	var band: MeshInstance3D = MeshInstance3D.new()
	var band_mesh: CylinderMesh = CylinderMesh.new()
	band_mesh.top_radius = radius * 1.06
	band_mesh.bottom_radius = radius * 1.06
	band_mesh.height = length * 0.055
	band_mesh.radial_segments = 10
	band_mesh.rings = 1
	band.mesh = band_mesh
	band.rotation.x = PI * 0.5
	band.position.z = half - nose_length - body_length * 0.16
	band.material_override = band_material
	_add_part(band)

	for index in 4:
		var pivot: Node3D = Node3D.new()
		pivot.position = Vector3(0.0, 0.0, -half + length * 0.26)
		pivot.rotation.z = TAU * 0.25 * float(index)
		add_child(pivot)

		# A swept prism, not a slab: the profile is a triangle whose root chord runs
		# fore-aft and whose tip leans back, which is what reads as a fin at this
		# size. Rotation.y turns the extrusion into the plate's thickness.
		var fin: MeshInstance3D = MeshInstance3D.new()
		var fin_mesh: PrismMesh = PrismMesh.new()
		fin_mesh.size = Vector3(length * 0.34, radius * 1.70, 0.05)
		fin_mesh.left_to_right = 0.85
		fin.mesh = fin_mesh
		fin.rotation.y = PI * 0.5
		fin.position = Vector3(0.0, radius * 1.15, 0.0)
		fin.material_override = fin_material
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(fin)

	# A dark nozzle ring separates the airframe from the flame, so the tail reads as
	# hardware instead of a second nose.
	var nozzle: MeshInstance3D = MeshInstance3D.new()
	var nozzle_mesh: CylinderMesh = CylinderMesh.new()
	nozzle_mesh.top_radius = radius * 1.04
	nozzle_mesh.bottom_radius = radius * 0.86
	nozzle_mesh.height = length * 0.07
	nozzle_mesh.radial_segments = 10
	nozzle_mesh.rings = 1
	nozzle.mesh = nozzle_mesh
	nozzle.rotation.x = PI * 0.5
	nozzle.position.z = -half + length * 0.035
	nozzle.material_override = fin_material
	_add_part(nozzle)

	# A long, narrow flame: the silhouette has to be clearly not-a-nose.
	var exhaust: MeshInstance3D = MeshInstance3D.new()
	var exhaust_mesh: CylinderMesh = CylinderMesh.new()
	exhaust_mesh.top_radius = 0.0
	exhaust_mesh.bottom_radius = radius * 0.58
	exhaust_mesh.height = length * 0.22
	exhaust_mesh.radial_segments = 8
	exhaust_mesh.rings = 1
	exhaust.mesh = exhaust_mesh
	# +Y becomes -Z, so the cone tapers away from the tail.
	exhaust.rotation.x = -PI * 0.5
	exhaust.position.z = -half - length * 0.105
	exhaust.material_override = _flat_material(Color(1.0, 0.93, 0.68), 3.2)
	_add_part(exhaust)


func _add_part(part: MeshInstance3D) -> void:
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)


func _flat_material(color: Color, glow: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow
	return material


func _physics_process(delta: float) -> void:
	_steer(delta)
	global_position += _velocity * delta
	_life -= delta
	if _style == Style.MISSILE:
		_emit_trail(delta)

	# The planet has no edge, so lifetime is the only bound on a missed shot.
	if _life <= 0.0:
		queue_free()


## Puffs are dropped at a fixed cadence, not per frame, so the trail stays just as
## dense on a slow machine and the node count stays bounded.
func _emit_trail(delta: float) -> void:
	_trail_timer += delta
	while _trail_timer >= TRAIL_INTERVAL:
		_trail_timer -= TRAIL_INTERVAL
		_spawn_puff()


func _spawn_puff() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	var puff: SmokePuff = SmokePuff.new()
	scene.add_child(puff)
	var heading: Vector3 = _velocity.normalized()
	puff.global_position = global_position - heading * _trail_offset
	# A little sideways and upward drift keeps the plume from drawing a ruler line.
	var drift: Vector3 = Vector3(randf_range(-0.5, 0.5), randf_range(0.1, 0.45), randf_range(-0.5, 0.5))
	puff.launch(
		_velocity * TRAIL_INHERIT + drift,
		TRAIL_START_RADIUS,
		TRAIL_END_RADIUS,
		TRAIL_PUFF_LIFETIME
	)


## Homing shots keep their speed and turn towards the target at a fixed rate, so
## the curve is legible: snapping instantly would look like a second aim, and an
## unbounded turn would orbit the target instead of arriving. A freed target (it
## died mid-flight) simply leaves the shot flying straight.
func _steer(delta: float) -> void:
	if _turn_rate <= 0.0 or not is_instance_valid(_target):
		return

	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return

	var heading: Vector3 = _velocity.normalized()
	var angle: float = heading.signed_angle_to(to_target.normalized(), Vector3.UP)
	var step: float = clampf(angle, -_turn_rate * delta, _turn_rate * delta)
	_velocity = heading.rotated(Vector3.UP, step) * _speed
	rotation.y = atan2(_velocity.x, _velocity.z)


func _on_body_entered(body: Node3D) -> void:
	if body is Player and _team == Team.ENEMY:
		body.take_damage(_damage, global_position)
	elif body is Enemy and _team == Team.PLAYER:
		body.take_damage(_damage)

	_spawn_impact()
	queue_free()


func _spawn_impact() -> void:
	if impact_scene == null:
		return
	var impact: Node3D = impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position
