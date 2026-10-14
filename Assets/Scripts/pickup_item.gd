extends RigidBody3D

@onready var _interactable: Interactable = $InteractableBase

var held_by: CharacterBody3D = null
var _original_parent: Node


func _ready() -> void:
	_original_parent = get_parent()
	_interactable.interacted.connect(_on_interacted)
	_interactable.interaction_action = "Pick up"


func _on_interacted(player: Node) -> void:
	if not player is CharacterBody3D:
		return

	if held_by != null:
		return

	if player.get("held_item") != null:
		return

	var hold_point := player.get_node_or_null("HoldPoint") as Marker3D

	if hold_point == null:
		push_warning("Player is missing HoldPoint!")
		return

	held_by = player
	player.set("held_item", self)

	_interactable.set_interaction_enabled(false)
	_interactable.hide_prompt()

	# Wake up nearby physical objects before removing their support.
	_wake_nearby_items()

	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	reparent(hold_point)
	position = Vector3.ZERO
	rotation = Vector3.ZERO

	print(player.name, " picked up ", name)


func drop_item() -> void:
	if not is_instance_valid(held_by):
		return

	var player := held_by

	# Preserve the item's world position when reparenting.
	reparent(_original_parent, true)

	# Clear the player's held item.
	player.set("held_item", null)
	held_by = null

	# Restore physics.
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false

	# Allow the item to be picked up again.
	_interactable.set_interaction_enabled(true)

	print(player.name, " dropped ", name)

func _wake_nearby_items() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(
		Basis.IDENTITY,
		global_position
	)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var results := get_world_3d().direct_space_state.intersect_shape(
		query,
		32
	)

	for result in results:
		var body := result["collider"] as RigidBody3D

		if body != null and body != self:
			body.sleeping = false
