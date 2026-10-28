class_name Hud
extends CanvasLayer
## HUD mínimo: país e coordenadas da célula embaixo do personagem, mensagens de status
## e a lista de controles. Montado em código para ficar fácil de mexer.

const INK := Color("3b3f5c")
const INK_SOFT := Color("6b6f8c")

var _country: Label
var _coords: Label
var _time: Label
var _status_panel: PanelContainer
var _status: Label


func _ready() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.position = Vector2(16, 16)
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	_country = _label(24, INK)
	_coords = _label(15, INK_SOFT)
	_time = _label(15, INK_SOFT)
	box.add_child(_country)
	box.add_child(_coords)
	box.add_child(_time)
	_country.text = "Goblo"
	_coords.text = "carregando o mundo…"

	_status_panel = PanelContainer.new()
	_status_panel.add_theme_stylebox_override("panel", _card_style())
	_status_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_status_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_status_panel)
	_status = _label(18, INK)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_panel.add_child(_status)

	var help := _label(14, Color(1, 1, 1, 0.85))
	help.text = "WASD andar · Shift correr · botão direito arrasta a câmera · Q/E girar · roda do mouse: zoom"
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = 16
	help.offset_bottom = -12
	add_child(help)


## Mensagem rápida no centro da tela, que some sozinha.
func flash(text: String) -> void:
	show_status(text)
	await get_tree().create_timer(1.5).timeout
	if _status.text == text:
		hide_status()


func show_status(text: String) -> void:
	_status.text = text
	_status_panel.visible = true


func hide_status() -> void:
	_status_panel.visible = false


## Horário solar local onde o personagem está.
func show_time(hours: float, speed: float) -> void:
	var h := int(hours)
	var m := int((hours - h) * 60.0)
	var text := "%02d:%02d" % [h, m]
	if speed != 1.0:
		text += "  (×%d)" % int(speed)
	_time.text = text


func show_cell(world: WorldData, id: int) -> void:
	var code := world.country_codes[id]
	var title := world.country_name(id)
	if not code.is_empty():
		title += "  ·  " + code
	_country.text = title
	_coords.text = "%s  ·  %s  ·  célula %d" % [world.biome_label(id), WorldData.format_lat_lon(world.lats[id], world.lons[id]), id]


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 0.99, 0.97, 0.9)
	s.set_corner_radius_all(14)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.15)
	s.shadow_size = 6
	return s
