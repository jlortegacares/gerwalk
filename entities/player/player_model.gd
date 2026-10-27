class_name PlayerModel
extends Node3D
## Bone-driven VF-1S. The file ships the whole transformation as a clip, so this
## node does not hand-pose a stance: it samples the fighter frame and the GERWALK
## hold once at build time and slerps between them with the mode blend the flight
## rules use. That keeps the stance the one the asset authored instead of a set of
## angles guessed from screenshots.
##
## Godot stores a bone pose as an absolute transform, not as an offset from the
## rest: writing an identity rotation collapses the skeleton. Both sampled frames
## are stored as full poses for that reason, and nothing is rebuilt from the rest.
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

## The two frames of the shipped clip that matter, in seconds. Frame zero is the
## fighter. The clip is named `__ActionLegGERWALKgunner` for a reason: it lands the
## legs first and then brings the arms out into the gunner stance, and holds both
## from 8.5 s to 10 s before it carries on into Battroid. Nine is that hold -- the
## legs are already planted there, and the hands are in front where the gunpod
## needs them. Sampling the earlier seven-second hold leaves the arms stowed.
const FIGHTER_TIME: float = 0.0
const GERWALK_TIME: float = 9.0

## Gear and crew ship inside the airframe and are never meant to be seen in
## flight. Matching by node name is the only handle the imported scene gives.
const HIDDEN_PREFIXES: Array[String] = [
	"f35c-landingon", "whellnut", "00_milia",
]

## The airframe renders on its own layer so the player's fill light can target the
## ship and nothing else: the arena, the stars and the enemies keep the single-sun
## look. Layer 1 is the default the rest of the scene uses.
const AIRFRAME_LAYER: int = 2
const AIRFRAME_LAYER_MASK: int = 1 << (AIRFRAME_LAYER - 1)

## The canopy ships as two stacked panels: a tinted glass sheet on the glass
## bone, and the grey shell the exporter hangs off the cover bone, which is the
## one the camera actually sees. Only the panels are repainted -- the rib keeps
## the file's trim, which makes it part of the black lines -- and the colour is
## written once at build time, so the switch between modes cannot change it.
##
## The panels are found by bone and mesh name rather than by material: the cover
## wears a hull material ("Aircraft BASE color.004"), so a family match would
## paint the cockpit with the hull colour.
const CANOPY_BONES: Array[String] = ["Bone.GLASScanopy", "Bone.CanopyCover"]
const CANOPY_MESH: String = "vf_1s-fast_canopy"

## The nose is not a mesh of its own: the exporter merged the cone, the panel
## lines across it, the nose gear and the cockpit housing into the forward
## fuselage mesh. It is found by name because the file gives no other handle.
##
## The cone also shares one hull sheet with the section under the cockpit, so that
## sheet is split at the canopy's leading edge and only the half in front of it is
## painted as nose. The half is renamed to NOSE_MATERIAL, which is how the paint
## pass tells the two apart; the trim, the gear and the housing keep their own
## families either way.
const NOSE_MESH: String = "vf_1s-airframe_018"
const NOSE_MATERIAL: String = "Player Nose"
## How far ahead of the canopy's leading edge the nose paint starts, in the forward
## fuselage's own units (about 0.021 game units each, so this is roughly 6 cm on a
## four-metre ship). A small gap leaves the lip in front of the cockpit in the hull
## colour instead of butting the nose colour straight against the canopy.
const NOSE_GAP: float = 3.0

## The livery lives in three of the file's 59 materials: the hull sheets
## ("Aircraft BASE color"), the stripe that runs across them ("Pilot COLOR"), and
## the dark trim that cuts both into panels ("Pilot TRIM"). Everything else --
## nozzles, gear, markings -- keeps what the file shipped, because repainting
## those would flatten the airframe into one colour. The names carry a suffix per
## mesh, so the match is on the prefix.
const HULL_MATERIAL: String = "Aircraft BASE color"
const TRIM_MATERIAL: String = "Pilot COLOR"
const LINE_MATERIAL: String = "Pilot TRIM"

## The bind pose is not the fighter. The armature was exported neutral, and the
## fast pack, the rudders and the gear doors only land where the fighter wants
## them once the clip that ships with the file is applied: the bare import shows
## blades floating off the tail and a pack flipped onto its back.
##
## Frame zero of that clip is the working fighter, but it also parks the ship:
## gear down, canopy open, wings half folded. Only the parts that ride the
## transformation are taken from it. Everything the mode pose owns -- legs, arms,
## wings, canopy -- goes back to the bind pose, which is the shape this class was
## already tuned against and the one that stays symmetric.
const SEEDED_PREFIXES: Array[String] = [
	"Bone.JetPack", "Bone.Rudder", "Bone.GearDOOR", "Bone.gearDOOR",
	"Bone.TailHOOK", "Bone.gearRear", "Bone.WheelStruct", "Bone.gearFRONT",
]

## The clip opens the canopy and cycles the gear on its way to the stance. The
## pilot is hidden, so an open canopy would show an empty seat, and the gear is
## hidden by name -- both keep the fighter pose in the GERWALK frame too.
const FROZEN_PREFIXES: Array[String] = [
	"Bone.GLASScanopy", "Bone.CanopyCover", "Bone.GearDOOR", "Bone.gearDOOR",
	"Bone.gearRear", "Bone.gearFRONT", "Bone.WheelStruct",
]


const BONE_WING_L: String = "Bone.Wing.L"
const BONE_WING_R: String = "Bone.Wing.R"
## The missiles leave from the wing hardpoints. The wing bone sits at the root, so
## the point is pushed outboard along the wing's own axis, which carries the sweep:
## a swept wing launches from where the wing actually is.
const WING_HARDPOINT: float = 0.55
## The two wingtips, measured off the airframe and expressed in each wing bone's own
## frame. The wingtip is a chord, not a point: which corner is outermost depends on
## the sweep, so the measurement is taken at cruise -- the pose the vapour actually
## lives in -- instead of at rest, where the leading corner sticks out and a point
## calibrated there floats outside the silhouette once the wing sweeps back. Keeping
## the points in the bone frame is what makes them ride the sweep, and per-side
## values keep them honest: the rig's wings are not the same length, so one fraction
## of the span would trail one of them short.
const WING_TIP_L: Vector3 = Vector3(-2.275, 7.555, 0.426)
const WING_TIP_R: Vector3 = Vector3(0.732, 7.536, 0.287)
const BONE_NOZZLE_L: String = "Exhaust.UPPERx.L"
const BONE_NOZZLE_R: String = "Exhaust.UPPER.R"
## The wrist, not "Hand.R": that name belongs to the link the gunner clip turns,
## while the hand mesh rides the wrist attachment.
const BONE_HAND_R: String = "Wrist_STATIC.R"

var _skeleton: Skeleton3D
## Bone index -> local pose at each sampled frame. Both are built once, so posing
## a frame is one slerp per bone and nothing is derived from the rest pose.
var _base_rotation: Dictionary = {}
var _base_position: Dictionary = {}
var _gerwalk_rotation: Dictionary = {}
var _gerwalk_position: Dictionary = {}
## Bone index -> the model's up axis pulled into that bone's parent frame, for the
## wing sweep that rides on top of the sampled pose.
var _axis_y: Dictionary = {}
var _wing: Array[int] = []
var _nozzles: Array[int] = []
var _hand: int = -1
## Wing sweep the last pose was built with, in degrees. Exposed so the wing rules
## can be checked without reading bones back.
var sweep_degrees: float = 0.0
## Last blend that was written, so a frame that changes neither the mode nor the
## throttle skips touching the skeleton at all.
var _last_gerwalk: float = -1.0
var _last_sweep: float = 0.0

## Livery colours. Alpha zero means "leave the file's own paint alone", so a model
## built without one is the ship the asset ships, which is what the tools want.
## The canopy, the lines and the nose are the parts the game paints on its own, so
## they start at the factory colours instead of at "unpainted".
var livery_hull: Color = Color(0.0, 0.0, 0.0, 0.0)
var livery_trim: Color = Color(0.0, 0.0, 0.0, 0.0)
var livery_canopy: Color = GameSettings.DEFAULT_CANOPY
var livery_lines: Color = GameSettings.DEFAULT_LINES
var livery_nose: Color = GameSettings.DEFAULT_NOSE
## Every painted material, kept so a colour change after `build()` is a write
## instead of a rebuild: the options preview repaints the same airframe.
var _hull_materials: Array[StandardMaterial3D] = []
var _trim_materials: Array[StandardMaterial3D] = []
var _line_materials: Array[StandardMaterial3D] = []
var _canopy_materials: Array[StandardMaterial3D] = []
var _nose_materials: Array[StandardMaterial3D] = []


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

	_prepare_meshes(model)

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

	# The clip only plays once the model is inside the tree, so the frames are
	# sampled after the holder is attached, not before it.
	_sample_poses(model)

	_wing = [_bone(BONE_WING_L), _bone(BONE_WING_R)]
	_nozzles = [_bone(BONE_NOZZLE_L), _bone(BONE_NOZZLE_R)]
	_hand = _bone(BONE_HAND_R)

	_cache_wing_axes()
	pose_mode(0.0, 0.0)

	# The paint runs on the posed fighter frame. Splitting the nose needs the
	# canopy's position, and the canopy is only placed once the skeleton is in the
	# tree, so the two passes cannot happen while the model is still detached.
	_paint_livery(model)
	_paint_canopy(model)
	return true


## Hides the gear and crew, and drops the shadow. The hull is a few dozen pixels
## across and the directional light has to cover the whole arena, so its shadowmap
## resolves as a dotted arc trailing the ship -- which reads as debris at gameplay
## distance, the same reason the gunpod casts nothing.
func _prepare_meshes(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = mi as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The fill light culls on this layer, so the ship gets its counter-light and
		# the arena keeps the single sun it was tuned with.
		mesh.layers = AIRFRAME_LAYER_MASK
		var lower: String = String(mesh.name).to_lower()
		for prefix in HIDDEN_PREFIXES:
			if lower.begins_with(prefix):
				mesh.visible = false
				break


## Repaints the airframe with the player's livery. Safe to call before `build()`
## (the paint pass picks the colours up) and after it (the kept materials are
## rewritten), which is what lets the options preview change colour live.
func set_livery(
	hull: Color, trim: Color, canopy: Color, lines: Color, nose: Color
) -> void:
	livery_hull = hull
	livery_trim = trim
	livery_canopy = canopy
	livery_lines = lines
	livery_nose = nose
	_apply_livery()


func _apply_livery() -> void:
	if livery_hull.a > 0.0:
		for material in _hull_materials:
			material.albedo_color = livery_hull
	if livery_trim.a > 0.0:
		for material in _trim_materials:
			material.albedo_color = livery_trim
	for material in _line_materials:
		material.albedo_color = livery_lines
	for material in _canopy_materials:
		material.albedo_color = livery_canopy
	for material in _nose_materials:
		material.albedo_color = livery_nose


## Duplicates each livery material per surface instead of editing the imported
## ones in place: the GLB is shared by every instance, so writing into it would
## repaint the enemy previews and every later ship too.
##
## The canopy panels are skipped here and painted by `_paint_canopy()`: the cover
## wears a hull-family material, so leaving it in this pass would paint the cockpit
## with the hull colour.
##
## The forward fuselage is the one mesh whose hull family splits: the cone sheet is
## cut at the canopy before this pass runs, so its front half arrives named
## NOSE_MATERIAL and the section under the cockpit stays hull. The panel lines and
## the nose gear on that mesh still read as themselves.
func _paint_livery(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if _is_canopy_panel(mesh):
			continue
		if _is_nose_mesh(mesh):
			_split_nose_cone(model, mesh)
		for surface in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if source == null:
				continue
			var material_name: String = String(source.resource_name)
			var painted_into: Array[StandardMaterial3D]
			var color: Color
			if material_name.begins_with(NOSE_MATERIAL):
				painted_into = _nose_materials
				color = livery_nose
			elif material_name.begins_with(HULL_MATERIAL):
				painted_into = _hull_materials
				color = livery_hull
			elif material_name.begins_with(TRIM_MATERIAL):
				painted_into = _trim_materials
				color = livery_trim
			elif material_name.begins_with(LINE_MATERIAL):
				painted_into = _line_materials
				color = livery_lines
			else:
				continue
			if color.a <= 0.0:
				continue

			var painted: StandardMaterial3D = source.duplicate() as StandardMaterial3D
			painted.albedo_color = color
			mesh.set_surface_override_material(surface, painted)
			painted_into.append(painted)


## Splits the hull sheet of the forward fuselage at the canopy's leading edge, so
## the nose livery stops where the cockpit starts instead of running under it. The
## paint starts NOSE_GAP ahead of that edge, leaving a strip of hull in front of
## the canopy.
##
## The halves become surfaces of a rebuilt mesh rather than two nodes: the file's
## vertices are not welded, so connectivity cannot tell the cone from the section
## under the cockpit, and a second mesh over the same triangles would z-fight. Each
## triangle goes whole to the side its centroid falls on, so nothing is dropped or
## duplicated and the silhouette does not change.
##
## The cone half wears a copy of the hull material renamed to NOSE_MATERIAL. The
## file's own material is never touched, and the section behind keeps it, which is
## what the hull livery paints.
func _split_nose_cone(model: Node3D, mesh: MeshInstance3D) -> void:
	var cut: float = _canopy_front(model, mesh) + NOSE_GAP
	var source: Mesh = mesh.mesh
	var rebuilt: ArrayMesh = ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var material: StandardMaterial3D = (
			mesh.get_active_material(surface) as StandardMaterial3D
		)
		if material == null or not String(material.resource_name).begins_with(HULL_MATERIAL):
			_add_surface(rebuilt, source, surface, arrays, material)
			continue
		var halves: Dictionary = _split_triangles(arrays, cut)
		var cone: StandardMaterial3D = material.duplicate() as StandardMaterial3D
		cone.resource_name = NOSE_MATERIAL
		_add_half(rebuilt, source, surface, arrays, halves["cone"], cone)
		_add_half(rebuilt, source, surface, arrays, halves["aft"], material)
	mesh.mesh = rebuilt


## The leading edge of the canopy, in the forward fuselage mesh's own space: the
## canopy is measured, not assumed, so the cut follows the asset if it is ever
## re-exported. Both sit on the fighter frame when this runs, and the canopy is
## frozen there, so the plane holds in GERWALK too.
##
## No canopy to measure against means no nose paint: the whole sheet stays hull
## rather than the nose colour swallowing the cockpit.
func _canopy_front(model: Node3D, mesh: MeshInstance3D) -> float:
	var to_mesh: Transform3D = mesh.global_transform.affine_inverse()
	var front: float = -INF
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var panel: MeshInstance3D = node as MeshInstance3D
		if not _is_canopy_panel(panel):
			continue
		var local: Transform3D = to_mesh * panel.global_transform
		for surface in panel.mesh.get_surface_count():
			var vertices: PackedVector3Array = (
				panel.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			)
			for point in vertices:
				front = maxf(front, (local * point).z)
	if front == -INF:
		return INF
	return front


## Walks the index buffer in triangles and sends each one to the side of the cut
## its centroid falls on. Packed arrays are values in GDScript, so the two lists
## are appended to directly instead of through a shared handle.
func _split_triangles(arrays: Array, cut: float) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cone: PackedInt32Array = PackedInt32Array()
	var aft: PackedInt32Array = PackedInt32Array()
	for corner in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[corner]]
		var b: Vector3 = vertices[indices[corner + 1]]
		var c: Vector3 = vertices[indices[corner + 2]]
		if (a + b + c).z / 3.0 >= cut:
			cone.append(indices[corner])
			cone.append(indices[corner + 1])
			cone.append(indices[corner + 2])
		else:
			aft.append(indices[corner])
			aft.append(indices[corner + 1])
			aft.append(indices[corner + 2])
	return {"cone": cone, "aft": aft}


## Adds one half of a split surface. An empty half is skipped instead of being
## added as a surface with no triangles, which the array mesh rejects.
func _add_half(
	rebuilt: ArrayMesh,
	source: Mesh,
	surface: int,
	arrays: Array,
	indices: PackedInt32Array,
	material: Material
) -> void:
	if indices.is_empty():
		return
	var half: Array = arrays.duplicate()
	half[Mesh.ARRAY_INDEX] = indices
	_add_surface(rebuilt, source, surface, half, material)


## Copies one surface into the rebuilt mesh, keeping its primitive type and its
## material: the surfaces this pass does not split have to render exactly as the
## file shipped them.
func _add_surface(
	rebuilt: ArrayMesh, source: Mesh, surface: int, arrays: Array, material: Material
) -> void:
	rebuilt.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
	if material != null:
		rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, material)


## Repaints the canopy glass. The rib is not a panel, so it keeps the line colour
## and the canopy still has its frame and its silhouette.
func _paint_canopy(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not _is_canopy_panel(mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = (
				mesh.get_active_material(surface) as StandardMaterial3D
			)
			if source == null:
				continue
			var panel: StandardMaterial3D = source.duplicate() as StandardMaterial3D
			panel.albedo_color = livery_canopy
			mesh.set_surface_override_material(surface, panel)
			_canopy_materials.append(panel)


## A canopy panel is a mesh hung off one of the canopy bones whose name carries
## the canopy mesh and not the rib. The rib is the frame, and the frame belongs to
## the lines.
func _is_canopy_panel(mesh: MeshInstance3D) -> bool:
	var attachment: BoneAttachment3D = mesh.get_parent() as BoneAttachment3D
	if attachment == null or not CANOPY_BONES.has(attachment.bone_name):
		return false
	var lower: String = String(mesh.name).to_lower()
	return lower.contains(CANOPY_MESH) and not lower.contains("rib")


## The forward fuselage mesh, which carries the nose cone.
func _is_nose_mesh(mesh: MeshInstance3D) -> bool:
	return String(mesh.name).to_lower().contains(NOSE_MESH)


## Samples the two frames the stance is built from. The clip only plays once the
## model is in the tree, so this runs after the holder is attached.
func _sample_poses(model: Node3D) -> void:
	var count: int = _skeleton.get_bone_count()
	var players: Array = model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_warning("PlayerModel: no clip to pose from, the airframe keeps its bind pose")
		_capture_bind_pose(count)
		return
	var player: AnimationPlayer = players[0] as AnimationPlayer
	var clips: PackedStringArray = player.get_animation_list()
	if clips.is_empty():
		push_warning("PlayerModel: the clip list is empty, the airframe keeps its bind pose")
		_capture_bind_pose(count)
		return

	player.play(clips[0])
	player.seek(FIGHTER_TIME, true)
	player.pause()
	# Frame zero is the fighter, but it is the parked one: gear down, canopy open,
	# wings half folded. Only the parts that ride the transformation keep the
	# clip's value; everything the mode pose owns goes back to bind, which is the
	# symmetric fighter this class was tuned against.
	for idx in count:
		if not _is_seeded(_skeleton.get_bone_name(idx)):
			_skeleton.reset_bone_pose(idx)
	_skeleton.force_update_all_bone_transforms()
	for idx in count:
		_base_rotation[idx] = _skeleton.get_bone_pose_rotation(idx)
		_base_position[idx] = _skeleton.get_bone_pose_position(idx)

	player.seek(GERWALK_TIME, true)
	player.pause()
	for idx in count:
		if _is_frozen(_skeleton.get_bone_name(idx)):
			_gerwalk_rotation[idx] = _base_rotation[idx]
			_gerwalk_position[idx] = _base_position[idx]
		else:
			_gerwalk_rotation[idx] = _skeleton.get_bone_pose_rotation(idx)
			_gerwalk_position[idx] = _skeleton.get_bone_pose_position(idx)

	# Leave the skeleton on the fighter frame: the first pose is written from the
	# captured values anyway, so the paused player is only a fallback.
	for idx in count:
		_skeleton.set_bone_pose_rotation(idx, _base_rotation[idx])
		_skeleton.set_bone_pose_position(idx, _base_position[idx])
	_skeleton.force_update_all_bone_transforms()


## Fallback for a missing clip: both frames are the pose the file was exported in.
func _capture_bind_pose(count: int) -> void:
	for idx in count:
		var rotation: Quaternion = _skeleton.get_bone_pose_rotation(idx)
		var position: Vector3 = _skeleton.get_bone_pose_position(idx)
		_base_rotation[idx] = rotation
		_base_position[idx] = position
		_gerwalk_rotation[idx] = rotation
		_gerwalk_position[idx] = position


func _is_seeded(bone_name: String) -> bool:
	for prefix in SEEDED_PREFIXES:
		if bone_name.begins_with(prefix):
			return true
	return false


func _is_frozen(bone_name: String) -> bool:
	for prefix in FROZEN_PREFIXES:
		if bone_name.begins_with(prefix):
			return true
	return false


func _bone(bone_name: String) -> int:
	var idx: int = _skeleton.find_bone(bone_name)
	if idx < 0:
		push_error("PlayerModel: missing bone " + bone_name)
	return idx


## The sweep is the one rotation that rides on top of the sampled pose, so its
## axis is pulled into the wing bone's parent frame once, from the fighter frame.
func _cache_wing_axes() -> void:
	for idx in _wing:
		if idx < 0:
			continue
		var parent: int = _skeleton.get_bone_parent(idx)
		var parent_basis: Basis = Basis.IDENTITY
		if parent >= 0:
			parent_basis = _skeleton.get_bone_global_pose(parent).basis
		var to_parent: Basis = parent_basis.inverse()
		_axis_y[idx] = (to_parent * Vector3.UP).normalized()


## Poses the airframe. `gerwalk` runs 0 (fighter) to 1 (stance); `sweep` is the
## wing sweep in degrees, positive aft.
func _pose(gerwalk: float, sweep: float) -> void:
	if _base_rotation.is_empty():
		return
	if is_equal_approx(gerwalk, _last_gerwalk) and is_equal_approx(sweep, _last_sweep):
		return
	_last_gerwalk = gerwalk
	_last_sweep = sweep
	for idx in _base_rotation:
		var rotation: Quaternion = (_base_rotation[idx] as Quaternion).slerp(
			_gerwalk_rotation[idx] as Quaternion, gerwalk
		)
		_skeleton.set_bone_pose_rotation(idx, rotation)
		var origin: Vector3 = (_base_position[idx] as Vector3).lerp(
			_gerwalk_position[idx] as Vector3, gerwalk
		)
		_skeleton.set_bone_pose_position(idx, origin)

	for side in 2:
		if _wing[side] < 0:
			continue
		var out: float = 1.0 if side == 0 else -1.0
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


## The two engine nozzles, which are also the feet: the flames follow them so a
## stance that swings the legs forward drags the exhaust with it.
func nozzle_anchors() -> Array[Vector3]:
	if _nozzles.size() < 2:
		return []
	return [_anchor(_nozzles[0]), _anchor(_nozzles[1])]


## Where the right hand ends up, which is where the gunpod rides in GERWALK. The
## gunner stance puts it in front of the wing root, so the pod reaches ahead of
## the hull instead of trailing the tail.
func hand_anchor() -> Vector3:
	return _anchor(_hand)


## The two wing hardpoints, left first, in this node's space. The bone origin is
## the root, so the point is pushed outboard along the bone's own span axis: that
## axis is what the sweep turns, so a folded wing moves its hardpoint with it.
func wing_anchors() -> Array[Vector3]:
	if _wing.size() < 2:
		return []
	var points: Array[Vector3] = []
	for idx in _wing:
		if idx < 0:
			return []
		var pose: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(idx)
		var root: Vector3 = to_local(pose.origin)
		var span: Vector3 = to_local(pose.origin + pose.basis.y.normalized()) - root
		points.append(root + span.normalized() * WING_HARDPOINT)
	return points


## The two wingtips, in the same frame as `wing_anchors`. The measured mesh tip is
## carried by the posed wing bone, so a swept wing leaves its vapour from where the
## tip actually is instead of from a fixed point in the model.
func wing_tips() -> Array[Vector3]:
	if _wing.size() < 2:
		return []
	var offsets: Array[Vector3] = [WING_TIP_L, WING_TIP_R]
	var points: Array[Vector3] = []
	for side in _wing.size():
		var idx: int = _wing[side]
		if idx < 0:
			return []
		var pose: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(idx)
		points.append(to_local(pose * offsets[side]))
	return points
