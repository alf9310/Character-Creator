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
		# TODO: restore blendshape / color / animation passes
		for mesh in meshes:
			results.append_array(_inspect_blendshapes(mesh, root))

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
func _inspect_blendshapes(mesh_node: MeshInstance3D, root: Node) -> Array[OptionDefinition]:
	# TODO: Add debug flag
	print("Inspecting Mesh Blenshapes")
	var results: Array[OptionDefinition] = []
	var count := mesh_node.get_blend_shape_count()
	print("\tFound ", count, " blendshapes")

	for i in range(count):
		# NOTE: MeshInstance3D does NOT have this method, need to ref Mesh
		var shape_name = mesh_node.mesh.get_blend_shape_name(i)
		print("\tAdding bendshape ", shape_name)

		# Skip Blender's internal reset shapes
		if shape_name.begins_with("_") or shape_name.to_upper() == "BASIS":
			continue

		var opt := BlendshapeOption.new()
		opt.display_name    = shape_name
		opt.mesh_path       = root.get_path_to(mesh_node)
		opt.blend_shape_name = shape_name
		opt.default_value   = mesh_node.get_blend_shape_value(i)
		opt.min_value       = 0.0
		opt.max_value       = 1.0
		results.append(opt)

	return results
	
	
## Color Parameters
# TODO: Refactor this implementation to be purely blender-uv defined
# Walks every surface on every MeshInstance3D and looks for color-type shader parameters on ShaderMaterial, falling back to standard albedo/emission on StandardMaterial3D
func _inspect_color_params(mesh_node: MeshInstance3D, root: Node) -> Array[OptionDefinition]:
	print("Inspecting Mesh Colors")
	var results: Array[OptionDefinition] = []
	var seen: Dictionary = {}  # guard against duplicate params across surfaces

	for surface_idx in range(mesh_node.get_surface_override_material_count()):
		var mat := mesh_node.get_active_material(surface_idx)

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
					print("\tAdding color ", pname)
					if seen.has(pname):
						continue
					seen[pname] = true
					var opt := ColorOption.new()
					opt.display_name   = pname.replace("_", " ").capitalize()
					opt.mesh_path      = root.get_path_to(mesh_node)
					opt.shader_param   = pname
					opt.default_color  = mat.get_shader_parameter(pname)
					results.append(opt)

		# TODO: Change skin-color option
		elif mat is StandardMaterial3D:
			print("Found a StandardMaterial3D")
			# Expose albedo and emission as the two most useful color options
			var albedo := ColorOption.new()
			albedo.display_name  = "Skin color"
			albedo.mesh_path     = root.get_path_to(mesh_node)
			albedo.shader_param  = "albedo_color"
			albedo.default_color = mat.albedo_color
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
			opt.animation_player_path = player.get_path()
			opt.animation_name        = anim_name
			results.append(opt)

	return results
	
## Deduplication pass
# If the character has multiple MeshInstance3D nodes, blendshape names may collide. 
# The dedup pass uses mesh_path + display_name as a compound key
func _deduplicate(options: Array[OptionDefinition]) -> Array[OptionDefinition]:
	var seen: Dictionary = {}
	var out: Array[OptionDefinition] = []

	for opt in options:
		var key: String
		if opt is MeshSwapOption:
			key = "%s::swap::%s" % [str(opt.mesh_path), opt.display_name]
		else:
			key = "%s::%s" % [str(opt.mesh_path), opt.display_name]

		if not seen.has(key):
			seen[key] = true
			out.append(opt)

	return out
