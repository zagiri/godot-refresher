
extends RigidBody3D


# ==================================================
# ITEM STATES
# ==================================================

enum ItemState {
	WORLD,
	HELD,
	PLACED
}

var item_state := ItemState.WORLD


# ==================================================
# SETTINGS
# ==================================================

@export_group("Pickup")
@export var hold_offset := Vector3(0.0, 1.0, 1.0)

@export_group("Multiplayer")
@export var physics_sync_rate := 0.1


# ==================================================
# REFERENCES
# ==================================================

@onready var _interactable: Interactable = $InteractableBase


# ==================================================
# ITEM DATA
# ==================================================

var held_by: CharacterBody3D = null
var placed_in: Node3D = null

var _original_collision_layer: int
var _original_collision_mask: int
var _physics_sync_timer := 0.0

# Late-join synchronization
var _pending_holder_id := 0
var _pending_slot_path := NodePath("")


# ==================================================
# INITIALIZATION
# ==================================================

func _ready() -> void:
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask

	_interactable.interacted.connect(_on_interacted)
	_interactable.interaction_action = "Pick up"

	add_to_group("sync_pickup_items")

	if not multiplayer.is_server():
		freeze = true


# ==================================================
# PHYSICS UPDATE
# ==================================================

func _physics_process(delta: float) -> void:
	# Resolve a late-join holder.
	if _pending_holder_id != 0:
		var player := _get_player(_pending_holder_id)

		if is_instance_valid(player):
			_apply_pickup_local(_pending_holder_id)

	# Resolve a late-join placement slot.
	if not _pending_slot_path.is_empty():
		var slot := get_node_or_null(
			_pending_slot_path
		) as Node3D

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

	_physics_sync_timer += delta

	if _physics_sync_timer >= physics_sync_rate:
		_physics_sync_timer = 0.0

		_sync_physics.rpc(
			global_transform,
			linear_velocity,
			angular_velocity
		)


# ==================================================
# INTERACTION
# ==================================================

func _on_interacted(player: Node) -> void:
	if not player is CharacterBody3D:
		return

	if not player.is_multiplayer_authority():
		return

	if item_state != ItemState.WORLD:
		return

	if _pending_holder_id != 0:
		return

	if not _pending_slot_path.is_empty():
		return

	if is_instance_valid(player.get("held_item")):
		return

	if multiplayer.is_server():
		_server_pickup(
			player.get_multiplayer_authority()
		)
	else:
		_request_pickup.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup() -> void:
	if not multiplayer.is_server():
		return

	_server_pickup(
		multiplayer.get_remote_sender_id()
	)


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

	if player.global_position.distance_to(
		global_position
	) > 3.0:
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

		# Do not allow interaction while waiting.
		freeze = true
		collision_layer = 0
		collision_mask = 0
		_interactable.set_interaction_enabled(false)

		return

	_pending_holder_id = 0
	_pending_slot_path = NodePath("")

	if item_state == ItemState.HELD and held_by == player:
		return

	# Clear the previous player.
	if is_instance_valid(held_by):
		if held_by.get("held_item") == self:
			held_by.set("held_item", null)

	# Clear previous placement slot.
	if is_instance_valid(placed_in):
		_clear_slot_reference()

	held_by = player
	placed_in = null

	player.set("held_item", self)

	item_state = ItemState.HELD

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

	print(player.name, " picked up ", name)


# ==================================================
# HELD ITEM POSITION
# ==================================================

func _update_held_position() -> void:
	if not is_instance_valid(held_by):
		return

	var skin := held_by.get_node_or_null(
		"PlayerSkin"
	) as Node3D

	if skin == null:
		return

	global_transform = skin.global_transform * Transform3D(
		Basis.IDENTITY,
		hold_offset
	)


# ==================================================
# DROPPING
# ==================================================

func drop_item() -> void:
	if item_state != ItemState.HELD:
		return

	if not is_instance_valid(held_by):
		return

	if not held_by.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_server_drop(
			held_by.get_multiplayer_authority()
		)
	else:
		_request_drop.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_drop() -> void:
	if not multiplayer.is_server():
		return

	_server_drop(
		multiplayer.get_remote_sender_id()
	)


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

	var skin := held_by.get_node_or_null(
		"PlayerSkin"
	) as Node3D

	if skin != null:
		drop_transform.origin += (
			skin.global_basis.z * 0.5
		)

	_apply_drop.rpc(drop_transform)


@rpc("authority", "call_local", "reliable")
func _apply_drop(drop_transform: Transform3D) -> void:
	_apply_drop_local(drop_transform)


func _apply_drop_local(
	drop_transform: Transform3D
) -> void:
	# Clear previous holder.
	if is_instance_valid(held_by):
		if held_by.get("held_item") == self:
			held_by.set("held_item", null)

	# Clear previous slot.
	if is_instance_valid(placed_in):
		_clear_slot_reference()

	held_by = null
	placed_in = null

	_pending_holder_id = 0
	_pending_slot_path = NodePath("")

	item_state = ItemState.WORLD

	global_transform = drop_transform

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask

	freeze = not multiplayer.is_server()

	if multiplayer.is_server():
		sleeping = false

	_interactable.set_interaction_enabled(true)

	print("Dropped item: ", name)


# ==================================================
# PLACEMENT
# ==================================================

func place_in_slot(slot: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if item_state != ItemState.HELD:
		return

	if not is_instance_valid(slot):
		return

	if not is_instance_valid(held_by):
		return

	_apply_placement.rpc(slot.get_path())


@rpc("authority", "call_local", "reliable")
func _apply_placement(slot_path: NodePath) -> void:
	_apply_placement_local(slot_path)


func _apply_placement_local(
	slot_path: NodePath
) -> void:
	var slot := get_node_or_null(slot_path) as Node3D

	if slot == null:
		_pending_slot_path = slot_path
		return

	var marker := slot.get_node_or_null(
		"ItemPosition"
	) as Marker3D

	if marker == null:
		push_warning(
			"PlacementSlot missing ItemPosition: " +
			str(slot_path)
		)
		return

	_pending_slot_path = NodePath("")
	_pending_holder_id = 0

	# Release item from player.
	if is_instance_valid(held_by):
		if held_by.get("held_item") == self:
			held_by.set("held_item", null)

	held_by = null

	# Clear an old slot if needed.
	if is_instance_valid(placed_in):
		if placed_in != slot:
			_clear_slot_reference()

	item_state = ItemState.PLACED
	placed_in = slot

	# Update slot occupancy.
	slot.set("placed_item", self)

	var slot_interactable := slot.get_node_or_null(
		"InteractableBase"
	) as Interactable

	if slot_interactable != null:
		slot_interactable.interaction_action = "Retrieve"

	freeze = true

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	collision_layer = 0
	collision_mask = 0

	_interactable.set_interaction_enabled(false)
	_interactable.hide_prompt()

	global_transform = marker.global_transform

	print(name, " placed into ", slot.name)


func _update_placed_position() -> void:
	if not is_instance_valid(placed_in):
		return

	var marker := placed_in.get_node_or_null(
		"ItemPosition"
	) as Marker3D

	if marker != null:
		global_transform = marker.global_transform


# ==================================================
# RETRIEVAL
# ==================================================

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


# ==================================================
# SLOT CLEANUP
# ==================================================

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


# ==================================================
# PHYSICS SYNCHRONIZATION
# ==================================================

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_physics(
	item_transform: Transform3D,
	item_velocity: Vector3,
	item_angular_velocity: Vector3
) -> void:
	if multiplayer.is_server():
		return

	if item_state != ItemState.WORLD:
		return

	if _pending_holder_id != 0:
		return

	if not _pending_slot_path.is_empty():
		return

	global_transform = item_transform

	linear_velocity = item_velocity
	angular_velocity = item_angular_velocity


# ==================================================
# LATE-JOIN SYNCHRONIZATION
# ==================================================

func send_current_state(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var holder_id := 0
	var slot_path := NodePath("")

	if item_state == ItemState.HELD:
		if is_instance_valid(held_by):
			holder_id = held_by.get_multiplayer_authority()

	elif item_state == ItemState.PLACED:
		if is_instance_valid(placed_in):
			slot_path = placed_in.get_path()

	_receive_current_state.rpc_id(
		peer_id,
		item_state,
		holder_id,
		slot_path,
		global_transform,
		linear_velocity,
		angular_velocity
	)


@rpc("authority", "call_remote", "reliable")
func _receive_current_state(
	state: int,
	holder_id: int,
	slot_path: NodePath,
	item_transform: Transform3D,
	item_velocity: Vector3,
	item_angular_velocity: Vector3
) -> void:
	if multiplayer.is_server():
		return

	match state:
		ItemState.WORLD:
			_apply_drop_local(item_transform)

			linear_velocity = item_velocity
			angular_velocity = item_angular_velocity

		ItemState.HELD:
			if holder_id != 0:
				_apply_pickup_local(holder_id)

		ItemState.PLACED:
			if not slot_path.is_empty():
				_apply_placement_local(slot_path)


# ==================================================
# PLAYER LOOKUP
# ==================================================

func _get_player(peer_id: int) -> CharacterBody3D:
	var game_scene := get_tree().current_scene

	if game_scene == null:
		return null

	var player := game_scene.get_node_or_null(
		str(peer_id)
	) as CharacterBody3D

	if player == null:
		return null

	if player.get_multiplayer_authority() != peer_id:
		return null

	return player


# ==================================================
# PLAYER DISCONNECT CLEANUP
# ==================================================

func release_disconnected_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if item_state != ItemState.HELD:
		return

	if not is_instance_valid(held_by):
		return

	if held_by.get_multiplayer_authority() != peer_id:
		return

	print(
		"Releasing item from disconnected player: ",
		peer_id
	)

	_server_drop(peer_id)


# ==================================================
# STACKED ITEM PHYSICS
# ==================================================

func _wake_nearby_items() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0

	var query := PhysicsShapeQueryParameters3D.new()

	query.shape = sphere

	query.transform = Transform3D(
		Basis.IDENTITY,
		global_position
	)

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
