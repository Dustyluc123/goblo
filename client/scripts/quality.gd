class_name Quality
extends RefCounted
## Qualidade gráfica: baixa, média ou alta. Controla densidade e distância da vegetação,
## sombras e antisserrilhado. Fica salva em user://settings.cfg.
##
## A densidade só afeta decorações pequenas (grama, plantas, pedrinhas): árvores e pedras
## grandes são iguais em qualquer qualidade (ver docs/decisoes/0011).

signal changed

const SETTINGS_FILE := "user://settings.cfg"
const NAMES := ["low", "medium", "high"]
const LABELS := {"low": "baixa", "medium": "média", "high": "alta"}
const PRESETS := {
	"low": {
		"small_density": 0.4, "small_radius": 30.0, "big_radius": 75.0,
		"collider_radius": 35.0, "shadows": false, "big_shadows": false,
		"shadow_distance": 0.0, "msaa": Viewport.MSAA_DISABLED, "fxaa": false, "clouds": 30,
	},
	"medium": {
		"small_density": 0.7, "small_radius": 45.0, "big_radius": 115.0,
		"collider_radius": 40.0, "shadows": true, "big_shadows": false,
		"shadow_distance": 40.0, "msaa": Viewport.MSAA_DISABLED, "fxaa": true, "clouds": 50,
	},
	"high": {
		"small_density": 1.0, "small_radius": 70.0, "big_radius": 170.0,
		"collider_radius": 45.0, "shadows": true, "big_shadows": true,
		"shadow_distance": 90.0, "msaa": Viewport.MSAA_4X, "fxaa": false, "clouds": 80,
	},
}
const DEFAULT := "medium"

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
