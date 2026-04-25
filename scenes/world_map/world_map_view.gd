class_name WorldMapView
extends Control

signal tile_pressed(x: int, y: int)

const TILE_W : int = 72
const TILE_H : int = 36

## Per-terrain flat colours.
const TERRAIN : Dictionary = {
	"field":    Color(0.95, 0.85, 0.20),
	"forest":   Color(0.20, 0.65, 0.20),
	"mountain": Color(0.60, 0.60, 0.60),
	"lake":     Color(0.20, 0.45, 0.85),
	"ruins":    Color(0.55, 0.45, 0.65),
	"volcano":  Color(0.80, 0.25, 0.10),
}

const OUTLINE      : Color = Color(0.0, 0.0, 0.0, 0.22)
const MY_BORDER    : Color = Color(0.95, 0.85, 0.10, 0.95)
const TAKEN_BORDER : Color = Color(0.85, 0.25, 0.25, 0.90)

var _tiles    : Dictionary = {}
var _my_uid   : String     = ""
var _map_cols : int        = 20
var _map_rows : int        = 20

## Panning state
var _pan_offset     : Vector2 = Vector2.ZERO
var _drag_start_pos : Vector2 = Vector2.ZERO
var _drag_start_pan : Vector2 = Vector2.ZERO
var _mouse_held     : bool    = false
var _is_dragging    : bool    = false
const DRAG_THRESHOLD_SQ : float = 64.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_tiles(tiles: Dictionary, my_uid: String, cols: int, rows: int) -> void:
	_tiles    = tiles
	_my_uid   = my_uid
	_map_cols = cols
	_map_rows = rows
	queue_redraw()


## (col, row) grid coords → isometric screen position of tile centre.
func _g2s(col: int, row: int) -> Vector2:
	var c : Vector2 = size * 0.5 + _pan_offset
	return c + Vector2(
		(col - row) * TILE_W * 0.5,
		(col + row) * TILE_H * 0.5
	)


## Screen position → nearest grid cell.
func _s2g(pos: Vector2) -> Vector2i:
	var c   : Vector2 = size * 0.5 + _pan_offset
	var rel : Vector2 = pos - c
	var hw  : float   = TILE_W * 0.5
	var hh  : float   = TILE_H * 0.5
	var col : int     = int(floor((rel.x / hw + rel.y / hh) * 0.5))
	var row : int     = int(floor((rel.y / hh - rel.x / hw) * 0.5))
	return Vector2i(col, row)


func _draw() -> void:
	# Painter's algorithm — draw far tiles first (lowest col+row depth).
	for depth in range(_map_cols + _map_rows - 1):
		for col in range(_map_cols):
			var row : int = depth - col
			if row >= 0 and row < _map_rows:
				_draw_tile(col, row)


func _draw_tile(col: int, row: int) -> void:
	var center : Vector2 = _g2s(col, row)
	var hw     : float   = TILE_W * 0.5
	var hh     : float   = TILE_H * 0.5
	var key    : String  = "%d_%d" % [col, row]

	var ttype : String = "field"
	var owner : String = ""
	if _tiles.has(key):
		var tile : Dictionary = _tiles[key] as Dictionary
		ttype = str(tile.get("tile_type", "field"))
		owner = str(tile.get("occupied_by", ""))

	var bc : Color = TERRAIN.get(ttype, TERRAIN["field"]) as Color

	# Flat ground diamond.
	var gp := PackedVector2Array([
		center + Vector2(0,   -hh),
		center + Vector2(hw,  0),
		center + Vector2(0,   hh),
		center + Vector2(-hw, 0),
	])
	draw_colored_polygon(gp, bc)
	draw_polyline(PackedVector2Array([gp[0], gp[1], gp[2], gp[3], gp[0]]), OUTLINE, 1.0)

	# Ownership border.
	if owner == _my_uid and _my_uid != "":
		draw_polyline(PackedVector2Array([gp[0], gp[1], gp[2], gp[3], gp[0]]), MY_BORDER, 2.5)
	elif owner != "" and owner != "null":
		draw_polyline(PackedVector2Array([gp[0], gp[1], gp[2], gp[3], gp[0]]), TAKEN_BORDER, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_mouse_held      = true
			_is_dragging     = false
			_drag_start_pos  = mb.position
			_drag_start_pan  = _pan_offset
		else:
			if not _is_dragging:
				var cell : Vector2i = _s2g(mb.position)
				if cell.x >= 0 and cell.x < _map_cols and cell.y >= 0 and cell.y < _map_rows:
					tile_pressed.emit(cell.x, cell.y)
			_mouse_held  = false
			_is_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _mouse_held:
		var mm     := event as InputEventMouseMotion
		var moved  : Vector2 = mm.position - _drag_start_pos
		if not _is_dragging and moved.length_squared() > DRAG_THRESHOLD_SQ:
			_is_dragging = true
		if _is_dragging:
			_pan_offset = _drag_start_pan + moved
			queue_redraw()
			accept_event()