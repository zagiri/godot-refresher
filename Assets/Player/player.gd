
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
@export var max_zoom := 20.0
@export var first_person_threshold := 0.5


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


# Animation settings
@export_group("Animation")
@export var animation_blend_time := 0.2
@export var walking_animation_speed := 1.0
@export var animation_speed_threshold := 0.15


# Node references
@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %Camera3D
@onready var _camera_pan: SpringArm3D = %SpringArm3D
@onready var _skin: Node3D = %PlayerSkin
@onready var _interaction_ray: RayCast3D = %InteractionRay
@onready var _animation_player: AnimationPlayer = $PlayerSkin/AnimationPlayer


# Movement data
var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.BACK


# Camera state data
var _camera_state := CameraState.THIRD_PERSON
var _third_person_camera_dragging := false
var _third_person_mouse_position := Vector2.ZERO


# Interaction data
var _current_interactable: Interactable
@onready var _interaction_ui: Control = $PlayerUI/InteractionUI


# Animation data
var _current_animation: StringName = &""


# Set multiplayer ownership using the player's peer ID
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


# Set up local camera, input and interaction
func _ready() -> void:
	var is_local_player := is_multiplayer_authority()
	$PlayerUI.visible = is_local_player

	set_process_input(is_local_player)
	set_process_unhandled_input(is_local_player)

	_interaction_ray.enabled = is_local_player
	_interaction_ray.target_position = Vector3(0.0, 0.0, -interaction_range)

	if is_local_player:
		_interaction_ray.add_exception(self)
		_camera.make_current()
		_enter_camera_state(_camera_state)
	else:
		_camera.current = false

	# Configure animation looping
	_setup_animations()

	# Start with Idle
	_play_animation(&"Anim/Idle")


# Handle mouse buttons and camera zoom
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Third-person right-click camera control
	if _camera_state == CameraState.THIRD_PERSON:
		if event.is_action_pressed("right_click"):
			_third_person_mouse_position = get_viewport().get_mouse_position()
			_third_person_camera_dragging = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		if event.is_action_released("right_click") and _third_person_camera_dragging:
			_third_person_camera_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Input.warp_mouse(_third_person_mouse_position)

	# Camera zoom
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance -= zoom_amount
			camera_distance = clamp(camera_distance, min_zoom, max_zoom)
			_update_camera_state()

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _camera_state == CameraState.FIRST_PERSON:
				camera_distance = first_person_threshold + zoom_amount
			else:
				camera_distance += zoom_amount

			camera_distance = clamp(camera_distance, min_zoom, max_zoom)
			_update_camera_state()


# Handle mouse movement and interaction input
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	var is_camera_motion := (
		event is InputEventMouseMotion
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)

	if is_camera_motion:
		_camera_input_direction = event.screen_relative * mouse_sensitivty

	if event.is_action_pressed("interact") and not event.is_echo():
		_handle_interaction()


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


# Decide which camera state should be active
func _update_camera_state() -> void:
	if camera_distance <= first_person_threshold:
		_change_camera_state(CameraState.FIRST_PERSON)
	else:
		_change_camera_state(CameraState.THIRD_PERSON)


# Switch from one camera state to another
func _change_camera_state(new_state: CameraState) -> void:
	if new_state == _camera_state:
		return

	_exit_camera_state(_camera_state)
	_camera_state = new_state
	_enter_camera_state(_camera_state)


# Apply settings when entering a camera state
func _enter_camera_state(state: CameraState) -> void:
	match state:
		CameraState.THIRD_PERSON:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_skin.visible = true

		CameraState.FIRST_PERSON:
			camera_distance = 0.0
			_third_person_camera_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_skin.visible = false


# Clean up settings when leaving a camera state
func _exit_camera_state(state: CameraState) -> void:
	match state:
		CameraState.THIRD_PERSON:
			_third_person_camera_dragging = false

		CameraState.FIRST_PERSON:
			pass


# Rotate the camera from mouse movement
func _update_camera_rotation(delta: float) -> void:
	_camera_pivot.rotation.x += _camera_input_direction.y * delta
	_camera_pivot.rotation.x = clamp(
		_camera_pivot.rotation.x,
		-PI / 6.0,
		PI / 3.0
	)

	_camera_pivot.rotation.y -= _camera_input_direction.x * delta
	_camera_input_direction = Vector2.ZERO


# Smoothly move camera toward requested zoom distance
func _update_camera_zoom(delta: float) -> void:
	var zoom_weight := 1.0 - exp(-zoom_speed * delta)

	_camera_pan.spring_length = lerp(
		_camera_pan.spring_length,
		camera_distance,
		zoom_weight
	)


# Get movement direction relative to the camera
func _get_move_direction() -> Vector3:
	var raw_input := Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
		"ui_down"
	)

	var forward := _camera.global_basis.z
	var right := _camera.global_basis.x

	var move_direction := forward * raw_input.y + right * raw_input.x
	move_direction.y = 0.0

	return move_direction.normalized()


# Apply responsive movement, gravity and jumping
func _update_movement(move_direction: Vector3, delta: float) -> void:
	var target_velocity := move_direction * move_speed

	var horizontal_velocity := Vector3(
		velocity.x,
		0.0,
		velocity.z
	)

	# Decide how quickly velocity should change
	var current_acceleration := acceleration

	if move_direction.length_squared() < 0.01:
		# Stop faster when no movement key is pressed
		current_acceleration = deceleration

	elif horizontal_velocity.length_squared() > 0.01:
		# Change direction faster when turning against momentum
		if horizontal_velocity.normalized().dot(move_direction) < 0.0:
			current_acceleration = turn_acceleration

	# Smoothly approach target movement speed
	horizontal_velocity = horizontal_velocity.move_toward(
		target_velocity,
		current_acceleration * delta
	)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# Keep character grounded
		if velocity.y < 0.0:
			velocity.y = 0.0

		# Jump
		if Input.is_action_just_pressed("ui_accept"):
			velocity.y = jump_impulse

	move_and_slide()


# Rotate the character depending on camera state
func _update_character_rotation(move_direction: Vector3, delta: float) -> void:
	match _camera_state:
		CameraState.FIRST_PERSON:
			# Face the same horizontal direction as the camera
			_skin.rotation.y = _camera_pivot.rotation.y

		CameraState.THIRD_PERSON:
			# Face actual horizontal movement direction
			var horizontal_velocity := Vector3(
				velocity.x,
				0.0,
				velocity.z
			)

			if horizontal_velocity.length() <= 0.15:
				return

			_last_movement_direction = horizontal_velocity.normalized()

			var target_angle := Vector3.BACK.signed_angle_to(
				_last_movement_direction,
				Vector3.UP
			)

			var rotation_weight: float = clampf(rotation_speed * delta, 0.0, 1.0)

			_skin.rotation.y = lerp_angle(
				_skin.rotation.y,
				target_angle,
				rotation_weight
			)


# Set animation looping
func _setup_animations() -> void:
	var animations: Array[StringName] = [
		&"Anim/Idle",
		&"Anim/Walking",
		&"Anim/Running"
	]

	for animation_name in animations:
		if _animation_player.has_animation(animation_name):
			var animation := _animation_player.get_animation(animation_name)
			animation.loop_mode = Animation.LOOP_LINEAR


# Play animation only when changing state
func _play_animation(animation_name: StringName) -> void:
	if _current_animation == animation_name:
		return

	if not _animation_player.has_animation(animation_name):
		push_warning("Animation not found: " + str(animation_name))
		return

	_current_animation = animation_name

	_animation_player.play(
		animation_name,
		animation_blend_time
	)


# Update animation based on actual player velocity
func _update_animation() -> void:
	var horizontal_speed := Vector2(
		velocity.x,
		velocity.z
	).length()

	if horizontal_speed <= animation_speed_threshold:
		_play_animation(&"Anim/Idle")
		_animation_player.speed_scale = 1.0
		return

	_play_animation(&"Anim/Running")

	# Adjust walking playback relative to movement speed
	var speed_ratio: float = horizontal_speed / maxf(move_speed, 0.01)

	_animation_player.speed_scale = clamp(
		speed_ratio * walking_animation_speed,
		0.5,
		1.5
	)


# Aim the interaction ray based on camera state
func _update_interaction_ray() -> void:
	match _camera_state:
		CameraState.FIRST_PERSON:
			_interaction_ray.global_basis = _camera.global_basis

		CameraState.THIRD_PERSON:
			_interaction_ray.global_rotation = Vector3(
				0.0,
				_skin.global_rotation.y + PI,
				0.0
			)

	_interaction_ray.target_position = Vector3(
		0.0,
		0.0,
		-interaction_range
	)

	_interaction_ray.force_raycast_update()


# Find an interactable object within range
func _get_interactable() -> Interactable:
	if not _interaction_ray.is_colliding():
		return null

	var collider := _interaction_ray.get_collider()

	if collider is Interactable:
		return collider

	return null


# Track the interactable currently being targeted
func _update_interactable() -> void:
	var interactable := _get_interactable()

	if interactable == _current_interactable:
		return

	_current_interactable = interactable

	if is_instance_valid(_current_interactable):
		_interaction_ui.show_prompt(_current_interactable.get_interaction_text())
	else:
		_interaction_ui.hide_prompt()


# Interact with the currently targeted object
func _handle_interaction() -> void:
	if not is_multiplayer_authority():
		return

	_update_interaction_ray()
	_update_interactable()

	if not is_instance_valid(_current_interactable):
		print("Nothing in range")
		return

	_current_interactable.interact(self)
