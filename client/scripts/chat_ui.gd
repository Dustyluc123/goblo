class_name ChatUi
extends VBoxContainer
## Chat (fase 3): as últimas mensagens no canto de baixo à esquerda (somem devagar) e a
## linha para escrever. Enter abre, Enter manda, Esc fecha. Quem está perto (chat.radius do
## servidor) vê o balão em cima da cabeça; palavrões viram coraçõezinhos no servidor.

const KEEP := 8
const SHOW_TIME := 14.0

signal sent(text: String)

var input: LineEdit
var max_chars := 120
var _log: VBoxContainer
var _ages: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 20
	offset_bottom = -150
	custom_minimum_size = Vector2(460, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 2)
	add_child(_log)
	input = UiStyle.line_edit("diga algo… (Enter manda, Esc fecha)")
	input.max_length = max_chars
	input.visible = false
	input.set_meta("keep_focus", true)  # o GameUi não tira o foco dela
	input.text_submitted.connect(_submit)
	input.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled())
	add_child(input)


func is_open() -> bool:
	return input.visible


func open() -> void:
	input.max_length = max_chars
	input.visible = true
	input.text = ""
	input.grab_focus()
	for c in _log.get_children():
		(c as Control).modulate.a = 1.0
	_ages.fill(0.0)


func close() -> void:
	input.visible = false
	input.release_focus()


func _submit(text: String) -> void:
	text = text.strip_edges()
	close()
	if not text.is_empty():
		sent.emit(text)


## Uma linha no histórico: "Apelido: texto" (ou um aviso, sem apelido).
func add_line(nick: String, text: String, own := false) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(460, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 17)
	l.add_theme_font_size_override("bold_font_size", 17)
	l.add_theme_color_override("default_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.1, 0.18, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	var safe := text.replace("[", "[lb]")
	if nick.is_empty():
		l.text = "[i]%s[/i]" % safe
	else:
		l.text = "[b][color=%s]%s[/color][/b]: %s" % ["#ffe08a" if own else "#b8f0d8", nick.replace("[", "[lb]"), safe]
	_log.add_child(l)
	_ages.append(0.0)
	while _log.get_child_count() > KEEP:
		_log.get_child(0).free()
		_ages.pop_front()


func _process(delta: float) -> void:
	for i in _ages.size():
		_ages[i] = float(_ages[i]) + delta
		var c := _log.get_child(i) as Control
		if c and not is_open():
			c.modulate.a = clampf((SHOW_TIME - float(_ages[i])) / 2.0, 0.0, 1.0)
