class_name PlayersUi
extends PanelContainer
## Jogadores por perto (tecla J, fase 3): apelido, país e distância de quem aparece na tela,
## com Silenciar (só neste computador: some o balão e o chat dele) e Bloquear (no servidor:
## nenhum dos dois vê mais o chat e os emotes do outro).

var game: GameMain
var remotes: RemotePlayers
var _list: VBoxContainer
var _empty: Label
## Bloqueados nesta sessão (o servidor guarda; aqui só para mostrar o botão certo).
var blocked := {}


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26))
	custom_minimum_size = Vector2(620, 420)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Jogadores por perto", 26), "J ou Esc", func() -> void: visible = false))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_empty = UiStyle.label("Ninguém por perto agora.", 18, UiStyle.INK_SOFT)
	box.add_child(_empty)
	visible = false


func setup(g: GameMain, r: RemotePlayers) -> void:
	game = g
	remotes = r


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var here := game.player_position()
	var rows: Array = []
	for id: int in remotes.ids():
		rows.append([here.distance_to(remotes.position_of(id)), id])
	rows.sort()
	for r: Array in rows:
		var id: int = r[1]
		var inf := remotes.info(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name := UiStyle.label("%s  ·  %s  ·  %d m" % [inf.get("nick", "?"), game.country_name(str(inf.get("country", ""))), int(r[0] * 6.4)], 18)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		if bool(inf.get("bot", false)):
			row.add_child(UiStyle.label("bot", 15, UiStyle.INK_SOFT))
		var mute := UiStyle.button("Ouvir de novo" if remotes.muted.has(id) else "Silenciar", false)
		mute.pressed.connect(func() -> void:
			game.set_muted(id, not remotes.muted.has(id))
			refresh())
		row.add_child(mute)
		var block := UiStyle.button("Desbloquear" if blocked.has(id) else "Bloquear", false)
		block.disabled = bool(inf.get("bot", false))
		block.pressed.connect(func() -> void:
			game.set_blocked(id, not blocked.has(id))
			refresh())
		row.add_child(block)
		_list.add_child(row)
	_empty.visible = rows.is_empty()
