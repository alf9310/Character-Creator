@tool
extends Control
class_name OptionRow

# Inspector nodes (set in .tscn)
@onready var _include_option:	CheckBox	= %IncludeOption
@onready var _display_name:		LineEdit	= %DisplayName
@onready var _type_badge:		Label		= %TypeBadge
@onready var _default:			CheckBox	= %Default # (only one can be selected at once per group)

var _mesh_path: NodePath

func setup(option: OptionDefinition) -> void:
	_include_option.button_pressed = true
	_display_name.text = option.display_name
	_type_badge.text = _type_string(option)
	# TODO: Add mesh path for some
	
# Used by GroupContainer for individual swap choices
func setup_choice(choice: MeshSwapChoice, group: String) -> void:
	_include_option.button_pressed	= choice.include
	_display_name.text				= choice.label
	_type_badge.text				= "swap"
	_default.button_pressed 		= choice.default_choice
	_mesh_path						= choice.mesh_path

# Get the type of the OptionDefinition as a string
func _type_string(opt: OptionDefinition) -> String:
	if opt is ColorOption:			return "color"
	if opt is AnimationOption:		return "anim"
	if opt is MeshSwapOption:		return "swap"
	if opt is BlendshapeOption:		return "blend"
	return "not_recognized"

func get_choice() -> MeshSwapChoice:
	if not _include_option.button_pressed:
		return null
	var choice            := MeshSwapChoice.new()
	choice.label           = _display_name.text
	choice.include         = true
	choice.default_choice  = _default.button_pressed
	choice.mesh_path       = _mesh_path
	return choice
