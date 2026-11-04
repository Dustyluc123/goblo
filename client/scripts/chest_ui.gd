class_name ChestUi
extends PanelContainer
## Baú do lote (fase 4.5, ADR 0057): o bolso de um lado, o baú do outro. Clique guarda ou
## tira um; com Shift, tudo daquele item. Só o dono abre; o servidor guarda o conteúdo.

var game: GameMain
var session: Session
var icons: ItemIcons
var chest_id := 0
var _bag: GridContainer
var _box: GridContainer
var _info: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(24))
	custom_minimum_size = Vector2(860, 500)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Baú", 26), "Esc", func() -> void: visible = false))
	box.add_child(UiStyle.label("Clique num item para passar um; Shift + clique passa todos.", 15, UiStyle.INK_SOFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	for side in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiStyle.label("Bolso" if side == 0 else "Baú", 19))
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size = Vector2(380, 330)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(grid)
		col.add_child(scroll)
		row.add_child(col)
		if side == 0:
			_bag = grid
		else:
			_box = grid
	_info = UiStyle.label("", 15, UiStyle.INK_SOFT)
	box.add_child(_info)
	visible = false


func setup(g: GameMain, s: Session, i: ItemIcons) -> void:
	game = g
	session = s
	icons = i


func open(id: int) -> void:
	chest_id = id
	var r := await game.api_request("GET", "/chest/%d" % id)
	if not r["ok"]:
		game.toast(str(r["message"]))
		return
	visible = true
	_show(r["data"])


func _show(v: Dictionary) -> void:
	if v.get("inventory") is Array:
		session.set_inventory(v["inventory"], int(v.get("slots_used", 0)))
	_fill(_bag, session.inventory, true)
	_fill(_box, v.get("items", []), false)
	_info.text = tr("Baú: %d de %d espaços · bolso: %d de %d") % [int(v.get("slots_used_chest", 0)), int(v.get("slots_max_chest", 0)),
		session.slots_used, session.slots_max]


func _fill(grid: GridContainer, list: Array, put: bool) -> void:
	for c in grid.get_children():
		c.queue_free()
	for st: Dictionary in list:
		var item := str(st["item"])
		var b := Button.new()
		b.custom_minimum_size = Vector2(68, 68)
		b.icon = icons.icon(item)
		b.expand_icon = true
		b.text = str(int(st["count"]))
		b.tooltip_text = session.item_name(item)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiStyle.slot(false))
		b.pressed.connect(func() -> void:
			var n := int(st["count"]) if Input.is_key_pressed(KEY_SHIFT) else 1
			var r := await game.api_request("POST", "/chest/%d/%s" % [chest_id, "put" if put else "take"], {"item": item, "count": n})
			if not r["ok"]:
				game.toast(str(r["message"]))
				return
			_show(r["data"]))
		grid.add_child(b)
