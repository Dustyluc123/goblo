class_name FurnaceUi
extends PanelContainer
## Fornalha (fase 4.5, ADR 0057): derrete minério em barra com carvão, com uma espera. Vale a
## fornalha do lote (cave = −1) ou a fornalha antiga da entrada de uma caverna. O que fica
## pronto espera na fornalha até o jogador buscar (em qualquer fornalha). Regras e espera
## ficam no servidor; aqui só se escolhe e se mostra a contagem.

var game: GameMain
var session: Session
var icons: ItemIcons
var cave := -1
var _rows: VBoxContainer
var _jobs: VBoxContainer
var _collect: Button
var _view := {}
var _clock_at := 0.0
var _tick := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(24))
	custom_minimum_size = Vector2(720, 480)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Fornalha", 26), "Esc", func() -> void: visible = false))
	box.add_child(UiStyle.label("Minério + carvão viram barra. Fica pronto depois de uns segundos; pode sair e voltar.", 15, UiStyle.INK_SOFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	_rows = VBoxContainer.new()
	_rows.custom_minimum_size = Vector2(400, 0)
	_rows.add_theme_constant_override("separation", 6)
	row.add_child(_rows)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(260, 0)
	row.add_child(right)
	right.add_child(UiStyle.label("Na fornalha", 19))
	_jobs = VBoxContainer.new()
	right.add_child(_jobs)
	_collect = UiStyle.button("Pegar o que está pronto", true)
	_collect.pressed.connect(func() -> void: _do("POST", "/furnace/collect", _body({})))
	right.add_child(_collect)
	visible = false


func setup(g: GameMain, s: Session, i: ItemIcons) -> void:
	game = g
	session = s
	icons = i
	session.inventory_changed.connect(func() -> void:
		if visible:
			_build())


func open(where: int) -> void:
	cave = where
	visible = true
	_build()
	var r := await game.api_request("GET", "/furnace")
	if r["ok"]:
		_set_view(r["data"])


func _body(b: Dictionary) -> Dictionary:
	if cave >= 0:
		b["cave"] = cave
	return b


func _do(method: String, path: String, body: Dictionary) -> void:
	var r := await game.api_request(method, path, body)
	if not r["ok"]:
		game.toast(str(r["message"]))
		return
	var d: Dictionary = r["data"]
	if d.get("inventory") is Array:
		session.set_inventory(d["inventory"], int(d.get("slots_used", 0)))
	if not str(d.get("message", "")).is_empty():
		game.toast(str(d["message"]))
	_set_view(d)


func _set_view(v: Dictionary) -> void:
	_view = v
	_clock_at = Time.get_unix_time_from_system() - float(v.get("now", Time.get_unix_time_from_system()))
	_show_jobs()


func _process(delta: float) -> void:
	if not visible:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_show_jobs()


func _build() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for r: Dictionary in session.recipes:
		if str(r.get("station", "")) != "furnace":
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.texture = icons.icon(str(r["result"]))
		ic.custom_minimum_size = Vector2(40, 40)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		line.add_child(ic)
		var parts: PackedStringArray = []
		for k: String in r["ingredients"]:
			parts.append("%d %s" % [int(r["ingredients"][k]), session.item_name(k)])
		var l := UiStyle.label("%s\n%s · %d s" % [session.item_name(str(r["result"])), " + ".join(parts), int(r.get("seconds", 0))], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		for n in [1, 5]:
			var b := UiStyle.button("×%d" % n, n == 1)
			b.disabled = not session.can_afford(_times(r["ingredients"], n))
			var id := str(r["id"])
			b.pressed.connect(func() -> void: _do("POST", "/furnace/smelt", _body({"recipe": id, "times": n})))
			line.add_child(b)
		_rows.add_child(line)


func _times(cost: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k: String in cost:
		out[k] = int(cost[k]) * n
	return out


func _show_jobs() -> void:
	for c in _jobs.get_children():
		c.queue_free()
	var now := Time.get_unix_time_from_system() - _clock_at
	var ready := 0
	for j: Dictionary in _view.get("jobs", []):
		var left := int(ceil(float(j["ready_at"]) - now))
		var text := "%d× %s  ·  %s" % [int(j["count"]), session.item_name(str(j["item"])), tr("pronto!") if left <= 0 else tr("%d s") % left]
		ready += 1 if left <= 0 else 0
		_jobs.add_child(UiStyle.label(text, 15, UiStyle.INK if left <= 0 else UiStyle.INK_SOFT))
	if (_view.get("jobs", []) as Array).is_empty():
		_jobs.add_child(UiStyle.label("Vazia.", 15, UiStyle.INK_SOFT))
	_collect.disabled = ready == 0
