class_name TravelUi
extends PanelContainer
## Balcão do aeroporto (E no balcão): lista pesquisável de destinos com o preço da passagem
## (pela distância) e se você tem o passaporte de lá; ao escolher um destino sem passaporte,
## ele entra junto na conta e o total aparece. A aba Passaportes vende o passaporte de
## qualquer país, até dos pequenos sem aeroporto. Preços e regras: servidor (economy.json).

var game: GameMain
var session: Session
## Aeroporto onde o jogador está (de onde sai a viagem).
var from := {}
var _title: Label
var _search: LineEdit
var _list: ItemList
var _detail: Label
var _go: Button
var _tabs: TabContainer
var _p_search: LineEdit
var _p_list: ItemList
var _p_buy: Button
var _p_detail: Label
var _quotes: Array = []
var _prices: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26, Color("f4fbff")))
	custom_minimum_size = Vector2(860, 560)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = UiStyle.label("Aeroporto", 26, Color("3a6ea5"))
	box.add_child(UiStyle.header(_title, "Esc", func() -> void: visible = false))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStyle.tabs(_tabs)
	box.add_child(_tabs)

	var travel := HBoxContainer.new()
	travel.name = "Viajar"
	travel.add_theme_constant_override("separation", 12)
	_tabs.add_child(travel)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	travel.add_child(left)
	_search = UiStyle.line_edit("procurar destino…")
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	left.add_child(_search)
	_list = UiStyle.item_list()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(_i: int) -> void: _show())
	_list.item_activated.connect(func(_i: int) -> void: _travel())
	left.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	travel.add_child(right)
	_detail = UiStyle.label("Escolha um destino.", 18)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_detail)
	_go = UiStyle.button("Viajar")
	_go.pressed.connect(_travel)
	right.add_child(_go)

	var pass_tab := HBoxContainer.new()
	pass_tab.name = "Passaportes"
	pass_tab.add_theme_constant_override("separation", 12)
	_tabs.add_child(pass_tab)
	var pl := VBoxContainer.new()
	pl.custom_minimum_size = Vector2(420, 0)
	pass_tab.add_child(pl)
	_p_search = UiStyle.line_edit("procurar país…")
	_p_search.text_changed.connect(func(_t: String) -> void: _fill_passports())
	pl.add_child(_p_search)
	_p_list = UiStyle.item_list()
	_p_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_p_list.item_selected.connect(func(_i: int) -> void: _show_passport())
	pl.add_child(_p_list)
	var pr := VBoxContainer.new()
	pr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_tab.add_child(pr)
	_p_detail = UiStyle.label("Com o passaporte de um país, você entra nele a pé ou de avião.", 18)
	_p_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	_p_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pr.add_child(_p_detail)
	_p_buy = UiStyle.button("Comprar passaporte")
	_p_buy.pressed.connect(_buy_passport)
	pr.add_child(_p_buy)
	visible = false


func setup(g: GameMain, s: Session) -> void:
	game = g
	session = s
	session.coins_changed.connect(func(_d: int) -> void:
		if visible:
			_show()
			_show_passport())


## Abre o balcão do aeroporto `airport` e pede os preços ao servidor.
func open(airport: Dictionary) -> void:
	from = airport
	_title.text = str(airport.get("name", "Aeroporto"))
	visible = true
	_quotes = []
	_fill()
	var r := await game.api_request("GET", "/travel/quotes?from=" + str(airport.get("country", "")))
	if r["ok"]:
		_quotes = r["data"]["quotes"]
		_fill()
	var p := await game.api_request("GET", "/passport/prices")
	if p["ok"]:
		_prices = p["data"]["countries"]
		_fill_passports()


func _fill() -> void:
	_list.clear()
	var q := _search.text.strip_edges().to_lower()
	for a: Dictionary in _quotes:
		var name := str(a["country_name"])
		if not q.is_empty() and not name.to_lower().contains(q) and not str(a["city"]).to_lower().contains(q):
			continue
		var pass_tab := "  ·  passaporte ✓" if bool(a["has_passport"]) else "  ·  + passaporte"
		var i := _list.add_item("%s  —  %s%s" % [name, session.coins_text(int(a["fare"])), pass_tab])
		_list.set_item_metadata(i, a)
	_show()


func _selected() -> Dictionary:
	var sel := _list.get_selected_items()
	return _list.get_item_metadata(sel[0]) if not sel.is_empty() else {}


func _show() -> void:
	var a := _selected()
	if a.is_empty():
		_detail.text = "Escolha um destino na lista.\n\nVocê tem %s." % session.coins_text(session.coins)
		_go.disabled = true
		return
	var fare := int(a["fare"])
	var pass_tab := 0 if bool(a["has_passport"]) else int(a["passport_price"])
	var total := fare + pass_tab
	var lines := ["%s" % a["name"], "", "Passagem: %s" % session.coins_text(fare)]
	if pass_tab > 0:
		lines.append("Passaporte de %s: %s" % [a["country_name"], session.coins_text(pass_tab)])
		lines.append("(sem ele não dá para entrar no país)")
	lines.append("")
	lines.append("Total: %s" % session.coins_text(total))
	lines.append("Você tem %s." % session.coins_text(session.coins))
	_detail.text = "\n".join(lines)
	_go.disabled = session.coins < total
	_go.text = "Viajar" if pass_tab == 0 else "Comprar passaporte e viajar"


func _travel() -> void:
	var a := _selected()
	if a.is_empty() or _go.disabled:
		return
	visible = false
	game.travel(from, a, not bool(a["has_passport"]))


func _fill_passports() -> void:
	_p_list.clear()
	var q := _p_search.text.strip_edges().to_lower()
	var have: Array = session.passports()
	for c: Dictionary in _prices:
		var name := str(c["name"])
		if not q.is_empty() and not name.to_lower().contains(q):
			continue
		var owned := have.has(str(c["country"]))
		var i := _p_list.add_item("%s  —  %s" % [name, "você tem ✓" if owned else session.coins_text(int(c["price"]))])
		_p_list.set_item_metadata(i, c)
	_show_passport()


func _show_passport() -> void:
	var sel := _p_list.get_selected_items()
	if sel.is_empty():
		_p_buy.disabled = true
		return
	var c: Dictionary = _p_list.get_item_metadata(sel[0])
	var owned := session.passports().has(str(c["country"]))
	_p_detail.text = "Passaporte de %s\n\n%s\n\nVocê tem %s." % [c["name"],
		"Você já tem este passaporte." if owned else "Preço: %s" % session.coins_text(int(c["price"])), session.coins_text(session.coins)]
	_p_buy.disabled = owned or session.coins < int(c["price"])


func _buy_passport() -> void:
	var sel := _p_list.get_selected_items()
	if sel.is_empty():
		return
	var c: Dictionary = _p_list.get_item_metadata(sel[0])
	if await game.buy_passport(str(c["country"])):
		for a: Dictionary in _quotes:
			if a["country"] == c["country"]:
				a["has_passport"] = true
	_fill_passports()
	_fill()
