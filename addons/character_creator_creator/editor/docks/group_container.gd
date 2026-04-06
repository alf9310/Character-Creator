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
	var opt          := MeshSwapOption.new()
	opt.group         = _group_field.text
	opt.required      = _required.button_pressed
	opt.include       = true
	for row in _owned_rows:
		var choice := row.get_choice()
		if choice != null:
			opt.choices.append(choice)
	return opt

func _on_include_group_toggled(toggled_on: bool) -> void:
	_set_rows_visible(toggled_on)
