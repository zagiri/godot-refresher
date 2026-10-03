extends CharacterBody3D

@export_group("Camera")
@export_range(0.0, 1.0) var mouse_sensitivty := 0.25
@export_range(0.0, 1.0) var zoom_amount := 0.50
@export var camera_distance := 8.0
@export var zoom_speed := 50.0
@export var min_zoom := 0.0
@export var max_zoom := 20.0

@export_group("Movement")
@export var move_speed := 8.0
@export var acceleration := 20.0
@export var rotation_speed := 12.0
@export var jump_impulse := 12.0


@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %Camera3D
@onready var _camera_pan: SpringArm3D = %SpringArm3D
@onready var _skin: MeshInstance3D = %PlayerSkin

var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.BACK
var _gravity := -30.0


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("right_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_released("right_click"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance -= zoom_amount
			camera_distance = clamp(camera_distance, min_zoom, max_zoom)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance += zoom_amount
			camera_distance = clamp(camera_distance, min_zoom, max_zoom)

func _unhandled_input(event: InputEvent) -> void:
	var is_camera_motion := (
		event is InputEventMouseMotion and
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)

	if is_camera_motion:
		_camera_input_direction = event.screen_relative * mouse_sensitivty


func _physics_process(delta: float) -> void:
	
	_camera_pivot.rotation.x -= _camera_input_direction.y * delta
	_camera_pivot.rotation.x = clamp(
		_camera_pivot.rotation.x,
		-PI / 6.0,
		PI / 3.0
	)

	_camera_pivot.rotation.y -= _camera_input_direction.x * delta

	_camera_input_direction = Vector2.ZERO


	# Smooth camera zoom
	_camera_pan.spring_length = lerp(
		_camera_pan.spring_length,
		camera_distance,
		zoom_speed * delta
	)


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
	move_direction = move_direction.normalized()

	var y_velocity := velocity.y
	velocity.y = 0.0
	velocity = velocity.move_toward(move_direction * move_speed, acceleration * delta)
	velocity.y = y_velocity + _gravity * delta
	
	var is_starting_jump := Input.is_action_just_pressed("ui_accept") and is_on_floor()
	if is_starting_jump:
		velocity.y += jump_impulse
	
	move_and_slide()


	if move_direction.length() > 0.2:
		_last_movement_direction = move_direction

	var target_angle := Vector3.BACK.signed_angle_to(
		_last_movement_direction,
		Vector3.UP
	)

	_skin.global_rotation.y = lerp_angle(
		_skin.rotation.y,
		target_angle,
		rotation_speed * delta
	)
