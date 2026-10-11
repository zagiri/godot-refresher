extends Node3D


# Fryer states
enum FryerState {
	IDLE,
	COOKING,
	READY
}


# Cooking settings
@export_group("Cooking")
@export var cooking_time := 5.0


# Node references
@onready var _interactable: Interactable = $InteractableBase
@onready var _equipment_ui: EquipmentUI = $EquipmentUI


# Fryer data
var _current_state: FryerState = FryerState.IDLE
var _cooking_timer: Timer


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)

	_cooking_timer = Timer.new()
	_cooking_timer.one_shot = true
	add_child(_cooking_timer)

	_cooking_timer.timeout.connect(_on_cooking_finished)

	_equipment_ui.set_title(name)
	_update_ui()


# Update cooking countdown
func _process(_delta: float) -> void:
	if _current_state != FryerState.COOKING:
		return

	var remaining: float = _cooking_timer.time_left

	var progress: float = 100.0 * (
		1.0 - remaining / maxf(cooking_time, 0.01)
	)

	_equipment_ui.set_progress(progress)
	_equipment_ui.set_timer(remaining)


# Handle interaction
func _on_interacted(_player: Node) -> void:
	match _current_state:
		FryerState.IDLE:
			_start_cooking()

		FryerState.COOKING:
			pass

		FryerState.READY:
			_collect_food()


# Start cooking
func _start_cooking() -> void:
	_current_state = FryerState.COOKING
	_cooking_timer.start(maxf(cooking_time, 0.01))
	_update_ui()


# Finish cooking
func _on_cooking_finished() -> void:
	_current_state = FryerState.READY
	_update_ui()


# Collect food
func _collect_food() -> void:
	_current_state = FryerState.IDLE
	_update_ui()


# Update equipment display
func _update_ui() -> void:
	match _current_state:
		FryerState.IDLE:
			_interactable.interaction_action = "Use"

			_equipment_ui.set_status("READY TO COOK")
			_equipment_ui.set_progress(0.0)
			_equipment_ui.set_timer(0.0)
			_equipment_ui.hide_status()

		FryerState.COOKING:
			_interactable.interaction_action = "Cooking..."

			_equipment_ui.set_status("COOKING")
			_equipment_ui.set_progress(0.0)
			_equipment_ui.set_timer(cooking_time)
			_equipment_ui.show_status()

		FryerState.READY:
			_interactable.interaction_action = "Grab Food From"

			_equipment_ui.set_status("FOOD READY!")
			_equipment_ui.set_progress(100.0)
			_equipment_ui.set_timer(0.0)
			_equipment_ui.show_status()

	# Refresh prompt if the player is already looking at the fryer
	_equipment_ui.set_prompt_text(
		_interactable.get_interaction_text()
	)
