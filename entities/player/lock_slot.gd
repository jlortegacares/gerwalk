class_name LockSlot
extends RefCounted
## One place a missile can be sent: a contact and the node its mark hangs from.
##
## A fighter or a turret is a single slot — the body itself. A capital ship offers
## its own anchors, so one hull can be three targets and the salvo can be spent on
## the bow, the middle or the stern of the same ship.

## The hull that takes the damage. Kept even when `host` is one of its anchors.
var contact: Enemy
## The node the mark hangs from and the point the missile steers to: the contact
## itself, or one of its lock anchors.
var host: Node3D
var reticle: LockReticle = null


func _init(p_contact: Enemy, p_host: Node3D) -> void:
	contact = p_contact
	host = p_host
