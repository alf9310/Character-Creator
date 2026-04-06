## CreatorUI is the generated control tree the player actually interacts with. 
## It doesn't know what a blendshape is or how a mesh swap works. 
## It only knows how to build, display, and emit changes from controls. 
## The mapping between a control's value and a mesh operation lives entirely in CharacterExporter. 
## CreatorUI's contract is simple: receive OptionDefinition resources, produce controls, emit signals when those controls change.

# Note: This strict separation means CreatorUI could be replaced entirely with a custom UI 
# (Ex: a radial wheel, a card gallery, a body-map click interface) without touching any other part of the system. 
# As long as the replacement emits option_changed(option_id, value), confirm_pressed, cancel_pressed, and randomize_pressed, the rest of the add-on works unchanged.
@tool
class_name CreatorUI
extends VBoxContainer

## Emitted whenever any control value changes.
## option_id matches OptionDefinition.resource_name.
## value is float, int, Color, or String depending on the control type.
signal option_changed(option_id: String, value: Variant)

signal confirm_pressed()
signal cancel_pressed()
signal randomize_pressed()

# Flat map of option_id → Control, used by apply_state() to sync controls
# back to their values when loading a saved state or randomizing.
var _control_map: Dictionary[int, Control] = {}

@onready var _tabs:   TabContainer  = $Tabs
@onready var _footer: HBoxContainer = $Footer

# TODO: Remove build logic

func build(options: Array[OptionDefinition]) -> void:
	# Clear any previously generated children
	for child in _tabs.get_children():
		child.queue_free()
	_control_map.clear()

	# Group options preserving the order they first appear
	var groups: Array[String] = []
	var grouped: Dictionary   = {}
	
	# Unnamed groups go in "General"
	for opt in options:
		var g := opt.group if opt.group != "" else "General"
		if not grouped.has(g):
			groups.append(g)
			grouped[g] = []
		grouped[g].append(opt)

	for group_name in groups:
		var scroll := ScrollContainer.new()
		scroll.name = group_name
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(vbox)

		for opt in grouped[group_name]:
			var control := _build_control(opt)
			if control:
				vbox.add_child(control)
				_control_map[opt.resource_name] = control

	_build_footer()
	

## Each builder returns a fully self-contained HBoxContainer (a "row") that handles 
## its own internal signal routing before emitting option_changed upward.
# TODO: Convert these to .tscn templates? Would make it easier to modify...
func _build_control(opt: OptionDefinition) -> Control:
	if opt is MeshSwapOption:     return _build_swap_group(opt)
	if opt is BlendshapeOption:   return _build_slider_row(opt)
	if opt is ColorOption:        return _build_color_row(opt)
	if opt is AnimationOption:    return _build_anim_row(opt)
	push_warning("[CreatorUI] Unhandled OptionDefinition type: %s" % opt.get_class())
	return null

## For MeshSwapOption
func _build_swap_group(opt: MeshSwapOption) -> Control:
	var container := VBoxContainer.new()
	container.name = "SwapGroup_" + opt.resource_name

	var label := Label.new()
	label.text = opt.display_name
	container.add_child(label)
	
	# Can have more than one button per line (wraps-around)
	var btn_row := HFlowContainer.new()
	btn_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(btn_row)

	# ButtonGroup enforces mutual exclusion across all buttons
	var btn_group := ButtonGroup.new()

	for i in range(opt.choices.size()):
		var choice: MeshSwapChoice = opt.choices[i]
		var btn := Button.new()
		btn.text         = choice.label
		btn.toggle_mode  = true
		btn.button_group = btn_group
		btn.button_pressed      = (i == opt.default_choice)
		btn_row.add_child(btn)

		# Capture loop variable with an explicit parameter
		# Emits toggled(false) on the previously selected button at the same time 
		# it emits toggled(true) on the new one
		btn.toggled.connect(func(active: bool, idx := i) -> void:
			if active:
				option_changed.emit(opt.resource_name, idx)
			)

	return container

## For BlendshapeOption
func _build_slider_row(opt: BlendshapeOption) -> Control:
	var row := HBoxContainer.new()
	row.name = "SliderRow_" + opt.resource_name

	var label := Label.new()
	label.text                   = opt.display_name
	label.custom_minimum_size.x  = 100
	label.size_flags_horizontal  = Control.SIZE_SHRINK_BEGIN
	label.clip_text              = true
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value            = opt.min_value
	slider.max_value            = opt.max_value
	slider.step                 = 0.01
	slider.value                = opt.default_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	
	# Shows exact current value of blendshape!
	# TODO: Add as a label that shows up underneath the mouse?
	var readout := Label.new()
	readout.text                 = "%.2f" % opt.default_value
	readout.custom_minimum_size.x = 36
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(readout)

	# Wire internal signal — update readout and emit option_changed
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = "%.2f" % v
		option_changed.emit(opt.resource_name, v)
		)

	return row

## For ColorOption
# TODO: Option to edit alpha (expose as a field on ColorOption
func _build_color_row(opt: ColorOption) -> Control:
	var row := HBoxContainer.new()
	row.name = "ColorRow_" + opt.resource_name

	var label := Label.new()
	label.text                  = opt.display_name
	label.custom_minimum_size.x = 100
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)

	var picker := ColorPickerButton.new()
	picker.color                 = opt.default_color
	picker.edit_alpha            = false   # most character colors don't need alpha
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.y = 28
	row.add_child(picker)
	
	# NOTE: CharacterExporter._apply_color() is called on every drag frame
	# *should* be fine as it's an inexpensive operation
	picker.color_changed.connect(func(color: Color) -> void:
		option_changed.emit(opt.resource_name, color)
	)

	return row
	

## For AnimationOption
# Animations are discrete choices rather than continuous values, 
# so they get a row of toggle buttons similar to mesh swaps, 
# but without ButtonGroup enforcing mutual exclusion.
# TODO: Convert these into sliders integrated with the animation tree for 
# Skeleton deformations. Also add mutual exclusion for previews
func _build_anim_row(opt: AnimationOption) -> Control:
	var row := HBoxContainer.new()
	row.name = "AnimRow_" + opt.resource_name

	var label := Label.new()
	label.text                  = opt.display_name
	label.custom_minimum_size.x = 100
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)

	var btn := Button.new()
	btn.text                 = "Preview"
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(btn)

	btn.pressed.connect(func() -> void:
		option_changed.emit(opt.resource_name, opt.animation_name)
	)

	return row
	
## Syncing controls to a loaded state.
## Walks _control_map and pushes values into each control without re-emitting option_changed.
# Ex: When CharacterCreator loads a saved CharacterState or applies a randomized one, 
# the controls need to reflect the new values.
# TODO: Access control nodes with unique names?
func apply_state(state: CharacterState) -> void:
	var _applying_state := true   # guard flag (see below)
	
	for option_id in state.swap_choices:
		var control := _control_map.get(option_id)
		if control:
			var target_idx: int = state.swap_choices[option_id]
			var btn_row : Control = control.get_node("HFlowContainer")
			for i in range(btn_row.get_child_count()):
				# set_value_no_signal() and set_pressed_no_signal(): built-in methods for 
				# mutating control's value without emitting signals
				(btn_row.get_child(i) as Button).set_pressed_no_signal(i == target_idx)

	for option_id in state.blendshape_values:
		var control := _control_map.get(option_id)
		if control:
			control.get_node("HSlider").set_value_no_signal(
				state.blendshape_values[option_id]
			)
			control.get_node("Label").text = "%.2f" % state.blendshape_values[option_id]

	for option_id in state.color_values:
		var control := _control_map.get(option_id)
		if control:
			control.get_node("ColorPickerButton").color = state.color_values[option_id]
	
	# TODO: Add skeleton deformations
	
	_applying_state = false

## Emits upward to CharacterCreator rather than acting directly
func _build_footer() -> void:
	var randomize_btn := Button.new()
	randomize_btn.name = "RandomizeButton"
	# TODO: Add icon instead of text
	randomize_btn.text = "↺ Randomize"
	randomize_btn.pressed.connect(func(): randomize_pressed.emit())
	_footer.add_child(randomize_btn)

	var cancel_btn := Button.new()
	cancel_btn.name = "CancelButton"
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): cancel_pressed.emit())
	_footer.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.name = "ConfirmButton"
	confirm_btn.text = "Confirm"
	confirm_btn.pressed.connect(func(): confirm_pressed.emit())
	_footer.add_child(confirm_btn)

func hide_randomize_button() -> void:
	var btn := _footer.get_node_or_null("RandomizeButton")
	if btn:
		btn.queue_free()
