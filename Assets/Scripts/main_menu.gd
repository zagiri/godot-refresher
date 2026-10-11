
extends Control


@onready var _host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var _join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var _quit_button: Button = $CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	# Always restore mouse when opening the menu.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_host_pressed() -> void:
	print("Host button pressed")

	_host_button.disabled = true
	Networking.host_lobby()


func _on_join_pressed() -> void:
	print("Opening Steam Friends overlay...")
	Steam.activateGameOverlay("friends")


func _on_quit_pressed() -> void:
	get_tree().quit()
