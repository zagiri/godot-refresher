
extends Node3D


# Fryer states
enum FryerState {
	IDLE,
	COOKING,
	READY
}


# Cooking settings
@export_group("Cooking")
@export var cooking_time := 5.0


# Multiplayer settings
@export_group("Multiplayer")
@export var interaction_distance := 3.5
@export var sync_interval := 1.0


# Node references
@onready var _interactable: Interactable = $InteractableBase
@onready var _equipment_ui: EquipmentUI = $EquipmentUI


# Cooking data
var _current_state: FryerState = FryerState.IDLE
var _cooking_timer: Timer
var _remaining_time := 0.0
var _sync_elapsed := 0.0


func _ready() -> void:
	add_to_group("sync_equipment")

	_interactable.interacted.connect(_on_interacted)

	_cooking_timer = Timer.new()
	_cooking_timer.one_shot = true
	add_child(_cooking_timer)

	_cooking_timer.timeout.connect(_on_cooking_finished)

	_equipment_ui.set_title(name)
	_update_ui()


# Update countdown
func _process(delta: float) -> void:
	if _current_state != FryerState.COOKING:
		return

	if multiplayer.is_server():
		_remaining_time = _cooking_timer.time_left

		_sync_elapsed += delta

		if _sync_elapsed >= sync_interval:
			_sync_elapsed = 0.0
			_broadcast_state()
	else:
		_remaining_time = maxf(
			_remaining_time - delta,
			0.0
		)

	_update_progress()


# Player interaction
func _on_interacted(player: Node) -> void:
	if multiplayer.is_server():
		_server_try_interact(
			player.get_multiplayer_authority()
		)
	else:
		_request_interaction.rpc_id(1)


# Client sends interaction request to host
@rpc("any_peer", "call_remote", "reliable")
func _request_interaction() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()

	_server_try_interact(sender_id)


# Host validates interaction
func _server_try_interact(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if not _is_player_nearby(peer_id):
		return

	match _current_state:
		FryerState.IDLE:
			_start_cooking()

		FryerState.COOKING:
			pass

		FryerState.READY:
			_collect_food()


# Check requesting player's distance
func _is_player_nearby(peer_id: int) -> bool:
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as CharacterBody3D

		if player == null:
			continue

		if player.get_multiplayer_authority() != peer_id:
			continue

		var distance: float = player.global_position.distance_to(
			_interactable.global_position
		)

		return distance <= interaction_distance

	return false


# Host starts cooking
func _start_cooking() -> void:
	if not multiplayer.is_server():
		return

	_current_state = FryerState.COOKING
	_remaining_time = maxf(cooking_time, 0.01)

	_cooking_timer.start(_remaining_time)

	_broadcast_state()


# Cooking completes
func _on_cooking_finished() -> void:
	if not multiplayer.is_server():
		return

	_current_state = FryerState.READY
	_remaining_time = 0.0

	_broadcast_state()


# Food collected
func _collect_food() -> void:
	if not multiplayer.is_server():
		return

	_cooking_timer.stop()

	_current_state = FryerState.IDLE
	_remaining_time = 0.0

	_broadcast_state()


# Send current state to all connected players
func _broadcast_state() -> void:
	if not multiplayer.is_server():
		return

	_sync_elapsed = 0.0

	_sync_state.rpc(
		_current_state,
		_remaining_time
	)


# Send current state to one joining player
func send_current_state(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var remaining := 0.0

	if _current_state == FryerState.COOKING:
		remaining = _cooking_timer.time_left

	_sync_state.rpc_id(
		peer_id,
		_current_state,
		remaining
	)


# Apply synchronized state
@rpc("authority", "call_local", "reliable")
func _sync_state(state: int, remaining: float) -> void:
	_current_state = state
	_remaining_time = maxf(remaining, 0.0)

	if not _equipment_ui.is_node_ready():
		await _equipment_ui.ready

	_update_ui()
	_update_progress()


# Update progress bar and countdown
func _update_progress() -> void:
	if _current_state != FryerState.COOKING:
		return

	var progress: float = 100.0 * (
		1.0 - _remaining_time / maxf(cooking_time, 0.01)
	)

	_equipment_ui.set_progress(progress)
	_equipment_ui.set_timer(_remaining_time)


# Update equipment interface
func _update_ui() -> void:
	match _current_state:
		FryerState.IDLE:
			_interactable.set_prompt_text("Use Fryer")
			_interactable.set_interaction_enabled(true)

			_equipment_ui.set_status("READY TO COOK")
			_equipment_ui.set_progress(0.0)
			_equipment_ui.set_timer(0.0)
			_equipment_ui.hide_status()

		FryerState.COOKING:
			_interactable.set_interaction_enabled(false)

			_equipment_ui.set_status("COOKING")
			_equipment_ui.show_status()

		FryerState.READY:
			_interactable.set_prompt_text("Grab Food")
			_interactable.set_interaction_enabled(true)

			_equipment_ui.set_status("FOOD READY!")
			_equipment_ui.set_progress(100.0)
			_equipment_ui.set_timer(0.0)
			_equipment_ui.show_status()
