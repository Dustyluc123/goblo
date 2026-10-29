class_name Interaction
extends Node
## Tecla E perto de um objeto: sacudir árvore, cortar com machado, quebrar pedra com
## picareta, colher flor e frutinhas, pegar pedrinha e galho, abrir a bancada.
##
## O cliente só pede ("sacudi a árvore X"); o servidor confere o limite do dia e devolve
## o que o jogador ganhou e o inventário novo. Aqui ficam o aviso na tela ("E: sacudir"),
## a animação do personagem e os efeitos (árvore balançando, item fazendo "pop").

## Até onde o personagem alcança, por tipo (a partir do centro do objeto).
const REACH := {"tree": 1.7, "rock": 1.6, "bush": 1.4, "flower": 1.1, "pebble": 1.0, "branch": 1.0}
const WORKBENCH_REACH := 1.8
## Até onde alcança um animal (a partir da borda dele).
const ANIMAL_REACH := 1.3

var game: GameMain
var player: Player
var data: ChunkData
var session: Session
var api: Api
var ui: GameUi
var vegetation: Vegetation
var icons: ItemIcons
var neighborhood: Neighborhood
var animals: Animals
## Alvo atual: {"type": "object", "obj": {...}} ou {"type": "workbench", "pos": Vector3}.
var target := {}

var _timer := 0.0
var _busy := false


func _process(delta: float) -> void:
	if player == null or not player.visible or data == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	target = _find_target()
	ui.show_prompt(_prompt_text(target) if not ui.blocking() and not game.building() else "")


func _find_target() -> Dictionary:
	var pos := player.global_position
	var fwd := -player.global_basis.z
	var best := {}
	var best_score := INF
	for o: Dictionary in data.objects_near(pos, 2.6):
		var kind := str(o["kind"])
		if not REACH.has(kind):
			continue
		var to: Vector3 = (o["pos"] as Vector3) - pos
		var dist := to.length()
		var reach: float = REACH[kind] * maxf(1.0, float(o["scale"]) * (0.6 if kind == "rock" else 0.0))
		if dist > reach:
			continue
		var score := dist - fwd.dot(to.normalized()) * 0.6
		if score < best_score:
			best_score = score
			best = {"type": "object", "obj": o}
	if animals:
		var an := animals.nearest(pos, ANIMAL_REACH)
		if not an.is_empty():
			var dist := (an["pos"] as Vector3).distance_to(pos) - 0.4
			if dist < best_score:
				best_score = dist
				best = {"type": "animal", "animal": an}
	for kind: String in ["workbench", "sell_box"]:
		for wb: Vector3 in _own_placements(kind):
			var dist := wb.distance_to(pos)
			if dist < WORKBENCH_REACH and dist - 0.3 < best_score:
				best_score = dist - 0.3
				best = {"type": kind, "pos": wb}
	return best


## Posições dos objetos de um tipo (bancada, caixa de vendas) no lote do jogador.
func _own_placements(item: String) -> Array:
	var out: Array = []
	var lot := session.lot()
	if lot.is_empty():
		return out
	var node := neighborhood.lot_node(int(lot["id"]))
	if node == null:
		return out
	for c in node.get_children():
		if c is MeshInstance3D and c.has_meta("placement") and str((c.get_meta("placement") as Dictionary)["item"]) == item:
			out.append((c as Node3D).global_position)
	return out


## Qual ação o E faz neste objeto, com a ferramenta que está na mão.
func _action(o: Dictionary) -> String:
	match str(o["kind"]):
		"tree":
			if session.equipped == "axe" and o.get("chop", false):
				return "chop"
			return "shake"
		"rock":
			return "mine" if session.equipped == "pickaxe" else ""
		"bush":
			return "shake"
		"flower", "pebble", "branch":
			return "pick"
	return ""


func _prompt_text(t: Dictionary) -> String:
	if t.is_empty():
		return ""
	if t["type"] == "workbench":
		return "E: bancada"
	if t["type"] == "sell_box":
		return "E: caixa de vendas"
	if t["type"] == "animal":
		var an: Dictionary = t["animal"]
		if _wants_fruit(an):
			return "%s  ·  E: dar frutinha" % an["name"]
		return "%s  ·  E: fazer carinho" % an["name"]
	var o: Dictionary = t["obj"]
	var st: Dictionary = o.get("state", {}) if o.get("state") is Dictionary else {}
	match str(o["kind"]):
		"tree":
			if session.equipped == "axe" and o.get("chop", false):
				var left := 3 - int(st.get("chop", 0))
				return "E: cortar (%d hoje)" % left if left > 0 else "Esta árvore já deu madeira hoje"
			if int(st.get("shake", 0)) >= 1:
				return "Já sacudida hoje" + ("  ·  segure o machado (1–5) para cortar" if session.count("axe") > 0 and o.get("chop", false) else "")
			return "E: sacudir"
		"rock":
			if session.equipped != "pickaxe":
				return "Pedra grande  ·  precisa de uma picareta" if session.count("pickaxe") == 0 else "Pedra grande  ·  segure a picareta (1–5)"
			var left := 3 - int(st.get("mine", 0))
			return "E: quebrar (%d hoje)" % left if left > 0 else "Esta pedra já deu tudo hoje"
		"bush":
			return "E: colher frutinhas" if int(st.get("shake", 0)) == 0 else "Já colhido hoje"
		"flower":
			return "E: colher flor"
		"pebble":
			return "E: pegar pedrinha"
		"branch":
			return "E: pegar galho"
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo() and not ui.menu_open() and not game.building():
		get_viewport().set_input_as_handled()
		interact()


## Faz a ação no alvo atual (também usado pelos testes automáticos).
func interact() -> Dictionary:
	if _busy or target.is_empty():
		return {}
	if target["type"] == "workbench":
		player.face(target["pos"])
		ui.craft.open()
		return {"ok": true}
	if target["type"] == "sell_box":
		player.face(target["pos"])
		ui.sell.open()
		return {"ok": true}
	if target["type"] == "animal":
		return await _animal(target["animal"])
	var o: Dictionary = target["obj"]
	var action := _action(o)
	if action.is_empty():
		ui.toast(_prompt_text(target))
		return {}
	player.face(o["pos"])
	player.play_action("pick-up" if action == "pick" else "interact-right")
	_busy = true
	var r := await api.request("POST", "/interact", {"object": o["id"], "action": action})
	_busy = false
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return r
	var res: Dictionary = r["data"]
	session.set_inventory(res["inventory"], int(res["slots_used"]))
	if action == "shake" or action == "chop" or action == "mine":
		_wobble(o, 0.12 if action == "shake" else 0.06)
	data.set_object_state(o["id"], res["state"])
	for g: Dictionary in res.get("gained", []):
		ui.toast("+%d %s" % [int(g["count"]), session.item_name(g["item"])], g["item"])
		_pop(o, str(g["item"]))
	if (res.get("gained", []) as Array).is_empty() and str(res.get("message", "")) != "":
		ui.toast(str(res["message"]))
	_timer = 0.0
	return r


## Com frutinha no bolso, o E dá a frutinha (o animal vira amigo); com o amigo, faz carinho.
func _wants_fruit(an: Dictionary) -> bool:
	return session.count("berries") > 0 and not animals.is_friend(int(an["id"]))


## Carinho ou frutinha. Nunca há forma de machucar os animais.
func _animal(an: Dictionary) -> Dictionary:
	var id := int(an["id"])
	player.face(an["pos"])
	player.play_action("interact-right")
	if not _wants_fruit(an):
		animals.pet(id)
		return {"ok": true, "action": "pet"}
	if id < 0:  # animal criado pelo modo dev: só existe aqui
		animals.fed(id)
		return {"ok": true, "action": "feed"}
	_busy = true
	var r := await api.request("POST", "/animal/feed", {"animal": id})
	_busy = false
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return r
	session.set_inventory(r["data"]["inventory"], int(r["data"]["slots_used"]))
	animals.fed(id)
	ui.toast(str(r["data"]["message"]), "berries")
	game.on_animal_fed(str(r["data"]["species"]))
	_timer = 0.0
	return r


## Árvore (ou pedra) balançando: esconde a instância do MultiMesh e anima uma cópia.
func _wobble(o: Dictionary, strength: float) -> void:
	var lib := ModelLibrary.get_model(str(o.get("drawn_model", o["model"])))
	if lib.is_empty():
		return
	vegetation.set_object_visible(o["id"], false)
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_transform = Transform3D((o["basis"] as Basis).orthonormalized(), o["pos"])
	var mi := MeshInstance3D.new()
	mi.mesh = lib["mesh"]
	mi.scale = Vector3.ONE * float(o["scale"])
	pivot.add_child(mi)
	var side := randf_range(0, TAU)
	var axis := Vector3(cos(side), 0, sin(side))
	var base := pivot.basis
	var tw := pivot.create_tween()
	tw.tween_method(func(t: float) -> void:
		pivot.basis = base * Basis(axis, sin(t * TAU * 2.5) * strength * (1.0 - t)), 0.0, 1.0, 0.8)
	tw.tween_callback(func() -> void:
		pivot.queue_free()
		var cur := data.object(o["id"])
		vegetation.set_object_visible(o["id"], cur.is_empty() or not cur["hidden"]))


## Item fazendo "pop": o ícone sobe do objeto, pula e voa até o personagem.
func _pop(o: Dictionary, item: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var s := Sprite3D.new()
	s.texture = icons.icon(item)
	s.pixel_size = 0.006
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.render_priority = 10
	add_child(s)
	var up: Vector3 = o["up"]
	var start: Vector3 = (o["pos"] as Vector3) + up * 0.8
	s.global_position = start
	s.scale = Vector3.ONE * 0.2
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "global_position", start + up * 0.8, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float) -> void:
		var dest := player.global_position + player.global_position.normalized() * 0.9
		s.global_position = (start + up * 0.8).lerp(dest, t)
		s.scale = Vector3.ONE * lerpf(1.0, 0.3, t), 0.0, 1.0, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(s.queue_free)
