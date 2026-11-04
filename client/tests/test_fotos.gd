extends SceneTree
## Álbum de fotos (fase 4.5, ADR 0055): fotos de vários assuntos em sequência, em duas contas
## de perfis diferentes e em duas contas do mesmo perfil; cada página mostra a foto certa
## (pela cor da imagem), escolher outra foto troca a miniatura, apagar volta para a mais
## antiga da página e nada vaza de uma conta para a outra. Sem servidor.
##
##   godot --headless --path . -s tests/test_fotos.gd

var _fails := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FALHOU ", what)


func _img(c: Color) -> Image:
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img


func _color_of(t: Texture2D) -> Color:
	if t == null:
		return Color(0, 0, 0, 0)
	return t.get_image().get_pixel(4, 4)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.03 and absf(a.g - b.g) < 0.03 and absf(a.b - b.b) < 0.03 and a.a > 0.0


func _run() -> void:
	var accounts := ["teste_fotos_a/1_aaaa", "teste_fotos_b/1_bbbb", "teste_fotos_a/2_cccc"]
	for a: String in accounts:
		_wipe(PediaPhotos.dir_of(a))
	var subjects := {"flower_red": Color.RED, "cow": Color.BLUE, "ipe": Color.YELLOW, "fox": Color.GREEN}
	# Cada conta fotografa os mesmos assuntos em sequência, com cores próprias.
	for k in accounts.size():
		for entry: String in subjects:
			var c: Color = (subjects[entry] as Color).darkened(0.25 * k)
			var id := PediaPhotos.save(accounts[k], _img(c), {"country": "BRA"})
			_check(not id.is_empty(), "salvar %s" % entry)
			PediaPhotos.tag(accounts[k], id, entry)
	for k in accounts.size():
		for entry: String in subjects:
			var want: Color = (subjects[entry] as Color).darkened(0.25 * k)
			_check(_near(_color_of(PediaPhotos.entry_thumbnail(accounts[k], entry)), want), "conta %d, %s: foto errada" % [k, entry])
		_check(PediaPhotos.list(accounts[k]).size() == subjects.size(), "conta %d: álbum com %d fotos" % [k, PediaPhotos.list(accounts[k]).size()])
	# Ids únicos mesmo no mesmo milissegundo.
	var seen := {}
	for i in 200:
		var id := PediaPhotos.new_id()
		_check(not seen.has(id), "id repetido")
		seen[id] = true
	# A segunda foto de uma página não troca a primeira; escolher na galeria troca.
	var a: String = accounts[0]
	var second := PediaPhotos.save(a, _img(Color.WHITE))
	PediaPhotos.tag(a, second, "cow")
	_check(_near(_color_of(PediaPhotos.entry_thumbnail(a, "cow")), Color.BLUE), "segunda foto trocou a da página")
	PediaPhotos.set_pick(a, "cow", second)
	_check(_near(_color_of(PediaPhotos.entry_thumbnail(a, "cow")), Color.WHITE), "escolher não trocou a foto da página")
	# Mais recentes primeiro.
	_check(str(PediaPhotos.list(a)[0]["id"]) == second, "álbum fora de ordem")
	# Apagar a escolhida volta para a mais antiga da página; apagar a última deixa sem foto.
	PediaPhotos.remove(a, second)
	_check(_near(_color_of(PediaPhotos.entry_thumbnail(a, "cow")), Color.BLUE), "apagar não voltou para a outra foto")
	var only := PediaPhotos.pick_of(a, "cow")
	PediaPhotos.remove(a, only)
	_check(PediaPhotos.entry_thumbnail(a, "cow") == null, "página ficou com foto apagada (cache)")
	# Zerar a Goblopédia (dev) tira as páginas, mas não as fotos.
	PediaPhotos.clear(a)
	_check(PediaPhotos.entry_thumbnail(a, "ipe") == null and PediaPhotos.list(a).size() == subjects.size() - 1, "zerar")
	for acc: String in accounts:
		_wipe(PediaPhotos.dir_of(acc))
	print("fotos: %s" % ("ok" if _fails == 0 else "%d falhas" % _fails))
	quit(1 if _fails else 0)


func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir)
