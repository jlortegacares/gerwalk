class_name LiveryPreview
extends SubViewport
## A copy of the airframe turning in the options panel, so a swatch is a decision
## made by looking instead of by imagining.
##
## It builds the same `PlayerModel` the game builds and paints it through the same
## `set_livery` call, so the preview cannot drift from the ship. The camera and the
## lights live here rather than in the scene because they exist only to frame one
## object: a rig that is read as numbers is a rig that can be tuned by reading it.

const TURN_SPEED: float = 0.7
## The airframe is about four units nose to tail, so the camera has to sit far
## enough back to leave air around it at every angle of the turn.
const CAMERA_POSITION: Vector3 = Vector3(0.0, 1.45, 4.6)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.05, 0.0)
const BACKGROUND: Color = Color(0.035, 0.05, 0.07, 1.0)

var _pivot: Node3D
var _model: PlayerModel
## The colours are kept even before there is a model to paint, so the owner can
## push a livery at any time and the airframe is built already wearing it.
var _hull: Color = GameSettings.DEFAULT_HULL
var _nose: Color = GameSettings.DEFAULT_NOSE
var _trim: Color = GameSettings.DEFAULT_TRIM
var _canopy: Color = GameSettings.DEFAULT_CANOPY
var _lines: Color = GameSettings.DEFAULT_LINES
var _built: bool = false


func _ready() -> void:
	_build_rig()

	_pivot = Node3D.new()
	add_child(_pivot)


## Builds the airframe the first time somebody is going to look at it. The panel
## starts hidden, and this is the most expensive thing in the menu, so building at
## `_ready` would pay for a ship nobody has asked to see.
func ensure_built() -> void:
	if _built or _pivot == null:
		return
	_built = true
	_model = PlayerModel.new()
	_pivot.add_child(_model)
	_model.set_livery(_hull, _trim, _canopy, _lines, _nose)
	if not _model.build():
		push_warning("LiveryPreview: the airframe did not build, the panel shows an empty bay")


func set_livery(
	hull: Color, trim: Color, canopy: Color, lines: Color, nose: Color
) -> void:
	_hull = hull
	_trim = trim
	_canopy = canopy
	_lines = lines
	_nose = nose
	if _built:
		_model.set_livery(hull, trim, canopy, lines, nose)


func _process(delta: float) -> void:
	if _built:
		_pivot.rotation.y = wrapf(_pivot.rotation.y + TURN_SPEED * delta, -PI, PI)


func _build_rig() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.65, 0.85)
	environment.ambient_light_energy = 0.35
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	# The game lights the ship with one sun plus a fill that rides the camera, so
	# the preview does the same: a hull that reads well here reads well in flight.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(35.0), 0.0)
	key.light_energy = 1.5
	add_child(key)

	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(-140.0), 0.0)
	fill.light_color = Color(0.62, 0.72, 0.95)
	fill.light_energy = 0.6
	add_child(fill)

	var camera: Camera3D = Camera3D.new()
	camera.fov = 42.0
	add_child(camera)
	camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
