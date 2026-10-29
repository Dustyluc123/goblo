class_name FpsLimit
extends RefCounted
## Limite de fps (fase 2.6), nas configurações (F6): 30, 60 ou sem limite; padrão 60.
## O V-Sync fica sempre ligado: a placa de vídeo espera a tela e não desenha quadros que
## ninguém vê (esquenta menos o Mac). "Sem limite" tira só o limite do jogo; o V-Sync
## continua segurando na frequência da tela. Fica salvo em user://settings.cfg.

const OPTIONS := [30, 60, 0]
const DEFAULT := 60

static var _value := -1


static func value() -> int:
	if _value < 0:
		_value = DEFAULT
		var cfg := ConfigFile.new()
		if cfg.load(Quality.SETTINGS_FILE) == OK:
			var saved := int(cfg.get_value("graphics", "fps_limit", DEFAULT))
			if saved in OPTIONS:
				_value = saved
	return _value


static func label_of(v: int) -> String:
	return "sem limite" if v == 0 else "%d fps" % v


static func label() -> String:
	return label_of(value())


static func set_value(v: int, save := true) -> void:
	if not v in OPTIONS:
		return
	_value = v
	if save:
		var cfg := ConfigFile.new()
		cfg.load(Quality.SETTINGS_FILE)
		cfg.set_value("graphics", "fps_limit", v)
		cfg.save(Quality.SETTINGS_FILE)
	apply()


## Aplica o limite e liga o V-Sync. Se o limite for igual ou maior que a frequência da tela
## (60 fps numa tela de 60 Hz), quem segura é só o V-Sync: dois limitadores juntos fazem o
## ritmo dos quadros tremer.
static func apply() -> void:
	var v := value()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		var hz := DisplayServer.screen_get_refresh_rate()
		if v > 0 and hz > 0.0 and float(v) >= hz - 1.0:
			v = 0
	Engine.max_fps = v
