class_name UiStyle
extends RefCounted
## Estilo dos menus, no espírito dos menus do Animal Crossing: cartões creme com cantos bem
## redondos, texto marrom suave, botões fofinhos. Tudo montado em código.

const CREAM := Color("fffaf0")
const CREAM_DARK := Color("f3e9d6")
const INK := Color("5b4636")
const INK_SOFT := Color("8c7663")
const ACCENT := Color("7cc49a")
const ACCENT_DARK := Color("4f9a70")
const WARN := Color("d9705b")
const OK := Color("4f9a70")


static func panel(radius := 22, bg := CREAM, margin := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin - 4
	s.content_margin_bottom = margin - 4
	s.border_color = Color(0.55, 0.42, 0.3, 0.18)
	s.set_border_width_all(2)
	s.shadow_color = Color(0, 0, 0, 0.12)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


static func slot(selected := false, empty := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CREAM_DARK if not empty else Color(0.93, 0.89, 0.81, 0.6)
	if selected:
		s.bg_color = Color("fff1c2")
		s.border_color = Color("e8b93e")
		s.set_border_width_all(3)
	else:
		s.border_color = Color(0.55, 0.42, 0.3, 0.12)
		s.set_border_width_all(2)
	s.set_corner_radius_all(16)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func label(text: String, size := 16, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, primary := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		var base := ACCENT if primary else CREAM_DARK
		match state:
			"hover":
				base = base.lightened(0.12)
			"pressed":
				base = base.darkened(0.1)
			"disabled":
				base = Color(0.85, 0.82, 0.76)
		s.bg_color = base
		s.set_corner_radius_all(14)
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 7
		s.content_margin_bottom = 7
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", Color.WHITE if primary else INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE if primary else INK)
	b.add_theme_color_override("font_pressed_color", Color.WHITE if primary else INK)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.8))
	return b


static func line_edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", 16)
	var s := StyleBoxFlat.new()
	s.bg_color = Color.WHITE
	s.set_corner_radius_all(12)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.border_color = Color(0.55, 0.42, 0.3, 0.25)
	s.set_border_width_all(2)
	e.add_theme_stylebox_override("normal", s)
	var f := s.duplicate() as StyleBoxFlat
	f.border_color = ACCENT
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", INK_SOFT)
	return e


static func item_list() -> ItemList:
	var l := ItemList.new()
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_selected_color", INK)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.7)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 6
	bg.content_margin_right = 6
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	l.add_theme_stylebox_override("panel", bg)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color("fff1c2")
	sel.set_corner_radius_all(8)
	l.add_theme_stylebox_override("selected", sel)
	l.add_theme_stylebox_override("selected_focus", sel)
	return l


## Coloca o controle centralizado na tela.
static func center(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


## Abas no estilo creme (o tema padrão do Godot é escuro).
static func tabs(tc: TabContainer) -> void:
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(1, 1, 1, 0.55)
	panel_bg.set_corner_radius_all(14)
	panel_bg.content_margin_left = 10
	panel_bg.content_margin_right = 10
	panel_bg.content_margin_top = 10
	panel_bg.content_margin_bottom = 10
	tc.add_theme_stylebox_override("panel", panel_bg)
	for state in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var t := StyleBoxFlat.new()
		t.bg_color = Color(1, 1, 1, 0.75) if state == "tab_selected" else CREAM_DARK
		if state == "tab_hovered":
			t.bg_color = Color("fff1c2")
		t.corner_radius_top_left = 12
		t.corner_radius_top_right = 12
		t.content_margin_left = 14
		t.content_margin_right = 14
		t.content_margin_top = 6
		t.content_margin_bottom = 6
		tc.add_theme_stylebox_override(state, t)
	tc.add_theme_color_override("font_selected_color", INK)
	tc.add_theme_color_override("font_unselected_color", INK_SOFT)
	tc.add_theme_color_override("font_hovered_color", INK)
	tc.add_theme_font_size_override("font_size", 15)


## SpinBox clarinho, combinando com os campos de texto.
static func spin_box(sb: SpinBox) -> void:
	var e := sb.get_line_edit()
	var s := StyleBoxFlat.new()
	s.bg_color = Color.WHITE
	s.set_corner_radius_all(10)
	s.content_margin_left = 10
	s.content_margin_right = 6
	s.border_color = Color(0.55, 0.42, 0.3, 0.25)
	s.set_border_width_all(2)
	e.add_theme_stylebox_override("normal", s)
	e.add_theme_stylebox_override("focus", s)
	e.add_theme_color_override("font_color", INK)
