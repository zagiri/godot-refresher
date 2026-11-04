extends Node


@export_group("Contents")
@export var contents_scene: PackedScene
@export var contents_name := "Fries Bag"
@export_range(1, 100, 1) var starting_quantity := 4

@export_group("Contents Display")
# Use a visual-only GLB/scene, not the pickup scene with physics and scripts.
@export var contents_display_scene: PackedScene
@export var contents_container_path := NodePath("../Box_Open/Contents")
@export_range(1, 20, 1) var display_columns := 4
@export_range(1, 20, 1) var display_rows := 1
@export var display_spacing := Vector3(0.202, 0.45, 0.22)
@export var display_origin := Vector3(0.01, -0.3297065, 0.0)
@export var display_rotation_degrees := Vector3(0.0, -90.0, 0.0)
@export var display_scale := Vector3(2.5, 1.5, 2.5)

@export_group("Interaction")
@export var interaction_distance := 2.5


@onready var _carton: RigidBody3D = get_parent()
@onready var _animation: AnimationPlayer = $"../AnimationPlayer"
@onready var _box_closed: Node3D = $"../Box_Closed"
@onready var _box_open: Node3D = $"../Box_Open"
@onready var _interactable: Interactable = $"../InteractableBase"
@onready var _contents_container: Node3D = get_node_or_null(contents_container_path) as Node3D


var is_open := false
var remaining_quantity := 0
var _taking_item := false
var _prompt_target: Interactable = null
var _generated_visuals: Array[Node3D] = []


func _ready() -> void:
	add_to_group("sync_equipment")
	remaining_quantity = starting_quantity
	_animation.animation_finished.connect(_on_animation_finished)
	_build_contents_visuals()
	_apply_visual_state()
	_update_contents_visuals()
	_refresh_ui_mesh_cache.call_deferred()

	if not InputMap.has_action("take_contents"):
		push_warning("Add take_contents to the Input Map and bind it to G.")


func _process(_delta: float) -> void:
	_update_prompts()


func _get_player(peer_id: int) -> CharacterBody3D:
	var main := get_tree().current_scene
	if main == null:
		return null
	return main.get_node_or_null(str(peer_id)) as CharacterBody3D


func _get_local_player() -> CharacterBody3D:
	return _get_player(multiplayer.get_unique_id())


func _is_held_by(player: CharacterBody3D) -> bool:
	return (
		is_instance_valid(player)
		and _carton.get("held_by") == player
		and player.get("held_item") == _carton
	)


func _is_in_reach(player: CharacterBody3D) -> bool:
	return player.global_position.distance_to(_carton.global_position) <= interaction_distance


# Supports the carton itself and its occupied placement slot.
func _get_carton_target(player: CharacterBody3D) -> Interactable:
	if not is_instance_valid(player) or not player.has_method("get_targeted_interactable"):
		return null
	var target := player.call("get_targeted_interactable") as Interactable
	if not is_instance_valid(target) or not target.interaction_enabled:
		return null
	if _carton.is_ancestor_of(target):
		return target
	var equipment := target.get_parent()
	if equipment.has_method("get_ui_anchor_item"):
		if equipment.call("get_ui_anchor_item") == _carton:
			return target
	return null


func _clear_extra_prompts(target: Interactable) -> void:
	if is_instance_valid(target):
		target.set_secondary_prompt("")
		target.set_tertiary_prompt("")


func _set_prompt_target(target: Interactable) -> void:
	if _prompt_target == target:
		return
	_clear_extra_prompts(_prompt_target)
	_prompt_target = target


func _update_prompts() -> void:
	var player := _get_local_player()
	var toggle_text := "Close Carton" if is_open else "Open Carton"
	var busy := _animation.is_playing()

	if _is_held_by(player) and not busy:
		_interactable.set_held_prompt(toggle_text, "F")
	else:
		_interactable.clear_held_prompt()

	var target: Interactable = null
	if is_instance_valid(player) and not busy:
		# Held cartons own F; a carton on the ground needs free hands.
		if not is_instance_valid(player.get("held_item")):
			if not is_instance_valid(_carton.get("held_by")) and _is_in_reach(player):
				target = _get_carton_target(player)
	_set_prompt_target(target)
	if not is_instance_valid(_prompt_target):
		return

	_prompt_target.set_secondary_prompt(toggle_text, "F")
	if not is_open:
		_prompt_target.set_tertiary_prompt("")
	elif remaining_quantity <= 0:
		_prompt_target.set_tertiary_prompt("Empty", "—")
	else:
		_prompt_target.set_tertiary_prompt(
			"Take %s (%d left)" % [contents_name, remaining_quantity], "G"
		)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var wants_toggle := event.is_action_pressed("open_carton")
	var wants_take := (
		InputMap.has_action("take_contents")
		and event.is_action_pressed("take_contents")
	)
	if not wants_toggle and not wants_take:
		return
	var player := _get_local_player()
	if not is_instance_valid(player) or not player.is_multiplayer_authority():
		return
	if _animation.is_playing():
		return

	if _is_held_by(player):
		if not wants_toggle:
			return
	else:
		if is_instance_valid(player.get("held_item")):
			return
		if is_instance_valid(_carton.get("held_by")) or not _is_in_reach(player):
			return
		if _get_carton_target(player) == null:
			return

	if wants_toggle:
		get_viewport().set_input_as_handled()
		# Request the desired state so duplicate requests cannot double-toggle.
		if multiplayer.is_server():
			_server_try_set_open(multiplayer.get_unique_id(), not is_open)
		else:
			_request_set_open.rpc_id(1, not is_open)
	elif is_open and remaining_quantity > 0:
		get_viewport().set_input_as_handled()
		if multiplayer.is_server():
			_server_try_take(multiplayer.get_unique_id())
		else:
			_request_take.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_set_open(opened: bool) -> void:
	if multiplayer.is_server():
		_server_try_set_open(multiplayer.get_remote_sender_id(), opened)


func _server_try_set_open(peer_id: int, opened: bool) -> void:
	if not multiplayer.is_server() or opened == is_open:
		return
	if _taking_item or _animation.is_playing():
		return
	var player := _get_player(peer_id)
	if not is_instance_valid(player) or player.get_multiplayer_authority() != peer_id:
		return
	var holder := _carton.get("held_by") as CharacterBody3D
	if is_instance_valid(holder):
		if not _is_held_by(player):
			return
	else:
		if not _is_in_reach(player) or is_instance_valid(player.get("held_item")):
			return
	_sync_open_state.rpc(opened, true)


@rpc("any_peer", "call_remote", "reliable")
func _request_take() -> void:
	if multiplayer.is_server():
		_server_try_take(multiplayer.get_remote_sender_id())


func _server_try_take(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _taking_item or not is_open or remaining_quantity <= 0:
		return
	if _animation.is_playing() or is_instance_valid(_carton.get("held_by")):
		return
	if contents_scene == null:
		push_warning("Assign the carton's Contents Scene.")
		return
	var main := get_tree().current_scene
	if main == null or not main.has_method("spawn_pickup_item"):
		return
	var player := _get_player(peer_id)
	if not is_instance_valid(player) or player.get_multiplayer_authority() != peer_id:
		return
	if is_instance_valid(player.get("held_item")) or not _is_in_reach(player):
		return

	_taking_item = true
	var item_transform := Transform3D(Basis.IDENTITY, player.global_position + Vector3.UP)
	var item := main.call("spawn_pickup_item", contents_scene, item_transform) as RigidBody3D
	if not is_instance_valid(item):
		_taking_item = false
		return
	if not item.has_method("_server_pickup"):
		item.queue_free()
		_taking_item = false
		push_warning("Contents Scene must use the PickupItem script.")
		return

	item.call("_server_pickup", peer_id)
	if player.get("held_item") != item:
		item.queue_free()
		_taking_item = false
		push_warning("The spawned product could not be picked up; carton stock was preserved.")
		return
	remaining_quantity -= 1
	_sync_contents.rpc(remaining_quantity)
	_taking_item = false


@rpc("authority", "call_local", "reliable")
func _sync_open_state(opened: bool, animate: bool) -> void:
	if not is_node_ready():
		await ready
	var changed := is_open != opened
	is_open = opened
	if changed and animate and _animation.has_animation("OpenBox"):
		if is_open:
			_animation.play("OpenBox")
		else:
			_animation.play_backwards("OpenBox")
		_animation.advance(0.0)
	else:
		_apply_visual_state()
	_update_prompts()


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


# Created on each peer from identical settings. These are visual models only;
# the real pickup is spawned by Main only after the host accepts G.
func _build_contents_visuals() -> void:
	if _contents_container == null:
		push_warning("Carton needs Box_Open/Contents, or an assigned Contents Container Path.")
		return
	if contents_display_scene == null:
		push_warning("Assign Contents Display Scene to the product's visual-only GLB.")
		return

	for index in range(starting_quantity):
		var instance := contents_display_scene.instantiate()
		if not instance is Node3D or not _is_visual_only(instance):
			instance.free()
			push_warning("Contents Display Scene must be a model without scripts, physics or multiplayer nodes.")
			return
		var visual := instance as Node3D
		visual.name = "ProductDisplay_%d" % index
		visual.transform = _display_transform(index)
		_contents_container.add_child(visual)
		_generated_visuals.append(visual)


func _is_visual_only(node: Node) -> bool:
	if node.get_script() != null or node is CollisionObject3D:
		return false
	if node is MultiplayerSpawner or node is MultiplayerSynchronizer:
		return false
	for child in node.get_children():
		if not _is_visual_only(child):
			return false
	return true


func _display_transform(index: int) -> Transform3D:
	var columns := maxi(display_columns, 1)
	var rows := maxi(display_rows, 1)
	var per_layer := columns * rows
	var layer := floori(float(index) / per_layer)
	var cell := index % per_layer
	var row := floori(float(cell) / columns)
	var column := cell % columns
	# Center each initial layer, keeping positions fixed as stock is removed.
	var layer_count := mini(starting_quantity - layer * per_layer, per_layer)
	var used_rows := ceili(float(layer_count) / columns)
	var row_count := mini(layer_count - row * columns, columns)
	var offset := Vector3(
		(float(column) - float(row_count - 1) * 0.5) * display_spacing.x,
		layer * display_spacing.y,
		(float(row) - float(used_rows - 1) * 0.5) * display_spacing.z
	)
	var angles := display_rotation_degrees * (PI / 180.0)
	var basis := Basis.from_euler(angles) * Basis.from_scale(display_scale)
	return Transform3D(basis, display_origin + offset)


func _update_contents_visuals() -> void:
	for index in range(_generated_visuals.size()):
		_generated_visuals[index].visible = index < remaining_quantity


func _refresh_ui_mesh_cache() -> void:
	var ui := _carton.get_node_or_null("EquipmentUI") as EquipmentUI
	if ui != null:
		ui.refresh_mesh_cache()
	# Placement slots may have cached this item before visuals were created.
	for node in get_tree().get_nodes_in_group("sync_equipment"):
		if node.has_method("get_ui_anchor_item") and node.call("get_ui_anchor_item") == _carton:
			var slot_ui := node.get_node_or_null("EquipmentUI") as EquipmentUI
			if slot_ui != null:
				slot_ui.refresh_mesh_cache()


func _exit_tree() -> void:
	_clear_extra_prompts(_prompt_target)
