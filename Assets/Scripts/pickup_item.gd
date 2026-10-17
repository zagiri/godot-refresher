
extends RigidBody3D

enum ItemState { WORLD, HELD, PLACED }

var item_state := ItemState.WORLD

@export_group("Item Data")
@export var item_data: ItemData

@export_group("Pickup")
@export var hold_offset := Vector3(0.0, 1.0, 1.0)

@export_group("Multiplayer")
@export var physics_sync_rate := 0.05
@export var interpolation_speed := 15.0

@export_group("Network Optimization")
@export var position_threshold := 0.02
@export var rotation_threshold := 2.0
@export var heartbeat_interval := 0.5

@onready var _interactable: Interactable = $InteractableBase

var held_by: CharacterBody3D = null
var placed_in: Node3D = null

var _original_collision_layer: int
var _original_collision_mask: int

var _physics_sync_timer := 0.0
var _heartbeat_timer := 0.0

var _pending_holder_id := 0
var _pending_slot_path := NodePath("")

var _target_transform := Transform3D.IDENTITY
var _has_physics_snapshot := false

var _last_sent_transform := Transform3D.IDENTITY
var _has_sent_physics := false

var _was_sleeping := false
var _remote_sleeping := false

var _physics_sequence := 0
var _last_received_sequence := -1


func _ready() -> void:
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask

	_interactable.interacted.connect(_on_interacted)
	_interactable.interaction_action = "Pick up"

	if item_data != null and not item_data.item_name.is_empty():
		_interactable.set_prompt_text("Pick up " + item_data.item_name)
	else:
		_interactable.set_prompt_text("Pick up " + name)

	add_to_group("sync_pickup_items")

	_target_transform = global_transform
	_last_sent_transform = global_transform

	if multiplayer.is_server():
		_was_sleeping = sleeping
	else:
		freeze = true


func _process(delta: float) -> void:
	if multiplayer.is_server():
		return

	if item_state != ItemState.WORLD:
		return

	if not _has_physics_snapshot:
		return

	if _pending_holder_id != 0 or not _pending_slot_path.is_empty():
		return

	var weight: float = 1.0 - exp(
		-maxf(interpolation_speed, 0.0) * delta
	)

	global_transform = global_transform.interpolate_with(
		_target_transform,
		weight
	)

	if _remote_sleeping:
		var position_close := global_position.distance_to(
			_target_transform.origin
		) < 0.005

		var rotation_close := global_basis.get_rotation_quaternion().angle_to(
			_target_transform.basis.get_rotation_quaternion()
		) < deg_to_rad(0.5)

		if position_close and rotation_close:
			global_transform = _target_transform
			_has_physics_snapshot = false


func _physics_process(delta: float) -> void:
	if _pending_holder_id != 0:
		var player := _get_player(_pending_holder_id)

		if is_instance_valid(player):
			_apply_pickup_local(_pending_holder_id)

	if not _pending_slot_path.is_empty():
		var slot := get_node_or_null(_pending_slot_path) as Node3D

		if slot != null:
			_apply_placement_local(_pending_slot_path)
		else:
			return

	match item_state:
		ItemState.HELD:
			if is_instance_valid(held_by):
				_update_held_position()
			return

		ItemState.PLACED:
			if is_instance_valid(placed_in):
				_update_placed_position()
			return

		ItemState.WORLD:
			pass

	if not multiplayer.is_server():
		return

	_update_sleep_state()

	if sleeping:
		return

	_physics_sync_timer += delta
	_heartbeat_timer += delta

	if _physics_sync_timer >= physics_sync_rate:
		_physics_sync_timer = 0.0
		_send_physics_if_needed()


func _send_physics_if_needed() -> void:
	var should_send := not _has_sent_physics

	if _has_sent_physics:
		var position_difference := global_position.distance_to(
			_last_sent_transform.origin
		)

		var rotation_difference := rad_to_deg(
			global_basis.get_rotation_quaternion().angle_to(
				_last_sent_transform.basis.get_rotation_quaternion()
			)
		)

		should_send = (
			position_difference >= position_threshold
			or rotation_difference >= rotation_threshold
			or _heartbeat_timer >= heartbeat_interval
		)

	if not should_send:
		return

	_physics_sequence += 1

	_sync_physics.rpc(
		_physics_sequence,
		global_transform,
		linear_velocity,
		angular_velocity
	)

	_last_sent_transform = global_transform
	_has_sent_physics = true
	_heartbeat_timer = 0.0


func _update_sleep_state() -> void:
	if sleeping == _was_sleeping:
		return

	_was_sleeping = sleeping
	_physics_sequence += 1

	_sync_sleep_state.rpc(
		_physics_sequence,
		global_transform,
		sleeping
	)

	if sleeping:
		_has_sent_physics = false
	else:
		# Send a fresh physics snapshot after waking.
		_has_sent_physics = false
		_physics_sync_timer = physics_sync_rate
		_heartbeat_timer = 0.0


@rpc("authority", "call_remote", "reliable")
func _sync_sleep_state(
	sequence: int,
	item_transform: Transform3D,
	is_sleeping: bool
) -> void:
	if multiplayer.is_server() or item_state != ItemState.WORLD:
		return

	if sequence <= _last_received_sequence:
		return

	_last_received_sequence = sequence
	_remote_sleeping = is_sleeping

	_target_transform = item_transform
	_has_physics_snapshot = true

	if is_sleeping:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


func _on_interacted(player: Node) -> void:
	if not player is CharacterBody3D:
		return

	if not player.is_multiplayer_authority():
		return

	if item_state != ItemState.WORLD:
		return

	if _pending_holder_id != 0 or not _pending_slot_path.is_empty():
		return

	if is_instance_valid(player.get("held_item")):
		return

	if multiplayer.is_server():
		_server_pickup(player.get_multiplayer_authority())
	else:
		_request_pickup.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup() -> void:
	if not multiplayer.is_server():
		return

	_server_pickup(multiplayer.get_remote_sender_id())


func _server_pickup(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if item_state != ItemState.WORLD:
		return

	var player := _get_player(peer_id)

	if not is_instance_valid(player):
		return

	if is_instance_valid(player.get("held_item")):
		return

	if player.global_position.distance_to(global_position) > 3.0:
		return

	_apply_pickup.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _apply_pickup(peer_id: int) -> void:
	_apply_pickup_local(peer_id)


func _apply_pickup_local(peer_id: int) -> void:
	var player := _get_player(peer_id)

	if not is_instance_valid(player):
		_pending_holder_id = peer_id
		_pending_slot_path = NodePath("")

		_reset_client_physics()

		freeze = true
		collision_layer = 0
		collision_mask = 0
		_interactable.set_interaction_enabled(false)
		return

	_pending_holder_id = 0
	_pending_slot_path = NodePath("")

	if item_state == ItemState.HELD and held_by == player:
		return

	if is_instance_valid(held_by):
		if held_by.get("held_item") == self:
			held_by.set("held_item", null)

	if is_instance_valid(placed_in):
		_clear_slot_reference()

	held_by = player
	placed_in = null

	player.set("held_item", self)
	item_state = ItemState.HELD

	_reset_client_physics()

	_interactable.set_interaction_enabled(false)
	_interactable.hide_prompt()

	if multiplayer.is_server():
		_wake_nearby_items()

	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	collision_layer = 0
	collision_mask = 0

	_update_held_position()


func _update_held_position() -> void:
	if not is_instance_valid(held_by):
		return

	var skin := held_by.get_node_or_null("PlayerSkin") as Node3D

	if skin == null:
		return

	global_transform = skin.global_transform * Transform3D(
		Basis.IDENTITY,
		hold_offset
	)


func drop_item() -> void:
	if item_state != ItemState.HELD:
		return

	if not is_instance_valid(held_by):
		return

	if not held_by.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_drop(held_by.get_multiplayer_authority())
	else:
		_request_drop.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_drop() -> void:
	if not multiplayer.is_server():
		return

	_server_drop(multiplayer.get_remote_sender_id())


func _server_drop(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if item_state != ItemState.HELD:
		return

	if not is_instance_valid(held_by):
		return

	if held_by.get_multiplayer_authority() != peer_id:
		return

	var drop_transform := global_transform
	var skin := held_by.get_node_or_null("PlayerSkin") as Node3D

	if skin != null:
		drop_transform.origin += skin.global_basis.z * 0.5

	_apply_drop.rpc(drop_transform)


@rpc("authority", "call_local", "reliable")
func _apply_drop(drop_transform: Transform3D) -> void:
	_apply_drop_local(drop_transform)


func _apply_drop_local(drop_transform: Transform3D) -> void:
	if is_instance_valid(held_by):
		if held_by.get("held_item") == self:
			held_by.set("held_item", null)

	if is_instance_valid(placed_in):
		_clear_slot_reference()

	held_by = null
	placed_in = null

	_pending_holder_id = 0
	_pending_slot_path = NodePath("")

	item_state = ItemState.WORLD
	global_transform = drop_transform

	_reset_client_physics()
	_target_transform = drop_transform

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask

	freeze = not multiplayer.is_server()

	if multiplayer.is_server():
		sleeping = false
		_was_sleeping = false
		_has_sent_physics = false
		_physics_sync_timer = 0.0
		_heartbeat_timer = 0.0

	_interactable.set_interaction_enabled(true)


func place_in_slot(slot: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if item_state != ItemState.HELD and item_state != ItemState.WORLD:
		return

	if not is_instance_valid(slot):
		return

	if is_instance_valid(slot.get("placed_item")):
		return

	if slot.get_node_or_null("ItemPosition") == null:
		return

	if slot.has_method("can_accept_item"):
		if not bool(slot.call("can_accept_item", self)):
			return

	_apply_placement.rpc(slot.get_path())


@rpc("authority", "call_local", "reliable")
func _apply_placement(slot_path: NodePath) -> void:
	_apply_placement_local(slot_path)


func _apply_placement_local(slot_path: NodePath) -> void:
	var slot := get_node_or_null(slot_path) as Node3D

	if slot == null:
		_pending_slot_path = slot_path
		_reset_client_physics()
		return

	var marker := slot.get_node_or_null("ItemPosition") as Marker3D

	if marker == null:
		push_warning("Placement slot missing ItemPosition: " + str(slot_path))
		return

	_pending_slot_path = NodePath("")
	_pending_holder_id = 0

	if is_instance_valid(held_by):
		if held_by.get("held_item") == self:
			held_by.set("held_item", null)

	held_by = null

	if is_instance_valid(placed_in) and placed_in != slot:
		_clear_slot_reference()

	item_state = ItemState.PLACED
	placed_in = slot

	_reset_client_physics()

	slot.set("placed_item", self)

	var slot_interactable := slot.get_node_or_null(
		"InteractableBase"
	) as Interactable

	if slot_interactable != null:
		slot_interactable.interaction_action = "Retrieve"

	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# Keep collision enabled for stacked items.
	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask

	_interactable.set_interaction_enabled(false)
	_interactable.hide_prompt()

	global_transform = _get_aligned_placement_transform(marker)


func _get_aligned_placement_transform(marker: Marker3D) -> Transform3D:
	var target := marker.global_transform
	var lowest_y := INF

	var offset := target.basis * global_transform.basis.inverse()

	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D

		if mesh.mesh == null:
			continue

		var mesh_transform := Transform3D(
			offset * mesh.global_basis,
			target.origin + offset * (mesh.global_position - global_position)
		)

		var bounds: AABB = mesh_transform * mesh.get_aabb()
		lowest_y = minf(lowest_y, bounds.position.y)

	if lowest_y != INF:
		target.origin.y += marker.global_position.y - lowest_y

	return target


func _update_placed_position() -> void:
	if not is_instance_valid(placed_in):
		return

	var marker := placed_in.get_node_or_null("ItemPosition") as Marker3D

	if marker != null:
		global_transform = _get_aligned_placement_transform(marker)


func retrieve_from_slot(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if item_state != ItemState.PLACED:
		return

	var player := _get_player(peer_id)

	if not is_instance_valid(player):
		return

	if is_instance_valid(player.get("held_item")):
		return

	_apply_retrieval.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _apply_retrieval(peer_id: int) -> void:
	_apply_pickup_local(peer_id)


func _clear_slot_reference() -> void:
	if not is_instance_valid(placed_in):
		return

	if placed_in.get("placed_item") == self:
		placed_in.set("placed_item", null)

	var slot_interactable := placed_in.get_node_or_null(
		"InteractableBase"
	) as Interactable

	if slot_interactable != null:
		slot_interactable.interaction_action = "Place"


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_physics(
	sequence: int,
	item_transform: Transform3D,
	item_velocity: Vector3,
	item_angular_velocity: Vector3
) -> void:
	if multiplayer.is_server() or item_state != ItemState.WORLD:
		return

	if _pending_holder_id != 0 or not _pending_slot_path.is_empty():
		return

	if sequence <= _last_received_sequence:
		return

	_last_received_sequence = sequence
	_remote_sleeping = false

	_target_transform = item_transform
	_has_physics_snapshot = true

	linear_velocity = item_velocity
	angular_velocity = item_angular_velocity


func send_current_state(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var holder_id := 0
	var slot_path := NodePath("")

	if item_state == ItemState.HELD and is_instance_valid(held_by):
		holder_id = held_by.get_multiplayer_authority()

	elif item_state == ItemState.PLACED and is_instance_valid(placed_in):
		slot_path = placed_in.get_path()

	_receive_current_state.rpc_id(
		peer_id,
		item_state,
		holder_id,
		slot_path,
		global_transform,
		linear_velocity,
		angular_velocity,
		sleeping,
		_physics_sequence
	)


@rpc("authority", "call_remote", "reliable")
func _receive_current_state(
	state: int,
	holder_id: int,
	slot_path: NodePath,
	item_transform: Transform3D,
	item_velocity: Vector3,
	item_angular_velocity: Vector3,
	is_sleeping: bool,
	sequence: int
) -> void:
	if multiplayer.is_server():
		return

	match state:
		ItemState.WORLD:
			_apply_drop_local(item_transform)

			_target_transform = item_transform
			_has_physics_snapshot = true
			_remote_sleeping = is_sleeping
			_last_received_sequence = sequence

			linear_velocity = item_velocity
			angular_velocity = item_angular_velocity

		ItemState.HELD:
			if holder_id != 0:
				_apply_pickup_local(holder_id)

		ItemState.PLACED:
			if not slot_path.is_empty():
				_apply_placement_local(slot_path)


func _reset_client_physics() -> void:
	_has_physics_snapshot = false
	_remote_sleeping = false


func _get_player(peer_id: int) -> CharacterBody3D:
	var game_scene := get_tree().current_scene

	if game_scene == null:
		return null

	var player := game_scene.get_node_or_null(str(peer_id)) as CharacterBody3D

	if player == null:
		return null

	if player.get_multiplayer_authority() != peer_id:
		return null

	return player


func release_disconnected_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if item_state != ItemState.HELD:
		return

	if not is_instance_valid(held_by):
		return

	if held_by.get_multiplayer_authority() != peer_id:
		return

	_server_drop(peer_id)


func _wake_nearby_items() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var results := get_world_3d().direct_space_state.intersect_shape(
		query,
		32
	)

	for result in results:
		var body := result["collider"] as RigidBody3D

		if body != null and body != self:
			body.sleeping = false
