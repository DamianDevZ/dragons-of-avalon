extends Control

const GRID_COLS : int = 5
const GRID_ROWS : int = 5

@onready var wood_label    : Label         = %WoodLabel
@onready var food_label    : Label         = %FoodLabel
@onready var stone_label   : Label         = %StoneLabel
@onready var gold_label    : Label         = %GoldLabel
@onready var city_name_lbl    : Label         = %CityNameLabel
@onready var world_map_button : Button        = %WorldMapButton
@onready var building_grid    : GridContainer = %BuildingGrid

## Keyed by "grid_x_grid_y" string, value is the building Dictionary from DB.
var _buildings : Dictionary = {}


var _tick : float = 0.0

func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_resource_bar()


func _ready() -> void:
	GameState.resources_updated.connect(_on_resources_updated)
	GameState.player_loaded.connect(_on_player_loaded)
	world_map_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/world_map/world_map.tscn"))
	_update_resource_bar()
	# Show player name if already loaded (e.g. reconnect scenario).
	if GameState.player != null:
		_on_player_loaded(GameState.player)
	_load_city()


func _load_city() -> void:
	var uid : String = SupabaseClient.get_user_id()
	if uid == "":
		return
	var result : Variant = await SupabaseClient.select(
		"city_buildings",
		"id,building_type,level,grid_x,grid_y,upgrade_complete_at",
		"player_id=eq." + uid
	)
	_buildings.clear()
	if result is Array:
		for item : Variant in result:
			if typeof(item) == TYPE_DICTIONARY:
				var b : Dictionary = item as Dictionary
				var key : String = "%d_%d" % [int(b.get("grid_x", 0)), int(b.get("grid_y", 0))]
				_buildings[key] = b
	elif result is Dictionary:
		push_error("[City] Failed to load buildings: " + str((result as Dictionary).get("error", "")))
	_render_grid()


func _render_grid() -> void:
	for child in building_grid.get_children():
		child.queue_free()
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var key : String = "%d_%d" % [col, row]
			var slot := Button.new()
			slot.custom_minimum_size = Vector2(120, 90)
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if _buildings.has(key):
				var b : Dictionary = _buildings[key] as Dictionary
				var btype : String  = str(b.get("building_type", "empty"))
				var lvl   : int     = int(b.get("level", 1))
				var upgrading : bool = b.get("upgrade_complete_at", null) != null
				var display : String = btype.capitalize().replace("_", " ")
				slot.text = display + "\nLv " + str(lvl)
				if upgrading:
					slot.text += " (upgrading)"
			else:
				slot.text = "[ Empty ]\n(" + str(col) + "," + str(row) + ")"
			var c : int = col
			var r : int = row
			slot.pressed.connect(func(): _on_slot_pressed(c, r))
			building_grid.add_child(slot)


func _on_slot_pressed(col: int, row: int) -> void:
	var key : String = "%d_%d" % [col, row]
	if _buildings.has(key):
		var b : Dictionary = _buildings[key] as Dictionary
		print("[City] Tapped building: ", b.get("building_type"), " at (", col, ",", row, ")")
	else:
		print("[City] Empty slot (", col, ",", row, ") — build menu would open here")


func _update_resource_bar() -> void:
	wood_label.text  = "Wood:  " + str(int(GameState.get_live_wood()))
	food_label.text  = "Food:  " + str(int(GameState.get_live_food()))
	stone_label.text = "Stone: " + str(int(GameState.get_live_stone()))
	gold_label.text  = "Gold:  " + str(int(GameState.get_live_gold()))


func _on_resources_updated(_snapshot: Variant) -> void:
	_update_resource_bar()


func _on_player_loaded(pd: Variant) -> void:
	if typeof(pd) == TYPE_OBJECT:
		var player := pd as GameState.PlayerData
		if player != null and player.display_name != "":
			city_name_lbl.text = player.display_name + "'s Kingdom"