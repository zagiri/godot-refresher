class_name Interactable
extends Area3D


# Text we can show on-screen later
@export var interaction_text := "Interact"


# Called by the player when they interact with this object
func interact(player: Node) -> void:
	print(player.name, " interacted with ", name)
