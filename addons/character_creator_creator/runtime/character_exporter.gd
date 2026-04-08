## Serializes CharacterState and applies it to the live mesh.
## translating abstract option changes into concrete mesh operations 
## and maintaining the running CharacterState.
## AKA: Everything visible in the preview that isn't camera or lighting.
@tool
class_name CharacterExporter
extends Node

var _config:			CharacterConfig
var _current_state:		CharacterState
var _character_root:	Node
var _ui:				Control          # held for load_state UI sync
var _option_map:		Dictionary[String, OptionDefinition] = {}   # resource_name -> OptionDefinition

# Cached node paths resolved once in initialize() rather than on every apply call.
# Get_node() on a NodePath is cheap but not free, and apply_option() fires on every slider frame.
var _mesh_cache:		Dictionary[NodePath, MeshInstance3D] = {}
var _blend_idx_cache:	Dictionary[String, int] = {}		# "MeshPath":"blend_shape_mesh" -> blendshape_idx
var _player_cache:		Dictionary[NodePath, AnimationPlayer] = {}
var _mat_cache:			Dictionary[String, Material] = {}   # "NodePath":surface_idx -> Material

# Called once by CharacterCreator._ready() before any player input arrives
# Does 3 things:
# - Builds the option map
# - Resolves and caches every node the apply methods will need
# - Applies defaults to the live mesh so the character appears correct from frame one
func initialize(config: CharacterConfig, preview: CharacterPreview, ui: Control) -> void:
	_config         = config
	_ui             = ui
	_current_state  = CharacterState.from_config(config)
	_character_root = preview.get_character_root()

	# Build option map and warm caches in a single pass
	for opt in config.options:
		_option_map[opt.resource_name] = opt
		_warm_cache(opt)

	# Apply defaults (every option starts at its config default value)
	_apply_full_state(_current_state)


func _warm_cache(opt: OptionDefinition) -> void:
	# TODO: Clean this
	if opt is BlendshapeOption or opt is ColorOption or opt is MeshSwapOption:
		var path: NodePath = opt.mesh_path if opt.get("mesh_path") else NodePath("")
		if path != NodePath("") and not _mesh_cache.has(path):
			var node := _character_root.get_node_or_null(path)
			if node is MeshInstance3D:
				_mesh_cache[path] = node

	if opt is ColorOption:
		var mesh := _mesh_cache.get(opt.mesh_path) as MeshInstance3D
		if mesh:
			var key := "%s:%d" % [opt.mesh_path, opt.surface_index]
			if not _mat_cache.has(key):
				# May be a shared resource used by multiple mesh nodes.
				# Whether writes to it propagate to other nodes is controlled 
				# per-option by ColorOption.apply_to_shared_material.
				_mat_cache[key] = mesh.get_active_material(opt.surface_index)

	if opt is MeshSwapOption:
		for choice: MeshSwapChoice in opt.choices:
			if not _mesh_cache.has(choice.mesh_path):
				var node := _character_root.get_node_or_null(choice.mesh_path)
				if node is MeshInstance3D:
					_mesh_cache[choice.mesh_path] = node

	if opt is AnimationOption:
		var path : NodePath = opt.animation_player_path
		if not _player_cache.has(path):
			var node := _character_root.get_node_or_null(path)
			if node is AnimationPlayer:
				_player_cache[path] = node


# Hot Path
# Every slider move, button press, and color pick arrives here.
# TODO: Refactor to make as fast as possible! 
func apply_option(option_id: String, value: Variant) -> void:
	var opt := _option_map.get(option_id) as OptionDefinition
	if opt == null:
		return

	if opt is BlendshapeOption:
		_apply_blendshape(opt, value as float)
	elif opt is MeshSwapOption:
		_apply_swap(opt, value as int)
	elif opt is ColorOption:
		_apply_color(opt, value as Color)
	elif opt is AnimationOption:
		_apply_animation(opt)
	
	# State stays in sync with what the player intended rather than what the mesh actually reflects.
	# If a node was missing (ex. a swap mesh the artist forgot to include), 
	# the state records the player's selection correctly
	_current_state.record(option_id, value)

# MeshSwapOption
# ONLY USES VISABILITY TOGGLING!
# Less efficient for baking, BUT alteratives have unwanted side-effects. 
# Ex. 	Swapping mesh_instance.mesh looses per-node material overrides,
# 		Adding and removing nodes triggers _ready()
func _apply_swap(opt: MeshSwapOption, choice_index: int) -> void:
	# All of this happens before rendering (order doesn't matter)
	for i in range(opt.choices.size()):
		var node := _mesh_cache.get(opt.choices[i].mesh_path) as MeshInstance3D
		if node == null:
			continue
		node.visible = (i == choice_index)

# The two-level cache (_mesh_cache for the node, _blend_idx_cache for the integer index in the mesh) 
# means that on the hot path (slider dragged) the only work done is 
# a dictionary lookup and set_blend_shape_value()
func _apply_blendshape(opt: BlendshapeOption, value: float) -> void:
	var mesh := _mesh_cache.get(opt.mesh_path) as MeshInstance3D
	if mesh == null:
		return

	# Index lookup is cached separately to avoid find_blend_shape_by_name() on every slider frame.
	# Names are stable within a session.
	var cache_key := "%s::%s" % [opt.mesh_path, opt.blend_shape_name]
	var idx: int = _blend_idx_cache.get(cache_key, -2)

	if idx == -2:   # -2 = not yet looked up; -1 = confirmed missing
		idx = mesh.find_blend_shape_by_name(opt.blend_shape_name)
		_blend_idx_cache[cache_key] = idx

	if idx < 0:
		return

	mesh.set_blend_shape_value(idx, value)

# ColorOption: 
func _apply_color(opt: ColorOption, color: Color) -> void:
	var key := "%s:%d" % [opt.mesh_path, opt.surface_index]
	var mat := _mat_cache.get(key) as Material

	if mat == null:
		return

	if opt.surface_index == -1:
		# Apply to every surface on this mesh
		var mesh := _mesh_cache.get(opt.mesh_path) as MeshInstance3D
		if mesh == null:
			return
		for i in range(mesh.get_surface_override_material_count()):
			_write_color(mesh.get_active_material(i), opt.shader_param, color)
		return
	
	# Duplicates on first write and then updates _mat_cache[key] to point at the duplicate.
	if not opt.apply_to_shared_material:
		# Duplicate the material so other meshes using the same resource
		# are not affected. Store the duplicate back into the cache so
		# subsequent frames write to the duplicate, not the original.
		mat = mat.duplicate()
		var mesh := _mesh_cache.get(opt.mesh_path) as MeshInstance3D
		if mesh:
			mesh.set_surface_override_material(opt.surface_index, mat)
		_mat_cache[key] = mat

	_write_color(mat, opt.shader_param, color)

func _write_color(mat: Material, param: String, color: Color) -> void:
	if mat is ShaderMaterial:
		mat.set_shader_parameter(param, color)
	elif mat is StandardMaterial3D:
		match param:
			"albedo_color": mat.albedo_color = color
			"emission":     mat.emission     = color
			_: push_warning("[CharacterExporter] Unknown param '%s'" % param)


# TODO: Add bone deformations
func _apply_animation(opt: AnimationOption) -> void:
	var player := _player_cache.get(opt.animation_player_path) as AnimationPlayer
	if player == null:
		return
	if not player.has_animation(opt.animation_name):
		return

	var anim := player.get_animation(opt.animation_name)

	if opt.loop_in_preview:
		player.play(opt.animation_name)
	else:
		# Seek to the last frame and stop. 
		# Holds the final pose without keeping the AnimationPlayer ticking every frame.
		player.play(opt.animation_name)
		player.seek(anim.length, true)   # true = update immediately
		player.pause()


## Bulk Application
## When a CharacterState is loaded from disk and needs to be applied all at once. 
## Ex. On session restore, after randomization, or when showing a preset.
# NOTE: Order matters! 
func _apply_full_state(state: CharacterState) -> void:
	for option_id in state.blendshape_values:
		var opt := _option_map.get(option_id) as BlendshapeOption
		if opt:
			_apply_blendshape(opt, state.blendshape_values[option_id])

	for option_id in state.swap_choices:
		var opt := _option_map.get(option_id) as MeshSwapOption
		if opt:
			_apply_swap(opt, state.swap_choices[option_id])

	for option_id in state.color_values:
		var opt := _option_map.get(option_id) as ColorOption
		if opt:
			_apply_color(opt, state.color_values[option_id])

	for option_id in state.animation_choices:
		var opt := _option_map.get(option_id) as AnimationOption
		if opt:
			_apply_animation(opt)


## Public entry point
func load_state(state: CharacterState) -> void:
	_current_state = state
	_apply_full_state(state)
	# Sync UI controls to reflect the loaded values without triggering option_changed signals.
	(_ui as CreatorUI).apply_state(state)


## Compatability load 
# When CharacterCreator._validate_state_compatibility() returns COMPAT_PARTIAL
func load_state_partial(state: CharacterState) -> void:
	# Build a new state from current defaults,
	# then overlay whatever keys the old state has that still match.
	var merged := CharacterState.from_config(_config)

	for id in state.blendshape_values:
		if _option_map.has(id):
			merged.blendshape_values[id] = state.blendshape_values[id]

	for id in state.swap_choices:
		if _option_map.has(id):
			merged.swap_choices[id] = state.swap_choices[id]

	for id in state.color_values:
		if _option_map.has(id):
			merged.color_values[id] = state.color_values[id]

	for id in state.animation_choices:
		if _option_map.has(id):
			merged.animation_choices[id] = state.animation_choices[id]

	load_state(merged)

## CharacterCreator._on_confirm() calls this to get the state for its signal and optional disk write.
# ResourceSaver.save() call lives in CharacterCreator because serialization is a policy decision.
func get_current_state() -> CharacterState:
	# Stamp the time before returning so the .tres reflects when
	# this character was last confirmed, not when the session started.
	_current_state.last_modified = Time.get_unix_time_from_system()
	return _current_state
'''

The resulting `.tres` is human-readable:
	
[gd_resource type="CharacterState" format=3]

[resource]
blendshape_values = {
"blend_face_fat": 0.32,
"blend_brow_height": 0.61,
"blend_body_muscle": 0.18
}
swap_choices = {
"swap_hair": 2,
"swap_outfit": 0
}
color_values = {
"color_skin_color": Color(0.87, 0.72, 0.61, 1),
"color_eye_color": Color(0.24, 0.45, 0.72, 1)
}
animation_choices = {
"anim_idle_pose": "idle_confident"
}
last_modified = 1743200000
metadata = {}
'''
