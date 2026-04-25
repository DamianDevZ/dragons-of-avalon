extends Control

## World grid dimensions. Must match world_tiles seeded in the DB.
const MAP_COLS : int = 20
const MAP_ROWS : int = 20

## Colour tints per tile type — purely cosmetic.
const TILE_COLORS : Dictionary = {
	"field":    Color(0.85, 0.80, 0.30),
	"forest":   Color(0.15, 0.50, 0.20),
	"mountain": Color(0.55, 0.50, 0.45),
	"lake":     Color(0.20, 0.45, 0.75),
	"ruins":    Color(0.55, 0.35, 0.60),
	"volcano":  Color(0.80, 0.25, 0.10),
}

@onready var tile_grid        : GridContainer   = %TileGrid
@onready var status_lbl       : Label           = %StatusLabel
@onready var back_button      : Button          = %BackButton
@onready var scroll_container : ScrollContainer = $VBox/Scroll

## Drag-to-pan state
const DRAG_THRESHOLD_SQ : float = 64.0  # 8 px before drag is committed
var _mouse_held    : bool     = false
var _is_dragging   : bool     = false
var _press_pos     : Vector2  = Vector2.ZERO
var _scroll_start  : Vector2i = Vector2i.ZERO

## world_tiles rows keyed by "x_y".
var _tiles : Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_load_map()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_mouse_held   = true
			_is_dragging  = false
			_press_pos    = mb.global_position
			_scroll_start = Vector2i(
				scroll_container.scroll_horizontal,
				scroll_container.scroll_vertical
			)
		else:
			if _is_dragging:
				get_viewport().set_input_as_handled()  # cancel tile button press
			_mouse_held  = false
			_is_dragging = false
	elif event is InputEventMouseMotion and _mouse_held:
		var mm     := event as InputEventMouseMotion
		var moved  : Vector2 = mm.global_position - _press_pos
		if not _is_dragging and moved.length_squared() > DRAG_THRESHOLD_SQ:
			_is_dragging = true
		if _is_dragging:
			scroll_container.scroll_horizontal = _scroll_start.x - int(moved.x)
			scroll_container.scroll_vertical   = _scroll_start.y - int(moved.y)
			get_viewport().set_input_as_handled()


func _load_map() -> void:
	status_lbl.text = "Loading map..."
	var result : Variant = await SupabaseClient.select(
		"world_tiles",
		"x,y,tile_type,occupied_by",
		""
	)
	if result is Dictionary:
		push_error("[WorldMap] Failed to load tiles: " + str((result as Dictionary).get("error", "")))
		status_lbl.text = "Failed to load map."
		return
	_tiles.clear()
	if result is Array:
		for item : Variant in result:
			if typeof(item) == TYPE_DICTIONARY:
				var tile : Dictionary = item as Dictionary
				var key : String = "%d_%d" % [int(tile.get("x", 0)), int(tile.get("y", 0))]
				_tiles[key] = tile
	_render_map()
	status_lbl.text = str(_tiles.size()) + " tiles loaded"


func _render_map() -> void:
	for child in tile_grid.get_children():
		child.queue_free()
	var my_uid : String = SupabaseClient.get_user_id()
	for row in range(MAP_ROWS):
		for col in range(MAP_COLS):
			var key : String = "%d_%d" % [col, row]
			var tile_btn := Button.new()
			tile_btn.custom_minimum_size = Vector2(52, 52)
			tile_btn.clip_text = true
			if _tiles.has(key):
				var tile : Dictionary = _tiles[key] as Dictionary
				var ttype  : String = str(tile.get("tile_type", "field"))
				var owner  : String = str(tile.get("occupied_by",  ""))
				var color  : Color  = TILE_COLORS.get(ttype, Color(0.6, 0.6, 0.6)) as Color
				if owner == my_uid:
					tile_btn.text = "[Mine]\n" + ttype
				elif owner != "":
					tile_btn.text = "[Taken]\n" + ttype
				else:
					tile_btn.text = ttype
				tile_btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
				tile_btn.add_theme_stylebox_override("normal", _colored_stylebox(color))
			else:
				tile_btn.text = "?"
			var tx : int = col
			var ty : int = row
			tile_btn.pressed.connect(func(): _on_tile_pressed(tx, ty))
			tile_grid.add_child(tile_btn)


func _colored_stylebox(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left     = 4
	sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_left  = 4
	sb.corner_radius_bottom_right = 4
	return sb


func _on_tile_pressed(tx: int, ty: int) -> void:
	var key : String = "%d_%d" % [tx, ty]
	if not _tiles.has(key):
		return
	var tile : Dictionary = _tiles[key] as Dictionary
	var owner : String = str(tile.get("occupied_by", ""))
	var my_uid : String = SupabaseClient.get_user_id()
	print("[WorldMap] Tile (", tx, ",", ty, ") type=", tile.get("tile_type"), " owner=", owner)
	if owner == "" and my_uid != "":
		print("[WorldMap] Tile is unclaimed — claim logic would go here")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/city/city.tscn")