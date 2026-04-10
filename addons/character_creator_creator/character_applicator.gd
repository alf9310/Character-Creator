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
		
		for path in opt.mesh_paths:
			var mesh := character_root.get_node_or_null(path) as MeshInstance3D
			if mesh == null: continue
			
			var idx := mesh.find_blend_shape_by_name(opt.blend_shape_name)
			if idx != -1:
				mesh.set_blend_shape_value(idx, state.blendshape_values[option_id])
	
	# MeshSwapOption & TextureAtlasOption
	for option_id in state.swap_choices:
		var opt := option_map.get(option_id)

		if opt is MeshSwapOption:
			var choice_idx: int = state.swap_choices[option_id]
			for i in range(opt.choices.size()):
				var node := character_root.get_node_or_null(opt.choices[i].mesh_path) as MeshInstance3D
				if node:
					node.visible = (i == choice_idx)

		elif opt is TextureAtlasOption:
			var choice_idx: int = state.swap_choices[option_id]
			var uv_width := 1.0 / float(opt.columns)
			var uv_height := 1.0 / float(opt.rows)
			var offset := Vector3((choice_idx % opt.columns) * uv_width, (choice_idx / opt.columns) * uv_height, 0.0)

			for path in opt.mesh_paths:
				var mesh := character_root.get_node_or_null(path) as MeshInstance3D
				if mesh == null: continue
				var mat := mesh.get_active_material(opt.surface_index)
				if mat is StandardMaterial3D:
					mat.uv1_offset = offset
				elif mat is ShaderMaterial:
					mat.set_shader_parameter(opt.shader_param, Vector2(offset.x, offset.y))

	for option_id in state.color_values:
		var opt := option_map.get(option_id) as ColorOption
		if opt == null: continue
		
		for path in opt.mesh_paths:
			var mesh := character_root.get_node_or_null(path) as MeshInstance3D
			if mesh == null: continue
			
			# Helper logic to apply to all surfaces if index is -1
			var start_idx = 0 if opt.surface_index == -1 else opt.surface_index
			var end_idx = mesh.get_surface_override_material_count() - 1 if opt.surface_index == -1 else opt.surface_index

			for i in range(start_idx, end_idx + 1):
				var mat := mesh.get_active_material(i)
				if mat is ShaderMaterial:
					mat.set_shader_parameter(opt.shader_param, state.color_values[option_id])
				elif mat is StandardMaterial3D:
					# Note: You can expand this match statement if you use Emission/etc in game
					if opt.shader_param == "albedo_color":
						mat.albedo_color = state.color_values[option_id]

	for option_id in state.animation_choices:
		var opt := option_map.get(option_id) as AnimationOption
		if opt == null: continue
		var player := character_root.get_node(opt.animation_player_path) as AnimationPlayer
		if player and player.has_animation(state.animation_choices[option_id]):
			player.play(state.animation_choices[option_id])
			player.advance(player.get_animation(state.animation_choices[option_id]).length)
			player.pause()
