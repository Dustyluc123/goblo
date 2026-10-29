class_name SellUi
extends PanelContainer
## Caixa de vendas (E perto dela, no lote): mostra o que dá para vender do bolso, com o
## preço de cada unidade, e paga na hora. Preços e regras ficam no servidor (economy.json,
## POST /sell); aqui só se escolhe o quê e quanto.

var game: GameMain
var session: Session
var icons: ItemIcons
var _rows: VBoxContainer
var _empty: Label
var _total: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26))
	custom_minimum_size = Vector2(620, 480)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Caixa de vendas", 26), "Esc", func() -> void: visible = false))
	box.add_child(UiStyle.label("Coloque itens na caixa e receba na hora.", 16, UiStyle.INK_SOFT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	_empty = UiStyle.label("Nada para vender no bolso. Madeira, pedra, flores, frutinhas e cocos valem moedas!", 16, UiStyle.INK_SOFT)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_empty)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	_total = UiStyle.label("", 18)
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_total)
	var all := UiStyle.button("Vender tudo")
	all.pressed.connect(func() -> void: game.sell(_everything()))
	foot.add_child(all)
	box.add_child(foot)
	visible = false


func setup(g: GameMain, s: Session, i: ItemIcons) -> void:
	game = g
	session = s
	icons = i
	session.inventory_changed.connect(func() -> void:
		if visible:
			refresh())


func open() -> void:
	visible = true
	refresh()


func _everything() -> Array:
	var out: Array = []
	for st: Dictionary in session.inventory:
		if int(session.sell_prices.get(st["item"], 0)) > 0:
			out.append({"item": st["item"], "count": int(st["count"])})
	return out


func refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var total := 0
	for st: Dictionary in session.inventory:
		var id: String = st["item"]
		var price := int(session.sell_prices.get(id, 0))
		if price <= 0:
			continue
		var n := int(st["count"])
		total += price * n
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ic := TextureRect.new()
		ic.texture = icons.icon(id)
		ic.custom_minimum_size = Vector2(44, 44)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
		var name := UiStyle.label("%s  ×%d" % [session.item_name(id), n], 18)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var coin := CoinIcon.new()
		coin.diameter = 18.0
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
		row.add_child(UiStyle.label("%d cada" % price, 16, UiStyle.INK_SOFT))
		var one := UiStyle.button("Vender 1", false)
		one.pressed.connect(func() -> void: game.sell([{"item": id, "count": 1}]))
		row.add_child(one)
		var every := UiStyle.button("Todos")
		every.pressed.connect(func() -> void: game.sell([{"item": id, "count": n}]))
		row.add_child(every)
		_rows.add_child(row)
	_empty.visible = total == 0
	_total.text = "Tudo vale %s" % session.coins_text(total) if total > 0 else ""
