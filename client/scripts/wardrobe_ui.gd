class_name WardrobeUi
extends PanelContainer
## Guarda-roupa (tecla C, fase 4.0): um espaço por parte do corpo (cabeça, corpo, pernas, pés,
## costas). Vestir troca pela peça que estava no espaço (ela volta ao bolso). A tinta (feita
## de flores na bancada) pinta a peça vestida. A prévia mostra o personagem girando com a
## peça escolhida antes de vestir.

const SLOT_NAMES := {"head": "Cabeça", "body": "Corpo", "legs": "Pernas", "feet": "Pés", "back": "Costas"}

var game: GameMain
var session: Session
var _preview: LookPreview
var _slots: VBoxContainer
var _bag: VBoxContainer
var _info: Label
var _try := ""


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
	_preview = LookPreview.new()
	row.add_child(_preview)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(430, 0)
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	right.add_child(UiStyle.label("Vestido", 20))
	_slots = VBoxContainer.new()
	right.add_child(_slots)
	right.add_child(UiStyle.label("No bolso (passe o mouse para ver, clique para vestir)", 18))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 170)
	_bag = VBoxContainer.new()
	_bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_bag)
	right.add_child(scroll)
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
		refresh()


func _view() -> Dictionary:
	var v: Dictionary = game._player.look_view.duplicate(true)
	if v.is_empty():
		return v
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
			for p: String in paints:
				var pb := UiStyle.button(session.item_name(p), false)
				pb.tooltip_text = tr("Pintar esta peça")
				pb.add_theme_color_override("font_color", Color(str(session.items[p].get("color", "#ffffff"))).darkened(0.2))
				pb.pressed.connect(func() -> void: game.dye(slot, p))
				line.add_child(pb)
		_slots.add_child(line)
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


func _protection(w: Dictionary) -> String:
	var parts: PackedStringArray = []
	if float(w.get("cold", 0)) > 0:
		parts.append(tr("frio −%d °C") % int(w["cold"]))
	if float(w.get("heat", 0)) > 0:
		parts.append(tr("calor +%d °C") % int(w["heat"]))
	return ", ".join(parts) if not parts.is_empty() else tr("enfeite")
