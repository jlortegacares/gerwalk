class_name MovementSuite
extends SmokeSuite
## The ship: flight models, transformation, dash and i-frames, the
## afterburner, the planet's roll under it, and death.

func _test_player_is_centered() -> void:
	var camera: Camera3D = _player.camera
	_check(camera != null, "player owns a Camera3D")
	if camera == null:
		return

	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = camera.unproject_position(_player.global_position)
	var offset: float = projected.distance_to(centre)
	_check(offset < 1.0, "player projects to the screen centre (off by %.2f px)" % offset)


func _test_movement() -> void:
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_right")
	for _i in 30:
		await get_tree().physics_frame
	Input.action_release(&"move_right")

	var travelled: float = _player.global_position.x - start.x
	_check(travelled > 5.0, "player moves right on the play plane (%.1f units)" % travelled)
	_check(
		absf(_player.global_position.z - start.z) < 0.1,
		"movement keeps the player on its plane"
	)


## The maneuverability contract: cruise inside 0.08 s, a full stop inside 0.06 s,
## tap mode on a light tilt, a 3x dash that drops the old inertia, a model that
## banks and catches up without ever lagging the shot, and a camera that springs
## the ship back to centre once it stops.
func _test_maneuverability() -> void:
	_release_all_input()
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	var accel_frames: int = 0
	Input.action_press(&"move_right")
	while accel_frames < 15 and _flat_speed() < Player.MAX_SPEED * 0.98:
		await get_tree().physics_frame
		accel_frames += 1
	_check(
		accel_frames <= 4,
		"cruise arrives in %d frames (%.3f s)" % [accel_frames, accel_frames / 60.0]
	)

	var stop_frames: int = 0
	Input.action_release(&"move_right")
	while stop_frames < 15 and _flat_speed() > 0.01:
		await get_tree().physics_frame
		stop_frames += 1
	_check(
		stop_frames <= 3,
		"a full stop from cruise takes %d frames (%.3f s)"
		% [stop_frames, stop_frames / 60.0]
	)

	# Tap mode: a 20 percent tilt has to move the ship without giving it real
	# cruise speed, or threading a narrow gap becomes all or nothing.
	Input.action_press(&"move_right", 0.2)
	for _i in 20:
		await get_tree().physics_frame
	var tap_speed: float = _flat_speed()
	Input.action_release(&"move_right")
	_check(
		tap_speed > 0.5 and tap_speed < Player.MAX_SPEED * 0.25,
		"a light tilt moves the ship at tap speed (%.1f u/s)" % tap_speed
	)
	_player.velocity = Vector3.ZERO

	# Dash: the double tap is still the jink -- 3x cruise from the first frame, and
	# it must wipe the inertia it had.
	Input.action_press(&"move_left")
	for _i in 20:
		await get_tree().physics_frame
	var before_dash: float = _player.velocity.x
	Input.action_release(&"move_left")

	Input.action_press(&"move_right")
	# Input injected from a coroutine lands after the physics step, so the
	# just_pressed latch never reaches _physics_process; call the handler the
	# frame would.
	_player.call("_start_dash", Vector2.RIGHT)
	await get_tree().physics_frame
	var dash_speed: float = _flat_speed()
	var dash_x: float = _player.velocity.x
	_check(
		dash_speed >= Player.MAX_SPEED * 3.0,
		"the tapped dash injects %.2fx cruise on frame one" % (dash_speed / Player.MAX_SPEED)
	)
	_check(
		dash_x > 0.0 and before_dash < -Player.MAX_SPEED * 0.5,
		"the tapped dash cancels the inherited inertia (%.1f -> %.1f u/s)" % [before_dash, dash_x]
	)
	var tap_spin: float = float(_player.get("_roll_anim_time"))
	_check(tap_spin > 0.0, "the tapped dash also comes over (%.2f s)" % tap_spin)
	Input.action_release(&"move_right")

	# Space is the spin on its own: a key pressed to "come over" must not also shove
	# the ship somewhere, and the roll is what carries the i-frames. The side is the
	# aim axis, the same control the fighter's button reads.
	_player.velocity = Vector3.ZERO
	_player.set("_roll_anim_time", 0.0)
	_player.set("_dash_cooldown", 0.0)
	Input.action_press(&"aim_right")
	_player.call("_start_dash")
	await get_tree().physics_frame
	var spin_speed: float = _flat_speed()
	var gerwalk_spin: float = float(_player.get("_roll_anim_time"))
	var gerwalk_side: float = float(_player.get("_roll_side"))
	var gerwalk_roll: float = (_player.get("_visual") as Node3D).rotation.x
	_check(
		spin_speed < Player.MAX_SPEED * 0.25 and gerwalk_spin > 0.0,
		"a GERWALK button roll spins without dashing (%.1f u/s, %.2f s)"
		% [spin_speed, gerwalk_spin]
	)
	_check(
		gerwalk_side > 0.0 and gerwalk_roll > 0.0,
		"the GERWALK button roll comes over on the side the aim asked (side %+.0f, %.0f deg)"
		% [gerwalk_side, rad_to_deg(gerwalk_roll)]
	)
	_check(_player.is_evading(), "the GERWALK button roll still carries its i-frames")
	Input.action_release(&"aim_right")
	_player.set("_roll_anim_time", 0.0)

	# Aim is instant while the model eases in at 1800 deg/s: the shot never waits
	# for the animation, and the animation still finishes a 180 in about 0.1 s.
	Input.action_press(&"aim_left")
	for _i in 30:
		await get_tree().physics_frame
	Input.action_release(&"aim_left")
	Input.action_press(&"aim_right")
	await get_tree().physics_frame
	var shot_axis: float = _player.get("_aim_direction").x
	var catching_up: float = absf(rad_to_deg(_player.get("_visual").rotation.y))
	for _i in 8:
		await get_tree().physics_frame
	var settled_yaw: float = absf(rad_to_deg(_player.get("_visual").rotation.y))
	_check(shot_axis > 0.99, "the shot direction flips on the first frame (x %.2f)" % shot_axis)
	_check(
		catching_up > 60.0,
		"the model is still swinging one frame after the flick (%.0f deg to go)" % catching_up
	)
	_check(settled_yaw < 2.0, "the model completes the 180 in under 0.15 s (%.1f deg off)" % settled_yaw)
	Input.action_release(&"aim_right")

	# Banking: drift sideways across the nose and the hull leans; stop and it
	# levels out again.
	Input.action_press(&"aim_right")
	for _i in 10:
		await get_tree().physics_frame
	Input.action_press(&"move_up")
	for _i in 20:
		await get_tree().physics_frame
	var bank: float = rad_to_deg(_player.get("_visual").rotation.x)
	Input.action_release(&"move_up")
	Input.action_release(&"aim_right")
	for _i in 40:
		await get_tree().physics_frame
	var level: float = absf(rad_to_deg(_player.get("_visual").rotation.x))
	_check(absf(bank) >= 15.0 and absf(bank) <= 40.0, "strafing banks the hull (%.1f deg)" % bank)
	_check(level < 3.0, "the hull levels out when the drift stops (%.1f deg)" % level)

	# The camera spring settles the ship back to dead centre once it is still.
	_release_all_input()
	_player.velocity = Vector3.ZERO
	for _i in 30:
		await get_tree().physics_frame
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = _player.camera.unproject_position(_player.global_position)
	_check(
		projected.distance_to(centre) < 1.0,
		"the camera settles the ship back to centre at rest (%.2f px)"
		% projected.distance_to(centre)
	)


## The dash gesture: a double tap on the movement stick dashes the way it was
## tapped, one tap and two taps in different directions spend nothing, and in
## FIGHTER the jink follows the tap on both axes, diagonals included. The Space /
## L3 button stays as the alternative.
func _test_double_tap_dash() -> void:
	await _reset_dash_gesture()
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	Input.action_release(&"move_right")
	await get_tree().physics_frame
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	var tap_speed: float = _flat_speed()
	_check(
		float(_player.get("_dash_time")) > 0.0
		and tap_speed >= Player.MAX_SPEED * 3.0
		and _player.velocity.x > 0.0,
		"a double tap dashes the way it was tapped (%.1f u/s)" % tap_speed
	)
	Input.action_release(&"move_right")

	# One tap is a nudge, not a dash: the second tap is the whole gesture.
	await _reset_dash_gesture()
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	await get_tree().physics_frame
	_check(
		float(_player.get("_dash_time")) <= 0.0,
		"one tap moves the ship without spending the dash"
	)

	# Two taps that disagree are a direction change, not a dash. Left then up is
	# 90 degrees apart, well outside the cone.
	await _reset_dash_gesture()
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	Input.action_release(&"move_left")
	await get_tree().physics_frame
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	_check(
		float(_player.get("_dash_time")) <= 0.0,
		"two taps in different directions do not dash"
	)
	Input.action_release(&"move_up")

	# FIGHTER: the lateral double tap rolls to the tapped side. With the nose
	# up-screen, screen-left is the airframe's own left.
	await _reset_dash_gesture()
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the double-tap check starts in FIGHTER")
	await _reset_dash_gesture()
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	Input.action_release(&"move_left")
	await get_tree().physics_frame
	# The first tap is a heading request too, so the nose is reset between taps:
	# the jink is measured against the heading it was actually asked from.
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	var roll_side: float = float(_player.get("_roll_side"))
	_check(
		float(_player.get("_dash_time")) > 0.0 and roll_side < 0.0,
		"a lateral double tap rolls to the side that was tapped (%.0f)" % roll_side
	)
	Input.action_release(&"move_left")

	# In FIGHTER any direction is a jink, diagonals included. The stick is read in
	# the same world axes the flight model uses, so with the nose up-screen a tap
	# up is forward, down is backward, and up-right is the diagonal between them.
	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	for _i in 4:
		await get_tree().physics_frame
	var forward_push: Vector2 = _jink_push()
	_check(
		forward_push.x > 20.0 and absf(forward_push.y) < 2.0,
		"a double tap forward jinks along the nose (%.1f u/s)" % forward_push.x
	)
	Input.action_release(&"move_up")

	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_down")
	await get_tree().physics_frame
	Input.action_release(&"move_down")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_down")
	for _i in 4:
		await get_tree().physics_frame
	var back_push: Vector2 = _jink_push()
	_check(
		back_push.x < -20.0 and absf(back_push.y) < 2.0,
		"a double tap backward jinks against the nose (%.1f u/s)" % back_push.x
	)
	Input.action_release(&"move_down")

	await _reset_dash_gesture()
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	Input.action_release(&"move_up")
	Input.action_release(&"move_right")
	await get_tree().physics_frame
	_player.set("_heading", Vector3.FORWARD)
	Input.action_press(&"move_up")
	Input.action_press(&"move_right")
	for _i in 4:
		await get_tree().physics_frame
	var diagonal_push: Vector2 = _jink_push()
	_check(
		diagonal_push.x > 15.0 and diagonal_push.y > 15.0,
		"a diagonal double tap jinks on both axes (%.1f forward, %.1f right)"
		% [diagonal_push.x, diagonal_push.y]
	)
	Input.action_release(&"move_up")
	Input.action_release(&"move_right")

	# Leave the ship in GERWALK: the rest of the suite starts from the hover.
	await _reset_dash_gesture()
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(not _player.is_fighter(), "the double-tap check restores GERWALK")


## The transformation contract: two real modes, a switch that costs commitment,
## a fighter that flies at 180% on a stall-speed floor, a course that lags the
## nose into a skid, the same speed in every heading, a gun welded to the airframe,
## and a burner that shreds what it flies through.
func _test_transformation() -> void:
	_release_all_input()
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(not _player.is_fighter(), "the ship starts in GERWALK")

	# S1: the switch is a 0.28 s commitment, not an instant toggle.
	_player.call("_start_transform")
	await get_tree().physics_frame
	_check(not _player.is_fighter(), "the switch does not land in one frame")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the ship reaches FIGHTER after 0.28 s")

	# S3: 180% of the hover cruise, measured in airspeed, and the same whichever
	# way the ship is pointed.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 20.0
	Input.action_press(&"move_right")
	for _i in 20:
		await get_tree().physics_frame
	var fighter_speed: float = _player.velocity.length()
	_check(
		absf(fighter_speed / Player.MAX_SPEED - 1.8) < 0.05,
		"fighter cruise is %.0f%% of the hover's (%.1f u/s airspeed)"
		% [100.0 * fighter_speed / Player.MAX_SPEED, fighter_speed]
	)

	# FR-15 still holds at fighter speed: the camera lead saturates instead of
	# scaling with 180% of the hover cruise.
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var projected: Vector2 = _player.camera.unproject_position(_player.global_position)
	_check(
		projected.distance_to(centre) < 16.0,
		"the camera keeps the fighter framed at 1.8x (%.1f px)" % projected.distance_to(centre)
	)

	# S4: the gun is bolted to the airframe. The right stick, which would aim in
	# GERWALK, must not move the shot off the nose.
	Input.action_press(&"aim_up")
	for _i in 2:
		await get_tree().physics_frame
	var nose: Vector3 = _player.get("_aim_direction")
	_check(nose.x > 0.99, "the gun stays on the nose in FIGHTER (x %.2f)" % nose.x)
	Input.action_release(&"aim_up")

	# S3: a reversal is an arc. One frame cannot turn 180 degrees, and the full
	# turn lands inside the 360-450 deg/s band.
	var before_turn: Vector3 = _player.get("_heading")
	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	await get_tree().physics_frame
	var after_one: Vector3 = _player.get("_heading")
	_check(
		after_one.dot(before_turn) > 0.9,
		"one frame cannot reverse the heading (%.0f deg)"
		% rad_to_deg(after_one.angle_to(before_turn))
	)
	var yaw_before: float = atan2(-before_turn.z, before_turn.x)
	var peak_bank: float = 0.0
	var peak_lean: float = 0.0
	for _i in 30:
		await get_tree().physics_frame
		var roll: float = _player.get("_visual").rotation.x
		if absf(roll) > absf(peak_bank):
			peak_bank = roll
			var heading: Vector3 = _player.get("_heading")
			var right: Vector3 = Vector3(-heading.z, 0.0, heading.x)
			peak_lean = _player.get("_visual").global_transform.basis.y.dot(right)
	var reversed: Vector3 = _player.get("_heading")
	var turned: float = angle_difference(yaw_before, atan2(-reversed.z, reversed.x))
	_check(reversed.dot(before_turn) < -0.9, "the heading completes a 180 in about 0.45 s")
	Input.action_release(&"move_left")

	# The hull banks into the turn like a wing. A car yaws flat; a fighter drops
	# the wing on the inside of the turn and raises it when the stick centres, so
	# the airframe's own up vector leans the way the nose is going.
	_check(
		rad_to_deg(absf(peak_bank)) >= 35.0,
		"a fighter banks into the turn (%.1f deg)" % rad_to_deg(peak_bank)
	)
	_check(
		signf(peak_lean) == -signf(turned),
		"the wing drops on the inside of the turn (%.1f deg roll, %.0f deg turn)"
		% [rad_to_deg(peak_bank), rad_to_deg(turned)]
	)
	for _i in 40:
		await get_tree().physics_frame
	var levelled: float = absf(rad_to_deg(_player.get("_visual").rotation.x))
	_check(levelled < 4.0, "the fighter levels out when the turn ends (%.1f deg)" % levelled)

	# S4: fighter rounds leave faster, live 40% longer and keep a tight fan.
	var weapons: WeaponSystem = _player.get_node("Weapons")
	weapons.select(Arsenal.Kind.VULCAN)
	weapons.primary().set_cooldown(0.0)
	_clear_projectiles()
	weapons.tick(0.016, _player.global_position, _player.global_position, reversed, true, true)
	var shots: Array[Projectile] = _player_projectiles()
	_check(shots.size() >= Arsenal.VULCAN_PELLETS, "the fighter vulcan still fans out")
	if shots.size() >= 2:
		var widest: float = 0.0
		for i in shots.size():
			for j in range(i + 1, shots.size()):
				var first: Vector3 = shots[i].get("_velocity")
				var second: Vector3 = shots[j].get("_velocity")
				widest = maxf(widest, rad_to_deg(first.angle_to(second)))
		var speed: float = shots[0].get("_velocity").length()
		var life: float = shots[0].get("_life")
		_check(
			absf(speed - Arsenal.VULCAN_SPEED * Arsenal.FIGHTER_SPEED_MULTIPLIER) < 1.0,
			"fighter rounds leave at %.0f u/s (1.35x)" % speed
		)
		_check(
			life > Arsenal.FIGHTER_RANGE_MULTIPLIER * Projectile.LIFETIME - 0.1,
			"fighter rounds carry 40%% more range (%.1f s of flight)" % life
		)
		_check(widest < 12.0, "the fighter fan closes to %.1f deg" % widest)

	# S4: and plasma loses the lock that makes it plasma in the hover.
	_clear_projectiles()
	var target: Enemy = _spawn_enemy(_player.global_position + reversed * 10.0)
	# The automatic battery would launch at that same target inside this tick and
	# look like a second plasma bolt, so park it while the count is measured.
	weapons.radar().set_cooldown(99.0)
	weapons.select(Arsenal.Kind.PLASMA)
	weapons.primary().set_cooldown(0.0)
	weapons.tick(0.016, _player.global_position, _player.global_position, reversed, true, true)
	var bolts: Array[Projectile] = _player_projectiles()
	_check(bolts.size() == 1, "the fighter plasma still fires")
	if bolts.size() == 1:
		_check(bolts[0].get("_target") == null, "fighter plasma has no lock-on")
	weapons.radar().set_cooldown(0.0)
	_clear_projectiles()
	if target != null:
		target.queue_free()
	await get_tree().physics_frame

	# S5: the button is the spin on its own. Space must not step the ship -- a
	# dodge that teleports sideways under a key the player pressed to "come over"
	# is a movement they never asked for -- and the double tap is still the jink.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 30.0
	Input.action_press(&"aim_left")
	for _i in 2:
		await get_tree().physics_frame
	var heading_before: Vector3 = _player.get("_heading")
	var position_before: Vector3 = _player.global_position
	_player.call("_start_dash")
	for _i in 12:
		await get_tree().physics_frame
	var travelled: Vector3 = _player.global_position - position_before
	var lateral: float = travelled.dot(Vector3(-heading_before.z, 0.0, heading_before.x))
	var heading_after: Vector3 = _player.get("_heading")
	_check(
		absf(lateral) < 1.0,
		"the button roll spins without stepping the ship (%.1f units)" % lateral
	)
	_check(heading_after.dot(heading_before) > 0.99, "the roll leaves the nose where it was")
	_check(
		float(_player.get("_dash_time")) <= 0.0,
		"the button roll opens no jink window"
	)
	_check(_player.is_evading(), "the button roll still carries its i-frames")

	# The roll animation runs on its own, slower clock: it is still coming over,
	# and it is coming over to the side the aim picked.
	var spin: float = _player.get("_visual").rotation.x
	_check(
		spin < -1.0,
		"the roll is still turning when the spinner is done (%.0f deg)" % rad_to_deg(spin)
	)
	_check(
		float(_player.get("_roll_side")) < 0.0,
		"the roll remembers the side it went to"
	)

	# A tapped roll is still the jink: it steps to the side the tap asked for. The
	# tap is given in world axes, so with the nose on +X a stick pushed up-screen is
	# a step to the hull's own left. This is the entry the double-tap gesture calls.
	Input.action_release(&"aim_left")
	_player.set("_dash_cooldown", 0.0)
	_player.set("_roll_anim_time", 0.0)
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 30.0
	position_before = _player.global_position
	_player.call("_start_barrel_roll", Vector2.UP)
	_check(
		float(_player.get("_dash_time")) > 0.0,
		"a tapped roll opens the jink window"
	)
	for _i in 12:
		await get_tree().physics_frame
	travelled = _player.global_position - position_before
	lateral = travelled.dot(Vector3(-heading_before.z, 0.0, heading_before.x))
	_check(
		lateral < -2.0,
		"a tapped roll still steps left (%.1f units)" % lateral
	)

	# A centred stick repeats that side instead of defaulting to the right.
	_player.set("_dash_cooldown", 0.0)
	_player.set("_roll_anim_time", 0.0)
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * 30.0
	_player.call("_start_dash")
	_check(
		float(_player.get("_roll_side")) < 0.0,
		"a neutral stick repeats the last side"
	)
	# And the slower spin lands back on the bank axis instead of parking a turn.
	for _i in 32:
		await get_tree().physics_frame
	var settle: float = _player.get("_visual").rotation.x
	_check(
		absf(settle) < 0.1,
		"the roll settles level when it ends (%.1f deg)" % rad_to_deg(settle)
	)

	# S6 was withdrawn: the burner no longer clears the sky in front of the nose.
	# The cone outlived its own mesh for a while, deleting projectiles nobody could
	# see a reason for, so this pins the absence instead of the rule.
	_player.set("_heading", Vector3.RIGHT)
	var front: Projectile = _spawn_enemy_bullet(_player.global_position + Vector3.RIGHT * 4.0)
	_player.set("_boosting", true)
	for _i in 2:
		await get_tree().physics_frame
	_check(
		front != null and is_instance_valid(front) and not front.is_queued_for_deletion(),
		"the burner no longer shreds enemy fire in front of the nose"
	)
	_player.set("_boosting", false)
	_clear_projectiles()
	await get_tree().physics_frame

	# S3: the fighter bleeds from cruise down to its stall speed in the old 0.35 s
	# and then keeps flying: drag, not a brake. The velocity is set to cruise along
	# the nose, so the airspeed starts at the spec number.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * Player.FIGHTER_SPEED
	var glide_speed: float = Player.FIGHTER_STALL_SPEED
	var stall_frames: int = 0
	while stall_frames < 40 and _flat_speed() > glide_speed + 0.6:
		await get_tree().physics_frame
		stall_frames += 1
	_check(
		absf(stall_frames / 60.0 - Player.FIGHTER_STOP_TIME) < 0.05,
		"fighter bleeds to stall speed in %.2f s" % (stall_frames / 60.0)
	)
	for _i in 6:
		await get_tree().physics_frame
	_check(
		absf(_flat_speed() - glide_speed) < 1.0,
		"the fighter glides at the stall floor (%.1f u/s)" % _flat_speed()
	)

	# S3: a coast still covers ground. If the floor regresses to zero, the ship
	# parks on the planet and the planet stops rolling.
	var glide_from: Vector3 = _player.global_position
	for _i in 30:
		await get_tree().physics_frame
	var glided: float = _flat_distance(_player.global_position, glide_from)
	_check(glided > 8.0, "coasting still covers ground (%.1f units in 0.5 s)" % glided)

	# S3: the nose turns faster than the air does. Asking for a reversal, the ship
	# keeps travelling the old way while the nose already points the new one.
	_player.set("_heading", Vector3.RIGHT)
	_player.velocity = Vector3.RIGHT * Player.FIGHTER_SPEED
	Input.action_press(&"move_left")
	for _i in 12:
		await get_tree().physics_frame
	var skid: float = _sideways_airspeed()
	_check(absf(skid) > 20.0, "a reversal skids across the nose (%.1f u/s)" % skid)
	Input.action_release(&"move_left")
	for _i in 60:
		await get_tree().physics_frame
	skid = _sideways_airspeed()
	_check(
		absf(skid) < 3.0,
		"the skid bleeds out once the nose settles (%.1f u/s)" % skid
	)

	# S3: every heading flies the same speed. A world-space wind used to make the
	# same run 15% faster downwind than upwind, and the wing sweep read that as
	# wings swept on one side of the screen only. The window is cleared of combat:
	# enemies draw from the global RNG and a hit pushes the ship 11 u/s, which
	# moved the measurement by more than the tolerance.
	_clear_enemies()
	_clear_projectiles()
	_player.set("_invulnerable", 1000.0)
	await get_tree().physics_frame
	var coast: Array[float] = []
	for heading in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		_player.set("_heading", heading)
		_player.velocity = Vector3.ZERO
		for _i in 60:
			await get_tree().physics_frame
		coast.append(_flat_speed())
	_player.set("_invulnerable", 0.0)
	_check(
		absf(coast[0] - Player.FIGHTER_STALL_SPEED) < 1.0,
		"the glide holds the stall floor (%.1f u/s)" % coast[0]
	)
	var spread: float = coast.max() - coast.min()
	_check(
		spread < 0.5,
		"the glide is the same in every heading (spread %.2f u/s)" % spread
	)

	# S1: back to the hover, and the gun is free the moment it lands.
	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(not _player.is_fighter(), "the ship returns to GERWALK")

	# S3: the hover holds station. A push that the fighter would ride is killed by
	# the hover's friction, which is its whole reason to exist next to the fighter.
	_player.velocity = Vector3(21.0, 0.0, 0.0)
	for _i in 20:
		await get_tree().physics_frame
	_check(
		_flat_speed() < 0.2,
		"the hover holds station after a push (%.2f u/s)" % _flat_speed()
	)

	Input.action_press(&"aim_up")
	for _i in 3:
		await get_tree().physics_frame
	_check(
		_player.get("_aim_direction").z < -0.9,
		"the gun aims freely again in GERWALK"
	)
	Input.action_release(&"aim_up")
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame


## The GERWALK silhouette is a skeleton pose, not a second mesh: the nacelles swing
## down and outboard with the nozzles ahead of the wing root, where the near-overhead
## camera can see them, the gunpod rides in the right hand, and FIGHTER folds both
## back into the airframe without dropping anything through the planet.
func _test_gerwalk_silhouette() -> void:
	var model: PlayerModel = _player.get("_model") as PlayerModel
	var pod: Node3D = _player.get("_gunpod")
	var hull: Node3D = _player.get("_visual")
	_check(model != null, "the airframe is the imported model")
	if model == null or pod == null or hull == null:
		return

	var feet: Array[Vector3] = model.nozzle_anchors()
	_check(feet.size() == 2, "the airframe carries two legs")
	if feet.size() < 2:
		return
	_check(
		absf(feet[0].z + feet[1].z) < 0.05,
		"the legs splay symmetrically (z %.2f / %.2f)" % [feet[0].z, feet[1].z]
	)
	_check(absf(feet[0].z) > 0.45, "the legs stand wide (z %.2f)" % absf(feet[0].z))
	_check(feet[0].y < -0.2, "the legs hang below the hull (y %.2f)" % feet[0].y)
	_check(feet[0].x > -0.5, "the feet leave the tail fold (x %.2f)" % feet[0].x)
	var sole: float = hull.to_global(feet[0]).y - 0.15
	_check(
		sole > Arena.GROUND_Y + 0.2,
		"the soles stay clear of the ground (%.2f vs %.2f)" % [sole, Arena.GROUND_Y]
	)

	# The gunner hold brings the right arm out, so the pod has to be in the hand
	# and the hand in front of the wing root, not trailing the tail.
	var hand: Vector3 = model.to_global(model.hand_anchor())
	_check(
		pod.global_position.distance_to(hand) < 0.05,
		"the gunpod is in the right hand in GERWALK"
	)
	var held: Vector3 = hull.to_local(pod.global_position)
	_check(held.x > 0.3, "the gunpod reaches ahead of the wing root (x %.2f)" % held.x)
	_check(held.z > 0.1, "the gunpod rides the right side (z %.2f)" % held.z)

	# GERWALK is a hover, not a wing: it flies sideways and backwards as happily as
	# forwards, so a tip trail there would say nothing about anything. There is no
	# wingtip vapour in that mode at all, at any throttle. The measurement is driven
	# directly so the check does not depend on the flight model's timing.
	var frame: float = 1.0 / 60.0
	_player.velocity = Vector3.RIGHT * Player.MAX_SPEED
	_check(
		is_zero_approx(float(_player.call("_wingtip_vapour"))),
		"GERWALK leaves the tips clean at cruise"
	)
	_player.velocity = Vector3.RIGHT * (Player.MAX_SPEED + Player.ACCELERATION * frame)
	_check(
		is_zero_approx(float(_player.call("_wingtip_vapour"))),
		"GERWALK leaves the tips clean while it gains speed"
	)
	# The strips are wiped, not merely faded: a trail laid down in FIGHTER would
	# otherwise hang in the air for its whole lifetime after the switch.
	var gerwalk_trails: Array = _player.effects().wingtip_trails
	for trail in gerwalk_trails:
		(trail.get("points") as Array).append(Vector3.ONE)
		(trail.get("born") as Array).append(0.0)
	_player.call("_update_wingtip_trails", frame)
	var wiped: bool = true
	for trail in gerwalk_trails:
		wiped = wiped and (trail.get("points") as Array).is_empty()
	_check(wiped, "the strips are wiped outside FIGHTER")
	_player.velocity = Vector3.ZERO

	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	_check(_player.is_fighter(), "the silhouette test reaches FIGHTER")
	_check(
		float(_player.get("_mode_blend")) > 0.99,
		"the pose arrives with the rules (blend %.2f)" % float(_player.get("_mode_blend"))
	)
	var tucked: Vector3 = model.nozzle_anchors()[0]
	_check(tucked.x < -1.0, "FIGHTER folds the legs back along the fuselage (x %.2f)" % tucked.x)
	_check(tucked.y > -0.4, "FIGHTER lifts the feet into the tail (y %.2f)" % tucked.y)
	var stowed: Vector3 = hull.to_local(pod.global_position)
	_check(absf(stowed.z) < 0.15, "FIGHTER stows the gunpod on the centreline (z %.2f)" % stowed.z)
	_check(stowed.y < -0.2, "the stowed gunpod rides under the belly (y %.2f)" % stowed.y)

	# The wings answer speed, not the mode: nearly straight at the glide floor, a
	# clear contraction at cruise, and the rest of the sweep once the ship is
	# pushed past it. Driving the visual directly keeps the check out of the flight
	# model's hands, and a zero delta poses the current speed instead of animating.
	var aim: Vector3 = _player.get("_aim_direction")
	_player.velocity = aim * Player.FIGHTER_STALL_SPEED
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees < 4.0,
		"the wings stay nearly straight at the glide floor (%.1f deg)" % model.sweep_degrees
	)
	# Eased, not linear: halfway to cruise the wings are still well short of half
	# the cruise contraction, so the sweep reads as speed rather than as throttle.
	_player.velocity = aim * (Player.FIGHTER_SPEED * 0.5)
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees < Player.WING_SWEEP_CRUISE * 0.4,
		"the wings stay open at half cruise (%.1f deg)" % model.sweep_degrees
	)
	_player.velocity = aim * (Player.FIGHTER_SPEED - 1.0)
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees > 10.0 and model.sweep_degrees < 18.0,
		"the wings contract at cruise (%.1f deg)" % model.sweep_degrees
	)
	_player.velocity = aim * (Player.FIGHTER_BOOST_SPEED - 2.0)
	_player.call("_update_afterburner_visual", 0.0)
	_check(
		model.sweep_degrees > 30.0,
		"the wings sweep past cruise (%.1f deg)" % model.sweep_degrees
	)

	# The angle is a mechanism, not a readout: the throttle jumps in a couple of
	# frames and the wing still has to travel there.
	_player.velocity = aim * Player.FIGHTER_STALL_SPEED
	_player.call("_update_afterburner_visual", 0.0)
	var settled: float = model.sweep_degrees
	_player.velocity = aim * Player.FIGHTER_BOOST_SPEED
	_player.call("_update_afterburner_visual", 1.0 / 60.0)
	_check(
		model.sweep_degrees > settled
		and model.sweep_degrees < Player.WING_SWEEP_BACK - 10.0,
		"the wings travel to the stop instead of snapping (%.1f deg in one frame)"
		% model.sweep_degrees
	)
	_player.velocity = Vector3.ZERO

	# The speed cue is a ribbon off each tip. The wedge that used to draw the burst
	# is gone; the rule still eats enemy fire (S6), but nothing is painted in front
	# of the nose any more. The pose is pinned to cruise first: the wingtip is a
	# chord and which corner is outermost depends on the sweep, so the point is
	# calibrated -- and checked -- in the pose the vapour actually lives in.
	model.pose_mode(0.0, Player.WING_SWEEP_CRUISE)
	var tips: Array[Vector3] = model.wing_tips()
	var hardpoints: Array[Vector3] = model.wing_anchors()
	_check(tips.size() == 2, "the airframe carries two wingtips")
	if tips.size() == 2 and hardpoints.size() == 2:
		_check(
			tips[0].length() > hardpoints[0].length() + 0.2,
			"the vapour leaves from the tip, past the hardpoint"
		)
		# The point sits on the wing, not past it: the outer edge at cruise is where
		# the silhouette ends, and a corner measured at rest floats outside it.
		_check(
			tips[0].z < -1.6 and tips[1].z > 1.6,
			"the vapour leaves from the outer edge at cruise (z %.2f / %.2f)"
			% [tips[0].z, tips[1].z]
		)
	var trails: Array = _player.effects().wingtip_trails
	_check(trails.size() == 2, "the fighter carries a ribbon on each tip")
	if trails.size() == 2 and tips.size() == 2:
		# The tips answer airspeed now, not the burner: the vapour is the cue that
		# the ship is moving, so it starts at the middle of the throttle.
		_player.call("_clear_wingtip_trails")
		_player.velocity = aim * Player.FIGHTER_SPEED * 0.5
		_check(
			is_zero_approx(float(_player.call("_wingtip_vapour"))),
			"the tips are clean at half throttle"
		)
		_player.velocity = aim * Player.FIGHTER_SPEED
		_check(
			float(_player.call("_wingtip_vapour")) > 0.9,
			"the tips vapour at cruise"
		)

		# A turn is the case the forward component got wrong: the nose outruns the
		# course, so the velocity points well off the nose while the wing is still
		# moving through the air at cruise. Reading the projection made the vapour
		# die at about 70 deg of skid, which is a hard turn, not a slow ship.
		_player.velocity = aim.rotated(Vector3.UP, deg_to_rad(70.0)) * Player.FIGHTER_SPEED
		_check(
			float(_player.call("_wingtip_vapour")) > 0.9,
			"the tips still trail through a turn's skid"
		)

		_player.velocity = aim * Player.FIGHTER_SPEED
		_player.call("_update_wingtip_trails", 1.0 / 60.0)
		var visual: Node3D = _player.get("_visual") as Node3D
		var tip: Vector3 = visual.global_transform * tips[0]
		var samples: Array = trails[0].get("points")
		var first: Vector3 = samples[0] if samples.size() > 0 else Vector3.ZERO
		_check(
			samples.size() == 1 and first.distance_to(tip) < 0.01,
			"the ribbon starts on the wingtip"
		)

		# Walk the tip along and watch the strip build: a particle wake could only
		# ever be as dense as its spawn rate, so what is checked is that the ribbon
		# is one surface ending exactly where the tip is.
		var head: Vector3 = tip
		for _i in 6:
			head += Vector3(0.0, 0.0, 1.0)
			_player.call("_advance_wingtip_trail", trails[0], head, 1.0, 1.0 / 60.0)
		var strip: ImmediateMesh = trails[0].get("mesh") as ImmediateMesh
		_check(
			strip != null and strip.get_surface_count() == 1,
			"the tip vapour is one continuous strip"
		)
		samples = trails[0].get("points")
		var last: Vector3 = samples[samples.size() - 1] if samples.size() > 0 else Vector3.ZERO
		_check(
			samples.size() >= 7 and last.distance_to(head) < 0.01,
			"the ribbon ends on the wingtip (%d samples)" % samples.size()
		)

		# Slowing down stops the head and retires the tail by age.
		for _i in 40:
			_player.call("_advance_wingtip_trail", trails[0], head, 0.0, 1.0 / 30.0)
		_check(
			(trails[0].get("points") as Array).is_empty(),
			"the ribbon dissolves once the ship slows"
		)
		_player.velocity = Vector3.ZERO

	_player.call("_start_transform")
	for _i in 20:
		await get_tree().physics_frame
	var dropped: Vector3 = model.nozzle_anchors()[0]
	_check(
		not _player.is_fighter() and dropped.y < -0.2,
		"the switch back drops the legs again (y %.2f)" % dropped.y
	)


## The burner is a tank, not a cooldown, so this drives the whole cycle in one
## run: burn, coast, burn out, release and re-arm. Those four states are the
## mechanic; checking a single one of them would miss the transitions.
## The wake is a visual, but it is wired to the flight model: two emitters, one per
## nozzle, and the density has to answer a change in speed rather than a clock or
## the speed itself. The puffs are left in world space, which is what turns a point
## emitter into a trail.
func _test_exhaust_trail() -> void:
	var smoke: Array = _player.effects().smoke
	_check(smoke.size() == 2, "the airframe carries one exhaust emitter per nozzle")
	if smoke.size() < 2:
		return
	var first: GPUParticles3D = smoke[0] as GPUParticles3D
	_check(first != null and not first.local_coords, "the puffs stay where they were dropped")
	_check(
		first.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"the trail casts no shadow on the hull"
	)

	# The wake marks a change in speed, not the speed itself. A steady throttle
	# leaves the nozzles clean; a puff is born at the nozzle and stays there, so a
	# standing ship would otherwise wear its own trail.
	_player.call("_update_smoke", 0.0)
	var steady: float = first.amount_ratio
	_player.call("_update_smoke", Player.FIGHTER_ACCELERATION)
	var climbing: float = first.amount_ratio
	_player.call("_update_smoke", -Player.FIGHTER_ACCELERATION)
	var coasting: float = first.amount_ratio
	_check(is_zero_approx(steady), "a steady throttle leaves the nozzles clean")
	_check(
		climbing > steady and is_zero_approx(coasting),
		"the wake marks the climb, not the speed (%.2f climbing, %.2f coasting)"
		% [climbing, coasting]
	)

	var model: PlayerModel = _player.get("_model") as PlayerModel
	var anchor: Vector3 = model.nozzle_anchors()[0]
	_check(
		first.position.distance_to(anchor) < 0.01,
		"the emitter rides its nozzle"
	)


## The ship is a mirror lit by one sun, so the two legs present opposite facets and
## one spine crushed to black while its twin read warm grey: one leg wearing a
## shadow the other did not have. The fill rides the camera and culls on the
## airframe layer. Both halves matter -- a fill that lit the arena would change the
## scene, and meshes left off the layer would not receive it at all.
func _test_airframe_lighting() -> void:
	var rig: Node = _player.camera.get_parent()
	var fill: DirectionalLight3D = rig.get_node_or_null("FillLight") as DirectionalLight3D
	_check(fill != null, "the camera rig carries the airframe fill light")
	if fill == null:
		return
	_check(not fill.shadow_enabled, "the fill casts no shadow of its own")
	_check(
		fill.light_cull_mask == PlayerModel.AIRFRAME_LAYER_MASK,
		"the fill reaches the airframe layer and nothing else"
	)

	var model: PlayerModel = _player.get("_model") as PlayerModel
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	var on_layer: bool = not meshes.is_empty()
	for node in meshes:
		if (node as MeshInstance3D).layers != PlayerModel.AIRFRAME_LAYER_MASK:
			on_layer = false
			break
	_check(on_layer, "every airframe mesh sits on the layer the fill targets")


func _test_afterburner() -> void:
	var turbo_events: Array = []
	var handler: Callable = func(current: float, maximum: float) -> void:
		turbo_events.append(Vector2(current, maximum))
	GlobalEventBus.player_turbo_changed.connect(handler)

	_check(
		is_equal_approx(float(_player.get("_turbo")), Player.TURBO_MAX),
		"the turbo reserve starts full"
	)

	Input.action_press(&"move_right")
	Input.action_press(&"boost")
	var base_fov: float = _player.camera.fov
	for _i in 90:
		await get_tree().physics_frame

	var boosting_fov: float = _player.camera.fov
	var boosting_speed: float = _flat_speed()
	var spent: float = float(_player.get("_turbo"))
	Input.action_release(&"boost")

	_check(
		boosting_speed > Player.MAX_SPEED * 1.1,
		"the afterburner beats normal top speed (%.1f u/s)" % boosting_speed
	)
	_check(
		boosting_fov > base_fov + 1.0,
		"burning widens the lens as a speed cue (%.1f -> %.1f)" % [base_fov, boosting_fov]
	)
	_check(
		spent < Player.TURBO_MAX,
		"the burner spends the reserve (%.0f left)" % spent
	)

	for _i in 60:
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	var refilled: float = float(_player.get("_turbo"))
	_check(
		refilled > spent,
		"the reserve refills off the burner (%.0f -> %.0f)" % [spent, refilled]
	)

	# Burnout: with almost nothing left the burner must cut out and hand the ship
	# back to normal thrust instead of holding the fast speed for free.
	_player.set("_turbo", 3.0)
	Input.action_press(&"move_right")
	Input.action_press(&"boost")
	for _i in 20:
		await get_tree().physics_frame
	var burnt_out_speed: float = _flat_speed()
	_check(
		burnt_out_speed <= Player.MAX_SPEED + 0.5,
		"burnout hands the ship back to normal speed (%.1f u/s)" % burnt_out_speed
	)

	# Re-arm: releasing the button clears the lockout, so a refilled reserve can
	# burn again on the next press.
	Input.action_release(&"boost")
	for _i in 60:
		await get_tree().physics_frame
	Input.action_press(&"boost")
	for _i in 30:
		await get_tree().physics_frame
	var rearmed_speed: float = _flat_speed()
	Input.action_release(&"boost")
	Input.action_release(&"move_right")

	_check(
		rearmed_speed > Player.MAX_SPEED * 1.1,
		"releasing the burner re-arms it (%.1f u/s)" % rearmed_speed
	)
	_check(not turbo_events.is_empty(), "turbo changes reach the event bus")

	GlobalEventBus.player_turbo_changed.disconnect(handler)
	for _i in 40:
		await get_tree().physics_frame


## The planet has no boundary any more: the surface under the ship is replaced as
## the planet rolls, so a straight line must keep going forever.
func _test_travel_is_unbounded() -> void:
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame

	var planet: Node3D = _arena.get_node("Planet")
	var worst_offset: float = 0.0

	Input.action_press(&"move_right")
	for _i in 300:
		await get_tree().physics_frame
		worst_offset = maxf(worst_offset, _planet_offset(planet))
	Input.action_release(&"move_right")

	_check(
		_player.global_position.x > 60.0,
		"the player keeps travelling with no boundary (x %.1f)" % _player.global_position.x
	)
	# Lateral drift is not asserted here: turrets stream in along the heading, and
	# sliding around one is correct physics, not a broken play plane. Height is the
	# invariant — the ship never leaves y = 0 no matter what it meets.
	_check(
		absf(_player.global_position.y) < 0.1,
		"travelling keeps the player on the play plane (y %.3f)" % _player.global_position.y
	)
	# One frame of slack: the assertion may resume before this frame's physics
	# step, so at full speed the planet can legitimately be one step behind.
	_check(
		worst_offset < 1.0,
		"the planet stays under the player while travelling (worst offset %.2f)" % worst_offset
	)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var settled_offset: float = _planet_offset(planet)
	_check(
		settled_offset < 0.01,
		"the planet settles exactly under the player (offset %.4f)" % settled_offset
	)

	# The camera is a child of the player, so a drifting rig would show up here.
	var camera: Camera3D = _player.camera
	if camera != null:
		var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
		var projected: Vector2 = camera.unproject_position(_player.global_position)
		var offset: float = projected.distance_to(centre)
		# The rig trails the body under thrust, so the ship leads the frame by a
		# bounded handful of pixels instead of sitting dead centre like a HUD icon.
		_check(
			offset < 16.0,
			"the camera leads the ship without losing it (off by %.2f px)" % offset
		)


## Rolling without slipping: the planet must turn exactly distance / radius, about
## the axis perpendicular to the movement, in the direction that makes the ground
## flow backwards under the ship.
func _test_planet_rolls_with_the_player() -> void:
	var planet: Node3D = _arena.get_node("Planet")

	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	var start_basis: Basis = planet.global_transform.basis
	var start_position: Vector3 = _player.global_position

	Input.action_press(&"move_right")
	for _i in 90:
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	await get_tree().physics_frame

	var travelled: Vector3 = _player.global_position - start_position
	var distance: float = Vector2(travelled.x, travelled.z).length()
	_check(distance > 20.0, "the roll test covers ground (%.1f units)" % distance)

	# Movement is applied as a world-space pre-rotation, so current * start^-1 is
	# the accumulated spin itself.
	var spin: Basis = planet.global_transform.basis * start_basis.inverse()
	var rotation: Quaternion = spin.get_rotation_quaternion()
	var angle: float = rotation.get_angle()
	var axis: Vector3 = rotation.get_axis()
	var expected: float = distance / Arena.PLANET_RADIUS

	_check(
		absf(angle - expected) < maxf(0.002, expected * 0.1),
		"the planet turns distance / radius (%.4f rad, expected %.4f)" % [angle, expected]
	)
	_check(
		axis.z > 0.95,
		"moving right rolls the planet about +Z so the ground flows left (%s)" % axis
	)

	# No input, no roll: the surface must not creep while the ship hovers.
	_player.velocity = Vector3.ZERO
	for _i in 3:
		await get_tree().physics_frame
	var idle_basis: Basis = planet.global_transform.basis
	for _i in 30:
		await get_tree().physics_frame
	var idle_spin: float = (planet.global_transform.basis * idle_basis.inverse())\
		.get_rotation_quaternion().get_angle()
	_check(idle_spin < 0.01, "the planet holds still while the ship hovers (%.4f rad)" % idle_spin)


## The dash is a jink, not a screen clear. Enemy fire that reaches the hull mid-dash
## is evaded: no damage, no impact, and the shot keeps flying instead of being spent
## on the ship. The same bullet outside the window still costs health, which is what
## keeps the dash a decision instead of a free pass.
func _test_dash_evasion() -> void:
	_clear_projectiles()
	_clear_enemies()
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)
	_player.set("_dash_time", 0.0)
	_player.set("_roll_anim_time", 0.0)
	_player.set("_dash_cooldown", 0.0)
	await get_tree().physics_frame

	# Outside the window the shot is spent on the hit: the rule the dash is measured
	# against, and the behaviour a player still gets by dashing too late.
	var plain: Projectile = _spawn_enemy_bullet(
		_player.global_position - Vector3.RIGHT * 2.5
	)
	for _i in 12:
		await get_tree().physics_frame
	_check(
		int(_player.get("_hp")) == Player.MAX_HP - 1,
		"a bullet still hits a ship that is not dashing (hp %d)" % int(_player.get("_hp"))
	)
	_check(not is_instance_valid(plain), "a plain hit spends the bullet")

	# The window is held open with the burst direction zeroed, so the check is about
	# the rule and not about the hull outrunning the shot.
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)
	_player.set("_dash_direction", Vector3.ZERO)
	_player.set("_dash_time", 10.0)
	var evaded: Projectile = _spawn_enemy_bullet(
		_player.global_position - Vector3.RIGHT * 2.5
	)
	for _i in 12:
		await get_tree().physics_frame
	_check(
		int(_player.get("_hp")) == Player.MAX_HP,
		"a dashing ship takes no damage from the shot (hp %d)" % int(_player.get("_hp"))
	)
	_check(
		evaded != null and is_instance_valid(evaded) and not evaded.is_queued_for_deletion(),
		"the dash evades the shot instead of destroying it"
	)
	_player.set("_dash_time", 0.0)

	# The protection window is the animation, not the step. The button's fighter
	# spin sets no jink at all, so a hull that was only protected while
	# `_dash_time` ran would be shot halfway through the roll it can see itself
	# doing. A live spin clock alone must keep the ship evading.
	_player.set("_invulnerable", 0.0)
	_player.set("_dash_time", 0.0)
	_player.set("_roll_anim_time", Player.ROLL_ANIM_TIME * 0.5)
	_check(_player.is_evading(), "the spin alone still counts as evading")
	_player.set("_hp", Player.MAX_HP)
	var spun: Projectile = _spawn_enemy_bullet(
		_player.global_position - Vector3.RIGHT * 2.5
	)
	for _i in 12:
		await get_tree().physics_frame
	_check(
		int(_player.get("_hp")) == Player.MAX_HP,
		"a spinning ship takes no damage past the step (hp %d)" % int(_player.get("_hp"))
	)
	_check(
		spun != null and is_instance_valid(spun) and not spun.is_queued_for_deletion(),
		"the spin evades the shot past the step"
	)
	_player.set("_roll_anim_time", 0.0)

	_clear_projectiles()
	await get_tree().physics_frame


func _test_damage_and_iframes() -> void:
	# The encounter phase can legitimately land a hit, and this check is about
	# invulnerability frames, not about arriving at full health. The frames are
	# cleared too: an enemy hit a moment earlier would swallow the first one and
	# the test would pass or fail on timing.
	_player.set("_hp", Player.MAX_HP)
	_player.set("_invulnerable", 0.0)

	var event_bus_health: Array[int] = []
	GlobalEventBus.player_health_changed.connect(
		func(current: int, _maximum: int) -> void: event_bus_health.append(current)
	)

	_player.take_damage(1)
	await get_tree().physics_frame
	_player.take_damage(1)
	await get_tree().physics_frame

	var health: int = _player.get("_hp")
	_check(health == Player.MAX_HP - 1, "invulnerability frames block a second hit (hp %d)" % health)
	_check(
		not event_bus_health.is_empty(),
		"health changes reach the event bus for the HUD"
	)


func _test_death() -> void:
	var hud: CanvasLayer = _arena.get_node("HUD") as CanvasLayer
	var game_over: GameOver = hud.get_node("%GameOver") as GameOver
	var counter: Label = hud.get_node("%Counter") as Label
	_check(not game_over.visible, "the death screen starts hidden")

	# The HUD turns both answers into a scene change, and reloading here would
	# restart the scene this test runs in. The answers are the unit under test, so
	# the HUD's handlers are detached for the rest of the check; the countdown is
	# detached too, because it would answer on its own five seconds in.
	for connection in game_over.respawn_requested.get_connections():
		game_over.respawn_requested.disconnect(connection["callable"])
	for connection in game_over.menu_requested.get_connections():
		game_over.menu_requested.disconnect(connection["callable"])

	# The death sound is counted from a clean slate: an earlier encounter is allowed
	# to have landed a killing hit in another test, and this check is about the
	# blast the drain below produces.
	Sfx.reset_counts()
	while int(_player.get("_hp")) > 0:
		_player.set("_invulnerable", 0.0)
		_player.take_damage(1)
		await get_tree().physics_frame

	_check(int(_player.get("_hp")) == 0, "health drains to zero")
	_check(_died_count > 0, "player_died reaches the event bus")
	_check(not bool(_player.get("_alive")), "player enters a dead state")
	_check(Sfx.played(&"player_death") == 1, "the death asks for the ship's blast")
	_check(not Sfx.engine_active(), "the hull's death silences the engine hum")

	# The blast is a world node at the hull's last position, not a child of the
	# ship: it has to outlive the hidden model and the respawn that follows it.
	var blasts: Array[ShipExplosion] = []
	for child in get_tree().current_scene.get_children():
		if child is ShipExplosion:
			blasts.append(child)
	_check(blasts.size() == 1, "death spawns one explosion")
	_check(
		blasts.size() == 1
		and blasts[0].global_position.distance_to(_player.global_position) < 0.01,
		"the explosion starts where the ship died"
	)
	_check(
		blasts.size() == 1 and _wave_of(blasts[0]) != null,
		"the ship's death leaves its shockwave"
	)

	# The panel waits for the blast to open, so the screen is still clear on the
	# death frame; the count starts when the panel arrives.
	_check(not game_over.visible, "the panel waits for the blast")
	for _i in int(GameOver.BLAST_DELAY * 60.0) + 4:
		await get_tree().physics_frame
	_check(game_over.visible, "death opens the game over screen")
	_check(
		game_over.remaining > 0.0 and game_over.remaining <= GameOver.RESPAWN_SECONDS,
		"the countdown starts full (%.2f of %.0f)" % [game_over.remaining, GameOver.RESPAWN_SECONDS]
	)
	_check(
		counter.text == "RESPAWN IN %d" % GameOver.RESPAWN_SECONDS,
		"the counter reads the full countdown (\"%s\")" % counter.text
	)

	var before: float = game_over.remaining
	await get_tree().physics_frame
	_check(game_over.remaining < before, "the countdown ticks down with the frame")
	_check(counter.text.begins_with("RESPAWN IN "), "the counter stays a countdown (\"%s\")" % counter.text)

	# Each answer is checked for the signal it raises; navigation stays with the HUD,
	# whose handlers were detached above.
	var respawns: Array[bool] = []
	var menus: Array[bool] = []
	game_over.respawn_requested.connect(func() -> void: respawns.append(true))
	game_over.menu_requested.connect(func() -> void: menus.append(true))

	var continue_button: Button = hud.get_node("%ContinueButton") as Button
	var menu_button: Button = hud.get_node("%MenuButton") as Button
	_check(continue_button.has_focus(), "the continue button takes the focus for a gamepad")

	continue_button.pressed.emit()
	_check(respawns.size() == 1, "CONTINUE asks for a respawn")
	_check(menus.is_empty(), "CONTINUE does not also ask for the menu")

	game_over.start()
	menu_button.pressed.emit()
	_check(menus.size() == 1, "MAIN MENU asks for the menu")
	_check(respawns.size() == 1, "MAIN MENU does not also ask for a respawn")

	game_over.start()
	var restart_event: InputEventAction = InputEventAction.new()
	restart_event.action = &"restart"
	restart_event.pressed = true
	game_over._unhandled_input(restart_event)
	_check(respawns.size() == 2, "R continues the run")

	game_over.start()
	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	game_over._unhandled_input(cancel_event)
	_check(menus.size() == 2, "ESC leaves for the menu")

	# Disarmed by the last answer: a live countdown would reload the arena while the
	# rest of the suite is still running.
	var stopped_at: float = game_over.remaining
	await get_tree().physics_frame
	_check(game_over.remaining == stopped_at, "one answer stops the countdown")

	# Nothing else owns the blast, so it has to clean itself up: a leaked node would
	# sit in the arena until the next scene change.
	for _i in int(ShipExplosion.LIFETIME * 60.0) + 10:
		await get_tree().physics_frame
	var leaked: bool = false
	for child in get_tree().current_scene.get_children():
		if child is ShipExplosion:
			leaked = true
	_check(not leaked, "the explosion frees itself")


