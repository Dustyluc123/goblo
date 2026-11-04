class_name PhotoMode
extends CanvasLayer
## Câmera fotográfica (fases 2.5 e 2.6): com a câmera na mão, o botão direito entra no modo
## foto, em primeira pessoa (a câmera vai para os olhos e o corpo some; moldura, roda do
## mouse dá zoom, o cursor continua preso). F troca para o selfie (câmera na frente do
## personagem, que faz pose; o cenário fica atrás) e volta. O clique tira a foto: salva em
## user://fotos/ (com miniatura) e registra na Goblopédia o assunto enquadrado, nos dois
## modos: animais, flores (as do servidor e as decorativas) e árvores de outono ou com neve.
## Botão direito ou Esc saem.
##
## Enquadramento (fase 4.2, ADR 0053; números em rules.json → photo): só vale o assunto
## centralizado (dentro da área do meio, `center` da largura e da altura), visível (nada
## sólido na frente) e com um tamanho mínimo na tela (`min_size` da altura); com mais de um,
## vale o mais centralizado. A mira no meio muda de cor e mostra o nome (ou "???") quando há
## um assunto assim; o servidor confere o mesmo (cone e distância). No selfie, vale o que
## está centralizado atrás do personagem.

## Altura aproximada (unidades) de uma flor e de uma árvore, para o tamanho na tela.
const FLOWER_SIZE := 0.45
const TREE_SIZE := 4.0
## Cor da mira com um assunto bem enquadrado.
const AIM_COLOR := Color("ffd166")

signal photo_taken(photo: String, entries: Array)

var game: GameMain
var camera: CameraRig
var player: Player
var session: Session
var ui: GameUi
var hud: Hud
var data: ChunkData
var animals: Animals
var vegetation: Vegetation
var tracker: CountryTracker
var world: WorldData
var api: Api
var active := false

var _frame: Control
var _hint: Label
var _aim_label: Label
var _flash: ColorRect
var _busy := false
## O assunto enquadrado agora ({} = nenhum), refeito a cada AIM_EVERY s.
var aim := {}
var _aim_timer := 0.0
const AIM_EVERY := 0.1
## Páginas já descobertas (id → true), da Goblopédia (GET /pedia ao entrar no modo foto).
var _known := {}
var _known_loaded := false


func _ready() -> void:
	layer = 3
	_frame = Control.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_frame)
	_frame.visible = false
	add_child(_frame)
	_hint = UiStyle.label("", 17, Color.WHITE)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_bottom = -40
	_frame.add_child(_hint)
	_aim_label = UiStyle.label("", 18, AIM_COLOR)
	_aim_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_aim_label.add_theme_constant_override("outline_size", 6)
	_aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_aim_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_aim_label.offset_top = 34
	_aim_label.offset_bottom = 60
	_frame.add_child(_aim_label)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


## Moldura de foto: cantos arredondados, retícula no meio e a área de enquadramento.
func _draw_frame() -> void:
	var s := _frame.size
	var m := 36.0
	var l := 70.0
	var w := 4.0
	var c := Color(1, 1, 1, 0.9)
	for corner: Array in [[Vector2(m, m), Vector2(1, 1)], [Vector2(s.x - m, m), Vector2(-1, 1)],
			[Vector2(m, s.y - m), Vector2(1, -1)], [Vector2(s.x - m, s.y - m), Vector2(-1, -1)]]:
		var p: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		_frame.draw_line(p, p + Vector2(l * d.x, 0), c, w, true)
		_frame.draw_line(p, p + Vector2(0, l * d.y), c, w, true)
	var center := s * 0.5
	# Mira: branca; dourada e mais grossa com um assunto bem enquadrado.
	var mc := AIM_COLOR if not aim.is_empty() else Color(1, 1, 1, 0.75)
	var mw := 3.0 if not aim.is_empty() else 2.0
	_frame.draw_arc(center, 14.0, 0, TAU, 32, mc, mw, true)
	_frame.draw_line(center - Vector2(24, 0), center - Vector2(16, 0), mc, mw)
	_frame.draw_line(center + Vector2(16, 0), center + Vector2(24, 0), mc, mw)
	_frame.draw_line(center - Vector2(0, 24), center - Vector2(0, 16), mc, mw)
	_frame.draw_line(center + Vector2(0, 16), center + Vector2(0, 24), mc, mw)
	var k := center_frac()
	var box := Rect2(center - s * k * 0.5, s * k)
	_frame.draw_rect(box, Color(mc.r, mc.g, mc.b, 0.3), false, 1.5)
	_frame.draw_string(ThemeDB.fallback_font, Vector2(m + 8, s.y - m - 12), tr("zoom %d°") % int(camera.photo_fov), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))


func _process(_delta: float) -> void:
	if active and (session.equipped != "camera" or ui.menu_open() or game.building() or not player.visible):
		exit()
	if active:
		# O personagem olha para onde a câmera olha (primeira pessoa) ou para ela (selfie).
		player.face(player.global_position + camera.photo_heading())
		_aim_timer -= _delta
		if _aim_timer <= 0.0:
			_aim_timer = AIM_EVERY
			_update_aim()
		_frame.queue_redraw()


## Números do enquadramento (rules.json → photo).
func _photo_rules() -> Dictionary:
	return session.rules.get("photo", {}) if session and session.rules.get("photo") is Dictionary else {}


func center_frac() -> float:
	return float(_photo_rules().get("center", 0.35))


func _max_dist(kind: String) -> float:
	return float((_photo_rules().get("max_dist", {}) as Dictionary).get(kind, {"animal": 40.0, "flower": 12.0, "tree": 34.0}[kind]))


## Refaz a mira: o assunto enquadrado agora e o nome dele (ou "???").
func _update_aim() -> void:
	var list := find_subjects()
	aim = list[0] if not list.is_empty() else {}
	if aim.is_empty():
		_aim_label.text = ""
		return
	_aim_label.text = entry_name(str(aim["entry"])) if _known.has(str(aim["entry"])) else "???"


## Nome da página da Goblopédia.
func entry_name(entry: String) -> String:
	for e: Dictionary in session.pedia_catalog:
		if str(e.get("id", "")) == entry:
			return tr(str(e.get("name", entry)))
	return entry


## O que já foi descoberto (uma vez por sessão; atualizado a cada registro).
func _load_known() -> void:
	if _known_loaded or api == null:
		return
	_known_loaded = true
	var r: Dictionary = await api.request("GET", "/pedia")
	if r["ok"]:
		for e: Dictionary in r["data"].get("entries", []):
			if bool(e.get("discovered", false)):
				_known[str(e["id"])] = true


## O cartão do corpo (temperatura e necessidades) some do visor no modo foto.
func _body_card(on: bool) -> void:
	if game and game.body and is_instance_valid(game.body._hud):
		game.body._hud.visible = on


## Selfie ligado (câmera na frente do personagem)?
func selfie() -> bool:
	return active and camera.photo_selfie


## Troca entre primeira pessoa e selfie.
func set_selfie(on: bool) -> void:
	if not active:
		return
	camera.set_selfie(on)
	player.set_body_visible(on)
	player.set_pose(on)
	_update_hint()


func _update_hint() -> void:
	_hint.text = tr("clique: tirar foto  ·  roda: zoom  ·  F: %s  ·  botão direito ou Esc: sair") % ("primeira pessoa" if selfie() else "selfie")


func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	if not active:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT \
				and session.equipped == "camera" and not ui.menu_open() and not game.building():
			enter()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		exit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo() \
			and (event as InputEventKey).keycode == KEY_F:
		set_selfie(not selfie())
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				exit()
			MOUSE_BUTTON_LEFT:
				take_photo()
			MOUSE_BUTTON_WHEEL_UP:
				camera.photo_zoom(4.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				camera.photo_zoom(-4.0)
		get_viewport().set_input_as_handled()


func enter() -> void:
	active = true
	camera.set_photo_mode(true)
	player.set_body_visible(false)  # primeira pessoa: o corpo sai da frente
	player.set_pose(false)
	_frame.visible = true
	hud.visible = false  # o visor fica limpo: só a moldura
	_body_card(false)
	aim = {}
	_aim_label.text = ""
	_aim_timer = 0.0
	_update_hint()
	ui.show_prompt("")
	_load_known()


func exit() -> void:
	if not active:
		return
	active = false
	camera.set_photo_mode(false)
	player.set_body_visible(true)
	player.set_pose(false)
	_frame.visible = false
	hud.visible = true
	_body_card(true)


## Tira a foto: acha o assunto enquadrado, fotografa sem a moldura e sem a interface, salva e
## registra na Goblopédia (só o mais centralizado). Devolve os registros (testes).
func take_photo() -> Array:
	if _busy:
		return []
	_busy = true
	var subjects := find_subjects().slice(0, 1)
	var layers: Array = [_frame, hud, ui]
	var was: Array = layers.map(func(n: Variant) -> bool: return n.visible)
	for n: Variant in layers:
		n.visible = false
	var img: Image = null
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		img = get_viewport().get_texture().get_image()
	else:
		await get_tree().process_frame  # sem desenho nos testes headless
	for i in layers.size():
		layers[i].visible = was[i]
	_flash.color = Color(1, 1, 1, 0.85)
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.35)
	var here := WorldData.vec_to_lat_lon(player.global_position)
	var path := PediaPhotos.save(session.photo_account(), img, {"country": tracker.current,
		"country_name": game.country_name(tracker.current), "biome": world.biome_names[world.biomes[player.cell_id]],
		"lat": snappedf(here.x, 0.01), "lon": snappedf(here.y, 0.01)})
	var registered: Array = []
	game.net_act("photo")
	var cam_now := get_viewport().get_camera_3d()
	var look := -cam_now.global_basis.z if cam_now else Vector3.ZERO
	var cam_pos := cam_now.global_position if cam_now else Vector3.ZERO
	for s: Dictionary in subjects:
		var at: Vector3 = s["at"]
		var r := await api.request("POST", "/pedia/register", {"entry": s["entry"], "country": tracker.current,
			"biome": world.biome_names[world.biomes[player.cell_id]], "look": [look.x, look.y, look.z],
			"cam": [cam_pos.x, cam_pos.y, cam_pos.z], "at": [at.x, at.y, at.z]})
		if not r["ok"]:
			ui.toast(str(r["message"]))
			continue
		var res: Dictionary = r["data"]
		registered.append(res)
		_known[str(s["entry"])] = true
		PediaPhotos.tag(session.photo_account(), path, str(s["entry"]))
		if bool(res["first"]):
			session.set_coins(int(res["coins"]))
			ui.toast("%s  +%s" % [res["message"], session.coins_text(int(res["reward"]))])
		else:
			ui.toast(str(res["message"]))
	if subjects.is_empty():
		ui.toast(tr("Foto salva!") if not path.is_empty() else tr("Clique!"))
	_busy = false
	_update_aim()
	photo_taken.emit(path, registered)
	return registered


## Os assuntos bem enquadrados agora: [{"entry", "kind", "at", "dist", "center", "size"}],
## uma vez cada coisa, o mais centralizado primeiro. Bem enquadrado = na frente da câmera, a
## até max_dist do tipo, dentro da área central, com o tamanho mínimo na tela e visível.
func find_subjects() -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return []
	var vp := get_viewport().get_visible_rect().size
	var half := center_frac() * 0.5
	var min_size := float(_photo_rules().get("min_size", 0.05))
	var eye := cam.global_position
	var found := {}
	var consider := func(entry: String, kind: String, pos: Vector3, height: float, ok := Callable()) -> void:
		if cam.is_position_behind(pos):
			return
		var dist := eye.distance_to(pos)
		if dist > _max_dist(kind):
			return
		var sp := cam.unproject_position(pos) / vp - Vector2(0.5, 0.5)
		if absf(sp.x) > half or absf(sp.y) > half:
			return
		var up := pos.normalized()
		var top := cam.unproject_position(pos + up * height * 0.5)
		var bottom := cam.unproject_position(pos - up * height * 0.5)
		var size := top.distance_to(bottom) / vp.y
		if size < min_size:
			return
		if ok.is_valid() and not ok.call():
			return
		if not _visible(eye, pos, maxf(0.6, height * 0.4)):
			return
		var score := sp.length()
		if not found.has(entry) or score < float(found[entry]["center"]):
			found[entry] = {"entry": entry, "kind": kind, "at": pos, "dist": dist, "center": score, "size": size}
	if animals:
		for id: int in animals._active:
			var e: Dictionary = animals._active[id]
			var sp := str(e["animal"]["species"])
			var node: Node3D = e["node"]
			var h := float(animals.species[sp]["height"])
			consider.call(sp, "animal", node.global_position + node.global_position.normalized() * h * 0.55, h)
	var here := player.global_position
	var flowers := _flower_entries()
	for o: Dictionary in data.objects_near(here, maxf(_max_dist("tree"), _max_dist("flower")) + 6.0):
		var kind := str(o["kind"])
		var up := (o["up"] as Vector3)
		if kind == "flower" and flowers.has(str(o.get("item", ""))):
			consider.call(str(o["item"]), "flower", (o["pos"] as Vector3) + up * FLOWER_SIZE * 0.4, FLOWER_SIZE)
		elif kind == "tree" and vegetation:
			var entry := vegetation.season_entry(o)
			if not entry.is_empty():
				consider.call(entry, "tree", (o["pos"] as Vector3) + up * TREE_SIZE * 0.5, TREE_SIZE)
	# Flores decorativas: a espécie pelo modelo, se ela nasce ali agora (o servidor confere
	# o mesmo: flower_biomes do /content).
	if vegetation:
		var by_model := _flower_models()
		for f: Array in vegetation.decor_flowers_near(here, _max_dist("flower") + 6.0):
			var item := str(by_model.get(f[1], ""))
			var pos: Vector3 = f[0]
			if not item.is_empty() and flowers.has(item):
				consider.call(item, "flower", pos + pos.normalized() * FLOWER_SIZE * 0.4, FLOWER_SIZE,
					func() -> bool: return _grows_here(item, pos))
	var out: Array = found.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["center"]) < float(b["center"]))
	return out


## Páginas de flores da Goblopédia (id → true).
func _flower_entries() -> Dictionary:
	var out := {}
	for e: Dictionary in session.pedia_catalog:
		if str(e.get("kind", "")) == "flower":
			out[str(e["id"])] = true
	return out


## Modelo → item das flores (as decorativas usam os mesmos modelos dos itens).
func _flower_models() -> Dictionary:
	var out := {}
	for id: String in session.items:
		var it: Dictionary = session.items[id]
		if (it.get("tags", []) as Array).has("flower"):
			out[str(it.get("model", ""))] = id
	return out


## A flor nasce na célula do ponto agora (bioma e estação, com a folga da virada)? A mesma
## regra do servidor (game.FlowerGrows com seasonsAround).
func _grows_here(item: String, pos: Vector3) -> bool:
	var grows: Dictionary = session.flower_biomes
	var cell := world.find_cell(pos, player.cell_id)
	if cell < 0:
		return false
	var by_item: Dictionary = grows.get(world.biome_names[world.biomes[cell]], {})
	if not by_item.has(item):
		return false
	var seasons: Array = by_item[item]
	if seasons.has(""):
		return true
	var now: float = game.season_now()
	for dt in [0.0, -Seasons.BLEND_DAYS, Seasons.BLEND_DAYS]:
		var se := Seasons.season_at(now + dt * 86400.0, world.lats[cell]) if Seasons.seasonal_biome(world.biomes[cell]) else "none"
		if seasons.has(se):
			return true
	return false


## Nada sólido entre a câmera e a coisa (árvores, pedras, casas e o chão têm colisão; os
## animais não). Bater a até `near` da coisa conta como ver (o tronco da própria árvore).
func _visible(from: Vector3, to: Vector3, near := 1.0) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < near
