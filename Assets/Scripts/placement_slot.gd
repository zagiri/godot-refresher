
extends Node3D

@export_group("Placement")
@export var loose_item_search_radius := 0.65
@export var interaction_distance := 3.0

@onready var _interactable: Interactable = $InteractableBase
@onready var _item_position: Marker3D = $ItemPosition

var placed_item: RigidBody3D = null


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	_interactable.interaction_action = "Place"


func _process(_delta: float) -> void:
	_update_interaction_prompt()


func _on_interacted(player: Node) -> void:
	if not player is CharacterBody3D:
		return

	if not player.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_interact(player.get_multiplayer_authority())
	else:
		_request_interact.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if not multiplayer.is_server():
		return

	_server_interact(multiplayer.get_remote_sender_id())


func _server_interact(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var game_scene := get_tree().current_scene

	if game_scene == null:
		return

	var player := game_scene.get_node_or_null(str(peer_id)) as CharacterBody3D

	if player == null or player.get_multiplayer_authority() != peer_id:
		return

	if player.global_position.distance_to(global_position) > interaction_distance:
		return

	var held_item := player.get("held_item") as RigidBody3D

	# Retrieve an item already in the slot.
	if is_instance_valid(placed_item):
		if is_instance_valid(held_item):
			return

		if placed_item.item_state != placed_item.ItemState.PLACED:
			return

		if placed_item.placed_in != self:
			return

		placed_item.retrieve_from_slot(peer_id)
		return

	# Place the item the player is holding.
	if is_instance_valid(held_item):
		if held_item.item_state != held_item.ItemState.HELD:
			return

		held_item.place_in_slot(self)
		return

	# Pick up a loose item dropped onto the slot.
	var loose_item := _find_loose_item()

	if is_instance_valid(loose_item):
		loose_item._server_pickup(peer_id)


func _find_loose_item() -> RigidBody3D:
	if not multiplayer.is_server():
		return null

	var sphere := SphereShape3D.new()
	sphere.radius = loose_item_search_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, _item_position.global_position)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var results := get_world_3d().direct_space_state.intersect_shape(query, 32)

	var closest_item: RigidBody3D = null
	var closest_distance := INF

	for result in results:
		var body := result["collider"] as RigidBody3D

		if body == null or not body.is_in_group("sync_pickup_items"):
			continue

		if body.item_state != body.ItemState.WORLD:
			continue

		var distance := body.global_position.distance_to(_item_position.global_position)

		if distance < closest_distance:
			closest_distance = distance
			closest_item = body

	return closest_item


func _get_local_player() -> CharacterBody3D:
	var game_scene := get_tree().current_scene

	if game_scene == null:
		return null

	return game_scene.get_node_or_null(
		str(multiplayer.get_unique_id())
	) as CharacterBody3D


func _update_interaction_prompt() -> void:
	var player := _get_local_player()

	if not is_instance_valid(player):
		return

	var held_item := player.get("held_item") as RigidBody3D

	if is_instance_valid(placed_item):
		if is_instance_valid(held_item):
			_interactable.set_prompt_text("Slot Occupied")
		else:
			_interactable.set_prompt_text("Retrieve Item")

	elif is_instance_valid(held_item):
		_interactable.set_prompt_text("Place Item")

	else:
		_interactable.set_prompt_text("Empty Slot")


func get_ui_anchor_item() -> Node3D:
	if is_instance_valid(placed_item):
		return placed_item

	return null
