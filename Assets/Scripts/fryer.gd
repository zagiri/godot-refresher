
extends Node3D


# Fryer states
enum FryerState {
	IDLE,
	COOKING,
	READY
}


# Fryer settings
@export_group("Cooking")
@export var cooking_time := 5.0


# Node references
@onready var _interactable: Interactable = $InteractableBase


# Fryer data
var _current_state: FryerState = FryerState.IDLE
var _cooking_timer: Timer


func _ready() -> void:
	# Connect the interaction signal
	_interactable.interacted.connect(_on_interacted)

	# Create the cooking timer
	_cooking_timer = Timer.new()
	_cooking_timer.one_shot = true
	add_child(_cooking_timer)

	# Connect timer completion
	_cooking_timer.timeout.connect(_on_cooking_finished)

	print("Fryer ready!")


# Handle player interactions
func _on_interacted(player: Node) -> void:
	match _current_state:
		FryerState.IDLE:
			_start_cooking(player)

		FryerState.COOKING:
			print("Fryer is already cooking!")

		FryerState.READY:
			_collect_food(player)


# Start cooking
func _start_cooking(player: Node) -> void:
	_current_state = FryerState.COOKING
	_cooking_timer.start(cooking_time)

	print(player.name, " started cooking!")
	print("Cooking time: ", cooking_time, " seconds")


# Called when the cooking timer finishes
func _on_cooking_finished() -> void:
	_current_state = FryerState.READY
	print("Food is ready!")


# Collect the cooked food
func _collect_food(player: Node) -> void:
	print(player.name, " collected the food!")

	_current_state = FryerState.IDLE
	print("Fryer is available again!")
