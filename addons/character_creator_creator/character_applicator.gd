# Applying state outside the creator scene to a character mesh elsewhere in the game
# TODO: Find a way to bake the mesh during runtime instead!!!
@tool
class_name CharacterApplicator
extends RefCounted

# Example Usage: 
# Somewhere in the game scene that spawns the player character
# var state  := ResourceLoader.load("user://character_state.tres") as CharacterState
# var config := preload("res://scenes/character_creator.config.tres") as CharacterConfig
# CharacterApplicator.apply(state, config, $PlayerCharacter)
static func apply(
		state: CharacterState,
		config: CharacterConfig,
		character_root: Node) -> void:

	# Build option map from config
	var option_map: Dictionary = {}
	for opt in config.options:
		option_map[opt.resource_name] = opt

	for option_id in state.blendshape_values:
		var opt := option_map.get(option_id) as BlendshapeOption
		if opt == null: continue
		var mesh := character_root.get_node(opt.mesh_path) as MeshInstance3D
		if mesh == null: continue
		var idx := mesh.find_blend_shape_by_name(opt.blend_shape_name)
		if idx != -1:
			mesh.set_blend_shape_value(idx, state.blendshape_values[option_id])

	for option_id in state.swap_choices:
		var opt := option_map.get(option_id) as MeshSwapOption
		if opt == null: continue
		var choice_idx: int = state.swap_choices[option_id]
		for i in range(opt.choices.size()):
			var node := character_root.get_node(opt.choices[i].node_path) as MeshInstance3D
			if node:
				node.visible = (i == choice_idx)

	for option_id in state.color_values:
		var opt := option_map.get(option_id) as ColorOption
		if opt == null: continue
		var mesh := character_root.get_node(opt.mesh_path) as MeshInstance3D
		if mesh == null: continue
		var mat := mesh.get_active_material(opt.surface_index)
		if mat is ShaderMaterial:
			mat.set_shader_parameter(opt.shader_param, state.color_values[option_id])
		elif mat is StandardMaterial3D:
			mat.albedo_color = state.color_values[option_id]

	for option_id in state.animation_choices:
		var opt := option_map.get(option_id) as AnimationOption
		if opt == null: continue
		var player := character_root.get_node(opt.animation_player_path) as AnimationPlayer
		if player and player.has_animation(state.animation_choices[option_id]):
			player.play(state.animation_choices[option_id])
			player.advance(player.get_animation(state.animation_choices[option_id]).length)
			player.pause()
