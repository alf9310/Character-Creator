@tool
class_name CharacterPreview
extends SubViewportContainer

# TODO: Adjust in settings 
@export var rotation_speed := 0.01

@export var zoom_speed := 0.1
@export var min_zoom := 0.5
@export var max_zoom := 5.0


@export var pan_speed := 1.0
@export var min_height := 0.0
@export var max_height := 1.5

var zoom := 2.0


# Node references
@onready var _viewport:  SubViewport  = $SubViewport
@onready var _rig:     Node3D         = $SubViewport/CameraRig # Horizontal rotation (yaw)
@onready var _pivot:     Node3D       = $SubViewport/CameraRig/CameraPivot # Pan vertically
@onready var _camera:    Camera3D     = $SubViewport/CameraRig/CameraPivot/Camera3D
@onready var _character: Node         = $SubViewport/Character # Injected by SceneGenerator


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
	update_camera_distance()


func _input(event):
	# --- Zoom ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom -= zoom_speed
			update_camera_distance()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom += zoom_speed
			update_camera_distance()

	# --- Rotate + Pan (Left Click Drag) ---
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			# Rotate
			_rig.rotate_y(-event.relative.x * rotation_speed)

			# Normalize by viewport height
			var pan_delta = (event.relative.y / _viewport.size.y) * pan_speed
			
			var new_y := clamp(
				_pivot.position.y + pan_delta,
				min_height,
				max_height
			)

			_pivot.position.y = new_y


func update_camera_distance():
	zoom = clamp(zoom, min_zoom, max_zoom)
	_camera.position = Vector3(0, 0, zoom)


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
#func _notification(what: int) -> void:
#	if what == NOTIFICATION_RESIZED:
#		var new_size := Vector2i(int(size.x), int(size.y))
#		$SubViewport.size = new_size
