class_name DialogUi
extends Control
## Caixa de diálogo (fase 3.5, ADR 0043): um sistema só para todos os NPCs. Fica embaixo da
## tela, com o retratinho e o nome do NPC; o texto aparece letra por letra (clique, E ou
## Enter completa a fala ou passa para a próxima) e, quando há, as respostas viram botões
## (ou números 1 a 4). Os diálogos vêm de dialogs.json (servidor), com {name}, {player},
## {country}, {item_of_day}, {currency} e {slang} trocados na hora.
##
## Ações das respostas (open_shop, open_travel, intro_task…) são pedidas ao jogo pelo sinal
## `action`; `finished` avisa quando o diálogo acaba.

signal action(name: String, option: Dictionary)
signal finished

const CHARS_PER_SEC := 45.0

var dialogs := {}
var vars := {}
var speaker_name := ""
var speaker_title := ""
var tint := Color("ffd27f")
var _lines: Array = []
var _index := 0
var _shown := 0.0
var _text := ""
var _panel: PanelContainer
var _name: Label
var _body: Label
var _options: VBoxContainer
var _portrait: Control
var _hint: Label
var _skip: Button
## Botão "Pular apresentação" (só na apresentação do guia).
var on_skip := Callable()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(24, Color(1, 0.98, 0.94, 0.97), 18))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_bottom = -30
	_panel.custom_minimum_size = Vector2(900, 190)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)
	_portrait = Control.new()
	_portrait.custom_minimum_size = Vector2(130, 130)
	_portrait.draw.connect(_draw_portrait)
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	var head := HBoxContainer.new()
	_name = UiStyle.label("", 22, Color("b5566b"))
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name)
	_skip = UiStyle.button("Pular apresentação", false)
	_skip.pressed.connect(func() -> void:
		if on_skip.is_valid():
			on_skip.call())
	head.add_child(_skip)
	col.add_child(head)
	_body = UiStyle.label("", 20)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.custom_minimum_size = Vector2(700, 0)
	col.add_child(_body)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	col.add_child(_options)
	_hint = UiStyle.label("clique ou E para continuar", 14, UiStyle.INK_SOFT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_hint)
	# Clique na caixa (fora dos botões) também avança.
	_panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			advance()
			_panel.accept_event())
	visible = false
	# Fechar por qualquer caminho (Esc, outra janela, GameUi.close_windows) conta como fim.
	visibility_changed.connect(func() -> void:
		if not visible:
			finished.emit())


## Está mostrando uma fala?
func is_open() -> bool:
	return visible


## Começa o diálogo `id` com o NPC (nome, cargo e cor do retrato).
func start(id: String, who: String, who_title: String, color: Color, with_skip := false) -> void:
	if not dialogs.has(id):
		push_warning("Diálogo desconhecido: " + id)
		return
	speaker_name = who
	speaker_title = who_title
	tint = color
	_skip.visible = with_skip
	_lines = dialogs[id]
	_index = 0
	visible = true
	_show_line()


func close() -> void:
	visible = false


func _fill(text: String) -> String:
	var out := text
	var all := vars.duplicate()
	all["name"] = speaker_name
	for k: String in all:
		out = out.replace("{%s}" % k, str(all[k]))
	return out


func _show_line() -> void:
	for c in _options.get_children():
		c.queue_free()
	var line: Dictionary = _lines[_index]
	_name.text = "%s · %s" % [speaker_name, speaker_title] if not speaker_title.is_empty() else speaker_name
	_text = tr(_fill(str(line.get("text", ""))))
	_body.text = _text
	_shown = 0.0
	_body.visible_characters = 0
	_hint.visible = true
	_portrait.queue_redraw()


func _line_done() -> bool:
	return _body.visible_characters < 0 or _body.visible_characters >= _text.length()


func _show_options() -> void:
	var line: Dictionary = _lines[_index]
	var opts: Array = line.get("options", [])
	if opts.is_empty():
		return
	_hint.visible = false
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := UiStyle.button("%d  %s" % [i + 1, _fill(str(o.get("text", "")))], i == 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: choose(i))
		_options.add_child(b)


## Escolhe a resposta i (botão ou número; testes).
func choose(i: int) -> void:
	var opts: Array = (_lines[_index] as Dictionary).get("options", [])
	if i < 0 or i >= opts.size():
		return
	var o: Dictionary = opts[i]
	var act := str(o.get("action", ""))
	var next := str(o.get("next", ""))
	if not next.is_empty():
		_lines = dialogs.get(next, [])
		_index = 0
		if not act.is_empty():
			action.emit(act, o)
		_show_line()
		return
	close()
	if not act.is_empty() and act != "end":
		action.emit(act, o)


## Avança: completa a fala, ou passa para a próxima, ou termina (sem respostas).
func advance() -> void:
	if not visible:
		return
	if not _line_done():
		_body.visible_characters = -1
		_show_options()
		return
	if not (_lines[_index] as Dictionary).get("options", []).is_empty():
		return  # espera a resposta
	_index += 1
	if _index >= _lines.size():
		close()
	else:
		_show_line()


func _process(delta: float) -> void:
	if not visible or _line_done():
		return
	_shown += delta * CHARS_PER_SEC
	_body.visible_characters = int(_shown)
	if _line_done():
		_body.visible_characters = -1
		_show_options()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.is_echo():
		var k := (event as InputEventKey).keycode
		if k == KEY_E or k == KEY_ENTER or k == KEY_SPACE or k == KEY_KP_ENTER:
			advance()
			get_viewport().set_input_as_handled()
		elif k >= KEY_1 and k <= KEY_4 and _line_done():
			choose(k - KEY_1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()


## Retratinho: o rosto do NPC desenhado (círculo na cor do papel, rosto, chapéu).
func _draw_portrait() -> void:
	var c := _portrait.size * 0.5
	var r := minf(c.x, c.y) - 4
	_portrait.draw_circle(c, r, tint)
	_portrait.draw_circle(c, r - 6, Color("fff6e8"))
	var skin := Color("e9b48a")
	_portrait.draw_circle(c + Vector2(0, 12), r * 0.55, skin)
	_portrait.draw_circle(c + Vector2(-r * 0.2, 6), 5, Color("3b2f3f"))
	_portrait.draw_circle(c + Vector2(r * 0.2, 6), 5, Color("3b2f3f"))
	_portrait.draw_arc(c + Vector2(0, 18), r * 0.18, 0.2, PI - 0.2, 10, Color("b5566b"), 3, true)
	_portrait.draw_circle(c + Vector2(-r * 0.32, 18), 6, Color(1, 0.6, 0.6, 0.5))
	_portrait.draw_circle(c + Vector2(r * 0.32, 18), 6, Color(1, 0.6, 0.6, 0.5))
	# Chapéu na cor do papel.
	_portrait.draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.4), Vector2(r * 1.24, r * 0.14)), tint.darkened(0.1))
	_portrait.draw_rect(Rect2(c + Vector2(-r * 0.36, -r * 0.78), Vector2(r * 0.72, r * 0.42)), tint)
