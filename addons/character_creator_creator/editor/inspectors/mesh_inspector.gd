## Pure, stateless utility that takes a scene, walks the node tree, 
## and returns an Array[OptionDefinition]
@tool
class_name MeshInspector
extends RefCounted

## The scene is instantiated into a temporary node that lives only for the duration of the call
func inspect(packed_scene: PackedScene) -> Array[OptionDefinition]:
	var root := packed_scene.instantiate()
	var temp_host := Node.new()
	EditorInterface.get_edited_scene_root().add_child(temp_host)
	temp_host.add_child(root)

	var results: Array[OptionDefinition] = []
	var meshes := _find_meshes(root)
	
	if not meshes.is_empty():
		# Swap grouping is name-based across all meshes, not per-sibling
		results.append_array(_inspect_swap_slots(meshes, root))
		
		# Global trackers
		var global_seen_colors: Dictionary = {}
		var global_seen_blendshapes: Dictionary = {}
		var global_seen_atlases: Dictionary = {}
		
		for mesh in meshes:
			_inspect_blendshapes(mesh, root, global_seen_blendshapes, results)
			results.append_array(_inspect_materials(mesh, root, global_seen_colors, global_seen_atlases))
		
		results.append_array(_inspect_animations(root))
		
	temp_host.get_parent().remove_child(temp_host)
	temp_host.free()
	
	return results


## Swap Slots (Modular Meshes)
# Groups all meshes by the first token of their name, split on _ . , -
# "hair_long" → group "Hair", label "Long",  include = true
# "Body"      → group "Body", label "",      include = false
# TODO: Add custom flags for -default, -include, -required
static var _splitter := RegEx.create_from_string("[_.,\\-]+")

func _inspect_swap_slots(meshes: Array[MeshInstance3D], root: Node) -> Array[OptionDefinition]:
	print("Inspecting Mesh Swaps")
	var groups: Dictionary[String, Array] = {}
	
	# Go through all meshes and instantiate MeshSwapChoice(s)
	for mesh_node in meshes:
		var parts := _splitter.sub(mesh_node.name, "|", true).split("|", false)
		var group := parts[0].capitalize()

		var choice				:= MeshSwapChoice.new()
		choice.mesh_path 		= root.get_path_to(mesh_node)
		choice.default_choice	= not group in groups  # first mesh in group = default
		choice.label			= parts[1].capitalize() if parts.size() > 1 else ""
		choice.include			= parts.size() > 1

		if not group in groups:
			groups[group] = []
		groups[group].append(choice)
		
		print("\t%s -> group: %s  label: '%s'" % [mesh_node.name, group, choice.label])
	
	# Go through all the groups and instantiate MeshSwapGroups(s)
	var results: Array[OptionDefinition] = []
	for group: String in groups:
		var opt          := MeshSwapOption.new()
		opt.group         = group
		opt.default_choice = 0
		opt.include        = groups[group].size() > 1
		opt.required       = groups[group].size() > 1
		opt.choices.append_array(groups[group])
		results.append(opt)

	return results


func _find_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if node is MeshInstance3D and node.mesh != null:
			found.append(node)
	return found


## Blendshapes
func _inspect_blendshapes(mesh_node: MeshInstance3D, root: Node, global_seen: Dictionary, results: Array[OptionDefinition]) -> Array[OptionDefinition]:
	# TODO: Add debug flag
	print("Inspecting Mesh Blenshapes")
	var count := mesh_node.get_blend_shape_count()
	print("\tFound ", count, " blendshapes")
	
	# Parse group from mesh name (e.g. "Hair_Long" -> "Hair")
	var parts := _splitter.sub(mesh_node.name, "|", true).split("|", false)
	var group_name := parts[0].capitalize()

	for i in range(count):
		# NOTE: MeshInstance3D does NOT have this method, need to ref Mesh
		var shape_name = mesh_node.mesh.get_blend_shape_name(i)
		# Skip Blender's internal reset shapes
		if shape_name.begins_with("_") or shape_name.to_upper() == "BASIS":
			continue
		
		if global_seen.has(shape_name):
			# ALREADY EXISTS: Just adds mesh to the target array
			var existing_opt: BlendshapeOption = global_seen[shape_name]
			existing_opt.mesh_paths.append(root.get_path_to(mesh_node))
			
			# Record that this blendshape also belongs in this new group
			if not group_name in existing_opt.editor_groups:
				existing_opt.editor_groups.append(group_name)
		else:
			print("\tAdding bendshape ", shape_name)
			# New blendshape: Create option and register
			var opt := BlendshapeOption.new()
			opt.display_name    = shape_name.replace("_", " ").capitalize()
			opt.group            = group_name
			opt.mesh_paths       = [root.get_path_to(mesh_node)]
			opt.blend_shape_name = shape_name
			opt.default_value   = mesh_node.get_blend_shape_value(i)
			opt.min_value       = 0.0
			opt.max_value       = 1.0
			# Start the tracker with the first group it was found in
			opt.editor_groups    = [group_name]
			
			global_seen[shape_name] = opt
			results.append(opt)

	return results
	
	
## Color Parameters & Texture Atlas
# NOTE: Color Atlas needs to be named with the convention "Atlas_rows_cols_*"
# TODO: Refactor this implementation to be purely blender-uv defined
# Walks every surface on every MeshInstance3D and looks for color-type shader parameters on ShaderMaterial, falling back to standard albedo/emission on StandardMaterial3D
func _inspect_materials(mesh_node: MeshInstance3D, root: Node, global_colors: Dictionary, global_atlases: Dictionary) -> Array[OptionDefinition]:
	print("Inspecting Materials for ", mesh_node.name)
	var results: Array[OptionDefinition] = []
	
	# Parse group from mesh name
	var parts := _splitter.sub(mesh_node.name, "|", true).split("|", false)
	var group_name := parts[0].capitalize()

	for surface_idx in range(mesh_node.get_surface_override_material_count()):
		var mat := mesh_node.get_active_material(surface_idx)
		if mat == null: continue
		var mat_name := mat.resource_name
		var mat_id := str(mat.get_instance_id())
		
		# ATLAS DETECTION (ex: "Atlas_4_1_Eye_Shapes")
		if mat_name.begins_with("Atlas_"):
			var signature := group_name + "::" + mat_name

			if global_atlases.has(signature):
				var existing_opt: TextureAtlasOption = global_atlases[signature]
				if not root.get_path_to(mesh_node) in existing_opt.mesh_paths:
					existing_opt.mesh_paths.append(root.get_path_to(mesh_node))
				if not group_name in existing_opt.editor_groups:
					existing_opt.editor_groups.append(group_name)
				continue
				
			var tokens := mat_name.split("_", false)
			# Ensure the name has enough data (Atlas, Cols, Rows, Name)
			if tokens.size() >= 4:
				var opt := TextureAtlasOption.new()
				opt.columns       = tokens[1].to_int()
				opt.rows          = tokens[2].to_int()

				# Rejoin the remaining tokens for the display name (in case the name had underscores)
				var display_tokens = tokens.slice(3)
				opt.display_name  = " ".join(display_tokens).capitalize()

				opt.group         = group_name
				opt.editor_groups = [group_name]
				opt.mesh_paths    = [root.get_path_to(mesh_node)]
				opt.surface_index = surface_idx
				opt.apply_to_shared_material = true

				# StandardMaterial3D automatically uses uv1_offset. 
				# If using a Shader, assume the dev named the uniform 'uv_offset'
				opt.shader_param  = "uv_offset" if mat is ShaderMaterial else ""

				# Generate placeholder UI labels based on grid size
				var total_options = opt.columns * opt.rows
				for i in range(total_options):
					opt.choice_labels.append("Style " + str(i + 1))

				global_atlases[signature] = opt
				results.append(opt)
			else:
				push_warning("Material '%s' starts with 'Atlas_' but is formatted incorrectly. Use Atlas_Cols_Rows_Name." % mat_name)

			continue # Skip color processing for this material
	
		# COLOR DETECTION
		if mat is ShaderMaterial:
			print("Found a ShaderMaterial")
			var shader = mat.shader
			if shader == null: 
				continue
				
			for param in shader.get_shader_uniform_list():
				if param["hint"] == PROPERTY_HINT_COLOR_NO_ALPHA \
				#or param["hint"] == PROPERTY_HINT_COLOR \
				or param["type"] == TYPE_COLOR:
					var pname: String = param["name"]
					
					# Unique signature for this color parameter within this group
					var signature := group_name + "::" + pname
					if global_colors.has(signature):
						var existing_opt: ColorOption = global_colors[signature]
						if not root.get_path_to(mesh_node) in existing_opt.mesh_paths:
							existing_opt.mesh_paths.append(root.get_path_to(mesh_node))
						if not group_name in existing_opt.editor_groups:
							existing_opt.editor_groups.append(group_name)
						continue
					
					print("\tAdding color ", pname)
					
					var opt := ColorOption.new()
					opt.display_name   = pname.replace("_", " ").capitalize()
					opt.group          = group_name
					opt.editor_groups            = [group_name]
					opt.mesh_paths      = [root.get_path_to(mesh_node)]
					opt.shader_param   = pname
					opt.default_color  = mat.get_shader_parameter(pname)
					# Flag this so the exporter knows to color all meshes sharing this material!
					opt.apply_to_shared_material = true
					opt.surface_index            = surface_idx
					
					global_colors[signature] = opt
					results.append(opt)
		
		elif mat is StandardMaterial3D:
			# 1. Signature for standard materials
			var signature := group_name + "::albedo_color"
			if global_colors.has(signature):
				var existing_opt: ColorOption = global_colors[signature]
				if not root.get_path_to(mesh_node) in existing_opt.mesh_paths:
					existing_opt.mesh_paths.append(root.get_path_to(mesh_node))
				if not group_name in existing_opt.editor_groups:
					existing_opt.editor_groups.append(group_name)
				continue
			
			print("Found a StandardMaterial3D")
			# Expose albedo and emission as the two most useful color options
			var albedo := ColorOption.new()
			# Dynamic naming (e.g. "Hair Color", "Body Color")
			albedo.display_name  = group_name + " Color"
			albedo.group         = group_name
			albedo.editor_groups            = [group_name]
			albedo.mesh_paths     = [root.get_path_to(mesh_node)]
			albedo.shader_param  = "albedo_color"
			albedo.default_color = mat.albedo_color
			albedo.apply_to_shared_material = true
			albedo.surface_index            = surface_idx
			
			global_colors[signature] = albedo
			results.append(albedo)

	return results
	
## Animations
# TODO: Add bone deformation animations "bd_"
# AnimationPlayer nodes are found anywhere in the tree, not just on the root mesh. 
# The inspector then filters the animation list to exclude internal tracks
func _inspect_animations(root: Node) -> Array[OptionDefinition]:
	print("Inspecting Mesh Animations")
	var results: Array[OptionDefinition] = []

	for player in root.find_children("*", "AnimationPlayer", true, false):
		if not player is AnimationPlayer:
			continue

		for anim_name in player.get_animation_list():
			# Skip Godot's built-in RESET animation and any _-prefixed internals
			if anim_name == "RESET" or anim_name.begins_with("_"):
				continue
			print("\tAdding animation ", anim_name)

			var opt := AnimationOption.new()
			opt.display_name          = anim_name.replace("_", " ").capitalize()
			# Group all animations into a unified "Poses" tab
			opt.group                 = "Poses"
			opt.animation_player_path = root.get_path_to(player)
			opt.animation_name        = anim_name
			# TODO: Smart loop detection
			opt.loop_in_preview       = true
			results.append(opt)

	return results
