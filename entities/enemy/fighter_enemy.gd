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

const SMOKE_COLOR: Color = Color(0.74, 0.79, 0.85, 1.0)
const SMOKE_AMOUNT: int = 450
const SMOKE_LIFETIME: float = 0.50
const SMOKE_PUFF: float = 0.80
const SMOKE_DENSITY_HIGH: float = 0.95
const WINGTIP_COLOR: Color = Color(0.52, 0.86, 1.0, 0.9)
const WINGTIP_WIDTH: float = 0.18
const WINGTIP_SPEED_FLOOR: float = 0.55
const WINGTIP_LIFETIME: float = 0.65
const WINGTIP_SPACING: float = 0.30

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

var _thruster_plumes_material: StandardMaterial3D
var _thruster_cores_material: StandardMaterial3D
var _thruster_plumes: Array[MeshInstance3D] = []
var _thruster_cores: Array[MeshInstance3D] = []
var _smoke: Array[GPUParticles3D] = []
var _wingtip_trails: Array = []
var _wingtip_material: StandardMaterial3D
var _nozzle_anchors: Array[Vector3] = []
var _thrust_kick: float = 0.0
var _forward_speed: float = 0.0


func _ready() -> void:
	_hp = FIGHTER_HP
	add_to_group(&"enemy")
	_player = _find_player()
	_build_visual()
	if is_instance_valid(_model):
		_build_thrusters()
		_build_smoke()
		_build_wingtip_trails()
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
	_update_thrusters(delta)
	_update_smoke(delta)
	_update_wingtip_trails(delta)


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

func _build_thrusters() -> void:
	_thruster_plumes_material = _make_thruster_material(Color(0.22, 0.6, 1.0, 0.12))
	_thruster_cores_material = _make_thruster_material(Color(0.88, 0.98, 1.0, 0.25))
	if _model == null: return
	_nozzle_anchors = _model.nozzle_anchors()
	for nozzle in _nozzle_anchors.size():
		_add_thruster(nozzle, 0.19, _thruster_plumes_material, _thruster_plumes)
		_add_thruster(nozzle, 0.09, _thruster_cores_material, _thruster_cores)

func _add_thruster(nozzle: int, base_radius: float, material: StandardMaterial3D, into: Array) -> void:
	var flame_mesh: CylinderMesh = CylinderMesh.new()
	flame_mesh.top_radius = 0.0
	flame_mesh.bottom_radius = base_radius
	flame_mesh.height = 1.0
	flame_mesh.radial_segments = 8
	var flame: MeshInstance3D = MeshInstance3D.new()
	flame.mesh = flame_mesh
	flame.material_override = material
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.rotation.z = PI * 0.5
	flame.set_meta("nozzle", nozzle)
	_visual.add_child(flame)
	into.append(flame)

func _make_thruster_material(tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	return material

func _layout_flames(flames: Array[MeshInstance3D], length: float) -> void:
	if _model == null: return
	if _nozzle_anchors.is_empty():
		_nozzle_anchors = _model.nozzle_anchors()
	for flame in flames:
		var nozzle: int = int(flame.get_meta("nozzle", 0))
		var anchor: Vector3 = Vector3.ZERO
		if nozzle < _nozzle_anchors.size():
			anchor = _nozzle_anchors[nozzle]
		flame.scale = Vector3(1.0, length, 1.0)
		flame.position = Vector3(anchor.x - length * 0.5, anchor.y, anchor.z)

func _thrust_flame_colors(thrust: float, kick: float) -> void:
	var heat: float = clampf((maxf(_forward_speed - TOP_SPEED * 0.7, 0.0)) / maxf(TOP_SPEED * 0.3, 0.001), 0.0, 1.0)
	if _thruster_plumes_material != null:
		_thruster_plumes_material.albedo_color = Color(
			lerpf(0.22, 0.5, heat),
			lerpf(0.6, 0.85, heat),
			1.0,
			clampf(0.08 + thrust * 0.24 + kick * 0.30, 0.0, 0.8)
		)
	if _thruster_cores_material != null:
		_thruster_cores_material.albedo_color = Color(
			0.88, 0.98, 1.0, clampf(0.18 + thrust * 0.45 + kick * 0.25, 0.0, 0.95)
		)

func _update_thrusters(delta: float) -> void:
	if _model == null: return
	_forward_speed = maxf(velocity.dot(_heading), 0.0)
	var thrust: float = clampf(_forward_speed / TOP_SPEED, 0.0, 1.0)
	var accel: float = (maxf(velocity.dot(_heading), 0.0) - _forward_speed) / maxf(delta, 0.0001) if delta > 0.0 else 0.0
	_thrust_kick = maxf(_thrust_kick, clampf(accel / ACCELERATION, 0.0, 1.0))
	_thrust_kick = move_toward(_thrust_kick, 0.0, 3.0 * delta)
	var kick: float = _thrust_kick
	_layout_flames(_thruster_plumes, 0.35 + thrust * 1.65 + kick * 1.10)
	_layout_flames(_thruster_cores, 0.28 + thrust * 1.00 + kick * 0.70)
	_thrust_flame_colors(thrust, kick)

func _build_smoke() -> void:
	if _model == null: return
	_nozzle_anchors = _model.nozzle_anchors()
	for nozzle in _nozzle_anchors.size():
		var smoke: GPUParticles3D = GPUParticles3D.new()
		smoke.amount = SMOKE_AMOUNT
		smoke.lifetime = SMOKE_LIFETIME
		smoke.local_coords = false
		smoke.emitting = true
		smoke.fixed_fps = 0
		smoke.amount_ratio = 0.0
		smoke.process_material = _make_smoke_process()
		smoke.draw_pass_1 = _make_smoke_puff()
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke.set_meta("nozzle", nozzle)
		_visual.add_child(smoke)
		_smoke.append(smoke)

func _make_smoke_process() -> ParticleProcessMaterial:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.05
	process.direction = Vector3(-1.0, 0.0, 0.0)
	process.spread = 18.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, 0.4, 0.0)
	process.damping_min = 0.6
	process.damping_max = 1.6
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_min = 0.45
	process.scale_max = 1.15
	process.scale_curve = _make_smoke_curve()
	process.color = SMOKE_COLOR
	process.color_ramp = _make_smoke_ramp()
	return process

func _make_smoke_curve() -> CurveTexture:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.7))
	curve.add_point(Vector2(1.0, 2.6))
	var texture: CurveTexture = CurveTexture.new()
	texture.curve = curve
	return texture

func _make_smoke_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.30))
	gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.18))
	gradient.set_color(2, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture1D = GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	return texture

func _make_smoke_puff() -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SMOKE_PUFF, SMOKE_PUFF)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.add_point(0.45, Color(1.0, 1.0, 1.0, 0.75))
	grad.set_color(2, Color(1.0, 1.0, 1.0, 0.0))
	var grad_texture: GradientTexture2D = GradientTexture2D.new()
	grad_texture.gradient = grad
	grad_texture.fill = GradientTexture2D.FILL_RADIAL
	grad_texture.fill_from = Vector2(0.5, 0.5)
	grad_texture.fill_to = Vector2(1.0, 0.5)
	grad_texture.width = 64
	grad_texture.height = 64
	material.albedo_texture = grad_texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	return quad

func _update_smoke(delta: float) -> void:
	if _model == null: return
	var current_forward: float = maxf(velocity.dot(_heading), 0.0)
	var accel: float = (current_forward - _forward_speed) / maxf(delta, 0.0001) if delta > 0.0 else 0.0
	_forward_speed = current_forward
	var density: float = clampf(accel / ACCELERATION, 0.0, 1.0) * SMOKE_DENSITY_HIGH
	if _nozzle_anchors.is_empty():
		_nozzle_anchors = _model.nozzle_anchors()
	for smoke in _smoke:
		var nozzle: int = int(smoke.get_meta("nozzle", 0))
		if nozzle < _nozzle_anchors.size():
			smoke.position = _nozzle_anchors[nozzle]
		smoke.amount_ratio = density

class WingtipTrail:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	var points: Array[Vector3] = []
	var born: Array[float] = []
	var age: float = 0.0
	var vapour: float = 0.0

func _build_wingtip_trails() -> void:
	_wingtip_material = _make_wingtip_material()
	for _side in 2:
		var trail: WingtipTrail = WingtipTrail.new()
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = trail.mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.top_level = true
		instance.transform = Transform3D.IDENTITY
		add_child(instance)
		_wingtip_trails.append(trail)

func _make_wingtip_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _update_wingtip_trails(delta: float) -> void:
	if _model == null: return
	var vapour: float = _wingtip_vapour()
	var tips: Array[Vector3] = _model.wing_tips()
	for index in _wingtip_trails.size():
		var trail: WingtipTrail = _wingtip_trails[index]
		var has_tip: bool = index < tips.size()
		var tip: Vector3 = _visual.global_transform * tips[index] if has_tip else Vector3.ZERO
		_advance_wingtip_trail(trail, tip, vapour if has_tip else 0.0, delta)

func _wingtip_vapour() -> float:
	if not is_instance_valid(self) or _state == Enemy.State.DEAD:
		return 0.0
	var airspeed: float = velocity.length()
	var floor_speed: float = TOP_SPEED * WINGTIP_SPEED_FLOOR
	return clampf((airspeed - floor_speed) / maxf(TOP_SPEED - floor_speed, 0.001), 0.0, 1.0)

func _advance_wingtip_trail(trail: WingtipTrail, tip: Vector3, vapour: float, delta: float) -> void:
	trail.vapour = vapour
	trail.age += delta
	while not trail.born.is_empty() and trail.age - trail.born[0] > WINGTIP_LIFETIME:
		trail.born.pop_front()
		trail.points.pop_front()
	if vapour > 0.0:
		if trail.points.is_empty():
			trail.points.append(tip)
			trail.born.append(trail.age)
		else:
			var from: Vector3 = trail.points[-1]
			var gap: float = from.distance_to(tip)
			if gap < WINGTIP_SPACING:
				trail.points[-1] = tip
				trail.born[-1] = trail.age
			else:
				var steps: int = clampi(int(ceil(gap / WINGTIP_SPACING)), 1, 8)
				for step in steps:
					trail.points.append(from.lerp(tip, float(step + 1) / float(steps)))
					trail.born.append(trail.age)
	_rebuild_wingtip_ribbon(trail)

func _rebuild_wingtip_ribbon(trail: WingtipTrail) -> void:
	trail.mesh.clear_surfaces()
	var count: int = trail.points.size()
	if count < 2:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	trail.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _wingtip_material)
	for index in count:
		var point: Vector3 = trail.points[index]
		var before: Vector3 = trail.points[max(0, index - 1)]
		var after: Vector3 = trail.points[min(count - 1, index + 1)]
		var along: Vector3 = after - before
		if along.length_squared() < 0.000001:
			along = Vector3.RIGHT
		var side: Vector3 = (along.cross(Vector3.UP)).normalized() * (WINGTIP_WIDTH * 0.5)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT * (WINGTIP_WIDTH * 0.5)
		var fade: float = 1.0 - (trail.age - trail.born[index]) / WINGTIP_LIFETIME
		fade = clampf(fade, 0.0, 1.0)
		var color: Color = WINGTIP_COLOR
		color.a *= fade * fade * trail.vapour
		trail.mesh.surface_set_color(color)
		trail.mesh.surface_add_vertex(point - side)
		trail.mesh.surface_set_color(color)
		trail.mesh.surface_add_vertex(point + side)
	trail.mesh.surface_end()

func _clear_wingtip_trails() -> void:
	for trail: WingtipTrail in _wingtip_trails:
		trail.points.clear()
		trail.born.clear()

func _clear_trails() -> void:\n\t_clear_wingtip_trails()
