class_name Interactable
extends Area3D


signal interacted(player: Node)


# Interaction settings
@export_group("Interaction")
@export var interaction_action := "Use"
@export var interaction_enabled := true


# Equipment references
@onready var _equipment_ui: EquipmentUI = (
	get_parent().get_node_or_null("EquipmentUI") as EquipmentUI
)


# Interaction state
var _is_targeted := false
var _custom_prompt := ""


# Build interaction text
func get_interaction_text() -> String:
	if not _custom_prompt.is_empty():
		return _custom_prompt

	return interaction_action + " " + get_parent().name


# Show prompt when targeted
func show_prompt() -> void:
	_is_targeted = true
	_refresh_prompt()


# Hide prompt when no longer targeted
func hide_prompt() -> void:
	_is_targeted = false

	if is_instance_valid(_equipment_ui):
		_equipment_ui.hide_prompt()


# Enable or disable interaction
func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	_refresh_prompt()


# Change interaction prompt
func set_prompt_text(value: String) -> void:
	_custom_prompt = value
	_refresh_prompt()


# Refresh prompt without requiring the player to look away
func _refresh_prompt() -> void:
	if not is_instance_valid(_equipment_ui):
		return

	if not _is_targeted or not interaction_enabled:
		_equipment_ui.hide_prompt()
		return

	_equipment_ui.show_prompt(get_interaction_text())


# Handle interaction
func interact(player: Node) -> void:
	if not interaction_enabled:
		return

	if is_instance_valid(_equipment_ui):
		_equipment_ui.animate_interaction()

	interacted.emit(player)
