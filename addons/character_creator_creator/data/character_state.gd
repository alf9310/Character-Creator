# Holds no references to nodes, meshes, or materials
# Ex: Can be used interchangably between different meshes with the same names!
@tool
class_name CharacterState
extends Resource

## Mesh swap selections. Key = option resource_name, value = int choice index.
@export var swap_choices: Dictionary[String, int] = {}

## Blendshape weights. Key = option resource_name, value = float 0.0–1.0.
@export var blendshape_values: Dictionary[String, float] = {}

## Color selections. Key = option resource_name, value = Color.
@export var color_values: Dictionary[String, Color] = {}

## Animation selections. Key = option resource_name, value = String animation_name.
## Only populated for AnimationOptions with include_in_export = true.
@export var animation_choices: Dictionary[String, String] = {}

## Timestamp of the last modification. Useful for save slot UIs.
@export var last_modified: int = 0

## Arbitrary developer-defined metadata. Use this to attach things like
## character name, class, or faction without subclassing CharacterState.
@export var metadata: Dictionary = {}

static func from_config(config: CharacterConfig) -> CharacterState:
	var state := CharacterState.new()

	for opt in config.options:
		if opt is BlendshapeOption:
			state.blendshape_values[opt.resource_name] = opt.default_value
		elif opt is MeshSwapOption:
			state.swap_choices[opt.resource_name] = opt.default_choice
		elif opt is ColorOption:
			state.color_values[opt.resource_name] = opt.default_color
		elif opt is TextureAtlasOption:
			state.swap_choices[opt.resource_name] = opt.default_choice
		elif opt is AnimationOption:
			if opt.include_in_export and opt.is_default:
				state.animation_choices[opt.resource_name] = opt.animation_name

	state.last_modified = Time.get_unix_time_from_system()
	return state

# Keeps the state in sync
func record(option_id: String, value: Variant) -> void:
	# Determine which dictionary to write based on the value type
	match typeof(value):
		TYPE_FLOAT, TYPE_INT when value is float:
			blendshape_values[option_id] = float(value)
		TYPE_INT:
			swap_choices[option_id] = int(value)
		TYPE_COLOR:
			color_values[option_id] = value as Color
		TYPE_STRING:
			animation_choices[option_id] = value as String

	last_modified = Time.get_unix_time_from_system()

# Generates new values using the constraints baked into each OptionDefinition
static func randomized(config: CharacterConfig) -> CharacterState:
	var state := CharacterState.new()

	for opt in config.options:
		if opt is BlendshapeOption:
			state.blendshape_values[opt.resource_name] = randf_range(
			opt.min_value, opt.max_value
			)
		elif opt is MeshSwapOption:
			state.swap_choices[opt.resource_name] = randi() % opt.choices.size()
		elif opt is ColorOption:
			# Randomize only hue, preserve reasonable saturation and value
			# to avoid outputting unreadable or invisible colors
			# TODO: expose these as fields on CharacterConfig for games that want a wider or narrower palette
			var h := randf()
			var s := randf_range(0.0, 0.7)
			var v := randf_range(0.4, 0.95)
			state.color_values[opt.resource_name] = Color.from_hsv(h, s, v)
		elif opt is TextureAtlasOption:
			state.swap_choices[opt.resource_name] = randi() % opt.choice_labels.size()

	state.last_modified = Time.get_unix_time_from_system()
	return state
