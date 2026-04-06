# Swap options have a variable number of choices, 
# so the scene contains a fixed header and an empty container that UIGenerator populates

class_name SwapGroup
extends VBoxContainer

signal changed(option_id: String, value: Variant)

@export var option_id: String = ""

@onready var _container: HFlowContainer = %ButtonContainer

var _btn_group := ButtonGroup.new()

func _ready() -> void:
	# Buttons are added by UIGenerator before _ready() runs,
	# so they exist in the tree here. This connects their signals.
	for i in range(_container.get_child_count()):
		var btn := _container.get_child(i) as Button
		if btn == null:
			continue
		btn.button_group = _btn_group
		btn.toggled.connect(_on_button_toggled.bind(i))

func _on_button_toggled(active: bool, idx: int) -> void:
	if active:
		changed.emit(option_id, idx)

func set_choice_no_signal(idx: int) -> void:
	for i in range(_container.get_child_count()):
		var btn := _container.get_child(i) as Button
		if btn:
			btn.set_pressed_no_signal(i == idx)
