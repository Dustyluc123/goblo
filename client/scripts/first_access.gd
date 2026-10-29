class_name FirstAccess
extends Control
## Tela de primeiro acesso: o jogador escolhe um apelido e confirma (ou troca) o país.
## O país sugerido vem do servidor (pelo IP; rodando local, pelo idioma do sistema).

signal submitted(nickname: String, country: String)

var _nick: LineEdit
var _search: LineEdit
var _list: ItemList
var _detected: Label
var _error: Label
var _button: Button
var _countries: Array = []  # [código, nome] em ordem alfabética
var _selected := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.2, 0.25, 0.35, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(28, UiStyle.CREAM, 26))
	card.custom_minimum_size = Vector2(460, 0)
	add_child(card)
	UiStyle.center(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(UiStyle.label("Bem-vindo ao Goblo!", 28))
	box.add_child(UiStyle.label("Escolha um apelido e o país onde você vai morar.", 15, UiStyle.INK_SOFT))
	box.add_child(UiStyle.label("Apelido", 15))
	_nick = UiStyle.line_edit("de 3 a 16 letras")
	_nick.max_length = 16
	_nick.text_submitted.connect(func(_t: String) -> void: _submit())
	box.add_child(_nick)
	box.add_child(UiStyle.label("País", 15))
	_detected = UiStyle.label("", 14, UiStyle.INK_SOFT)
	_detected.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_detected)
	_search = UiStyle.line_edit("procurar país…")
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	box.add_child(_search)
	_list = UiStyle.item_list()
	_list.custom_minimum_size = Vector2(0, 200)
	_list.item_selected.connect(func(i: int) -> void: _selected = str(_list.get_item_metadata(i)))
	box.add_child(_list)
	_error = UiStyle.label("", 14, UiStyle.WARN)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_error)
	_button = UiStyle.button("Começar")
	_button.pressed.connect(_submit)
	box.add_child(_button)


func setup(countries: Dictionary, detected: String, source: String) -> void:
	_countries.clear()
	for code: String in countries:
		_countries.append([code, str(countries[code])])
	_countries.sort_custom(func(a: Array, b: Array) -> bool: return str(a[1]).naturalnocasecmp_to(b[1]) < 0)
	_selected = detected
	match source:
		"ip":
			_detected.text = "Achamos que você está em %s (pela sua conexão). Confirme ou escolha outro." % countries.get(detected, detected)
		"locale":
			_detected.text = "Pelo idioma do seu computador, sugerimos %s. Confirme ou escolha outro." % countries.get(detected, detected)
		_:
			_detected.text = "Não conseguimos descobrir seu país. Escolha na lista."
	_fill()
	_nick.grab_focus.call_deferred()


func _fill() -> void:
	_list.clear()
	var q := _search.text.strip_edges().to_lower()
	for c: Array in _countries:
		if q.is_empty() or str(c[1]).to_lower().contains(q) or str(c[0]).to_lower().contains(q):
			var i := _list.add_item(str(c[1]))
			_list.set_item_metadata(i, c[0])
			if c[0] == _selected:
				_list.select(i)
				_list.ensure_current_is_visible()


func show_error(text: String) -> void:
	_error.text = text
	_button.disabled = false


func _submit() -> void:
	if _selected.is_empty():
		show_error("Escolha um país na lista.")
		return
	_error.text = ""
	_button.disabled = true
	submitted.emit(_nick.text, _selected)
