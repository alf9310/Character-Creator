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

@onready var _categories_list:  VBoxContainer   = %CategoriesList

@onready var _allow_random:		CheckBox		= %AllowRandomize
@onready var _show_preview:		CheckBox		= %ShowPreview
@onready var _save_state:		CheckBox		= %SaveState

@onready var _output_path:		LineEdit		= %OutputPath
@onready var _output_dialog:	FileDialog		= %OutputDialog
@onready var _generate_btn:		Button			= %GenerateButton

var _current_scene_path: String = ""
var _detected_options: Array[OptionDefinition] = []

# Flat reference list for O(N) harvesting during generation
var _active_ui_controls: Array[Control] = []

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
	# 1. Clean up old UI
	for child in _categories_list.get_children():
		child.queue_free()
	_active_ui_controls.clear()
	
	# 2. Group all detected options by their 'group' string
	var grouped_options: Dictionary = {}
	for opt in _detected_options:
		var groups_to_add_to: Array[String] = []
		
		if opt.get("editor_groups") != null and opt.get("editor_groups").size() > 0:
			groups_to_add_to.append_array(opt.get("editor_groups"))
		else:
			groups_to_add_to.append(opt.group if not opt.group.is_empty() else "General")

		for g in groups_to_add_to:
			if not grouped_options.has(g):
				grouped_options[g] = []
			grouped_options[g].append(opt)
			
	# 3. Build the UI hierarchy dynamically
	for group_name in grouped_options:
		var category_vbox := VBoxContainer.new()
		_categories_list.add_child(category_vbox)

		# Create a collapsible header button
		var header_btn := Button.new()
		header_btn.text = group_name
		header_btn.toggle_mode = true
		header_btn.button_pressed = true
		category_vbox.add_child(header_btn)

		var content_vbox := VBoxContainer.new()
		category_vbox.add_child(content_vbox)

		# Wire the header to collapse the content
		header_btn.toggled.connect(func(pressed: bool): content_vbox.visible = pressed)

		# Populate the category with its options
		for opt in grouped_options[group_name]:
			if opt is MeshSwapOption:
				var group_ui: GroupContainer = GroupContainerScene.instantiate()
				content_vbox.add_child(group_ui)
				group_ui.setup(opt)

				var rows: Array[OptionRow] = []
				for choice in opt.choices:
					var row: OptionRow = OptionRowScene.instantiate()
					content_vbox.add_child(row)
					row.setup_choice(choice, opt.group)
					rows.append(row)
				group_ui.register_rows(rows)

				_active_ui_controls.append(group_ui)

			else: # Blendshapes, Colors, Animations
				var row: OptionRow = OptionRowScene.instantiate()
				content_vbox.add_child(row)
				row.setup(opt)
				row.set_meta("source_option", opt)
				row.set_meta("category", group_name)

				_active_ui_controls.append(row)

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

	# Tracker to ensure we don't add the same shared blendshape twice
	var processed_options: Dictionary = {}
	
	# Harvest options
	for control in _active_ui_controls:
		if control is GroupContainer:
			var opt: MeshSwapOption = control.get_config_option()
			if opt != null:
				config.options.append(opt)

		elif control is OptionRow:
			var include_checkbox := control.get_node_or_null("%IncludeOption") as CheckBox
			if include_checkbox and include_checkbox.button_pressed:
				var opt: OptionDefinition = control.get_meta("source_option")
				
				# If we already harvested this exact resource from a different tab, skip it!
				if processed_options.has(opt):
					continue
				processed_options[opt] = true
				
				# Assign the runtime group based on the UI category it was actually checked in
				opt.group = control.get_meta("category")

				var name_edit := control.get_node_or_null("%DisplayName") as LineEdit
				if name_edit:
					opt.display_name = name_edit.text
					
				# TODO: Get rid of this messy codepath
				if opt is AnimationOption:
					var default_box := control.get_node_or_null("%Default") as CheckBox
					if default_box:
						opt.is_default = default_box.button_pressed

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
	# 1. Clean the strings for safe dictionary keys
	var group_str := opt.group.to_lower().replace(" ", "_").replace(".", "").replace("-", "_")
	var name_str  := opt.display_name.to_lower().replace(" ", "_").replace(".", "").replace("-", "_")

	# 2. Generate truly unique IDs based on the specific subclass
	if opt is MeshSwapOption:
		# Swaps only need the group name (e.g., "swap_hair")
		return "swap_%s" % group_str

	elif opt is BlendshapeOption:
		# Blendshapes need both to avoid collisions (e.g., "blend_body_muscle", "blend_face_fat")
		if group_str.is_empty(): return "blend_%s" % name_str
		return "blend_%s_%s" % [group_str, name_str]

	elif opt is ColorOption:
		# Colors need both (e.g., "color_hair_albedo_color")
		if group_str.is_empty(): return "color_%s" % name_str
		return "color_%s_%s" % [group_str, name_str]

	elif opt is TextureAtlasOption:
		# Atlas swaps need both group and name (e.g., "atlas_face_eye_shape")
		if group_str.is_empty(): return "atlas_%s" % name_str
		return "atlas_%s_%s" % [group_str, name_str]

	elif opt is AnimationOption:
		# Animations don't have groups, just names (e.g., "anim_idle_confident")
		return "anim_%s" % name_str

	# Fallback
	return "opt_%s" % name_str
