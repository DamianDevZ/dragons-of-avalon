extends Control

@onready var wood_label       : Label    = %WoodLabel
@onready var food_label       : Label    = %FoodLabel
@onready var stone_label      : Label    = %StoneLabel
@onready var gold_label       : Label    = %GoldLabel
@onready var city_name_lbl    : Label    = %CityNameLabel
@onready var world_map_button : Button   = %WorldMapButton
@onready var city_view        : Control  = %CityView

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
	city_view.connect("slot_tapped", _on_slot_pressed)
	_update_resource_bar()
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
	city_view.call("set_buildings", _buildings)


func _on_slot_pressed(col: int, row: int) -> void:
	var key : String = "%d_%d" % [col, row]
	if _buildings.has(key):
		var b : Dictionary = _buildings[key] as Dictionary
		print("[City] Tapped building: ", b.get("building_type"), " at (", col, ",", row, ")")
	else:
		print("[City] Empty slot (", col, ",", row, ") — build menu here")


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