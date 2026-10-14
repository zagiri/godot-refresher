
extends Node3D


# Player scene
const PLAYER_CONTROLLER = preload("uid://cps4dh3kjo074")


# Player data
var players: Array[CharacterBody3D] = []


func _ready() -> void:
	print(
		"MAIN LOADED | Host: ",
		Networking.is_host
	)

	if Networking.is_host:
		# Host manages spawning and disconnections
		multiplayer.peer_disconnected.connect(
			_on_peer_disconnected
		)

		spawn_player(multiplayer.get_unique_id())


# Client starts synchronization after connecting
func start_client_sync() -> void:
	if Networking.is_host:
		return

	print("CLIENT: Gameplay loaded and connected.")

	_notify_server_ready.call_deferred()


# Notify host that gameplay is ready
func _notify_server_ready() -> void:
	if Networking.is_host:
		return

	if multiplayer.multiplayer_peer == null:
		return

	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return

	print("CLIENT: Notifying host.")

	_client_ready.rpc_id(1)


# Host receives client readiness
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	print("HOST: Client ready: ", peer_id)

	# Spawn the joining player
	if not _has_player(peer_id):
		spawn_player(peer_id)

	# Send current equipment states
	for equipment in get_tree().get_nodes_in_group(
		"sync_equipment"
	):
		if equipment.has_method("send_current_state"):
			equipment.send_current_state(peer_id)


# Spawn player on the server
func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if _has_player(peer_id):
		return

	var new_player := PLAYER_CONTROLLER.instantiate() as CharacterBody3D

	# Player authority is assigned from this name
	new_player.name = str(peer_id)

	# Set position before adding the player
	new_player.position = $SpawnPoint.position

	# MultiplayerSpawner replicates the player
	add_child(new_player)

	initialize_player(new_player)

	print("PLAYER SPAWNED: ", peer_id)


# Register a player
func initialize_player(player: CharacterBody3D) -> void:
	if not players.has(player):
		players.append(player)


# Check if player already exists
func _has_player(peer_id: int) -> bool:
	for player in players:
		if not is_instance_valid(player):
			continue

		if player.get_multiplayer_authority() == peer_id:
			return true

	return false


# Remove disconnected players
func _on_peer_disconnected(peer_id: int) -> void:
	for player in players:
		if not is_instance_valid(player):
			continue

		if player.get_multiplayer_authority() == peer_id:
			players.erase(player)
			player.queue_free()

			print("PLAYER DISCONNECTED: ", peer_id)
			return


# Called when MultiplayerSpawner replicates a player
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
