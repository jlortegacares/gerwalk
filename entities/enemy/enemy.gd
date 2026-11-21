class_name Enemy
extends CharacterBody3D
## A hostile contact. This is the contract every weapon, radar and level works
## against, not a behaviour.
##
## The `enemy` group is what puts a hull in the population count, the radar's
## contact list, the bomb's damage and the missile lock, so being one is what makes
## a ship a first-class target. This base adds what the contract needs: a pool to
## drain, a `killed` signal and a death that feeds the pilot's record, the hit
## flash, the warning beam and the state lifecycle the small hulls drive.
##
## What is deliberately absent is any flight, gun or hull. Those belong to the
## concrete enemy: `Turret` roams and fires patterns, `MissileEnemy` keeps the
## turret's body and swaps the guns, `FighterEnemy` flies the player's airframe and
## `Boss` is a set piece with its own death.
##
## This file exists because the base used to live inside `turret.gd`, which meant a
## capital ship inherited a turret and then overrode almost all of it. Moving the
## contract out is what makes `Boss extends Enemy` an honest statement: the base is
## an identity, not a behaviour.

## The lifecycle every small hull drives. `Turret`, `MissileEnemy` and
## `FighterEnemy` share the states even though they fill them differently; `Boss`
## runs its own and only uses `_state` through the base death path.
enum State {
	ROAM,
	ENGAGED,
	TELEGRAPH,
	RECOVER,
	DEAD,
}

## The standard explosion's camera kick. Lighter than the ship's full-strength
## kick: the blast is the same one, but the camera should not answer an enemy kill
## as if the run had ended. A capital ship runs its own break-up instead.
const DEATH_SHAKE: float = 0.35

## How long the hull pulses after a hit. Long enough to be read at combat speed,
## short enough that sustained fire does not strobe.
const HIT_FLASH_TIME: float = 0.12

## The warning bar the small hulls point at the ship before they fire. The turret's
## fan and an interceptor's launch warning are the same bar, so the mesh lives here
## and each hull owns when it is visible and where it points.
const AIM_BEAM_COLOR: Color = Color(1.0, 0.43, 0.52, 0.45)

signal killed

@export var bullet_scene: PackedScene

## The pool. Every concrete enemy declares its own size through `max_hp()`; the base
## only needs a value that is already drained if a subclass forgets one.
var _hp: int = 1
var _state: State = State.ROAM
var _timer: float = 0.0
var _player: Player = null
var _hit_flash: float = 0.0
var _visual: Node3D
var _aim_beam: MeshInstance3D


func _ready() -> void:
	add_to_group(&"enemy")
	_hp = max_hp()
	_player = _find_player()
	_build_visual()


## The hull this enemy starts with. A turret, an interceptor and a capital ship do
## not share a hull size, so the pool is a fact each one declares instead of a
## base default the subclasses have to remember to overwrite.
func max_hp() -> int:
	return 1


## Read-only view of the pool. The player still owns damage; this exists so the
## smoke test can assert what a weapon actually did to a target.
func current_hp() -> int:
	return _hp


## What the run earns for this kill. Every concrete enemy declares its own threat.
func score_value() -> int:
	return 0


## The footprint the missile lock box should frame, as `(half length, height above
## the body, half width)`. The default is zero, which tells the radar to use its own
## resting size: a turret is one unit and a box already frames it. A capital ship
## overrides this, because a fighter-sized box on its centre reads as no lock at all.
func lock_mark() -> Vector3:
	return Vector3.ZERO


## Whether the mark's plane sits inside the target's own model. The default is false:
## a turret's box floats above a body small enough to see past. A capital ship puts
## its mark on the hull, so the mark has to be drawn over the model to stay visible.
func lock_mark_on_hull() -> bool:
	return false


## Extra places a missile can be locked on, besides the body itself. The default is
## none, because a turret is one contact and one mark. A capital ship overrides it
## with one anchor per section, which is what lets the rack split a salvo over parts
## of the same hull.
func lock_mark_anchors() -> Array[Node3D]:
	var none: Array[Node3D] = []
	return none


func take_damage(amount: int) -> void:
	if _state == State.DEAD:
		return

	_hp -= amount
	_hit_flash = HIT_FLASH_TIME

	if _hp <= 0:
		_die()


func _die() -> void:
	_state = State.DEAD
	# The enemy frees itself at the end of the frame, so the hull and the aim beam
	# are hidden now: a live model under the fireball reads as two hulls for one
	# frame, which is exactly the frame the blast is peaking.
	if is_instance_valid(_visual):
		_visual.visible = false
	if is_instance_valid(_aim_beam):
		_aim_beam.visible = false
	_spawn_explosion()
	killed.emit()
	# The pilot's record grows here, for the same reason the score event is emitted
	# here: a kill counts no matter which path spawned the enemy, and the level is
	# earned by the count rather than awarded by the level.
	GameProgress.instance().register_kill()
	# The bus event is emitted here, not forwarded by the arena: a kill counts no
	# matter which path spawned the enemy, and the value travels with it.
	GlobalEventBus.enemy_killed.emit(score_value())
	queue_free()


## The enemy dies the way the ship does. The blast is a world node, not a child,
## because the enemy is freed on this frame and the wreck has to outlive it. The
## camera kick is lighter than the ship's: the explosion is the same, but a kill is
## not the run ending. A capital ship overrides `_die` with its own break-up.
func _spawn_explosion() -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		return
	var blast: ShipExplosion = ShipExplosion.new()
	blast.shake_strength = DEATH_SHAKE
	host.add_child(blast)
	blast.global_position = global_position
	Sfx.play_at(&"explosion", global_position)


func _planar_distance_to(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _find_player() -> Player:
	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	for node in players:
		if node is Player:
			return node
	return null


## Each enemy builds its own hull: a turret is a hexagon and a capital ship is a
## GLB. The base owns the node the subclass fills.
func _build_visual() -> void:
	pass


## The bar every small hull points at the ship before it fires. The mesh is shared
## because the shape and the colour are the same warning; where it points and when
## it is visible are the concrete hull's business.
func _build_aim_beam() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = AIM_BEAM_COLOR

	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(0.14, 0.05, 1.0)

	_aim_beam = MeshInstance3D.new()
	_aim_beam.mesh = beam_mesh
	_aim_beam.material_override = material
	_aim_beam.visible = false
	_aim_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_beam)
