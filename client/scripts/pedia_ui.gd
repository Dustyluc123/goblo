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


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26, Color("fff8ec")))
	custom_minimum_size = Vector2(1180, 640)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := UiStyle.label("Goblopédia", 28, Color("8a5a32"))
	box.add_child(UiStyle.header(title, "G ou Esc", func() -> void: visible = false))
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


func set_entries(list: Array) -> void:
	_entries = list
	if visible:
		_fill()


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var found := 0
	var friends := 0
	for e: Dictionary in _entries:
		var on := bool(e.get("discovered", false))
		found += 1 if on else 0
		friends += 1 if bool(e.get("friend", false)) else 0
		_grid.add_child(_card(e))
	_progress.text = "%d de %d páginas descobertas  ·  %d amigos" % [found, _entries.size(), friends]
	if _selected.is_empty() and not _entries.is_empty():
		_selected = str(_entries[0]["id"])
	_show(_selected)


func _picture(e: Dictionary, prefer_photo: bool) -> Texture2D:
	var id := str(e["id"])
	if prefer_photo and bool(e.get("discovered", false)):
		var photo := PediaPhotos.first_thumbnail(session.profile, id)
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
			lines.append("Primeira foto: %02d/%02d/%04d" % [when["day"], when["month"], when["year"]])
			if not where.is_empty() or not biome.is_empty():
				lines.append("Onde: %s" % "  ·  ".join(PackedStringArray([where, biome].filter(func(x: String) -> bool: return not x.is_empty()))))
			lines.append("Fotografado %d %s" % [int(e["sightings"]), "vez" if int(e["sightings"]) == 1 else "vezes"])
			if PediaPhotos.first_thumbnail(session.profile, id) == null:
				lines.append("(a foto ficou em outro computador)")
		else:
			lines.append(_hint(e))
		if str(e["kind"]) == "animal":
			lines.append("Amigos: sim ♥" if bool(e.get("friend", false)) else "Amigos: ainda não (dê uma frutinha)")
		_detail_text.text = "\n".join(lines)
		return


static func _hint(e: Dictionary) -> String:
	match str(e["kind"]):
		"animal":
			return "Ainda não fotografado. Equipe a câmera, botão direito para mirar e clique para fotografar."
		"flower":
			return "Uma flor de cor rara, que aparece pouco por aí."
		"tree":
			return "Uma árvore numa estação especial do ano. Fique de olho no calendário!"
	return ""
