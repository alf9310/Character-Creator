@tool
class_name MeshSwapOption
extends OptionDefinition


## If at least one option must be selected
@export var required: bool = true

## The individual choices. Contains MeshSwapChoice(s).
@export var choices: Array[MeshSwapChoice] = []

## Index of the choice shown by default.
@export var default_choice: int = 0

func _to_string() -> String:
	var choice_labels := ", ".join(
		choices.map(func(c: MeshSwapChoice) -> String: return str(c) + "\n")
	)
	return "MeshSwapOption(%s | required: %s | default: %d | choices: [%s])" % [
		display_name, required, default_choice, choice_labels
	]
