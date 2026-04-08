# A bridge between the editor and runtime.
# It takes a finalized CharacterConfig and writes a fully-wired .tscn file to disk 
# that the developer can drop into their project.

@tool
class_name SceneGenerator
extends RefCounted

# Root node is constructed entirely in memory until _save() packs and writes it
func generate(config: CharacterConfig, out_path: String) -> Error:
	if not _validate(config):
		return ERR_INVALID_PARAMETER

	var root := _build_base_tree(config)
	_generate_ui(root, config)

	var err := _save(root, config, out_path)
	root.free()
	return err

## Creates the four runtime nodes and configures each from config
func _build_base_tree(config: CharacterConfig) -> Node:
	print("Building the base CharacterCreator Scene tree")
	var root := Node.new()
	root.name = "CharacterCreator"
	root.set_script(
		load("res://addons/character_creator_creator/runtime/character_creator.gd")
	)
	
	# Store config as a typed property
	root.config = config

	# CharacterPreview (SubViewportContainer + internals)
	if config.show_preview:
		print("\tAdding the CharacterPreview")
		var preview := preload(
		    "res://addons/character_creator_creator/runtime/character_preview.tscn"
		).instantiate()
		preview.name = "CharacterPreview"

		var viewport := preview.get_node_or_null("SubViewport")
		# Error Checking
		if viewport == null:
			push_error("[SceneGenerator] CharacterPreview.tscn has no SubViewport node — check the scene.")
			return root

		if config.character_scene == null:
			push_error("[SceneGenerator] config.character_scene is null — was the config saved correctly?")
			return root
		
		# Inject the character mesh as a child of the SubViewport
		print("\tCharacter scene path: ", config.character_scene.resource_path)
		var character := config.character_scene.instantiate()
		if character == null:
			push_error("[SceneGenerator] Failed to instantiate character scene.")
			return root
	
		character.name = "Character"
		
		print("\tCharacter instantiated: ", character.name)
		# Add children
		#if character.get_parent():
		#	character.get_parent().remove_child(character)
		viewport.add_child(character)
		root.add_child(preview)
		
		# Unwrap the CharacterPreview so Godot is allowed to save the character inside its SubViewport
		_unwrap_and_bind(preview, root, character)

		# Bind the character instance to the root (but don't unwrap its internals!)
		character.owner = root
		
		# Set owners
		#preview.owner = root
		#_set_owners(character, root)
		
		root.preview = preview
		print("\tOwners set on character subtree")


	# CreatorUI (VBoxContainer — populated in stage 2)
	print("\tAdding the CreatorUI")
	var ui := VBoxContainer.new()
	ui.name = "CreatorUI"
	ui.set_script(
		load("res://addons/character_creator_creator/runtime/creator_ui.gd")
	)
	root.add_child(ui)
	ui.owner = root
	root.ui   = ui

	# CharacterExporter
	print("\tAdding the CharacterExporter")
	var exporter := Node.new()
	exporter.name = "CharacterExporter"
	exporter.set_script(
		load("res://addons/character_creator_creator/runtime/character_exporter.gd")
	)
	root.add_child(exporter)
	exporter.owner = root
	root.exporter   = exporter

	return root

# Delegates to UIGenerator to build the tab/group structure and individual control nodes.
func _generate_ui(root: Node, config: CharacterConfig) -> void:
	print("Generating the CharacterCreator UI")
	var ui := root.get_node("CreatorUI")
	var ui_gen := UIGenerator.new()
	ui_gen.build(ui, config.options, root)


# Serialization
func _save(root: Node, config: CharacterConfig, out_path: String) -> Error:
	print("Serializing CharacterCreator as a PackedScene")
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		push_error("[SceneGenerator] Failed to pack scene: %d" % pack_err)
		return pack_err

	var scene_err := ResourceSaver.save(packed, out_path)
	if scene_err != OK:
		push_error("[SceneGenerator] Failed to save scene to %s: %d" % [out_path, scene_err])
		return scene_err

	# Save the config .tres alongside the scene so it can be reloaded
	# by the dock on re-open, and inspected by the developer
	var config_path := out_path.get_basename() + ".config.tres"
	var config_err  := ResourceSaver.save(config, config_path)
	if config_err != OK:
		push_warning("[SceneGenerator] Scene saved but config .tres failed: %d" % config_err)

	# Notify the editor filesystem so the new file appears immediately
	EditorInterface.get_resource_filesystem().scan()

	return OK

# Validation 
# Catches configuration mistakes before any node construction begins
func _validate(config: CharacterConfig) -> bool:
	if config.character_scene == null:
		push_error("[SceneGenerator] CharacterConfig has no character_scene set.")
		return false
	if config.options.is_empty():
		push_error("[SceneGenerator] CharacterConfig has no options — nothing to generate.")
		return false
	var ids := {}
	for opt in config.options:
		if opt.resource_name.is_empty():
			push_error("[SceneGenerator] An OptionDefinition has an empty display_name.")
			return false
		# Check for duplicate resource names
		if ids.has(opt.resource_name):
			push_error("[CharacterConfig] Duplicate resource_name: '%s'." % opt.resource_name)
			return false
		ids[opt.resource_name] = true
	return true

## Recursively sets node owners to scene_root and clears their scene_file_path 
## so they are saved directly in the .tscn instead of remaining an external instance.
func _unwrap_and_bind(node: Node, scene_root: Node, ignore_node: Node) -> void:
	node.owner = scene_root
	node.scene_file_path = "" # Breaks the instance link so children can be saved inside it

	for child in node.get_children():
		if child != ignore_node:
			_unwrap_and_bind(child, scene_root, ignore_node)

# Walks a subtree and sets .owner on every node that doesn't already have one.
# Nodes from packed scenes carry their own owner so only new nodes need this.
# TODO: Duplicated in ui_generator.gd as it's a non-static function
func _set_owners(node: Node, scene_root: Node) -> void:
	node.owner = scene_root
	for child in node.get_children():
		_set_owners(child, scene_root)
