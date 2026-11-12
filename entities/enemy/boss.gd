class_name Boss
extends Enemy
## The mothership: the planet's final encounter. A capital ship built from the
## `models/boss-1` GLB that flies slowly over the surface and is fought as one
## set piece.
##
## The hull is three target points, one per section: bow, middle and stern. Each point
## owns its own pool, and the section's fires and gun read that pool, so shooting the
## bow wears down the bow and the bow is the section that stops answering. A 96-unit
## ship is already a level; three points give the player places to commit instead of
## one hitbox they can only graze, without splitting a third into halves nobody can
## aim at while the ship is moving.
##
## The three guns are three different problems (`entities/enemy/boss_weapon.gd`): a
## vulcan burst from the bow, a guided pair from the middle and a laser from the
## stern. They run on separate clocks, so the fight is a choice of which threat to
## silence rather than one broadside repeated from a longer bar.
##
## The points are the hull's collision: three solid boxes on the world and enemy
## layers. The body itself carries no shape, so a shot always lands on a point and
## never on a hull-wide fallback that would make the split cosmetic.
##
## The ship is solid against the player, unlike every other enemy. A fighter that
## flew through the hull would break the one thing the scale exists to sell, so the
## sections sit on the world layer as well as the enemy layer and the ship is a wall.
##
## The model already faces `+X` with `+Y` up, which is the game's forward
## convention, so no yaw trim is needed: the body's own `rotation.y` aims the hull.

## The hull, measured with `tools/probe_boss.gd`. Keeping the numbers here instead
## of re-reading the GLB every spawn means the framing and the collision shape are
## facts at build time.
const MODEL_SCENE: PackedScene = preload(
	"res://models/boss-1/capital_mother_ship_class_two..glb"
)
const MODEL_SIZE: Vector3 = Vector3(6.945099, 1.779842, 1.358975)
const MODEL_CENTER: Vector3 = Vector3(5.859949, 2.026372, 1.097977)
## 23 times the player's 4.15-unit airframe, and longer than the 75 units the game
## camera sees vertically: the ship is deliberately bigger than the frame, which is
## what "surprising" has to mean at this scale.
const SCALE: float = 13.8

## The surface the arena puts under the play plane. The hull sits on it instead of
## hovering: a ship this big has no polite altitude, and the decks have to read from
## a camera that looks almost straight down.
const GROUND_Y: float = -1.5

const BOSS_NAME: String = "CAPITAL SHIP"
const BOSS_HP: int = 1200
const BOSS_SCORE: int = 5000
## The hull is fought as three points, one per section: bow, middle and stern.
## `BOSS_HP` stays the ship's total so the bar, the phase threshold and the score
## keep one meaning; each point owns a third.
const SECTION_COUNT: int = 3
const PART_COUNT: int = SECTION_COUNT
const PART_HP: int = BOSS_HP / PART_COUNT
## Below this share of the pool the ship stops holding back: it turns harder, fires
## faster and adds the radial burst, so the second half of the fight is a different
## problem instead of the first half repeated.
const PHASE_TWO_RATIO: float = 0.6

## Slow enough that the player can always outrun it. The chase is the player's
## choice, and the ship is a place to fight over rather than a pursuer.
const CRUISE_SPEED: float = 7.0
const PHASE_TWO_SPEED: float = 10.0
## Degrees per second. A hull this long turns like a building on purpose: the
## player has to be able to circle it, so the nose is never a tracking turret.
const TURN_RATE_DEGREES: float = 12.0
const PHASE_TWO_TURN_RATE: float = 18.0

## First burst waits long enough for the arrival to be read before the first shot,
## and the three guns stagger from it so the opening is one threat, not three at once.
const FIRST_BURST_DELAY: float = 2.2
const FIRST_BURST_STAGGER: float = 0.9

## Which gun each section answers with, bow to stern. The bow is the vulcan because a
## gun in front of a ship is what a gun in front of a ship means; the stern carries the
## main laser because it is the heaviest mount; the middle launches the pair.
const WEAPON_KINDS: Array[int] = [
	BossWeapon.Kind.VULCAN,
	BossWeapon.Kind.MISSILES,
	BossWeapon.Kind.LASER,
]

## The phase-two ring is the ship's own pattern, not a section's: it is radial, so it
## has no aim and no telegraph, and it is the answer to a player who parks on the hull.
const RING_READY: float = 5.0
const BOSS_RING_BULLETS: int = 24
const BOSS_RING_SPEED: float = 26.0

## The middle section's pair. The tuning matches `MissileEnemy` on purpose: the
## counterplay — turn, dash, transform, decoy — must not change because the missile
## came from a capital ship instead of a launcher.
const BOSS_MISSILE_SPEED: float = 33.0
const BOSS_MISSILE_DAMAGE: int = 2
const BOSS_MISSILE_TURN_RATE: float = 1.6
const BOSS_MISSILE_LIFETIME: float = 6.0
const BOSS_MISSILE_SIZE: Vector3 = Vector3(0.50, 0.42, 2.1)

## The break-up. Twelve blasts walked bow to stern, each several times a fighter's
## death blast, then one detonation at the hull's centre sized to the ship: a 96-unit
## hull has to come apart like a capital ship, not like a turret with a longer bar.
const DEATH_BLASTS: int = 12
const DEATH_STEP: float = 0.11
const CASCADE_SHAKE: float = 0.5
const FINAL_SHAKE: float = 3.0
const CASCADE_SCALE: float = 2.2
const FINAL_SCALE: float = 6.0

## A section coming apart is a real explosion, not a hit: it is a third of a capital
## ship, so the blast is bigger than a fighter's death.
const PART_BLAST_SCALE: float = 2.2
const PART_BLAST_SHAKE: float = 0.9

## The hull catches fire as each section's pool drains. Two stations per section: the
## first deck lights at 90 percent of that section, the second at 55. Local fires are
## what make the split readable: shoot the bow and the bow burns.
const PART_FIRE_THRESHOLDS: Array[float] = [0.90, 0.55]
## Anchors in hull space, as fractions of the half extents: x along the keel, y up
## from the hull centre and z across the beam. The y fraction is at or just above
## the bounding-box top, because a billboard placed under the opaque deck is buried
## inside the hull and never reaches the camera. The list walks bow to stern, so the
## first deck to catch fire is the one the player is usually shooting at.
const FIRE_ANCHORS: Array[Vector3] = [
	Vector3(0.80, 0.88, -0.52),
	Vector3(0.62, 1.00, 0.48),
	Vector3(0.34, 1.05, -0.28),
	Vector3(0.02, 1.00, 0.62),
	Vector3(-0.30, 1.04, -0.55),
	Vector3(-0.66, 1.00, 0.30),
]

## A hit has to be visible on a hull this large. The projectile's own spark is a
## two-unit flash at the point of impact, which lands under the opaque deck from a
## top-down camera; this flash is placed on the upper deck toward the player, where
## the camera can actually see it.
const HIT_FLASH_SIZE: float = 7.0
const HIT_FLASH_DURATION: float = 0.16

## The missile lock on a capital ship: a small box that sits on the hull. Big enough
## to read as a lock from the cockpit, small enough that its corners stay over the
## ship instead of hanging in the air.
const LOCK_MARK_HALF: Vector2 = Vector2(5.0, 3.2)

var _heading: Vector3 = Vector3.RIGHT
## Bow, middle, stern. The hull's collision and its damage live here, not on the
## body: the sections are what the player actually fights.
var _parts: Array[BossPart] = []
## One gun per section, in the same bow-to-stern order. The gun asks its own section
## whether it is still alive, so the silence is a property of the section.
var _weapons: Array[BossWeapon] = []
var _fires: Array[HullFire] = []
## One lock anchor per section, at the section's own centre. The radar locks the
## ship once and the rack splits its salvo over these points, so a player can put
## missiles on the bow, the middle or the stern and the damage lands on that third.
var _lock_anchors: Array[Node3D] = []
var _hull_flash: MeshInstance3D
var _hull_flash_quad: QuadMesh
var _hull_flash_tween: Tween
## The ring is the ship's own clock; the sections keep theirs.
var _ring_timer: float = RING_READY
var _dead: bool = false


func score_value() -> int:
	return BOSS_SCORE


func _ready() -> void:
	_hp = BOSS_HP
	add_to_group(&"enemy")
	add_to_group(&"boss")
	_player = _find_player()
	_build_visual()
	_build_parts()
	_build_lock_anchors()
	_build_weapons()
	_build_fires()
	_build_hull_flash()
	GlobalEventBus.boss_appeared.emit(BOSS_NAME, BOSS_HP)


## Called by the arena right after the ship enters the tree. It arrives pointed at
## the player, because an arrival that wandered off on its own heading would be a
## flyby the player never notices.
func setup_spawn(spawn_position: Vector3) -> void:
	global_position = spawn_position
	if is_instance_valid(_player):
		var to_player: Vector3 = _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			_heading = to_player.normalized()
	_apply_heading()


func _physics_process(delta: float) -> void:
	if _dead:
		return

	if not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return

	_steer(delta)
	_drive(delta)
	_tick_weapons(delta)
	_tick_ring(delta)


func is_phase_two() -> bool:
	return _hp <= int(float(BOSS_HP) * PHASE_TWO_RATIO)


## The heading walks toward the player at a fixed rate instead of snapping to the
## bearing: the turn is the fight's clock, and a ship that aimed instantly would
## make circling pointless.
func _steer(delta: float) -> void:
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return

	var rate: float = PHASE_TWO_TURN_RATE if is_phase_two() else TURN_RATE_DEGREES
	var step: float = deg_to_rad(rate) * delta
	var turn: float = _heading.signed_angle_to(to_player.normalized(), Vector3.UP)
	_heading = _heading.rotated(Vector3.UP, clampf(turn, -step, step))
	_apply_heading()


## The body's yaw is the hull's yaw, so the collision shape and the model turn
## together and every gun keeps its section's place on the keel.
func _apply_heading() -> void:
	rotation.y = atan2(-_heading.z, _heading.x)


## The body carries no collision shape: the sections own the hull, and the planet has
## no world geometry to slide against. Integrating the position directly keeps the
## motion independent of a body that must never intercept a shot.
func _drive(delta: float) -> void:
	var speed: float = PHASE_TWO_SPEED if is_phase_two() else CRUISE_SPEED
	global_position += Vector3(_heading.x, 0.0, _heading.z) * speed * delta


## Each section answers on its own clock. The boss only hands them the same player and
## phase, so a destroyed section cannot be kept alive by the ship's state machine.
func _tick_weapons(delta: float) -> void:
	var phase_two: bool = is_phase_two()
	for weapon in _weapons:
		weapon.tick(delta, _player, phase_two)


## The ring is the ship's own escalation, so it is the one pattern with no aim and no
## telegraph: there is no line to read, only bullets leaving the silhouette.
func _tick_ring(delta: float) -> void:
	if not is_phase_two():
		return
	_ring_timer -= delta
	if _ring_timer > 0.0:
		return
	_ring_timer = RING_READY
	_fire_ring()


func _fire_ring() -> void:
	for index in BOSS_RING_BULLETS:
		var angle: float = TAU * float(index) / float(BOSS_RING_BULLETS)
		var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var edge: Vector3 = global_position + _hull_edge(angle).rotated(
			Vector3.UP, rotation.y
		)
		spawn_shot(edge, direction, BOSS_RING_SPEED)
	Sfx.play_at(&"enemy_fire", global_position)


## Where a radial shot leaves the hull. Firing the ring from the ship's centre
## would hide every bullet under an opaque 96-unit slab until it cleared the
## silhouette, and the pattern meant to punish a player parked on the hull would
## be the one they cannot see coming. The silhouette is the hull rectangle, so the
## distance to the edge along a direction is the ray/rectangle hit.
func _hull_edge(world_angle: float) -> Vector3:
	var local_angle: float = world_angle + rotation.y
	var cosine: float = absf(cos(local_angle))
	var sine: float = absf(sin(local_angle))
	var reach: float = minf(
		_half_length() / maxf(cosine, 0.0001),
		_half_width() / maxf(sine, 0.0001)
	)
	return Vector3(cos(local_angle), 0.0, sin(local_angle)) * reach


## One enemy shot. The hull sits on the world layer so the player cannot fly through
## it, which also puts it inside an enemy bullet's default mask: the ship would shoot
## down its own fire on the frame it left the flank. The boss is a planet-only
## encounter and the planet has no world colliders, so its shots only need the player
## layer.
func spawn_shot(
	origin: Vector3,
	direction: Vector3,
	speed: float,
	damage: int = 1,
	tint: Color = Color(0.0, 0.0, 0.0, 0.0)
) -> void:
	if bullet_scene == null:
		return
	var bullet: Projectile = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin
	bullet.setup(direction, speed, Projectile.Team.ENEMY, damage, Projectile.DART_SIZE, null, 0.0, tint)
	bullet.collision_mask = 1 << Projectile.LAYER_PLAYER


## The middle section's pair. The missile owns its own layer and group, so the only
## thing the hull decides is where it leaves and who it chases.
func spawn_missile(origin: Vector3, direction: Vector3, target: Node3D) -> void:
	if bullet_scene == null:
		return
	var missile: Projectile = bullet_scene.instantiate()
	get_tree().current_scene.add_child(missile)
	missile.global_position = origin
	missile.setup(
		direction,
		BOSS_MISSILE_SPEED,
		Projectile.Team.ENEMY,
		BOSS_MISSILE_DAMAGE,
		BOSS_MISSILE_SIZE,
		target,
		BOSS_MISSILE_TURN_RATE,
		Color(0.0, 0.0, 0.0, 0.0),
		BOSS_MISSILE_LIFETIME,
		Projectile.Style.MISSILE
	)


## Player fire never reaches this: every shot lands on a `BossPart` and is routed
## there, which is what keeps the points independent. This is the hull-wide helper
## the capture tool and the suite use to put the ship at a known pool; it drains bow
## to stern and never spills damage past a point.
func take_damage(amount: int) -> void:
	if _dead:
		return

	var remaining: int = amount
	for part in _parts:
		if remaining <= 0:
			return
		if part.is_destroyed():
			continue
		var dealt: int = mini(remaining, part.current_hp())
		part.take_damage(dealt)
		remaining -= dealt


## The bar reads the pool the ship started with, not the pool it has left, so the
## HUD never has to remember the maximum.
func _sync_health() -> void:
	var total: int = 0
	for part in _parts:
		total += part.current_hp()
	_hp = total
	GlobalEventBus.boss_health_changed.emit(_hp, BOSS_HP)
	_update_fires()


func _on_part_damaged(part: BossPart, _current: int, _maximum: int) -> void:
	_sync_health()
	_flash_hit(part)


## One section down is not the kill. A section falls when its point does, and the
## ship dies when the third section falls. The last point does not get its own blast:
## the break-up owns that beat.
func _on_part_destroyed(part: BossPart) -> void:
	_sync_health()

	if destroyed_sections() >= SECTION_COUNT:
		_die()
		return

	Sfx.play_at(&"explosion", part.global_position)
	_spawn_blast(part.global_position, PART_BLAST_SHAKE, PART_BLAST_SCALE)


## Read-only view of the target points, in bow-to-stern order: one per section. The
## suite and the capture tool drive a point without going through the hull helper.
func parts() -> Array[BossPart]:
	return _parts


## A section is finished when its point is. That is the unit the gun and the fires
## read, so a destroyed third stops answering and burns at full intensity.
func is_section_destroyed(section: int) -> bool:
	if section < 0 or section >= SECTION_COUNT:
		return false
	for part in _parts:
		if part.section_id == section and not part.is_destroyed():
			return false
	return true


func destroyed_sections() -> int:
	var total: int = 0
	for section in SECTION_COUNT:
		if is_section_destroyed(section):
			total += 1
	return total


## The pool of one section: its point's pool. The bar reads all three, the fires read
## each section, and the phase threshold reads the ship.
func section_hp(section: int) -> int:
	var total: int = 0
	for part in _parts:
		if part.section_id == section:
			total += part.current_hp()
	return total


func destroyed_parts() -> int:
	var total: int = 0
	for part in _parts:
		if part.is_destroyed():
			total += 1
	return total


## Read-only view of the section guns, in bow-to-stern order, so the suite can prove
## that destroying a section silences exactly its own gun.
func weapons() -> Array[BossWeapon]:
	return _weapons


## The lock is a small box on the hull, not a frame around a third of it. A
## hull-sized frame reads as detached: its corners hang over the water because the
## ship narrows toward the bow and the stern, and a mark that floats is a mark the
## player does not trust. A turret-sized box, on the other hand, disappears on a
## 96-unit ship. The mark is bigger than a fighter's but small enough to sit on the
## ship it belongs to.
## `x` is the half length, `y` the height above the body and `z` the half width: the
## same order the reticle's `set_mark_size` takes.
func lock_mark() -> Vector3:
	return Vector3(
		LOCK_MARK_HALF.x,
		GROUND_Y + _half_height(),
		LOCK_MARK_HALF.y
	)


## The mark sits at the hull's own mid height, not above it: at that height the
## opaque model would hide a depth-tested box, so the reticle draws over the ship.
func lock_mark_on_hull() -> bool:
	return true


## The three places a missile can be locked on: bow, middle and stern. A turret
## offers none and keeps the single mark on its body; the ship offers one per
## section, so the rack can be spent on the part the player wants to finish.
func lock_mark_anchors() -> Array[Node3D]:
	return _lock_anchors


func _die() -> void:
	if _dead:
		return

	_dead = true
	# The bar goes before the cascade: the fight is decided on this frame, and a
	# full bar over a hull that is already coming apart would be a lie.
	GlobalEventBus.boss_defeated.emit()
	killed.emit()
	GameProgress.instance().register_kill()
	GlobalEventBus.enemy_killed.emit(score_value())
	_break_apart()


## The cascade is a coroutine so the ship is not freed on the frame it dies: the
## blasts have to outlive the hull, and the wreck stays a valid node until the
## cascade finishes.
func _break_apart() -> void:
	Sfx.play_at(&"explosion", global_position)

	for index in DEATH_BLASTS:
		if not is_inside_tree():
			return
		var t: float = float(index) / float(maxi(DEATH_BLASTS - 1, 1))
		var local: Vector3 = Vector3(
			lerpf(-_half_length() * 0.92, _half_length() * 0.92, t),
			_half_height() * randf_range(0.7, 1.3),
			randf_range(-_half_width(), _half_width()) * 0.75
		)
		_spawn_blast(
			global_position + local.rotated(Vector3.UP, rotation.y),
			CASCADE_SHAKE,
			CASCADE_SCALE
		)
		await get_tree().create_timer(DEATH_STEP).timeout

	if not is_inside_tree():
		return
	if is_instance_valid(_visual):
		_visual.visible = false
	# The last blast is the ship's own size: it opens at the hull's centre and has to
	# read from the far end of the arena.
	_spawn_blast(
		global_position + Vector3(0.0, _half_height(), 0.0),
		FINAL_SHAKE,
		FINAL_SCALE
	)
	queue_free()


func _spawn_blast(at: Vector3, shake: float, scale: float) -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		return
	var blast: ShipExplosion = ShipExplosion.new()
	blast.shake_strength = shake
	blast.scale_multiplier = scale
	host.add_child(blast)
	blast.global_position = at


func _half_length() -> float:
	return MODEL_SIZE.x * SCALE * 0.5


func _half_width() -> float:
	return MODEL_SIZE.z * SCALE * 0.5


func _half_height() -> float:
	return MODEL_SIZE.y * SCALE * 0.5


## The hull replaces the placeholder the base class builds. The model is offset by
## its own measured centre so the body's origin is the middle of the ship, which is
## what keeps the sections, the muzzle stations and the death cascade in one
## coordinate space.
func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Hull"
	# The belly sits on the surface and the decks stack above it.
	_visual.position.y = GROUND_Y + _half_height()
	add_child(_visual)

	var model: Node3D = MODEL_SCENE.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * SCALE
	model.position = -MODEL_CENTER * SCALE
	_visual.add_child(model)


## The three target points are the hull's only collision, one per section and as wide
## as the beam. A box that covers its whole third at the hull's own height means a
## shot that visibly crosses a section lands on it and never on a hull-wide fallback
## that would make the split cosmetic.
##
## Index 0 is the bow, so the walk goes from +X to -X. The box centre sits at the
## hull's height, not on the play plane: a shape at the body origin would leave the
## upper decks outside the collision, where a shot can visibly cross them and miss.
func _build_parts() -> void:
	var length: float = _half_length() * 2.0
	var section_length: float = length / float(SECTION_COUNT)
	var part_width: float = MODEL_SIZE.z * SCALE
	for section in SECTION_COUNT:
		var part: BossPart = BossPart.new()
		part.name = "Part%d" % section
		part.setup(
			section,
			section,
			PART_HP,
			Vector3(section_length, MODEL_SIZE.y * SCALE, part_width)
		)
		part.position = Vector3(
			_half_length() - section_length * (float(section) + 0.5),
			GROUND_Y + _half_height(),
			0.0
		)
		part.damaged.connect(_on_part_damaged)
		part.destroyed.connect(_on_part_destroyed)
		add_child(part)
		_parts.append(part)


## One lock anchor per section, at the section's centre and at the hull's own mid
## height, which is where the mark sits so it reads as attached to the ship. They
## are plain markers, not hitboxes: a shot is aimed here and the hull under it takes
## the damage, so the anchors never become a second damage path.
##
## They hang from the body, not the visual, so they follow the same coordinate space
## as the target points.
func _build_lock_anchors() -> void:
	var length: float = _half_length() * 2.0
	var section_length: float = length / float(SECTION_COUNT)
	for section in SECTION_COUNT:
		var anchor: Marker3D = Marker3D.new()
		anchor.name = "LockAnchor%d" % section
		anchor.position = Vector3(
			_half_length() - section_length * (float(section) + 0.5),
			GROUND_Y + _half_height(),
			0.0
		)
		add_child(anchor)
		_lock_anchors.append(anchor)


## One fire per damage station, parented to the hull so it turns with the ship and
## hides with it when the wreck comes apart.
func _build_fires() -> void:
	for index in FIRE_ANCHORS.size():
		var fire: HullFire = HullFire.new()
		fire.name = "Fire%d" % index
		fire.position = Vector3(
			FIRE_ANCHORS[index].x * _half_length(),
			FIRE_ANCHORS[index].y * _half_height(),
			FIRE_ANCHORS[index].z * _half_width()
		)
		_visual.add_child(fire)
		_fires.append(fire)
	_update_fires()


## Fire is a function of each section's pool, not an event: it is recomputed on every
## hit so the blaze can never drift out of step with the bar. The pool is the
## section's point, so the fire drains as the third is worn down. Two stations per
## section, so the fire tells the player which third is wearing down.
func _update_fires() -> void:
	if (
		_parts.size() != PART_COUNT
		or _fires.size() != SECTION_COUNT * PART_FIRE_THRESHOLDS.size()
	):
		return

	for section in SECTION_COUNT:
		var ratio: float = float(section_hp(section)) / float(maxi(PART_HP, 1))
		for station in PART_FIRE_THRESHOLDS.size():
			var fire: HullFire = _fires[section * PART_FIRE_THRESHOLDS.size() + station]
			# A destroyed section burns at full intensity: it is the clearest read
			# that this third is finished, short of cutting the model apart.
			if is_section_destroyed(section):
				fire.ignite(1.0)
				continue
			var threshold: float = PART_FIRE_THRESHOLDS[station]
			if ratio > threshold:
				fire.ignite(0.0)
				continue
			# A fire that has just lit starts small and grows as the section keeps
			# taking damage, so it looks worse at 20 percent than at 60.
			var depth: float = (threshold - ratio) / threshold
			fire.ignite(0.35 + 0.65 * clampf(depth, 0.0, 1.0))


## Read-only count of lit fires, so the suite can assert the damage state without
## reaching into the visual tree.
func burning_fires() -> int:
	var total: int = 0
	for fire in _fires:
		if fire.is_burning():
			total += 1
	return total


func _build_hull_flash() -> void:
	var quad: QuadMesh = QuadMesh.new()
	# The size lives in the mesh: a billboarded instance ignores its own scale, so
	# a `scale = HIT_FLASH_SIZE` flash renders one unit wide and is never seen.
	quad.size = Vector2.ONE * HIT_FLASH_SIZE
	_hull_flash_quad = quad

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.66, 0.36, 0.9)
	material.albedo_texture = _puff_texture()
	# The flash is centred on the deck, so half of it would be buried in the opaque
	# hull without this.
	material.no_depth_test = true

	_hull_flash = MeshInstance3D.new()
	_hull_flash.name = "HitFlash"
	_hull_flash.mesh = quad
	_hull_flash.material_override = material
	_hull_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Top level: the flash is placed in world space on the upper deck, not in the
	# hull's rotating local space.
	_hull_flash.top_level = true
	_hull_flash.visible = false
	add_child(_hull_flash)


## A short warm flash on the section the player is shooting at. The projectile's own
## spark is at the impact point, which the opaque hull hides from above; this is the
## hit the player can actually see, and it has to name the section that took it.
func _flash_hit(part: BossPart) -> void:
	if _hull_flash == null or part == null:
		return

	_hull_flash.global_position = Vector3(
		part.global_position.x,
		# On the top deck, not under it: a flash centred below the hull top is
		# buried inside the opaque model from a top-down camera.
		GROUND_Y + _half_height() * 2.0 + 1.0,
		part.global_position.z
	)
	_hull_flash.transparency = 0.0
	_hull_flash_quad.size = Vector2.ONE * HIT_FLASH_SIZE
	_hull_flash.visible = true

	if _hull_flash_tween != null and _hull_flash_tween.is_valid():
		_hull_flash_tween.kill()
	_hull_flash_tween = create_tween()
	_hull_flash_tween.set_parallel(true)
	_hull_flash_tween.tween_property(
		_hull_flash_quad,
		"size",
		Vector2.ONE * HIT_FLASH_SIZE * 1.5,
		HIT_FLASH_DURATION
	)
	_hull_flash_tween.tween_property(_hull_flash, "transparency", 1.0, HIT_FLASH_DURATION)
	_hull_flash_tween.chain().tween_callback(_hide_hull_flash)


func _hide_hull_flash() -> void:
	if _hull_flash != null:
		_hull_flash.visible = false


## The flash quad is a billboarded, soft-edged radial gradient generated in code,
## the same placeholder vocabulary as the explosion.
func _puff_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.3, Color(1.0, 1.0, 1.0, 0.55))
	gradient.add_point(0.65, Color(1.0, 1.0, 1.0, 0.16))
	gradient.set_color(3, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


## One gun per section, on the play plane. A shot born at the section body's height
## would fly over the player for the whole fight, so the gun sits at the section's x
## on the body's own y = 0 and fires from the section's silhouette edge. The three
## are staggered from `FIRST_BURST_DELAY`, so the arrival opens with one threat
## instead of three at once. The section, not the point, owns the gun: a point falling
## does not silence a third that still has a live half.
func _build_weapons() -> void:
	var section_length: float = _half_length() * 2.0 / float(SECTION_COUNT)
	var top: float = GROUND_Y + _half_height() * 2.0
	for section in SECTION_COUNT:
		var weapon: BossWeapon = BossWeapon.new()
		weapon.name = "Weapon%d" % section
		weapon.setup(
			WEAPON_KINDS[section],
			self,
			section,
			section_length,
			_half_width() * 2.0,
			top
		)
		weapon.position = Vector3(
			_half_length() - section_length * (float(section) + 0.5),
			0.0,
			0.0
		)
		weapon.arm(FIRST_BURST_DELAY + FIRST_BURST_STAGGER * float(section))
		add_child(weapon)
		_weapons.append(weapon)
