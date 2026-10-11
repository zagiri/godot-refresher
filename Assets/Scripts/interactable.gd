class_name Interactable
extends Area3D


signal interacted(player: Node)


# Interaction settings
@export_group("Interaction")
@export var interaction_action := "Use"


# Equipment UI reference
@onready var _equipment_ui: EquipmentUI = get_parent().get_node_or_null("EquipmentUI") as EquipmentUI


# Automatically identify the owning equipment
func get_interaction_text() -> String:
	var equipment := get_parent()

	if equipment == null:
		return interaction_action

	return interaction_action + " " + equipment.name


# Show interaction prompt
func show_prompt() -> void:
	if not is_instance_valid(_equipment_ui):
		return

	_equipment_ui.show_prompt(get_interaction_text())


# Hide interaction prompt
func hide_prompt() -> void:
	if is_instance_valid(_equipment_ui):
		_equipment_ui.hide_prompt()


# Forward interaction to equipment
func interact(player: Node) -> void:
	if is_instance_valid(_equipment_ui):
		_equipment_ui.animate_interaction()

	interacted.emit(player)
