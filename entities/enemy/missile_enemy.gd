class_name MissileEnemy
extends Enemy
## Missile launcher. It keeps the turret's body and movement — roam, engage, orbit,
## leash — and replaces the bullet patterns with a guided pair. The threat is the
## turn: the shot outruns the hover's cruise, so flying away only works with the
## burner or by transforming, and a hard turn, a dash or a decoy breaks the lock.
## The fight is about spending the warning window instead of out-drawing a wall of
## bullets.
##
## Everything else is inherited on purpose: the arena streams it, the radar sees
## it, the bomb damages it and the player's missiles lock it, because it is still
## an `Enemy` in the `enemy` group.

## Tougher than a turret: killing the launcher before it commits is the counterplay,
## so the hull has to be worth prioritizing.
const LAUNCHER_HP: int = 12

const SALVO_MISSILES: int = 2
## Faster than the hover's cruise (26.8), so running away in GERWALK does not work:
## the shot closes about 6 units a second. It stays below the afterburner (42) and
## well below FIGHTER cruise (48.2), so the burner, the transform, a hard turn, a
## dash or a decoy all still break it. The threat is the commitment it forces, not
## an unanswerable chase.
const MISSILE_SPEED: float = 33.0
const MISSILE_DAMAGE: int = 2
const MISSILE_TURN_RATE: float = 1.6
const MISSILE_SIZE: Vector3 = Vector3(0.50, 0.42, 2.1)
const MISSILE_LIFETIME: float = 6.0
const MISSILE_SPREAD_DEGREES: float = 9.0
## Far enough ahead of the hull that the long body clears it on the first frame.
const LAUNCH_OFFSET: float = 2.4

## A missile is a bigger commitment than a bullet, so the warning is longer and the
## recovery is longer: the exchange is a window, not a rate of fire.
const LAUNCH_TELEGRAPH: float = 0.72
const LAUNCH_RECOVER: float = 2.3

const LAUNCHER_COLOR: Color = Color(0.98, 0.62, 0.25, 1.0)
const POD_COLOR: Color = Color(0.34, 0.26, 0.22, 1.0)


func _ready() -> void:
	# A variant repaints and re-times itself before the inherited `_ready` builds
	# the visual and reads the clock, so the state machine never has to be copied.
	_hp = LAUNCHER_HP
	_base_color = LAUNCHER_COLOR
	_telegraph_time = LAUNCH_TELEGRAPH
	_recover_time = LAUNCH_RECOVER
	super()


## A guided shot needs a warning that points at the ship for the whole telegraph,
## not only for the fan pattern the turret draws a beam for.
func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = _telegraph_time
	_aim_beam.visible = true


func _fire_pattern() -> void:
	if bullet_scene == null or not is_instance_valid(_player):
		return

	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return
	var aim_at_player: Vector3 = to_player.normalized()

	for index in SALVO_MISSILES:
		var offset_index: float = float(index) - float(SALVO_MISSILES - 1) * 0.5
		var offset: float = deg_to_rad(MISSILE_SPREAD_DEGREES) * offset_index
		_spawn_missile(aim_at_player.rotated(Vector3.UP, offset))


## The missile is born already pointed at the ship, but its guidance is what makes
## it a threat: the launch angle only keeps the curve legible from the first frame.
func _spawn_missile(direction: Vector3) -> void:
	var missile: Projectile = bullet_scene.instantiate()
	get_tree().current_scene.add_child(missile)
	missile.global_position = global_position + direction * LAUNCH_OFFSET
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


## The inherited hull, plus the two launch tubes that say "this one shoots
## missiles" before it fires. The pods are children of `_visual`, so they take the
## hit flash with the rest of the body.
func _build_visual() -> void:
	super()

	var pod_material: StandardMaterial3D = StandardMaterial3D.new()
	pod_material.albedo_color = POD_COLOR
	pod_material.emission_enabled = true
	pod_material.emission = _base_color
	pod_material.emission_energy_multiplier = 0.28
	pod_material.roughness = 0.6

	for side in [-1.0, 1.0]:
		var pod: MeshInstance3D = MeshInstance3D.new()
		var pod_mesh: BoxMesh = BoxMesh.new()
		pod_mesh.size = Vector3(0.85, 0.55, 2.9)
		pod.mesh = pod_mesh
		pod.material_override = pod_material
		pod.position = Vector3(1.15 * side, 0.55, 0.0)
		pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(pod)
