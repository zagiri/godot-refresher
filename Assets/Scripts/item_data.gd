
class_name ItemData
extends Resource

enum ItemType {
	INGREDIENT,
	FOOD,
	CONTAINER,
	TOOL
}

@export_group("Information")
@export var item_name: String = ""
@export_multiline var description: String = ""
@export var item_type: ItemType = ItemType.INGREDIENT

@export_group("Visuals")
@export var icon: Texture2D
