class_name SellUi
extends PanelContainer
## Vender (fase 3.5): a caixa de vendas do lote e a loja da praça usam esta janela. Todo
## item do bolso pode ser vendido, com a quantidade escolhida ou "tudo deste tipo". A loja
## paga um pouco mais (economy.shop_buy_bonus). Ferramentas e itens raros pedem confirmação.
## Preços e regras ficam no servidor (Service.Price); aqui só se escolhe o quê e quanto.

## Itens raros (pedem confirmação, além das ferramentas): a flor azul e o que vale muito.
const RARE := ["flower_blue", "windmill", "fountain", "fountain_square", "camera"]
const RARE_PRICE := 20

var game: GameMain
var session: Session
var icons: ItemIcons
## "box" (caixa de vendas do lote) ou "shop" (loja da praça de `country`).
var mode := "box"
var country := ""
var _title: Label
var _hint: Label
var _rows: VBoxContainer
var _empty: Label
var _total: Label
var _confirm: PanelContainer
var _confirm_text: Label
var _pending: Array = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26))
	custom_minimum_size = Vector2(760, 520)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UiStyle.label("Caixa de vendas", 26)
	box.add_child(UiStyle.header(_title, "Esc", func() -> void: visible = false))
	_hint = UiStyle.label("", 16, UiStyle.INK_SOFT)
	box.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	_empty = UiStyle.label("O bolso está vazio. Tudo o que você coleta ou fabrica vale gobolares!", 16, UiStyle.INK_SOFT)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_empty)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	_total = UiStyle.label("", 18)
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_total)
	var all := UiStyle.button("Vender tudo")
	all.pressed.connect(func() -> void: _ask(_everything()))
	foot.add_child(all)
	box.add_child(foot)
	# Confirmação (ferramentas e itens raros).
	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", UiStyle.panel(18, Color("fff4dc"), 14))
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 8)
	_confirm.add_child(cb)
	_confirm_text = UiStyle.label("", 17)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	cb.add_child(_confirm_text)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	var yes := UiStyle.button("Vender mesmo assim")
	yes.pressed.connect(func() -> void:
		_confirm.visible = false
		_do_sell(_pending))
	crow.add_child(yes)
	var no := UiStyle.button("Cancelar", false)
	no.pressed.connect(func() -> void: _confirm.visible = false)
	crow.add_child(no)
	cb.add_child(crow)
	_confirm.visible = false
	box.add_child(_confirm)
	visible = false


func setup(g: GameMain, s: Session, i: ItemIcons) -> void:
	game = g
	session = s
	icons = i
	session.inventory_changed.connect(func() -> void:
		if visible:
			refresh())


## Abre a caixa de vendas do lote.
func open() -> void:
	open_mode("box", "")


## Abre como a caixa de vendas ("box") ou como a loja da praça ("shop", do país).
func open_mode(m: String, c: String) -> void:
	mode = m
	country = c
	_title.text = "Caixa de vendas" if mode == "box" else "Vender na loja"
	_hint.text = "Coloque itens na caixa e receba na hora." if mode == "box" \
		else "A loja paga um pouquinho mais que a caixa de vendas."
	_confirm.visible = false
	visible = true
	refresh()


## Preço de uma unidade aqui (a loja paga o bônus em cima da caixa de vendas).
func unit_price(id: String) -> int:
	var base := int(session.sell_prices.get(id, 0))
	if mode == "shop":
		return ceili(base * float(session.shop_buy_bonus))
	return base


func _everything() -> Array:
	var out: Array = []
	for st: Dictionary in session.inventory:
		if unit_price(st["item"]) > 0:
			out.append({"item": st["item"], "count": int(st["count"])})
	return out


static func needs_confirm(s: Session, id: String) -> bool:
	return str(s.items.get(id, {}).get("category", "")) == "tool" or RARE.has(id) \
		or int(s.sell_prices.get(id, 0)) >= RARE_PRICE


## Vende, pedindo confirmação antes se houver ferramenta ou item raro.
func _ask(items: Array) -> void:
	if items.is_empty():
		return
	var special: Array = items.filter(func(x: Dictionary) -> bool: return needs_confirm(session, str(x["item"])))
	if special.is_empty():
		_do_sell(items)
		return
	_pending = items
	var names: Array = special.map(func(x: Dictionary) -> String: return "%d× %s" % [int(x["count"]), session.item_name(x["item"])])
	_confirm_text.text = "Tem certeza? Você vai vender %s (ferramenta ou item raro)." % ", ".join(names)
	_confirm.visible = true


func _do_sell(items: Array) -> void:
	if mode == "shop":
		await game.shop_sell(country, items)
	else:
		await game.sell(items)


func refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var total := 0
	for st: Dictionary in session.inventory:
		var id: String = st["item"]
		var price := unit_price(id)
		if price <= 0:
			continue
		var n := int(st["count"])
		total += price * n
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ic := TextureRect.new()
		ic.texture = icons.icon(id)
		ic.custom_minimum_size = Vector2(44, 44)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
		var name := UiStyle.label("%s  ×%d" % [session.item_name(id), n], 18)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var coin := CoinIcon.new()
		coin.diameter = 18.0
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(coin)
		row.add_child(UiStyle.label("%d cada" % price, 16, UiStyle.INK_SOFT))
		var qty := SpinBox.new()
		qty.min_value = 1
		qty.max_value = n
		qty.value = 1
		qty.custom_minimum_size = Vector2(90, 0)
		UiStyle.spin_box(qty)
		row.add_child(qty)
		var some := UiStyle.button("Vender", false)
		some.pressed.connect(func() -> void: _ask([{"item": id, "count": int(qty.value)}]))
		row.add_child(some)
		var every := UiStyle.button("Tudo deste tipo")
		every.pressed.connect(func() -> void: _ask([{"item": id, "count": n}]))
		row.add_child(every)
		_rows.add_child(row)
	_empty.visible = total == 0
	_total.text = "Tudo vale %s" % session.coins_text(total) if total > 0 else ""
