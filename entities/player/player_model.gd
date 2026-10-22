class_name PlayerModel
extends Node3D
## Bone-driven VF-1S. The imported model is a fighter whose legs and arms are
## folded back along the fuselage; this node poses those bones from the same mode
## blend the flight rules use, so GERWALK is a stance instead of a second mesh.
##
## Godot stores a bone pose as an absolute transform, not as an offset from the
## rest: writing an identity rotation collapses the skeleton. Every rotation here
## is therefore composed on top of the bone's rest rotation, and the axis is
## converted from model space into the bone's parent frame once at build time.
##
## The node itself sits at the origin of the player's visual container, so every
## anchor it reports is already in that container's space.

const MODEL_PATH: String = "res://models/vf-1s/source/Vf-01_BRoid_ULa.glb"

## Scale and yaw that put the airframe in the slot the placeholder hull used to
## occupy. The model faces -Z; the game flies towards +X.
const SCALE: float = 0.21
const YAW: float = -PI * 0.5
## Centre of the airframe's bounding box in model space, gear and crew excluded.
## The holder is offset by this so the hull is centred on the capsule origin.
const PIVOT: Vector3 = Vector3(0.0, 1.238, -1.046)

## GERWALK keyframe in degrees, about the model's own axes. The sign conventions
## were measured on the imported rig: the legs hang aft in FIGHTER, so the thigh
## swings about X and the splay about Z, mirrored per side.
const THIGH_ANGLE: float = -150.0
const KNEE_ANGLE: float = -40.0
const LEG_SPLAY: float = 25.0
const ARM_ANGLE: float = -180.0
const ELBOW_ANGLE: float = -35.0
const ARM_SPLAY: float = 22.0

## Gear and crew ship inside the airframe and are never meant to be seen in
## flight. Matching by node name is the only handle the imported scene gives.
const HIDDEN_PREFIXES: Array[String] = [
	"f35c-landingon", "whellnut", "00_milia",
]

const BONE_THIGH_L: String = "Bone.LEG.UPPER.L"
const BONE_THIGH_R: String = "Bone.LEG.UPPER.R"
const BONE_KNEE_L: String = "Bone.LEG.LOWERx.L"
const BONE_KNEE_R: String = "Bone.LEG.LOWER.R"
const BONE_SHOULDER_L: String = "Shoulder_Joint_L"
const BONE_SHOULDER_R: String = "Shoulder_Joint_R"
const BONE_ELBOW_L: String = "Shoulder_Joint_001_L"
const BONE_ELBOW_R: String = "Shoulder_Joint_001_R"
const BONE_WING_L: String = "Bone.Wing.L"
const BONE_WING_R: String = "Bone.Wing.R"
const BONE_HAND_R: String = "Hand.R"
const BONE_NOZZLE_L: String = "Exhaust.UPPERx.L"
const BONE_NOZZLE_R: String = "Exhaust.UPPER.R"

var _skeleton: Skeleton3D
## Bone index -> rest rotation, and the three model axes pulled into that bone's
## parent frame. Built once, so the per-frame pose is only quaternion products.
var _rest: Dictionary = {}
var _axis_x: Dictionary = {}
var _axis_y: Dictionary = {}
var _axis_z: Dictionary = {}
var _thigh: Array[int] = []
var _knee: Array[int] = []
var _shoulder: Array[int] = []
var _elbow: Array[int] = []
var _wing: Array[int] = []
var _hand: int = -1
var _nozzles: Array[int] = []
## Wing sweep the last pose was built with, in degrees. Exposed so the wing rules
## can be checked without reading bones back.
var sweep_degrees: float = 0.0


## Builds the airframe and returns false when the model is missing, so the caller
## can report one clear failure instead of flying an invisible ship.
func build() -> bool:
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("PlayerModel: cannot load " + MODEL_PATH)
		return false
	var model: Node3D = packed.instantiate() as Node3D
	if model == null:
		push_error("PlayerModel: %s is not a 3D scene" % MODEL_PATH)
		return false

	_hide_ground_gear(model)

	# The yaw has to be part of the pivot offset: the pivot is expressed in model
	# space, so it is rotated into the holder's frame before it is cancelled.
	var basis: Basis = Basis(Vector3.UP, YAW).scaled(Vector3.ONE * SCALE)
	var holder: Node3D = Node3D.new()
	holder.name = "Holder"
	holder.basis = basis
	holder.position = -(basis * PIVOT)
	holder.add_child(model)
	add_child(holder)

	var found: Array = model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("PlayerModel: the model has no Skeleton3D")
		return false
	_skeleton = found[0] as Skeleton3D

	_thigh = [_bone(BONE_THIGH_L), _bone(BONE_THIGH_R)]
	_knee = [_bone(BONE_KNEE_L), _bone(BONE_KNEE_R)]
	_shoulder = [_bone(BONE_SHOULDER_L), _bone(BONE_SHOULDER_R)]
	_elbow = [_bone(BONE_ELBOW_L), _bone(BONE_ELBOW_R)]
	_wing = [_bone(BONE_WING_L), _bone(BONE_WING_R)]
	_hand = _bone(BONE_HAND_R)
	_nozzles = [_bone(BONE_NOZZLE_L), _bone(BONE_NOZZLE_R)]

	_cache_bones()
	pose_mode(0.0, 0.0)
	return true


func _hide_ground_gear(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = mi as MeshInstance3D
		var lower: String = String(mesh.name).to_lower()
		for prefix in HIDDEN_PREFIXES:
			if lower.begins_with(prefix):
				mesh.visible = false
				break


func _bone(bone_name: String) -> int:
	var idx: int = _skeleton.find_bone(bone_name)
	if idx < 0:
		push_error("PlayerModel: missing bone " + bone_name)
	return idx


func _cache_bones() -> void:
	for idx in _thigh + _knee + _shoulder + _elbow + _wing:
		if idx < 0 or _rest.has(idx):
			continue
		_rest[idx] = _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
		var parent: int = _skeleton.get_bone_parent(idx)
		var parent_basis: Basis = Basis.IDENTITY
		if parent >= 0:
			parent_basis = _skeleton.get_bone_global_rest(parent).basis
		var to_parent: Basis = parent_basis.inverse()
		_axis_x[idx] = (to_parent * Vector3.RIGHT).normalized()
		_axis_y[idx] = (to_parent * Vector3.UP).normalized()
		_axis_z[idx] = (to_parent * Vector3.BACK).normalized()


## Poses the airframe. `gerwalk` runs 0 (fighter) to 1 (stance); `sweep` is the
## wing sweep in degrees, positive aft.
func _pose(gerwalk: float, sweep: float) -> void:
	if _thigh.size() < 2:
		return
	for idx in _rest:
		_skeleton.set_bone_pose_rotation(idx, _rest[idx])

	for side in 2:
		var out: float = 1.0 if side == 0 else -1.0
		_rotate(_thigh[side], _axis_x[_thigh[side]], THIGH_ANGLE * gerwalk)
		_rotate(_thigh[side], _axis_y[_thigh[side]], LEG_SPLAY * out * gerwalk)
		_rotate(_knee[side], _axis_x[_knee[side]], KNEE_ANGLE * gerwalk)
		_rotate(_shoulder[side], _axis_x[_shoulder[side]], ARM_ANGLE * gerwalk)
		_rotate(_shoulder[side], _axis_z[_shoulder[side]], ARM_SPLAY * out * gerwalk)
		_rotate(_elbow[side], _axis_x[_elbow[side]], ELBOW_ANGLE * gerwalk)
		_rotate(_wing[side], _axis_y[_wing[side]], sweep * out)

	_skeleton.force_update_all_bone_transforms()


## Compose one rotation on top of what the bone already carries this frame. The
## pose is absolute, so this reads the pose back instead of rebuilding it from the
## rest; rebuilding would drop the previous rotation on the same bone.
func _rotate(bone: int, axis: Vector3, degrees: float) -> void:
	if bone < 0 or is_zero_approx(degrees):
		return
	var q: Quaternion = Quaternion(axis, deg_to_rad(degrees)) * _skeleton.get_bone_pose_rotation(bone)
	_skeleton.set_bone_pose_rotation(bone, q)


func pose_mode(gerwalk: float, sweep: float) -> void:
	sweep_degrees = sweep
	_pose(clampf(gerwalk, 0.0, 1.0), sweep)


## Anchors are reported in this node's space, which is the player visual's space.
func _anchor(bone: int) -> Vector3:
	if bone < 0:
		return Vector3.ZERO
	return to_local(_skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin)


## The right hand, where the gunpod rides in GERWALK.
func hand_anchor() -> Vector3:
	return _anchor(_hand)


## The two engine nozzles, which are also the feet: the flames follow them so a
## stance that swings the legs forward drags the exhaust with it.
func nozzle_anchors() -> Array[Vector3]:
	if _nozzles.size() < 2:
		return []
	return [_anchor(_nozzles[0]), _anchor(_nozzles[1])]
