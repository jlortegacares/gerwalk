class_name FighterEnemy
extends Enemy
## Enemy interceptor. It flies the player's own airframe and the player's own
## nose-first flight model, but it never transforms: the wings stay folded, the
## gun stays bolted to the airframe, and the only weapon is the missile rack.
##
## It inherits from `Enemy` for the identity, not for the movement. Everything the
## rest of the game asks of a hostile -- the arena's population count and despawn,
## the radar's contact list, the bomb's damage, the player's missile lock -- goes
## through the `enemy` group and the `Enemy` type, so being one is what keeps this
## ship a first-class target. The turret's roam/orbit state machine, its hull and
## its bullet patterns are all replaced here; what survives from the base is the
## hit flash, the damage bookkeeping and the `killed` signal.
##
## Speed is the brief's "medium": the ceiling sits between the player's hover
## cruise (26.8) and the burner (42), so GERWALK cannot outrun it but FIGHTER and
## the afterburner can. That is the whole point of the enemy -- a chase that the
## player wins by choosing a mode, not by holding a direction.

## Tougher than a turret, softer than the launcher: the counterplay is a burst on
## the pass, so the hull has to survive one exchange but not two.
const FIGHTER_HP: int = 8

## Flight model. The airspeed is a state, not the projection of the velocity: the
## ship accelerates into its ceiling and holds it, and only the turn is capped.
## 34 sits between the hover cruise and the burner, and the floor keeps a
## disengaged patrol moving instead of hovering in place like a turret.
const TOP_SPEED: float = 34.0
const FLOOR_SPEED: float = 15.0
const ACCELERATION: float = 55.0
const BRAKE: float = 90.0
## Well below the player's 400 deg/s: the player has to be able to read the nose
## coming round, and a mirror of the player's own turn rate would make the pass a
## coin flip.
const TURN_RATE: float = 120.0
## A fighter leans with the whole wing, exactly like the player's does, because in
## this mode the bank is the only cue that the nose is turning.
const BANK: float = 50.0
const BANK_RATE: float = 6.0
const NOSE_PITCH: float = -5.0

## Engagement. The aggro is wide because the encounter starts as a flyby: the
## arena spawns contacts 85-110 units ahead, and a fighter that only noticed the
## ship at turret range would cross the whole encounter without ever committing.
const CHASE_RADIUS: float = 62.0
const BREAK_OFF_RADIUS: float = 130.0
## The launch window. Inside the attack range and roughly on the nose it commits;
## closer than the minimum it has to extend first, or the missile would be born
## past the ship it is chasing.
const ATTACK_RANGE: float = 46.0
const MIN_LAUNCH_RANGE: float = 12.0
const AIM_TOLERANCE_DEGREES: float = 22.0
## Patrol drift. It is a leg, not a random walk: the heading is held for a few
## seconds so the silhouette reads as a ship with somewhere to go.
const WANDER_TIME: float = 3.4
const WANDER_ARC: float = 0.9

## The rearm. It is shorter than the break on purpose: the ship spends the break
## extending, and the clock has to be done by the time the next approach crosses
## the attack range, or the reload would always finish behind the player and the
## fight would degrade into one salvo every other pass.
const RELOAD_TIME: float = 1.5
## The first pass commits almost at once. The spawn is already the encounter, and a
## full reload before the opening shot would burn the one clean approach the ship
## gets before the merge turns into a turning fight.
const FIRST_PASS_TIME: float = 0.9
const WARNING_TIME: float = 0.72
const EXTEND_TIME: float = 2.1

## The salvo is a pair off the wing hardpoints, like the player's own: the shot
## leaves from where the wing is, so a swept wing fires from the swept hardpoint.
const SALVO: int = 2
const MISSILE_SPEED: float = 36.0
const MISSILE_DAMAGE: int = 2
const MISSILE_TURN_RATE: float = 1.7
const MISSILE_SIZE: Vector3 = Vector3(0.46, 0.38, 1.9)
const MISSILE_LIFETIME: float = 5.0
const MISSILE_SPREAD_DEGREES: float = 5.0
const LAUNCH_CLEARANCE: float = 0.35

## The nose is long, so the fallback muzzle and the aim beam start past its tip.
const NOSE_DISTANCE: float = 2.9
const AIM_LENGTH: float = 5.5

## Hostile livery. The airframe is the player's, so the paint is what tells the two
## apart at a glance: the hull goes maroon, the stripe keeps the enemy red the
## turrets already use, and the canopy and lines go near-black.
const HULL_COLOR: Color = Color(0.36, 0.13, 0.15, 1.0)
const TRIM_COLOR: Color = Color(0.93, 0.36, 0.48, 1.0)
const CANOPY_COLOR: Color = Color(0.09, 0.05, 0.06, 1.0)
const LINES_COLOR: Color = Color(0.07, 0.05, 0.06, 1.0)
const NOSE_COLOR: Color = Color(0.44, 0.16, 0.17, 1.0)

var _model: PlayerModel
var _heading: Vector3 = Vector3.RIGHT
var _desired_heading: Vector3 = Vector3.RIGHT
var _airspeed: float = FLOOR_SPEED
var _wander_heading: Vector3 = Vector3.RIGHT
var _wander_timer: float = 0.0
var _visual_yaw: float = 0.0
var _bank: float = 0.0
var _yaw_rate: float = 0.0
var _sweep: float = 0.0


func _ready() -> void:
	_hp = FIGHTER_HP
	add_to_group(&"enemy")
	_player = _find_player()
	_build_visual()
	_build_aim_beam()


## Called by the arena right after the ship enters the tree. It is pointed at the
## ship on the way in, because the spawn is already an encounter: a contact that
## wandered off on its own heading would be a flyby the player never notices.
func setup_spawn(spawn_position: Vector3) -> void:
	global_position = spawn_position
	_airspeed = FLOOR_SPEED
	if is_instance_valid(_player):
		var to_player: Vector3 = _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			_heading = to_player.normalized()
	_desired_heading = _heading
	_wander_heading = _heading
	_visual_yaw = atan2(-_heading.z, _heading.x)


func _physics_process(delta: float) -> void:
	if _state == Enemy.State.DEAD:
		return

	_hit_flash = maxf(_hit_flash - delta, 0.0)

	if not is_instance_valid(_player):
		_player = _find_player()

	if _player == null:
		return

	var distance: float = _planar_distance_to(_player.global_position)
	if _state == Enemy.State.ROAM:
		if distance < CHASE_RADIUS:
			_enter_attack(true)
	elif distance > BREAK_OFF_RADIUS:
		_enter_roam()
		return

	_timer -= delta

	match _state:
		Enemy.State.ROAM:
			_tick_roam(delta)
		Enemy.State.ENGAGED:
			_tick_chase()
			if _timer <= 0.0 and _can_launch(distance):
				_enter_telegraph()
		Enemy.State.TELEGRAPH:
			_tick_chase()
			_tick_telegraph()
			if _timer <= 0.0:
				_fire_pattern()
				_enter_recover()
		Enemy.State.RECOVER:
			_tick_extend()
			if _timer <= 0.0:
				_enter_attack()

	_fly(delta)
	_pose(delta)


## The patrol is a straight leg with a drift at the end of it. The wings stay at
## the forward stop because the speed is the floor, which is the one pose the
## fighter frame reads as "cruising slowly".
func _tick_roam(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_heading = _heading.rotated(
			Vector3.UP, randf_range(-WANDER_ARC, WANDER_ARC)
		)
		_wander_timer = WANDER_TIME
	_desired_heading = _wander_heading


## Committed: the nose tracks the ship and the throttle opens up. A fighter that
## could not point at its target could not fire, so the pursuit and the aim are
## the same act -- the turn rate is what makes it survivable.
##
## Inside the launch floor the nose turns away instead of through: a ship that kept
## pointing at the target would fly clean through it and lose the shot, and the
## pass is the attack. The turn radius (34 / 2.09 rad/s, about 16 units) is larger
## than the floor, so the ship cannot break off cleanly -- it goes by close and
## comes round, which is exactly the merge the player is meant to read.
func _tick_chase() -> void:
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()
	if distance < 0.01:
		return
	if distance < MIN_LAUNCH_RANGE:
		_desired_heading = -to_player / distance
		return
	_desired_heading = to_player / distance


## The break. After a launch the ship extends away for the reload, which gives the
## player the window to punish the pass instead of eating a stream of missiles.
func _tick_extend() -> void:
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		_desired_heading = -to_player.normalized()


func _can_launch(distance: float) -> bool:
	if distance > ATTACK_RANGE or distance < MIN_LAUNCH_RANGE:
		return false
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return false
	return rad_to_deg(_heading.angle_to(to_player)) <= AIM_TOLERANCE_DEGREES


## The aim beam is the launch warning. It hangs off the nose and points where the
## missiles will go, so the player reads the commitment before the shot, which is
## the whole counterplay: break the nose off before it lines up.
func _tick_telegraph() -> void:
	_aim_beam.visible = true
	_aim_beam.position = _heading * (NOSE_DISTANCE + AIM_LENGTH * 0.5)
	_aim_beam.rotation.y = atan2(_heading.x, _heading.z)
	_aim_beam.scale.z = AIM_LENGTH


## The heading turns at a capped rate; the airspeed is its own state. Both are
## written every frame, and the airframe is posed after them so the model and the
## rule agree on the same frame.
func _fly(delta: float) -> void:
	var yaw: float = atan2(-_heading.z, _heading.x)
	var target_yaw: float = atan2(-_desired_heading.z, _desired_heading.x)
	var step: float = deg_to_rad(TURN_RATE) * delta
	var turn: float = clampf(angle_difference(yaw, target_yaw), -step, step)
	yaw = wrapf(yaw + turn, -PI, PI)
	_yaw_rate = turn / delta if delta > 0.0 else 0.0
	_heading = Vector3(cos(yaw), 0.0, -sin(yaw))

	var wanted: float = TOP_SPEED if _state != Enemy.State.ROAM else FLOOR_SPEED
	var rate: float = ACCELERATION if wanted > _airspeed else BRAKE
	_airspeed = move_toward(_airspeed, wanted, rate * delta)

	velocity = _heading * _airspeed
	velocity.y = 0.0
	move_and_slide()


func _pose(delta: float) -> void:
	var normalised: float = clampf(_yaw_rate / deg_to_rad(TURN_RATE), -1.0, 1.0)
	_bank = lerpf(_bank, -deg_to_rad(BANK) * normalised, 1.0 - exp(-BANK_RATE * delta))
	_visual_yaw = atan2(-_heading.z, _heading.x)
	_visual.rotation.y = _visual_yaw
	_visual.rotation.x = _bank
	_visual.rotation.z = deg_to_rad(NOSE_PITCH)
	_visual.scale = Vector3.ONE * (1.0 + _hit_flash * 0.6)

	if _model == null:
		return
	# The same sweep curve the player's fighter flies, measured against this
	# ship's own ceiling: the wings fold as it accelerates, and the ceiling is the
	# cruise stop, because it has no burner to sweep past.
	var fraction: float = clampf(_airspeed / TOP_SPEED, 0.0, 1.0)
	_sweep = lerpf(
		Player.WING_SWEEP_FORWARD, Player.WING_SWEEP_CRUISE, fraction * fraction
	)
	_model.pose_mode(0.0, _sweep)


func _enter_attack(first: bool = false) -> void:
	_state = Enemy.State.ENGAGED
	_timer = FIRST_PASS_TIME if first else RELOAD_TIME
	_aim_beam.visible = false


func _enter_roam() -> void:
	_state = Enemy.State.ROAM
	_aim_beam.visible = false
	_wander_heading = _heading
	_wander_timer = WANDER_TIME


func _enter_telegraph() -> void:
	_state = Enemy.State.TELEGRAPH
	_timer = WARNING_TIME
	_aim_beam.visible = true


func _enter_recover() -> void:
	_state = Enemy.State.RECOVER
	_timer = EXTEND_TIME
	_aim_beam.visible = false


## A pair off the hardpoints, one per wing, spread so the two lines separate. The
## hardpoint is read in the model's frame and converted to world, which is what
## makes the launch point ride the sweep instead of hanging in model space.
func _fire_pattern() -> void:
	if bullet_scene == null or not is_instance_valid(_player):
		return

	var hardpoints: Array[Vector3] = []
	if _model != null:
		hardpoints = _model.wing_anchors()

	for index in SALVO:
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var origin: Vector3 = global_position + _heading * NOSE_DISTANCE
		if hardpoints.size() >= 2:
			var pick: int = 0 if side < 0.0 else 1
			origin = _model.to_global(hardpoints[pick]) + _heading * LAUNCH_CLEARANCE
		var spread: float = (
			deg_to_rad(MISSILE_SPREAD_DEGREES) * (float(index) - float(SALVO - 1) * 0.5)
		)
		_spawn_missile(origin, _heading.rotated(Vector3.UP, spread))


func _spawn_missile(origin: Vector3, direction: Vector3) -> void:
	var missile: Projectile = bullet_scene.instantiate()
	get_tree().current_scene.add_child(missile)
	missile.global_position = origin
	missile.setup(
		direction,
		MISSILE_SPEED,
		Projectile.Team.ENEMY,
		MISSILE_DAMAGE,
		MISSILE_SIZE,
		_player,
		MISSILE_TURN_RATE,
		Color(0.0, 0.0, 0.0, 0.0),
		MISSILE_LIFETIME,
		Projectile.Style.MISSILE
	)


## The player's own airframe, painted hostile. The model is the same one the
## player flies, so the silhouette reads as a peer instead of a prop; the livery is
## what keeps friend and foe apart.
##
## The meshes go back to the default render layer after the build: `PlayerModel`
## puts the airframe on the player's own layer so the ship's fill light can find
## it, and that light would otherwise paint an enemy that happens to be close.
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_model = PlayerModel.new()
	_model.name = "Model"
	_model.set_livery(HULL_COLOR, TRIM_COLOR, CANOPY_COLOR, LINES_COLOR, NOSE_COLOR)
	_visual.add_child(_model)
	if not _model.build():
		push_error("FighterEnemy: the airframe failed to build")
		return

	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh != null:
			mesh.layers = 1
