class_name ShopUi
extends PanelContainer
## Loja da praça central (fase 3.5, ADR 0042): o estoque do dia do país (igual para todos
## do país, muda às 5h do horário de lá), com itens fixos, os do dia e os exclusivos da
## região. Comprar e vender passam pelo servidor (GET /shop, POST /shop/buy e /shop/sell);
## os preços vêm de lá (Service.Price, com os modificadores do país).

var game: GameMain
var session: Session
var icons: ItemIcons
var country := ""
var _title: Label
var _hint: Label
var _rows: VBoxContainer
var _coins: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26, Color("fff8ec")))
	custom_minimum_size = Vector2(760, 540)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UiStyle.label("Loja", 26, Color("b5566b"))
	box.add_child(UiStyle.header(_title, "Esc", func() -> void: visible = false))
	_hint = UiStyle.label("", 16, UiStyle.INK_SOFT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	_coins = UiStyle.label("", 18)
	_coins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_coins)
	var sell := UiStyle.button("Vender para a loja", false)
	sell.pressed.connect(func() -> void:
		visible = false
		game.open_shop_sell(country))
	foot.add_child(sell)
	box.add_child(foot)
	visible = false


func setup(g: GameMain, s: Session, i: ItemIcons) -> void:
	game = g
	session = s
	icons = i
	session.coins_changed.connect(func(_d: int) -> void: _coins.text = "Você tem %s" % session.coins_text(session.coins))


func open(c: String) -> void:
	country = c
	visible = true
	_title.text = "Loja"
	_hint.text = "Carregando o estoque…"
	for ch in _rows.get_children():
		ch.queue_free()
	_coins.text = "Você tem %s" % session.coins_text(session.coins)
	var r := await game.api_request("GET", "/shop?country=" + c)
	if not r["ok"]:
		_hint.text = str(r["message"])
		return
	_fill(r["data"])


func _fill(d: Dictionary) -> void:
	_title.text = "Loja de %s" % str(d.get("country_name", country))
	var left := int(d.get("next_rollover", 0)) - int(Time.get_unix_time_from_system())
	_hint.text = "Estoque de hoje (chega coisa nova em %dh%02d, às 5h daqui). Os itens do dia e os exclusivos daqui mudam todo dia!" % [maxi(0, left) / 3600, (maxi(0, left) % 3600) / 60]
	for ch in _rows.get_children():
		ch.queue_free()
	for st: Dictionary in d.get("stock", []):
		var id := str(st["item"])
		var price := int((st["price"] as Dictionary).get("total", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ic := TextureRect.new()
		ic.texture = icons.icon(id)
		ic.custom_minimum_size = Vector2(48, 48)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
		var name := UiStyle.label(str(st.get("name", id)), 18)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var kind := str(st.get("kind", ""))
		if kind != "fixed":
			row.add_child(UiStyle.label({"rotating": "do dia", "regional": "exclusivo daqui"}.get(kind, ""), 15, Color("b5566b")))
		var coin := CoinIcon.new()
		coin.diameter = 18.0
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
		row.add_child(UiStyle.label(session.price_text(price), 17))
		var qty := SpinBox.new()
		qty.min_value = 1
		qty.max_value = 20
		qty.value = 1
		qty.custom_minimum_size = Vector2(80, 0)
		UiStyle.spin_box(qty)
		row.add_child(qty)
		var buy := UiStyle.button("Comprar")
		buy.pressed.connect(func() -> void: game.shop_buy(country, id, int(qty.value)))
		row.add_child(buy)
		_rows.add_child(row)
