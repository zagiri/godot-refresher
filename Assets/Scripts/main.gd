extends Node3D


const PLAYER_CONTROLLER = preload("uid://cps4dh3kjo074")


# Item spawning
@export_group("Item Spawning")
@export var spawnable_items: Array[PackedScene] = []


# Node references
@onready var _spawned_items: Node3D = (
	get_node_or_null("SpawnedItems") as Node3D
)

@onready var _item_spawner: MultiplayerSpawner = (
	get_node_or_null("ItemSpawner") as MultiplayerSpawner
)


# Runtime data
var players: Array[CharacterBody3D] = []
var _next_item_id := 0
var _item_spawning_ready := false


func _ready() -> void:
	_setup_item_spawner()

	print("MAIN LOADED | Host: ", Networking.is_host)

	if Networking.is_host:
		if not multiplayer.peer_disconnected.is_connected(
			_on_peer_disconnected
		):
			multiplayer.peer_disconnected.connect(
				_on_peer_disconnected
			)

		spawn_player(multiplayer.get_unique_id())


# Item spawner setup
func _setup_item_spawner() -> void:
	if _spawned_items == null:
		push_error(
			"Main needs a direct child named SpawnedItems "
			+ "with type Node3D."
		)
		return

	if _item_spawner == null:
		push_error(
			"Main needs a direct child named ItemSpawner "
			+ "with type MultiplayerSpawner."
		)
		return

	_item_spawner.spawn_path = _item_spawner.get_path_to(
		_spawned_items
	)

	_item_spawner.spawn_function = _create_spawned_item

	if not _item_spawner.spawned.is_connected(_on_item_spawned):
		_item_spawner.spawned.connect(_on_item_spawned)

	_item_spawning_ready = true


# Client connection
func start_client_sync() -> void:
	if Networking.is_host:
		return

	print("CLIENT: Gameplay loaded and connected.")

	_notify_server_ready.call_deferred()


func _notify_server_ready() -> void:
	if Networking.is_host:
		return

	if multiplayer.multiplayer_peer == null:
		return

	if (
		multiplayer.multiplayer_peer.get_connection_status()
		!= MultiplayerPeer.CONNECTION_CONNECTED
	):
		return

	print("CLIENT: Notifying host.")

	_client_ready.rpc_id(1)


# Client tells the host that gameplay is loaded
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()

	if peer_id <= 0:
		return

	print("HOST: Client ready: ", peer_id)

	if not _has_player(peer_id):
		spawn_player(peer_id)

	# Synchronize equipment already in the level.
	for equipment in get_tree().get_nodes_in_group("sync_equipment"):
		if equipment.has_method("send_current_state"):
			equipment.send_current_state(peer_id)

	# Synchronize pickup items already in the level.
	for item in get_tree().get_nodes_in_group("sync_pickup_items"):
		# Spawned items request state after appearing on the client.
		if is_instance_valid(_spawned_items):
			if _spawned_items.is_ancestor_of(item):
				continue

		if item.has_method("send_current_state"):
			item.send_current_state(peer_id)


# Host spawns players
func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if _has_player(peer_id):
		return

	var new_player := (
		PLAYER_CONTROLLER.instantiate() as CharacterBody3D
	)

	new_player.name = str(peer_id)
	new_player.position = $SpawnPoint.position

	# The existing player MultiplayerSpawner replicates this.
	add_child(new_player)

	initialize_player(new_player)

	print("PLAYER SPAWNED: ", peer_id)


func initialize_player(player: CharacterBody3D) -> void:
	if not players.has(player):
		players.append(player)


func _has_player(peer_id: int) -> bool:
	for player in players:
		if not is_instance_valid(player):
			continue

		if player.get_multiplayer_authority() == peer_id:
			return true

	return false


# Player disconnection
func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("PLAYER DISCONNECTED: ", peer_id)

	# Release held items before removing the player.
	for item in get_tree().get_nodes_in_group("sync_pickup_items"):
		if item.has_method("release_disconnected_player"):
			item.release_disconnected_player(peer_id)

	for index in range(players.size() - 1, -1, -1):
		var player := players[index]

		if not is_instance_valid(player):
			players.remove_at(index)
			continue

		if player.get_multiplayer_authority() == peer_id:
			players.remove_at(index)
			player.queue_free()
			return


# Existing player spawner signal
func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node is CharacterBody3D:
		var player := node as CharacterBody3D

		initialize_player(player)

		print(
			"REPLICATED PLAYER | Local: ",
			multiplayer.get_unique_id(),
			" | Authority: ",
			player.get_multiplayer_authority()
		)


# Spawn an approved pickup scene on the host
func spawn_pickup_item(
	item_scene: PackedScene,
	world_transform: Transform3D
) -> RigidBody3D:
	if not multiplayer.is_server():
		return null

	if not _item_spawning_ready:
		push_warning("Item spawning is unavailable. Check Main's nodes.")
		return null

	if item_scene == null:
		return null

	var scene_index := spawnable_items.find(item_scene)

	if scene_index == -1:
		push_warning(
			"Item scene is missing from Main's Spawnable Items."
		)
		return null

	_next_item_id += 1

	var spawn_data := {
		"scene_index": scene_index,
		"item_name": "SpawnedItem_%d" % _next_item_id,
		"local_transform": (
			_spawned_items.global_transform.affine_inverse()
			* world_transform
		)
	}

	return _item_spawner.spawn(spawn_data) as RigidBody3D


# Runs on every peer when the host requests a custom spawn
func _create_spawned_item(data: Variant) -> Node:
	if not data is Dictionary:
		return null

	var spawn_data: Dictionary = data

	if not spawn_data.has_all([
		"scene_index",
		"item_name",
		"local_transform"
	]):
		return null

	if typeof(spawn_data["scene_index"]) != TYPE_INT:
		return null

	if typeof(spawn_data["item_name"]) != TYPE_STRING:
		return null

	if typeof(spawn_data["local_transform"]) != TYPE_TRANSFORM3D:
		return null

	var scene_index: int = spawn_data["scene_index"]

	if scene_index < 0 or scene_index >= spawnable_items.size():
		return null

	var item_scene: PackedScene = spawnable_items[scene_index]

	if item_scene == null:
		return null

	var instance: Node = item_scene.instantiate()
	var item := instance as RigidBody3D

	if item == null:
		instance.free()
		push_error("Spawnable item must have a RigidBody3D root.")
		return null

	if not item.has_method("send_current_state"):
		item.free()
		push_error("Spawnable item must use the PickupItem system.")
		return null

	item.name = str(spawn_data["item_name"])

	var item_transform: Transform3D = spawn_data["local_transform"]
	item.transform = item_transform

	# Item physics and gameplay remain host-authoritative.
	item.set_multiplayer_authority(1)

	# MultiplayerSpawner adds the item to SpawnedItems.
	return item


# Runs on clients after a replicated item appears
func _on_item_spawned(item: Node) -> void:
	if multiplayer.is_server():
		return

	_request_spawned_item_state.call_deferred(str(item.name))


func _request_spawned_item_state(item_name: String) -> void:
	if multiplayer.is_server():
		return

	if not is_inside_tree():
		return

	if multiplayer.multiplayer_peer == null:
		return

	if (
		multiplayer.multiplayer_peer.get_connection_status()
		!= MultiplayerPeer.CONNECTION_CONNECTED
	):
		return

	_request_item_state.rpc_id(1, item_name)


# Host supplies the item's latest state
@rpc("any_peer", "call_remote", "reliable")
func _request_item_state(item_name: String) -> void:
	if not multiplayer.is_server():
		return

	if not _item_spawning_ready:
		return

	var peer_id := multiplayer.get_remote_sender_id()

	if peer_id <= 0:
		return

	# Only allow requests for direct children of SpawnedItems.
	for item in _spawned_items.get_children():
		if str(item.name) != item_name:
			continue

		if item.has_method("send_current_state"):
			item.send_current_state(peer_id)

		return
