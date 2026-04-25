class_name CityView
extends Control

signal slot_tapped(col: int, row: int)

const TILE_W    : int = 128
const TILE_H    : int = 64
const GRID_COLS : int = 5
const GRID_ROWS : int = 5

const GROUND_COLOR : Color = Color(0.38, 0.60, 0.28)
const GROUND_OCC   : Color = Color(0.30, 0.48, 0.22)
const OUTLINE      : Color = Color(0.0, 0.0, 0.0, 0.28)

const BUILDING_COLORS : Dictionary = {
	"castle":      Color(0.62, 0.62, 0.76),
	"lumber_mill": Color(0.60, 0.38, 0.18),
	"farm":        Color(0.72, 0.85, 0.28),
	"quarry":      Color(0.62, 0.58, 0.54),
	"gold_mine":   Color(0.90, 0.76, 0.12),
	"barracks":    Color(0.65, 0.25, 0.25),
	"market":      Color(0.88, 0.65, 0.20),
	"wall":        Color(0.72, 0.68, 0.60),
}

const BNAME : Dictionary = {
	"castle":      "Castle",
	"lumber_mill": "Mill",
	"farm":        "Farm",
	"quarry":      "Quarry",
	"gold_mine":   "Mine",
	"barracks":    "Barracks",
	"market":      "Market",
	"wall":        "Wall",
}

var _buildings : Dictionary = {}
var _origin    : Vector2    = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)


func _on_resized() -> void:
	_recalc_origin()
	queue_redraw()


func _recalc_origin() -> void:
	_origin = Vector2(size.x * 0.5, float(TILE_H) * 1.2)


func set_buildings(buildings: Dictionary) -> void:
	_buildings = buildings
	_recalc_origin()
	queue_redraw()


## Grid (col, row) to isometric screen position (centre of tile).
func _g2s(col: int, row: int) -> Vector2:
	return _origin + Vector2(
		(col - row) * TILE_W * 0.5,
		(col + row) * TILE_H * 0.5
	)


## Screen position to nearest grid cell.
func _s2g(pos: Vector2) -> Vector2i:
	var rel : Vector2 = pos - _origin
	var hw  : float   = TILE_W * 0.5
	var hh  : float   = TILE_H * 0.5
	var col : int = int(floor((rel.x / hw + rel.y / hh) * 0.5))
	var row : int = int(floor((rel.y / hh - rel.x / hw) * 0.5))
	return Vector2i(col, row)


func _draw() -> void:
	# Painter's algorithm: lower depth (col+row) = farther from viewer = draw first.
	for depth in range(GRID_COLS + GRID_ROWS - 1):
		for col in range(GRID_COLS):
			var row : int = depth - col
			if row >= 0 and row < GRID_ROWS:
				_draw_tile(col, row)


func _draw_tile(col: int, row: int) -> void:
	var center : Vector2 = _g2s(col, row)
	var hw     : float   = TILE_W * 0.5
	var hh     : float   = TILE_H * 0.5
	var key    : String  = "%d_%d" % [col, row]

	var btype : String = ""
	var blvl  : int    = 1
	if _buildings.has(key):
		var b : Dictionary = _buildings[key] as Dictionary
		btype = str(b.get("building_type", ""))
		blvl  = int(b.get("level", 1))

	var has_bld : bool = btype != ""

	# --- Ground diamond ---
	var gc : Color = GROUND_OCC if has_bld else GROUND_COLOR
	var gp := PackedVector2Array([
		center + Vector2(0,   -hh),
		center + Vector2(hw,  0),
		center + Vector2(0,   hh),
		center + Vector2(-hw, 0),
	])
	draw_colored_polygon(gp, gc)
	draw_polyline(PackedVector2Array([gp[0], gp[1], gp[2], gp[3], gp[0]]), OUTLINE, 1.0)

	if not has_bld:
		draw_line(center + Vector2(-7, 0), center + Vector2(7, 0), Color(1,1,1,0.18), 1.0)
		draw_line(center + Vector2(0, -4), center + Vector2(0, 4), Color(1,1,1,0.18), 1.0)
		return

	var base_col : Color = BUILDING_COLORS.get(btype, Color(0.55, 0.55, 0.65)) as Color
	var bh       : float = 22.0 + float(blvl) * 9.0

	# --- Right face (south-east, darkest) ---
	var rf := PackedVector2Array([
		center + Vector2(hw,  0),
		center + Vector2(0,   hh),
		center + Vector2(0,   hh - bh),
		center + Vector2(hw,  -bh),
	])
	var rc : Color = base_col.darkened(0.30)
	draw_colored_polygon(rf, rc)
	draw_polyline(PackedVector2Array([rf[0], rf[1], rf[2], rf[3], rf[0]]), OUTLINE, 1.0)

	# --- Left face (south-west, darker) ---
	var lf := PackedVector2Array([
		center + Vector2(-hw, 0),
		center + Vector2(0,   hh),
		center + Vector2(0,   hh - bh),
		center + Vector2(-hw, -bh),
	])
	var lc : Color = base_col.darkened(0.45)
	draw_colored_polygon(lf, lc)
	draw_polyline(PackedVector2Array([lf[0], lf[1], lf[2], lf[3], lf[0]]), OUTLINE, 1.0)

	# --- Top face (lightest) ---
	var tf := PackedVector2Array([
		center + Vector2(0,   -hh - bh),
		center + Vector2(hw,  -bh),
		center + Vector2(0,   hh - bh),
		center + Vector2(-hw, -bh),
	])
	var tc : Color = base_col.lightened(0.12)
	draw_colored_polygon(tf, tc)
	draw_polyline(PackedVector2Array([tf[0], tf[1], tf[2], tf[3], tf[0]]), OUTLINE, 1.0)

	# --- Label on top face ---
	var font      : Font   = ThemeDB.fallback_font
	var font_size : int    = 11
	var label_str : String = (BNAME.get(btype, btype) as String) + " " + str(blvl)
	var tw        : float  = font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var lpos      : Vector2 = center + Vector2(-tw * 0.5, -bh - hh * 0.25)
	draw_string(font, lpos, label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1,1,1,0.95))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		var cell : Vector2i = _s2g(mb.position)
		if cell.x >= 0 and cell.x < GRID_COLS and cell.y >= 0 and cell.y < GRID_ROWS:
			slot_tapped.emit(cell.x, cell.y)
			accept_event()