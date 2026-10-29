class_name CraftUi
extends PanelContainer
## Menu da bancada (E perto dela): receitas (vindas do servidor, GET /content) e a casa.

var game: GameMain
var session: Session
var icons: ItemIcons
var _tabs: TabContainer
var _list: ItemList
var _detail: VBoxContainer
var _house_box: VBoxContainer
var _selected := 0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26))
	custom_minimum_size = Vector2(640, 430)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := UiStyle.label("Bancada", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiStyle.label("Esc fecha", 13, UiStyle.INK_SOFT))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStyle.tabs(_tabs)
	box.add_child(_tabs)

	var recipes := HBoxContainer.new()
	recipes.name = "Receitas"
	recipes.add_theme_constant_override("separation", 12)
	_tabs.add_child(recipes)
	_list = UiStyle.item_list()
	_list.custom_minimum_size = Vector2(270, 0)
	_list.fixed_icon_size = Vector2i(36, 36)
	_list.item_selected.connect(func(i: int) -> void:
		_selected = i
		_show_recipe())
	recipes.add_child(_list)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	recipes.add_child(_detail)

	_house_box = VBoxContainer.new()
	_house_box.name = "Casa"
	_house_box.add_theme_constant_override("separation", 10)
	_tabs.add_child(_house_box)
	visible = false


func setup(g: GameMain, s: Session, i: ItemIcons) -> void:
	game = g
	session = s
	icons = i
	session.inventory_changed.connect(func() -> void:
		if visible:
			refresh())
	session.me_changed.connect(func() -> void:
		if visible:
			refresh())


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	_list.clear()
	for r: Dictionary in session.recipes:
		var i := _list.add_item(session.item_name(r["result"]), icons.icon(r["result"]))
		if not session.can_afford(r["ingredients"]):
			_list.set_item_custom_fg_color(i, UiStyle.INK_SOFT)
	if _list.item_count > 0:
		_selected = clampi(_selected, 0, _list.item_count - 1)
		_list.select(_selected)
	_show_recipe()
	_show_house()


func _show_recipe() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _selected >= session.recipes.size():
		return
	var r: Dictionary = session.recipes[_selected]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.texture = icons.icon(r["result"])
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var names := VBoxContainer.new()
	var count := int(r.get("count", 1))
	names.add_child(UiStyle.label(session.item_name(r["result"]) + ("  ×%d" % count if count > 1 else ""), 20))
	var item: Dictionary = session.items.get(r["result"], {})
	var kind := {"tool": "ferramenta", "placeable": "para colocar no lote", "material": "material"}
	names.add_child(UiStyle.label(str(kind.get(item.get("category", ""), "")), 13, UiStyle.INK_SOFT))
	names.add_child(UiStyle.label("Você tem: %d" % session.count(r["result"]), 13, UiStyle.INK_SOFT))
	head.add_child(names)
	_detail.add_child(head)
	_detail.add_child(UiStyle.label("Precisa de:", 15))
	_detail.add_child(_cost_list(r["ingredients"]))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)
	var b := UiStyle.button("Fabricar")
	b.disabled = not session.can_afford(r["ingredients"])
	b.pressed.connect(func() -> void: game.craft(r["id"]))
	_detail.add_child(b)


func _cost_list(cost: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	for k: String in cost:
		var need := int(cost[k])
		var have := session.have_for(k)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if not k.begins_with("#"):
			var ic := TextureRect.new()
			ic.texture = icons.icon(k)
			ic.custom_minimum_size = Vector2(28, 28)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(ic)
		row.add_child(UiStyle.label("%s: %d/%d" % [session.cost_label(k), mini(have, need), need], 15, UiStyle.OK if have >= need else UiStyle.WARN))
		box.add_child(row)
	return box


func _show_house() -> void:
	for c in _house_box.get_children():
		c.queue_free()
	var lot := session.lot()
	var house: Variant = lot.get("house")
	var level := 0
	var pending := 0
	if house is Dictionary:
		level = int(house.get("level", 0))
		pending = int(house.get("pending_level", 0))
	var now_name := "nenhuma (só o terreno)" if level == 0 else str(session.house_level(level).get("name", "?"))
	_house_box.add_child(UiStyle.label("Sua casa: " + now_name, 20))
	if pending > 0:
		_house_box.add_child(UiStyle.label("Em obras: %s. Fica pronta na próxima virada do dia (5h no seu horário)." % session.house_level(pending).get("name", "?"), 15, UiStyle.INK_SOFT))
		return
	var next := session.house_level(level + 1)
	if next.is_empty():
		_house_box.add_child(UiStyle.label("Sua casa já está no nível máximo. Que linda!", 15, UiStyle.INK_SOFT))
		return
	var fp: Array = next["footprint"]
	_house_box.add_child(UiStyle.label("Próximo nível: %s (%d × %d quadradinhos)" % [next["name"], fp[0], fp[1]], 16))
	_house_box.add_child(_cost_list(next["cost"]))
	var b := UiStyle.button("Escolher o lugar e construir" if level == 0 else "Melhorar a casa")
	b.disabled = not session.can_afford(next["cost"])
	if level == 0:
		b.pressed.connect(func() -> void:
			visible = false
			game.start_house_placement())
	else:
		b.pressed.connect(func() -> void: game.upgrade_house())
	_house_box.add_child(b)
	_house_box.add_child(UiStyle.label("A obra fica pronta no dia seguinte, como no Animal Crossing.", 13, UiStyle.INK_SOFT))
