class_name TradeUi
extends PanelContainer
## Troca entre jogadores (fase 3.5, ADR 0044). Os dois lados montam a oferta (itens do bolso
## e gobolares) e cada mudança aparece para o outro na hora. Quando os dois marcam "Pronto",
## falta a confirmação final; qualquer mudança desfaz os "Pronto". Quem executa é o servidor
## (de uma vez só, conferindo bolso, distância e bloqueio); aqui só se monta e se mostra.
##
## A mesma janela mostra o pedido de troca que chegou (Aceitar / Recusar).

const REQUEST_SECONDS := 30.0

var game: GameMain
var session: Session
var icons: ItemIcons
## Estado da troca (trade_open/trade_update): {id, with, nick, mine, theirs, my_ready, …}.
var view := {}
var _offer_items: Array = []  # [{item, count}]
var _title: Label
var _trade_box: VBoxContainer
var _mine: VBoxContainer
var _theirs: VBoxContainer
var _their_title: Label
var _pick: OptionButton
var _pick_count: SpinBox
var _coins: SpinBox
var _their_coins: Label
var _status: Label
var _ready_btn: Button
var _confirm_btn: Button
var _req_box: VBoxContainer
var _req_text: Label
var _req_from := 0
var _req_at := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26))
	custom_minimum_size = Vector2(860, 520)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UiStyle.label("Troca", 26)
	box.add_child(UiStyle.header(_title, "Esc cancela", cancel))

	# Pedido que chegou.
	_req_box = VBoxContainer.new()
	_req_box.add_theme_constant_override("separation", 10)
	_req_text = UiStyle.label("", 20)
	_req_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_req_box.add_child(_req_text)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 10)
	var yes := UiStyle.button("Aceitar")
	yes.pressed.connect(func() -> void: _answer(true))
	rrow.add_child(yes)
	var no := UiStyle.button("Recusar", false)
	no.pressed.connect(func() -> void: _answer(false))
	rrow.add_child(no)
	_req_box.add_child(rrow)
	box.add_child(_req_box)

	# A negociação.
	_trade_box = VBoxContainer.new()
	_trade_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trade_box.add_theme_constant_override("separation", 10)
	box.add_child(_trade_box)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 18)
	_trade_box.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(UiStyle.label("Você oferece", 20, Color("b5566b")))
	_mine = VBoxContainer.new()
	_mine.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_mine)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	_pick = OptionButton.new()
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pick.add_theme_font_size_override("font_size", 17)
	_pick.add_theme_constant_override("icon_max_width", 28)
	_pick.get_popup().add_theme_constant_override("icon_max_width", 28)
	_pick.get_popup().add_theme_font_size_override("font_size", 17)
	add_row.add_child(_pick)
	_pick_count = SpinBox.new()
	_pick_count.min_value = 1
	_pick_count.max_value = 999
	UiStyle.spin_box(_pick_count)
	add_row.add_child(_pick_count)
	var add := UiStyle.button("Pôr na troca", false)
	add.pressed.connect(_add_item)
	add_row.add_child(add)
	left.add_child(add_row)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 6)
	var ci := CoinIcon.new()
	ci.diameter = 20.0
	ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_row.add_child(ci)
	coin_row.add_child(UiStyle.label("Gobolares", 17))
	_coins = SpinBox.new()
	_coins.min_value = 0
	_coins.max_value = 1000000
	UiStyle.spin_box(_coins)
	_coins.value_changed.connect(func(_v: float) -> void: _send_offer())
	coin_row.add_child(_coins)
	left.add_child(coin_row)

	cols.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	_their_title = UiStyle.label("", 20, Color("4f7a9a"))
	right.add_child(_their_title)
	_theirs = VBoxContainer.new()
	_theirs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_theirs)
	_their_coins = UiStyle.label("", 17)
	right.add_child(_their_coins)

	_status = UiStyle.label("", 17, UiStyle.INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_trade_box.add_child(_status)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	_ready_btn = UiStyle.button("Pronto", false)
	_ready_btn.pressed.connect(func() -> void:
		game.net_send({"t": "trade_ready", "on": not bool(view.get("my_ready", false))}))
	foot.add_child(_ready_btn)
	_confirm_btn = UiStyle.button("Confirmar troca")
	_confirm_btn.pressed.connect(func() -> void: game.net_send({"t": "trade_confirm"}))
	foot.add_child(_confirm_btn)
	var cancel_btn := UiStyle.button("Cancelar", false)
	cancel_btn.pressed.connect(cancel)
	foot.add_child(cancel_btn)
	_trade_box.add_child(foot)
	visible = false
	# Fechou a janela (Esc, outra janela) no meio da troca: cancela.
	visibility_changed.connect(func() -> void:
		if not visible and trading():
			game.net_send({"t": "trade_cancel"}))


func setup(g: GameMain, s: Session, i: ItemIcons) -> void:
	game = g
	session = s
	icons = i
	session.inventory_changed.connect(func() -> void:
		if visible and not view.is_empty():
			_fill_pick())


## Está negociando agora?
func trading() -> bool:
	return not view.is_empty()


## Chegou um pedido de troca: mostra Aceitar / Recusar (some sozinho em 30 s).
func show_request(from: int, nick: String) -> void:
	if trading():
		game.net_send({"t": "trade_answer", "from": from, "ok": false})
		return
	_req_from = from
	_req_at = Time.get_ticks_msec() / 1000.0
	_title.text = "Pedido de troca"
	_req_text.text = "%s quer trocar com você." % nick
	_req_box.visible = true
	_trade_box.visible = false
	visible = true


func _answer(ok: bool) -> void:
	game.net_send({"t": "trade_answer", "from": _req_from, "ok": ok})
	_req_from = 0
	if not ok:
		visible = false


## Estado novo da troca (trade_open, trade_update).
func show_view(v: Dictionary) -> void:
	var opening := view.is_empty() or int(view.get("id", 0)) != int(v.get("id", 0))
	view = v
	if opening:
		_offer_items = []
		_coins.set_value_no_signal(0)
		_fill_pick()
	_req_box.visible = false
	_trade_box.visible = true
	_title.text = "Troca com %s" % str(v.get("nick", "?"))
	_their_title.text = "%s oferece" % str(v.get("nick", "?"))
	var mine: Dictionary = v.get("mine", {})
	_offer_items = (mine.get("items", []) if mine.get("items") is Array else []).map(
		func(x: Dictionary) -> Dictionary: return {"item": str(x["item"]), "count": int(x["count"])})
	_coins.set_value_no_signal(float(mine.get("coins", 0)))
	_fill_side(_mine, _offer_items, true)
	var theirs: Dictionary = v.get("theirs", {})
	var their_items: Array = theirs.get("items", []) if theirs.get("items") is Array else []
	_fill_side(_theirs, their_items, false)
	_their_coins.text = "+ %s" % session.coins_text(int(theirs.get("coins", 0)))
	var me_ready := bool(v.get("my_ready", false))
	var they_ready := bool(v.get("their_ready", false))
	_ready_btn.text = "Pronto ✓" if me_ready else "Pronto"
	_confirm_btn.disabled = not bool(v.get("both_ready", false)) or bool(v.get("my_confirm", false))
	if bool(v.get("my_confirm", false)):
		_status.text = "Você confirmou. Esperando %s confirmar…" % str(v.get("nick", "?"))
	elif bool(v.get("both_ready", false)):
		_status.text = "Os dois estão prontos. Confira tudo e confirme a troca."
	else:
		_status.text = "Você: %s  ·  %s: %s  (qualquer mudança desfaz os \"pronto\")" % [
			"pronto" if me_ready else "montando", str(v.get("nick", "?")), "pronto" if they_ready else "montando"]
	visible = true


## A troca aconteceu: o servidor manda o bolso e o saldo novos.
func on_done(r: Dictionary) -> void:
	view = {}
	visible = false
	session.set_inventory(r.get("inventory", []), int(r.get("slots_used", 0)))
	session.set_coins(int(r.get("coins", session.coins)))
	game.toast(str(r.get("message", "Troca feita!")))


func on_closed(reason: String) -> void:
	view = {}
	visible = false
	if not reason.is_empty():
		game.toast(reason)


func cancel() -> void:
	if trading():
		game.net_send({"t": "trade_cancel"})
	elif _req_from != 0:
		_answer(false)
	visible = false


func _process(_delta: float) -> void:
	if visible and _req_box.visible and Time.get_ticks_msec() / 1000.0 - _req_at > REQUEST_SECONDS:
		visible = false


func _fill_pick() -> void:
	_pick.clear()
	for st: Dictionary in session.inventory:
		_pick.add_icon_item(icons.icon(st["item"]), "%s (%d)" % [session.item_name(st["item"]), int(st["count"])])
		_pick.set_item_metadata(_pick.item_count - 1, st["item"])
	_pick.disabled = _pick.item_count == 0


func _add_item() -> void:
	if _pick.selected < 0:
		return
	var id := str(_pick.get_item_metadata(_pick.selected))
	var n := int(_pick_count.value)
	var have := session.count(id)
	for x: Dictionary in _offer_items:
		if x["item"] == id:
			x["count"] = mini(int(x["count"]) + n, have)
			_send_offer()
			return
	_offer_items.append({"item": id, "count": mini(n, have)})
	_send_offer()


func _remove_item(id: String) -> void:
	_offer_items = _offer_items.filter(func(x: Dictionary) -> bool: return x["item"] != id)
	_send_offer()


func _send_offer() -> void:
	if not trading():
		return
	game.net_send({"t": "trade_offer", "items": _offer_items, "coins": int(_coins.value)})


func _fill_side(box: VBoxContainer, items: Array, mine: bool) -> void:
	for c in box.get_children():
		c.queue_free()
	if items.is_empty():
		box.add_child(UiStyle.label("(nada ainda)", 16, UiStyle.INK_SOFT))
	for x: Dictionary in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.texture = icons.icon(str(x["item"]))
		ic.custom_minimum_size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
		var name := UiStyle.label("%s  ×%d" % [session.item_name(str(x["item"])), int(x["count"])], 17)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		if mine:
			var rm := UiStyle.button("Tirar", false)
			var id := str(x["item"])
			rm.pressed.connect(func() -> void: _remove_item(id))
			row.add_child(rm)
		box.add_child(row)
