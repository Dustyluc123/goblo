class_name BodyGame
extends Node
## Corpo do personagem no cliente (fase 4.0, ADR 0050). O servidor é a fonte da verdade das
## necessidades e da temperatura: aqui só se mostra o que chega na mensagem body e se pedem as
## ações (comer, beber, cozinhar, encher o cantil, acender fogueira).
##
## - HUD (canto de cima, à direita): termômetro com a temperatura sentida e um ícone (sol,
##   floco) quando está muito quente ou muito frio; três indicadores (sede, conforto, fome),
##   discretos quando estão bem; os bônus da comida com o tempo que falta.
## - Fome no mínimo: a tela fica levemente zonza (ondulação suave e cantos escuros).
## - Reações: treme no frio, solta gotinhas de suor no calor e vapor da respiração no gelado.
## - Fogueiras acesas no chão (de todo mundo), com fogo e luz.
## - Janela de cozinhar perto de uma fogueira (receitas de station fire).

const HUD_WIDTH := 236.0
## Abaixo disto (°C, temperatura do ar), sai vapor da respiração.
const BREATH_BELOW := 3.0

var game: GameMain
var session: Session
var api: Api
var ui: GameUi
var player: Player
var data: ChunkData
var airports: Airports
## O último corpo que o servidor mandou (BodyView em docs/API.md).
var body := {}
var fires := {}  # id → {"node": Node3D, "until": float (segundos do relógio local), "pos": Vector3}

var _hud: Control
var _temp_label: Label
var _icon: Label
var _bars := {}  # need → {"bar": ProgressBar, "row": Control}
var _buffs: Label
var _level: Label
var _dizzy: ColorRect
var _dizzy_amount := 0.0
var _cook: PanelContainer
var _cook_list: VBoxContainer
var _breath: CPUParticles3D
var _sweat: CPUParticles3D
var _shiver_t := 0.0
var _fire_mesh: Mesh
var _flame_mat: StandardMaterial3D
var _placements := {}  # tag → [msec, Array de pontos]
var _budget_t := 0.0
## Segundos que a lista de fogueiras, fontes e espelhos dos lotes fica em cache.
const PLACEMENTS_TTL := 0.5


func setup(g: GameMain, s: Session, a: Api, u: GameUi, p: Player, d: ChunkData, ap: Airports) -> void:
	game = g
	session = s
	api = a
	ui = u
	player = p
	data = d
	airports = ap
	_build_hud()
	_build_cook()
	_build_effects()


# --- Estado -------------------------------------------------------------------------------

## Corpo novo (mensagem body ou resposta de uma ação).
func set_body(v: Dictionary) -> void:
	if v.is_empty():
		return
	body = v
	player.speed_mult = float(v.get("speed", 1.0))
	_refresh_hud()


func quiet() -> bool:
	return bool(body.get("quiet", false))


## Liga ou desliga o modo tranquilo (F6). Fica salvo no servidor.
func set_quiet(on: bool) -> void:
	var r := await api.request("POST", "/body/quiet", {"on": on})
	if r["ok"]:
		set_body(r["data"])
		ui.toast("Modo tranquilo ligado: sem necessidades." if on else "Modo tranquilo desligado.")
	else:
		ui.toast(str(r["message"]))


func load_body() -> void:
	var r := await api.request("GET", "/body")
	if r["ok"]:
		set_body(r["data"])


## Aplica a resposta de uma ação do corpo (corpo, bolso, mensagem, fogueira).
func _apply_result(r: Dictionary) -> bool:
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return false
	var d: Dictionary = r["data"]
	if d.has("inventory"):
		session.set_inventory(d["inventory"], int(d.get("slots_used", 0)))
	if d.get("body") is Dictionary:
		set_body(d["body"])
	if d.get("fire") is Dictionary:
		add_fire(d["fire"])
	if not str(d.get("message", "")).is_empty():
		ui.toast(str(d["message"]))
	return true


# --- Ações --------------------------------------------------------------------------------

## Come ou bebe um item do bolso.
func consume(item: String) -> bool:
	var r := await api.request("POST", "/body/consume", {"item": item})
	if r["ok"]:
		player.play_action("pick-up")
	return _apply_result(r)


## Enche o cantil (perto de uma fonte ou de um poço).
func fill() -> bool:
	var r := await api.request("POST", "/body/fill", {})
	return _apply_result(r)


## Acende a fogueira do bolso no chão, na frente do personagem.
func light_fire() -> bool:
	var r := await api.request("POST", "/body/fire", {})
	if r["ok"]:
		player.play_action("interact-right")
	return _apply_result(r)


func cook(recipe: String) -> void:
	var r := await api.request("POST", "/body/cook", {"recipe": recipe, "times": 1})
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return
	var d: Dictionary = r["data"]
	session.set_inventory(d["inventory"], int(d.get("slots_used", 0)))
	ui.toast(str(d.get("message", "")), str(d.get("crafted", {}).get("item", "")))
	_fill_cook()


## Item com comida ou bebida?
func is_food(item: String) -> bool:
	var f: Variant = session.items.get(item, {}).get("food")
	return f is Dictionary and (float(f.get("hunger", 0)) > 0.0 or float(f.get("thirst", 0)) > 0.0)


# --- Lugares (fogueira, água, espelho) -------------------------------------------------------

## Centros dos objetos colocados (de todos os lotes carregados) com a tag. Fica em cache
## por PLACEMENTS_TTL segundos (a interação pergunta a cada quadro; fase 4.1).
func placements_with(tag: String) -> Array:
	var now := Time.get_ticks_msec()
	var c: Variant = _placements.get(tag)
	if c is Array and now - int(c[0]) < PLACEMENTS_TTL * 1000.0:
		return c[1]
	var out := _scan_placements(tag)
	_placements[tag] = [now, out]
	return out


func _scan_placements(tag: String) -> Array:
	var out: Array = []
	for lot: Dictionary in data.all_lots():
		var f := data.frame(int(lot["cell"]))
		for p: Dictionary in lot.get("placements", []):
			var it: Dictionary = session.items.get(str(p["item"]), {})
			if not (it.get("tags", []) as Array).has(tag):
				continue
			var fp := LotGeom.rotated(LotGeom.footprint_of(it), int(p.get("rot", 0)))
			out.append(LotGeom.point(f, lot, session.tile_size, float(p["x"]) + fp.x * 0.5, float(p["y"]) + fp.y * 0.5))
	return out


## Alvos do E perto: [{"type": "fire"|"water"|"mirror", "pos", "dist"}].
func targets_near(pos: Vector3) -> Array:
	var out: Array = []
	var fire_r := float(session.body.get("sources", {}).get("fire", {}).get("radius", 4.5)) * 0.6
	for f: Dictionary in fires.values():
		var d := (f["pos"] as Vector3).distance_to(pos)
		if d < fire_r:
			out.append({"type": "fire", "pos": f["pos"], "dist": d - 0.8})
	for p: Vector3 in placements_with("fire"):
		if p.distance_to(pos) < fire_r:
			out.append({"type": "fire", "pos": p, "dist": p.distance_to(pos) - 0.8})
	var reach := float(session.body.get("fill_reach", 3.0))
	var has_canteen := session.count("canteen") > 0 or session.count("canteen_half") > 0
	if has_canteen:
		for p: Vector3 in placements_with("water"):
			if p.distance_to(pos) < reach + 1.5:
				out.append({"type": "water", "pos": p, "dist": p.distance_to(pos) - 1.0})
		if airports:
			for cell: int in airports._built:
				var a: Dictionary = (airports._built[cell] as Node3D).get_meta("airport")
				if bool(a.get("small", false)):
					continue
				var fp := airports.plaza_point(a, -3.9, 3.2)
				if fp.distance_to(pos) < reach + 1.2:
					out.append({"type": "water", "pos": fp, "dist": fp.distance_to(pos) - 1.0})
	for p: Vector3 in placements_with("mirror"):
		if p.distance_to(pos) < 1.8:
			out.append({"type": "mirror", "pos": p, "dist": p.distance_to(pos)})
	return out


# --- Fogueiras no chão -------------------------------------------------------------------

func add_fire(f: Dictionary) -> void:
	var id := int(f["id"])
	if fires.has(id):
		(fires[id]["node"] as Node).queue_free()
	var fr := data.frame(int(f["cell"]))
	var pos := WorldData.frame_point(fr, float(f["x"]), float(f["y"]))
	var node := Node3D.new()
	node.name = "Fire_%d" % id
	add_child(node)
	node.global_transform = Transform3D(WorldData.frame_basis(fr, 0.0), pos)
	var lib := ModelLibrary.get_model("primitive:campfire")
	if not lib.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = lib["mesh"]
		node.add_child(mi)
	var flames := _flames()
	node.add_child(flames)
	# Luz sem sombra e de alcance pequeno; só as fire_lights mais perto acendem (_budget).
	var light := OmniLight3D.new()
	light.light_color = Color("ffb05a")
	light.light_energy = 1.4
	light.omni_range = 4.0
	light.shadow_enabled = false
	light.visible = false
	light.position = Vector3(0, 0.6, 0)
	node.add_child(light)
	fires[id] = {"node": node, "until": Time.get_ticks_msec() / 1000.0 + float(f.get("left", 600)), "pos": pos,
		"light": light, "flames": flames}
	_budget_t = 0.0


## Medição (profile-scene): esconde ou mostra todas as fogueiras.
func visible_fires(on: bool) -> void:
	for f: Dictionary in fires.values():
		(f["node"] as Node3D).visible = on


func set_fires(list: Array) -> void:
	for f: Dictionary in list:
		if not fires.has(int(f["id"])):
			add_fire(f)


func _flames() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(4, roundi(14 * float(Quality.current()["particles"])))
	p.emitting = false
	p.lifetime = 0.7
	p.mesh = _fire_mesh
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.position = Vector3(0, 0.15, 0)
	return p


# --- HUD ----------------------------------------------------------------------------------

func _build_hud() -> void:
	var card := PanelContainer.new()
	card.name = "Body"
	card.add_theme_stylebox_override("panel", UiStyle.panel(14, Color(1, 0.98, 0.94, 0.9), 10))
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.offset_right = -18
	card.offset_top = 18
	card.custom_minimum_size = Vector2(HUD_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var top := HBoxContainer.new()
	_temp_label = UiStyle.label("–", 20, UiStyle.INK)
	_icon = UiStyle.label("", 20, UiStyle.INK)
	top.add_child(_thermo_icon())
	top.add_child(_temp_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_icon)
	box.add_child(top)
	for need: Array in [["thirst", "Sede", Color("6db7e8")], ["comfort", "Conforto", Color("f2a65a")], ["hunger", "Fome", Color("8fcf7a")]]:
		var row := HBoxContainer.new()
		var l := UiStyle.label(need[1], 14, UiStyle.INK_SOFT)
		l.custom_minimum_size = Vector2(74, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(130, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.36, 0.27, 0.21, 0.15)
		bg.set_corner_radius_all(6)
		var fg := StyleBoxFlat.new()
		fg.bg_color = need[2]
		fg.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		row.add_child(bar)
		box.add_child(row)
		_bars[need[0]] = {"bar": bar, "row": row, "fill": fg, "color": need[2]}
	_level = UiStyle.label("", 14, UiStyle.ACCENT_DARK)
	box.add_child(_level)
	_buffs = UiStyle.label("", 14, UiStyle.INK)
	_buffs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_buffs)
	ui.add_child(card)
	_hud = card
	# Tela zonza (fome no mínimo): por cima de tudo, sem pegar cliques.
	_dizzy = ColorRect.new()
	_dizzy.name = "Dizzy"
	_dizzy.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dizzy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/dizzy.gdshader")
	_dizzy.material = sm
	_dizzy.visible = false
	ui.add_child(_dizzy)
	ui.move_child(_dizzy, 0)


func _thermo_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(18, 24)
	c.draw.connect(func() -> void:
		var col := Color("e86a6a")
		c.draw_rect(Rect2(6, 2, 6, 14), Color(0.36, 0.27, 0.21, 0.6), false, 1.5)
		c.draw_rect(Rect2(7.5, 8, 3, 9), col)
		c.draw_circle(Vector2(9, 18), 4.5, col))
	return c


func _refresh_hud() -> void:
	if _hud == null:
		return
	var q := quiet()
	var felt := float(body.get("felt", 0.0))
	_temp_label.text = "%.0f °C" % felt
	if bool(body.get("hot", false)):
		_icon.text = tr("calor")
		_icon.add_theme_color_override("font_color", Color("e8772e"))
	elif bool(body.get("cold", false)):
		_icon.text = tr("frio")
		_icon.add_theme_color_override("font_color", Color("4d8fe8"))
	else:
		_icon.text = ""
	var sources: Array = body.get("sources", [])
	if sources.has("fire"):
		_icon.text = (_icon.text + "  " if not _icon.text.is_empty() else "") + tr("fogueira")
	var max_v := float(body.get("max", 100.0))
	for need: String in _bars:
		var b: Dictionary = _bars[need]
		var v := float(body.get(need, max_v))
		(b["bar"] as ProgressBar).max_value = max_v
		(b["bar"] as ProgressBar).value = v
		# Discreto quando está bem; mais forte e avermelhado quando acaba.
		(b["row"] as Control).visible = not q
		(b["row"] as Control).modulate.a = 0.55 if v >= max_v * 0.9 else 1.0
		(b["fill"] as StyleBoxFlat).bg_color = (b["color"] as Color) if v > max_v * 0.2 else Color("e86a6a")
	match str(body.get("level", "")):
		"optimal":
			_level.text = tr("Tudo em dia: um pouco mais rápido!")
		"critical":
			_level.text = tr("Cansado: um pouco mais devagar")
		"quiet":
			_level.text = tr("Modo tranquilo")
		_:
			_level.text = ""
	var lines: PackedStringArray = []
	for bf: Dictionary in body.get("buffs", []):
		var left := int(bf.get("left", 0))
		lines.append("%s  %d:%02d" % [tr(str(bf.get("name", ""))), left / 60, left % 60])
	_buffs.text = "\n".join(lines)
	_buffs.visible = not lines.is_empty()


# --- Efeitos -----------------------------------------------------------------------------

func _build_effects() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.2)
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.albedo_color = Color("ffb347")
	_flame_mat.emission_enabled = true
	_flame_mat.emission = Color("ff8a2e")
	_flame_mat.emission_energy_multiplier = 1.6
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_flame_mat.vertex_color_use_as_albedo = true
	quad.material = _flame_mat
	_fire_mesh = BorderLines._baked(quad, _flame_mat)
	_breath = _puffs(Color(1, 1, 1, 0.55), Vector3(0, 0.78, -0.22), Vector3(0, 0.15, -1), 0.8)
	_sweat = _puffs(Color("9fd8ff"), Vector3(0, 0.95, 0), Vector3(0, -1, 0), 0.5)
	player.add_child(_breath)
	player.add_child(_sweat)


func _puffs(col: Color, at: Vector3, dir: Vector3, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var s := SphereMesh.new()
	s.radius = 0.035
	s.height = 0.07
	s.radial_segments = 6
	s.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.mesh = BorderLines._baked(s, m)
	p.amount = maxi(2, roundi(6 * float(Quality.current()["particles"])))
	p.lifetime = life
	p.position = at
	p.direction = dir
	p.spread = 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.4
	p.emitting = false
	p.local_coords = false
	return p


func _process(delta: float) -> void:
	if body.is_empty() or player == null:
		return
	var q := quiet()
	var air := float(body.get("air", 20.0))
	var cold := bool(body.get("cold", false)) and not q
	var hot := bool(body.get("hot", false)) and not q
	var fx := float(Quality.current()["particles"]) > 0.0
	_breath.emitting = fx and air < BREATH_BELOW and player.visible
	_sweat.emitting = fx and hot and player.visible
	_budget_t -= delta
	if _budget_t <= 0.0:
		_budget_t = 0.5
		_budget()
	# Treme de frio: o corpo balança de leve (só o visual).
	_shiver_t += delta
	player.shiver = 0.035 * sin(_shiver_t * 38.0) if cold else 0.0
	player.fanning = hot
	# Tontura: entra e sai devagar.
	var want := 1.0 if bool(body.get("dizzy", false)) and not q else 0.0
	_dizzy_amount = move_toward(_dizzy_amount, want, delta * 0.5)
	_dizzy.visible = _dizzy_amount > 0.01
	if _dizzy.visible:
		(_dizzy.material as ShaderMaterial).set_shader_parameter("amount", _dizzy_amount)
	# Fogueiras que apagaram.
	var now := Time.get_ticks_msec() / 1000.0
	for id: int in fires.keys():
		if now > float(fires[id]["until"]):
			(fires[id]["node"] as Node).queue_free()
			fires.erase(id)


## Orçamento das fogueiras (2×/s): só as fire_lights mais perto da câmera acendem a luz, e
## só as que estão a até fx_radius soltam fogo (as outras ficam com a lenha).
func _budget() -> void:
	var cam := get_viewport().get_camera_3d()
	var focus := cam.global_position if cam else player.global_position
	var q := Quality.current()
	var lights := int(q["fire_lights"])
	var fx_r := float(q["fx_radius"])
	var list: Array = fires.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector3).distance_squared_to(focus) < (b["pos"] as Vector3).distance_squared_to(focus))
	for i in list.size():
		var f: Dictionary = list[i]
		var d := (f["pos"] as Vector3).distance_to(focus)
		(f["light"] as OmniLight3D).visible = i < lights and d < fx_r
		(f["flames"] as CPUParticles3D).emitting = d < fx_r and float(q["particles"]) > 0.0


# --- Cozinhar ----------------------------------------------------------------------------

func _build_cook() -> void:
	_cook = PanelContainer.new()
	_cook.add_theme_stylebox_override("panel", UiStyle.panel(24))
	UiStyle.center(_cook)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_cook.add_child(box)
	box.add_child(UiStyle.header(UiStyle.label("Fogueira", 26), "Esc", func() -> void: _cook.visible = false))
	box.add_child(UiStyle.label("Receitas simples. Comidas melhores dão um bônus por alguns minutos.", 15, UiStyle.INK_SOFT))
	_cook_list = VBoxContainer.new()
	_cook_list.add_theme_constant_override("separation", 6)
	box.add_child(_cook_list)
	_cook.visible = false
	ui.add_window(_cook)


func open_cook() -> void:
	_fill_cook()
	_cook.visible = true
	ui.release_mouse()


func cook_open() -> bool:
	return _cook.visible


func _fill_cook() -> void:
	for c in _cook_list.get_children():
		c.queue_free()
	for r: Dictionary in session.recipes:
		if str(r.get("station", "")) != "fire":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var res := str(r["result"])
		var food: Dictionary = session.items.get(res, {}).get("food", {})
		var info := session.item_name(res)
		var parts: PackedStringArray = []
		if float(food.get("hunger", 0)) > 0:
			parts.append(tr("fome +%d") % int(food["hunger"]))
		if float(food.get("thirst", 0)) > 0:
			parts.append(tr("sede +%d") % int(food["thirst"]))
		if not str(food.get("buff", "")).is_empty():
			var bname := str(session.body.get("buffs", {}).get(str(food["buff"]), {}).get("name", food["buff"]))
			parts.append(tr("%s por %d min") % [tr(bname), int(food.get("minutes", 0))])
		var l := UiStyle.label("%s  ·  %s\n%s" % [info, ", ".join(parts), _ingredients(r)], 16)
		l.custom_minimum_size = Vector2(420, 0)
		row.add_child(l)
		var ok := session.can_afford(r["ingredients"])
		var b := UiStyle.button("Cozinhar", ok)
		b.disabled = not ok
		var id := str(r["id"])
		b.pressed.connect(func() -> void: cook(id))
		row.add_child(b)
		_cook_list.add_child(row)


func _ingredients(r: Dictionary) -> String:
	var out: PackedStringArray = []
	for k: String in r["ingredients"]:
		out.append("%d× %s (%d)" % [int(r["ingredients"][k]), session.cost_label(k), session.have_for(k)])
	return ", ".join(out)
