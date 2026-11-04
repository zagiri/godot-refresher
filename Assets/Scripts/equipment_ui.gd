class_name EquipmentUI
extends Node3D


# ==================================================
# DISTANCE SCALING
# ==================================================

@export_group("Prompt Layout")
@export_range(120.0, 800.0, 1.0) var prompt_text_max_width := 360.0


@export_group("Distance Scaling")
@export var reference_distance := 5.0
@export var base_scale := 0.8
@export var min_scale := 0.5
@export var max_scale := 1.4
@export var scale_smoothing := 8.0


# ==================================================
# POSITIONING
# ==================================================

@export_group("Positioning")
@export var height_offset := 0.15
@export var panel_gap := 0.0
@export var follow_speed := 12.0

@export_group("Dynamic Positioning")
@export var dynamic_item_height := true
@export var item_clearance := 0.1

@export var instant_follow := false

# ==================================================
# ANIMATION
# ==================================================

@export_group("Animation")
@export var fade_duration := 0.14
@export var hidden_scale := 0.94


# ==================================================
# INTERACTION ANIMATION
# ==================================================

@export_group("Interaction Animation")
@export var press_scale := 0.85
@export var press_duration := 0.12
@export var text_change_duration := 0.1


# ==================================================
# DISPLAY REFERENCES
# ==================================================

@onready var _status_sprite: Sprite3D = $StatusDisplay
@onready var _status_viewport: SubViewport = $StatusViewport

@onready var _prompt_sprite: Sprite3D = $PromptDisplay
@onready var _prompt_viewport: SubViewport = $PromptViewport

@onready var _status_panel: Control = $StatusViewport/UIPanel/PanelContainer

@onready var _prompt_panel: Control = $PromptViewport/InteractionUI/PromptPanel


# ==================================================
# STATUS UI REFERENCES
# ==================================================

@onready var _title_label: Label = $StatusViewport/UIPanel/PanelContainer/MarginContainer/VBoxContainer/Header/TitleLabel

@onready var _status_label: Label = $StatusViewport/UIPanel/PanelContainer/MarginContainer/VBoxContainer/Header/StatusLabel

@onready var _timer_label: Label = $StatusViewport/UIPanel/PanelContainer/MarginContainer/VBoxContainer/TimerLabel

@onready var _progress_bar: ProgressBar = $StatusViewport/UIPanel/PanelContainer/MarginContainer/VBoxContainer/ProgressBar


# ==================================================
# PROMPT UI REFERENCES
# ==================================================

@onready var _key_label: Label = $PromptViewport/InteractionUI/PromptPanel/PromptRows/HBoxContainer/KeyPanel/KeyLabel

@onready var _action_label: Label = $PromptViewport/InteractionUI/PromptPanel/PromptRows/HBoxContainer/ActionLabel

@onready var _secondary_row: HBoxContainer = $PromptViewport/InteractionUI/PromptPanel/PromptRows/SecondaryRow
@onready var _secondary_key: Label = $PromptViewport/InteractionUI/PromptPanel/PromptRows/SecondaryRow/KeyPanel/KeyLabel
@onready var _secondary_action: Label = $PromptViewport/InteractionUI/PromptPanel/PromptRows/SecondaryRow/ActionLabel

@onready var _tertiary_row: HBoxContainer = $PromptViewport/InteractionUI/PromptPanel/PromptRows/TertiaryRow
@onready var _tertiary_key: Label = $PromptViewport/InteractionUI/PromptPanel/PromptRows/TertiaryRow/KeyPanel/KeyLabel
@onready var _tertiary_action: Label = $PromptViewport/InteractionUI/PromptPanel/PromptRows/TertiaryRow/ActionLabel

var _prompt_layout_queued := false
const PROMPT_PADDING := 4


# ==================================================
# ANIMATION DATA
# ==================================================

var _status_visible := false
var _prompt_visible := false

var _status_alpha := 0.0
var _prompt_alpha := 0.0

var _status_appearance := 0.94
var _prompt_appearance := 0.94

var _status_tween: Tween
var _prompt_tween: Tween

var _press_tween: Tween
var _text_tween: Tween

var _press_multiplier := 1.0
var _current_prompt_text := ""


# ==================================================
# POSITIONING DATA
# ==================================================

var _distance_scale := 0.8

# Original equipment position.
var _equipment_top := Vector3.ZERO

# Dynamic target position.
var _target_top := Vector3.ZERO

# Cache references, not bounds: transforms and visibility can change.
var _mesh_cache: Dictionary = {}
var _was_ui_active := false


# ==================================================
# INITIALIZATION
# ==================================================

func _ready() -> void:
	_status_sprite.texture = _status_viewport.get_texture()
	_prompt_sprite.texture = _prompt_viewport.get_texture()

	_status_sprite.hide()
	_prompt_sprite.hide()

	_status_sprite.modulate.a = 0.0
	_prompt_sprite.modulate.a = 0.0

	_status_appearance = hidden_scale
	_prompt_appearance = hidden_scale
	_distance_scale = base_scale

	_prompt_panel.show()
	_key_label.text = "E"
	_secondary_row.hide()
	_tertiary_row.hide()
	_prompt_panel.minimum_size_changed.connect(_queue_prompt_layout)
	_prompt_panel.resized.connect(_queue_prompt_layout)
	_queue_prompt_layout()

	set_title("Equipment")
	set_status("Idle")
	set_progress(0.0)
	set_timer(0.0)

	_calculate_equipment_top()

	_target_top = _equipment_top

	# Start the panels at the equipment position.
	_status_sprite.global_position = _equipment_top
	_prompt_sprite.global_position = _equipment_top


# ==================================================
# FRAME UPDATE
# ==================================================

func _process(delta: float) -> void:
	if not _status_sprite.visible and not _prompt_sprite.visible:
		_was_ui_active = false
		return

	_calculate_equipment_top()
	_update_dynamic_target()
	_update_distance_scale(delta)
	_update_panel_scale()

	# Fade-out remains active until the sprites actually hide.
	if not _status_sprite.visible and not _prompt_sprite.visible:
		_was_ui_active = false
		return

	_update_panel_positions(delta, not _was_ui_active)
	_was_ui_active = true


# ==================================================
# EQUIPMENT INFORMATION
# ==================================================

func set_title(value: String) -> void:
	if _title_label.text != value:
		_title_label.text = value


func set_status(value: String) -> void:
	if _status_label.text != value:
		_status_label.text = value


func set_progress(value: float) -> void:
	var clamped := clampf(value, 0.0, 100.0)

	if not is_equal_approx(_progress_bar.value, clamped):
		_progress_bar.value = clamped


func set_timer(seconds: float) -> void:
	var text := "%.1fs remaining" % seconds if seconds > 0.0 else ""

	if _timer_label.text != text:
		_timer_label.text = text


# ==================================================
# INTERACTION PROMPT
# ==================================================

# Existing single-row callers continue to work.
func show_prompt(action_text: String) -> void:
	set_secondary_prompt("")
	set_tertiary_prompt("")
	set_prompt_text(action_text)

	if _prompt_visible:
		return

	_prompt_visible = true
	_animate_prompt(1.0, 1.0)


func hide_prompt() -> void:
	if not _prompt_visible:
		return

	_prompt_visible = false
	_animate_prompt(0.0, hidden_scale)


# ==================================================
# STATUS VISIBILITY
# ==================================================

func show_status() -> void:
	if _status_visible:
		return

	_status_visible = true
	_animate_status(1.0, 1.0)


func hide_status() -> void:
	if not _status_visible:
		return

	_status_visible = false
	_animate_status(0.0, hidden_scale)


# ==================================================
# PROMPT ANIMATION
# ==================================================

func _animate_prompt(
	alpha: float,
	target_scale: float
) -> void:
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()

	_prompt_sprite.show()

	if alpha > 0.0:
		_prompt_alpha = maxf(
			_prompt_alpha,
			0.25
		)

	_prompt_tween = create_tween()

	_prompt_tween.set_parallel(true)
	_prompt_tween.set_trans(Tween.TRANS_CUBIC)
	_prompt_tween.set_ease(Tween.EASE_OUT)

	_prompt_tween.tween_property(
		self,
		"_prompt_alpha",
		alpha,
		fade_duration
	)

	_prompt_tween.tween_property(
		self,
		"_prompt_appearance",
		target_scale,
		fade_duration
	)


# ==================================================
# STATUS ANIMATION
# ==================================================

func _animate_status(
	alpha: float,
	target_scale: float
) -> void:
	if _status_tween and _status_tween.is_valid():
		_status_tween.kill()

	_status_sprite.show()

	if alpha > 0.0:
		_status_alpha = maxf(
			_status_alpha,
			0.25
		)

	_status_tween = create_tween()

	_status_tween.set_parallel(true)
	_status_tween.set_trans(Tween.TRANS_CUBIC)
	_status_tween.set_ease(Tween.EASE_OUT)

	_status_tween.tween_property(
		self,
		"_status_alpha",
		alpha,
		fade_duration
	)

	_status_tween.tween_property(
		self,
		"_status_appearance",
		target_scale,
		fade_duration
	)


# ==================================================
# CAMERA DISTANCE SCALING
# ==================================================

func _update_distance_scale(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()

	if camera == null:
		return

	var distance: float = _target_top.distance_to(
		camera.global_position
	)

	var target_scale: float = clampf(
		base_scale
		* distance
		/ maxf(reference_distance, 0.01),
		min_scale,
		max_scale
	)

	var weight: float = 1.0 - exp(
		-maxf(scale_smoothing, 0.0) * delta
	)

	_distance_scale = lerpf(
		_distance_scale,
		target_scale,
		weight
	)


# ==================================================
# PANEL OPACITY AND SCALE
# ==================================================

func _update_panel_scale() -> void:
	_status_sprite.modulate.a = _status_alpha
	_prompt_sprite.modulate.a = _prompt_alpha

	_status_sprite.scale = (
		Vector3.ONE
		* _distance_scale
		* _status_appearance
	)

	_prompt_sprite.scale = (
		Vector3.ONE
		* _distance_scale
		* _prompt_appearance
		* _press_multiplier
	)

	if not _status_visible and _status_alpha <= 0.01:
		_status_sprite.hide()

	if not _prompt_visible and _prompt_alpha <= 0.01:
		_prompt_sprite.hide()


# ==================================================
# DYNAMIC POSITIONING
# ==================================================

func _update_dynamic_target() -> void:
	# Fall back to the original equipment height.
	_target_top = _equipment_top

	if not dynamic_item_height:
		return

	var equipment := get_parent() as Node3D

	if equipment == null:
		return

	# Only equipment that implements this function
	# will provide a dynamic item.
	#
	# Existing fryer UI remains unchanged.
	if not equipment.has_method("get_ui_anchor_item"):
		return

	var item := equipment.call(
		"get_ui_anchor_item"
	) as Node3D

	if not is_instance_valid(item):
		return

	var item_top := _calculate_node_top(item)

	# Keep the UI above both the equipment and item.
	_target_top = Vector3(
		item_top.x,
		maxf(
			_equipment_top.y,
			item_top.y + item_clearance
		),
		item_top.z
	)


# ==================================================
# FIND TOP OF A 3D NODE
# ==================================================

# Call after adding/removing mesh nodes at runtime.
# Rotation, movement, visibility and mesh-resource changes need no refresh.
func refresh_mesh_cache() -> void:
	_mesh_cache.clear()


func _get_target_meshes(target: Node3D) -> Array[MeshInstance3D]:
	var target_id := target.get_instance_id()

	if _mesh_cache.has(target_id):
		return _mesh_cache[target_id]

	# Only retain the equipment and its current dynamic item.
	if target != get_parent():
		var equipment_id := get_parent().get_instance_id()
		for cached_id in _mesh_cache.keys():
			if cached_id != equipment_id:
				_mesh_cache.erase(cached_id)

	var meshes: Array[MeshInstance3D] = []

	if target is MeshInstance3D:
		meshes.append(target as MeshInstance3D)

	for child in target.find_children("*", "MeshInstance3D", true, false):
		meshes.append(child as MeshInstance3D)

	_mesh_cache[target_id] = meshes
	return meshes


func _calculate_node_top(target: Node3D) -> Vector3:
	if not is_instance_valid(target):
		return _equipment_top

	var bounds := AABB()
	var found_mesh := false

	for mesh in _get_target_meshes(target):
		if not is_instance_valid(mesh):
			continue

		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue

		# Transform each mesh's bounds before finding the world-space top.
		var mesh_bounds: AABB = mesh.global_transform * mesh.get_aabb()

		if found_mesh:
			bounds = bounds.merge(mesh_bounds)
		else:
			bounds = mesh_bounds
			found_mesh = true

	if not found_mesh:
		return target.global_position

	var center := bounds.get_center()
	return Vector3(center.x, bounds.end.y, center.z)


# ==================================================
# PANEL POSITIONING
# ==================================================

func _update_panel_positions(delta: float, snap := false) -> void:
	# Measure visible panel dimensions.
	var status_height: float = (
		_status_panel.size.y
		* _status_sprite.pixel_size
		* _status_sprite.scale.y
	)

	var prompt_height: float = (
		_prompt_panel.size.y
		* _prompt_sprite.pixel_size
		* _prompt_sprite.scale.y
	)

	# Automatically follows the top of an item,
	# or uses the original equipment height.
	var base_y: float = (
		_target_top.y + height_offset
	)

	# Prompt sits closest to the object.
	var prompt_target_y: float = (
		base_y + prompt_height * 0.5
	)

	# Status appears above the prompt.
	var status_target_y: float = (
		base_y
		+ status_height * 0.5
		+ (prompt_height + panel_gap)
		* _prompt_alpha
	)

	var weight: float = 1.0 if instant_follow or snap else (
		1.0 - exp(-maxf(follow_speed, 0.0) * delta)
	)

	var prompt_target := Vector3(
		_target_top.x,
		prompt_target_y,
		_target_top.z
	)

	var status_target := Vector3(
		_target_top.x,
		status_target_y,
		_target_top.z
	)

	_prompt_sprite.global_position = (
		_prompt_sprite.global_position.lerp(
			prompt_target,
			weight
		)
	)

	_status_sprite.global_position = (
		_status_sprite.global_position.lerp(
			status_target,
			weight
		)
	)


# ==================================================
# CALCULATE ORIGINAL EQUIPMENT HEIGHT
# ==================================================

func _calculate_equipment_top() -> void:
	var equipment := get_parent() as Node3D

	if equipment != null:
		_equipment_top = _calculate_node_top(equipment)


# ==================================================
# PROMPT TEXT ANIMATION
# ==================================================

func set_prompt_text(action_text: String) -> void:
	if action_text == _current_prompt_text:
		return

	_current_prompt_text = action_text

	if _text_tween and _text_tween.is_valid():
		_text_tween.kill()

	if not _prompt_visible:
		_action_label.text = action_text
		_action_label.modulate.a = 1.0
		_queue_prompt_layout()
		return

	_text_tween = create_tween()

	_text_tween.tween_property(
		_action_label,
		"modulate:a",
		0.0,
		text_change_duration
	)

	_text_tween.tween_callback(
		func() -> void:
			_action_label.text = action_text
			_queue_prompt_layout()
	)

	_text_tween.tween_property(
		_action_label,
		"modulate:a",
		1.0,
		text_change_duration
	)


# ==================================================
# INTERACTION PRESS ANIMATION
# ==================================================

func animate_interaction() -> void:
	if not _prompt_visible:
		return

	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()

	_press_tween = create_tween()

	# Shrink when pressing E.
	_press_tween.tween_property(
		self,
		"_press_multiplier",
		press_scale,
		press_duration
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)

	# Bounce back to normal size.
	_press_tween.tween_property(
		self,
		"_press_multiplier",
		1.0,
		press_duration * 1.5
	).set_trans(
		Tween.TRANS_BACK
	).set_ease(
		Tween.EASE_OUT
	)

func set_prompt_key(value: String) -> void:
	if _key_label.text != value:
		_key_label.text = value
		_queue_prompt_layout()


# Set both rows together. No parsing of slash-separated strings.
func show_prompts(
	primary_text: String,
	primary_key: String = "E",
	secondary_text: String = "",
	secondary_key: String = "F",
	tertiary_text: String = "",
	tertiary_key: String = "G"
) -> void:
	set_prompt_key(primary_key)
	set_prompt_text(primary_text)
	set_secondary_prompt(secondary_text, secondary_key)
	set_tertiary_prompt(tertiary_text, tertiary_key)
	if not _prompt_visible:
		_prompt_visible = true
		_animate_prompt(1.0, 1.0)


func set_secondary_prompt(text: String, key_text: String = "F") -> void:
	var should_show := not text.is_empty()
	if (
		_secondary_action.text == text
		and _secondary_key.text == key_text
		and _secondary_row.visible == should_show
	):
		return

	_secondary_action.text = text
	_secondary_key.text = key_text
	_secondary_row.visible = should_show
	_queue_prompt_layout()


func set_tertiary_prompt(text: String, key_text: String = "G") -> void:
	var should_show := not text.is_empty()
	if (
		_tertiary_action.text == text
		and _tertiary_key.text == key_text
		and _tertiary_row.visible == should_show
	):
		return

	_tertiary_action.text = text
	_tertiary_key.text = key_text
	_tertiary_row.visible = should_show
	_queue_prompt_layout()


# Coalesce text/visibility/container changes into one deferred layout pass.
func _queue_prompt_layout() -> void:
	if _prompt_layout_queued or not is_inside_tree():
		return
	_prompt_layout_queued = true
	_resize_prompt.call_deferred()


func _resize_prompt() -> void:
	_prompt_layout_queued = false
	if not is_inside_tree():
		return

	_size_prompt_label(_action_label)
	if _secondary_row.visible:
		_size_prompt_label(_secondary_action)
	if _tertiary_row.visible:
		_size_prompt_label(_tertiary_action)

	# Containers propagate wrapped text height through minimum_size_changed.
	# Resetting to the minimum lets the panel shrink as well as grow.
	_prompt_panel.reset_size()
	_prompt_panel.position = Vector2.ONE * PROMPT_PADDING
	var required := Vector2i(
		ceili(_prompt_panel.size.x) + PROMPT_PADDING * 2,
		ceili(_prompt_panel.size.y) + PROMPT_PADDING * 2
	)
	if _prompt_viewport.size != required:
		_prompt_viewport.size = required


func _size_prompt_label(label: Label) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var natural_width := 0.0
	for line in label.text.split("\n"):
		natural_width = maxf(natural_width, font.get_string_size(
			line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x)

	var width := ceilf(clampf(natural_width + 2.0, 1.0, prompt_text_max_width))
	if not is_equal_approx(label.custom_minimum_size.x, width):
		label.custom_minimum_size.x = width
	# The row keeps this column at its own measured width.
	if not is_equal_approx(label.size.x, width):
		label.size.x = width
