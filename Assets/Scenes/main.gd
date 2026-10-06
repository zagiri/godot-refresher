extends Node3D

const PLAYER_CONTROLLER = preload("uid://cps4dh3kjo074")
var players: Array[CharacterBody3D]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Networking.host_created.connect(on_host_created)
	
func on_host_created() -> void:
	spawn_player(multiplayer.get_unique_id())
	multiplayer.peer_connected.connect(spawn_player)

func spawn_player(peer_id:int) -> void:
	var new_player := PLAYER_CONTROLLER.instantiate() as CharacterBody3D
	new_player.name = str(peer_id)
	add_child(new_player)
	initialize_player(new_player)

func initialize_player(player: CharacterBody3D) -> void:
	player.position = $SpawnPoint.position
	players.append(player)

func _on_host_pressed() -> void:
	Networking.host_lobby()
	$CanvasLayer/Host.queue_free()

func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node is CharacterBody3D:
		initialize_player(node)
