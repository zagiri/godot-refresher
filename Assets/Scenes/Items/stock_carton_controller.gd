extends Node


@export_group("Contents")
@export var contents_scene: PackedScene
@export var contents_name := "Fries Bag"
@export_range(1, 100, 1) var starting_quantity := 4
@export var contents_visuals: Array[Node3D] = []

@export_group("Interaction")
@export var interaction_distance := 2.5


@onready var _carton: RigidBody3D = get_parent()
@onready var _animation: AnimationPlayer = $"../AnimationPlayer"
@onready var _box_closed: Node3D = $"../Box_Closed"
@onready var _box_open: Node3D = $"../Box_Open"
@onready var _interactable: Interactable = $"../InteractableBase"


var is_open := false
var remaining_quantity := 0

var _taking_item := false
var _prompt_target: Interactable = null


func _ready() -> void:
	add_to_group("sync_equipment")

	remaining_quantity = starting_quantity

	_animation.animation_finished.connect(_on_animation_finished)

	_apply_visual_state()
	_update_contents_visuals()


func _process(_delta: float) -> void:
	_update_prompts()


func _get_local_player() -> CharacterBody3D:
	var main := get_tree().current_scene

	if main == null:
		return null

	return main.get_node_or_null(
		str(multiplayer.get_unique_id())
	) as CharacterBody3D


func _is_held_by(player: CharacterBody3D) -> bool:
	if not is_instance_valid(player):
		return false

	return (
		_carton.get("held_by") == player
		and player.get("held_item") == _carton
	)


# Supports targeting the carton directly or its occupied placement slot.
func _get_carton_target(player: CharacterBody3D) -> Interactable:
	if not is_instance_valid(player):
		return null

	if not player.has_method("get_targeted_interactable"):
		return null

	var target := player.call(
		"get_targeted_interactable"
	) as Interactable

	if not is_instance_valid(target):
		return null

	if not target.interaction_enabled:
		return null

	if _carton.is_ancestor_of(target):
		return target

	var equipment := target.get_parent()

	if equipment.has_method("get_ui_anchor_item"):
		if equipment.call("get_ui_anchor_item") == _carton:
			return target

	return null


func _set_prompt_target(target: Interactable) -> void:
	if _prompt_target == target:
		return

	if is_instance_valid(_prompt_target):
		_prompt_target.set_secondary_prompt("")

	_prompt_target = target


func _update_prompts() -> void:
	var player := _get_local_player()

	if _is_held_by(player) and not is_open:
		_interactable.set_held_prompt("Open Carton", "F")
	else:
		_interactable.clear_held_prompt()

	var target: Interactable = null

	if is_instance_valid(player):
		if is_open and not is_instance_valid(_carton.get("held_by")):
			target = _get_carton_target(player)

	_set_prompt_target(target)

	if not is_instance_valid(_prompt_target):
		return

	if _animation.is_playing():
		_prompt_target.set_secondary_prompt("")
		return

	if remaining_quantity <= 0:
		_prompt_target.set_secondary_prompt("Empty", "—")
		return

	if is_instance_valid(player.get("held_item")):
		_prompt_target.set_secondary_prompt("")
		return

	_prompt_target.set_secondary_prompt(
		"Take %s (%d left)" % [contents_name, remaining_quantity],
		"F"
	)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("open_carton") or event.is_echo():
		return

	var player := _get_local_player()

	if not is_instance_valid(player):
		return

	if not player.is_multiplayer_authority():
		return

	if not is_open:
		if not _is_held_by(player):
			return

		get_viewport().set_input_as_handled()

		if multiplayer.is_server():
			_server_try_open(multiplayer.get_unique_id())
		else:
			_request_open.rpc_id(1)

		return

	if remaining_quantity <= 0 or _animation.is_playing():
		return

	if is_instance_valid(_carton.get("held_by")):
		return

	if is_instance_valid(player.get("held_item")):
		return

	if _get_carton_target(player) == null:
		return

	get_viewport().set_input_as_handled()

	if multiplayer.is_server():
		_server_try_take(multiplayer.get_unique_id())
	else:
		_request_take.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_open() -> void:
	if not multiplayer.is_server():
		return

	_server_try_open(multiplayer.get_remote_sender_id())


func _server_try_open(peer_id: int) -> void:
	if not multiplayer.is_server() or is_open:
		return

	var holder := _carton.get("held_by") as CharacterBody3D

	if not is_instance_valid(holder):
		return

	if holder.get_multiplayer_authority() != peer_id:
		return

	if not _is_held_by(holder):
		return

	_sync_open_state.rpc(true, true)


@rpc("any_peer", "call_remote", "reliable")
func _request_take() -> void:
	if not multiplayer.is_server():
		return

	_server_try_take(multiplayer.get_remote_sender_id())


func _server_try_take(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if _taking_item or not is_open or remaining_quantity <= 0:
		return

	if _animation.is_playing():
		return

	if is_instance_valid(_carton.get("held_by")):
		return

	if contents_scene == null:
		push_warning("Assign the carton's Contents Scene.")
		return

	var main := get_tree().current_scene

	if main == null or not main.has_method("spawn_pickup_item"):
		return

	var player := main.get_node_or_null(
		str(peer_id)
	) as CharacterBody3D

	if not is_instance_valid(player):
		return

	if player.get_multiplayer_authority() != peer_id:
		return

	if is_instance_valid(player.get("held_item")):
		return

	if player.global_position.distance_to(
		_carton.global_position
	) > interaction_distance:
		return

	_taking_item = true

	# Spawn close to the player so PickupItem's distance check passes.
	var item_transform := Transform3D(
		Basis.IDENTITY,
		player.global_position + Vector3.UP
	)

	var item := main.call(
		"spawn_pickup_item",
		contents_scene,
		item_transform
	) as RigidBody3D

	if not is_instance_valid(item):
		_taking_item = false
		return

	if not item.has_method("_server_pickup"):
		item.queue_free()
		_taking_item = false
		push_warning("Contents Scene must use the PickupItem script.")
		return

	# Use the existing server-authoritative pickup behaviour.
	item.call("_server_pickup", peer_id)

	if player.get("held_item") != item:
		item.queue_free()
		_taking_item = false
		return

	remaining_quantity -= 1
	_sync_contents.rpc(remaining_quantity)

	_taking_item = false


@rpc("authority", "call_local", "reliable")
func _sync_open_state(opened: bool, animate: bool) -> void:
	if not is_node_ready():
		await ready

	var was_open := is_open
	is_open = opened

	_update_prompts()

	if is_open and not was_open and animate:
		if _animation.has_animation("OpenBox"):
			_animation.play("OpenBox")
			return

	_apply_visual_state()


@rpc("authority", "call_local", "reliable")
func _sync_contents(quantity: int) -> void:
	if not is_node_ready():
		await ready

	remaining_quantity = clampi(quantity, 0, starting_quantity)

	_update_contents_visuals()
	_update_prompts()


func send_current_state(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	_sync_open_state.rpc_id(peer_id, is_open, false)
	_sync_contents.rpc_id(peer_id, remaining_quantity)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"OpenBox":
		_apply_visual_state()
		_update_prompts()


func _apply_visual_state() -> void:
	_animation.stop()

	_box_closed.visible = not is_open
	_box_open.visible = is_open


func _update_contents_visuals() -> void:
	for index in range(contents_visuals.size()):
		var visual := contents_visuals[index]

		if is_instance_valid(visual):
			visual.visible = index < remaining_quantity


func _exit_tree() -> void:
	if is_instance_valid(_prompt_target):
		_prompt_target.set_secondary_prompt("")
