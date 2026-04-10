@tool
class_name TextureAtlasOption
extends OptionDefinition

## Array of NodePaths to the MeshInstance3D nodes.
@export var mesh_paths: Array[NodePath] = []

## Surface index on the mesh to target.
@export var surface_index: int = 0

## How many options are in a horizontal row
@export var columns: int = 4

## How many rows of options (Usually 1 for a single horizontal strip)
@export var rows: int = 1

## The labels for the UI buttons (e.g. ["Almond", "Round", "Cat", "Droopy"])
## The size of this array determines how many buttons are generated.
@export var choice_labels: Array[String] = []

@export var default_choice: int = 0

## If true, modifying this material alters all meshes sharing it.
@export var apply_to_shared_material: bool = true

@export var editor_groups: Array[String] = []

## For ShaderMaterial: the uniform name for UV offset (usually a vec2 or vec3).
## For StandardMaterial3D: leave blank, it will automatically use uv1_offset.
@export var shader_param: String = ""

func _to_string() -> String:
	return "TextureAtlasOption(%s | meshes:%d | col:%d row:%d)" % [
		display_name, mesh_paths.size(), columns, rows
	]
