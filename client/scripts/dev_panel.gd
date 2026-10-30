class_name DevPanel
extends PanelContainer
## Painel do modo desenvolvedor (F1). Só abre se o servidor estiver com GOBLO_DEV=1.
## Itens: dar qualquer item (lista pesquisável) e moedas. Mundo: teleporte para país ou
## lat/lon, voar (noclip) e tempo. Viagem: passaportes, barreira da fronteira, voo de graça,
## linhas e polígonos das fronteiras. Natureza: forçar a estação, criar e listar animais,
## completar ou zerar a Goblopédia e o passaporte. Jogador: obra na hora, dia seguinte,
## trocar país, resets e vizinhos falsos.

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
var _coins: SpinBox
var _species: OptionButton


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(22, Color("fdf6ff")))
	custom_minimum_size = Vector2(680, 580)
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
	tabs.add_child(_travel_tab())
	tabs.add_child(_nature_tab())
	tabs.add_child(_player_tab())
	tabs.add_child(_net_tab())
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
	_species.clear()
	var ids: Array = s.animal_species.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return str(s.animal_species[a]["name"]) < str(s.animal_species[b]["name"]))
	for id: String in ids:
		_species.add_item(str(s.animal_species[id]["name"]))
		_species.set_item_metadata(_species.item_count - 1, id)


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
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 8)
	var coin := CoinIcon.new()
	coin.diameter = 22.0
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money.add_child(coin)
	money.add_child(UiStyle.label("Moedas", 17))
	_coins = SpinBox.new()
	_coins.min_value = 1
	_coins.max_value = 100000
	_coins.value = 500
	UiStyle.spin_box(_coins)
	money.add_child(_coins)
	var give_coins := UiStyle.button("Dar moedas")
	give_coins.pressed.connect(func() -> void: game.dev_coins(int(_coins.value)))
	money.add_child(give_coins)
	var take_coins := UiStyle.button("Tirar", false)
	take_coins.pressed.connect(func() -> void: game.dev_coins(-int(_coins.value)))
	money.add_child(take_coins)
	box.add_child(money)
	return box


func _travel_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Viagem"
	box.add_theme_constant_override("separation", 8)
	box.add_child(UiStyle.label("País: o selecionado na aba Mundo.", 15, UiStyle.INK_SOFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var give := UiStyle.button("Dar passaporte")
	give.pressed.connect(func() -> void:
		var code := _selected_country()
		if not code.is_empty():
			game.dev_passport("give", code))
	row.add_child(give)
	var remove := UiStyle.button("Tirar passaporte", false)
	remove.pressed.connect(func() -> void:
		var code := _selected_country()
		if not code.is_empty():
			game.dev_passport("remove", code))
	row.add_child(remove)
	var fly := UiStyle.button("Voar de graça para lá")
	fly.tooltip_text = "Vai ao aeroporto do país selecionado sem pagar nem precisar de passaporte"
	fly.pressed.connect(func() -> void:
		var code := _selected_country()
		if not code.is_empty():
			visible = false
			game.dev_travel(code))
	row.add_child(fly)
	box.add_child(row)
	var barrier := CheckButton.new()
	barrier.text = "Barreira da fronteira (passaporte) ligada"
	barrier.button_pressed = true
	barrier.focus_mode = Control.FOCUS_NONE
	barrier.add_theme_color_override("font_color", UiStyle.INK)
	barrier.add_theme_color_override("font_pressed_color", UiStyle.INK)
	barrier.add_theme_color_override("font_hover_pressed_color", UiStyle.INK)
	barrier.add_theme_color_override("font_hover_color", UiStyle.INK)
	barrier.toggled.connect(func(on: bool) -> void: game.set_barrier(on))
	box.add_child(barrier)
	var lines := CheckButton.new()
	lines.text = "Linhas de fronteira no chão"
	lines.button_pressed = true
	lines.focus_mode = Control.FOCUS_NONE
	lines.add_theme_color_override("font_color", UiStyle.INK)
	lines.add_theme_color_override("font_pressed_color", UiStyle.INK)
	lines.add_theme_color_override("font_hover_pressed_color", UiStyle.INK)
	lines.add_theme_color_override("font_hover_color", UiStyle.INK)
	var debug := CheckButton.new()
	debug.text = "Polígonos de debug (costa e cores por país)"
	debug.focus_mode = Control.FOCUS_NONE
	debug.add_theme_color_override("font_color", UiStyle.INK)
	debug.add_theme_color_override("font_pressed_color", UiStyle.INK)
	debug.add_theme_color_override("font_hover_pressed_color", UiStyle.INK)
	debug.add_theme_color_override("font_hover_color", UiStyle.INK)
	lines.toggled.connect(func(on: bool) -> void: game.set_border_lines(on, debug.button_pressed))
	debug.toggled.connect(func(on: bool) -> void: game.set_border_lines(lines.button_pressed, on))
	box.add_child(lines)
	box.add_child(debug)
	var view := HBoxContainer.new()
	view.add_theme_constant_override("separation", 6)
	view.add_child(UiStyle.label("Visão da fronteira:", 16))
	for opt: Array in [["Pelos passaportes", ""], ["Todas abertas", "open"], ["Todas fechadas", "closed"]]:
		var b := UiStyle.button(opt[0], false)
		var mode: String = opt[1]
		b.pressed.connect(func() -> void: game.set_border_view(mode))
		view.add_child(b)
	box.add_child(view)
	var book := HBoxContainer.new()
	book.add_theme_constant_override("separation", 6)
	var complete := UiStyle.button("Completar o passaporte", false)
	complete.tooltip_text = "Todos os passaportes e um carimbo de cada país com aeroporto (sem moedas)"
	complete.pressed.connect(func() -> void: game.dev_passport("complete", ""))
	book.add_child(complete)
	var reset := UiStyle.button("Zerar passaportes e carimbos", false)
	reset.pressed.connect(func() -> void: game.dev_passport("reset", ""))
	book.add_child(reset)
	box.add_child(book)
	return box


func _nature_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Natureza"
	box.add_theme_constant_override("separation", 8)
	box.add_child(UiStyle.label("Forçar a estação (no hemisfério norte; o sul fica com a oposta):", 15, UiStyle.INK_SOFT))
	var seasons := HBoxContainer.new()
	seasons.add_theme_constant_override("separation", 6)
	for pair: Array in [["spring", "Primavera"], ["summer", "Verão"], ["autumn", "Outono"], ["winter", "Inverno"], ["real", "Data real"]]:
		var b := UiStyle.button(pair[1], pair[0] == "real")
		var key: String = pair[0]
		b.pressed.connect(func() -> void: game.dev_force_season(key))
		seasons.add_child(b)
	box.add_child(seasons)
	var animals := HBoxContainer.new()
	animals.add_theme_constant_override("separation", 6)
	_species = OptionButton.new()
	_species.focus_mode = Control.FOCUS_NONE
	_species.add_theme_font_size_override("font_size", 17)
	animals.add_child(_species)
	var spawn := UiStyle.button("Criar perto de mim")
	spawn.pressed.connect(func() -> void:
		if _species.item_count > 0:
			game.dev_spawn_animal(str(_species.get_item_metadata(_species.selected))))
	animals.add_child(spawn)
	var list := UiStyle.button("Listar carregados", false)
	list.pressed.connect(func() -> void: game.dev_list_animals())
	animals.add_child(list)
	box.add_child(animals)
	var pedia := HBoxContainer.new()
	pedia.add_theme_constant_override("separation", 6)
	var complete := UiStyle.button("Completar a Goblopédia", false)
	complete.pressed.connect(func() -> void: game.dev_pedia("complete"))
	pedia.add_child(complete)
	var reset := UiStyle.button("Zerar a Goblopédia", false)
	reset.pressed.connect(func() -> void: game.dev_pedia("reset"))
	pedia.add_child(reset)
	box.add_child(pedia)
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
	_noclip.add_theme_color_override("font_pressed_color", UiStyle.INK)
	_noclip.add_theme_color_override("font_hover_pressed_color", UiStyle.INK)
	_noclip.add_theme_color_override("font_hover_color", UiStyle.INK)
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


## Aba Rede (fase 3): quem está conectado, bots perto de mim e simulação de atraso e perda.
var _online: Label
var _latency: Label
var _loss: Label


func _net_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Rede"
	box.add_theme_constant_override("separation", 8)
	var bots := HBoxContainer.new()
	bots.add_theme_constant_override("separation", 6)
	for n: int in [1, 5, 20]:
		var b := UiStyle.button("Criar %d bot%s perto" % [n, "s" if n > 1 else ""], n == 5)
		b.pressed.connect(func() -> void: game.dev_bots(n))
		bots.add_child(b)
	var rm := UiStyle.button("Tirar os bots", false)
	rm.pressed.connect(func() -> void: game.dev_bots(0))
	bots.add_child(rm)
	box.add_child(bots)
	box.add_child(UiStyle.label("Simular rede ruim (só neste computador):", 15, UiStyle.INK_SOFT))
	_latency = UiStyle.label("Atraso: 0 ms", 16)
	box.add_child(_latency)
	var lat := HSlider.new()
	lat.min_value = 0
	lat.max_value = 300
	lat.step = 10
	lat.focus_mode = Control.FOCUS_NONE
	lat.value_changed.connect(func(v: float) -> void:
		_latency.text = "Atraso: %d ms" % int(v)
		game.set_net_sim(int(v), -1.0))
	box.add_child(lat)
	_loss = UiStyle.label("Perda de pacotes de movimento: 0%", 16)
	box.add_child(_loss)
	var loss := HSlider.new()
	loss.min_value = 0
	loss.max_value = 10
	loss.step = 1
	loss.focus_mode = Control.FOCUS_NONE
	loss.value_changed.connect(func(v: float) -> void:
		_loss.text = "Perda de pacotes de movimento: %d%%" % int(v)
		game.set_net_sim(-1, v / 100.0))
	box.add_child(loss)
	var refresh := UiStyle.button("Atualizar quem está conectado", false)
	refresh.pressed.connect(func() -> void: game.dev_online())
	box.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 140)
	box.add_child(scroll)
	_online = UiStyle.label("", 15)
	_online.autowrap_mode = TextServer.AUTOWRAP_WORD
	_online.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_online)
	return box


## Lista de conectados (vem de GameMain.dev_online).
func show_online(text: String) -> void:
	_online.text = text
