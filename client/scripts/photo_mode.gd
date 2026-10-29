class_name PhotoMode
extends CanvasLayer
## Câmera fotográfica (fases 2.5 e 2.6): com a câmera na mão, o botão direito entra no modo
## foto, em primeira pessoa (a câmera vai para os olhos e o corpo some; moldura, roda do
## mouse dá zoom, o cursor continua preso). F troca para o selfie (câmera na frente do
## personagem, que faz pose; o cenário fica atrás) e volta. O clique tira a foto: salva em
## user://fotos/ (com miniatura) e registra na Goblopédia o que estiver enquadrado (perto
## do centro e visível), nos dois modos: animais, a flor azul rara e árvores de outono ou
## com neve. Botão direito ou Esc saem.

## Área do centro da tela em que a coisa precisa estar (fração da tela).
const CENTER_W := 0.32
const CENTER_H := 0.36
## Distância máxima por tipo.
const MAX_DIST := {"animal": 38.0, "flower": 9.0, "tree": 30.0}

signal photo_taken(path: String, entries: Array)

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
var _flash: ColorRect
var _busy := false


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
	_frame.draw_arc(center, 14.0, 0, TAU, 32, Color(1, 1, 1, 0.75), 2.0, true)
	_frame.draw_line(center - Vector2(24, 0), center - Vector2(16, 0), c, 2.0)
	_frame.draw_line(center + Vector2(16, 0), center + Vector2(24, 0), c, 2.0)
	_frame.draw_line(center - Vector2(0, 24), center - Vector2(0, 16), c, 2.0)
	_frame.draw_line(center + Vector2(0, 16), center + Vector2(0, 24), c, 2.0)
	var box := Rect2(center - Vector2(s.x * CENTER_W, s.y * CENTER_H) * 0.5, Vector2(s.x * CENTER_W, s.y * CENTER_H))
	_frame.draw_rect(box, Color(1, 1, 1, 0.22), false, 1.5)
	_frame.draw_string(ThemeDB.fallback_font, Vector2(m + 8, s.y - m - 12), "zoom %d°" % int(camera.photo_fov), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))


func _process(_delta: float) -> void:
	if active and (session.equipped != "camera" or ui.menu_open() or game.building() or not player.visible):
		exit()
	if active:
		# O personagem olha para onde a câmera olha (primeira pessoa) ou para ela (selfie).
		player.face(player.global_position + camera.photo_heading())
		_frame.queue_redraw()


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
	_hint.text = "clique: tirar foto  ·  roda: zoom  ·  F: %s  ·  botão direito ou Esc: sair" % ("primeira pessoa" if selfie() else "selfie")


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
	_update_hint()
	ui.show_prompt("")


func exit() -> void:
	if not active:
		return
	active = false
	camera.set_photo_mode(false)
	player.set_body_visible(true)
	player.set_pose(false)
	_frame.visible = false
	hud.visible = true


## Tira a foto: acha o que está enquadrado, fotografa sem a moldura e sem a interface,
## salva e registra na Goblopédia. Devolve as coisas registradas (testes).
func take_photo() -> Array:
	if _busy:
		return []
	_busy = true
	var subjects := find_subjects()
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
	var path := PediaPhotos.save(img)
	var registered: Array = []
	for s: Dictionary in subjects:
		var r := await api.request("POST", "/pedia/register", {"entry": s["entry"], "country": tracker.current,
			"biome": world.biome_names[world.biomes[player.cell_id]]})
		if not r["ok"]:
			ui.toast(str(r["message"]))
			continue
		var res: Dictionary = r["data"]
		registered.append(res)
		PediaPhotos.set_first(session.profile, str(s["entry"]), path)
		if bool(res["first"]):
			session.set_coins(int(res["coins"]))
			ui.toast("%s  +%s" % [res["message"], session.coins_text(int(res["reward"]))])
		else:
			ui.toast(str(res["message"]))
	if subjects.is_empty():
		ui.toast("Foto salva!" if not path.is_empty() else "Clique!")
	_busy = false
	photo_taken.emit(path, registered)
	return registered


## O que está enquadrado agora: [{"entry", "dist", "center"}], uma vez cada coisa,
## no máximo 3, as mais perto do centro primeiro.
func find_subjects() -> Array:
	var cam := get_viewport().get_camera_3d()
	var vp := get_viewport().get_visible_rect().size
	var found := {}
	var consider := func(entry: String, kind: String, pos: Vector3) -> void:
		if cam.is_position_behind(pos):
			return
		var dist := cam.global_position.distance_to(pos)
		if dist > float(MAX_DIST[kind]):
			return
		var sp := cam.unproject_position(pos) / vp - Vector2(0.5, 0.5)
		if absf(sp.x) > CENTER_W * 0.5 or absf(sp.y) > CENTER_H * 0.5:
			return
		if not _visible(cam.global_position, pos):
			return
		var score := sp.length()
		if not found.has(entry) or score < float(found[entry]["center"]):
			found[entry] = {"entry": entry, "dist": dist, "center": score}
	if animals:
		for id: int in animals._active:
			var e: Dictionary = animals._active[id]
			var sp := str(e["animal"]["species"])
			var node: Node3D = e["node"]
			var h := float(animals.species[sp]["height"])
			consider.call(sp, "animal", node.global_position + node.global_position.normalized() * h * 0.55)
	var here := player.global_position
	for o: Dictionary in data.objects_near(here, MAX_DIST["tree"]):
		var kind := str(o["kind"])
		if kind == "flower" and str(o.get("item", "")) == "flower_blue":
			consider.call("flower_blue", "flower", (o["pos"] as Vector3) + (o["up"] as Vector3) * 0.15)
		elif kind == "tree" and vegetation:
			var entry := vegetation.season_entry(o)
			if not entry.is_empty():
				consider.call(entry, "tree", (o["pos"] as Vector3) + (o["up"] as Vector3) * 2.0)
	var out: Array = found.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["center"]) < float(b["center"]))
	return out.slice(0, 3)


## Nada sólido entre a câmera e a coisa (árvores e casas têm colisão; os animais não).
func _visible(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 1.0
