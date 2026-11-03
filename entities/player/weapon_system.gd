class_name WeaponSystem
extends Node3D
## The player's primary arsenal. The player node owns flight, aim and HP; this node
## owns what comes out of the nose, so `player.gd` keeps reading as "how the ship
## flies" instead of "how the ship flies plus three weapons".
##
## Everything fires along the aim vector on the play plane, and nothing here
## touches the ship's velocity: firing must never cost speed.

## How far ahead of a wing hardpoint the missile is born, so it never spawns inside
## the wing it hangs from.
const MISSILE_CLEARANCE: float = 0.12

var _bullet_scene: PackedScene
var _kind: Arsenal.Kind = Arsenal.Kind.VULCAN
var _cooldown: float = 0.0
var _laser_tick: float = 0.0
var _beam: Node3D

var _missile_cooldown: float = 0.0
var _salvo_timer: float = 0.0
## Missiles loaded by the current hold. The radar only decides who they are spread
## over; the load itself is pure held time.
var _salvo: int = 0
## Enemies carrying a reticle right now, always a subset of the radar pool, so a
## mark can follow the radar without leaving a stale ring behind.
var _marked: Array[Enemy] = []
## The contact the scan is on: the newest lock, the only box still moving. Every
## earlier mark is settled, which is what makes the salvo read as one reticle
## walking the pool instead of eight boxes appearing together.
var _active_mark: Enemy = null
## The salvo count already announced. The reticle animation is per assignment, so
## the sync needs to know which missiles are new this frame: a single contact fed
## eight times has to re-run the lock eight times, not once.
var _synced_salvo: int = 0

## Fighter mode is a profile, not a different arsenal: the same three archetypes
## keep their identity and only lose the freedom to point anywhere but forward.
var _fighter: bool = false

## The wing hardpoints in world space, left first, refreshed by the player every
## frame because the sweep moves them. Empty means "fall back to the nose".
var _hardpoints: Array[Vector3] = []

var _bombs: int = Arsenal.BOMB_START_CHARGES
var _kills: int = 0
## Seconds until the next flare. The cooldown is the whole cost of the decoy.
var _decoy_cooldown: float = 0.0
## True while the beam is already sounding, so a held trigger ignites once.
var _laser_sounding: bool = false


func setup(bullet_scene: PackedScene) -> void:
	_bullet_scene = bullet_scene


func _ready() -> void:
	_build_beam()
	GlobalEventBus.enemy_killed.connect(_on_enemy_killed)
	# Deferred so a HUD that connects in its own `_ready` still sees the start
	# state: the player must never sit with an empty weapon label.
	GlobalEventBus.player_weapon_changed.emit.call_deferred(Arsenal.NAMES[_kind])
	GlobalEventBus.player_bombs_changed.emit.call_deferred(_bombs, Arsenal.BOMB_MAX_CHARGES)
	GlobalEventBus.player_decoy_changed.emit.call_deferred(true)


func kind() -> Arsenal.Kind:
	return _kind


func bomb_charges() -> int:
	return _bombs


## Switching is instant and always legal: the weapons are a player choice, not a
## pickup economy. A switch also clears the cadence so the new weapon can fire on
## the same frame instead of inheriting the old one's wait.
func select(kind: Arsenal.Kind) -> void:
	if kind == _kind:
		return
	_kind = kind
	_cooldown = 0.0
	_laser_tick = 0.0
	_laser_sounding = false
	GlobalEventBus.player_weapon_changed.emit(Arsenal.NAMES[_kind])


func cycle(step: int) -> void:
	var kinds: Array = Arsenal.Kind.values()
	var index: int = (kinds.find(_kind) + step + kinds.size()) % kinds.size()
	select(kinds[index])


func tick(
	delta: float,
	origin: Vector3,
	muzzle: Vector3,
	direction: Vector3,
	wants_fire: bool,
	fighter: bool = false,
	wants_missile: bool = false,
	hardpoints: Array[Vector3] = []
) -> void:
	_fighter = fighter
	_hardpoints = hardpoints
	_cooldown = maxf(_cooldown - delta, 0.0)
	# The decoy reloads on its own clock whether or not anything else is firing:
	# it is a countermeasure, not a weapon the player has to be holding.
	if _decoy_cooldown > 0.0:
		_decoy_cooldown = maxf(_decoy_cooldown - delta, 0.0)
		if _decoy_cooldown <= 0.0:
			GlobalEventBus.player_decoy_changed.emit(true)
	# The beam is a fire-time visual: every frame it is not being drawn stays off,
	# which covers switching weapons mid-burst without a special case.
	_beam.visible = false
	if not wants_fire:
		_laser_tick = 0.0
		_laser_sounding = false
		_tick_missiles(delta, origin, direction, wants_missile)
		return

	match _kind:
		Arsenal.Kind.VULCAN:
			_fire_vulcan(muzzle, direction)
		Arsenal.Kind.LASER:
			_fire_laser(delta, muzzle, direction)
		Arsenal.Kind.PLASMA:
			_fire_plasma(muzzle, direction)

	_tick_missiles(delta, origin, direction, wants_missile)


func _fire_vulcan(muzzle: Vector3, direction: Vector3) -> void:
	if _cooldown > 0.0:
		return

	var spread: float = deg_to_rad(
		Arsenal.FIGHTER_VULCAN_SPREAD_DEGREES if _fighter else Arsenal.VULCAN_SPREAD_DEGREES
	)
	for pellet in Arsenal.VULCAN_PELLETS:
		var offset: float = 0.0
		if Arsenal.VULCAN_PELLETS > 1:
			offset = lerpf(-spread, spread, float(pellet) / float(Arsenal.VULCAN_PELLETS - 1))
		_spawn(
			muzzle,
			direction.rotated(Vector3.UP, offset),
			Arsenal.VULCAN_SPEED * _speed_multiplier(),
			Arsenal.VULCAN_DAMAGE,
			Arsenal.VULCAN_SIZE,
			Arsenal.VULCAN_COLOR,
			null,
			0.0,
			Projectile.LIFETIME * _range_multiplier()
		)
	_cooldown = Arsenal.VULCAN_INTERVAL
	# One burst per shot, not per pellet: five pellets of noise would read as one
	# smear instead of a gun.
	Sfx.play(&"vulcan")


## The beam stops at the first thing it meets, so the drawn length is the truth
## about what it can hit. Piercing would draw a line through the target and pay
## damage behind it, which is a different weapon.
func _fire_laser(delta: float, muzzle: Vector3, direction: Vector3) -> void:
	_laser_tick = maxf(_laser_tick - delta, 0.0)

	var reach: Vector3 = muzzle + direction * (
		Arsenal.LASER_RANGE * _range_multiplier()
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
		_laser_tick = Arsenal.LASER_TICK
	# The beam is continuous, so it gets one ignition per trigger pull instead of a
	# zap per frame: `_laser_sounding` is cleared the moment the trigger comes up.
	if not _laser_sounding:
		_laser_sounding = true
		Sfx.play(&"laser")
	_show_beam(muzzle, end)


func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var mask: int = (
		(1 << Projectile.LAYER_WORLD)
		| (1 << Projectile.LAYER_ENEMY)
		| (1 << Projectile.LAYER_ENEMY_MISSILE)
	)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask)
	# A missile is an area, not a body, so the beam has to see areas to intercept
	# one. Missiles are the only area on this mask, so nothing else changes.
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _fire_plasma(muzzle: Vector3, direction: Vector3) -> void:
	if _cooldown > 0.0:
		return

	# No lock in Fighter: the bolt is one more thing bolted to the airframe.
	var target: Node3D = null
	if not _fighter:
		target = _nearest_enemy(
			muzzle, direction, Arsenal.PLASMA_LOCK_RANGE, Arsenal.PLASMA_LOCK_CONE_DEGREES
		)
	_spawn(
		muzzle,
		direction,
		Arsenal.PLASMA_SPEED * _speed_multiplier(),
		Arsenal.PLASMA_DAMAGE,
		Arsenal.PLASMA_SIZE,
		Arsenal.PLASMA_COLOR,
		target,
		Arsenal.PLASMA_TURN_RATE,
		Projectile.LIFETIME * _range_multiplier()
	)
	_cooldown = Arsenal.PLASMA_INTERVAL
	Sfx.play(&"plasma")


## Fighter range is +40%; the same multiplier is expressed as projectile lifetime
## for bullets and as beam length for the hit-scan laser.
func _range_multiplier() -> float:
	return Arsenal.FIGHTER_RANGE_MULTIPLIER if _fighter else 1.0


func _speed_multiplier() -> float:
	return Arsenal.FIGHTER_SPEED_MULTIPLIER if _fighter else 1.0


## Nearest turret inside the cone, or null. A lock that ignored the cone would be
## an aimbot: the player must at least point the ship at the fight.
func _nearest_enemy(
	origin: Vector3, direction: Vector3, max_range: float, cone_degrees: float
) -> Node3D:
	var found: Array[Enemy] = _enemies_in_cone(origin, direction, max_range, cone_degrees)
	return found[0] if not found.is_empty() else null


## Every enemy inside the cone, nearest first. The plasma lock wants the head of
## the list; the missile radar wants the whole list, because a salvo is spread over
## it.
func _enemies_in_cone(
	origin: Vector3, direction: Vector3, max_range: float, cone_degrees: float
) -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy: Enemy = node as Enemy
		if enemy == null:
			continue
		var to_enemy: Vector3 = enemy.global_position - origin
		to_enemy.y = 0.0
		var distance: float = to_enemy.length()
		if distance < 0.01 or distance > max_range:
			continue
		if cone_degrees < 180.0:
			var angle: float = rad_to_deg(direction.angle_to(to_enemy.normalized()))
			if angle > cone_degrees:
				continue
		found.append(enemy)

	found.sort_custom(
		func(a: Enemy, b: Enemy) -> bool:
			return (
				a.global_position.distance_squared_to(origin)
				< b.global_position.distance_squared_to(origin)
			)
	)
	return found


## One spawn path for every player shot, so the muzzle, the scene and the team can
## never drift between weapons. Returns the shot so a caller that needs to configure
## it further (the missile's guidance delay) does not have to search the scene.
func _spawn(
	position: Vector3,
	direction: Vector3,
	speed: float,
	damage: int,
	size: Vector3,
	color: Color,
	target: Node3D = null,
	turn_rate: float = 0.0,
	lifetime: float = Projectile.LIFETIME,
	style: Projectile.Style = Projectile.Style.DART
) -> Projectile:
	if _bullet_scene == null:
		return null

	var bullet: Projectile = _bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = position
	bullet.setup(
		direction, speed, Projectile.Team.PLAYER, damage, size, target, turn_rate, color,
		lifetime, style
	)
	return bullet


## How many missiles the hold has loaded. The HUD reads it through the bus and the
## smoke test asserts against it.
func salvo_count() -> int:
	return _salvo


func max_salvo() -> int:
	return Arsenal.MISSILE_MAX_SALVO


## The rack is a radar and a charge, not a clock. The radar holds every contact
## inside the forward cone; while the button is down one missile loads every
## MISSILE_SALVO_INTERVAL, and letting go fires the whole load, one missile per
## contact from the nearest outwards. Nothing fires with the button up, and a tap
## shorter than one interval loads nothing at all.
##
## The load needs contacts to grow: with an empty radar the rack stays empty, so a
## salvo can never be pre-charged in empty sky and dumped the moment a turret
## appears.
func _tick_missiles(
	delta: float, origin: Vector3, direction: Vector3, wants_lock: bool
) -> void:
	_missile_cooldown = maxf(_missile_cooldown - delta, 0.0)
	var pool: Array[Enemy] = _radar_pool(origin, direction)

	# The cooldown is the gap after a salvo, not a pause: the rack is empty and
	# unmarked for its whole length.
	if _missile_cooldown > 0.0:
		_discharge()
		return

	if not wants_lock:
		if _salvo > 0 and not pool.is_empty():
			_fire_salvo(pool, origin, direction)
		_discharge()
		return

	if not pool.is_empty() and _salvo < Arsenal.MISSILE_MAX_SALVO:
		_salvo_timer += delta
		while (
			_salvo_timer >= Arsenal.MISSILE_SALVO_INTERVAL
			and _salvo < Arsenal.MISSILE_MAX_SALVO
		):
			_salvo_timer -= Arsenal.MISSILE_SALVO_INTERVAL
			_salvo += 1
			# One sting per assignment, not per frame: a long frame that loads two
			# missiles has to sound twice, because two assignments happened. The
			# pitch climbs with the rack, since eight identical beeps do not say
			# "eight locks" the way a rising ladder does.
			Sfx.play(&"lock_tone", 0.0, 1.0 + 0.07 * float(_salvo - 1))
			GlobalEventBus.player_missile_salvo_changed.emit(
				_salvo, Arsenal.MISSILE_MAX_SALVO
			)

		if _salvo >= Arsenal.MISSILE_MAX_SALVO:
			_salvo_timer = 0.0

	# Marks come last, after the count has settled, so the bracket for a missile is
	# on screen the frame that missile loads.
	_sync_marks(pool)


## The contacts the radar holds, nearest first and capped at the rack size: the same
## list is what the hold loads against and what a salvo is spread over.
func _radar_pool(origin: Vector3, direction: Vector3) -> Array[Enemy]:
	var pool: Array[Enemy] = _enemies_in_cone(
		origin, direction, Arsenal.MISSILE_RANGE, Arsenal.MISSILE_RADAR_CONE_DEGREES
	)
	if pool.size() > Arsenal.MISSILE_MAX_SALVO:
		pool.resize(Arsenal.MISSILE_MAX_SALVO)
	return pool


## Rings the contacts the load will chase, nearest first, and writes on each one the
## number of missiles it will take. The salvo is spread round-robin over the pool
## (`_fire_salvo` walks `pool[index % pool.size()]`), so the tally is that same walk:
## each contact takes one per pass and the earlier ones take the extra when the load
## does not divide evenly. Showing the count instead of a rank is what makes the box
## promise the split the salvo will actually produce — eight over three is 3/3/2,
## and the box reading ×2 is the contact the rack only chases twice.
##
## The count is what decides, not the pool, which is why the brackets appear one at a
## time as the hold fills the rack.
##
## Only the newest box is being acquired; the rest settle. The scan is the point: a
## multi-lock that paints every contact at once reads as a field of boxes, while one
## box walking the pool reads as the rack filling one contact at a time. A contact
## that receives another missile takes the scan back, so an extra assignment is
## visible instead of a silent counter bump.
func _sync_marks(pool: Array[Enemy]) -> void:
	var tally: Dictionary = {}
	var marks: Array[Enemy] = []
	if not pool.is_empty():
		for index in _salvo:
			var target: Enemy = pool[index % pool.size()]
			tally[target] = int(tally.get(target, 0)) + 1
			if not marks.has(target):
				marks.append(target)

	for index in range(_marked.size() - 1, -1, -1):
		var marked: Enemy = _marked[index]
		# A turret can die under its own ring. A freed mark is dropped from the
		# list without a call: it took its reticle with it, and handing the freed
		# reference to _drop_reticle fails the parameter type check.
		if not is_instance_valid(marked):
			_marked.remove_at(index)
			continue
		if marks.has(marked):
			continue
		_drop_reticle(marked)
		_marked.remove_at(index)

	for enemy in marks:
		if _marked.has(enemy):
			continue
		if enemy.get_node_or_null(^"LockReticle") == null:
			var reticle: LockReticle = LockReticle.new()
			reticle.name = "LockReticle"
			enemy.add_child(reticle)
		_marked.append(enemy)

	# The scan sits on the contact the last missile takes. When it moves, the box it
	# leaves settles and the new one is acquired.
	var active: Enemy = null
	if not pool.is_empty() and _salvo > 0:
		active = pool[(_salvo - 1) % pool.size()]
	if active != _active_mark:
		_settle_active_mark()
		_active_mark = active
		_acquire(active)

	# Every new missile re-runs the lock on its own target, even when that target is
	# the contact the previous missile already locked. The animation belongs to the
	# assignment, not to the active target: one contact fed eight times has to
	# announce eight locks, which is the whole point of the scan.
	if not pool.is_empty() and _salvo > _synced_salvo:
		for index in range(_synced_salvo, _salvo):
			_acquire(pool[index % pool.size()])
		_synced_salvo = _salvo
		# Only the last assignment keeps moving. A long frame that loads two missiles
		# must not leave two boxes acquiring, so everything else settles now.
		for enemy in marks:
			if enemy == _active_mark or not is_instance_valid(enemy):
				continue
			var box: LockReticle = enemy.get_node_or_null(^"LockReticle") as LockReticle
			if box != null and not box.is_held():
				box.hold()

	# The tally is recomputed every sync because the pool order can change under it:
	# a nearer contact entering the radar reshuffles who takes which missile, and the
	# picture has to agree with what `_fire_salvo` will do.
	for enemy in marks:
		if not is_instance_valid(enemy):
			continue
		var box: LockReticle = enemy.get_node_or_null(^"LockReticle") as LockReticle
		if box != null:
			box.set_missiles(int(tally.get(enemy, 0)))


## Runs the lock-in on a contact's box, if the mark exists and the contact is alive.
func _acquire(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	var box: LockReticle = enemy.get_node_or_null(^"LockReticle") as LockReticle
	if box != null:
		box.acquire()


## Hands the scan to a new contact: the box that had it settles where it stands.
func _settle_active_mark() -> void:
	if _active_mark != null and is_instance_valid(_active_mark):
		var reticle: LockReticle = (
			_active_mark.get_node_or_null(^"LockReticle") as LockReticle
		)
		if reticle != null:
			reticle.hold()
	_active_mark = null


func _drop_reticle(enemy: Enemy) -> void:
	if enemy == _active_mark:
		_active_mark = null
	if not is_instance_valid(enemy):
		return
	var reticle: Node = enemy.get_node_or_null(^"LockReticle")
	if reticle != null:
		reticle.queue_free()


## The whole load leaves at once, one missile per mark: the pool is walked from the
## nearest contact outwards and wraps when the load is longer than the radar, so a
## lone contact still takes every missile. This is the same order `_sync_marks`
## rings, which is what makes the brackets the load's promise.
func _fire_salvo(pool: Array[Enemy], origin: Vector3, direction: Vector3) -> void:
	var count: int = _salvo
	_discharge()
	if count == 0 or pool.is_empty():
		return

	_missile_cooldown = Arsenal.MISSILE_SALVO_COOLDOWN
	for index in count:
		var target: Enemy = pool[index % pool.size()]
		if is_instance_valid(target):
			_launch_missile(target, origin, direction, index)


## Alternating wings and a widening angle, so the guidance curve is visible from
## the first frame instead of looking like a straight shot. Same salvo, different
## line: the load decides how many, the radar decides who.
##
## The fan opens in pairs outwards (11, -11, 22, -22...), so every missile of the
## load has a heading of its own. The angle also picks the wing: the missile leaves
## from the pylon it is angling towards, which is what keeps the picture and the
## trajectory agreeing.
func _launch_missile(
	target: Enemy, origin: Vector3, direction: Vector3, index: int
) -> void:
	var side: float = 1.0 if index % 2 == 0 else -1.0
	var pair: int = index / 2 + 1
	var angle: float = minf(
		float(pair) * Arsenal.MISSILE_LAUNCH_ANGLE_STEP_DEGREES,
		Arsenal.MISSILE_LAUNCH_ANGLE_MAX_DEGREES
	)

	var right: Vector3 = Vector3(-direction.z, 0.0, direction.x)
	var launch: Vector3 = (
		origin
		+ direction * (Arsenal.MISSILE_LAUNCH_AHEAD + 0.06 * float(index))
		+ right * Arsenal.MISSILE_LAUNCH_SIDE * side
	)
	if _hardpoints.size() >= 2:
		var pick: int = 0
		if (_hardpoints[0] - origin).dot(right) * side < 0.0:
			pick = 1
		# A hand's width ahead of the pylon, so the shot clears the wing it hangs from.
		launch = _hardpoints[pick] + direction * MISSILE_CLEARANCE
	var heading: Vector3 = direction.rotated(
		Vector3.UP, deg_to_rad(angle) * side
	)
	var shot: Projectile = _spawn(
		launch,
		heading,
		Arsenal.MISSILE_SPEED,
		Arsenal.MISSILE_DAMAGE,
		Arsenal.MISSILE_SIZE,
		Arsenal.MISSILE_COLOR,
		target,
		Arsenal.MISSILE_TURN_RATE,
		Projectile.LIFETIME,
		Projectile.Style.MISSILE
	)
	# The fan only exists if the missiles hold their line for a beat: guidance that
	# engages on the launch frame folds the spread into one column before it is
	# readable.
	if shot != null:
		shot.set_guidance_delay(Arsenal.MISSILE_GUIDANCE_DELAY)
		# Each shot weaves on its own phase, so a salvo draws a braid of smoke
		# instead of six trails moving in lockstep.
		shot.set_weave(
			Arsenal.MISSILE_WEAVE_AMPLITUDE,
			Arsenal.MISSILE_WEAVE_RATE,
			float(index) * 2.1,
			Arsenal.MISSILE_WEAVE_HIT_RANGE,
			Arsenal.MISSILE_WEAVE_FADE
		)
		# One launch per shot, rising a little as the rack empties: a salvo is a
		# burst of whooshes, and the pitch climb is what makes it read as a sequence
		# instead of one long noise.
		Sfx.play(&"missile_launch", 0.0, 1.0 + float(index) * 0.04)


## Empties the rack and its marks. Called on release, on cooldown and on an empty
## radar, so there is never a loaded salvo waiting for a second press.
##
## This runs every frame of a cooldown, so it cannot assume its marks are alive: a
## turret killed under its ring is dropped without a call and the rack still empties.
func _discharge() -> void:
	for index in range(_marked.size() - 1, -1, -1):
		var enemy: Enemy = _marked[index]
		if is_instance_valid(enemy):
			_drop_reticle(enemy)
		_marked.remove_at(index)
	_active_mark = null
	_synced_salvo = 0
	_salvo_timer = 0.0
	if _salvo == 0:
		return
	_salvo = 0
	GlobalEventBus.player_missile_salvo_changed.emit(0, Arsenal.MISSILE_MAX_SALVO)


## The bomb is the only weapon with a resource. It damages and cancels in the same
## frame, so what the player sees (the ring) and what happened (the clear) are one
## event and the ring can be pure presentation.
func fire_bomb(origin: Vector3) -> bool:
	if _bombs <= 0:
		return false

	_bombs -= 1
	GlobalEventBus.player_bombs_changed.emit(_bombs, Arsenal.BOMB_MAX_CHARGES)

	_clear_enemy_fire(origin)
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy: Enemy = node as Enemy
		if enemy == null:
			continue
		if _flat_distance(enemy.global_position, origin) <= Arsenal.BOMB_RADIUS:
			enemy.take_damage(Arsenal.BOMB_DAMAGE)

	_spawn_wave(origin)
	GlobalEventBus.camera_shake_requested.emit(1.4)
	Sfx.play_at(&"bomb", origin)
	return true


## Drops a flare where the ship is. It stays there while the ship flies on, which
## is the whole manoeuvre: the countermeasure only pays if the ship leaves the spot
## the missile was already heading for.
func drop_decoy(origin: Vector3) -> bool:
	if _decoy_cooldown > 0.0:
		return false

	var scene: Node = get_tree().current_scene
	if scene == null:
		return false

	_decoy_cooldown = Arsenal.DECOY_COOLDOWN
	var decoy: Decoy = Decoy.new()
	scene.add_child(decoy)
	decoy.global_position = origin
	GlobalEventBus.player_decoy_changed.emit(false)
	Sfx.play_at(&"decoy", origin)
	return true


## Radius-bound on purpose: "screen clear" is the intent, but a bullet far off the
## camera is not a threat the player is asking to erase.
func _clear_enemy_fire(origin: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for child in scene.get_children():
		var bullet: Projectile = child as Projectile
		if bullet == null:
			continue
		if int(bullet.get("_team")) != Projectile.Team.ENEMY:
			continue
		if _flat_distance(bullet.global_position, origin) <= Arsenal.BOMB_RADIUS:
			bullet.queue_free()


func _spawn_wave(origin: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var wave: BombWave = BombWave.new()
	scene.add_child(wave)
	wave.global_position = origin


## Charges come back on kills rather than on a timer: the resource rewards staying
## in the fight, and a full rack stops banking progress it cannot spend.
func _on_enemy_killed(_value: int) -> void:
	if _bombs >= Arsenal.BOMB_MAX_CHARGES:
		_kills = 0
		return

	_kills += 1
	if _kills < Arsenal.BOMB_KILLS_PER_CHARGE:
		return

	_kills = 0
	_bombs += 1
	GlobalEventBus.player_bombs_changed.emit(_bombs, Arsenal.BOMB_MAX_CHARGES)


func _flat_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()


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
