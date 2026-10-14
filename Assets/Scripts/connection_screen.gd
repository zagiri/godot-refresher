
extends CanvasLayer


signal connection_timed_out


@onready var _back_button: Button = $Background/CenterContainer/VBoxContainer/BackButton
@onready var _status_label: Label = $Background/CenterContainer/VBoxContainer/StatusLabel
@onready var _loading_spinner: TextureRect = $Background/CenterContainer/VBoxContainer/LoadingSpinner


var _connection_timer: Timer
var _return_timer: Timer
var connection_failed := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_back_button.pressed.connect(_on_back_pressed)

	_start_loading_animation()

	# Maximum time to wait for the host.
	_connection_timer = Timer.new()
	_connection_timer.one_shot = true
	_connection_timer.wait_time = 60.0
	add_child(_connection_timer)

	_connection_timer.timeout.connect(_on_connection_timeout)
	_connection_timer.start()

	# Delay before returning to the menu.
	_return_timer = Timer.new()
	_return_timer.one_shot = true
	_return_timer.wait_time = 3.0
	add_child(_return_timer)

	_return_timer.timeout.connect(_on_return_timeout)


func _start_loading_animation() -> void:
	await get_tree().process_frame

	if not is_inside_tree():
		return

	_loading_spinner.pivot_offset = _loading_spinner.size / 2.0

	var tween := create_tween()
	tween.set_loops()

	tween.tween_property(
		_loading_spinner,
		"rotation_degrees",
		360.0,
		1.0
	).from(0.0)


func _on_connection_timeout() -> void:
	if connection_failed:
		return

	connection_timed_out.emit()


func show_connection_failed() -> void:
	if connection_failed:
		return

	connection_failed = true

	_connection_timer.stop()

	_status_label.text = "Failed to connect to LAN host."

	_loading_spinner.visible = false

	_back_button.text = "Back to Main Menu"

	print("LAN connection failed. Returning to menu shortly...")

	_return_timer.start()


func _on_return_timeout() -> void:
	Networking.leave_game()


func _on_back_pressed() -> void:
	_back_button.disabled = true
	Networking.leave_game()
