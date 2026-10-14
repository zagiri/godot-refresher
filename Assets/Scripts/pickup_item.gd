
extends RigidBody3D


@export_group("Pickup")
@export var hold_offset := Vector3(0.0, 1.0, 1.0)

@export_group("Multiplayer")
@export var physics_sync_rate := 0.1


@onready var _interactable: Interactable = $InteractableBase


var held_by: CharacterBody3D = null

var _original_collision_layer: int
var _original_collision_mask: int
var _physics_sync_timer := 0.0

# Late-join state
var _pending_holder_id := 0


func _ready() -> void:
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask

	_interactable.interacted.connect(_on_interacted)
	_interactable.interaction_action = "Pick up"

	add_to_group("sync_pickup_items")

	# Only the host simulates item physics.
	if not multiplayer.is_server():
		freeze = true


func _physics_process(delta: float) -> void:
	# Apply a late-join pickup once the holder exists.
	if _pending_holder_id != 0:
		var player := _get_player(_pending_holder_id)

		if is_instance_valid(player):
			_apply_pickup_local(_pending_holder_id)
			_pending_holder_id = 0

	# Keep carried items attached visually.
	if is_instance_valid(held_by):
		_update_held_position()
		return

	# Clients do not simulate dropped item physics.
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

	if is_instance_valid(held_by):
		return

	if _pending_holder_id != 0:
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

	var peer_id := multiplayer.get_remote_sender_id()
	_server_pickup(peer_id)


func _server_pickup(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if is_instance_valid(held_by):
		return

	var player := _get_player(peer_id)

	if not is_instance_valid(player):
		return

	if is_instance_valid(player.get("held_item")):
		return

	# Server-side pickup distance validation.
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
		return

	_pending_holder_id = 0

	# Avoid replaying an already-applied pickup.
	if held_by == player:
		return

	# Clear an outdated holder if necessary.
	if is_instance_valid(held_by):
		if held_by.get("held_item") == self:
			held_by.set("held_item", null)

	held_by = player
	player.set("held_item", self)

	_interactable.set_interaction_enabled(false)
	_interactable.hide_prompt()

	if multiplayer.is_server():
		_wake_nearby_items()

	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# Prevent the carried item from colliding with players.
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

	var skin := held_by.get_node_or_null("PlayerSkin") as Node3D

	if skin == null:
		return

	# Keep the item under Main to preserve multiplayer paths.
	global_transform = skin.global_transform * Transform3D(
		Basis.IDENTITY,
		hold_offset
	)


# ==================================================
# DROPPING
# ==================================================

func drop_item() -> void:
	if not is_instance_valid(held_by):
		return

	# Only the player holding the item can request dropping.
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

	var peer_id := multiplayer.get_remote_sender_id()
	_server_drop(peer_id)


func _server_drop(peer_id: int) -> void:
	if not multiplayer.is_server():
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

# Automatically release items when their holder disconnects.
func release_disconnected_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if not is_instance_valid(held_by):
		return

	if held_by.get_multiplayer_authority() != peer_id:
		return

	print("Releasing item from disconnected player: ", peer_id)

	# Reuse our existing drop logic.
	_server_drop(peer_id)

@rpc("authority", "call_local", "reliable")
func _apply_drop(drop_transform: Transform3D) -> void:
	_apply_drop_local(drop_transform)


func _apply_drop_local(drop_transform: Transform3D) -> void:
	if is_instance_valid(held_by):
		var player := held_by

		if player.get("held_item") == self:
			player.set("held_item", null)

	held_by = null
	_pending_holder_id = 0

	global_transform = drop_transform

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	collision_layer = _original_collision_layer
	collision_mask = _original_collision_mask

	# Only the host resumes physics simulation.
	freeze = not multiplayer.is_server()

	if multiplayer.is_server():
		sleeping = false

	_interactable.set_interaction_enabled(true)

	print("Dropped item: ", name)


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

	if is_instance_valid(held_by) or _pending_holder_id != 0:
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

	if is_instance_valid(held_by):
		holder_id = held_by.get_multiplayer_authority()

	_receive_current_state.rpc_id(
		peer_id,
		holder_id,
		global_transform,
		linear_velocity,
		angular_velocity
	)


@rpc("authority", "call_remote", "reliable")
func _receive_current_state(
	holder_id: int,
	item_transform: Transform3D,
	item_velocity: Vector3,
	item_angular_velocity: Vector3
) -> void:
	if multiplayer.is_server():
		return

	if holder_id != 0:
		# The holder might not have spawned on this client yet.
		_apply_pickup_local(holder_id)
	else:
		_apply_drop_local(item_transform)

		# Restore the host's current physics snapshot.
		linear_velocity = item_velocity
		angular_velocity = item_angular_velocity


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
