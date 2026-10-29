class_name InventoryUi
extends PanelContainer
## Inventário (Tab ou I): 20 espaços, itens iguais empilham até 99 (ferramentas, 1).
## Clique numa ferramenta para segurar; num objeto colocável para entrar no modo
## construção com ele.

signal place_requested(item: String)

const COLUMNS := 5

var session: Session
var icons: ItemIcons
var _grid: GridContainer
var _title: Label
var _hint: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26))
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UiStyle.label("Bolso", 26)
	box.add_child(UiStyle.header(_title, "Tab ou Esc", func() -> void: visible = false))
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)
	_hint = UiStyle.label("Clique numa ferramenta para segurar, ou num objeto para colocar no lote.", 15, UiStyle.INK_SOFT)
	box.add_child(_hint)
	visible = false


func setup(s: Session, i: ItemIcons) -> void:
	session = s
	icons = i
	session.inventory_changed.connect(refresh)
	session.equipped_changed.connect(refresh)
	icons.icon_ready.connect(func(_id: String) -> void:
		if visible:
			refresh())
	refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	if session == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	var slots: Array = []  # [item, quantidade]
	for s: Dictionary in session.inventory:
		var stack := int(session.items.get(s["item"], {}).get("stack", 99))
		var left := int(s["count"])
		while left > 0:
			slots.append([s["item"], mini(left, stack)])
			left -= stack
	_title.text = "Bolso  ·  %d/%d" % [slots.size(), session.slots_max]
	for i in session.slots_max:
		_grid.add_child(_slot(slots[i] if i < slots.size() else []))


func _slot(entry: Array) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(84, 84)
	b.focus_mode = Control.FOCUS_NONE
	var empty := entry.is_empty()
	var selected: bool = not empty and session.equipped == entry[0]
	for state in ["normal", "hover", "pressed", "disabled"]:
		var st := UiStyle.slot(selected, empty)
		if state == "hover" and not empty:
			st.bg_color = st.bg_color.lightened(0.25)
		b.add_theme_stylebox_override(state, st)
	if empty:
		b.disabled = true
		return b
	var item: String = entry[0]
	b.tooltip_text = session.item_name(item)
	var icon := TextureRect.new()
	icon.texture = icons.icon(item)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	if int(entry[1]) > 1:
		var n := UiStyle.label(str(entry[1]), 16, UiStyle.INK)
		n.add_theme_color_override("font_outline_color", Color.WHITE)
		n.add_theme_constant_override("outline_size", 6)
		n.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		n.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		n.grow_vertical = Control.GROW_DIRECTION_BEGIN
		n.offset_right = -6
		n.offset_bottom = -2
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(n)
	b.pressed.connect(func() -> void: _clicked(item))
	return b


func _clicked(item: String) -> void:
	if session.is_tool(item):
		session.equip("" if session.equipped == item else item)
	elif session.is_placeable(item):
		visible = false
		place_requested.emit(item)
