class_name PlayerEffects
extends Node3D
## The ship's presentation: thruster plumes, exhaust smoke, wingtip vapour and the
## aim beam.
##
## `player.gd` keeps the flight model, the input and the airframe; this node owns
## what the ship shows while it flies. The plumes, the wake and the ribbons hang
## from the visual root so they turn with the hull, and the beam hangs here at an
## identity transform so its offsets keep the player's own space.
##
## The state only the wake reads lives here: the last forward speed, the burner
## edge and the wing sweep. The numbers only the ship knows arrive with each call:
## the run's speeds through `set_speeds`, the frame's values as arguments, and the
## pose through `pose`, so the hull still owns what the numbers move.

## Where the aim beam starts, past the nose tip, and how long it is.
const BEAM_START: float = 2.60
const BEAM_LENGTH: float = 2.0
const BEAM_COLOR: Color = Color(0.24, 0.9, 0.8, 1.0)

const THRUST_KICK_DECAY: float = 3.0
const FOV_BOOST_KICK: float = 5.0
const FOV_RATE: float = 18.0

## Wing sweep in degrees: nearly straight at rest, a clear contraction at cruise,
## and swept back when the burner is lit. The wing already carries about 27 degrees
## of leading-edge sweep, so the tip ends up near 65 degrees at full burn.
const WING_SWEEP_FORWARD: float = 0.0
const WING_SWEEP_CRUISE: float = 14.0
const WING_SWEEP_BACK: float = 38.0
## Degrees per second the wings travel between those stops. The throttle changes in
## a couple of frames, so the wing needs its own clock to read as a mechanism
## instead of a snap: 0 to full sweep takes a bit over half a second.
const WING_SWEEP_RATE: float = 60.0

## The exhaust wake. The puffs are dropped in world space and left behind, so the
## gap between them -- and therefore the length of the trail -- grows with the
## speed on its own. Only the density needs a knob: `amount_ratio` drops puffs
## without reallocating the buffer or restarting the emission.
##
## The density answers a change in speed, not the speed itself. A steady throttle
## leaves the nozzles clean, and what the wake marks is the ship climbing: a puff
## is born at the nozzle and stays there, so a burst during the climb leaves a
## short smear behind the hull and then nothing. That also keeps a standing ship
## from wearing its own trail -- from the game camera the near leg sat behind the
## plume, and a grey veil over a white leg reads as a shadow the other leg does
## not have.
const SMOKE_COLOR: Color = Color(0.74, 0.79, 0.85, 1.0)
const SMOKE_AMOUNT: int = 450
const SMOKE_LIFETIME: float = 0.50
const SMOKE_PUFF: float = 0.80
const SMOKE_DENSITY_HIGH: float = 0.95

## Wingtip vapour, the speed cue. The cone that used to point the way is gone; a
## pair of trails off the tips says "this is moving" without painting a shape over
## the arena.
##
## The trail is a ribbon, not a particle wake. Puffs can only ever be as dense as
## the rate they spawn at, and at 60 u/s that leaves visible gaps, so the tips read
## as a dotted line. A strip rebuilt through the tip's own history is continuous by
## construction: two vertices per sample, no gaps to tune away.
const WINGTIP_COLOR: Color = Color(0.52, 0.86, 1.0, 0.9)
const WINGTIP_WIDTH: float = 0.18
## Where the FIGHTER vapour starts, as a fraction of cruise. It cannot wait for the
## burner any more: from the middle of the throttle up the tips are already saying
## the ship is moving, and the burner is just the top of that range. FIGHTER is the
## only mode with a trail at all, so this is the only curve there is.
const WINGTIP_SPEED_FLOOR: float = 0.55
## Longer-lived than the exhaust wake on purpose: the two lines have to outlast the
## grey rope the nozzles drop, or they end inside it and there is nothing to see.
const WINGTIP_LIFETIME: float = 0.65
## Distance between samples. Below this the head is just moved instead of a new
## vertex being added, so a slow ship does not pile up points on one spot.
const WINGTIP_SPACING: float = 0.30

## The camera the burner kicks and the base field of view it kicks from.
var camera: Camera3D
## The airframe's pose step: the player applies the blend and the sweep to the hull.
var pose: Callable

var smoke: Array[GPUParticles3D] = []
var wingtip_trails: Array[WingtipTrail] = []


## The plumes, the cores and the beam, for tools that build a still and want the
## motion cues out of the frame.
func thruster_plumes() -> Array[MeshInstance3D]:
	return _thruster_plumes


func thruster_cores() -> Array[MeshInstance3D]:
	return _thruster_cores


func aim_beam() -> MeshInstance3D:
	return _aim_beam


## The run's numbers, scaled by the pilot's level. They are handed over instead of
## read from the record, so a level earned mid-fight stays the next run's number.
var _max_speed: float = 0.0
var _boost_speed: float = 0.0
var _fighter_speed: float = 0.0
var _fighter_boost_speed: float = 0.0
## The ship's own acceleration, used to normalise a frame's speed change into a
## kick and a wake density. Flight owns the number; the effects only scale by it.
var _accel: float = 1.0

var _body: Node3D
var _model: PlayerModel
var _base_fov: float = 0.0

## Nozzle positions for the frame, in `_body` space. They move with the legs, so
## the flames are rebuilt from them every frame instead of a fixed offset.
var _nozzle_anchors: Array[Vector3] = []
var _thruster_plumes_material: StandardMaterial3D
var _thruster_cores_material: StandardMaterial3D
var _thruster_plumes: Array[MeshInstance3D] = []
var _thruster_cores: Array[MeshInstance3D] = []
var _wingtip_material: StandardMaterial3D
var _aim_beam: MeshInstance3D

var _forward_speed: float = 0.0
## Whether the burner is already lit. The ignition is an edge, not a level: the
## sound belongs to crossing into the burner, not to every frame spent in it.
var _burning: bool = false
## Wing angle the pose was last built with. The wings travel to their target at a
## fixed rate instead of following the throttle frame by frame: the fighter reaches
## cruise in a handful of frames, so a derived angle would snap.
var _wing_sweep: float = 0.0


## Builds everything onto `body`, the visual root the ship already owns, and reads
## the airframe's anchors from `model`.
func build(body: Node3D, model: PlayerModel) -> void:
	_body = body
	_model = model
	_base_fov = camera.fov if camera != null else 0.0
	_build_thrusters()
	_build_smoke()
	_build_wingtip_trails()
	_build_aim_beam()


## The player owns the run's numbers and hands them over; the effects never read
## the pilot's record or the ship.
func set_speeds(
	max_speed: float,
	boost_speed: float,
	fighter_speed: float,
	fighter_boost_speed: float,
	accel: float
) -> void:
	_max_speed = max_speed
	_boost_speed = boost_speed
	_fighter_speed = fighter_speed
	_fighter_boost_speed = fighter_boost_speed
	_accel = maxf(accel, 0.001)


## The wake: two nested cones per nozzle, plus the wing sweep. The flame follows
## the forward component of the velocity, not the input: a ship strafing with its
## nose elsewhere is not burning towards its nose, and a flame that grew anyway
## would be a lie. The camera kicks out a little while burning, which reads as
## speed on a featureless surface.
##
## `turbo_ratio` is how deep into the burner band the airspeed sits, 0 at cruise
## and 1 at the burner's ceiling, which is the heat the plumes are tinted by.
##
## Returns the thrust kick after this frame's decay, so the player keeps the dash
## impulse and the wake keeps the clock.
func update_afterburner(
	delta: float,
	thrust_kick: float,
	forward_speed: float,
	boosting: bool,
	turbo_ratio: float,
	fighter: bool
) -> float:
	var thrust: float = clampf(forward_speed / maxf(_boost_speed, 0.001), 0.0, 1.0)
	var heat: float = turbo_ratio
	# The burner announces itself once, on the way in. Hysteresis, because a ship
	# riding the threshold would otherwise stutter the ignition every few frames.
	var burning: bool = heat > 0.08 if not _burning else heat > 0.02
	if burning and not _burning and delta > 0.0:
		Sfx.play(&"afterburner")
	_burning = burning

	# A kick is a flash, not a speed curve: opening the throttle past a walk, or
	# punching the dash, spikes the plumes and then decays in about a third of a
	# second. It is the only cue that the ship has weight at all.
	var accel: float = (forward_speed - _forward_speed) / maxf(delta, 0.0001)
	_forward_speed = forward_speed
	var kick: float = maxf(thrust_kick, clampf(accel / _accel, 0.0, 1.0))
	kick = move_toward(kick, 0.0, THRUST_KICK_DECAY * delta)

	# The wings answer speed, not the mode: they contract as the ship reaches cruise
	# and sweep the rest of the way once it is pushed past it, which is where the
	# burner lives. The thresholds come from the mode being committed to, not from
	# the blend, so a transformation never makes the wings flap back and forth on
	# the way.
	var cruise: float = _fighter_speed if fighter else _max_speed
	var ceiling: float = _fighter_boost_speed if fighter else _boost_speed
	var target_sweep: float
	if forward_speed <= cruise:
		var approach: float = clampf(forward_speed / maxf(cruise, 0.001), 0.0, 1.0)
		# Squared, not linear: a swing wing keeps its span while it is slow and
		# folds only as it closes on cruise. Linear put the wings a third of the
		# way back at a walk, which read as the sweep answering the throttle
		# position rather than the speed.
		target_sweep = lerpf(
			WING_SWEEP_FORWARD, WING_SWEEP_CRUISE, approach * approach
		)
	else:
		var past: float = clampf(
			(forward_speed - cruise) / maxf(ceiling - cruise, 0.001), 0.0, 1.0
		)
		target_sweep = lerpf(WING_SWEEP_CRUISE, WING_SWEEP_BACK, past)
	# The angle is a mechanism, not a readout: the wing travels to the stop at
	# `WING_SWEEP_RATE` and the throttle is free to jump. A zero delta means "pose
	# the current speed", which is what the tools use for a still.
	if delta > 0.0:
		_wing_sweep = move_toward(
			_wing_sweep, target_sweep, WING_SWEEP_RATE * delta
		)
	else:
		_wing_sweep = target_sweep
	# The silhouette is the mode read from above, and the hull owns what the pose
	# moves: FIGHTER dips the nose and folds the wings, GERWALK holds it level.
	if pose.is_valid():
		pose.call(delta, fighter, _wing_sweep)

	# The flames hang off the nozzles, and the nozzles are the feet: the stance
	# swings them forward, so the anchors are read back after the pose.
	_nozzle_anchors = _model.nozzle_anchors() if _model != null else []
	_layout_flames(_thruster_plumes, 0.35 + thrust * 1.65 + kick * 1.10)
	_layout_flames(_thruster_cores, 0.28 + thrust * 1.00 + kick * 0.70)
	update_smoke(accel)

	_thruster_plumes_material.albedo_color = Color(
		lerpf(0.22, 0.5, heat),
		lerpf(0.6, 0.85, heat),
		1.0,
		clampf(0.08 + thrust * 0.24 + kick * 0.30, 0.0, 0.8)
	)
	_thruster_cores_material.albedo_color = Color(
		0.88, 0.98, 1.0, clampf(0.18 + thrust * 0.45 + kick * 0.25, 0.0, 0.95)
	)

	if camera == null:
		return kick
	var target_fov: float = _base_fov + (FOV_BOOST_KICK if boosting else 0.0)
	camera.fov = move_toward(camera.fov, target_fov, FOV_RATE * delta)
	return kick


## Places the beam along the aim. This node sits at an identity transform, so the
## offsets keep the meaning they had in the player's own space.
func aim(direction: Vector3) -> void:
	_aim_beam.position = direction * (BEAM_START + BEAM_LENGTH * 0.5)
	_aim_beam.rotation.y = atan2(direction.x, direction.z)


## The hull is hidden the moment the ship dies, so the beam goes with it.
func hide_beam() -> void:
	_aim_beam.visible = false


## The cone's tip trails behind the nozzle, so growing it must move it back by the
## same amount or the base would detach from the hull.
func _layout_flames(flames: Array[MeshInstance3D], length: float) -> void:
	for flame in flames:
		var nozzle: int = int(flame.get_meta("nozzle", 0))
		var anchor: Vector3 = Vector3.ZERO
		if nozzle < _nozzle_anchors.size():
			anchor = _nozzle_anchors[nozzle]
		flame.scale = Vector3(1.0, length, 1.0)
		flame.position = Vector3(anchor.x - length * 0.5, anchor.y, anchor.z)


## Two additive, unshaded cones per nozzle: a wide plume and a thin core. The
## materials are shared by both nozzles, so one colour update per frame is enough
## and the two sides can never drift apart.
func _build_thrusters() -> void:
	_thruster_plumes_material = _make_thruster_material(Color(0.22, 0.6, 1.0, 0.12))
	_thruster_cores_material = _make_thruster_material(Color(0.88, 0.98, 1.0, 0.25))

	_nozzle_anchors = _model.nozzle_anchors() if _model != null else []
	for nozzle in _nozzle_anchors.size():
		_add_thruster(nozzle, 0.19, _thruster_plumes_material, _thruster_plumes)
		_add_thruster(nozzle, 0.09, _thruster_cores_material, _thruster_cores)

	update_afterburner(0.0, 0.0, 0.0, false, 0.0, false)


func _make_thruster_material(tint: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	return material


## Cone with its tip trailing behind: the mesh axis is local Y, so a quarter turn
## about Z lays it along X, pointing away from the nose. Each flame remembers which
## nozzle it belongs to and is placed from that anchor every frame.
func _add_thruster(
	nozzle: int,
	base_radius: float,
	material: StandardMaterial3D,
	into: Array[MeshInstance3D]
) -> void:
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
	_body.add_child(flame)
	into.append(flame)


## One emitter per nozzle, built once with its worst case. The puffs are not
## carried along with the hull: `local_coords = false` leaves each one where it was
## born, which is what turns a burst into a trail.
func _build_smoke() -> void:
	for nozzle in _nozzle_anchors.size():
		var emitter: GPUParticles3D = GPUParticles3D.new()
		emitter.amount = SMOKE_AMOUNT
		emitter.lifetime = SMOKE_LIFETIME
		emitter.local_coords = false
		emitter.emitting = true
		# At the default 30 Hz the emitter lays the puffs down in batches and the
		# trail reads as a string of beads; the render rate closes the gaps.
		emitter.fixed_fps = 0
		emitter.amount_ratio = 0.0
		emitter.process_material = _make_smoke_process()
		emitter.draw_pass_1 = _make_smoke_puff()
		# The trail is world-space and the sun's shadow map covers the whole arena,
		# so a puff that drifts back over the hull drops a soft blob on it. From the
		# game camera that reads as one leg being in shadow and the other not, which
		# is exactly what a transparent billboard must not do: it is haze, not a
		# solid. Nothing else on the ship casts either (see `_prepare_meshes`).
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.set_meta("nozzle", nozzle)
		_body.add_child(emitter)
		smoke.append(emitter)


## Density follows the climb, not the speed: a steady throttle leaves the nozzles
## clean, and what leaves a trail is the ship gaining speed. The puffs keep their
## own lifetime, so the burst outlives the acceleration by half a second and then
## clears itself. Nothing here has to rescale the emitters, and `amount_ratio`
## changes without restarting the emission.
func update_smoke(accel: float) -> void:
	var density: float = clampf(accel / _accel, 0.0, 1.0) * SMOKE_DENSITY_HIGH
	for emitter in smoke:
		var nozzle: int = int(emitter.get_meta("nozzle", 0))
		if nozzle < _nozzle_anchors.size():
			emitter.position = _nozzle_anchors[nozzle]
		emitter.amount_ratio = density


## One wingtip's ribbon: the tip positions it has visited, oldest first, plus the
## moment each was laid down. The strip is rebuilt from this every frame, so the
## vapour follows the wing exactly -- the sweep moves the tip and the ribbon head
## moves with it, with no frame of lag.
class WingtipTrail:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	## World-space samples, oldest first. The last one is the live tip.
	var points: Array[Vector3] = []
	## The trail's own clock at which each sample was laid down.
	var born: Array[float] = []
	var age: float = 0.0
	## How hard this tip is trailing right now, 0..1. It scales the strip's alpha,
	## so the vapour fades in as the ship picks up speed instead of popping on at
	## a threshold.
	var vapour: float = 0.0


## Two ribbons, one per tip. They are children of the hull but `top_level`, because
## the strip is built in world space from the tip's own history: inheriting the
## ship's yaw would swing the whole contrail around with every turn, and the roll
## animation would whip it around the airframe.
func _build_wingtip_trails() -> void:
	_wingtip_material = _make_wingtip_material()
	for _side in 2:
		var trail: WingtipTrail = WingtipTrail.new()
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = trail.mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.top_level = true
		instance.transform = Transform3D.IDENTITY
		_body.add_child(instance)
		wingtip_trails.append(trail)


func update_wingtips(delta: float, fighter: bool, airspeed: float) -> void:
	if _model == null:
		return
	# GERWALK is a hover, not a wing, and mid-transform the wings are folding. The
	# tips leave no vapour there at all: it is a wingtip effect and there is no
	# wingtip doing anything worth reading.
	if not fighter:
		clear_wingtip_trails()
		return
	var vapour: float = wingtip_vapour(fighter, airspeed)
	var tips: Array[Vector3] = _model.wing_tips()
	for index in wingtip_trails.size():
		var trail: WingtipTrail = wingtip_trails[index]
		var has_tip: bool = index < tips.size()
		var tip: Vector3 = _body.global_transform * tips[index] if has_tip else Vector3.ZERO
		advance_wingtip_trail(trail, tip, vapour if has_tip else 0.0, delta)


## How hard the tips are trailing, 0..1. FIGHTER only: GERWALK has no wingtip
## vapour at all, and the caller clears the strips there.
##
## It answers airspeed, not the burner: the vapour is the cue that the ship is
## moving, so it starts at the middle of the throttle and reaches full strength at
## cruise. The burner is simply the top of that range, which is also where the
## burst rule applies.
##
## It is the speed through the air, not the component along the nose. In a turn the
## nose outruns the course -- that lag is the skid -- so the forward component
## collapses while the wing is still moving through the air at cruise, and the tips
## went quiet exactly when the airframe was loaded. The jink is subtracted for the
## same reason the flight model subtracts it: it is a step the hull takes, not air
## it flies through.
func wingtip_vapour(fighter: bool, airspeed: float) -> float:
	if not fighter:
		return 0.0
	var floor_speed: float = _fighter_speed * WINGTIP_SPEED_FLOOR
	return clampf(
		(airspeed - floor_speed) / maxf(_fighter_speed - floor_speed, 0.001), 0.0, 1.0
	)


## Lays down one frame of vapour and redraws the strip. While the tips are trailing
## the head tracks the tip; when the ship slows the head stays where it was and the
## tail is retired by age, so the line dissolves from its far end instead of
## vanishing.
func advance_wingtip_trail(
	trail: WingtipTrail, tip: Vector3, vapour: float, delta: float
) -> void:
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
				# Barely moved: move the head instead of stacking a vertex on it.
				trail.points[-1] = tip
				trail.born[-1] = trail.age
			else:
				# A frame at 60 u/s is a whole unit, so one vertex per frame would
				# show a turn as a corner. Split the step into even pieces.
				var steps: int = clampi(int(ceil(gap / WINGTIP_SPACING)), 1, 8)
				for step in steps:
					trail.points.append(from.lerp(tip, float(step + 1) / float(steps)))
					trail.born.append(trail.age)

	_rebuild_wingtip_ribbon(trail)


## Rebuilds the strip as a camera-facing band: each sample is split sideways along
## the sample's own direction, so the ribbon keeps its width however the ship turns.
## The head is bright and the tail fades to nothing, which is what reads as a
## contrail rather than as a drawn line.
func _rebuild_wingtip_ribbon(trail: WingtipTrail) -> void:
	trail.mesh.clear_surfaces()
	var count: int = trail.points.size()
	if count < 2:
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	trail.mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _wingtip_material)
	for index in count:
		var point: Vector3 = trail.points[index]
		var before: Vector3 = trail.points[maxi(index - 1, 0)]
		var after: Vector3 = trail.points[mini(index + 1, count - 1)]
		var along: Vector3 = after - before
		if along.length_squared() < 0.000001:
			along = Vector3.RIGHT
		along = along.normalized()

		var view: Vector3 = Vector3.UP
		if camera != null:
			view = camera.global_position - point
		if view.length_squared() < 0.000001:
			view = Vector3.UP
		var side: Vector3 = along.cross(view)
		if side.length_squared() < 0.000001:
			side = along.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = along.cross(Vector3.RIGHT)
		side = side.normalized() * (WINGTIP_WIDTH * 0.5)

		var fade: float = float(index) / float(count - 1)
		var color: Color = Color(
			WINGTIP_COLOR.r,
			WINGTIP_COLOR.g,
			WINGTIP_COLOR.b,
			WINGTIP_COLOR.a * fade * fade * trail.vapour
		)
		trail.mesh.surface_set_color(color)
		trail.mesh.surface_add_vertex(point - side)
		trail.mesh.surface_set_color(color)
		trail.mesh.surface_add_vertex(point + side)
	trail.mesh.surface_end()


## The hull is hidden the moment the ship dies and `_physics_process` stops with
## it, so without this the last strip would stay painted in the arena forever. It
## also runs every frame outside FIGHTER, so an already-clean strip is skipped.
func clear_wingtip_trails() -> void:
	for trail: WingtipTrail in wingtip_trails:
		if trail.points.is_empty() and trail.born.is_empty():
			continue
		trail.points.clear()
		trail.born.clear()
		trail.mesh.clear_surfaces()


## Additive, unlike the exhaust wake: the tips have sky behind them, and a bright
## line against a dark arena is what makes the speed readable from the game camera.
func _make_wingtip_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_smoke_process() -> ParticleProcessMaterial:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.05
	# Local -X is aft: the emitter turns with the ship, the puff does not.
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


## Puffs grow as they age and fade out instead of vanishing, which is what keeps a
## short trail from reading as a dotted line.
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


## A radial fade generated in code, so a puff is a soft disc instead of a square
## and the repository does not have to carry art for one effect.
func _make_smoke_puff() -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SMOKE_PUFF, SMOKE_PUFF)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _make_smoke_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	return quad


func _make_smoke_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.75))
	gradient.set_color(2, Color(1.0, 1.0, 1.0, 0.0))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func _build_aim_beam() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.45)

	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(0.08, 0.08, 1.0)

	_aim_beam = MeshInstance3D.new()
	_aim_beam.mesh = beam_mesh
	_aim_beam.material_override = material
	_aim_beam.scale.z = BEAM_LENGTH
	_aim_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_beam)
