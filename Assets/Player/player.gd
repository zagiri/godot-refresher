extends CharacterBody3D


# Camera states
enum CameraState {
	THIRD_PERSON,
	FIRST_PERSON
}


# Camera variables
@export_group("Camera")
@export_range(0.0, 1.0) var mouse_sensitivty := 0.25
@export_range(0.0, 1.0) var zoom_amount := 0.50
@export var camera_distance := 8.0
@export var zoom_speed := 50.0
@export var min_zoom := 0.0
@export var max_zoom := 20.0
@export var first_person_threshold := 0.5


# Movement variables
@export_group("Movement")
@export var move_speed := 8.0
@export var acceleration := 20.0
@export var rotation_speed := 12.0
@export var jump_impulse := 12.0


# Interaction variables
@export_group("Interaction")
@export var interaction_range := 2.5


# Unique nodes
@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %Camera3D
@onready var _camera_pan: SpringArm3D = %SpringArm3D
@onready var _skin: Node3D = %PlayerSkin
@onready var _interaction_ray: RayCast3D = %InteractionRay


# Direction and movement
var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.BACK
var _gravity := -30.0


# Camera state
var _camera_state := CameraState.THIRD_PERSON
var _third_person_camera_dragging := false
var _third_person_mouse_position := Vector2.ZERO


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	var is_local_player := is_multiplayer_authority()

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


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	var is_camera_motion := event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

	if is_camera_motion:
		_camera_input_direction = event.screen_relative * mouse_sensitivty

	if event.is_action_pressed("interact"):
		test_interaction()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	_update_camera_rotation(delta)
	_update_camera_zoom(delta)

	var move_direction := _get_move_direction()

	_update_movement(move_direction, delta)
	_update_character_rotation(move_direction, delta)
	_update_interaction_ray()


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
			_skin.visible = true

		CameraState.FIRST_PERSON:
			camera_distance = 0.0
			_third_person_camera_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_skin.visible = false


func _exit_camera_state(state: CameraState) -> void:
	match state:
		CameraState.THIRD_PERSON:
			_third_person_camera_dragging = false

		CameraState.FIRST_PERSON:
			pass


func _update_camera_rotation(delta: float) -> void:
	_camera_pivot.rotation.x += _camera_input_direction.y * delta
	_camera_pivot.rotation.x = clamp(_camera_pivot.rotation.x, -PI / 6.0, PI / 3.0)
	_camera_pivot.rotation.y -= _camera_input_direction.x * delta

	_camera_input_direction = Vector2.ZERO


func _update_camera_zoom(delta: float) -> void:
	var zoom_weight := 1.0 - exp(-zoom_speed * delta)
	_camera_pan.spring_length = lerp(_camera_pan.spring_length, camera_distance, zoom_weight)


func _get_move_direction() -> Vector3:
	var raw_input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	var forward := _camera.global_basis.z
	var right := _camera.global_basis.x

	var move_direction := forward * raw_input.y + right * raw_input.x
	move_direction.y = 0.0

	return move_direction.normalized()


func _update_movement(move_direction: Vector3, delta: float) -> void:
	var y_velocity := velocity.y

	velocity.y = 0.0
	velocity = velocity.move_toward(move_direction * move_speed, acceleration * delta)
	velocity.y = y_velocity + _gravity * delta

	var is_starting_jump := Input.is_action_just_pressed("ui_accept") and is_on_floor()

	if is_starting_jump:
		velocity.y += jump_impulse

	move_and_slide()


func _update_character_rotation(move_direction: Vector3, delta: float) -> void:
	match _camera_state:
		CameraState.FIRST_PERSON:
			_skin.rotation.y = _camera_pivot.rotation.y

		CameraState.THIRD_PERSON:
			if move_direction.length() <= 0.2:
				return

			_last_movement_direction = move_direction

			var target_angle := Vector3.BACK.signed_angle_to(_last_movement_direction, Vector3.UP)
			_skin.rotation.y = lerp_angle(_skin.rotation.y, target_angle, rotation_speed * delta)


func _update_interaction_ray() -> void:
	match _camera_state:
		CameraState.FIRST_PERSON:
			# First person follows the camera
			_interaction_ray.global_basis = _camera.global_basis

		CameraState.THIRD_PERSON:
			# Third person follows the character
			_interaction_ray.global_rotation = Vector3(0.0, _skin.global_rotation.y + PI, 0.0)

	_interaction_ray.target_position = Vector3(0.0, 0.0, -interaction_range)
	_interaction_ray.force_raycast_update()


func test_interaction() -> void:
	if _interaction_ray.is_colliding():
		var collider := _interaction_ray.get_collider()
		print("Interacting with: ", collider.name)
	else:
		print("Nothing in range")
