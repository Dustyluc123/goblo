class_name LookEditor
extends PanelContainer
## Editor de personagem (fase 4.0, ADR 0051; partes independentes na 4.1, ADR 0052): rosto
## (a cabeça sem o cabelo), cabelo (o de qualquer uma das 12 cabeças, ou nenhum), penteado
## extra, tom de pele, cor do cabelo, tronco e braços, pernas e acessório. Cada parte muda só
## ela. No primeiro acesso é obrigatório, antes de entrar no jogo (sem fechar; "Começar a
## jogar" salva). Depois, abre no espelho do lote e nas configurações (F6). Salvar manda para
## o servidor e todos veem.

signal saved

const PART_LABELS := {"body": "Tronco e braços", "legs": "Pernas"}
const STYLE_NAMES := {"none": "Nenhum", "bun": "Coque", "ponytail": "Rabo de cavalo", "curls": "Cachos", "spiky": "Espetado"}
const ACC_NAMES := {"none": "Nenhum", "aid-glasses": "Óculos", "aid-sunglasses": "Óculos escuros", "cap-male-c": "Quepe azul"}

var game: GameMain
var session: Session
var look := {}
## Primeiro acesso: não fecha e o botão diz "Começar a jogar".
var first := false
var _preview: LookPreview
var _rows: VBoxContainer
var _title: Label
var _close: Control
var _hint: Label
var _save: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(24))
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UiStyle.label("Seu personagem", 26)
	var head := UiStyle.header(_title, "Esc", func() -> void: visible = false)
	_close = head.get_child(head.get_child_count() - 1)
	_hint = head.get_child(1)
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_preview = LookPreview.new()
	row.add_child(_preview)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 7)
	_rows.custom_minimum_size = Vector2(440, 0)
	row.add_child(_rows)
	_save = UiStyle.button("Salvar", true)
	_save.pressed.connect(func() -> void:
		_save.disabled = true
		var ok := await game.save_look(look)
		_save.disabled = false
		if ok:
			saved.emit()
			first = false
			visible = false)
	box.add_child(_save)
	visible = false
	# No primeiro acesso, nada fecha o editor sem salvar (Esc fecha as janelas: abre de novo).
	visibility_changed.connect(func() -> void:
		if first and not visible:
			(func() -> void:
				if first:
					visible = true).call_deferred())


func setup(g: GameMain, s: Session) -> void:
	game = g
	session = s


func open(first_time := false) -> void:
	first = first_time
	_title.text = tr("Monte o seu personagem") if first else tr("Seu personagem")
	_close.visible = not first
	_hint.visible = not first
	_save.text = tr("Começar a jogar") if first else tr("Salvar")
	var lv: Dictionary = game._player.look_view
	look = (lv.get("look", {}) as Dictionary).duplicate() if lv.get("look") is Dictionary else {}
	if look.is_empty():
		var part := game._player.character.trim_prefix("character-")
		look = {"head": part, "body": part, "legs": part, "skin": "", "hair": "", "hairstyle": "none", "accessory": "none"}
	if not look.has("haircut"):
		look["haircut"] = ""
	_build()
	visible = true


## Primeiro acesso: mostra o editor e espera salvar.
func run_first() -> void:
	open(true)
	await saved


func _opts() -> Dictionary:
	return session.body.get("look", {})


func _build() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var o := _opts()
	var parts: Array = o.get("parts", [])
	_rows.add_child(_stepper(tr("Rosto"), "head", parts, func(v: String) -> String: return tr("Rosto %d") % (parts.find(v) + 1)))
	_rows.add_child(_stepper(tr("Cabelo"), "haircut", o.get("haircuts", [""]), func(v: String) -> String:
		match v:
			"":
				return tr("O do rosto")
			"none":
				return tr("Sem cabelo")
		return CharacterLook.haircut_name(v)))
	_rows.add_child(_swatches(tr("Cor do cabelo"), "hair", o.get("hair_colors", [])))
	_rows.add_child(_stepper(tr("Penteado extra"), "hairstyle", o.get("hairstyles", ["none"]), func(v: String) -> String: return tr(STYLE_NAMES.get(v, v))))
	_rows.add_child(_swatches(tr("Tom de pele"), "skin", o.get("skins", [])))
	for k: String in PART_LABELS:
		_rows.add_child(_stepper(tr(PART_LABELS[k]), k, parts, func(v: String) -> String: return Player.character_label("character-" + v)))
	_rows.add_child(_stepper(tr("Acessório"), "accessory", o.get("accessories", ["none"]), func(v: String) -> String: return tr(ACC_NAMES.get(v, v))))
	_show()


func _show() -> void:
	var lv: Dictionary = game._player.look_view.duplicate(true)
	lv["look"] = look
	if not lv.has("wear"):
		lv["wear"] = {}
	_preview.show_look(lv)


## Linha "‹ valor ›" que passa pelas opções.
func _stepper(title: String, key: String, options: Array, name_of: Callable) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var l := UiStyle.label(title, 17)
	l.custom_minimum_size = Vector2(150, 0)
	line.add_child(l)
	var value := UiStyle.label(name_of.call(str(look.get(key, options[0] if not options.is_empty() else ""))), 17, UiStyle.INK)
	value.custom_minimum_size = Vector2(170, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for dir in [-1, 1]:
		var b := UiStyle.button("‹" if dir < 0 else "›", false)
		b.pressed.connect(func() -> void:
			if options.is_empty():
				return
			var i := options.find(str(look.get(key, "")))
			if key == "head":
				_pin_haircut()
			i = posmod(i + dir, options.size())
			look[key] = str(options[i])
			value.text = name_of.call(look[key])
			_show())
		if dir < 0:
			line.add_child(b)
			line.add_child(value)
		else:
			line.add_child(b)
	return line


## Antes de trocar o rosto: o cabelo "o do rosto" vira o cabelo daquele rosto, para trocar o
## rosto não mudar o cabelo (partes independentes). O quepe vira acessório.
func _pin_haircut() -> void:
	if str(look.get("haircut", "")) != "":
		return
	var head := str(look.get("head", ""))
	var cuts: Array = _opts().get("haircuts", [])
	if cuts.has(head):
		look["haircut"] = head
	else:
		look["haircut"] = "none"
		if CharacterLook.is_cap_head(head) and str(look.get("accessory", "none")) == "none" and (_opts().get("accessories", []) as Array).has("cap-" + head):
			look["accessory"] = "cap-" + head
	_build.call_deferred()


## Linha de bolinhas de cor ("" = a cor original do personagem).
func _swatches(title: String, key: String, colors: Array) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	var l := UiStyle.label(title, 17)
	l.custom_minimum_size = Vector2(150, 0)
	line.add_child(l)
	for c: String in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = tr("Original") if c.is_empty() else c
		var st := StyleBoxFlat.new()
		st.bg_color = Color(c) if not c.is_empty() else Color("fffaf0")
		st.set_corner_radius_all(15)
		st.set_border_width_all(3 if str(look.get(key, "")) == c else 1)
		st.border_color = UiStyle.INK if str(look.get(key, "")) == c else Color(0.36, 0.27, 0.21, 0.3)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, st)
		if c.is_empty():
			b.text = "–"
		b.pressed.connect(func() -> void:
			look[key] = c
			_build())
		line.add_child(b)
	return line
