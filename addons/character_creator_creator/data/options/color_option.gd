## Drives a color parameter on a material, producing a ColorPickerButton, 
## Handles both ShaderMaterial custom uniforms and StandardMaterial3D built-in properties.
@tool
class_name ColorOption
extends OptionDefinition

## NodePath to the MeshInstance3D whose material contains this parameter.
@export var mesh_path: NodePath

## Surface index on the mesh to target. -1 means apply to all surfaces.
@export var surface_index: int = 0

## For ShaderMaterial: the uniform name as declared in the shader.
## For StandardMaterial3D: one of the recognised property names below.
@export var shader_param: String = ""

@export var default_color: Color = Color.WHITE

## If true, also update the material on any other MeshInstance3D nodes
## that share the same material resource (e.g. eyelashes sharing skin material).
@export var apply_to_shared_material: bool = false

func _to_string() -> String:
	return "ColorOption(%s | %s surface:%d | param: %s | default: %s | shared: %s)" % [
		display_name, mesh_path, surface_index,
		shader_param, default_color.to_html(), apply_to_shared_material
	]
