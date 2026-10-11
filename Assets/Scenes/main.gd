
extends Node3D


const PLAYER_CONTROLLER = preload("uid://cps4dh3kjo074")

var players: Array[CharacterBody3D]


func _ready() -> void:
	Networking.host_created.connect(on_host_created)

	multiplayer.connected_to_server.connect(
		_on_connected_to_server
	)


# Host initialization
func on_host_created() -> void:
	spawn_player(multiplayer.get_unique_id())

	multiplayer.peer_connected.connect(spawn_player)


# Client tells the host its game scene is ready
func _on_connected_to_server() -> void:
	await get_tree().process_frame

	_client_ready.rpc_id(1)


# Host sends equipment states to joining client
@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()

	print("Client ready: ", sender_id)

	for equipment in get_tree().get_nodes_in_group("sync_equipment"):
		if equipment.has_method("send_current_state"):
			equipment.send_current_state(sender_id)


# Spawn player
func spawn_player(peer_id: int) -> void:
	var new_player := PLAYER_CONTROLLER.instantiate() as CharacterBody3D

	new_player.name = str(peer_id)
	add_child(new_player)

	initialize_player(new_player)


# Initialize player
func initialize_player(player: CharacterBody3D) -> void:
	player.position = $SpawnPoint.position
	players.append(player)


# Host button
func _on_host_pressed() -> void:
	Networking.host_lobby()
	$CanvasLayer/Host.queue_free()


# MultiplayerSpawner callback
func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node is CharacterBody3D:
		initialize_player(node)
