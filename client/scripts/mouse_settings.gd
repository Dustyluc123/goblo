class_name MouseSettings
extends RefCounted
## Configurações do mouse (F6): sensibilidade do giro da câmera e eixo vertical invertido.
## Ficam em user://settings.cfg, seção "mouse", junto das gráficas (Quality).

const MIN_SENSITIVITY := 0.25
const MAX_SENSITIVITY := 3.0

static var _sensitivity := -1.0
static var _invert_y := false
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(Quality.SETTINGS_FILE) == OK:
		_sensitivity = clampf(float(cfg.get_value("mouse", "sensitivity", 1.0)), MIN_SENSITIVITY, MAX_SENSITIVITY)
		_invert_y = bool(cfg.get_value("mouse", "invert_y", false))
	else:
		_sensitivity = 1.0


## Multiplicador da sensibilidade (1 = padrão).
static func sensitivity() -> float:
	_load()
	return _sensitivity


static func invert_y() -> bool:
	_load()
	return _invert_y


static func set_sensitivity(v: float) -> void:
	_load()
	_sensitivity = clampf(v, MIN_SENSITIVITY, MAX_SENSITIVITY)
	_save("sensitivity", _sensitivity)


static func set_invert_y(v: bool) -> void:
	_load()
	_invert_y = v
	_save("invert_y", v)


static func _save(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(Quality.SETTINGS_FILE)
	cfg.set_value("mouse", key, value)
	cfg.save(Quality.SETTINGS_FILE)
