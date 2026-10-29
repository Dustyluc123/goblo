class_name Quality
extends RefCounted
## Qualidade gráfica (baixa, média, alta) e tamanho da interface (80% a 150%).
## A qualidade controla densidade e distância da vegetação, sombras, antisserrilhado e a
## resolução do 3D (scale_3d: fração da tela em que o 3D é renderizado antes de ser
## ampliado com FSR; a interface continua na resolução cheia). Tudo fica salvo em
## user://settings.cfg.
##
## A densidade só afeta decorações pequenas (grama, plantas, pedrinhas): árvores e pedras
## grandes são iguais em qualquer qualidade (ver docs/decisoes/0011).

signal changed
## O tamanho da interface mudou (não recarrega a vegetação).
signal ui_changed

const SETTINGS_FILE := "user://settings.cfg"
const NAMES := ["low", "medium", "high"]
const LABELS := {"low": "baixa", "medium": "média", "high": "alta"}
const PRESETS := {
	"low": {
		"small_density": 0.4, "small_radius": 30.0, "big_radius": 75.0,
		"collider_radius": 35.0, "shadows": false, "big_shadows": false,
		"shadow_distance": 0.0, "msaa": Viewport.MSAA_DISABLED, "fxaa": false, "clouds": 30,
		"scale_3d": 0.5,
	},
	"medium": {
		"small_density": 0.7, "small_radius": 45.0, "big_radius": 115.0,
		"collider_radius": 40.0, "shadows": true, "big_shadows": false,
		"shadow_distance": 40.0, "msaa": Viewport.MSAA_DISABLED, "fxaa": true, "clouds": 50,
		"scale_3d": 0.67,
	},
	"high": {
		"small_density": 1.0, "small_radius": 70.0, "big_radius": 170.0,
		"collider_radius": 45.0, "shadows": true, "big_shadows": true,
		"shadow_distance": 90.0, "msaa": Viewport.MSAA_4X, "fxaa": false, "clouds": 80,
		"scale_3d": 0.85,
	},
}
const DEFAULT := "medium"
## Tamanhos da interface (multiplicam a escala que acompanha a janela).
const UI_SCALES := [0.8, 1.0, 1.25, 1.5]
## Abaixo desta altura de janela (em pixels), o 3D é renderizado na resolução cheia: a
## redução só vale em telas grandes (Retina), onde não dá para ver a diferença.
const FULL_RES_HEIGHT := 1080.0

static var _ui_scale := -1.0

static var _current := ""
static var emitter := Quality.new()


static func current_name() -> String:
	if _current.is_empty():
		var cfg := ConfigFile.new()
		_current = DEFAULT
		if cfg.load(SETTINGS_FILE) == OK:
			var saved := str(cfg.get_value("graphics", "quality", DEFAULT))
			if PRESETS.has(saved):
				_current = saved
	return _current


static func current() -> Dictionary:
	return PRESETS[current_name()]


static func label() -> String:
	return LABELS[current_name()]


static func set_quality(q: String, save := true) -> void:
	if not PRESETS.has(q):
		push_warning("Qualidade desconhecida: %s" % q)
		return
	_current = q
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_FILE)
		cfg.set_value("graphics", "quality", q)
		cfg.save(SETTINGS_FILE)
	emitter.changed.emit()


static func cycle() -> void:
	var i := NAMES.find(current_name())
	set_quality(NAMES[(i + 1) % NAMES.size()])


static func ui_scale() -> float:
	if _ui_scale < 0.0:
		var cfg := ConfigFile.new()
		_ui_scale = 1.0
		if cfg.load(SETTINGS_FILE) == OK:
			var saved := float(cfg.get_value("interface", "scale", 1.0))
			if saved in UI_SCALES:
				_ui_scale = saved
	return _ui_scale


static func set_ui_scale(v: float, save := true) -> void:
	_ui_scale = v
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_FILE)
		cfg.set_value("interface", "scale", v)
		cfg.save(SETTINGS_FILE)
	emitter.ui_changed.emit()


## Fração da resolução da janela em que o 3D é renderizado. Em janelas pequenas (até
## 1080 de altura) é 1; em telas maiores, a do preset (ou o que der 1080 linhas, se for mais).
static func render_scale(window_height: float) -> float:
	var target: float = current()["scale_3d"]
	return clampf(maxf(target, FULL_RES_HEIGHT / maxf(window_height, 1.0)), 0.25, 1.0)
