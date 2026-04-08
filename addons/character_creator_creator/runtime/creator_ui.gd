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

# Flat map of option_id -> Control node (SwapGroup, SliderRow, ColorRow, AnimRow)
# Used by apply_state() to sync controls without re-emitting signals.
var _control_map: Dictionary = {}

func _ready() -> void:
	# We only want to wire up signals when running the game, not in the editor
	if Engine.is_editor_hint():
		return
		
	# The UI tree is already built by UIGenerator and saved into the .tscn.
	# We walk the tree once to index the controls and connect their signals.
	_bind_controls(self)
	_bind_footer_buttons()

## Recursively searches the tree for custom Option control nodes
func _bind_controls(node: Node) -> void:
	if node is SwapGroup or node is SliderRow or node is ColorRow or node is AnimRow:
		var opt_id: String = node.option_id
		_control_map[opt_id] = node
		
		# All of these custom row types emit a consistent 'changed' signal
		node.changed.connect(func(id: String, val: Variant) -> void: 
			option_changed.emit(id, val)
		)
		
	for child in node.get_children():
		_bind_controls(child)

## Finds the standard footer buttons and wires them up
func _bind_footer_buttons() -> void:
	# Using find_child is robust against layout changes UIGenerator might make
	var randomize_btn := find_child("RandomizeButton", true, false) as Button
	if randomize_btn:
		randomize_btn.pressed.connect(func() -> void: randomize_pressed.emit())
		
	var cancel_btn := find_child("CancelButton", true, false) as Button
	if cancel_btn:
		cancel_btn.pressed.connect(func() -> void: cancel_pressed.emit())
		
	var confirm_btn := find_child("ConfirmButton", true, false) as Button
	if confirm_btn:
		confirm_btn.pressed.connect(func() -> void: confirm_pressed.emit())

func hide_randomize_button() -> void:
	var btn := find_child("RandomizeButton", true, false) as Button
	if btn:
		btn.visible = false

## Syncing controls to a loaded state.
## Uses the UIGenerator's custom row APIs to mutate values without triggering signals.
func apply_state(state: CharacterState) -> void:
	for option_id in state.swap_choices:
		var control = _control_map.get(option_id)
		if control is SwapGroup:
			control.set_choice_no_signal(state.swap_choices[option_id])

	for option_id in state.blendshape_values:
		var control = _control_map.get(option_id)
		if control is SliderRow:
			control.set_value_no_signal(state.blendshape_values[option_id])

	for option_id in state.color_values:
		var control = _control_map.get(option_id)
		if control is ColorRow:
			control.set_color_no_signal(state.color_values[option_id])
			
	# Animations usually don't have a persistent UI state to sync, 
	# but if you add toggle states to AnimRow later, handle them here!
