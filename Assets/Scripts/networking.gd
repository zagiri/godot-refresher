
extends Node


signal host_created()
signal client_connected()


const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4

const GAME_SCENE := "res://Assets/Scenes/Main.tscn"
const MAIN_MENU_SCENE := "res://Assets/Scenes/main_menu.tscn"


var peer: SteamMultiplayerPeer
var lobby_id: int = 0
var is_host := false

var _host_steam_id: int = 0
var _transitioning := false
var _leaving := false


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


func host_lobby() -> void:
	if _transitioning or _leaving or lobby_id != 0:
		return

	print("Creating Steam lobby...")
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)


func on_lobby_created(
	result: int,
	new_lobby_id: int
) -> void:
	if result != Steam.RESULT_OK:
		push_error("Failed to create Steam lobby.")
		return

	if _leaving:
		Steam.leaveLobby(new_lobby_id)
		return

	lobby_id = new_lobby_id
	is_host = true

	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true

	var error: Error = peer.create_host()

	if error != OK:
		push_error("Failed to create Steam host.")
		_leave_lobby()
		peer = null
		is_host = false
		return

	multiplayer.multiplayer_peer = peer

	print("Steam lobby created: ", lobby_id)
	host_created.emit()

	_enter_game.call_deferred()


func on_lobby_joined(
	new_lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("Failed to join Steam lobby.")
		return

	if _leaving:
		Steam.leaveLobby(new_lobby_id)
		return

	lobby_id = new_lobby_id

	if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
		return

	is_host = false
	_host_steam_id = Steam.getLobbyOwner(lobby_id)

	print("Joined Steam lobby: ", lobby_id)
	print("Preparing game scene before connecting...")

	_enter_game.call_deferred()


func _enter_game() -> void:
	if _transitioning or _leaving:
		return

	_transitioning = true

	var error: Error = get_tree().change_scene_to_file(GAME_SCENE)

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
		_connect_to_host()

	_transitioning = false


func _connect_to_host() -> void:
	if _leaving:
		return

	print("Starting Steam client connection...")

	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true

	var error: Error = peer.create_client(_host_steam_id)

	if error != OK:
		push_error("Failed to create Steam client.")
		peer = null
		leave_game()
		return

	# The game scene exists before the client connects.
	multiplayer.multiplayer_peer = peer

	print("Waiting for Steam host connection...")


func _on_connected_to_server() -> void:
	if is_host or _leaving:
		return

	print("Connected to Steam host.")
	client_connected.emit()

	var game_scene := get_tree().current_scene

	if game_scene != null and game_scene.has_method("start_client_sync"):
		game_scene.start_client_sync()


func on_join_requested(
	requested_lobby_id: int,
	_friend_steam_id: int
) -> void:
	if _transitioning or _leaving or lobby_id != 0:
		return

	print("Steam join requested: ", requested_lobby_id)
	Steam.joinLobby(requested_lobby_id)


func _on_connection_failed() -> void:
	if _leaving:
		return

	push_error("Failed to connect to Steam host.")
	leave_game()


func _on_server_disconnected() -> void:
	if _leaving:
		return

	print("Host disconnected. Returning to Main Menu.")
	leave_game()


# Leave the game and clean up the Steam session.
func leave_game() -> void:
	if _leaving:
		return

	_leaving = true

	# Restore mouse control.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("Leaving multiplayer session...")

	if peer != null:
		peer.close()

	multiplayer.multiplayer_peer = null
	peer = null

	_leave_lobby()

	is_host = false
	_host_steam_id = 0
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

	# Final safeguard after gameplay nodes are removed.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("Returned to Main Menu.")
	_leaving = false
