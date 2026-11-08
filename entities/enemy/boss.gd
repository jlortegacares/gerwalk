class_name Boss
extends Enemy
## The mothership: the planet's final encounter. A capital ship built from the
## `models/boss-1` GLB that flies slowly over the surface and is fought as one
## set piece.
##
## The hull is a single body. Damage anywhere on it counts, because a 96-unit ship
## is already the boss: asking the player to hit a subsystem on a moving slab this
## large would turn the fight into a search problem instead of a duel. What the
## size buys is the arena, not the hitbox.
##
## The ship is solid against the player, unlike every other enemy. A fighter that
## flew through the hull would break the one thing the scale exists to sell, so the
## body sits on the world layer as well as the enemy layer and the ship is a wall.
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

## First burst waits long enough for the arrival to be read before the first shot.
const FIRST_BURST_DELAY: float = 2.2
const BOSS_TELEGRAPH_TIME: float = 1.1
const BOSS_RECOVER_TIME: float = 2.6
const PHASE_TWO_RECOVER: float = 1.8

## Muzzle stations along the hull, as a fraction of the half-length and the flank
## each one fires from. They alternate sides so a burst reads as a broadside coming
## off the whole ship instead of a single gun.
const MUZZLE_STATIONS: Array[Vector2] = [
	Vector2(-0.36, -1.0),
	Vector2(-0.12, 1.0),
	Vector2(0.12, -1.0),
	Vector2(0.36, 1.0),
]
const BOSS_FAN_BULLETS: int = 3
const FAN_SPREAD_DEGREES: float = 7.0
const BULLET_SPEED: float = 30.0
## The phase-two ring is the answer to a player who parks on the hull: it leaves
## from the silhouette edge so the bullets are visible the frame they fire, and it
## forces a reposition.
const BOSS_RING_BULLETS: int = 24
const BOSS_RING_SPEED: float = 26.0

## The break-up. Six blasts walked bow to stern read as a hull coming apart; one
## blast reads as a hull switching off.
const DEATH_BLASTS: int = 6
const DEATH_STEP: float = 0.14
const CASCADE_SHAKE: float = 0.18
const FINAL_SHAKE: float = 1.4

## The hull catches fire as its pool drains. Each entry is a share of the starting
## pool: at 90 percent the first deck burns, and by 30 percent the whole ship is on
## fire. Six stations walked bow to stern, because one fire on a 96-unit hull reads
## as a scorch mark instead of a ship going down.
const FIRE_THRESHOLDS: Array[float] = [0.90, 0.78, 0.66, 0.54, 0.42, 0.30]
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

var _heading: Vector3 = Vector3.RIGHT
var _fires: Array[HullFire] = []
var _hull_flash: MeshInstance3D
var _hull_flash_quad: QuadMesh
var _hull_flash_tween: Tween

@onready var _collider: CollisionShape3D = $CollisionShape3D


func score_value() -> int:
	return BOSS_SCORE


func _ready() -> void:
	_hp = BOSS_HP
	add_to_group(&"enemy")
	add_to_group(&"boss")
	_player = _find_player()
	_build_collider()
	_build_visual()
	_build_fires()
	_build_hull_flash()
	_build_telegraph_beam()
	_state = Enemy.State.ENGAGED
	_timer = FIRST_BURST_DELAY
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
	if _state == Enemy.State.DEAD:
		return

	if not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return

	_steer(delta)
	_drive()
	_tick_attack(delta)


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
## together and the broadside stations stay on the correct flank.
func _apply_heading() -> void:
	rotation.y = atan2(-_heading.z, _heading.x)


func _drive() -> void:
	var speed: float = PHASE_TWO_SPEED if is_phase_two() else CRUISE_SPEED
	velocity = Vector3(_heading.x, 0.0, _heading.z) * speed
	move_and_slide()


func _tick_attack(delta: float) -> void:
	_timer -= delta

	match _state:
		Enemy.State.ENGAGED:
			_aim_beam.visible = false
			if _timer <= 0.0:
				_enter_telegraph()
		Enemy.State.TELEGRAPH:
			_tick_telegraph()
			if _timer <= 0.0:
				_fire()
				_enter_recover()
		Enemy.State.RECOVER:
			if _timer <= 0.0:
				_enter_engaged()


func _enter_engaged() -> void:
	_state = Enemy.State.ENGAGED
	_timer = 0.1


func _enter_telegraph() -> void:
	_state = Enemy.State.TELEGRAPH
	_timer = BOSS_TELEGRAPH_TIME
	_aim_beam.visible = true


func _enter_recover() -> void:
	_state = Enemy.State.RECOVER
	_timer = PHASE_TWO_RECOVER if is_phase_two() else BOSS_RECOVER_TIME
	_aim_beam.visible = false


## The telegraph is one line from the hull's centre to the ship, not four: the
## pattern is a converging broadside, so the player only needs to read where the
## ship is aiming, and four beams would hide the horizon behind red lines.
func _tick_telegraph() -> void:
	var offset: Vector3 = _player.global_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= 0.001:
		return
	_aim_beam.position = offset * 0.5
	_aim_beam.rotation.y = atan2(offset.x, offset.z)
	_aim_beam.scale.z = distance


func _fire() -> void:
	if bullet_scene == null:
		return

	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return
	var aim: Vector3 = to_player.normalized()

	for station in MUZZLE_STATIONS:
		var local: Vector3 = Vector3(
			station.x * _half_length(),
			0.0,
			station.y * _half_width()
		)
		var muzzle: Vector3 = global_position + local.rotated(Vector3.UP, rotation.y)
		for index in BOSS_FAN_BULLETS:
			var offset_index: float = float(index) - float(BOSS_FAN_BULLETS - 1) * 0.5
			var spread: float = deg_to_rad(FAN_SPREAD_DEGREES) * offset_index
			_fire_shot(muzzle, aim.rotated(Vector3.UP, spread), BULLET_SPEED)

	if is_phase_two():
		for index in BOSS_RING_BULLETS:
			var angle: float = TAU * float(index) / float(BOSS_RING_BULLETS)
			var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
			var edge: Vector3 = global_position + _hull_edge(angle).rotated(
				Vector3.UP, rotation.y
			)
			_fire_shot(edge, direction, BOSS_RING_SPEED)

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


func _fire_shot(origin: Vector3, direction: Vector3, speed: float) -> void:
	var bullet: Projectile = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin
	bullet.setup(direction, speed, Projectile.Team.ENEMY, 1)
	# The hull sits on the world layer so the player cannot fly through it, which
	# also puts it inside an enemy bullet's default mask: the ship would shoot down
	# its own broadside on the frame it left the flank. The boss is a planet-only
	# encounter and the planet has no world colliders, so its shots only need the
	# player layer.
	bullet.collision_mask = 1 << Projectile.LAYER_PLAYER


## The bar reads the pool the ship started with, not the pool it has left, so the
## HUD never has to remember the maximum.
func take_damage(amount: int) -> void:
	if _state == Enemy.State.DEAD:
		return

	_hp = maxi(_hp - amount, 0)
	GlobalEventBus.boss_health_changed.emit(_hp, BOSS_HP)
	_update_fires()
	_flash_hit()

	if _hp <= 0:
		_die()


func _die() -> void:
	if _state == Enemy.State.DEAD:
		return

	_state = Enemy.State.DEAD
	_aim_beam.visible = false
	# The bar goes before the cascade: the fight is decided on this frame, and a
	# full bar over a hull that is already coming apart would be a lie.
	GlobalEventBus.boss_defeated.emit()
	killed.emit()
	GameProgress.instance().register_kill()
	GlobalEventBus.enemy_killed.emit(score_value())
	_break_apart()


## The cascade is a coroutine so the ship is not freed on the frame it dies: the
## blasts have to outlive the hull, and the arena keeps the fight suppressed until
## the body is actually gone.
func _break_apart() -> void:
	Sfx.play_at(&"explosion", global_position)

	for index in DEATH_BLASTS:
		if not is_inside_tree():
			return
		var t: float = float(index) / float(maxi(DEATH_BLASTS - 1, 1))
		var local: Vector3 = Vector3(
			lerpf(-_half_length() * 0.8, _half_length() * 0.8, t),
			_half_height(),
			randf_range(-_half_width(), _half_width())
		)
		_spawn_blast(global_position + local.rotated(Vector3.UP, rotation.y), CASCADE_SHAKE)
		await get_tree().create_timer(DEATH_STEP).timeout

	if not is_inside_tree():
		return
	if is_instance_valid(_visual):
		_visual.visible = false
	_spawn_blast(global_position, FINAL_SHAKE)
	queue_free()


func _spawn_blast(at: Vector3, shake: float) -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		return
	var blast: ShipExplosion = ShipExplosion.new()
	blast.shake_strength = shake
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
## what keeps the collision shape, the muzzle stations and the death cascade in one
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


## The collider is the hull's own box, not a capsule. A capsule is centred on the
## body origin, which is the play plane, while the hull is lifted so its belly sits
## on the ground: the top thirteen units of the ship were outside the old shape, and
## a shot that visibly crossed the upper decks could pass through. A box sized from
## the same constants as the model covers the hull exactly, at the hull's height.
func _build_collider() -> void:
	var box: BoxShape3D = BoxShape3D.new()
	box.size = MODEL_SIZE * SCALE
	_collider.shape = box
	_collider.position = Vector3(0.0, GROUND_Y + _half_height(), 0.0)
	_collider.rotation = Vector3.ZERO


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


## The fire is a function of the pool, not an event: it is recomputed on every hit
## so the blaze can never drift out of step with the bar.
func _update_fires() -> void:
	var ratio: float = float(_hp) / float(BOSS_HP)
	for index in _fires.size():
		var threshold: float = FIRE_THRESHOLDS[index]
		if ratio > threshold:
			_fires[index].ignite(0.0)
			continue
		# A fire that has just lit starts small and grows as the hull keeps taking
		# damage, so the ship looks worse at 20 percent than at 60 percent.
		var depth: float = (threshold - ratio) / threshold
		_fires[index].ignite(0.35 + 0.65 * clampf(depth, 0.0, 1.0))


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


## A short warm flash on the deck the player is shooting at. The projectile's own
## spark is at the impact point, which the opaque hull hides from above; this is the
## hit the player can actually see.
func _flash_hit() -> void:
	if _hull_flash == null:
		return

	var direction: Vector3 = _heading
	if is_instance_valid(_player):
		var to_player: Vector3 = _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			direction = to_player.normalized()

	_hull_flash.global_position = global_position + Vector3(
		direction.x * _half_length() * 0.6,
		# On the top deck, not under it: a flash centred below the hull top is
		# buried inside the opaque model from a top-down camera.
		GROUND_Y + _half_height() * 2.0 + 1.0,
		direction.z * _half_width() * 0.6
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


func _build_telegraph_beam() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.32, 0.38, 0.30)

	var mesh: BoxMesh = BoxMesh.new()
	# Wider than the turret's hairline: this line is read from the far end of a
	# 96-unit hull, not from four units away.
	mesh.size = Vector3(1.4, 0.05, 1.0)

	_aim_beam = MeshInstance3D.new()
	_aim_beam.mesh = mesh
	_aim_beam.material_override = material
	_aim_beam.visible = false
	_aim_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_beam)
