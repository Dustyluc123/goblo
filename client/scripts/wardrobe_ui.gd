class_name WardrobeUi
extends PanelContainer
## Guarda-roupa (tecla C, fase 4.0): um espaço por parte do corpo (cabeça, corpo, pernas, pés,
## costas). Vestir troca pela peça que estava no espaço (ela volta ao bolso). A tinta (feita
## de flores na bancada) pinta a peça vestida. A prévia mostra o personagem parado, de
## frente, com a peça escolhida antes de vestir (fase 4.1): arrastar ou A/D gira, a roda
## aproxima, e os botões viram de costas (bom para a capa) e de frente.

const SLOT_NAMES := {"head": "Cabeça", "body": "Corpo", "legs": "Pernas", "feet": "Pés", "back": "Costas"}

var game: GameMain
var session: Session
var _preview: LookPreview
var _slots: VBoxContainer
var _bag: VBoxContainer
var _info: Label
var _try := ""
## Escolha da capa (fase 4.5): bandeiras na ordem em que aparecem (null = sem edição aberta).
var _cape_edit: Variant = null
var _cape_box: VBoxContainer
var _bag_title: Label
var _bag_scroll: ScrollContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(24))
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Guarda-roupa", 26), "C ou Esc", func() -> void: visible = false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	_preview = LookPreview.new()
	left.add_child(_preview)
	var turn := HBoxContainer.new()
	turn.add_theme_constant_override("separation", 6)
	turn.alignment = BoxContainer.ALIGNMENT_CENTER
	var back := UiStyle.button("Ver de costas", false)
	back.pressed.connect(func() -> void: _preview.show_back())
	var front := UiStyle.button("De frente", false)
	front.pressed.connect(func() -> void: _preview.show_front())
	turn.add_child(back)
	turn.add_child(front)
	left.add_child(turn)
	left.add_child(UiStyle.label("Arraste ou A/D para girar · roda para aproximar", 13, UiStyle.INK_SOFT))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(430, 0)
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	right.add_child(UiStyle.label("Vestido", 20))
	_slots = VBoxContainer.new()
	right.add_child(_slots)
	_bag_title = UiStyle.label("No bolso (passe o mouse para ver, clique para vestir)", 18)
	right.add_child(_bag_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 170)
	_bag = VBoxContainer.new()
	_bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bag)
	right.add_child(scroll)
	_bag_scroll = scroll
	_cape_box = VBoxContainer.new()
	_cape_box.add_theme_constant_override("separation", 6)
	_cape_box.visible = false
	right.add_child(_cape_box)
	_info = UiStyle.label("", 15, UiStyle.INK_SOFT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(430, 0)
	right.add_child(_info)
	visible = false


func setup(g: GameMain, s: Session) -> void:
	game = g
	session = s
	session.inventory_changed.connect(func() -> void:
		if visible:
			refresh())


func toggle() -> void:
	visible = not visible
	if visible:
		_try = ""
		_cape_edit = null
		_preview.reset_view()
		refresh()


func _view() -> Dictionary:
	var v: Dictionary = game._player.look_view.duplicate(true)
	if v.is_empty():
		return v
	if _cape_edit != null:
		v["cape"] = (_cape_edit as Array).duplicate()
	if not _try.is_empty():
		var w: Dictionary = session.items.get(_try, {}).get("wear", {})
		var wear: Dictionary = v.get("wear", {}) if v.get("wear") is Dictionary else {}
		wear[str(w.get("slot", ""))] = {"item": _try, "color": str(w.get("color", "#ffffff"))}
		v["wear"] = wear
	return v


func refresh() -> void:
	if session == null or game == null:
		return
	var v := _view()
	if not v.is_empty():
		_preview.show_look(v)
	for c in _slots.get_children():
		c.queue_free()
	for c in _bag.get_children():
		c.queue_free()
	var worn: Dictionary = game._player.look_view.get("wear", {}) if game._player.look_view.get("wear") is Dictionary else {}
	var paints: Array = []
	for s: Dictionary in session.inventory:
		if (session.items.get(s["item"], {}).get("tags", []) as Array).has("paint"):
			paints.append(s["item"])
	for slot: String in SLOT_NAMES:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var w: Dictionary = worn.get(slot, {})
		var text := "%s: %s" % [tr(SLOT_NAMES[slot]), session.item_name(str(w["item"])) if not w.is_empty() else tr("nada")]
		var l := UiStyle.label(text, 16)
		l.custom_minimum_size = Vector2(190, 0)
		line.add_child(l)
		if not w.is_empty():
			var off := UiStyle.button("Tirar", false)
			off.pressed.connect(func() -> void: game.unwear(slot))
			line.add_child(off)
			if str(w["item"]) == "flag_cape":
				var pick := UiStyle.button("Bandeiras", false)
				pick.tooltip_text = tr("Escolher quais bandeiras aparecem na capa e em que ordem")
				pick.pressed.connect(open_cape)
				line.add_child(pick)
			# Tintas do bolso: bolinhas de cor (passe o mouse para ver o nome).
			for p: String in paints:
				var pb := Button.new()
				pb.custom_minimum_size = Vector2(28, 28)
				pb.focus_mode = Control.FOCUS_NONE
				pb.tooltip_text = tr("Pintar com %s") % session.item_name(p)
				var st := StyleBoxFlat.new()
				st.bg_color = Color(str(session.items[p].get("color", "#ffffff")))
				st.set_corner_radius_all(14)
				st.set_border_width_all(1)
				st.border_color = Color(0.36, 0.27, 0.21, 0.4)
				for state in ["normal", "hover", "pressed"]:
					pb.add_theme_stylebox_override(state, st)
				pb.pressed.connect(func() -> void: game.dye(slot, p))
				line.add_child(pb)
		_slots.add_child(line)
	_bag_title.visible = _cape_edit == null
	_bag_scroll.visible = _cape_edit == null
	_cape_box.visible = _cape_edit != null
	if _cape_edit != null:
		_build_cape()
	var any := false
	for s: Dictionary in session.inventory:
		var it: Dictionary = session.items.get(s["item"], {})
		if not it.get("wear") is Dictionary:
			continue
		any = true
		var wi: Dictionary = it["wear"]
		var b := UiStyle.button("%s  ·  %s  ·  %s" % [session.item_name(s["item"]), tr(SLOT_NAMES.get(str(wi["slot"]), "")), _protection(wi)], false)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var id := str(s["item"])
		b.mouse_entered.connect(func() -> void:
			_try = id
			_preview.show_look(_view()))
		b.pressed.connect(func() -> void:
			_try = ""
			game.wear(id))
		_bag.add_child(b)
	if not any:
		_bag.add_child(UiStyle.label("Nenhuma roupa no bolso. Fabrique na bancada ou compre na loja da praça.", 15, UiStyle.INK_SOFT))
	var body := game.body.body
	_info.text = tr("Proteção: frio %d °C, calor %d °C · confortável de %d a %d °C") % [int(body.get("cold_protection", 0)),
		int(body.get("heat_protection", 0)), int(body.get("comfort_min", 12)), int(body.get("comfort_max", 26))]


## Abre a escolha das bandeiras (com a capa vestida).
func open_cape() -> void:
	_cape_edit = (game._player.look_view.get("cape", []) as Array).duplicate()
	_preview.show_back()
	refresh()


## Editor da capa: as escolhidas (subir, descer, tirar) e os outros carimbos (clique põe).
## A prévia mostra a capa como vai ficar; "Salvar capa" manda para o servidor.
func _build_cape() -> void:
	for c in _cape_box.get_children():
		c.queue_free()
	var lv: Dictionary = game._player.look_view
	var stamped: Array = lv.get("stamped", []) if lv.get("stamped") is Array else []
	var max_flags := int(session.body.get("cape_flags", 12))
	var chosen: Array = _cape_edit
	_cape_box.add_child(UiStyle.label(tr("Capa: %d de %d bandeiras (a primeira fica no alto, à esquerda)") % [chosen.size(), max_flags], 17))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_cape_box.add_child(scroll)
	for i in chosen.size():
		var code := str(chosen[i])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		line.add_child(_flag_icon(code))
		var l := UiStyle.label("%d. %s" % [i + 1, _country(code)], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		for spec: Array in [["↑", -1], ["↓", 1], ["✕", 0]]:
			var b := UiStyle.button(str(spec[0]), false)
			var d: int = spec[1]
			b.disabled = (d == -1 and i == 0) or (d == 1 and i == chosen.size() - 1)
			b.pressed.connect(func() -> void:
				if d == 0:
					chosen.remove_at(i)
				else:
					var tmp: Variant = chosen[i]
					chosen[i] = chosen[i + d]
					chosen[i + d] = tmp
				refresh())
			line.add_child(b)
		list.add_child(line)
	var others := HFlowContainer.new()
	others.add_theme_constant_override("h_separation", 4)
	others.add_theme_constant_override("v_separation", 4)
	for code: String in stamped:
		if chosen.has(code):
			continue
		var b := UiStyle.button(code, false)
		b.tooltip_text = _country(code)
		b.icon = _flag_texture(code)
		b.add_theme_constant_override("icon_max_width", 24)
		b.add_theme_font_size_override("font_size", 13)
		b.disabled = chosen.size() >= max_flags
		b.pressed.connect(func() -> void:
			chosen.append(code)
			refresh())
		others.add_child(b)
	if others.get_child_count() > 0:
		_cape_box.add_child(UiStyle.label("Outros carimbos (clique para pôr)", 15, UiStyle.INK_SOFT))
		var os := ScrollContainer.new()
		os.custom_minimum_size = Vector2(430, 110)
		os.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		others.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		os.add_child(others)
		_cape_box.add_child(os)
	elif stamped.is_empty():
		_cape_box.add_child(UiStyle.label("Ganhe carimbos no passaporte (P) para pôr bandeiras na capa.", 15, UiStyle.INK_SOFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var save := UiStyle.button("Salvar capa", true)
	save.pressed.connect(func() -> void:
		var list_to_send: Array = chosen.duplicate()
		_cape_edit = null
		await game.set_cape(list_to_send))
	var auto := UiStyle.button("Automático", false)
	auto.tooltip_text = tr("Os últimos carimbos, na ordem das viagens")
	auto.pressed.connect(func() -> void:
		_cape_edit = null
		await game.set_cape([]))
	var cancel := UiStyle.button("Voltar", false)
	cancel.pressed.connect(func() -> void:
		_cape_edit = null
		refresh())
	row.add_child(save)
	row.add_child(auto)
	row.add_child(cancel)
	_cape_box.add_child(row)


func _country(code: String) -> String:
	for st: Variant in session.passport_book.get("stamps", []):
		if st is Dictionary and str(st.get("country", "")) == code:
			return "%s (%s)" % [str(st.get("name", code)), code]
	return code


func _flag_texture(code: String) -> Texture2D:
	var at := AtlasTexture.new()
	at.atlas = FlagAtlas.texture()
	var r := FlagAtlas.uv_rect(code)
	var size := Vector2(at.atlas.get_width(), at.atlas.get_height())
	at.region = Rect2(r.position * size, r.size * size)
	return at


func _flag_icon(code: String) -> Control:
	var t := TextureRect.new()
	t.texture = _flag_texture(code)
	t.custom_minimum_size = Vector2(32, 24)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t


func _protection(w: Dictionary) -> String:
	var parts: PackedStringArray = []
	if float(w.get("cold", 0)) > 0:
		parts.append(tr("frio −%d °C") % int(w["cold"]))
	if float(w.get("heat", 0)) > 0:
		parts.append(tr("calor +%d °C") % int(w["heat"]))
	return ", ".join(parts) if not parts.is_empty() else tr("enfeite")
