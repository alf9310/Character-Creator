@tool
extends EditorPlugin

const DOCK_SCENE = preload("res://addons/character_creator_creator/editor/docks/character_creator_dock.tscn")

var _dock: CharacterCreatorDock

func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Instantiate and add the dock to the editor UI
	_dock = DOCK_SCENE.instantiate()
	# TODO: Make placement a plugin setting
	# TODO: Depreciated, use "add_dock()"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	
	# TODO: Register custom resource types so they appear in the "Add Resource" dialog with correct icons
	add_custom_type("CharacterConfig",      "Resource", preload("data/character_config.gd"),       preload("icons/character_config.svg"))
	add_custom_type("BlendshapeOption",     "Resource", preload("data/options/blendshape_option.gd"), preload("icons/option.svg"))
	add_custom_type("MeshSwapOption",       "Resource", preload("data/options/mesh_swap_option.gd"),  preload("icons/option.svg"))
	add_custom_type("ColorOption",          "Resource", preload("data/options/color_option.gd"),       preload("icons/option.svg"))
	add_custom_type("AnimationOption",      "Resource", preload("data/options/animation_option.gd"),   preload("icons/option.svg"))


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
		
	remove_custom_type("CharacterConfig")
	remove_custom_type("BlendshapeOption")
	remove_custom_type("MeshSwapOption")
	remove_custom_type("ColorOption")
	remove_custom_type("AnimationOption")
