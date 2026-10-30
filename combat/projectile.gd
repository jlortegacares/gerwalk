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
## Enemy missiles get a layer of their own so the player can shoot them down
## without turning every orb in a bullet pattern into a destructible prop.
const LAYER_ENEMY_MISSILE: int = 5

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
## tight and the puffs grow past the gap between them. It is tuned against the
## fastest shot in the game (the player's missile at 42), where one interval is
## still under a puff's diameter at the tail.
const TRAIL_INTERVAL: float = 0.017
const TRAIL_PUFF_LIFETIME: float = 0.85
const TRAIL_START_RADIUS: float = 0.10
const TRAIL_END_RADIUS: float = 0.62
## A fraction of the missile's speed: enough to curl with a guided turn, little
## enough that the shot instantly outruns its own smoke. Higher than a straight
## shot needs, because the weave is what the trail is meant to show.
const TRAIL_INHERIT: float = 0.24

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
## Straight flight left before the guidance engages. The player's salvo uses it so
## the fan is readable before the shots commit to their targets.
var _guidance_timer: float = 0.0
## Flight time, used by the weave's phase.
var _age: float = 0.0
## The weave: the heading is swung off the line of sight by `_weave_amplitude`
## radians at `_weave_rate` radians per second, with a phase per missile so a
## salvo braids. It fades to zero inside `_weave_hit_range`, where the shot must
## fly straight enough to hit what it was locked onto.
var _weave_amplitude: float = 0.0
var _weave_rate: float = 0.0
var _weave_phase: float = 0.0
var _weave_hit_range: float = 0.0
var _weave_fade: float = 1.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
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
		# The missile layer is in the mask so gunfire can intercept a guided shot.
		# Nothing else lives there, so a pattern still passes through untouched.
		collision_mask = (
			(1 << LAYER_WORLD) | (1 << LAYER_ENEMY) | (1 << LAYER_ENEMY_MISSILE)
		)
		_build_visual(size, color)
	else:
		collision_mask = (1 << LAYER_WORLD) | (1 << LAYER_PLAYER)
		# Enemy fire is the orb silhouette by default: the team read outranks the
		# weapon's own preference. A missile is the exception, because its shape is
		# the warning that it is guided, can be shaken off and can be shot down.
		if _style == Style.MISSILE:
			collision_layer = 1 << LAYER_ENEMY_MISSILE
			# A bullet is not monitorable because nothing should ever detect one. A
			# missile is the opposite: it is a target, so the player's fire has to be
			# able to see it.
			monitorable = true
			add_to_group(&"enemy_missile")
			_build_visual(size, color)
		else:
			collision_layer = 1 << LAYER_ENEMY_BULLET
			_style = Style.ORB
			_build_visual(Vector3.ONE * ORB_RADIUS, color)

	_trail_offset = size.z * 0.5


func _build_visual(size: Vector3, color: Color) -> void:
	# The missile builds its own node tree, so it is answered before the shared
	# mesh is allocated: an unused MeshInstance3D here would never be parented and
	# would leak one node per shot.
	if _style == Style.MISSILE:
		_build_missile(size, color)
		return

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	if _style == Style.ORB:
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = size.x
		sphere.height = size.x * 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		mesh_instance.mesh = sphere
		mesh_instance.material_override = _flat_material(color, 1.6)
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
	_age += delta
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


## A shot is guided when it has a turn rate. Only a guided shot can be pulled off
## its chase, which is what makes the decoy worth dropping on one.
func is_homing() -> bool:
	return _turn_rate > 0.0


## Holds the shot on its launch heading for `seconds` before the guidance engages.
## A salvo that turns on the launch frame folds into one line before the spread is
## readable; the delay is what lets the fan open first.
func set_guidance_delay(seconds: float) -> void:
	_guidance_timer = maxf(seconds, 0.0)


## Makes the shot weave around its line of sight instead of tracking it dead
## straight, which is what draws the braided smoke of a Macross salvo. `phase`
## separates a salvo's shots so they do not weave in step, and the weave fades out
## inside `hit_range` so the shot still arrives.
func set_weave(
	amplitude: float, rate: float, phase: float, hit_range: float, fade: float
) -> void:
	_weave_amplitude = maxf(amplitude, 0.0)
	_weave_rate = maxf(rate, 0.0)
	_weave_phase = phase
	_weave_hit_range = maxf(hit_range, 0.0)
	_weave_fade = maxf(fade, 0.01)


## Hands the guidance to another target. The decoy is the only caller: the flare
## takes the lock for as long as it burns, and the shot is left with nothing when
## it is gone.
func retarget(target: Node3D) -> void:
	_target = target


## Homing shots keep their speed and turn towards the target at a fixed rate, so
## the curve is legible: snapping instantly would look like a second aim, and an
## unbounded turn would orbit the target instead of arriving. A freed target (it
## died mid-flight, or a decoy burned out) simply leaves the shot flying straight.
func _steer(delta: float) -> void:
	if _turn_rate <= 0.0:
		return

	# The salvo's fan is only readable while the shots hold their launch heading.
	if _guidance_timer > 0.0:
		_guidance_timer = maxf(_guidance_timer - delta, 0.0)
		return

	# Enemy guidance is dumb enough to be fooled: any flare close enough outranks
	# the ship. The check runs every frame rather than once on the drop, so a
	# missile that arrives after the flare was dropped still takes it. Once the
	# lock is on a flare the scan stops, because nothing outranks a flare.
	if _team == Team.ENEMY:
		if not is_instance_valid(_target) or not _target.is_in_group(&"decoy"):
			var decoy: Node3D = _nearest_decoy()
			if decoy != null:
				retarget(decoy)

	if not is_instance_valid(_target):
		return

	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return

	var heading: Vector3 = _velocity.normalized()
	var desired: Vector3 = to_target.normalized()
	# The weave swings the aim direction itself, not the per-frame step. A step is
	# already an angle, so adding a swing to it would turn at a rate the missile
	# never asked for and send the shot spiralling off the target instead of at it.
	if _weave_amplitude > 0.0:
		var distance: float = to_target.length()
		var weight: float = clampf(
			(distance - _weave_hit_range) / _weave_fade, 0.0, 1.0
		)
		var swing: float = sin(_age * _weave_rate + _weave_phase) * _weave_amplitude * weight
		desired = desired.rotated(Vector3.UP, swing)

	var angle: float = heading.signed_angle_to(desired, Vector3.UP)
	var step: float = clampf(angle, -_turn_rate * delta, _turn_rate * delta)
	_velocity = heading.rotated(Vector3.UP, step) * _speed
	rotation.y = atan2(_velocity.x, _velocity.z)


## The flare with the strongest pull: the closest one inside its own capture
## radius, measured on the play plane like every other range in the prototype.
## Null means nothing close enough is spoofing, so the current target stands.
func _nearest_decoy() -> Node3D:
	var best: Node3D = null
	var best_distance: float = Decoy.CAPTURE_RADIUS
	for node in get_tree().get_nodes_in_group(&"decoy"):
		var decoy: Node3D = node as Node3D
		if decoy == null:
			continue
		var distance: float = Vector2(
			decoy.global_position.x - global_position.x,
			decoy.global_position.z - global_position.z
		).length()
		if distance <= best_distance:
			best_distance = distance
			best = decoy
	return best


func _on_body_entered(body: Node3D) -> void:
	if body is Player and _team == Team.ENEMY:
		body.take_damage(_damage, global_position)
	elif body is Enemy and _team == Team.PLAYER:
		body.take_damage(_damage)

	_spawn_impact()
	queue_free()


## Shooting down a missile is a player privilege, and the layer makes it a cheap
## check: only guided enemy shots sit on the missile layer, so anything the player's
## fire meets there is worth killing. An orb never reaches this function.
func _on_area_entered(area: Area3D) -> void:
	if _team != Team.PLAYER:
		return
	if not area.is_in_group(&"enemy_missile"):
		return
	if area.is_queued_for_deletion():
		return

	area.queue_free()
	_spawn_impact()
	queue_free()


func _spawn_impact() -> void:
	if impact_scene == null:
		return
	var impact: Node3D = impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position
