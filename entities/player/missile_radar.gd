class_name MissileRadar
extends RefCounted
## The missile rack: a radar and a charge, not a clock.
##
## The radar holds every contact inside the forward cone. While the button is down
## one missile loads every `MISSILE_SALVO_INTERVAL`, and letting go fires the whole
## load, one missile per contact from the nearest outwards. Nothing fires with the
## button up, and a tap shorter than one interval loads nothing at all.
##
## The load needs contacts to grow: with an empty radar the rack stays empty, so a
## salvo can never be pre-charged in empty sky and dumped the moment a turret
## appears.
##
## It owns no tree. The muzzle and the world belong to `WeaponSystem`, which hands
## over a spawn callable and the cone query, and a reticle hangs from the contact it
## marks rather than from the rack.

## How far ahead of a wing hardpoint the missile is born, so it never spawns inside
## the wing it hangs from.
const MISSILE_CLEARANCE: float = 0.12

## `(position, direction, speed, damage, size, colour, target, turn, lifetime, style)
## -> Projectile`. Assigned by the facade.
var spawn: Callable = Callable()
## `(origin, direction, range, cone) -> Array[Enemy]`, nearest first. Assigned by the
## facade; the same query the plasma lock uses.
var enemies_in_cone: Callable = Callable()

var _missile_cooldown: float = 0.0
var _salvo_timer: float = 0.0
## Missiles loaded by the current hold. The radar only decides who they are spread
## over; the load itself is pure held time.
var _salvo: int = 0

## Slots carrying a reticle right now, always a subset of the radar pool, so a mark
## can follow the radar without leaving a stale ring behind.
var _marked: Array[LockSlot] = []
## The slot the scan is on: the newest lock, the only box still moving. Every
## earlier mark is settled, which is what makes the salvo read as one reticle
## walking the pool instead of eight boxes appearing together.
var _active_mark: LockSlot = null
## The salvo count already announced. The reticle animation is per assignment, so
## the sync needs to know which missiles are new this frame: a single contact fed
## eight times has to re-run the lock eight times, not once.
var _synced_salvo: int = 0

## The wing hardpoints in world space, left first, refreshed by the player every
## frame because the sweep moves them. Empty means "fall back to the nose".
var _hardpoints: Array[Vector3] = []


func tick(
	delta: float, origin: Vector3, direction: Vector3, wants_lock: bool
) -> void:
	_missile_cooldown = maxf(_missile_cooldown - delta, 0.0)
	var pool: Array[LockSlot] = radar_pool(origin, direction)

	# The cooldown is the gap after a salvo, not a pause: the rack is empty and
	# unmarked for its whole length.
	if _missile_cooldown > 0.0:
		discharge()
		return

	if not wants_lock:
		if _salvo > 0 and not pool.is_empty():
			_fire_salvo(pool, origin, direction)
		discharge()
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
			# pitch stays fixed: the count of stings is the count of locks, and a
			# ladder on top of it turns eight locks into one long rising whine.
			Sfx.play(&"lock_tone")
			GlobalEventBus.player_missile_salvo_changed.emit(
				_salvo, Arsenal.MISSILE_MAX_SALVO
			)

		if _salvo >= Arsenal.MISSILE_MAX_SALVO:
			_salvo_timer = 0.0

	# Marks come last, after the count has settled, so the bracket for a missile is
	# on screen the frame that missile loads.
	sync_marks(pool)


func set_hardpoints(points: Array[Vector3]) -> void:
	_hardpoints = points


## How many missiles the hold has loaded. The HUD reads it through the bus and the
## smoke test asserts against it.
func salvo_count() -> int:
	return _salvo


func max_salvo() -> int:
	return Arsenal.MISSILE_MAX_SALVO


## Park a given load. Test API: a load is normally earned by holding the button,
## which is a wall-clock wait the suite does not need.
func set_loaded(count: int) -> void:
	_salvo = clampi(count, 0, Arsenal.MISSILE_MAX_SALVO)


func cooldown() -> float:
	return _missile_cooldown


func set_cooldown(seconds: float) -> void:
	_missile_cooldown = maxf(seconds, 0.0)


## The slot the scan is on, or null. Read by the suite to prove the scan ends where
## the last missile goes.
func active_mark() -> LockSlot:
	return _active_mark


func marks() -> Array[LockSlot]:
	return _marked.duplicate()


## The places the radar holds, nearest first and capped at the rack size: the same
## list is what the hold loads against and what a salvo is spread over. A contact
## with lock anchors contributes one slot per anchor instead of a slot of its own,
## so a capital ship is three targets while a turret stays one.
##
## The radar detects the contact by its body, not by its anchors: a ship that is in
## range is in range for the whole rack, and its marks are how the salvo splits over
## it. Sorting is by the slot itself, so the near third is the one that takes the
## extra missile.
func radar_pool(origin: Vector3, direction: Vector3) -> Array[LockSlot]:
	var pool: Array[LockSlot] = []
	if not enemies_in_cone.is_valid():
		return pool
	var contacts: Array[Enemy] = enemies_in_cone.call(
		origin, direction, Arsenal.MISSILE_RANGE, Arsenal.MISSILE_RADAR_CONE_DEGREES
	)
	for enemy in contacts:
		var anchors: Array[Node3D] = enemy.lock_mark_anchors()
		if anchors.is_empty():
			pool.append(LockSlot.new(enemy, enemy))
			continue
		for anchor in anchors:
			if is_instance_valid(anchor):
				pool.append(LockSlot.new(enemy, anchor))
	pool.sort_custom(
		func(a: LockSlot, b: LockSlot) -> bool:
			return (
				a.host.global_position.distance_squared_to(origin)
				< b.host.global_position.distance_squared_to(origin)
			)
	)
	if pool.size() > Arsenal.MISSILE_MAX_SALVO:
		pool.resize(Arsenal.MISSILE_MAX_SALVO)
	return pool


## Rings the slots the load will chase, nearest first, and writes on each one the
## number of missiles it will take. The salvo is spread round-robin over the pool
## (`_fire_salvo` walks `pool[index % pool.size()]`), so the tally is that same walk:
## each slot takes one per pass and the earlier ones take the extra when the load
## does not divide evenly. Showing the count instead of a rank is what makes the box
## promise the split the salvo will actually produce — eight over three is 3/3/2,
## and the box reading ×2 is the slot the rack only chases twice.
##
## The count is what decides, not the pool, which is why the brackets appear one at a
## time as the hold fills the rack.
##
## Only the newest box is being acquired; the rest settle. The scan is the point: a
## multi-lock that paints every slot at once reads as a field of boxes, while one box
## walking the pool reads as the rack filling one target at a time. A slot that
## receives another missile takes the scan back, so an extra assignment is visible
## instead of a silent counter bump.
func sync_marks(pool: Array[LockSlot]) -> void:
	var tally: Dictionary = {}
	var marks: Array[LockSlot] = []
	if not pool.is_empty():
		for index in _salvo:
			var target: LockSlot = pool[index % pool.size()]
			tally[target] = int(tally.get(target, 0)) + 1
			if _find_slot(marks, target.host) == null:
				marks.append(target)

	for index in range(_marked.size() - 1, -1, -1):
		var marked: LockSlot = _marked[index]
		# A turret can die under its own ring and a capital ship takes its anchors
		# with it. A freed host already took its reticle, so the slot is dropped
		# without a call: a freed reference cannot be handed to one.
		if not is_instance_valid(marked.host) or not is_instance_valid(marked.contact):
			_marked.remove_at(index)
			continue
		if _find_slot(marks, marked.host) != null:
			continue
		_drop_mark(marked)
		_marked.remove_at(index)

	for slot in marks:
		var held: LockSlot = _find_slot(_marked, slot.host)
		if held == null:
			_make_mark(slot)
			_marked.append(slot)
		else:
			slot.reticle = held.reticle

	# The scan sits on the slot the last missile takes. When it moves, the box it
	# leaves settles and the new one is acquired.
	var active: LockSlot = null
	if not pool.is_empty() and _salvo > 0:
		active = pool[(_salvo - 1) % pool.size()]
	if not _same_slot(active, _active_mark):
		_settle_active_mark()
		_active_mark = active
		_acquire(active)

	# Every new missile re-runs the lock on its own slot, even when that slot is the
	# one the previous missile already locked. The animation belongs to the
	# assignment, not to the active target: one slot fed eight times has to announce
	# eight locks, which is the whole point of the scan.
	if not pool.is_empty() and _salvo > _synced_salvo:
		for index in range(_synced_salvo, _salvo):
			_acquire(pool[index % pool.size()])
		_synced_salvo = _salvo
		# Only the last assignment keeps moving. A long frame that loads two missiles
		# must not leave two boxes acquiring, so everything else settles now.
		for slot in marks:
			if _same_slot(slot, _active_mark):
				continue
			if is_instance_valid(slot.reticle) and not slot.reticle.is_held():
				slot.reticle.hold()

	# The tally is recomputed every sync because the pool order can change under it:
	# a nearer slot entering the radar reshuffles who takes which missile, and the
	# picture has to agree with what `_fire_salvo` will do.
	for slot in marks:
		if is_instance_valid(slot.reticle):
			slot.reticle.set_missiles(int(tally.get(slot, 0)))


## Empties the rack and its marks. Called on release, on cooldown and on an empty
## radar, so there is never a loaded salvo waiting for a second press.
##
## This runs every frame of a cooldown, so it cannot assume its marks are alive: a
## turret killed under its ring is dropped without a call and the rack still empties.
func discharge() -> void:
	for index in range(_marked.size() - 1, -1, -1):
		_drop_mark(_marked[index])
		_marked.remove_at(index)
	_active_mark = null
	_synced_salvo = 0
	_salvo_timer = 0.0
	if _salvo == 0:
		return
	_salvo = 0
	GlobalEventBus.player_missile_salvo_changed.emit(0, Arsenal.MISSILE_MAX_SALVO)


## Puts a mark on the slot's host. The contact owns the shape: a turret leaves the
## resting square, a capital ship reports its own small box. An anchor already sits
## on the hull, so its box takes no lift of its own and keeps the contact's draw
## rule.
func _make_mark(slot: LockSlot) -> void:
	slot.reticle = slot.host.get_node_or_null(^"LockReticle") as LockReticle
	if slot.reticle != null:
		return
	var reticle: LockReticle = LockReticle.new()
	reticle.name = "LockReticle"
	var mark: Vector3 = slot.contact.lock_mark()
	if mark != Vector3.ZERO:
		# The anchor already stands on the hull; only the body needs the lift.
		var lift: float = 0.0 if slot.host != slot.contact else mark.y
		reticle.set_mark_size(
			Vector2(mark.x, mark.z), lift, slot.contact.lock_mark_on_hull()
		)
	slot.host.add_child(reticle)
	slot.reticle = reticle


## Runs the lock-in on a slot's box, if the mark exists and the contact is alive.
func _acquire(slot: LockSlot) -> void:
	if slot == null or not is_instance_valid(slot.contact):
		return
	if is_instance_valid(slot.reticle):
		slot.reticle.acquire()


## Hands the scan to a new slot: the box that had it settles where it stands.
func _settle_active_mark() -> void:
	if _active_mark != null and is_instance_valid(_active_mark.reticle):
		_active_mark.reticle.hold()
	_active_mark = null


func _drop_mark(slot: LockSlot) -> void:
	if _same_slot(slot, _active_mark):
		_active_mark = null
	if is_instance_valid(slot.reticle):
		slot.reticle.queue_free()


## The slot hanging from this host, or null. Slots are rebuilt every frame, so the
## host is what survives between them: the contact for a turret, its own anchor for
## a capital ship.
func _find_slot(slots: Array[LockSlot], host: Node3D) -> LockSlot:
	for slot in slots:
		if is_instance_valid(slot.host) and slot.host == host:
			return slot
	return null


func _same_slot(a: LockSlot, b: LockSlot) -> bool:
	if a == null or b == null:
		return false
	return (
		is_instance_valid(a.host) and is_instance_valid(b.host) and a.host == b.host
	)


## The whole load leaves at once, one missile per mark: the pool is walked from the
## nearest contact outwards and wraps when the load is longer than the radar, so a
## lone contact still takes every missile. This is the same order `sync_marks`
## rings, which is what makes the brackets the load's promise.
func _fire_salvo(
	pool: Array[LockSlot], origin: Vector3, direction: Vector3
) -> void:
	var count: int = _salvo
	discharge()
	if count == 0 or pool.is_empty():
		return

	_missile_cooldown = Arsenal.MISSILE_SALVO_COOLDOWN
	for index in count:
		var target: LockSlot = pool[index % pool.size()]
		if is_instance_valid(target.contact) and is_instance_valid(target.host):
			_launch_missile(target, origin, direction, index)


## Alternating wings and a widening angle, so the guidance curve is visible from
## the first frame instead of looking like a straight shot. Same salvo, different
## line: the load decides how many, the radar decides who.
##
## The shot steers to the slot's host, which for a capital ship is the section the
## mark sits on: the missile crosses the part it was aimed at, so the split the
## marks promise is the split the damage produces.
##
## The fan opens in pairs outwards (11, -11, 22, -22...), so every missile of the
## load has a heading of its own. The angle also picks the wing: the missile leaves
## from the pylon it is angling towards, which is what keeps the picture and the
## trajectory agreeing.
func _launch_missile(
	target: LockSlot, origin: Vector3, direction: Vector3, index: int
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
	var shot: Projectile = spawn.call(
		launch,
		heading,
		Arsenal.MISSILE_SPEED,
		Arsenal.MISSILE_DAMAGE,
		Arsenal.MISSILE_SIZE,
		Arsenal.MISSILE_COLOR,
		target.host,
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
