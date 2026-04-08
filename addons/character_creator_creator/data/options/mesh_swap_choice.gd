## Companion resource of MeshSwapOption, 
## which the option owns as an array of inline sub-resources.
@tool
class_name MeshSwapChoice
extends Resource

## If this Option should be included as a selectable parameter or not in the UI
@export var include: bool = true

## Label shown on the generated button.
@export var label: String = ""

# NOTE: Mesh swap option stores default as the label name
## If the choice shown on the character by default.
@export var default_choice: bool = false

## NodePath to the MeshInstance3D for this choice.
## The node is shown when this choice is selected; all siblings are hidden.
# NOTE: Store a path instead of a Mesh Resource reference to keep 
# per-node material overrides, skeleton bindings & other node-level data
@export var mesh_path: NodePath

func _to_string() -> String:
	return "Choice(%s | path: %s | default: %s | include: %s)" % [
		label, mesh_path, default_choice, include
	]
