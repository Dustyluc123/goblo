class_name EmoteWheel
extends PanelContainer
## Roda de emotes (tecla T, fase 3): acenar, sim, não, sentar e comemorar. Clique ou número
## de 1 a 5; T ou Esc fecha. Quem está perto vê (o servidor manda para quem te vê).

signal picked(emote: String)

const EMOTES := [["wave", "Acenar"], ["yes", "Sim"], ["no", "Não"], ["sit", "Sentar"], ["cheer", "Comemorar"]]


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26, Color(1, 0.98, 0.94, 0.96), 14))
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Emotes", 22), "T ou Esc", func() -> void: visible = false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for i in EMOTES.size():
		var e: Array = EMOTES[i]
		var b := UiStyle.button("%d  %s" % [i + 1, e[1]], i == 0)
		b.custom_minimum_size = Vector2(130, 56)
		var id: String = e[0]
		b.pressed.connect(func() -> void: _pick(id))
		row.add_child(b)
	visible = false


func toggle() -> void:
	visible = not visible


func _pick(id: String) -> void:
	visible = false
	picked.emit(id)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_5:
		_pick(EMOTES[k - KEY_1][0])
		get_viewport().set_input_as_handled()
