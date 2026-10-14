
extends Node3D


const PLAYER_CONTROLLER = preload("uid://cps4dh3kjo074")


var players: Array[CharacterBody3D] = []


func _ready() -> void:
	print("MAIN LOADED | Host: ", Networking.is_host)

	if Networking.is_host:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

		spawn_player(multiplayer.get_unique_id())


# ==================================================
# CLIENT CONNECTION
# ==================================================

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

	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	print("CLIENT: Notifying host.")

	_client_ready.rpc_id(1)


# ==================================================
# SERVER PLAYER SPAWNING
# ==================================================

@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()

	print("HOST: Client ready: ", peer_id)

	if not _has_player(peer_id):
		spawn_player(peer_id)

	# Synchronize existing equipment, including the fryer.
	for equipment in get_tree().get_nodes_in_group("sync_equipment"):
		if equipment.has_method("send_current_state"):
			equipment.send_current_state(peer_id)

	# Synchronize existing pickup items for late joiners.
	for item in get_tree().get_nodes_in_group("sync_pickup_items"):
		if item.has_method("send_current_state"):
			item.send_current_state(peer_id)


# ==================================================
# SPAWN PLAYER
# ==================================================

func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if _has_player(peer_id):
		return

	var new_player := PLAYER_CONTROLLER.instantiate() as CharacterBody3D

	new_player.name = str(peer_id)
	new_player.position = $SpawnPoint.position

	# MultiplayerSpawner replicates the player.
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


# ==================================================
# PLAYER DISCONNECTION
# ==================================================

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("PLAYER DISCONNECTED: ", peer_id)

	# Release any items belonging to this player.
	for item in get_tree().get_nodes_in_group("sync_pickup_items"):
		if item.has_method("release_disconnected_player"):
			item.release_disconnected_player(peer_id)

	# Remove the disconnected player.
	for player in players:
		if not is_instance_valid(player):
			continue

		if player.get_multiplayer_authority() == peer_id:
			players.erase(player)
			player.queue_free()
			return

# ==================================================
# REPLICATED PLAYER SPAWNING
# ==================================================

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
