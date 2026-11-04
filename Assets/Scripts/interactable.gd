class_name Interactable
extends Area3D


signal interacted(player: Node)


@export_group("Interaction")
@export var interaction_action := "Use"
@export var interaction_enabled := true


@onready var _equipment_ui: EquipmentUI = (
	get_parent().get_node_or_null("EquipmentUI") as EquipmentUI
)


var _is_targeted := false
var _custom_prompt := ""
var _secondary_prompt := ""
var _secondary_prompt_key := "F"
var _held_prompt := ""
var _held_prompt_key := "F"


func get_interaction_text() -> String:
	if not _custom_prompt.is_empty():
		return _custom_prompt
	return interaction_action


func show_prompt() -> void:
	_is_targeted = true
	_refresh_prompt()


func hide_prompt() -> void:
	_is_targeted = false
	_refresh_prompt()


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	_refresh_prompt()


func set_prompt_text(value: String) -> void:
	if _custom_prompt == value:
		return
	_custom_prompt = value
	_refresh_prompt()


# This displays a hint; it does not enable pickup.
func set_held_prompt(text: String, key_text: String = "F") -> void:
	if _held_prompt == text and _held_prompt_key == key_text:
		return
	_held_prompt = text
	_held_prompt_key = key_text
	_refresh_prompt()


func clear_held_prompt() -> void:
	set_held_prompt("")


func set_secondary_prompt(text: String, key_text: String = "F") -> void:
	if _secondary_prompt == text and _secondary_prompt_key == key_text:
		return
	_secondary_prompt = text
	_secondary_prompt_key = key_text
	_refresh_prompt()


func _refresh_prompt() -> void:
	if not is_instance_valid(_equipment_ui):
		return

	if not _held_prompt.is_empty():
		_equipment_ui.show_prompts(_held_prompt, _held_prompt_key)
		return

	if not _is_targeted or not interaction_enabled:
		_equipment_ui.hide_prompt()
		return

	_equipment_ui.show_prompts(
		get_interaction_text(),
		"E",
		_secondary_prompt,
		_secondary_prompt_key
	)


func interact(player: Node) -> void:
	if not interaction_enabled:
		return
	if is_instance_valid(_equipment_ui):
		_equipment_ui.animate_interaction()
	interacted.emit(player)
