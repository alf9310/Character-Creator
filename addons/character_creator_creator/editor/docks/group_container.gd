@tool
extends Control
class_name GroupContainer

@onready var _include_group		: CheckBox		= %IncludeGroup
@onready var _group_field		: LineEdit		= %GroupField
@onready var _required			: CheckBox		= %Required

# Ideally Group Container would be in charge of setting up it's option rows
# BUT Godot's UI SUCKS with dynamically expanding the size of containers with
# nested scenes, SO this is the current work-around
var _owned_rows: Array[OptionRow] = []

func setup(opt: MeshSwapOption) -> void:
	_include_group.button_pressed	= opt.include
	_group_field.text				= opt.group
	_required.button_pressed		= opt.required

func register_rows(rows: Array[OptionRow]) -> void:
	_owned_rows = rows
	# Sync initial visibility with the checkbox state
	_set_rows_visible(_include_group.button_pressed)

func _set_rows_visible(visible: bool) -> void:
	for row in _owned_rows:
		row.visible = visible

func get_config_option() -> MeshSwapOption:
	if not _include_group.button_pressed:
		return null

	var opt           := MeshSwapOption.new()
	opt.group         = _group_field.text
	opt.required      = _required.button_pressed
	opt.include       = true
	
	var explicitly_selected_default := false
	var current_index := 0

	# Append all the developer-selected choices and look for a checked "Default" box
	for row in _owned_rows:
		var choice := row.get_choice()
		if choice != null:
			opt.choices.append(choice)
			
			# If this row is marked as the default, save its index
			if choice.default_choice and not explicitly_selected_default:
				opt.default_choice = current_index
				explicitly_selected_default = true

			current_index += 1

	# If the group is NOT required, inject a "None" choice at the front
	if not opt.required:
		var none_choice := MeshSwapChoice.new()
		none_choice.label = "None"
		none_choice.include = true
		none_choice.mesh_path = NodePath("") 

		opt.choices.push_front(none_choice)

		# Route the default logic
		if explicitly_selected_default:
			# Shift the index up by 1 so it still points to the developer's chosen mesh
			opt.default_choice += 1
		else:
			# No default was checked. Make "None" (which is now at index 0) the default!
			opt.default_choice = 0

	return opt

func _on_include_group_toggled(toggled_on: bool) -> void:
	_set_rows_visible(toggled_on)
