# ui_generator.gd
# runs exactly oncem when the developer clicks "Generate Scene" in the dock. 
# Its job is to write a node tree into a .tscn file.
@tool
class_name UIGenerator
extends RefCounted

# Control scene templates — preloaded once at class level.
# UIGenerator instantiates these; it never constructs control nodes by hand.
const SliderRowScene  := preload("res://addons/character_creator_creator/runtime/controls/slider_row.tscn")
const SwapGroupScene  := preload("res://addons/character_creator_creator/runtime/controls/swap_group.tscn")
const ColorRowScene   := preload("res://addons/character_creator_creator/runtime/controls/color_row.tscn")
const AnimRowScene    := preload("res://addons/character_creator_creator/runtime/controls/anim_row.tscn")


# Entry point. Called by SceneGenerator with:
#   ui: 			the CreatorUI VBoxContainer node already added to the scene tree
#   options:		the finalised Array[OptionDefinition] from CharacterConfig
#   scene_root:		the CharacterCreator root node; every new node's .owner must be set to this
func build(
		ui: VBoxContainer,
		options: Array[OptionDefinition],
		scene_root: Node) -> void:

	_build_tabs(ui, options, scene_root)
	_build_footer(ui, scene_root)


# ---------------------------------------------------------------------------
# Tab structure
# ---------------------------------------------------------------------------
func _build_tabs(
		ui: VBoxContainer,
		options: Array[OptionDefinition],
		scene_root: Node) -> void:

	var tabs := TabContainer.new()
	tabs.name                  = "Tabs"
	tabs.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	ui.add_child(tabs)
	tabs.owner = scene_root

	# Group options by .group string, preserving first-seen insertion order.
	# An empty group string falls back to "General".
	var group_order: Array[String] = []
	var grouped: Dictionary        = {}   # String → Array[OptionDefinition]

	for opt in options:
		var g: String = opt.group if opt.group != "" else "General"
		if not grouped.has(g):
			group_order.append(g)
			grouped[g] = []
		grouped[g].append(opt)
	
	for group_name in group_order:
		print("Building tab for group ", group_name)
		_build_tab(tabs, group_name, grouped[group_name], scene_root)


func _build_tab(
		tabs: TabContainer,
		group_name: String,
		options: Array, #[OptionDefinition],
		scene_root: Node) -> void:
		
	# ScrollContainer is the direct child of TabContainer,
	# its .name becomes the tab label shown to the player.
	var scroll := ScrollContainer.new()
	scroll.name                   = group_name
	scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size 		= Vector2(0, 500)
	tabs.add_child(scroll)
	scroll.owner = scene_root

	var vbox := VBoxContainer.new()
	vbox.name                      = "OptionList"
	vbox.size_flags_horizontal     = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	vbox.owner = scene_root

	for opt in options:
		var control := _build_control(opt, scene_root)
		if control == null:
			continue
		vbox.add_child(control)
		# Now scene_root is a true ancestor of control and all its descendants
		_set_owners(control, scene_root)


# Walks a subtree and sets .owner on every node.
# By overwriting the owner and clearing the scene_file_path, 
# we "unwrap" the instanced templates so Godot saves their internal overrides 
# and newly added children directly into the generated .tscn.
func _set_owners(node: Node, scene_root: Node) -> void:
	# Force the owner to be the root we are saving
	node.owner = scene_root
	
	# Break the instance link so it stops acting like a black box
	node.scene_file_path = ""

	for child in node.get_children():
		_set_owners(child, scene_root)


# ---------------------------------------------------------------------------
# Control builders — one per OptionDefinition subtype
# ---------------------------------------------------------------------------

func _build_control(
		opt: OptionDefinition,
		scene_root: Node) -> Control:
			
	if opt is MeshSwapOption:
		return _build_swap_group(opt as MeshSwapOption, scene_root)
	if opt is BlendshapeOption:
		return _build_slider_row(opt as BlendshapeOption)
	if opt is ColorOption:
		return _build_color_row(opt as ColorOption)
	if opt is AnimationOption:
		return _build_anim_row(opt as AnimationOption)

	push_warning(
		"[UIGenerator] Unrecognised OptionDefinition subtype '%s' — skipped."
		% opt.get_class()
	)
	return null

func _build_swap_group(opt: MeshSwapOption, scene_root: Node) -> SwapGroup:
	print("\tBuilding swap group for ", opt.group)
	var group := SwapGroupScene.instantiate() as SwapGroup
	group.name      = "SwapGroup_" + opt.resource_name
	group.option_id = opt.resource_name

	group.find_child("OptionLabel", true, false).text = opt.display_name

	var container := group.find_child("ButtonContainer", true, false) as HFlowContainer

	for i in range(opt.choices.size()):
		var choice := opt.choices[i] as MeshSwapChoice
		var btn    := Button.new()
		btn.name        = "Choice_%d" % i
		btn.text        = choice.label
		btn.toggle_mode = true
		btn.button_pressed = (i == opt.default_choice)
		container.add_child(btn)

	return group

func _build_slider_row(opt: BlendshapeOption) -> SliderRow:
	var row := SliderRowScene.instantiate() as SliderRow
	row.name      = "SliderRow_" + opt.resource_name
	row.option_id = opt.resource_name

	row.find_child("OptionLabel", true, false).text = opt.display_name
	row.find_child("Slider", true, false).min_value = opt.min_value
	row.find_child("Slider", true, false).max_value = opt.max_value
	row.find_child("Slider", true, false).value      = opt.default_value
	row.find_child("Readout", true, false).text      = "%.2f" % opt.default_value

	return row


func _build_color_row(opt: ColorOption) -> ColorRow:
	var row := ColorRowScene.instantiate() as ColorRow
	row.name      = "ColorRow_" + opt.resource_name
	row.option_id = opt.resource_name

	row.find_child("OptionLabel", true, false).text  = opt.display_name
	row.find_child("ColorPicker", true, false).color = opt.default_color

	return row


func _build_anim_row(opt: AnimationOption) -> AnimRow:
	var row := AnimRowScene.instantiate() as AnimRow
	row.name           = "AnimRow_" + opt.resource_name
	row.option_id      = opt.resource_name
	row.animation_name = opt.animation_name

	row.find_child("OptionLabel", true, false).text   = opt.display_name
	row.find_child("PreviewButton", true, false).text = "Preview"

	return row


# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------

func _build_footer(ui: VBoxContainer, scene_root: Node) -> void:
	var footer := HBoxContainer.new()
	footer.name                    = "Footer"
	footer.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	footer.alignment               = BoxContainer.ALIGNMENT_END
	ui.add_child(footer)
	footer.owner = scene_root

	for spec in [
		["RandomizeButton", "↺ Randomize"],
		["CancelButton",    "Cancel"],
		["ConfirmButton",   "Confirm"],
	]:
		var btn := Button.new()
		btn.name = spec[0]
		btn.text = spec[1]
		footer.add_child(btn)
		btn.owner = scene_root
