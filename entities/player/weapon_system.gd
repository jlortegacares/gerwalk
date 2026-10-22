class_name WeaponSystem
extends Node3D
## The player's primary arsenal. The player node owns flight, aim and HP; this node
## owns what comes out of the nose, so `player.gd` keeps reading as "how the ship
## flies" instead of "how the ship flies plus three weapons".
##
## Everything fires along the aim vector on the play plane, and nothing here
## touches the ship's velocity: firing must never cost speed.

var _bullet_scene: PackedScene
var _kind: Arsenal.Kind = Arsenal.Kind.VULCAN
var _cooldown: float = 0.0
var _laser_tick: float = 0.0
var _beam: Node3D


func setup(bullet_scene: PackedScene) -> void:
	_bullet_scene = bullet_scene


func _ready() -> void:
	_build_beam()


func kind() -> Arsenal.Kind:
	return _kind


## Switching is instant and always legal: the weapons are a player choice, not a
## pickup economy. A switch also clears the cadence so the new weapon can fire on
## the same frame instead of inheriting the old one's wait.
func select(kind: Arsenal.Kind) -> void:
	if kind == _kind:
		return
	_kind = kind
	_cooldown = 0.0
	_laser_tick = 0.0
	GlobalEventBus.player_weapon_changed.emit(Arsenal.NAMES[_kind])


func cycle(step: int) -> void:
	var kinds: Array = Arsenal.Kind.values()
	var index: int = (kinds.find(_kind) + step + kinds.size()) % kinds.size()
	select(kinds[index])


func tick(delta: float, muzzle: Vector3, direction: Vector3, wants_fire: bool) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	# The beam is a fire-time visual: every frame it is not being drawn stays off,
	# which covers switching weapons mid-burst without a special case.
	_beam.visible = false
	if not wants_fire:
		_laser_tick = 0.0
		return

	match _kind:
		Arsenal.Kind.VULCAN:
			_fire_vulcan(muzzle, direction)
		Arsenal.Kind.LASER:
			_fire_laser(delta, muzzle, direction)
		Arsenal.Kind.PLASMA:
			_fire_plasma(muzzle, direction)


func _fire_vulcan(muzzle: Vector3, direction: Vector3) -> void:
	if _cooldown > 0.0:
		return

	var spread: float = deg_to_rad(Arsenal.VULCAN_SPREAD_DEGREES)
	for pellet in Arsenal.VULCAN_PELLETS:
		var offset: float = 0.0
		if Arsenal.VULCAN_PELLETS > 1:
			offset = lerpf(-spread, spread, float(pellet) / float(Arsenal.VULCAN_PELLETS - 1))
		_spawn(
			muzzle,
			direction.rotated(Vector3.UP, offset),
			Arsenal.VULCAN_SPEED,
			Arsenal.VULCAN_DAMAGE,
			Arsenal.VULCAN_SIZE,
			Arsenal.VULCAN_COLOR
		)
	_cooldown = Arsenal.VULCAN_INTERVAL


## The beam stops at the first thing it meets, so the drawn length is the truth
## about what it can hit. Piercing would draw a line through the target and pay
## damage behind it, which is a different weapon.
func _fire_laser(delta: float, muzzle: Vector3, direction: Vector3) -> void:
	_laser_tick = maxf(_laser_tick - delta, 0.0)

	var reach: Vector3 = muzzle + direction * Arsenal.LASER_RANGE
	var hit: Dictionary = _raycast(muzzle, reach)
	var end: Vector3 = reach
	if not hit.is_empty():
		end = hit.position
		if _laser_tick <= 0.0 and hit.collider is Enemy:
			(hit.collider as Enemy).take_damage(Arsenal.LASER_DAMAGE)

	if _laser_tick <= 0.0:
		_laser_tick = Arsenal.LASER_TICK
	_show_beam(muzzle, end)


func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var mask: int = (1 << Projectile.LAYER_WORLD) | (1 << Projectile.LAYER_ENEMY)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)


func _fire_plasma(muzzle: Vector3, direction: Vector3) -> void:
	if _cooldown > 0.0:
		return

	var target: Node3D = _nearest_enemy(
		muzzle, direction, Arsenal.PLASMA_LOCK_RANGE, Arsenal.PLASMA_LOCK_CONE_DEGREES
	)
	_spawn(
		muzzle,
		direction,
		Arsenal.PLASMA_SPEED,
		Arsenal.PLASMA_DAMAGE,
		Arsenal.PLASMA_SIZE,
		Arsenal.PLASMA_COLOR,
		target,
		Arsenal.PLASMA_TURN_RATE
	)
	_cooldown = Arsenal.PLASMA_INTERVAL


## Nearest turret inside the cone, or null. A lock that ignored the cone would be
## an aimbot: the player must at least point the ship at the fight.
func _nearest_enemy(
	origin: Vector3, direction: Vector3, max_range: float, cone_degrees: float
) -> Node3D:
	var best: Node3D = null
	var best_distance: float = max_range
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy: Node3D = node as Node3D
		if enemy == null:
			continue
		var to_enemy: Vector3 = enemy.global_position - origin
		to_enemy.y = 0.0
		var distance: float = to_enemy.length()
		if distance < 0.01 or distance > best_distance:
			continue
		if cone_degrees < 180.0:
			var angle: float = rad_to_deg(direction.angle_to(to_enemy.normalized()))
			if angle > cone_degrees:
				continue
		best = enemy
		best_distance = distance
	return best


## One spawn path for every player shot, so the muzzle, the scene and the team can
## never drift between weapons.
func _spawn(
	position: Vector3,
	direction: Vector3,
	speed: float,
	damage: int,
	size: Vector3,
	color: Color,
	target: Node3D = null,
	turn_rate: float = 0.0
) -> void:
	if _bullet_scene == null:
		return

	var bullet: Projectile = _bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = position
	bullet.setup(direction, speed, Projectile.Team.PLAYER, damage, size, target, turn_rate, color)


func _build_beam() -> void:
	_beam = Node3D.new()
	_beam.visible = false
	add_child(_beam)
	_beam.add_child(_beam_box(Arsenal.LASER_GLOW, Arsenal.LASER_COLOR, 0.55))
	_beam.add_child(_beam_box(Arsenal.LASER_CORE, Color(0.92, 1.0, 1.0), 0.75))


func _beam_box(width: float, color: Color, alpha: float) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(width, width, 1.0)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, alpha)

	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = box
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The holder is scaled along its own Z, so the length is one number and the two
## nested boxes keep their own widths.
func _show_beam(from: Vector3, to: Vector3) -> void:
	var span: Vector3 = to - from
	var length: float = span.length()
	if length < 0.05:
		return
	# A slow pulse on the width: a perfectly static beam at this scale reads as a
	# debug line, and the pulse costs one sine per frame.
	var pulse: float = 1.0 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.05)
	_beam.visible = true
	_beam.global_position = from + span * 0.5
	_beam.rotation.y = atan2(span.x, span.z)
	_beam.scale = Vector3(pulse, pulse, length)
