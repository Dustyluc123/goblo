class_name GameUi
extends CanvasLayer
## Interface do jogo por cima do HUD: aviso de interação ("E: sacudir"), avisos de itens
## ganhos, barra rápida, barra do modo construção e as janelas (inventário, bancada, modo
## dev, primeiro acesso). Montada em código.

var prompt: Label
var hotbar: Hotbar
var inventory: InventoryUi
var craft: CraftUi
var dev: DevPanel
var first_access: FirstAccess
var build_bar: PanelContainer
var _build_items: HBoxContainer
var _build_hint: Label
var _toasts: VBoxContainer
var _icons: ItemIcons


func _ready() -> void:
	layer = 2
	prompt = UiStyle.label("", 18, UiStyle.INK)
	var prompt_card := PanelContainer.new()
	prompt_card.name = "Prompt"
	prompt_card.add_theme_stylebox_override("panel", UiStyle.panel(16, Color(1, 0.98, 0.94, 0.95), 12))
	prompt_card.add_child(prompt)
	prompt_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_card.offset_bottom = -124
	prompt_card.visible = false
	add_child(prompt_card)

	hotbar = Hotbar.new()
	hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hotbar.offset_bottom = -52
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
	build_bar.offset_bottom = -120
	var bb := VBoxContainer.new()
	build_bar.add_child(bb)
	_build_hint = UiStyle.label("", 14, UiStyle.INK)
	_build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bb.add_child(_build_hint)
	_build_items = HBoxContainer.new()
	_build_items.add_theme_constant_override("separation", 6)
	_build_items.alignment = BoxContainer.ALIGNMENT_CENTER
	bb.add_child(_build_items)
	build_bar.visible = false
	add_child(build_bar)

	inventory = InventoryUi.new()
	add_child(inventory)
	craft = CraftUi.new()
	add_child(craft)
	dev = DevPanel.new()
	add_child(dev)


func setup(game: GameMain, session: Session, icons: ItemIcons, countries: Dictionary) -> void:
	_icons = icons
	hotbar.setup(session, icons)
	inventory.setup(session, icons)
	craft.setup(game, session, icons)
	dev.setup(game, session, icons, countries)


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
		ic.custom_minimum_size = Vector2(32, 32)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
	row.add_child(UiStyle.label(text, 16))
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
		b.custom_minimum_size = Vector2(56, 56)
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


## Alguma janela que deve travar o personagem está aberta?
func blocking() -> bool:
	return inventory.visible or craft.visible or first_access != null


func close_windows() -> bool:
	var any := inventory.visible or craft.visible or dev.visible
	inventory.visible = false
	craft.visible = false
	dev.visible = false
	return any
