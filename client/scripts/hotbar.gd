class_name Hotbar
extends HBoxContainer
## Barra rápida: as ferramentas do inventário nas teclas 1 a 5. Apertar a tecla de novo
## guarda a ferramenta (mão vazia).

const SLOTS := 5

var session: Session
var icons: ItemIcons


func setup(s: Session, i: ItemIcons) -> void:
	session = s
	icons = i
	add_theme_constant_override("separation", 8)
	session.inventory_changed.connect(refresh)
	session.equipped_changed.connect(refresh)
	icons.icon_ready.connect(func(_id: String) -> void: refresh())
	refresh()


## Tecla 1–5.
func press(index: int) -> void:
	var tools := session.tools()
	if index >= tools.size():
		session.equip("")
		return
	var id: String = tools[index]
	session.equip("" if session.equipped == id else id)


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	var tools := session.tools()
	for i in SLOTS:
		var id: String = tools[i] if i < tools.size() else ""
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(58, 58)
		p.add_theme_stylebox_override("panel", UiStyle.slot(not id.is_empty() and id == session.equipped, id.is_empty()))
		if not id.is_empty():
			var icon := TextureRect.new()
			icon.texture = icons.icon(id)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(46, 46)
			icon.tooltip_text = session.item_name(id)
			p.add_child(icon)
		var n := UiStyle.label(str(i + 1), 12, UiStyle.INK_SOFT)
		n.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		p.add_child(n)
		add_child(p)
