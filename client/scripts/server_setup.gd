class_name ServerSetup
extends PanelContainer
## Endereço do servidor (fase 3, para jogar com amigos): aparece quando o jogo não acha o
## servidor ao abrir. O endereço fica salvo em user://settings.cfg ([network] server_url).
## Também dá para usar --server=URL, a variável GOBLO_SERVER_URL ou um arquivo
## goblo-servidor.txt ao lado do jogo (docs/DEPLOY.md).

signal chosen(url: String)

var _edit: LineEdit


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26))
	custom_minimum_size = Vector2(560, 0)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UiStyle.label("Endereço do servidor", 24))
	var hint := UiStyle.label("O jogo não achou o servidor. Se um amigo hospeda o Goblo, cole aqui o endereço que ele mandou (por exemplo https://goblo.exemplo.com).", 16, UiStyle.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(hint)
	_edit = UiStyle.line_edit("https://…")
	_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	box.add_child(_edit)
	var go := UiStyle.button("Conectar")
	go.pressed.connect(_submit)
	box.add_child(go)
	visible = false


func open(current: String) -> void:
	_edit.text = current
	visible = true


func _submit() -> void:
	var url := _edit.text.strip_edges().trim_suffix("/")
	if url.is_empty():
		return
	if not (url.begins_with("http://") or url.begins_with("https://")):
		url = "https://" + url
	var cfg := ConfigFile.new()
	cfg.load(Quality.SETTINGS_FILE)
	cfg.set_value("network", "server_url", url)
	cfg.save(Quality.SETTINGS_FILE)
	visible = false
	chosen.emit(url)
