extends Control

const MAP_COLS : int = 20
const MAP_ROWS : int = 20

@onready var status_lbl      : Label   = %StatusLabel
@onready var back_button     : Button  = %BackButton
@onready var world_map_view  : Control = %WorldMapView

var _tiles : Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	world_map_view.connect("tile_pressed", _on_tile_pressed)
	_load_map()


func _load_map() -> void:
	status_lbl.text = "Loading map..."
	var result : Variant = await SupabaseClient.select(
		"world_tiles",
		"x,y,tile_type,occupied_by",
		""
	)
	if result is Dictionary:
		push_error("[WorldMap] Failed: " + str((result as Dictionary).get("error", "")))
		status_lbl.text = "Failed to load map."
		return
	_tiles.clear()
	if result is Array:
		for item : Variant in result:
			if typeof(item) == TYPE_DICTIONARY:
				var tile : Dictionary = item as Dictionary
				var key : String = "%d_%d" % [int(tile.get("x", 0)), int(tile.get("y", 0))]
				_tiles[key] = tile
	world_map_view.call("set_tiles", _tiles, SupabaseClient.get_user_id(), MAP_COLS, MAP_ROWS)
	status_lbl.text = str(_tiles.size()) + " tiles"


func _on_tile_pressed(tx: int, ty: int) -> void:
	var key : String = "%d_%d" % [tx, ty]
	if not _tiles.has(key):
		return
	var tile : Dictionary = _tiles[key] as Dictionary
	var owner : String = str(tile.get("occupied_by", ""))
	var my_uid : String = SupabaseClient.get_user_id()
	print("[WorldMap] Tile (", tx, ",", ty, ") type=", tile.get("tile_type"), " owner=", owner)
	if owner == "" and my_uid != "":
		print("[WorldMap] Unclaimed — march/claim logic goes here")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/city/city.tscn")