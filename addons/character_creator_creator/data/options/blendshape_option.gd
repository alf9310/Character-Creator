## Drives a single blendshape weight via an HSlider. Maps to Blender shape keys.
@tool
class_name BlendshapeOption
extends OptionDefinition

## Array of NodePaths to the MeshInstance3D nodes that share this blendshape.
@export var mesh_paths: Array[NodePath] = []

## Tracks all the mesh groups this shape appears in, used by the editor dock.
@export var editor_groups: Array[String] = []

## The exact string returned by get_blend_shape_name() for this shape.
@export var blend_shape_name: String

@export_range(0.0, 1.0, 0.01) var default_value: float = 0.0
@export_range(0.0, 1.0, 0.01) var min_value: float = 0.0
@export_range(0.0, 1.0, 0.01) var max_value: float = 1.0


func _to_string() -> String:
	return "BlendshapeOption(%s | %s::%s | default: %.2f [%.2f–%.2f])" % [
		display_name, mesh_paths.size(), blend_shape_name,
		default_value, min_value, max_value
	]
