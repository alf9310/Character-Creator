@tool
class_name CharacterPreview
extends SubViewportContainer

# Orbit state
var _yaw:   float = 0.0
var _pitch: float = 0.0

# Zoom state
var _arm_length: float = 2.0

# TODO: Adjust in settings 
const ZOOM_MIN := 0.5
const ZOOM_MAX := 5.0

# Node references
@onready var _viewport:  SubViewport  = $SubViewport
@onready var _pivot:     Node3D       = $SubViewport/CameraRig/Pivot
@onready var _camera:    Camera3D     = $SubViewport/CameraRig/Camera3D
@onready var _character: Node         = null #$SubViewport/Character # Injected by SceneGenerator


### SubViewport configuration
'''
The `SubViewport` needs a handful of specific settings to behave correctly inside a UI panel. 
These are set in the `.tscn` rather than in script so they serialise cleanly and are visible in the editor inspector:

SubViewport:
	# An isolated world keeps the preview self-contained regardless of what scene the developer embeds the creator into.
	own_world_3d:             true
	# lets the SubViewportContainer's own background show through where there is no geometry. 
	# This means the developer can style the preview area with a StyleBox on the container 
	# (ex: A dark panel, a gradient, a patterned background)
	transparent_bg:           true
	# Forwards mouse events up to the main viewport 
	handle_input_locally:     false
	size:                     Vector2i(400, 600)
	# Allows the SubViewport to render at a fixed internal resolution while the container scales
	size_2d_override_stretch: true
	# Anti-aliasing
	# TODO: Make an option in settings!
	msaa_3d:                  MSAA_4X
'''

## Camera rig setup
func _ready() -> void:
	# Don't run initialization in the editor
	#if Engine.is_editor_hint():
	#	return
		
	_arm_length = _camera.position.z   # read initial distance from the .tscn
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	# Clamp pitch to prevent flipping over the top or bottom & gimbal lock
	_pitch = clamp(_pitch, -80.0, 80.0)

	_pivot.rotation_degrees = Vector3(_pitch, _yaw, 0.0)
	_camera.position        = Vector3(0.0, 0.0, _arm_length)

## Sets the pivot's look-at target which offsets it upward from the character's origin 
## CharacterCreator calls configure() in _ready() after reading the config.
func configure(config: CharacterConfig) -> void:
	_arm_length = config.preview_camera_distance

	# Offset the CameraRig itself upward so the orbit center
	# is at chest/face height rather than the character's feet
	$SubViewport/CameraRig.position = Vector3(0.0, config.preview_camera_height, 0.0)

	_apply_camera_transform()

## CharacterCreator._unhandled_input() calls orbit() on every drag frame 
## when the cursor is over the preview area.
# TODO: Adjust camera motion in settings 
func orbit(delta: Vector2) -> void:
	_yaw   -= delta.x   # horizontal drag -> rotate around Y axis
	_pitch -= delta.y   # vertical drag   -> tilt up/down
	_apply_camera_transform()

## Zoom is applied directly to _camera.position.z
func zoom(delta: float) -> void:
	_arm_length = clamp(_arm_length + delta, ZOOM_MIN, ZOOM_MAX)
	_camera.position.z = _arm_length

func reset() -> void:
	_yaw        = 0.0
	_pitch      = 0.0
	# TODO: Add a default distance in config
	# _arm_length = _config.preview_camera_distance
	_arm_length = 2.0
	_apply_camera_transform()
	_camera.position.z = _arm_length


## Exposes the character node to CharacterExporter to call blendshape and material operations.
## Uses a typed getter rather than making the node path part of the public API 
## so internal restructuring of the SubViewport tree doesn't break the exporter.
# TODO: Make faster!!!!
func get_character_root() -> Node: 
	#if Engine.is_editor_hint():
	#	return null
	# Resolve once and cache
	if _character == null:
		_character = get_node_or_null("SubViewport/Character")
		if _character == null:
			push_warning("[CharacterPreview] SubViewport/Character not found.")
	return _character

## SubViewport has a fixed size, but the SubViewportContainer can be resized by the layout.
## Updates the viewport's internal resolution when the container changes size to 
## avoid rendering at the wrong aspect ratio.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		var new_size := Vector2i(int(size.x), int(size.y))
		$SubViewport.size = new_size
