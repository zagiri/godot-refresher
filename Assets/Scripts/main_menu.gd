
extends Control


# Local tab
@onready var _host_lan_button: Button = $CenterContainer/VBoxContainer/TabContainer/Local/HBoxContainer/HostLANButton
@onready var _join_lan_button: Button = $CenterContainer/VBoxContainer/TabContainer/Local/HBoxContainer/JoinLANButton
@onready var _ip_address_input: LineEdit = $CenterContainer/VBoxContainer/TabContainer/Local/IPAddressInput

# Online tab
@onready var _host_button: Button = $CenterContainer/VBoxContainer/TabContainer/Online/HostButton
@onready var _join_button: Button = $CenterContainer/VBoxContainer/TabContainer/Online/JoinButton

# Quit
@onready var _quit_button: Button = $CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Local
	_host_lan_button.pressed.connect(_on_host_lan_pressed)
	_join_lan_button.pressed.connect(_on_join_lan_pressed)
	_ip_address_input.text_changed.connect(_on_ip_address_changed)

	# Online
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)

	# Quit
	_quit_button.pressed.connect(_on_quit_pressed)


# Host local game
func _on_host_lan_pressed() -> void:
	print("Host LAN button pressed")

	_host_lan_button.disabled = true
	Networking.host_lan()


# Join local game
func _on_join_lan_pressed() -> void:
	var ip_address := _ip_address_input.text.strip_edges()

	if ip_address.is_empty():
		ip_address = "127.0.0.1"

	print("Joining LAN server: ", ip_address)

	_join_lan_button.disabled = true
	Networking.join_lan(ip_address)


# Host Steam game
func _on_host_pressed() -> void:
	print("Host button pressed")

	_host_button.disabled = true
	Networking.host_lobby()


# Join Steam friend
func _on_join_pressed() -> void:
	print("Opening Steam Friends overlay...")
	Steam.activateGameOverlay("friends")


# Quit game
func _on_quit_pressed() -> void:
	get_tree().quit()


# Allow only numbers and periods in IP address
func _on_ip_address_changed(new_text: String) -> void:
	var filtered_text := ""

	for character in new_text:
		if character in "0123456789.":
			filtered_text += character

	if filtered_text != new_text:
		var cursor_position := _ip_address_input.caret_column

		_ip_address_input.text = filtered_text
		_ip_address_input.caret_column = mini(
			cursor_position,
			filtered_text.length()
		)
