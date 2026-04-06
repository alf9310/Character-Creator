## Drives an AnimationPlayer, used to let the player choose anr idle pose or expression preset. 
## It generates a row of buttons.
@tool
class_name AnimationOption
extends OptionDefinition

## NodePath to the AnimationPlayer. Relative to SubViewport root.
@export var animation_player_path: NodePath

## The animation to play. Must match a name in the AnimationPlayer's library.
@export var animation_name: String = ""

## If true, the animation loops and keeps playing in the preview.
## If false, it plays once and holds the final frame (useful for poses).
@export var loop_in_preview: bool = false

## If true, the animation is baked into the exported CharacterState
## as a pose (the player's choice persists in-game).
## If false, it's preview-only and not saved to CharacterState.
@export var include_in_export: bool = true

func _to_string() -> String:
	return "AnimationOption(%s | %s → %s | loop: %s | export: %s)" % [
		display_name, animation_player_path, animation_name,
		loop_in_preview, include_in_export
	]
