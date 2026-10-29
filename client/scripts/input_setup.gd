class_name InputSetup
extends RefCounted
## Registra as ações de teclado em código (mais fácil de ler e revisar que o InputMap do project.godot).
## Usa teclas físicas, então funciona igual em teclados QWERTY e AZERTY.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"inventory": [KEY_TAB, KEY_I],
	"build": [KEY_B],
	"rotate": [KEY_R],
	"pick_up": [KEY_X],
	"home": [KEY_H],
	"pedia": [KEY_G],
	"passport": [KEY_P],
	"dev_panel": [KEY_F1],
}


static func ensure() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
