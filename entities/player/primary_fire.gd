class_name PrimaryFire
extends Node3D
## The three primaries: vulcan, laser, plasma.
##
## One node so the laser and its drawn line share a home, and so the ship's cadence
## state stops living next to the missile rack. Everything fires along the aim
## vector on the play plane, and nothing here touches the ship's velocity: firing
## must never cost speed.
##
## The muzzle and the spawn path belong to `WeaponSystem`, handed over as callables,
## so a shot cannot come out of a different place depending on which weapon fired it.

## The run's pilot bonuses. The arsenal keeps its identity and the stats only scale
## the cadence and the handling, so a levelled pilot fires the same three weapons.
var stats: PilotStats = PilotStats.new()
## Fighter mode is a profile, not a different arsenal: the same three archetypes
## keep their identity and only lose the freedom to point anywhere but forward.
var fighter: bool = false
## `(position, direction, speed, damage, size, colour, target, turn, lifetime, style)
## -> Projectile`. Assigned by the facade.
var spawn: Callable = Callable()
## `(origin, direction, range, cone) -> Array[Enemy]`, nearest first. The plasma
## lock takes the head of that list.
var enemies_in_cone: Callable = Callable()

var _kind: Arsenal.Kind = Arsenal.Kind.VULCAN
var _cooldown: float = 0.0
var _laser_tick: float = 0.0
## True while the beam is already sounding, so a held trigger ignites once.
var _laser_sounding: bool = false
var _beam: BeamVisual = null


func _ready() -> void:
	_beam = BeamVisual.new()
	_beam.name = "Beam"
	add_child(_beam)


func kind() -> Arsenal.Kind:
	return _kind


func cooldown() -> float:
	return _cooldown


## Clears the cadence. Test API: a shot fired by hand must not inherit the wait of
## the one before it.
func set_cooldown(seconds: float) -> void:
	_cooldown = maxf(seconds, 0.0)


## Switching is instant and always legal: the weapons are a player choice, not a
## pickup economy. A switch also clears the cadence so the new weapon can fire on
## the same frame instead of inheriting the old one's wait. Returns false when the
## kind did not change, which is what keeps the facade from announcing a no-op.
func select(kind: Arsenal.Kind) -> bool:
	if kind == _kind:
		return false
	_kind = kind
	_cooldown = 0.0
	_laser_tick = 0.0
	_laser_sounding = false
	return true


func tick(delta: float, muzzle: Vector3, direction: Vector3, wants_fire: bool) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	# The beam is a fire-time visual: every frame it is not being drawn stays off,
	# which covers switching weapons mid-burst without a special case.
	_beam.hide_beam()
	if not wants_fire:
		_laser_tick = 0.0
		_laser_sounding = false
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

	var spread: float = deg_to_rad(
		(
			Arsenal.FIGHTER_VULCAN_SPREAD_DEGREES
			if fighter
			else Arsenal.VULCAN_SPREAD_DEGREES
		) * stats.vulcan_spread_multiplier()
	)
	for pellet in Arsenal.VULCAN_PELLETS:
		var offset: float = 0.0
		if Arsenal.VULCAN_PELLETS > 1:
			offset = lerpf(
				-spread, spread, float(pellet) / float(Arsenal.VULCAN_PELLETS - 1)
			)
		spawn.call(
			muzzle,
			direction.rotated(Vector3.UP, offset),
			Arsenal.VULCAN_SPEED * _speed_multiplier(),
			Arsenal.VULCAN_DAMAGE,
			Arsenal.VULCAN_SIZE,
			Arsenal.VULCAN_COLOR,
			null,
			0.0,
			Projectile.LIFETIME * _range_multiplier(),
			Projectile.Style.DART
		)
	_cooldown = Arsenal.VULCAN_INTERVAL * stats.primary_interval_multiplier()
	# One burst per shot, not per pellet: five pellets of noise would read as one
	# smear instead of a gun.
	Sfx.play(&"vulcan")


## The beam stops at the first thing it meets, so the drawn length is the truth
## about what it can hit. Piercing would draw a line through the target and pay
## damage behind it, which is a different weapon.
func _fire_laser(delta: float, muzzle: Vector3, direction: Vector3) -> void:
	_laser_tick = maxf(_laser_tick - delta, 0.0)

	var reach: Vector3 = muzzle + direction * (
		Arsenal.LASER_RANGE * _range_multiplier() * stats.laser_range_multiplier()
	)
	var hit: Dictionary = _raycast(muzzle, reach)
	var end: Vector3 = reach
	if not hit.is_empty():
		end = hit.position
		var collider: Object = hit.collider
		if collider is Projectile:
			# A missile has no hull to chew through: the beam cuts it down. Only the
			# enemy missile layer is in the ray's mask, so this cannot reach the
			# player's own shots.
			(collider as Projectile).queue_free()
		elif _laser_tick <= 0.0 and collider is Enemy:
			(collider as Enemy).take_damage(Arsenal.LASER_DAMAGE)

	if _laser_tick <= 0.0:
		_laser_tick = Arsenal.LASER_TICK * stats.primary_interval_multiplier()
	# The beam is continuous, so it gets one ignition per trigger pull instead of a
	# zap per frame: `_laser_sounding` is cleared the moment the trigger comes up.
	if not _laser_sounding:
		_laser_sounding = true
		Sfx.play(&"laser")
	_beam.show_beam(muzzle, end)


func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var mask: int = (
		(1 << Projectile.LAYER_WORLD)
		| (1 << Projectile.LAYER_ENEMY)
		| (1 << Projectile.LAYER_ENEMY_MISSILE)
	)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, mask
	)
	# A missile is an area, not a body, so the beam has to see areas to intercept
	# one. Missiles are the only area on this mask, so nothing else changes.
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _fire_plasma(muzzle: Vector3, direction: Vector3) -> void:
	if _cooldown > 0.0:
		return

	# No lock in Fighter: the bolt is one more thing bolted to the airframe.
	var target: Node3D = null
	if not fighter:
		target = _nearest_enemy(
			muzzle,
			direction,
			Arsenal.PLASMA_LOCK_RANGE,
			Arsenal.PLASMA_LOCK_CONE_DEGREES * stats.plasma_cone_multiplier()
		)
	spawn.call(
		muzzle,
		direction,
		Arsenal.PLASMA_SPEED * _speed_multiplier(),
		Arsenal.PLASMA_DAMAGE,
		Arsenal.PLASMA_SIZE,
		Arsenal.PLASMA_COLOR,
		target,
		Arsenal.PLASMA_TURN_RATE,
		Projectile.LIFETIME * _range_multiplier(),
		Projectile.Style.DART
	)
	_cooldown = Arsenal.PLASMA_INTERVAL * stats.primary_interval_multiplier()
	Sfx.play(&"plasma")


## Fighter range is +40%; the same multiplier is expressed as projectile lifetime
## for bullets and as beam length for the hit-scan laser.
func _range_multiplier() -> float:
	return Arsenal.FIGHTER_RANGE_MULTIPLIER if fighter else 1.0


func _speed_multiplier() -> float:
	return Arsenal.FIGHTER_SPEED_MULTIPLIER if fighter else 1.0


## Nearest contact inside the cone, or null. A lock that ignored the cone would be
## an aimbot: the player must at least point the ship at the fight.
func _nearest_enemy(
	origin: Vector3, direction: Vector3, max_range: float, cone_degrees: float
) -> Node3D:
	if not enemies_in_cone.is_valid():
		return null
	var found: Array[Enemy] = enemies_in_cone.call(
		origin, direction, max_range, cone_degrees
	)
	return found[0] if not found.is_empty() else null
