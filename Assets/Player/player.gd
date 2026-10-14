
extends CharacterBody3D


# Camera states
enum CameraState {
	THIRD_PERSON,
	FIRST_PERSON
}


# Camera settings
@export_group("Camera")
@export_range(0.0, 1.0) var mouse_sensitivty := 0.25
@export_range(0.0, 1.0) var zoom_amount := 0.50
@export var camera_distance := 8.0
@export var zoom_speed := 50.0
@export var min_zoom := 0.0
@export var max_zoom := 6.0
@export var first_person_threshold := 0.5
@export var camera_clip_threshold := 1.0
@export var camera_show_threshold := 1.2
@export_group("Camera Fade")
@export var fade_out_speed := 10.0
@export var fade_in_speed := 25.0
@export var fade_start_angle := 55.0
@export var fade_end_angle := 75.0


# Movement settings
@export_group("Movement")
@export var move_speed := 8.0
@export var acceleration := 45.0
@export var deceleration := 85.0
@export var turn_acceleration := 100.0
@export var rotation_speed := 12.0
@export var jump_impulse := 12.0
@export var gravity := 30.0


# Interaction settings
@export_group("Interaction")
@export var interaction_range := 2.5
@export_range(10.0, 180.0) var interaction_cone_angle := 60.0
@export var interaction_cone_height := 1.0


# Animation settings
@export_group("Animation")
@export var animation_blend_time := 0.2
@export var walking_animation_speed := 1.0
@export var animation_speed_threshold := 0.15
@export var running_speed_threshold := 4.0


# Replicated animation properties
# Add both to MultiplayerSynchronizer.
@export var animation_state: String = "Anim/Idle"
@export var animation_playback_speed: float = 1.0


# Camera references
@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %Camera3D
@onready var _camera_pan: SpringArm3D = %SpringArm3D
@onready var _skin: Node3D = %PlayerSkin
@onready var _interaction_ray: RayCast3D = %InteractionRay
@onready var _animation_player: AnimationPlayer = $PlayerSkin/AnimationPlayer


# HUD references
@onready var _player_hud: CanvasLayer = $PlayerHUD

#Player HoldPoint
@onready var _hold_point: Marker3D = $HoldPoint


# Movement data
var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.BACK


# Camera state data
var _camera_state := CameraState.THIRD_PERSON
var _third_person_camera_dragging := false
var _third_person_mouse_position := Vector2.ZERO
var _skin_transparency := 0.0


# Interaction data
var _current_interactable: Interactable
var held_item: RigidBody3D = null


# Animation data
var _current_animation: StringName = &""


# Multiplayer ownership
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


# Player initialization
func _ready() -> void:
	var is_local_player := is_multiplayer_authority()

	_player_hud.visible = false

	set_process_input(is_local_player)
	set_process_unhandled_input(is_local_player)

	_interaction_ray.enabled = is_local_player
	_interaction_ray.target_position = Vector3(
		0.0, 0.0, -interaction_range
	)

	if is_local_player:
		_interaction_ray.add_exception(self)
		_camera_pan.add_excluded_object(get_rid())
		_camera.make_current()
		_enter_camera_state(_camera_state)
	else:
		_camera.current = false

	_setup_animations()
	_play_animation(&"Anim/Idle")

	add_to_group("players")


# Mouse input and camera zoom
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if _camera_state == CameraState.THIRD_PERSON:
		if event.is_action_pressed("right_click"):
			_third_person_mouse_position = get_viewport().get_mouse_position()
			_third_person_camera_dragging = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		if event.is_action_released("right_click") and _third_person_camera_dragging:
			_third_person_camera_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Input.warp_mouse(_third_person_mouse_position)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance -= zoom_amount
			camera_distance = clampf(
				camera_distance, min_zoom, max_zoom
			)
			_update_camera_state()

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _camera_state == CameraState.FIRST_PERSON:
				camera_distance = first_person_threshold + zoom_amount
			else:
				camera_distance += zoom_amount

			camera_distance = clampf(
				camera_distance, min_zoom, max_zoom
			)
			_update_camera_state()


# Camera movement and interaction input
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	var is_camera_motion := (
		event is InputEventMouseMotion
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)

	if is_camera_motion:
		_camera_input_direction = (
			event.screen_relative * mouse_sensitivty
		)

	if event.is_action_pressed("interact") and not event.is_echo():
		_handle_interaction()
		
	if event.is_action_pressed("drop_item") and not event.is_echo():
		if is_instance_valid(held_item):
			held_item.drop_item()


# Main player update
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	_update_camera_rotation(delta)
	_update_camera_zoom(delta)

	var move_direction := _get_move_direction()

	_update_movement(move_direction, delta)
	_update_character_rotation(move_direction, delta)
	_update_animation()

	_update_interaction_ray()
	_update_interactable()
	
	_hold_point.global_transform = _skin.global_transform * Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 1.0, 1.0)
	)


# Camera visibility and remote animation updates
func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_update_player_visibility(delta)
	else:
		_update_remote_animation()


# Camera visibility
func _update_player_visibility(delta: float) -> void:
	var target_transparency := 0.0

	var distance := _camera.global_position.distance_to(
		_camera_pivot.global_position
	)

	# Fade when the camera gets too close.
	if distance < camera_show_threshold:
		target_transparency = 1.0 - smoothstep(
			camera_clip_threshold,
			camera_show_threshold,
			distance
		)

	# Fade when looking upward.
	var look_angle := rad_to_deg(-_camera_pivot.rotation.x)

	var angle_transparency := smoothstep(
		fade_start_angle,
		fade_end_angle,
		look_angle
	)

	target_transparency = maxf(
		target_transparency,
		angle_transparency
	)

	# Completely transparent in first-person.
	if _camera_state == CameraState.FIRST_PERSON:
		target_transparency = 1.0

	# Smooth transition.
	var current_fade_speed := fade_out_speed

	if target_transparency < _skin_transparency:
		current_fade_speed = fade_in_speed

	_skin_transparency = lerpf(
		_skin_transparency,
		target_transparency,
		1.0 - exp(-current_fade_speed * delta)
	)

	_skin_transparency = clampf(_skin_transparency, 0.0, 1.0)

	# Keep PlayerSkin visible so transparency can work.
	_skin.visible = true

	# Fade only the character meshes.
	for node in _skin.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.transparency = _skin_transparency


# Camera state
func _update_camera_state() -> void:
	if camera_distance <= first_person_threshold:
		_change_camera_state(CameraState.FIRST_PERSON)
	else:
		_change_camera_state(CameraState.THIRD_PERSON)


func _change_camera_state(new_state: CameraState) -> void:
	if new_state == _camera_state:
		return

	_exit_camera_state(_camera_state)
	_camera_state = new_state
	_enter_camera_state(_camera_state)


func _enter_camera_state(state: CameraState) -> void:
	match state:
		CameraState.THIRD_PERSON:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		CameraState.FIRST_PERSON:
			camera_distance = 0.0
			_third_person_camera_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_skin.visible = false

	_update_crosshair()


func _exit_camera_state(state: CameraState) -> void:
	match state:
		CameraState.THIRD_PERSON:
			_third_person_camera_dragging = false

		CameraState.FIRST_PERSON:
			pass


# Camera rotation
func _update_camera_rotation(delta: float) -> void:
	_camera_pivot.rotation.x += (
		_camera_input_direction.y * delta
	)

	_camera_pivot.rotation.x = clampf(
		_camera_pivot.rotation.x,
		-PI / 2.0 + 0.01,
		PI / 2.0 - 0.01
	)

	_camera_pivot.rotation.y -= (
		_camera_input_direction.x * delta
	)

	_camera_input_direction = Vector2.ZERO


# Camera zoom
func _update_camera_zoom(delta: float) -> void:
	var zoom_weight := 1.0 - exp(-zoom_speed * delta)

	_camera_pan.spring_length = lerpf(
		_camera_pan.spring_length,
		camera_distance,
		zoom_weight
	)


# Crosshair
func _update_crosshair() -> void:
	_player_hud.visible = (
		is_multiplayer_authority()
		and _camera_state == CameraState.FIRST_PERSON
	)


# Movement direction
func _get_move_direction() -> Vector3:
	var raw_input := Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
		"ui_down"
	)

	var forward := _camera.global_basis.z
	var right := _camera.global_basis.x

	var move_direction := (
		forward * raw_input.y
		+ right * raw_input.x
	)

	move_direction.y = 0.0

	return move_direction.normalized()


# Player movement
func _update_movement(
	move_direction: Vector3,
	delta: float
) -> void:
	var target_velocity := move_direction * move_speed

	var horizontal_velocity := Vector3(
		velocity.x,
		0.0,
		velocity.z
	)

	var current_acceleration := acceleration

	if move_direction.length_squared() < 0.01:
		current_acceleration = deceleration

	elif horizontal_velocity.length_squared() > 0.01:
		if horizontal_velocity.normalized().dot(
			move_direction
		) < 0.0:
			current_acceleration = turn_acceleration

	horizontal_velocity = horizontal_velocity.move_toward(
		target_velocity,
		current_acceleration * delta
	)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0

		if Input.is_action_just_pressed("ui_accept"):
			velocity.y = jump_impulse

	move_and_slide()


# Character rotation
func _update_character_rotation(
	move_direction: Vector3,
	delta: float
) -> void:
	match _camera_state:
		CameraState.FIRST_PERSON:
			_skin.rotation.y = _camera_pivot.rotation.y

		CameraState.THIRD_PERSON:
			if move_direction.length_squared() < 0.01:
				return

			_last_movement_direction = move_direction

			var target_angle := Vector3.BACK.signed_angle_to(
				_last_movement_direction,
				Vector3.UP
			)

			var rotation_weight: float = clampf(
				rotation_speed * delta,
				0.0,
				1.0
			)

			_skin.rotation.y = lerp_angle(
				_skin.rotation.y,
				target_angle,
				rotation_weight
			)


# Configure looping animations
func _setup_animations() -> void:
	var animations: Array[StringName] = [
		&"Anim/Idle",
		&"Anim/Walking",
		&"Anim/Running"
	]

	for animation_name in animations:
		if _animation_player.has_animation(animation_name):
			var animation := _animation_player.get_animation(
				animation_name
			)

			animation.loop_mode = Animation.LOOP_LINEAR


# Play animation without restarting the same animation
func _play_animation(animation_name: StringName) -> void:
	if _current_animation == animation_name:
		return

	if not _animation_player.has_animation(animation_name):
		push_warning(
			"Animation not found: " + str(animation_name)
		)
		return

	_current_animation = animation_name

	_animation_player.play(
		animation_name,
		animation_blend_time
	)


# Local authority chooses animation and updates replicated state
func _update_animation() -> void:
	var horizontal_speed := Vector2(
		velocity.x,
		velocity.z
	).length()

	var next_animation: StringName = &"Anim/Idle"
	var next_speed := 1.0

	if horizontal_speed > animation_speed_threshold:
		if horizontal_speed < running_speed_threshold:
			next_animation = &"Anim/Walking"

			next_speed = clampf(
				horizontal_speed / maxf(running_speed_threshold, 0.01),
				0.5,
				1.5
			) * walking_animation_speed
		else:
			next_animation = &"Anim/Running"

			next_speed = clampf(
				horizontal_speed / maxf(move_speed, 0.01),
				0.5,
				1.5
			) * walking_animation_speed

	animation_state = str(next_animation)
	animation_playback_speed = next_speed

	_play_animation(next_animation)
	_animation_player.speed_scale = next_speed


# Remote players apply the synchronized animation state
func _update_remote_animation() -> void:
	var next_animation := StringName(animation_state)

	_play_animation(next_animation)

	_animation_player.speed_scale = animation_playback_speed


# Interaction ray
func _update_interaction_ray() -> void:
	match _camera_state:
		CameraState.FIRST_PERSON:
			_interaction_ray.global_basis = _camera.global_basis

			_interaction_ray.target_position = Vector3(
				0.0,
				0.0,
				-interaction_range
			)

		CameraState.THIRD_PERSON:
			_interaction_ray.global_rotation = Vector3(
				0.0,
				_skin.global_rotation.y + PI,
				0.0
			)

			_interaction_ray.target_position = Vector3(
				0.0,
				-0.8,
				-interaction_range
			)

	_interaction_ray.force_raycast_update()

#ConeRay
func _get_interactable_in_cone() -> Interactable:
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_range

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(
		Basis.IDENTITY,
		global_position + Vector3.UP * interaction_cone_height
	)

	# Layer 3 = Interactables
	query.collision_mask = 1 << 2
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var results := get_world_3d().direct_space_state.intersect_shape(
		query,
		32
	)

	# Use the camera's full 3D direction.
	var camera_forward := -_camera.global_basis.z
	var camera_position := _camera.global_position

	var minimum_alignment := cos(
		deg_to_rad(interaction_cone_angle * 0.5)
	)

	var best_interactable: Interactable = null
	var best_score := -INF

	for result in results:
		var collider: Object = result["collider"]

		if not collider is Interactable:
			continue

		var interactable := collider as Interactable

		if not interactable.interaction_enabled:
			continue

		# Direction from the camera to the object.
		var to_target := interactable.global_position - camera_position
		var distance := to_target.length()

		if distance < 0.001:
			continue

		# Keep objects within interaction distance of the player.
		if interactable.global_position.distance_to(global_position) > interaction_range:
			continue

		var direction := to_target.normalized()
		var alignment := camera_forward.dot(direction)

		if alignment < minimum_alignment:
			continue

		# Prefer the object closest to the camera's aim.
		var score := alignment * 3.0 - distance * 0.05

		if score > best_score:
			best_score = score
			best_interactable = interactable

	return best_interactable

# Detect interactable
func _get_interactable() -> Interactable:
	if _camera_state == CameraState.THIRD_PERSON:
		return _get_interactable_in_cone()

	# Keep existing first-person raycast.
	if not _interaction_ray.is_colliding():
		return null

	var collider := _interaction_ray.get_collider()

	if collider is Interactable:
		return collider

	return null


# Update targeted interactable
func _update_interactable() -> void:
	var interactable := _get_interactable()

	if interactable == _current_interactable:
		return

	if is_instance_valid(_current_interactable):
		_current_interactable.hide_prompt()

	_current_interactable = interactable

	if is_instance_valid(_current_interactable):
		_current_interactable.show_prompt()


# Handle interaction
func _handle_interaction() -> void:
	if not is_multiplayer_authority():
		return

	_update_interaction_ray()
	_update_interactable()

	if not is_instance_valid(_current_interactable):
		return

	_current_interactable.interact(self)


# Clear interaction when player is removed
func _exit_tree() -> void:
	if is_instance_valid(_current_interactable):
		_current_interactable.hide_prompt()
