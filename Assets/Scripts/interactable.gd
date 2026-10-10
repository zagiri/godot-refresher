
class_name Interactable
extends Area3D


signal interacted(player: Node)


@export var interaction_action := "Use"


# Automatically get the owning object's name
func get_interaction_text() -> String:
	var parent := get_parent()

	if parent == null:
		return interaction_action

	return interaction_action + " " + parent.name


# Forward the interaction to the owning equipment
func interact(player: Node) -> void:
	interacted.emit(player)
