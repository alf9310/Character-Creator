@tool
extends Control
class_name CharacterCreatorDock

signal scene_generated(path: String)

const GroupContainerScene = preload("res://addons/character_creator_creator/editor/docks/group_container.tscn")
const OptionRowScene = preload("res://addons/character_creator_creator/editor/docks/option_row.tscn")

# Inspector nodes (set in .tscn)
@onready var _input_path:		LineEdit		= %InputPath
@onready var _input_dialog:		FileDialog		= %InputDialog
@onready var _status_label:		Label			= %StatusLabel

@onready var _options_list:		VBoxContainer	= %OptionsList
@onready var _mesh_swaps_list:	VBoxContainer	= %MeshSwapsList

@onready var _allow_random:		CheckBox		= %AllowRandomize
@onready var _show_preview:		CheckBox		= %ShowPreview
@onready var _save_state:		CheckBox		= %SaveState

@onready var _output_path:		LineEdit		= %OutputPath
@onready var _output_dialog:	FileDialog		= %OutputDialog
@onready var _generate_btn:		Button			= %GenerateButton

var _current_scene_path: String = ""
var _detected_options: Array[OptionDefinition] = []

# Phase 1: Mesh Loading
## When the developer picks a file, run MeshInspector and populates the options list:
func _on_input_button_pressed() -> void:
	_input_dialog.popup_centered_ratio(0.6)

func _on_input_dialog_file_selected(path: String) -> void:
	_current_scene_path = path
	_input_path.text = path.get_file()

	var inspector := MeshInspector.new()
	var character_tscn : Resource = load(path)
	_detected_options = inspector.inspect(character_tscn)

	_status_label.text = "%d options detected" % _detected_options.size()
	_status_label.add_theme_color_override(
		"font_color",
		Color.GREEN if _detected_options.size() > 0 else Color.YELLOW
	)
	
	_rebuild_options_list()

# Phase 2: Options List
## Each detected OptionDefinition gets its own OptionRow scene 
func _rebuild_options_list() -> void:
	for child in _mesh_swaps_list.get_children():
		child.queue_free()

	for opt in _detected_options:
		if opt is MeshSwapOption:
			# Swap groups get their own collapsible group with child rows
			var group: GroupContainer = GroupContainerScene.instantiate()
			_mesh_swaps_list.add_child(group)
			group.setup(opt)
			
			# One OptionRow per choice inside this group
			var rows: Array[OptionRow] = []
			for choice: MeshSwapChoice in opt.choices:
				var row: OptionRow = OptionRowScene.instantiate()
				_mesh_swaps_list.add_child(row)
				row.setup_choice(choice, opt.group)
				rows.append(row)
				
			group.register_rows(rows)
		#else:
			# Blendshapes, colors, animations remain flat rows
			#var row: OptionRow = OptionRowScene.instantiate()
			#_mesh_swaps_list.add_child(row)
			#row.setup(opt)
		# row.changed.connect(_on_option_row_changed)
		# TODO: Fix this signal connection
		
func _on_mesh_swaps_toggled(toggled_on: bool) -> void:
	_mesh_swaps_list.visible = toggled_on

# Phase 3: Character Config
func _on_output_button_pressed() -> void:
	_output_dialog.popup_centered_ratio(0.6)

func _on_output_dialog_file_selected(path: String) -> void:
	_output_path.text = path.get_file()


## Click "Generate Scene": The dock gathers the state of all rows into a CharacterConfig resource, 
## then hands it to SceneGenerator
func _on_generate_button_pressed() -> void:
	if _current_scene_path.is_empty():
		push_error("No character scene selected.")
		return

	var config := CharacterConfig.new()
	config.character_scene  		= load(_current_scene_path)
	config.allow_randomize  		= _allow_random.button_pressed
	config.save_state_on_confirm	= _save_state.button_pressed
	config.show_preview     		= _show_preview.button_pressed

	for child in _mesh_swaps_list.get_children():
		if not child is GroupContainer:
			continue
		var opt: MeshSwapOption = child.get_config_option()
		if opt != null:
			config.options.append(opt)

	if config.options.is_empty():
		push_error("No options selected.")
		return
	
	# Assigns resource_name before passing the config to SceneGenerator
	# (MeshInspector produces OptionDefinition instances with no resource_name set)
	for opt in config.options:
		if opt.resource_name.is_empty():
			opt.resource_name = _slugify(opt)
	
	print("Generating a new Character Creator Scene to ", _output_path.text)
	print("With CharacterConfig ", config)

	var generator := SceneGenerator.new()
	var err := generator.generate(config, _output_path.text)
	
	if err == OK:
		_status_label.text = "Scene saved to %s" % _output_path.text
		scene_generated.emit(_output_path.text)
	else:
		push_error("Generation failed (error %d)" % err)


func _slugify(opt: OptionDefinition) -> String:
	var prefix := {
		"BlendshapeOption": "blend",
		"MeshSwapOption":   "swap",
		"ColorOption":      "color",
		"AnimationOption":  "anim",
	}.get(opt.get_class(), "opt")
	var name := opt.group.to_lower().replace(" ", "_")
	return "%s_%s" % [prefix, name]
	# e.g. "blend_face_fat", "swap_hair", "color_skin_color"
