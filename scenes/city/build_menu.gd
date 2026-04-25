extends Control

signal build_requested(building_type: String, col: int, row: int)
signal upgrade_requested(building_id: String, col: int, row: int)

@onready var title_lbl : Label         = $Panel/VBox/TitleLabel
@onready var item_vbox : VBoxContainer = $Panel/VBox/Scroll/ItemVBox
@onready var close_btn : Button        = $Panel/VBox/CloseButton

const BUILD_COSTS : Dictionary = {
	"lumber_mill": {"wood": 50,  "food": 0,  "stone": 20, "gold": 10},
	"farm":        {"wood": 30,  "food": 0,  "stone": 10, "gold": 5 },
	"quarry":      {"wood": 40,  "food": 0,  "stone": 0,  "gold": 10},
	"gold_mine":   {"wood": 60,  "food": 20, "stone": 40, "gold": 0 },
	"barracks":    {"wood": 80,  "food": 40, "stone": 60, "gold": 20},
	"market":      {"wood": 60,  "food": 20, "stone": 30, "gold": 0 },
	"wall":        {"wood": 20,  "food": 0,  "stone": 80, "gold": 0 },
}

const BNAME : Dictionary = {
	"lumber_mill": "Lumber Mill",
	"farm":        "Farm",
	"quarry":      "Quarry",
	"gold_mine":   "Gold Mine",
	"barracks":    "Barracks",
	"market":      "Market",
	"wall":        "Wall",
}

var _col : int = 0
var _row : int = 0


func _ready() -> void:
	close_btn.pressed.connect(hide_menu)


func show_empty(col: int, row: int) -> void:
	_col = col
	_row = row
	title_lbl.text = "Build at (%d, %d)" % [col, row]
	_clear_items()
	for btype : String in BUILD_COSTS.keys():
		_add_build_button(btype)
	visible = true


func show_building(col: int, row: int, bdata: Dictionary) -> void:
	_col      = col
	_row      = row
	var btype : String = str(bdata.get("building_type", "?"))
	var level : int    = int(bdata.get("level", 1))
	var bid   : String = str(bdata.get("id", ""))
	title_lbl.text = "%s  (Level %d)" % [BNAME.get(btype, btype), level]
	_clear_items()
	var next_lv : int = level + 1
	if BUILD_COSTS.has(btype):
		var base : Dictionary = BUILD_COSTS[btype] as Dictionary
		var btn  : Button     = Button.new()
		btn.text = "Upgrade to Lv %d  |  Wood:%d  Stone:%d  Gold:%d" % [
			next_lv,
			int(base.get("wood", 0)) * level,
			int(base.get("stone", 0)) * level,
			int(base.get("gold", 0)) * level,
		]
		btn.pressed.connect(func(): upgrade_requested.emit(bid, _col, _row))
		item_vbox.add_child(btn)
	else:
		var info : Label = Label.new()
		info.text = "No upgrades available."
		item_vbox.add_child(info)
	visible = true


func hide_menu() -> void:
	visible = false
	_clear_items()


func _clear_items() -> void:
	for c : Node in item_vbox.get_children():
		c.queue_free()


func _add_build_button(btype: String) -> void:
	var costs : Dictionary = BUILD_COSTS[btype] as Dictionary
	var btn   : Button     = Button.new()
	btn.text = "%s  |  Wood:%d  Food:%d  Stone:%d  Gold:%d" % [
		BNAME.get(btype, btype),
		int(costs.get("wood", 0)),
		int(costs.get("food", 0)),
		int(costs.get("stone", 0)),
		int(costs.get("gold", 0)),
	]
	btn.pressed.connect(func(): build_requested.emit(btype, _col, _row))
	item_vbox.add_child(btn)