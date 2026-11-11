class_name BossPart
extends StaticBody3D
## One of the mothership's six target points: two per section, port and starboard on
## the bow, the middle and the stern.
##
## The hull is fought as six pools instead of one because a 96-unit ship is already a
## level. A single hitbox that large turns every shot into the same shot; six points
## give the player places to attack, and each one can be finished on its own. The
## section id is what groups them: a third of the ship falls when both of its points
## do, and that is what silences the section's gun.
##
## The section is a solid box on the world and enemy layers, so it blocks the player
## and every player shot finds it. Destroying it does not open the hull: the wreckage
## is still a wall, but the section stops taking damage and stops answering fire,
## which is how the player reads that this third is finished.
##
## The part owns its pool and reports through signals. The boss owns the sum, the bar
## and the death, so a section can never decide the fight on its own.
##
## It is a `StaticBody3D` and not an `AnimatableBody3D`. An animatable body writes the
## physics server's transform back onto the node every step, and inside a hull that
## moves every physics frame that read-back accumulates: the box drifts away from the
## model until shots pass through the deck they visibly crossed. A static body follows
## its parent's transform exactly, which is all a wall riding a moving hull has to do.

signal damaged(part: BossPart, current: int, maximum: int)
signal destroyed(part: BossPart)

## Collision layers, 1-based in the editor and bit index here, matching
## `Projectile`'s constants.
const LAYER_WORLD: int = 0
const LAYER_ENEMY: int = 3

var part_id: int = 0
## Which third of the hull this point belongs to: 0 bow, 1 middle, 2 stern. The
## section is the unit the fight reads as an area; the point is the unit a shot lands
## on. Two points share a section, so a section is alive while either one is.
var section_id: int = 0
var max_hp: int = 1

var _hp: int = 1
var _destroyed: bool = false


## Built before the part enters the tree, so the first frame already has a solid
## section instead of an empty body for one.
func setup(id: int, section: int, hp: int, size: Vector3) -> void:
	part_id = id
	section_id = section
	max_hp = maxi(hp, 1)
	_hp = max_hp

	# World so the player cannot fly through the hull, enemy so player fire finds
	# the section. The section detects nothing itself.
	collision_layer = (1 << LAYER_WORLD) | (1 << LAYER_ENEMY)
	collision_mask = 0

	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = box
	add_child(collider)


func current_hp() -> int:
	return _hp


func is_destroyed() -> bool:
	return _destroyed


func take_damage(amount: int) -> void:
	# A dead section keeps its collider, so the hull stays solid, but it no longer
	# takes damage: the player has to move to a section that is still alive.
	if _destroyed or amount <= 0:
		return

	_hp = maxi(_hp - amount, 0)
	damaged.emit(self, _hp, max_hp)

	if _hp <= 0:
		_destroyed = true
		destroyed.emit(self)
