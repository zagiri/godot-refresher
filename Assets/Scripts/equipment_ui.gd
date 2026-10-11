class_name EquipmentUI
extends Node3D


# Distance scaling
@export_group("Distance Scaling")
@export var reference_distance := 5.0
@export var base_scale := 0.8
@export var min_scale := 0.5
@export var max_scale := 1.4
@export var scale_smoothing := 8.0


# Positioning
@export_group("Positioning")
@export var height_offset := 0.15
@export var panel_gap := 0.08
@export var follow_speed := 12.0


# Animation
@export_group("Animation")
@export var fade_duration := 0.14
@export var hidden_scale := 0.94


# Display references
@onready var _status_sprite: Sprite3D = $StatusDisplay
@onready var _status_viewport: SubViewport = $StatusViewport
@onready var _prompt_sprite: Sprite3D = $PromptDisplay
@onready var _prompt_viewport: SubViewport = $PromptViewport


# Status UI references
@onready var _title_label: Label = $StatusViewport/UIPanel/PanelContainer/MarginContainer/VBoxContainer/Header/TitleLabel
@onready var _status_label: Label = $StatusViewport/UIPanel/PanelContainer/MarginContainer/VBoxContainer/Header/StatusLabel
@onready var _timer_label: Label = $StatusViewport/UIPanel/PanelContainer/MarginContainer/VBoxContainer/TimerLabel
@onready var _progress_bar: ProgressBar = $StatusViewport/UIPanel/PanelContainer/MarginContainer/VBoxContainer/ProgressBar
@onready var _prompt_panel: Control = $PromptViewport/InteractionUI/PromptPanel
@onready var _key_label: Label = $PromptViewport/InteractionUI/PromptPanel/HBoxContainer/KeyPanel/KeyLabel
@onready var _action_label: Label = $PromptViewport/InteractionUI/PromptPanel/HBoxContainer/ActionLabel

#Animation On interact
@export_group("Interaction Animation")
@export var press_scale := 0.85
@export var press_duration := 0.12
@export var text_change_duration := 0.1


# Animation data
var _status_visible := false
var _prompt_visible := false

var _status_alpha := 0.0
var _prompt_alpha := 0.0

var _status_appearance := 0.94
var _prompt_appearance := 0.94

var _status_tween: Tween
var _prompt_tween: Tween

var _distance_scale := 0.8
var _equipment_top := Vector3.ZERO

var _press_tween: Tween
var _text_tween: Tween

var _press_multiplier := 1.0
var _current_prompt_text := ""


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

	set_title("Equipment")
	set_status("Idle")
	set_progress(0.0)
	set_timer(0.0)

	_calculate_equipment_top()


# Update camera scaling and panel positioning
func _process(delta: float) -> void:
	_update_distance_scale(delta)
	_update_panel_scale()
	_update_panel_positions(delta)


# Equipment information
func set_title(value: String) -> void:
	_title_label.text = value


func set_status(value: String) -> void:
	_status_label.text = value


func set_progress(value: float) -> void:
	_progress_bar.value = clampf(value, 0.0, 100.0)


func set_timer(seconds: float) -> void:
	_timer_label.text = "%.1fs remaining" % seconds if seconds > 0.0 else ""


# Interaction prompt
func show_prompt(action_text: String) -> void:
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


# Equipment status visibility
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


# Animate interaction prompt
func _animate_prompt(alpha: float, target_scale: float) -> void:
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()

	_prompt_sprite.show()

	if alpha > 0.0:
		_prompt_alpha = maxf(_prompt_alpha, 0.25)

	_prompt_tween = create_tween()
	_prompt_tween.set_parallel(true)
	_prompt_tween.set_trans(Tween.TRANS_CUBIC)
	_prompt_tween.set_ease(Tween.EASE_OUT)

	_prompt_tween.tween_property(
		self, "_prompt_alpha", alpha, fade_duration
	)

	_prompt_tween.tween_property(
		self, "_prompt_appearance", target_scale, fade_duration
	)


# Animate equipment status
func _animate_status(alpha: float, target_scale: float) -> void:
	if _status_tween and _status_tween.is_valid():
		_status_tween.kill()

	_status_sprite.show()

	if alpha > 0.0:
		_status_alpha = maxf(_status_alpha, 0.25)

	_status_tween = create_tween()
	_status_tween.set_parallel(true)
	_status_tween.set_trans(Tween.TRANS_CUBIC)
	_status_tween.set_ease(Tween.EASE_OUT)

	_status_tween.tween_property(
		self, "_status_alpha", alpha, fade_duration
	)

	_status_tween.tween_property(
		self, "_status_appearance", target_scale, fade_duration
	)


# Calculate camera-distance scaling
func _update_distance_scale(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()

	if camera == null:
		return

	var distance: float = global_position.distance_to(
		camera.global_position
	)

	var target_scale: float = clampf(
		base_scale * distance / maxf(reference_distance, 0.01),
		min_scale,
		max_scale
	)

	var weight: float = 1.0 - exp(-maxf(scale_smoothing, 0.0) * delta)

	_distance_scale = lerpf(_distance_scale, target_scale, weight)


# Apply panel opacity and scale

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


# Automatically stack panels above equipment
func _update_panel_positions(delta: float) -> void:
	var status_height: float = (
		_status_viewport.size.y
		* _status_sprite.pixel_size
		* _status_sprite.scale.y
	)

	var prompt_height: float = (
		_prompt_viewport.size.y
		* _prompt_sprite.pixel_size
		* _prompt_sprite.scale.y
	)

	var prompt_visible_height: float = (
		prompt_height if _prompt_alpha > 0.01 else 0.0
	)

	var status_visible_height: float = (
		status_height if _status_alpha > 0.01 else 0.0
	)

	var base_y: float = _equipment_top.y + height_offset

	var prompt_target_y: float = base_y + prompt_height * 0.5
	var status_target_y: float = base_y + status_height * 0.5

	status_target_y += (
		prompt_height + panel_gap
	) * _prompt_alpha

	var weight: float = 1.0 - exp(-maxf(follow_speed, 0.0) * delta)

	_prompt_sprite.global_position = _prompt_sprite.global_position.lerp(
		Vector3(_equipment_top.x, prompt_target_y, _equipment_top.z),
		weight
	)

	_status_sprite.global_position = _status_sprite.global_position.lerp(
		Vector3(_equipment_top.x, status_target_y, _equipment_top.z),
		weight
	)


# Find equipment height from its meshes
func _calculate_equipment_top() -> void:
	var equipment := get_parent() as Node3D

	if equipment == null:
		return

	var bounds := AABB()
	var found_mesh := false

	for child in equipment.find_children(
		"*", "MeshInstance3D", true, false
	):
		var mesh := child as MeshInstance3D

		if mesh == null:
			continue

		var mesh_transform: Transform3D = (
			equipment.global_transform.affine_inverse()
			* mesh.global_transform
		)

		var mesh_bounds: AABB = mesh_transform * mesh.get_aabb()

		if not found_mesh:
			bounds = mesh_bounds
			found_mesh = true
		else:
			bounds = bounds.merge(mesh_bounds)

	if not found_mesh:
		_equipment_top = equipment.global_position
		return

	var top_local := Vector3(
		bounds.get_center().x,
		bounds.end.y,
		bounds.get_center().z
	)

	_equipment_top = equipment.to_global(top_local)
	


func set_prompt_text(action_text: String) -> void:
	if action_text == _current_prompt_text:
		return

	_current_prompt_text = action_text

	if _text_tween and _text_tween.is_valid():
		_text_tween.kill()

	if not _prompt_visible:
		_action_label.text = action_text
		_action_label.modulate.a = 1.0
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
	)

	_text_tween.tween_property(
		_action_label,
		"modulate:a",
		1.0,
		text_change_duration
	)


func animate_interaction() -> void:
	if not _prompt_visible:
		return

	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()

	_press_tween = create_tween()

	# Quickly shrink when pressing E
	_press_tween.tween_property(
		self,
		"_press_multiplier",
		press_scale,
		press_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Bounce back to normal size
	_press_tween.tween_property(
		self,
		"_press_multiplier",
		1.0,
		press_duration * 1.5
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
