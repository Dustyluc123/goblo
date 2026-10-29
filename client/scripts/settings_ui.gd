class_name SettingsUi
extends PanelContainer
## Configurações (F6): qualidade gráfica, tamanho da interface, mouse (sensibilidade e eixo
## vertical invertido) e tela cheia. Tudo fica salvo em user://settings.cfg.

const SENSITIVITIES := [0.5, 0.75, 1.0, 1.5, 2.0]

var _quality_row: HBoxContainer
var _scale_row: HBoxContainer
var _mouse_row: HBoxContainer
var _invert: Button
var _info: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26))
	custom_minimum_size = Vector2(560, 0)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Configurações", 26), "F6 ou Esc", func() -> void: visible = false))
	box.add_child(UiStyle.label("Qualidade gráfica", 18))
	_quality_row = HBoxContainer.new()
	_quality_row.add_theme_constant_override("separation", 8)
	box.add_child(_quality_row)
	box.add_child(UiStyle.label("Tamanho da interface", 18))
	_scale_row = HBoxContainer.new()
	_scale_row.add_theme_constant_override("separation", 8)
	box.add_child(_scale_row)
	box.add_child(UiStyle.label("Sensibilidade do mouse", 18))
	_mouse_row = HBoxContainer.new()
	_mouse_row.add_theme_constant_override("separation", 8)
	box.add_child(_mouse_row)
	_invert = UiStyle.button("", false)
	_invert.pressed.connect(func() -> void:
		MouseSettings.set_invert_y(not MouseSettings.invert_y())
		refresh())
	box.add_child(_invert)
	var full := UiStyle.button("Tela cheia (F11)", false)
	full.pressed.connect(toggle_fullscreen)
	box.add_child(full)
	_info = UiStyle.label("", 15, UiStyle.INK_SOFT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_info)
	visible = false
	Quality.emitter.changed.connect(refresh)
	Quality.emitter.ui_changed.connect(refresh)


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	for c in _quality_row.get_children():
		c.queue_free()
	for c in _scale_row.get_children():
		c.queue_free()
	for c in _mouse_row.get_children():
		c.queue_free()
	for v: float in SENSITIVITIES:
		var b := UiStyle.button("%d%%" % roundi(v * 100.0), is_equal_approx(v, MouseSettings.sensitivity()))
		b.custom_minimum_size = Vector2(90, 0)
		b.pressed.connect(func() -> void:
			MouseSettings.set_sensitivity(v)
			refresh())
		_mouse_row.add_child(b)
	_invert.text = "Inverter eixo vertical: %s" % ("sim" if MouseSettings.invert_y() else "não")
	for q: String in Quality.NAMES:
		var b := UiStyle.button(str(Quality.LABELS[q]).capitalize(), q == Quality.current_name())
		b.custom_minimum_size = Vector2(150, 0)
		b.pressed.connect(func() -> void: Quality.set_quality(q))
		_quality_row.add_child(b)
	for v: float in Quality.UI_SCALES:
		var b := UiStyle.button("%d%%" % roundi(v * 100.0), is_equal_approx(v, Quality.ui_scale()))
		b.custom_minimum_size = Vector2(110, 0)
		b.pressed.connect(func() -> void: Quality.set_ui_scale(v))
		_scale_row.add_child(b)
	var win := DisplayServer.window_get_size()
	var vp := get_viewport()
	var s := vp.scaling_3d_scale
	_info.text = "Janela %d × %d · 3D em %d × %d (%d%%%s) · a interface fica sempre na resolução cheia." % [
		win.x, win.y, int(win.x * s), int(win.y * s), roundi(s * 100.0), ", FSR" if vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR else ""]


static func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
