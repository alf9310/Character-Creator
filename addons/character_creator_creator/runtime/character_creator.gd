## Drops into project where character creation happens.
## Wires its children together and exposes a two-signal public API to the rest of the game.
@tool
class_name CharacterCreator
extends Node

## Emitted when the player presses Confirm.
## The developer connects to this and receives the final CharacterState.
signal character_confirmed(state: CharacterState)
## Emitted when the player presses Cancel.
signal character_cancelled()

# Set directly by SceneGenerator after the tree is built
@export var config:   CharacterConfig
@export var ui:       CreatorUI
@export var exporter: CharacterExporter
@export var preview:  CharacterPreview

enum CompatResult { COMPAT_FULL, COMPAT_PARTIAL, COMPAT_NONE }

## Where all the connections are made. 
func _ready() -> void:
	# Don't run initialization in the editor
	if Engine.is_editor_hint():
		return
		
	# Core data flow: every UI change is applied to the mesh immediately
	ui.option_changed.connect(exporter.apply_option)
	
	# Footer actions
	ui.confirm_pressed.connect(_on_confirm)
	ui.cancel_pressed.connect(_on_cancel)
	
	# Randomize buttons
	if config.allow_randomize:
		ui.randomize_pressed.connect(_on_randomize)
	else:
		ui.hide_randomize_button()
	
	# Seed the exporter with defaults and sync the UI to match
	exporter.initialize(config, preview, ui)
	
	# If a previous save exists and should be restored, load it now
	if config.save_state_on_confirm:
		_try_restore_saved_state()
	

# Does not free itself, change scenes, or make any assumptions about what happens next,
# Those are game-dependent!
func _on_confirm() -> void:
	var state: CharacterState = exporter.get_current_state()

	if config.save_state_on_confirm:
		var path := "user://" + config.state_save_path
		var err  := ResourceSaver.save(state, path)
		if err != OK:
			push_warning("[CharacterCreator] State save failed: %d" % err)

		character_confirmed.emit(state)

# Load a saved state and apply it 
# TODO: Add this to character select screen!
'''
# e.g. in the game's character select screen
func load_saved_character() -> void:
    var path := "user://character_state.tres"
    if not ResourceLoader.exists(path):
        return

    var state := ResourceLoader.load(path) as CharacterState
    if state == null:
        push_warning("Failed to load CharacterState from %s" % path)
        return

    var exporter := $CharacterCreator/CharacterExporter
    exporter.load_state(state)
'''



func _on_cancel() -> void:
	character_cancelled.emit()
# Ex: In the developer's game scene
'''
func _ready() -> void:
    $CharacterCreator.character_confirmed.connect(_on_character_confirmed)
    $CharacterCreator.character_cancelled.connect(_on_character_cancelled)

func _on_character_confirmed(state: CharacterState) -> void:
    # e.g. transition to the game world, store state for later use
    PlayerData.character_state = state
    get_tree().change_scene_to_file("res://scenes/world.tscn")

func _on_character_cancelled() -> void:
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
'''

func _on_randomize() -> void:
	var state := CharacterState.randomized(config)
	exporter.load_state(state)
	
## When the creator scene opens and save_state_on_confirm is true, 
## the root node checks for a previously saved state and restores it 
## so returning players see their last character.
func _try_restore_saved_state() -> void:
	var path := "user://" + config.state_save_path
	if not ResourceLoader.exists(path):
		return

	var state := ResourceLoader.load(path) as CharacterState
	if state == null:
		push_warning("[CharacterCreator] Could not load saved state from %s" % path)
		return

	# Validate that the saved state is compatible with the current config.
	# A mismatch happens if the developer regenerated the scene after adding
	# or removing options since the player last played.
	var compat := _validate_state_compatibility(state)
	if compat == CompatResult.COMPAT_FULL:
		exporter.load_state(state)
	elif compat == CompatResult.COMPAT_PARTIAL:
		# Apply what we can, leave unrecognised keys as defaults
		exporter.load_state_partial(state)
		push_warning("[CharacterCreator] Saved state partially compatible — some options reset to defaults.")
	else:
		push_warning("[CharacterCreator] Saved state incompatible with current config — starting fresh.")


# Checks whether the saved state's keys still exist in the current config.
func _validate_state_compatibility(state: CharacterState) -> CompatResult:
	var config_ids := {}
	for opt in config.options:
		config_ids[opt.resource_name] = true

	var state_keys: Array = []
	state_keys.append_array(state.blendshape_values.keys())
	state_keys.append_array(state.swap_choices.keys())
	state_keys.append_array(state.color_values.keys())
	state_keys.append_array(state.animation_choices.keys())

	if state_keys.is_empty():
		return CompatResult.COMPAT_NONE

	var matched := 0
	for key in state_keys:
		if config_ids.has(key):
			matched += 1

	if matched == state_keys.size():
		return CompatResult.COMPAT_FULL
	elif matched > 0:
		# Handles gracefully
		# New options initialize to their config defaults, 
		# existing ones restore from the saved state
		return CompatResult.COMPAT_PARTIAL
	else:
		return CompatResult.COMPAT_NONE


var _orbiting := false
var _last_mouse_pos := Vector2.ZERO

# Handles mouse drag input to rotate the preview camera
# Here instead of Character Preview bc Godot requires consuming node to be 
# in the main scne tree.
# TODO: Could refactor this to pass through, would be annoying though
# character_creator.gd
# TODO: Change to UI actions in settings
func _unhandled_input(event: InputEvent) -> void:
	if not preview.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			preview.zoom(-0.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			preview.zoom(0.15)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# RESET on double-left mouse click
			if event.double_click:
				preview.reset()
			else:
				_orbiting = event.pressed
				_last_mouse_pos = event.position

	elif event is InputEventMouseMotion and _orbiting:
		var delta : Vector2 = event.position - _last_mouse_pos
		_last_mouse_pos = event.position
		preview.orbit(delta * 0.4) # CharacterPreview exposes orbit(delta: Vector2)
