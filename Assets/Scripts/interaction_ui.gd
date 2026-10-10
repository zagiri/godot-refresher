
extends Control


@onready var _prompt_panel: PanelContainer = $PromptPanel
@onready var _key_label: Label = $PromptPanel/HBoxContainer/KeyPanel/KeyLabel
@onready var _action_label: Label = $PromptPanel/HBoxContainer/ActionLabel


func _ready() -> void:
	hide_prompt()


func show_prompt(action_text: String) -> void:
	_key_label.text = "E"
	_action_label.text = action_text
	_prompt_panel.show()


func hide_prompt() -> void:
	_prompt_panel.hide()
