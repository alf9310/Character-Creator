# Source of truth for everything the developer has decided about their character creator. 
# Ex. Which mesh to use, which options to expose, and how the runtime scene should behave. 
@tool
class_name CharacterConfig
extends Resource

## The character scene to instantiate inside CharacterPreview.
@export var character_scene: PackedScene

## All options the developer has chosen to expose to the player.
## Populated by MeshInspector, curated by CharacterCreatorDock.
@export var options: Array[OptionDefinition] = []

# --- Runtime behaviour flags ---

## Show the 3D preview viewport in the generated scene.
@export var show_preview: bool = true

## Expose a Randomize button in the generated scene footer.
@export var allow_randomize: bool = true

## Emit a CharacterState .tres file when the player confirms.
@export var save_state_on_confirm: bool = true

## Where to write the CharacterState .tres on confirm.
## Relative to the user:// directory.
@export var state_save_path: String = "character_state.tres"

# --- Preview settings ---

## Distance of the preview camera from the character origin.
@export_range(0.5, 10.0, 0.1) var preview_camera_distance: float = 2.0

## Vertical offset of the preview camera's look-at target.
## Useful for framing faces (positive) vs full body (zero).
@export_range(-2.0, 2.0, 0.05) var preview_camera_height: float = 0.8

## Whether the player can orbit the preview camera.
@export var allow_preview_orbit: bool = true

# Each `OptionDefinition` in `config.options` is stored as an inline sub-resource inside the `.tres` file.
# Ex:
'''
[gd_resource type="CharacterConfig" format=3]

[sub_resource type="BlendshapeOption" id="BlendshapeOption_1"]
display_name = "face_fat"
group = "Face"
mesh_path = NodePath("Character/Body")
blend_shape_name = "face_fat"
default_value = 0.0
min_value = 0.0
max_value = 1.0

[sub_resource type="MeshSwapOption" id="MeshSwapOption_2"]
display_name = "Hair"
group = "Hair"
...

[resource]
character_scene = ExtResource("hero_character.tscn")
options = [SubResource("BlendshapeOption_1"), SubResource("MeshSwapOption_2"), ...]
show_preview = true
allow_randomize = true
preview_camera_distance = 2.0
preview_camera_height = 0.8
'''


func _to_string() -> String:
	var option_summary := ", ".join(
		options.map(func(o: OptionDefinition) -> String: return str(o))
	)
	return (
		"CharacterConfig(\n"
		+ "  scene: %s\n"            % (character_scene.resource_path.get_file() if character_scene else "none")
		+ "  options: [%s]\n"        % option_summary
		+ "  show_preview: %s\n"     % show_preview
		+ "  allow_randomize: %s\n"  % allow_randomize
		+ "  save_state: %s -> %s\n"  % [save_state_on_confirm, state_save_path]
		+ "  camera: dist=%.1f height=%.2f orbit=%s\n" % [preview_camera_distance, preview_camera_height, allow_preview_orbit]
		+ ")"
	)
