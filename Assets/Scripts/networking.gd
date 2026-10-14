
extends Node


signal host_created()
signal client_connected()


enum ConnectionMode {
	NONE,
	STEAM,
	LAN
}


# Steam settings
const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4

# LAN settings
const LAN_PORT := 7777
const LAN_MAX_MEMBERS := 4

# Scenes
const GAME_SCENE := "res://Assets/Scenes/Main.tscn"
const MAIN_MENU_SCENE := "res://Assets/Scenes/main_menu.tscn"
const CONNECTION_SCREEN = preload("res://Assets/Scenes/connection_screen.tscn")


# Connection state
var peer: MultiplayerPeer
var connection_mode := ConnectionMode.NONE
var lobby_id: int = 0
var is_host := false

var _host_steam_id: int = 0
var _lan_address := "127.0.0.1"

var _transitioning := false
var _leaving := false

var _connection_screen: CanvasLayer


func _ready() -> void:
	Steam.initRelayNetworkAccess()

	Steam.lobby_created.connect(on_lobby_created)
	Steam.lobby_joined.connect(on_lobby_joined)
	Steam.join_requested.connect(on_join_requested)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	Steam.run_callbacks()


# Check whether we can begin a connection.
func _can_start_connection() -> bool:
	return (
		not _transitioning
		and not _leaving
		and connection_mode == ConnectionMode.NONE
		and peer == null
		and lobby_id == 0
	)


# ==================================================
# STEAM HOSTING
# ==================================================

func host_lobby() -> void:
	if not _can_start_connection():
		return

	connection_mode = ConnectionMode.STEAM

	print("Creating Steam lobby...")
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)


func on_lobby_created(
	result: int,
	new_lobby_id: int
) -> void:
	if _leaving or connection_mode != ConnectionMode.STEAM:
		if result == Steam.RESULT_OK:
			Steam.leaveLobby(new_lobby_id)
		return

	if result != Steam.RESULT_OK:
		push_error("Failed to create Steam lobby.")
		connection_mode = ConnectionMode.NONE
		return

	lobby_id = new_lobby_id
	is_host = true

	var steam_peer := SteamMultiplayerPeer.new()
	steam_peer.server_relay = true

	var error: Error = steam_peer.create_host()

	if error != OK:
		push_error("Failed to create Steam host.")
		steam_peer.close()
		_leave_lobby()
		is_host = false
		connection_mode = ConnectionMode.NONE
		return

	peer = steam_peer
	multiplayer.multiplayer_peer = peer

	print("Steam lobby created: ", lobby_id)
	host_created.emit()

	_enter_game.call_deferred()


# ==================================================
# STEAM JOINING
# ==================================================

func on_lobby_joined(
	new_lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("Failed to join Steam lobby.")

		if connection_mode == ConnectionMode.STEAM and not is_host:
			connection_mode = ConnectionMode.NONE
		return

	if _leaving:
		Steam.leaveLobby(new_lobby_id)
		return

	# Host receives this callback for its own lobby.
	if Steam.getLobbyOwner(new_lobby_id) == Steam.getSteamID():
		return

	if connection_mode != ConnectionMode.STEAM:
		Steam.leaveLobby(new_lobby_id)
		return

	lobby_id = new_lobby_id
	is_host = false
	_host_steam_id = Steam.getLobbyOwner(lobby_id)

	print("Joined Steam lobby: ", lobby_id)
	print("Preparing game scene before connecting...")

	_enter_game.call_deferred()


func on_join_requested(
	requested_lobby_id: int,
	_friend_steam_id: int
) -> void:
	if not _can_start_connection():
		return

	connection_mode = ConnectionMode.STEAM

	print("Steam join requested: ", requested_lobby_id)
	Steam.joinLobby(requested_lobby_id)


# ==================================================
# LAN HOSTING
# ==================================================

func host_lan() -> void:
	if not _can_start_connection():
		return

	print("Creating LAN server on UDP port ", LAN_PORT)

	var enet_peer := ENetMultiplayerPeer.new()

	var error: Error = enet_peer.create_server(
		LAN_PORT,
		LAN_MAX_MEMBERS
	)

	if error != OK:
		push_error("Failed to create LAN server: " + str(error))
		return

	peer = enet_peer
	connection_mode = ConnectionMode.LAN
	is_host = true

	multiplayer.multiplayer_peer = peer

	print("LAN server created successfully.")
	host_created.emit()

	_enter_game.call_deferred()


# ==================================================
# LAN JOINING
# ==================================================

func join_lan(ip_address: String) -> void:
	if not _can_start_connection():
		return

	ip_address = ip_address.strip_edges()

	if ip_address.is_empty():
		ip_address = "127.0.0.1"

	_lan_address = ip_address
	connection_mode = ConnectionMode.LAN
	is_host = false

	print("Preparing LAN game scene...")
	print("LAN server address: ", _lan_address)

	# Preserve scene-first connection.
	_enter_game.call_deferred()


# ==================================================
# GAME SCENE
# ==================================================

func _enter_game() -> void:
	if _transitioning or _leaving:
		return

	_transitioning = true

	var error: Error = get_tree().change_scene_to_file(
		GAME_SCENE
	)

	if error != OK:
		push_error("Failed to load game scene: " + str(error))
		_transitioning = false
		leave_game()
		return

	await get_tree().scene_changed

	if _leaving:
		_transitioning = false
		return

	print("Game scene loaded.")

	if is_host:
		print("Host game ready.")
	else:
		if connection_mode == ConnectionMode.LAN:
			_show_connection_screen()

		_connect_to_host()

	_transitioning = false


# ==================================================
# CLIENT CONNECTION
# ==================================================

func _connect_to_host() -> void:
	if _leaving:
		return

	match connection_mode:
		ConnectionMode.STEAM:
			_connect_steam_client()

		ConnectionMode.LAN:
			_connect_lan_client()

		_:
			push_error("No connection mode selected.")
			leave_game()


func _connect_steam_client() -> void:
	print("Starting Steam client connection...")

	var steam_peer := SteamMultiplayerPeer.new()
	steam_peer.server_relay = true

	var error: Error = steam_peer.create_client(
		_host_steam_id
	)

	if error != OK:
		push_error("Failed to create Steam client.")
		steam_peer.close()
		leave_game()
		return

	peer = steam_peer

	# Main.tscn exists before connecting.
	multiplayer.multiplayer_peer = peer

	print("Waiting for Steam host connection...")


func _connect_lan_client() -> void:
	print("Connecting to LAN server: ", _lan_address)

	var enet_peer := ENetMultiplayerPeer.new()

	var error: Error = enet_peer.create_client(
		_lan_address,
		LAN_PORT
	)

	if error != OK:
		push_error("Failed to create LAN client: " + str(error))
		_show_lan_connection_failed()
		return

	peer = enet_peer

	# Main.tscn exists before connecting.
	multiplayer.multiplayer_peer = peer

	print("Waiting for LAN host connection...")


# ==================================================
# CONNECTION SCREEN
# ==================================================

func _show_connection_screen() -> void:
	if is_instance_valid(_connection_screen):
		return

	_connection_screen = CONNECTION_SCREEN.instantiate()
	get_tree().root.add_child(_connection_screen)

	_connection_screen.connection_timed_out.connect(
		_on_lan_connection_timeout
	)


func _hide_connection_screen() -> void:
	if is_instance_valid(_connection_screen):
		_connection_screen.queue_free()

	_connection_screen = null


func _on_lan_connection_timeout() -> void:
	if connection_mode != ConnectionMode.LAN or _leaving or is_host:
		return

	print("LAN connection timed out.")
	_show_lan_connection_failed()


func _show_lan_connection_failed() -> void:
	if _leaving:
		return

	if not is_instance_valid(_connection_screen):
		leave_game()
		return

	if _connection_screen.connection_failed:
		return

	# Cancel the pending connection.
	if peer != null:
		peer.close()

	multiplayer.multiplayer_peer = null
	peer = null

	_connection_screen.show_connection_failed()


# ==================================================
# CONNECTION CALLBACKS
# ==================================================

func _on_connected_to_server() -> void:
	if is_host or _leaving:
		return

	# Ignore a late connection after LAN timeout.
	if connection_mode == ConnectionMode.LAN:
		if is_instance_valid(_connection_screen):
			if _connection_screen.connection_failed:
				return

	_hide_connection_screen()

	match connection_mode:
		ConnectionMode.STEAM:
			print("Connected to Steam host.")

		ConnectionMode.LAN:
			print("Connected to LAN host.")

	client_connected.emit()

	# Keep existing player synchronization.
	var game_scene := get_tree().current_scene

	if game_scene != null and game_scene.has_method("start_client_sync"):
		game_scene.start_client_sync()


func _on_connection_failed() -> void:
	if _leaving:
		return

	if connection_mode == ConnectionMode.LAN:
		_show_lan_connection_failed()
		return

	push_error("Failed to connect to Steam host.")
	leave_game()


func _on_server_disconnected() -> void:
	if _leaving:
		return

	print("Host disconnected. Returning to Main Menu.")
	leave_game()


# ==================================================
# DISCONNECT AND CLEANUP
# ==================================================

func leave_game() -> void:
	if _leaving:
		return

	_leaving = true

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("Leaving multiplayer session...")

	_hide_connection_screen()

	if peer != null:
		peer.close()

	multiplayer.multiplayer_peer = null
	peer = null

	# Only leave Steam lobby for Steam connections.
	if connection_mode == ConnectionMode.STEAM:
		_leave_lobby()

	connection_mode = ConnectionMode.NONE
	is_host = false
	_host_steam_id = 0
	_lan_address = "127.0.0.1"
	_transitioning = false

	_return_to_menu.call_deferred()


func _leave_lobby() -> void:
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0


func _return_to_menu() -> void:
	var error: Error = get_tree().change_scene_to_file(
		MAIN_MENU_SCENE
	)

	if error != OK:
		push_error("Failed to return to Main Menu: " + str(error))
		_leaving = false
		return

	await get_tree().scene_changed

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("Returned to Main Menu.")
	_leaving = false
