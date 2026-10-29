class_name PassportUi
extends PanelContainer
## Livro de passaporte (tecla P): uma página com os passaportes que você tem e, depois, um
## carimbo por país visitado (a pé ou de avião), com o nome e a data da primeira visita.
## Cada carimbo é desenhado em código e é único por país: forma, cor, borda e enfeite saem
## de um sorteio pelo código do país (StampArt).

var game: GameMain
var session: Session
var _passports: Label
var _grid: GridContainer
var _count: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(26, Color("f6efe0")))
	custom_minimum_size = Vector2(900, 600)
	UiStyle.center(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Passaporte", 28, Color("2f4f7a")), "P ou Esc", func() -> void: visible = false))
	_passports = UiStyle.label("", 16, UiStyle.INK)
	_passports.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_passports)
	_count = UiStyle.label("", 15, UiStyle.INK_SOFT)
	box.add_child(_count)
	var page := PanelContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("fffaf0")
	ps.set_corner_radius_all(14)
	ps.border_color = Color("d8c9a8")
	ps.set_border_width_all(2)
	ps.content_margin_left = 14
	ps.content_margin_right = 14
	ps.content_margin_top = 12
	ps.content_margin_bottom = 12
	page.add_theme_stylebox_override("panel", ps)
	box.add_child(page)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	visible = false


func setup(g: GameMain, s: Session) -> void:
	game = g
	session = s


func toggle() -> void:
	if visible:
		visible = false
		return
	visible = true
	_render(session.passport_book)
	var r := await game.api_request("GET", "/passport")
	if r["ok"]:
		session.set_passport_book(r["data"])
		_render(r["data"])


## Quantos nomes de passaportes aparecem antes do "e mais N" (com muitos, a lista empurrava
## a página dos carimbos para fora da janela).
const MAX_NAMES := 12


func _render(book: Dictionary) -> void:
	# Nome do país: o do mundo e, para os territórios sem hexágono, o que veio nos carimbos.
	var known := {}
	for st: Dictionary in book.get("stamps", []):
		known[str(st["country"])] = str(st["name"])
	var home := str(session.me.get("country", ""))
	var names: Array = []
	var codes: Array = book.get("passports", session.passports())
	for c: String in codes:
		var n := game.country_name(c)
		if n == c and known.has(c):
			n = known[c]
		names.append(n + (" (residência)" if c == home else ""))
	names.sort_custom(func(a: String, b: String) -> bool: return a.ends_with("(residência)") and not b.ends_with("(residência)"))
	var shown := names.slice(0, MAX_NAMES)
	var text := "%d %s: %s" % [names.size(), "passaporte" if names.size() == 1 else "passaportes", ", ".join(shown)]
	if names.size() > MAX_NAMES:
		text += " e mais %d" % (names.size() - MAX_NAMES)
	_passports.text = text
	for c in _grid.get_children():
		c.queue_free()
	var stamps: Array = book.get("stamps", [])
	_count.text = "%d %s" % [stamps.size(), "país visitado" if stamps.size() == 1 else "países visitados"] if not stamps.is_empty() \
		else "Nenhum carimbo ainda. Atravesse uma fronteira (com o passaporte) ou viaje de avião!"
	for st: Dictionary in stamps:
		var art := StampArt.new()
		art.code = str(st["country"])
		art.country_name = str(st["name"])
		var when := Time.get_datetime_dict_from_unix_time(int(st["first_at"]))
		art.date = "%02d/%02d/%04d" % [when["day"], when["month"], when["year"]]
		_grid.add_child(art)
