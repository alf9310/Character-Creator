# "Abstract" parent of Option classes: 
# BlendshapeOption, MeshSwapOption, ColorOption, AnimationOption
@tool
class_name OptionDefinition
extends Resource

## Human-readable label shown in the generated UI.
@export var display_name: String = ""

## If this Option should be included as a selectable parameter or not in the UI
@export var include: bool = true

## Which tab this option appears under in the TabContainer.
@export var group: String = ""

## Stable identifier used by CharacterExporter to route UI events.
## Set by CharacterCreatorDock before passing config to SceneGenerator.
## Must be unique within a CharacterConfig.
# TODO: How to set here without redefining
# @export var resource_name: String = ""

func _to_string() -> String:
	return "Option(%s | group: %s | include: %s)" % [display_name, group, include]
