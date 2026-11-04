class_name CaveGame
extends Node3D
## Cavernas no cliente (fase 4.5, ADR 0056). No globo: desenha as bocas perto do jogador e o
## E na boca entra. Na caverna: o mapa separado (CaveWorld), minérios (golpes com a
## picareta), tochas na mão e nas paredes, a fornalha antiga, a saída e o golem com os
## ataques avisados no chão. As regras são do servidor; aqui só se mostra e se pede.

signal entered(cave: int)
signal exited

const MOUTH_RADIUS := 140.0
const MOUTH_REACH := 3.6
const ORE_REACH := 2.6
const BOSS_REACH := 5.5
const TORCH_REACH := 2.2
const FALL_RESCUE := 6.0
const ROOM_LIGHTS := 4

var game: GameMain
var session: Session
var api: Api
var ui: GameUi
var player: Player
var camera: CameraRig
var world: WorldData
var data: ChunkData

var caves: Array = []
var active := false
var cave_id := -1
var view := {}
var cw: CaveWorld
var mined := {}
var torches: Array = []
var boss := {"phase": "idle", "hits": 0, "max": 3, "dodged": 0, "need": 6, "won": false, "name": ""}

var _mouths := {}  # id → Node3D
var _mouth_timer := 0.0
var _torch_nodes := {}  # id → Node3D
var _warnings: Array = []  # {"node", "at", "r", "start"}
var _player_light: OmniLight3D
var _fade: ColorRect
var _boss_label: Label
var _zzz: Label3D
var _busy := false
var _light_timer := 0.0
var _boss_anim := ""


func setup(g: GameMain, s: Session, a: Api, u: GameUi, p: Player, c: CameraRig, w: WorldData, d: ChunkData) -> void:
	game = g
	session = s
	api = a
	ui = u
	player = p
	camera = c
	world = w
	data = d
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.03, 0.05, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_boss_label = UiStyle.label("", 20)
	_boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_label.position = Vector2(-260, 96)
	_boss_label.custom_minimum_size = Vector2(520, 0)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_boss_label.add_theme_constant_override("outline_size", 6)
	_boss_label.add_theme_color_override("font_color", Color("fff6e4"))
	_boss_label.visible = false
	layer.add_child(_boss_label)
	_player_light = OmniLight3D.new()
	_player_light.light_color = Color("ffd59a")
	_player_light.omni_range = 9.0
	_player_light.light_energy = 1.3
	_player_light.shadow_enabled = false
	_player_light.visible = false
	add_child(_player_light)
	var r := await api.request("GET", "/caves")
	if r["ok"]:
		caves = r["data"]["caves"]


# --- Atualização por quadro ------------------------------------------------------------------

func update(delta: float) -> void:
	_update_player_light()
	if not active:
		_mouth_timer -= delta
		if _mouth_timer <= 0.0:
			_mouth_timer = 0.5
			_update_mouths()
		return
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.5
		_budget_lights()
	_update_warnings()
	_update_boss_label()
	if _zzz:
		_zzz.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 400.0)


## Luz na mão (tocha) ou na cabeça (capacete com luz), em qualquer lugar.
func _update_player_light() -> void:
	var torch := str(session.items.get(session.equipped, {}).get("tool", "")) == "torch"
	var helmet := str(player.look_view.get("wear", {}).get("head", {}).get("item", "")) == "lamp_helmet" if player.look_view.get("wear") is Dictionary else false
	_player_light.visible = torch or helmet
	if _player_light.visible:
		var up := player.global_position.normalized()
		_player_light.global_position = player.global_position + up * (1.9 if helmet and not torch else 1.4) - player.global_basis.z * 0.4
		_player_light.light_color = Color("ffd59a") if torch else Color("f4f6ff")
		_player_light.light_energy = (1.5 if active else 0.9) * (1.0 + 0.06 * sin(Time.get_ticks_msec() / 90.0) if torch else 1.0)


## Bocas de caverna perto do jogador (no globo).
func _update_mouths() -> void:
	var pos := player.global_position
	var want := {}
	for cv: Dictionary in caves:
		var cell := int(cv["cell"])
		var c: Vector3 = world.centers[cell]
		if c.dot(pos.normalized()) < cos(MOUTH_RADIUS / world.radius):
			continue
		want[int(cv["id"])] = cv
	for id: int in _mouths.keys():
		if not want.has(id):
			(_mouths[id] as Node3D).queue_free()
			_mouths.erase(id)
	for id: int in want:
		if _mouths.has(id):
			continue
		var cv: Dictionary = want[id]
		var f := data.frame(int(cv["cell"]))
		var mi := MeshInstance3D.new()
		mi.mesh = ModelLibrary.get_model("primitive:cave_mouth")["mesh"]
		add_child(mi)
		var up: Vector3 = f["center"]
		var dir := ((f["east"] as Vector3) * cos(float(cv["yaw"])) + (f["north"] as Vector3) * sin(float(cv["yaw"]))).normalized()
		mi.global_transform = Transform3D(Basis(up.cross(dir), up, dir), WorldData.frame_point(f, float(cv["x"]), float(cv["y"])))
		mi.set_meta("cave", cv)
		_mouths[id] = mi


func mouth_point(cv: Dictionary) -> Vector3:
	var f := data.frame(int(cv["cell"]))
	return WorldData.frame_point(f, float(cv["x"]), float(cv["y"]))


func _budget_lights() -> void:
	if cw == null:
		return
	var pos := player.global_position
	var list: Array = cw.lights.duplicate()
	list.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
		return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
	for i in list.size():
		(list[i] as OmniLight3D).visible = i < ROOM_LIGHTS
	var tl: Array = []
	for id: int in _torch_nodes:
		tl.append(_torch_nodes[id])
	tl.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
	var max_torches := maxi(2, int(Quality.current().get("fire_lights", 2)) + 2)
	for i in tl.size():
		var li := (tl[i] as Node3D).get_node_or_null("Light") as OmniLight3D
		if li:
			li.visible = i < max_torches


# --- O que o E alcança --------------------------------------------------------------------

## Alvos do E perto (como os do corpo): {"type": "cave", "what", "dist", "pos", ...}.
func targets_near(pos: Vector3) -> Array:
	var out: Array = []
	if not active:
		for id: int in _mouths:
			var cv: Dictionary = (_mouths[id] as Node3D).get_meta("cave")
			var p := mouth_point(cv)
			var d := p.distance_to(pos)
			if d < MOUTH_REACH:
				out.append({"type": "cave", "what": "enter", "cave": int(cv["id"]), "pos": p, "dist": d - 0.4})
		return out
	if cw == null:
		return out
	for id: int in cw.ores:
		if mined.has(id):
			continue
		var node: Node3D = cw.ores[id]["node"]
		var d := node.global_position.distance_to(pos)
		if d < ORE_REACH:
			out.append({"type": "cave", "what": "ore", "id": id, "ore": cw.ores[id]["ore"], "pos": node.global_position, "dist": d - 0.6})
	for spec: Array in [["exit", cw.exit_point, 3.0], ["furnace", cw.furnace_point, 2.4], ["boss", cw.boss_point, BOSS_REACH]]:
		var d := (spec[1] as Vector3).distance_to(pos)
		if d < float(spec[2]):
			out.append({"type": "cave", "what": spec[0], "pos": spec[1], "dist": d - 0.5})
	for t: Dictionary in torches:
		if int(t["owner"]) != game.my_id():
			continue
		var node: Node3D = _torch_nodes.get(int(t["id"]))
		if node and node.global_position.distance_to(pos) < TORCH_REACH:
			out.append({"type": "cave", "what": "torch", "id": int(t["id"]), "pos": node.global_position, "dist": node.global_position.distance_to(pos)})
	return out


func prompt(t: Dictionary) -> String:
	match str(t["what"]):
		"enter":
			return "E: entrar na caverna"
		"exit":
			return "E: sair da caverna"
		"furnace":
			return "E: fornalha antiga"
		"torch":
			return "E: pegar a tocha de volta"
		"boss":
			match str(boss["phase"]):
				"asleep":
					return tr("E: acordar o %s com carinho") % boss["name"]
				"awake":
					return tr("Desvie dos círculos no chão!")
			return tr("%s cochilando") % boss["name"]
		"ore":
			var o: Dictionary = t["ore"]
			var name := session.item_name(str(o["item"]))
			if not _holding("pickaxe"):
				return tr("%s  ·  segure uma picareta (1–5)") % name
			var tier := _best_tier("pickaxe")
			if tier < int(o["min_tier"]):
				return tr("%s  ·  precisa de uma picareta melhor") % name
			var need := maxi(1, int(o["hits"]) - (tier - int(o["min_tier"])))
			var done := int(view.get("hits", {}).get(str(int(t["id"])), 0))
			return tr("E: minerar %s (%d de %d)") % [name.to_lower(), done, need]
	return ""


func _holding(tool: String) -> bool:
	return str(session.items.get(session.equipped, {}).get("tool", "")) == tool


func _best_tier(tool: String) -> int:
	var best := 0
	for st: Dictionary in session.inventory:
		var it: Dictionary = session.items.get(str(st["item"]), {})
		if str(it.get("tool", "")) == tool:
			best = maxi(best, int(it.get("tier", 0)))
	return best


func interact(t: Dictionary) -> Dictionary:
	if _busy:
		return {}
	player.face(t["pos"])
	match str(t["what"]):
		"enter":
			await enter(int(t["cave"]))
		"exit":
			await exit()
		"furnace":
			ui.furnace.open(cave_id)
		"torch":
			await _take_torch(int(t["id"]))
		"boss":
			return await _wake_boss()
		"ore":
			return await _mine(t)
	return {"ok": true}


# --- Entrar e sair -------------------------------------------------------------------------

func _fade_to(a: float, seconds := 0.35) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, seconds)
	await tw.finished


## Entra na caverna (na boca dela; com dev = true, de qualquer lugar).
func enter(id: int, dev := false) -> bool:
	if active or _busy:
		return false
	_busy = true
	var r := await api.request("POST", "/dev/cave/enter" if dev else "/cave/enter", {"cave": id})
	if not r["ok"]:
		_busy = false
		ui.toast(str(r["message"]))
		return false
	await _fade_to(1.0)
	view = r["data"]
	cave_id = id
	cw = CaveWorld.new()
	cw.name = "Caverna"
	add_child(cw)
	await cw.build(view["layout"])
	mined.clear()
	for m: Variant in (view["mined"] if view.get("mined") is Array else []):
		mined[int(m)] = true
		cw.set_ore_mined(int(m), true)
	_set_torches(view["torches"] if view.get("torches") is Array else [])
	_set_boss_view(view.get("boss", {}))
	for id2: int in _mouths:
		(_mouths[id2] as Node3D).queue_free()
	_mouths.clear()
	active = true
	game.set_cave_mode(true)
	var spawn := cw.start_point
	player.cave_rescue = _rescue
	player.teleport(spawn)
	player.face(cw.boss_point)
	game.net_teleport("cave", player.global_position)
	camera.snap_behind_target()
	_busy = false
	await get_tree().process_frame
	await _fade_to(0.0)
	ui.toast(str(view.get("name", "Caverna")))
	game.show_place(str(view.get("name", "Caverna")))
	ui.restore_control(true)
	entered.emit(id)
	return true


## Sai pela boca (volta para o globo).
func exit() -> void:
	if not active or _busy:
		return
	_busy = true
	await _fade_to(1.0)
	var cv: Dictionary = {}
	for c: Dictionary in caves:
		if int(c["id"]) == cave_id:
			cv = c
	active = false
	game.set_cave_mode(false)
	_clear()
	var f := data.frame(int(cv.get("cell", 0)))
	var dir := ((f["east"] as Vector3) * cos(float(cv.get("yaw", 0.0))) + (f["north"] as Vector3) * sin(float(cv.get("yaw", 0.0)))).normalized()
	var at := mouth_point(cv) + dir * 2.4
	await game.teleport_to(at, "cave_exit")
	_busy = false
	await _fade_to(0.0)
	exited.emit()


## Sai na hora, sem a boca (casa com H, modo dev): o teleporte que chamou leva ao globo.
func leave_now() -> void:
	if not active:
		return
	active = false
	game.set_cave_mode(false)
	_clear()
	_fade.color.a = 0.0
	exited.emit()


func _clear() -> void:
	if cw:
		cw.queue_free()
		cw = null
	for id: int in _torch_nodes:
		(_torch_nodes[id] as Node3D).queue_free()
	_torch_nodes.clear()
	for w: Dictionary in _warnings:
		(w["node"] as Node3D).queue_free()
	_warnings.clear()
	_zzz = null
	_boss_label.visible = false
	cave_id = -1


## Volta para o começo da caverna (três acertos do chefe ou caiu para fora do chão).
func back_to_start(message := "") -> void:
	if not active or cw == null:
		return
	await _fade_to(1.0, 0.25)
	player.teleport(cw.start_point)
	game.net_teleport("cave_start", player.global_position)
	camera.snap_behind_target()
	await _fade_to(0.0, 0.4)
	if not message.is_empty():
		ui.toast(message)


func _rescue(pos: Vector3) -> void:
	if cw == null:
		return
	var local := cw.to_local(pos)
	var lo := INF
	for rm: Dictionary in view["layout"]["rooms"]:
		lo = minf(lo, float(rm["y"]))
	if local.y < lo - FALL_RESCUE:
		back_to_start()


# --- Minérios ------------------------------------------------------------------------------

func _mine(t: Dictionary) -> Dictionary:
	var o: Dictionary = t["ore"]
	if not _holding("pickaxe"):
		ui.toast(prompt(t))
		return {}
	player.play_action("interact-right")
	_busy = true
	var r := await api.request("POST", "/cave/mine", {"cave": cave_id, "ore": int(t["id"])})
	_busy = false
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return r
	var res: Dictionary = r["data"]
	session.set_inventory(res["inventory"], int(res["slots_used"]))
	game.net_act("mine")
	_wobble(cw.ores[int(t["id"])]["node"])
	var hits: Dictionary = view.get("hits", {})
	hits[str(int(t["id"]))] = int(res["hits"])
	view["hits"] = hits
	if bool(res["broken"]):
		mined[int(t["id"])] = true
		_crumble(int(t["id"]))
		for g: Dictionary in res.get("gained", []):
			ui.toast("+%d %s" % [int(g["count"]), session.item_name(g["item"])], g["item"])
	else:
		ui.toast(str(res["message"]))
	return r


func _wobble(node: Node3D) -> void:
	var base := node.basis
	var tw := node.create_tween()
	tw.tween_method(func(k: float) -> void:
		node.basis = base * Basis(Vector3.FORWARD, sin(k * TAU * 3.0) * 0.06 * (1.0 - k)), 0.0, 1.0, 0.4)


func _crumble(id: int) -> void:
	var node: Node3D = cw.ores[id]["node"]
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 0.05, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func() -> void:
		node.visible = false
		node.scale = Vector3.ONE)


# --- Tochas -------------------------------------------------------------------------------

## Põe uma tocha da mão na parede à frente (ou no chão).
func place_torch() -> void:
	if not active or _busy or cw == null:
		return
	var up := player.global_position.normalized()
	var fwd := -player.global_basis.z
	var from := player.global_position + up * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 2.4)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = from + fwd * 1.2 - up * 1.2
	if not hit.is_empty():
		at = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.15
	var l := cw.to_local(at)
	player.play_action("interact-right")
	_busy = true
	var r := await api.request("POST", "/cave/torch", {"cave": cave_id, "pos": [l.x, l.y, -l.z]})
	_busy = false
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return
	session.set_inventory(r["data"]["inventory"], int(r["data"]["slots_used"]))
	_set_torches(r["data"]["torches"])
	ui.toast(str(r["data"]["message"]), "torch")


func _take_torch(id: int) -> void:
	_busy = true
	var r := await api.request("POST", "/cave/torch/take", {"cave": cave_id, "id": id})
	_busy = false
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return
	session.set_inventory(r["data"]["inventory"], int(r["data"]["slots_used"]))
	_set_torches(r["data"]["torches"])


func _set_torches(list: Array) -> void:
	torches = list
	var want := {}
	for t: Dictionary in list:
		want[int(t["id"])] = t
	for id: int in _torch_nodes.keys():
		if not want.has(id):
			(_torch_nodes[id] as Node3D).queue_free()
			_torch_nodes.erase(id)
	if cw == null:
		return
	for id: int in want:
		if _torch_nodes.has(id):
			continue
		var p: Array = want[id]["pos"]
		var node := Node3D.new()
		cw.add_child(node)
		node.position = CaveWorld.local(float(p[0]), float(p[1]), float(p[2]))
		var mi := MeshInstance3D.new()
		mi.mesh = ModelLibrary.get_model("primitive:torch")["mesh"]
		mi.scale = Vector3.ONE * 1.6
		node.add_child(mi)
		var flame := MeshInstance3D.new()
		flame.mesh = ModelLibrary.get_model("primitive:torch")["mesh"]
		var li := OmniLight3D.new()
		li.name = "Light"
		li.light_color = Color("ffb35c")
		li.omni_range = 8.0
		li.light_energy = 1.4
		li.shadow_enabled = false
		li.position = Vector3(0, 1.0, 0)
		node.add_child(li)
		_torch_nodes[id] = node
	_light_timer = 0.0


# --- Chefe ---------------------------------------------------------------------------------

func _set_boss_view(b: Dictionary) -> void:
	for k: String in b:
		boss[k] = b[k]
	_boss_phase(str(boss["phase"]))


func _boss_phase(phase: String) -> void:
	boss["phase"] = phase
	if cw == null or cw.boss_ap == null:
		return
	var anim := "Idle" if phase == "awake" else "Sleep"
	if anim != _boss_anim:
		_boss_anim = anim
		cw.boss_ap.play(anim, 0.4)
	if phase == "awake":
		if _zzz:
			_zzz.queue_free()
			_zzz = null
	elif _zzz == null:
		_zzz = Label3D.new()
		_zzz.text = "z Z z"
		_zzz.font_size = 96
		_zzz.pixel_size = 0.012
		_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_zzz.modulate = Color("e8f0ff")
		_zzz.outline_size = 12
		cw.add_child(_zzz)
		_zzz.global_position = cw.boss_point + cw.global_basis.y.normalized() * 4.2


## Mensagens do tempo real da caverna: minério de outro jogador, tochas, chefe.
func on_message(d: Dictionary) -> void:
	if not active:
		return
	match str(d.get("t", "")):
		"cave":
			var data_: Dictionary = d.get("data", {})
			if int(data_.get("cave", -1)) != cave_id:
				return
			if data_.has("torches"):
				_set_torches(data_["torches"])
			if data_.has("ore") and cw and cw.ores.has(int(data_["ore"])):
				_wobble(cw.ores[int(data_["ore"])]["node"])
		"boss":
			if int(d.get("cave", -1)) == cave_id:
				_boss_phase(str(d.get("phase", "idle")))
				if str(d["phase"]) == "asleep":
					ui.toast(tr("O %s cansou e dormiu. Chegue perto e aperte E!") % boss["name"])
				elif str(d["phase"]) == "awake":
					boss["dodged"] = 0
					ui.toast(tr("O %s acordou! Desvie dos círculos no chão.") % boss["name"])
		"boss_attack":
			if int(d.get("cave", -1)) == cave_id:
				_attack(d["attack"], float(d.get("y", 0.0)))
		"boss_hit":
			boss["hits"] = int(d.get("hits", 0))
			boss["max"] = int(d.get("max", 3))
			camera_shake(0.35)
			if bool(d.get("reset", false)):
				boss["hits"] = 0
				back_to_start(tr("Ops! O %s te mandou de volta para o começo (nada se perdeu).") % boss["name"])
			else:
				ui.toast(tr("Ai! Acerto %d de %d") % [boss["hits"], boss["max"]])


func _attack(a: Dictionary, floor_y: float) -> void:
	if cw == null:
		return
	if cw.boss_ap and cw.boss_ap.has_animation("Slam"):
		cw.boss_ap.play("Slam", 0.15)
		_boss_anim = "Slam"
		cw.boss_ap.queue("Idle")
	var warn := float(a.get("warn", 1.4))
	for c: Array in a.get("circles", []):
		var disc := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 1.0
		m.bottom_radius = 1.0
		m.height = 0.04
		m.radial_segments = 28
		m.rings = 1
		disc.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.55, 0.35, 0.35)
		mat.no_depth_test = false
		disc.material_override = mat
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cw.add_child(disc)
		disc.position = CaveWorld.local(float(c[0]), floor_y + 0.06, float(c[1]))
		disc.scale = Vector3(0.05, 1, 0.05)
		_warnings.append({"node": disc, "r": float(c[2]), "start": Time.get_ticks_msec() / 1000.0, "warn": warn, "mat": mat})


func _update_warnings() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var keep: Array = []
	for w: Dictionary in _warnings:
		var k := (now - float(w["start"])) / float(w["warn"])
		var disc: MeshInstance3D = w["node"]
		if k >= 1.25:
			disc.queue_free()
			continue
		if k < 1.0:
			var r := float(w["r"]) * clampf(k * 1.4, 0.05, 1.0)
			disc.scale = Vector3(r, 1, r)
			(w["mat"] as StandardMaterial3D).albedo_color = Color(1.0, 0.45 + 0.2 * sin(now * 18.0), 0.3, 0.3 + 0.35 * k)
		else:
			if not w.has("hit"):
				w["hit"] = true
				_dust(disc.global_position, float(w["r"]))
			(w["mat"] as StandardMaterial3D).albedo_color = Color(0.95, 0.9, 0.85, 0.6 * (1.25 - k) * 4.0)
		keep.append(w)
	_warnings = keep


func _dust(at: Vector3, r: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = int(18 * float(Quality.current().get("particles", 1.0))) + 4
	p.lifetime = 0.8
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r * 0.6
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -4, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.35
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.5
	p.mesh = box
	p.color = Color("b8aea2")
	add_child(p)
	p.global_position = at
	p.global_basis = cw.global_basis
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	if at.distance_to(player.global_position) < 8.0:
		camera_shake(0.15)


func camera_shake(amount: float) -> void:
	var tw := create_tween()
	var base := camera.h_offset
	tw.tween_method(func(k: float) -> void:
		camera.h_offset = base + sin(k * 40.0) * amount * (1.0 - k)
		camera.v_offset = cos(k * 33.0) * amount * 0.6 * (1.0 - k), 0.0, 1.0, 0.35)
	tw.tween_callback(func() -> void:
		camera.h_offset = 0.0
		camera.v_offset = 0.0)


func boss_id() -> String:
	return str(session.caves_cfg.get("boss", {}).get("id", "cave_golem"))


func in_boss_room() -> bool:
	if cw == null or cw.boss_room.is_empty():
		return false
	var l := cw.to_local(player.global_position)
	return Vector2(l.x - float(cw.boss_room["x"]), -l.z - float(cw.boss_room["z"])).length() <= float(cw.boss_room["r"]) + 1.0


func _update_boss_label() -> void:
	var show := in_boss_room()
	_boss_label.visible = show
	if not show:
		return
	var hearts := ""
	for i in int(boss["max"]):
		hearts += "○" if i < int(boss["hits"]) else "●"
	var phase: String = {"awake": tr("acordado"), "asleep": tr("dormindo"), "idle": tr("cochilando")}.get(str(boss["phase"]), "")
	_boss_label.text = tr("%s · %s\nvocê: %s") % [boss["name"], phase, hearts]
	if bool(boss.get("won", false)):
		_boss_label.text += "  ·  " + tr("presente de hoje já ganho")


func _wake_boss() -> Dictionary:
	_busy = true
	var r := await api.request("POST", "/cave/boss", {"cave": cave_id})
	_busy = false
	if not r["ok"]:
		ui.toast(str(r["message"]))
		return r
	var res: Dictionary = r["data"]
	ui.toast(str(res["message"]), str(res.get("gained", [{}])[0].get("item", "")) if not (res.get("gained", []) as Array).is_empty() else "")
	if res.has("inventory") and res["inventory"] is Array:
		session.set_inventory(res["inventory"], int(res.get("slots_used", 0)))
	if bool(res.get("won", false)):
		if int(res.get("reward", 0)) > 0:
			session.set_coins(int(res["coins"]))
			boss["won"] = true
			if cw and cw.boss_ap:
				cw.boss_ap.play("Wake", 0.2)
				cw.boss_ap.queue("Sleep")
		if not str(res.get("achievement", "")).is_empty():
			ui.toast(tr("Conquista: acalmou o golem da caverna!"))
	return r
