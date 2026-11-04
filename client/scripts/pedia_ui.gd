class_name PediaUi
extends PanelContainer
## Goblopédia (tecla G): álbum com uma página por espécie de animal e por coisa rara (flor
## azul, árvore de outono, árvore com neve). Mostra a primeira foto (deste computador), onde
## foi tirada (país e bioma), quantas vezes já foi fotografada e se já são amigos. O que
## ainda não foi descoberto aparece como silhueta com "???". O progresso vem do servidor
## (GET /pedia); as fotos ficam em user://fotos/.

const COLUMNS := 5
const CARD := Vector2(150, 176)

var game: GameMain
var session: Session
var art: PediaArt
var _grid: GridContainer
var _progress: Label
var _detail_pic: TextureRect
var _detail_title: Label
var _detail_text: Label
var _entries: Array = []
var _selected := ""
## Seção aberta (fase 4.0): animal, flower ou tree.
var _section := "animal"
var _tabs: HBoxContainer
const SECTIONS := {"animal": "Animais", "flower": "Flores", "tree": "Árvores", "cave": "Cavernas", "legend": "Lendas", "photos": "Fotos"}
## Galeria (fase 4.5): foto aberta e o "apagar" que pede confirmação.
var _photo_sel := ""
var _confirm_delete := false
var _photo_buttons: HBoxContainer
const RARITY := {"common": "comum", "uncommon": "incomum", "rare": "rara"}


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26, Color("fff8ec")))
	custom_minimum_size = Vector2(1180, 640)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := UiStyle.label("Goblopédia", 28, Color("8a5a32"))
	box.add_child(UiStyle.header(title, "G ou Esc", func() -> void: visible = false))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	box.add_child(_tabs)
	_progress = UiStyle.label("", 16, UiStyle.INK_SOFT)
	box.add_child(_progress)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	# Página aberta (direita): foto grande e as anotações.
	var page := PanelContainer.new()
	page.custom_minimum_size = Vector2(340, 0)
	page.add_theme_stylebox_override("panel", UiStyle.panel(18, Color("fffdf7"), 14))
	row.add_child(page)
	var pb := VBoxContainer.new()
	pb.add_theme_constant_override("separation", 8)
	page.add_child(pb)
	_detail_pic = TextureRect.new()
	_detail_pic.custom_minimum_size = Vector2(300, 220)
	_detail_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pb.add_child(_detail_pic)
	_detail_title = UiStyle.label("", 24, Color("8a5a32"))
	pb.add_child(_detail_title)
	_detail_text = UiStyle.label("Escolha uma página.", 16, UiStyle.INK)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_text.custom_minimum_size = Vector2(300, 0)
	pb.add_child(_detail_text)
	_photo_buttons = HBoxContainer.new()
	_photo_buttons.add_theme_constant_override("separation", 6)
	pb.add_child(_photo_buttons)
	visible = false


func setup(g: GameMain, s: Session, a: PediaArt) -> void:
	game = g
	session = s
	art = a
	art.art_ready.connect(func(_id: String) -> void:
		if visible:
			_fill())


func toggle() -> void:
	if visible:
		visible = false
		return
	visible = true
	_entries = session.pedia_entries()
	_fill()
	var r := await game.api_request("GET", "/pedia")
	if r["ok"]:
		set_entries(r["data"]["entries"])


## Abre uma seção (animal, flower, tree, photos).
func open_section(sec: String) -> void:
	_section = sec
	_selected = ""
	_photo_sel = ""
	_fill()


func set_entries(list: Array) -> void:
	_entries = list
	if visible:
		_fill()


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for c in _tabs.get_children():
		c.queue_free()
	for c in _photo_buttons.get_children():
		c.queue_free()
	for sec: String in SECTIONS:
		var n := PediaPhotos.list(session.photo_account()).size() if sec == "photos" \
			else _entries.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == sec).size()
		var tb := UiStyle.button("%s (%d)" % [tr(SECTIONS[sec]), n], sec == _section)
		tb.pressed.connect(func() -> void:
			_section = sec
			_selected = ""
			_photo_sel = ""
			_confirm_delete = false
			_fill())
		_tabs.add_child(tb)
	if _section == "photos":
		_fill_photos()
		return
	var shown := _entries.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == _section)
	var found := 0
	var friends := 0
	for e: Dictionary in shown:
		var on := bool(e.get("discovered", false))
		found += 1 if on else 0
		friends += 1 if bool(e.get("friend", false)) else 0
		_grid.add_child(_card(e))
	_progress.text = tr("%d de %d páginas descobertas  ·  %d amigos") % [found, shown.size(), friends] if _section == "animal" \
		else tr("%d de %d páginas descobertas") % [found, shown.size()]
	if _selected.is_empty() and not shown.is_empty():
		_selected = str(shown[0]["id"])
	_show(_selected)


## Galeria: todas as fotos desta conta, mais recentes primeiro.
func _fill_photos() -> void:
	var acc := session.photo_account()
	var photos := PediaPhotos.list(acc)
	_progress.text = tr("%d fotos neste computador  ·  clique numa para ver, apagar ou pôr na página") % photos.size()
	if photos.is_empty():
		_detail_pic.texture = null
		_detail_title.text = tr("Nenhuma foto ainda")
		_detail_text.text = tr("Segure a câmera fotográfica (barra rápida) e use o botão direito para fotografar.")
		return
	if _photo_sel.is_empty() or not photos.any(func(p: Dictionary) -> bool: return str(p["id"]) == _photo_sel):
		_photo_sel = str(photos[0]["id"])
	for p: Dictionary in photos:
		_grid.add_child(_photo_card(acc, p))
	for p: Dictionary in photos:
		if str(p["id"]) == _photo_sel:
			_show_photo(acc, p)


func _photo_card(acc: String, p: Dictionary) -> Control:
	var id := str(p["id"])
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var st := UiStyle.slot(id == _photo_sel)
		if state == "hover":
			st.bg_color = Color("fff1c2")
		b.add_theme_stylebox_override(state, st)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6
	box.offset_right = -6
	box.offset_top = 6
	box.offset_bottom = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var pic := TextureRect.new()
	pic.texture = PediaPhotos.thumbnail(acc, id)
	pic.custom_minimum_size = Vector2(130, 110)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var when := Time.get_datetime_dict_from_unix_time(int(p.get("at", 0)) + _tz_bias())
	var l := UiStyle.label("%02d/%02d %02d:%02d" % [when["day"], when["month"], when["hour"], when["minute"]], 14, UiStyle.INK_SOFT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	var entry := str(p.get("entry", ""))
	if not entry.is_empty():
		var star := PediaPhotos.pick_of(acc, entry) == id
		var n := UiStyle.label(("★ " if star else "") + _entry_name(entry), 13, UiStyle.INK)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.clip_text = true
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(n)
	b.pressed.connect(func() -> void:
		_photo_sel = id
		_confirm_delete = false
		_fill())
	return b


func _show_photo(acc: String, p: Dictionary) -> void:
	var id := str(p["id"])
	_detail_pic.texture = PediaPhotos.full(acc, id)
	_detail_pic.self_modulate = Color.WHITE
	var entry := str(p.get("entry", ""))
	_detail_title.text = _entry_name(entry) if not entry.is_empty() else tr("Foto")
	var when := Time.get_datetime_dict_from_unix_time(int(p.get("at", 0)) + _tz_bias())
	var lines: Array = [tr("Tirada em %02d/%02d/%04d às %02d:%02d") % [when["day"], when["month"], when["year"], when["hour"], when["minute"]]]
	var where := str(p.get("country_name", p.get("country", "")))
	var biome := str(p.get("biome", ""))
	if not biome.is_empty():
		var i := Array(WorldData.Biome.keys()).find(biome.to_upper())
		biome = WorldData.BIOME_LABELS.get(i, biome)
	if p.has("cave"):
		biome = tr("caverna")
	var place := PackedStringArray([where, biome].filter(func(x: String) -> bool: return not x.is_empty()))
	if not place.is_empty():
		lines.append(tr("Onde: %s") % "  ·  ".join(place))
	if p.has("lat"):
		lines.append("%.2f°, %.2f°" % [float(p["lat"]), float(p["lon"])])
	if not entry.is_empty():
		lines.append(tr("É a foto da página.") if PediaPhotos.pick_of(acc, entry) == id else tr("Registrou a página, mas outra foto a representa."))
	_detail_text.text = "\n".join(lines)
	if not entry.is_empty() and PediaPhotos.pick_of(acc, entry) != id:
		var use := UiStyle.button("Usar na página", true)
		use.pressed.connect(func() -> void:
			PediaPhotos.set_pick(acc, entry, id)
			_fill())
		_photo_buttons.add_child(use)
	var del := UiStyle.button("Apagar?  Clique de novo" if _confirm_delete else "Apagar", _confirm_delete)
	del.pressed.connect(func() -> void:
		if not _confirm_delete:
			_confirm_delete = true
			_fill()
			return
		_confirm_delete = false
		PediaPhotos.remove(acc, id)
		_photo_sel = ""
		_fill())
	_photo_buttons.add_child(del)


func _entry_name(entry: String) -> String:
	for e: Dictionary in _entries:
		if str(e["id"]) == entry:
			return str(e["name"])
	return entry


## Diferença do fuso do computador (as datas do álbum ficam em UTC).
static func _tz_bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _picture(e: Dictionary, prefer_photo: bool) -> Texture2D:
	var id := str(e["id"])
	if prefer_photo and bool(e.get("discovered", false)):
		var photo := PediaPhotos.entry_thumbnail(session.photo_account(), id)
		if photo:
			return photo
	return art.art(id)


func _card(e: Dictionary) -> Control:
	var on := bool(e.get("discovered", false))
	var b := Button.new()
	b.custom_minimum_size = CARD
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var st := UiStyle.slot(str(e["id"]) == _selected)
		if state == "hover":
			st.bg_color = Color("fff1c2")
		b.add_theme_stylebox_override(state, st)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6
	box.offset_right = -6
	box.offset_top = 6
	box.offset_bottom = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var pic := TextureRect.new()
	pic.texture = _picture(e, true)
	pic.custom_minimum_size = Vector2(130, 120)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not on:
		pic.self_modulate = Color(0.22, 0.2, 0.28, 0.85)  # silhueta
	box.add_child(pic)
	var name := UiStyle.label(str(e["name"]) if on else "???", 16, UiStyle.INK if on else UiStyle.INK_SOFT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bool(e.get("friend", false)):
		name.text += "  ♥"
	box.add_child(name)
	b.pressed.connect(func() -> void:
		_selected = str(e["id"])
		_fill())
	return b


func _show(id: String) -> void:
	for e: Dictionary in _entries:
		if str(e["id"]) != id:
			continue
		var on := bool(e.get("discovered", false))
		_detail_pic.texture = _picture(e, true)
		_detail_pic.self_modulate = Color.WHITE if on else Color(0.22, 0.2, 0.28, 0.85)
		_detail_title.text = str(e["name"]) if on else "???"
		var lines: Array = []
		if on:
			var when := Time.get_datetime_dict_from_unix_time(int(e["first_at"]))
			var where := str(e.get("country_name", ""))
			var biome := str(e.get("biome", ""))
			if not biome.is_empty():
				var i := Array(WorldData.Biome.keys()).find(biome.to_upper())
				biome = WorldData.BIOME_LABELS.get(i, biome)
			lines.append(tr("Primeira foto: %02d/%02d/%04d") % [when["day"], when["month"], when["year"]])
			if not where.is_empty() or not biome.is_empty():
				lines.append(tr("Onde: %s") % "  ·  ".join(PackedStringArray([where, biome].filter(func(x: String) -> bool: return not x.is_empty()))))
			lines.append(tr("Fotografado %d %s") % [int(e["sightings"]), "vez" if int(e["sightings"]) == 1 else "vezes"])
			if PediaPhotos.entry_thumbnail(session.photo_account(), id) == null:
				lines.append("(a foto ficou em outro computador)")
		else:
			lines.append(_hint(e))
		if str(e["kind"]) == "flower" and not str(e.get("rarity", "")).is_empty():
			lines.append(tr("Raridade: %s") % tr(RARITY.get(str(e["rarity"]), str(e["rarity"]))))
		if str(e["kind"]) == "animal":
			lines.append("Amigos: sim ♥" if bool(e.get("friend", false)) else "Amigos: ainda não (dê uma frutinha)")
		if str(e["kind"]) == "legend":
			lines.append(tr("De: %s") % game.country_name(str(e.get("country", ""))))
			if on:
				lines.append(tr(str(e.get("story", ""))))
		_detail_text.text = "\n".join(lines)
		return


static func _hint(e: Dictionary) -> String:
	match str(e["kind"]):
		"animal":
			return "Ainda não fotografado. Equipe a câmera, botão direito para mirar e clique para fotografar."
		"flower":
			return "Uma flor ainda não fotografada. Cada bioma e cada estação têm as suas: equipe a câmera e enquadre de perto."
		"tree":
			return "Uma árvore numa estação especial do ano. Fique de olho no calendário!"
		"cave":
			return "Algo que só existe dentro das cavernas. Leve a câmera (e uma tocha)."
		"legend":
			return "Uma lenda que aparece de vez em quando no país de origem. Chegue devagar e fotografe de longe: de perto, ela some!"
	return ""
