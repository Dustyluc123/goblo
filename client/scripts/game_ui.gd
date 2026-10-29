class_name GameUi
extends CanvasLayer
## Interface do jogo por cima do HUD: aviso de interação ("E: sacudir"), avisos de itens
## ganhos, barra rápida, barra do modo construção e as janelas (inventário, bancada, modo
## dev, configurações, primeiro acesso). Montada em código.
##
## Também é o gerenciador da interface: `menu_open()` diz se há menu aberto e
## `captures(evento)` diz se um evento pertence à interface. Câmera, personagem, modo
## construção e interação perguntam aqui antes de reagir, então nenhum menu precisa
## tratar isso sozinho.
##
## Também cuida do cursor: durante o jogo ele fica capturado e escondido (mover o mouse
## gira a câmera). Fica livre com qualquer menu aberto, no modo construção (para mirar),
## com Alt segurado e depois de Esc sem menu aberto (um clique na janela captura de novo).

var prompt: Label
var hotbar: Hotbar
var inventory: InventoryUi
var craft: CraftUi
var dev: DevPanel
var first_access: FirstAccess
var settings: SettingsUi
var sell: SellUi
var pedia: PediaUi
var travel: TravelUi
var passport: PassportUi
## Todas as janelas (menus): qualquer uma aberta trava o jogo e solta o cursor. Janela nova
## só precisa entrar aqui (add_window).
var windows: Array[Control] = []
var build_bar: PanelContainer
var _build_items: HBoxContainer
var _build_hint: Label
var _toasts: VBoxContainer
var _icons: ItemIcons
## Chamado pelo X da barra do modo construção.
var on_build_close := Callable()
## Captura do cursor ligada (o jogo liga quando dá para jogar; nunca nas automações, para
## não prender o mouse de quem está usando o computador).
var mouse_capture := false
## Esc sem menu aberto soltou o cursor; um clique na janela captura de novo.
var _released := false


func _ready() -> void:
	layer = 2
	prompt = UiStyle.label("", 20, UiStyle.INK)
	var prompt_card := PanelContainer.new()
	prompt_card.name = "Prompt"
	prompt_card.add_theme_stylebox_override("panel", UiStyle.panel(16, Color(1, 0.98, 0.94, 0.95), 12))
	prompt_card.add_child(prompt)
	prompt_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_card.offset_bottom = -140
	prompt_card.visible = false
	add_child(prompt_card)

	hotbar = Hotbar.new()
	hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hotbar.offset_bottom = -62
	add_child(hotbar)

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toasts.offset_right = -18
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	add_child(_toasts)

	build_bar = PanelContainer.new()
	build_bar.add_theme_stylebox_override("panel", UiStyle.panel(18, Color(1, 0.98, 0.94, 0.95), 12))
	build_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_bar.offset_bottom = -138
	var bb := VBoxContainer.new()
	build_bar.add_child(bb)
	_build_hint = UiStyle.label("", 16, UiStyle.INK)
	_build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var build_head := HBoxContainer.new()
	build_head.add_child(_build_hint)
	build_head.add_child(UiStyle.close_button(func() -> void:
		if on_build_close.is_valid():
			on_build_close.call()))
	bb.add_child(build_head)
	_build_items = HBoxContainer.new()
	_build_items.add_theme_constant_override("separation", 6)
	_build_items.alignment = BoxContainer.ALIGNMENT_CENTER
	bb.add_child(_build_items)
	build_bar.visible = false
	add_child(build_bar)

	inventory = add_window(InventoryUi.new()) as InventoryUi
	craft = add_window(CraftUi.new()) as CraftUi
	dev = add_window(DevPanel.new()) as DevPanel
	settings = add_window(SettingsUi.new()) as SettingsUi
	sell = add_window(SellUi.new()) as SellUi
	pedia = add_window(PediaUi.new()) as PediaUi
	travel = add_window(TravelUi.new()) as TravelUi
	passport = add_window(PassportUi.new()) as PassportUi


## Registra uma janela (menu) e a coloca na tela.
func add_window(w: Control) -> Control:
	add_child(w)
	windows.append(w)
	return w


func setup(game: GameMain, session: Session, icons: ItemIcons, countries: Dictionary) -> void:
	_icons = icons
	hotbar.setup(session, icons)
	inventory.setup(session, icons)
	craft.setup(game, session, icons)
	dev.setup(game, session, icons, countries)
	sell.setup(game, session, icons)
	travel.setup(game, session)
	passport.setup(game, session)


## Mostra a tela de primeiro acesso.
func show_first_access(countries: Dictionary, detected: String, source: String) -> FirstAccess:
	first_access = FirstAccess.new()
	add_child(first_access)
	first_access.setup(countries, detected, source)
	return first_access


func close_first_access() -> void:
	if first_access:
		first_access.queue_free()
		first_access = null


func show_prompt(text: String) -> void:
	var card := prompt.get_parent() as Control
	card.visible = not text.is_empty()
	prompt.text = text


## Aviso pequeno na direita ("+2 Galho"), com o ícone do item. Some sozinho.
func toast(text: String, item := "") -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(14, Color(1, 0.98, 0.94, 0.95), 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	if not item.is_empty() and _icons:
		var ic := TextureRect.new()
		ic.texture = _icons.icon(item)
		ic.custom_minimum_size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
	row.add_child(UiStyle.label(text, 17))
	_toasts.add_child(card)
	card.pivot_offset = Vector2(60, 20)
	card.scale = Vector2(0.6, 0.6)
	var tw := card.create_tween()
	tw.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.2)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)
	while _toasts.get_child_count() > 6:
		_toasts.get_child(0).free()


## Barra do modo construção: os itens colocáveis do inventário.
func show_build_bar(session: Session, current: String, house: bool, on_pick: Callable) -> void:
	build_bar.visible = true
	for c in _build_items.get_children():
		c.queue_free()
	_build_hint.text = "Clique: colocar · R: girar · X: guardar o objeto embaixo do cursor · B ou Esc: sair"
	if house:
		_build_hint.text = "Escolha o lugar da casa · clique: construir · R: girar · Esc: cancelar"
		return
	for s: Dictionary in session.inventory:
		var id: String = s["item"]
		if not session.is_placeable(id):
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s (%d)" % [session.item_name(id), int(s["count"])]
		b.icon = _icons.icon(id)
		b.expand_icon = true
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, UiStyle.slot(id == current))
		b.pressed.connect(func() -> void: on_pick.call(id))
		_build_items.add_child(b)
	if _build_items.get_child_count() == 0:
		_build_hint.text = "Nada para colocar. Fabrique decorações na bancada! · X: guardar · B: sair"


func hide_build_bar() -> void:
	build_bar.visible = false


## Alguma janela (ou a barra do modo construção) está aberta?
func any_open() -> bool:
	return menu_open() or build_bar.visible


## Há um menu aberto (qualquer janela de `windows` ou o primeiro acesso)? Enquanto
## houver, o jogo não recebe teclas de movimento, cliques nem a roda do mouse.
func menu_open() -> bool:
	if first_access != null:
		return true
	for w in windows:
		if w.visible:
			return true
	return false


## Mantido para quem já usava: trava o personagem quando há menu aberto.
func blocking() -> bool:
	return menu_open()


## O mouse está em cima de algum controle da interface (janela, barra, HUD)?
func mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


## O evento pertence à interface e não deve mexer no jogo? Mouse e gestos: sim se há menu
## aberto ou se o mouse está em cima da interface (a roda rola a lista, não dá zoom).
## Teclado: sim se há menu aberto. Com o cursor capturado, o mouse é sempre do jogo.
func captures(event: InputEvent) -> bool:
	if event is InputEventMouse or event is InputEventGesture:
		if menu_open():
			return true
		# Cursor capturado: o mouse é todo da câmera (o cursor escondido não "está" na UI).
		return not mouse_captured() and mouse_over_ui()
	if event is InputEventKey:
		return menu_open()
	return false


## O cursor deveria estar capturado agora?
func wants_capture() -> bool:
	if not mouse_capture or _released or any_open():
		return false
	if Input.is_physical_key_pressed(KEY_ALT) or not get_window().has_focus():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is SpinBox)


## O cursor está capturado (mover o mouse gira a câmera)?
func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Esc sem menu aberto: solta o cursor até o próximo clique na janela.
func release_mouse() -> void:
	if mouse_capture:
		_released = true


func _process(_delta: float) -> void:
	if not mouse_capture:
		return
	var want := Input.MOUSE_MODE_CAPTURED if wants_capture() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _input(event: InputEvent) -> void:
	# Cursor solto por Esc: um clique no jogo (fora da interface) captura de novo, sem
	# fazer mais nada.
	if _released and event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and not any_open() and not mouse_over_ui():
		_released = false
		get_viewport().set_input_as_handled()


func close_windows() -> bool:
	var any := false
	for w in windows:
		any = any or w.visible
		w.visible = false
	return any
