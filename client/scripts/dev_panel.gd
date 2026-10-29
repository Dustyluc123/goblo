class_name DevPanel
extends PanelContainer
## Painel do modo desenvolvedor (F1). Só abre se o servidor estiver com GOBLO_DEV=1.
## Itens: dar qualquer item (lista pesquisável). Mundo: teleporte para país ou lat/lon,
## voar (noclip) e tempo. Jogador: obra na hora, dia seguinte, trocar país, resets e
## vizinhos falsos.

var game: GameMain
var session: Session
var icons: ItemIcons
var _item_search: LineEdit
var _item_list: ItemList
var _count: SpinBox
var _country_search: LineEdit
var _country_list: ItemList
var _lat: LineEdit
var _lon: LineEdit
var _noclip: CheckButton
var _status: Label
var _countries: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(22, Color("fdf6ff")))
	custom_minimum_size = Vector2(620, 540)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	offset_left = 16
	offset_top = -210
	offset_bottom = 330
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Modo dev", 24, Color("6b4c9a")), "F1 ou Esc", func() -> void: visible = false))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStyle.tabs(tabs)
	box.add_child(tabs)
	tabs.add_child(_items_tab())
	tabs.add_child(_world_tab())
	tabs.add_child(_player_tab())
	_status = UiStyle.label("", 15, UiStyle.INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)
	visible = false


func setup(g: GameMain, s: Session, i: ItemIcons, countries: Dictionary) -> void:
	game = g
	session = s
	icons = i
	_countries.clear()
	for code: String in countries:
		_countries.append([code, str(countries[code])])
	_countries.sort_custom(func(a: Array, b: Array) -> bool: return str(a[1]).naturalnocasecmp_to(b[1]) < 0)
	_fill_items()
	_fill_countries()


func toggle() -> void:
	visible = not visible
	if visible:
		_fill_items()
		_item_search.grab_focus()


func status(text: String) -> void:
	_status.text = text


func _items_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Itens"
	box.add_theme_constant_override("separation", 6)
	_item_search = UiStyle.line_edit("procurar item… (Enter dá o primeiro)")
	_item_search.text_changed.connect(func(_t: String) -> void: _fill_items())
	_item_search.text_submitted.connect(func(_t: String) -> void:
		if _item_list.item_count > 0:
			_item_list.select(0)
			_give())
	box.add_child(_item_search)
	_item_list = UiStyle.item_list()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.fixed_icon_size = Vector2i(32, 32)
	_item_list.item_activated.connect(func(_i: int) -> void: _give())
	box.add_child(_item_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiStyle.label("Quantidade", 17))
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 999
	_count.value = 10
	UiStyle.spin_box(_count)
	row.add_child(_count)
	var give := UiStyle.button("Dar")
	give.pressed.connect(_give)
	row.add_child(give)
	var kit := UiStyle.button("Kit inicial", false)
	kit.tooltip_text = "Machado, picareta, 99 madeiras, 99 pedras, 30 galhos e 20 flores"
	kit.pressed.connect(func() -> void: game.dev_starter_kit())
	row.add_child(kit)
	box.add_child(row)
	return box


func _fill_items() -> void:
	if session == null:
		return
	_item_list.clear()
	var q := _item_search.text.strip_edges().to_lower()
	for id: String in session.item_order:
		var name := session.item_name(id)
		if q.is_empty() or name.to_lower().contains(q) or id.contains(q):
			var i := _item_list.add_item("%s  (%s)" % [name, id], icons.icon(id))
			_item_list.set_item_metadata(i, id)


func _give() -> void:
	var sel := _item_list.get_selected_items()
	if sel.is_empty():
		status("Escolha um item na lista.")
		return
	game.dev_give(str(_item_list.get_item_metadata(sel[0])), int(_count.value))


func _world_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Mundo"
	box.add_theme_constant_override("separation", 6)
	_country_search = UiStyle.line_edit("procurar país…")
	_country_search.text_changed.connect(func(_t: String) -> void: _fill_countries())
	box.add_child(_country_search)
	_country_list = UiStyle.item_list()
	_country_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_country_list.item_activated.connect(func(_i: int) -> void: _teleport_country())
	box.add_child(_country_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var tp := UiStyle.button("Ir para o país")
	tp.pressed.connect(_teleport_country)
	row.add_child(tp)
	var home := UiStyle.button("Casa (H)", false)
	home.pressed.connect(func() -> void: game.go_home())
	row.add_child(home)
	box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	_lat = UiStyle.line_edit("lat (ex.: -3)")
	_lat.custom_minimum_size = Vector2(150, 0)
	_lon = UiStyle.line_edit("lon (ex.: -60)")
	_lon.custom_minimum_size = Vector2(150, 0)
	row2.add_child(_lat)
	row2.add_child(_lon)
	var go := UiStyle.button("Ir")
	go.pressed.connect(func() -> void:
		if _lat.text.is_valid_float() and _lon.text.is_valid_float():
			game.teleport_lat_lon(float(_lat.text), float(_lon.text))
		else:
			status("Lat e lon precisam ser números (ex.: -23.5 e -46.6)."))
	row2.add_child(go)
	box.add_child(row2)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	_noclip = CheckButton.new()
	_noclip.text = "Voar (noclip)"
	_noclip.focus_mode = Control.FOCUS_NONE
	_noclip.add_theme_color_override("font_color", UiStyle.INK)
	_noclip.toggled.connect(func(on: bool) -> void: game.set_noclip(on))
	row3.add_child(_noclip)
	var fast := UiStyle.button("Tempo mais rápido (F3)", false)
	fast.pressed.connect(func() -> void: game.time_faster())
	row3.add_child(fast)
	var real := UiStyle.button("Hora real (F4)", false)
	real.pressed.connect(func() -> void: game.time_real())
	row3.add_child(real)
	box.add_child(row3)
	box.add_child(UiStyle.label("Voando: WASD, Espaço sobe, Ctrl desce, Shift acelera.", 15, UiStyle.INK_SOFT))
	return box


func set_noclip_checked(on: bool) -> void:
	_noclip.set_pressed_no_signal(on)


func _fill_countries() -> void:
	_country_list.clear()
	var q := _country_search.text.strip_edges().to_lower()
	for c: Array in _countries:
		if q.is_empty() or str(c[1]).to_lower().contains(q) or str(c[0]).to_lower().contains(q):
			var i := _country_list.add_item("%s  (%s)" % [c[1], c[0]])
			_country_list.set_item_metadata(i, c[0])


func _selected_country() -> String:
	var sel := _country_list.get_selected_items()
	if sel.is_empty():
		status("Escolha um país na lista (aba Mundo).")
		return ""
	return str(_country_list.get_item_metadata(sel[0]))


func _teleport_country() -> void:
	var code := _selected_country()
	if not code.is_empty():
		game.teleport_country(code)


func _player_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Jogador"
	box.add_theme_constant_override("separation", 8)
	var actions := [
		["Concluir a obra agora", func() -> void: game.dev_finish_house(), true],
		["Avançar para o dia seguinte (limites e obra)", func() -> void: game.dev_next_day(), true],
		["Voltar o relógio do servidor para a hora real", func() -> void: game.dev_real_time(), false],
		["Criar 20 vizinhos falsos aqui perto", func() -> void: game.dev_fake_neighbors(20), true],
		["Trocar meu país para o selecionado na aba Mundo", func() -> void:
			var code := _selected_country()
			if not code.is_empty():
				game.dev_set_country(code), false],
		["Resetar o lote (casa e decoração)", func() -> void: game.dev_reset("lot"), false],
		["Resetar o inventário", func() -> void: game.dev_reset("inventory"), false],
		["Resetar as coletas de hoje", func() -> void: game.dev_reset("collections"), false],
		["Apagar o jogador inteiro (volta à tela inicial)", func() -> void: game.dev_reset("player"), false],
	]
	for a: Array in actions:
		var b := UiStyle.button(a[0], a[2])
		b.pressed.connect(a[1])
		box.add_child(b)
	return box
