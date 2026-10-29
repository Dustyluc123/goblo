class_name Hud
extends CanvasLayer
## HUD: país, bioma, coordenadas e horário local da célula embaixo do personagem, bússola,
## mini mapa, painel de desempenho (F2), mensagens de status e a lista de controles.
## Montado em código para ficar fácil de mexer.

const INK := Color("3b3f5c")
const INK_SOFT := Color("6b6f8c")

var _country: Label
var _coords: Label
var _time: Label
var _status_panel: PanelContainer
var _status: Label
var _compass: Compass
var _minimap: Minimap
var _perf: Label
var _dev_badge: Label
var _help: Label
var _info_box: VBoxContainer


func _ready() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.position = Vector2(16, 16)
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	_country = _label(26, INK)
	_coords = _label(17, INK_SOFT)
	_time = _label(17, INK_SOFT)
	_info_box = box
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
	_status = _label(20, INK)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_panel.add_child(_status)

	var help := _label(15, Color(1, 1, 1, 0.92))
	help.text = "WASD andar · Shift correr · Espaço pular · E interagir · Tab/I bolso · 1–5 ferramentas · B construir · H casa\nbotão direito gira a câmera (ou Q/C) · roda do mouse: zoom · F2 desempenho · F3/F4 tempo · F6 configurações · F11 tela cheia"
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	help.add_theme_constant_override("outline_size", 5)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = 16
	help.offset_bottom = -12
	add_child(help)
	_help = help

	_compass = Compass.new()
	_compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_compass.offset_left = -Compass.WIDTH * 0.5
	_compass.offset_right = Compass.WIDTH * 0.5
	_compass.offset_top = 14
	_compass.offset_bottom = 14 + Compass.HEIGHT
	add_child(_compass)

	_minimap = Minimap.new()
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -Minimap.SIZE - 14
	_minimap.offset_top = -Minimap.SIZE - 14
	_minimap.offset_right = -14
	_minimap.offset_bottom = -14
	add_child(_minimap)

	_perf = _label(15, INK)
	var perf_card := PanelContainer.new()
	perf_card.add_theme_stylebox_override("panel", _card_style())
	perf_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	perf_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	perf_card.offset_right = -16
	perf_card.offset_top = 16
	perf_card.add_child(_perf)
	perf_card.visible = false
	add_child(perf_card)


## A linha de controles some enquanto uma janela está aberta (para não ficar por baixo).
func set_help_visible(on: bool) -> void:
	_help.visible = on


## Mostra o selo "MODO DEV · F1" quando o servidor está com GOBLO_DEV=1.
func set_dev(on: bool) -> void:
	if _dev_badge == null:
		_dev_badge = _label(15, Color("6b4c9a"))
		_dev_badge.text = "MODO DEV · F1 abre o painel"
		# Dentro do cartão (embaixo da hora), para não sobrepor nada com a interface maior.
		_info_box.add_child(_dev_badge)
	_dev_badge.visible = on


## Mensagem rápida no centro da tela, que some sozinha.
func flash(text: String) -> void:
	show_status(text)
	await get_tree().create_timer(1.5).timeout
	if _status.text == text:
		hide_status()


func build_minimap(world: WorldData) -> void:
	_minimap.build(world)


## Bússola e mini mapa, a cada quadro. `facing`: para onde o jogador está virado.
func update_navigation(camera_basis: Basis, up: Vector3, sun_dir: Vector3, facing := Vector3.ZERO) -> void:
	_compass.update_from(camera_basis, up)
	_minimap.update_view(up, sun_dir, facing)


## Onde fica a casa do jogador (direção a partir do centro do planeta).
func set_home(dir: Vector3) -> void:
	_minimap.set_home(dir)


func toggle_perf() -> void:
	(_perf.get_parent() as Control).visible = not (_perf.get_parent() as Control).visible


func perf_visible() -> bool:
	return (_perf.get_parent() as Control).visible


func show_perf(text: String) -> void:
	_perf.text = text


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
	s.border_color = Color(0, 0, 0, 0.08)
	s.set_border_width_all(1)
	return s
