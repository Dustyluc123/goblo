class_name Animals
extends Node3D
## Animais andando pelo mundo (ADR 0032). Quais animais existem vem do servidor (junto com
## os objetos de cada pedaço); onde cada um está sai de AnimalPath.at(animal, horário do
## servidor), a mesma conta para todos os jogadores.
##
## Por cima do trajeto comum há um desvio só deste jogador (reações locais): o tímido foge
## galopando se o jogador correr perto, o amigo (ganhou frutinha) segue o jogador por um
## tempo, e no carinho o animal para e reage. Quando a reação acaba, o desvio volta a zero
## devagar (andando) e o animal reencontra o trajeto comum.
##
## Desempenho: só os MAX_ACTIVE animais mais perto (até RADIUS) ganham modelo; os mais
## longe são atualizados menos vezes por segundo; nada no zoom afastado.

const DIR := "res://assets/quaternius/ultimate-animated-animals/"
const RADIUS := 45.0
const MAX_ACTIVE := 12
const REFRESH := 0.5
const SPAWN_PER_FRAME := 1
const HIDE_ABOVE_ZOOM := 0.25
const FLEE_RADIUS := 7.0
const FLEE_TIME := 2.6
const MAX_DISPLACE := 10.0
const FRIEND_TIME := 25.0
const PET_TIME := 1.6
const FEED_TIME := 2.6
## Animação a cada quadro até ANIM_FULL; 1 a cada 2 até ANIM_MID; depois posição e
## animação a cada 3 quadros.
const ANIM_FULL := 15.0
const ANIM_MID := 28.0
const BLEND := 0.35
const LOOPED := ["Walk", "Gallop", "Idle", "Idle_2", "Eating"]

## espécie → PackedScene (carregadas no começo, em threads).
static var _scenes := {}
## espécie → altura do modelo original (para escalar).
static var _heights := {}

var world: WorldData
var data: ChunkData
var player: Player
## Espécies (do /content): nome, modelo, altura, shy, walk, run, roam, leg, jump.
var species := {}
## Quantos animais têm modelo agora (painel F2 e modo dev).
var active_count := 0

var _active := {}  # id → {"node", "ap", "animal", "xy", "heading", "anim", "acc", "frame"}
var _local := {}  # id → {"disp": Vector2, "flee_until", "flee_dir", "friend_until", "hold_until", "hold_xy", "hold_anim", "seen"}
var _wanted: Array = []
var _timer := 0.0
var _frame := 0
var _debug: Array = []
var _debug_next := -1
var _polys := {}  # célula → PackedVector2Array (cantos no plano da célula)
var _heart: ImageTexture


## Carrega as cenas das espécies, uma por quadro, na tela de carregamento (~100 ms ao todo).
## Na thread principal: carregar os GLB animados em threads dava erros de recurso.
static func preload_scenes(list: Dictionary, tree: SceneTree) -> void:
	for sp: String in list:
		var path := DIR + str(list[sp]["model"]) + ".glb"
		if _scenes.has(sp) or not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		await tree.process_frame
		if scene:
			_scenes[sp] = scene


func setup(w: WorldData, d: ChunkData, p: Player, sp: Dictionary) -> void:
	world = w
	data = d
	player = p
	species = sp


func _process(delta: float) -> void:
	if world == null or player == null or not player.visible:
		return
	_frame += 1
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		_refresh()
	var spawned := 0
	for a: Dictionary in _wanted:
		if not _active.has(a["id"]) and spawned < SPAWN_PER_FRAME:
			_spawn(a)
			spawned += 1
	if not visible:
		return
	var now := data.server_time()
	var local_now := Time.get_ticks_msec() / 1000.0
	var pos := player.global_position
	for id: int in _active:
		var e: Dictionary = _active[id]
		# Longe: posição e animação a cada 3 quadros (com o tempo acumulado).
		e["dt"] = float(e.get("dt", 0.0)) + delta
		var far: bool = (e["node"] as Node3D).global_position.distance_squared_to(pos) > ANIM_MID * ANIM_MID
		if far and (_frame + id) % 3 != 0:
			continue
		_update(e, now, local_now, float(e["dt"]))
		e["dt"] = 0.0


## Liga ou desliga pelo zoom da câmera.
func update_view(far_amount: float) -> void:
	visible = far_amount < HIDE_ABOVE_ZOOM


## Escolhe os animais que ganham modelo: os mais perto, até MAX_ACTIVE.
func _refresh() -> void:
	var pos := player.global_position
	var list: Array = []
	for a: Dictionary in data.animals_near(pos, RADIUS) + _debug:
		var home := _home(a)
		var d := home.distance_to(pos)
		if d <= RADIUS:
			list.append([d, a])
	list.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	_wanted = []
	var keep := {}
	for i in mini(list.size(), MAX_ACTIVE):
		_wanted.append(list[i][1])
		keep[list[i][1]["id"]] = true
	for id: int in _active.keys():
		if not keep.has(id):
			(_active[id]["node"] as Node).queue_free()
			_active.erase(id)
	active_count = _active.size()
	# Esquece reações antigas de animais que já foram embora.
	var local_now := Time.get_ticks_msec() / 1000.0
	for id: int in _local.keys():
		if not _active.has(id) and local_now - float(_local[id]["seen"]) > 60.0:
			_local.erase(id)


func _home(a: Dictionary) -> Vector3:
	var p: Array = a["points"][0]
	return WorldData.frame_point(data.frame(int(a["cell"])), float(p[0]), float(p[1]))


func _spawn(a: Dictionary) -> void:
	var sp := str(a["species"])
	if not _scenes.has(sp) or not species.has(sp):
		return
	var t0 := Time.get_ticks_usec()
	_spawn_model(a, sp)
	HitchLog.note("animal criado: %s" % sp, (Time.get_ticks_usec() - t0) / 1000.0)


func _spawn_model(a: Dictionary, sp: String) -> void:
	var model := (_scenes[sp] as PackedScene).instantiate() as Node3D
	if not _heights.has(sp):
		_heights[sp] = maxf(Player._model_height(model), 0.01)
	var holder := Node3D.new()
	holder.name = "Animal_%d" % int(a["id"])
	add_child(holder)
	var s := float(species[sp]["height"]) / float(_heights[sp])
	model.scale = Vector3.ONE * s
	holder.add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
	if ap:
		for anim_name in LOOPED:
			if ap.has_animation(anim_name):
				ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		ap.play("Idle")
		ap.seek(randf() * 2.0, true)
	var e := {"node": holder, "ap": ap, "animal": a, "xy": Vector2.INF, "heading": INF, "anim": "Idle", "acc": 0.0}
	_active[int(a["id"])] = e
	active_count = _active.size()
	_update(e, data.server_time(), Time.get_ticks_msec() / 1000.0, 0.0)


func _local_state(id: int) -> Dictionary:
	if not _local.has(id):
		_local[id] = {"disp": Vector2.ZERO, "flee_until": 0.0, "flee_dir": Vector2.ZERO, "friend_until": 0.0,
			"hold_until": 0.0, "hold_xy": Vector2.ZERO, "hold_anim": "", "seen": 0.0}
	return _local[id]


func _update(e: Dictionary, now: float, local_now: float, delta: float) -> void:
	var a: Dictionary = e["animal"]
	var id := int(a["id"])
	var sp: Dictionary = species[str(a["species"])]
	var cell := int(a["cell"])
	var f := data.frame(cell)
	var pose := AnimalPath.at(a, now)
	e["t"] = now  # horário (do servidor) da última atualização
	var path_xy := Vector2(float(pose["x"]), float(pose["y"]))
	var st := _local_state(id)
	st["seen"] = local_now
	var player_xy := WorldData.frame_coords(f, player.global_position)
	var cur: Vector2 = path_xy + (st["disp"] as Vector2)
	# Tímido: foge se o jogador vem correndo perto (andando devagar ou parado, deixa chegar).
	if bool(sp["shy"]) and local_now > float(st["hold_until"]) and local_now > float(st["friend_until"]) \
			and cur.distance_to(player_xy) < FLEE_RADIUS and _player_running():
		if local_now > float(st["flee_until"]):
			st["flee_dir"] = (cur - player_xy).normalized()
		st["flee_until"] = local_now + FLEE_TIME
	var disp: Vector2 = st["disp"]
	var mode := "back"
	if local_now < float(st["hold_until"]):
		mode = "hold"
		disp = (st["hold_xy"] as Vector2) - path_xy
	elif local_now < float(st["flee_until"]):
		mode = "flee"
		var step := (st["flee_dir"] as Vector2) * float(sp["run"]) * delta
		if _free(cell, path_xy + disp + step) and (disp + step).length() < MAX_DISPLACE:
			disp += step
	elif local_now < float(st["friend_until"]):
		mode = "follow"
		var to_player := player_xy - (path_xy + disp)
		var target := player_xy - to_player.normalized() * 1.3 - path_xy
		var next := disp.move_toward(target, float(sp["run"]) * 0.8 * delta)
		if to_player.length() > 1.4 and _free(cell, path_xy + next) and next.length() < MAX_DISPLACE * 1.5:
			disp = next
	elif disp != Vector2.ZERO:
		disp = disp.move_toward(Vector2.ZERO, float(sp["walk"]) * 1.4 * delta)
		if not _free(cell, path_xy + disp):
			disp = disp.move_toward(Vector2.ZERO, float(sp["walk"]) * 0.2 * delta)
	st["disp"] = disp
	var xy := path_xy + disp
	# Velocidade de verdade (trajeto + desvio) decide andar, galopar ou ficar parado.
	var last: Vector2 = e["xy"]
	var vel := Vector2.ZERO if last == Vector2.INF or delta <= 0.0 else (xy - last) / delta
	e["xy"] = xy
	var speed := vel.length()
	var anim := "Idle"
	var want_heading := float(pose["heading"])
	if mode == "hold":
		anim = str(st["hold_anim"])
		want_heading = (player_xy - xy).angle()
	elif speed > float(sp["walk"]) * 1.8:
		anim = "Gallop"
		want_heading = vel.angle()
	elif speed > 0.12:
		anim = "Walk"
		want_heading = vel.angle()
	else:
		anim = {"walk": "Idle", "idle": "Idle", "eat": "Eating", "look": "Idle_2"}.get(str(pose["state"]), "Idle")
		if mode == "follow":
			anim = "Idle"
			want_heading = (player_xy - xy).angle()
	var h := float(e["heading"])
	h = want_heading if h == INF else lerp_angle(h, want_heading, clampf(6.0 * delta, 0.0, 1.0))
	e["heading"] = h
	var node: Node3D = e["node"]
	node.global_transform = Transform3D(WorldData.frame_basis(f, h + PI / 2.0), WorldData.frame_point(f, xy.x, xy.y))
	var ap: AnimationPlayer = e["ap"]
	if ap == null:
		return
	if anim != str(e["anim"]) and ap.has_animation(anim):
		e["anim"] = anim
		ap.play(anim, BLEND)
	ap.speed_scale = clampf(speed / float(sp["walk"]), 0.6, 1.6) if anim == "Walk" else 1.0
	# Animação menos vezes por segundo quando o animal está longe.
	var dist := node.global_position.distance_to(player.global_position)
	var every := 1 if dist < ANIM_FULL else (2 if dist < ANIM_MID else 1)  # longe já vem a cada 3
	e["acc"] = float(e["acc"]) + delta
	if (_frame + id) % every == 0:
		ap.advance(float(e["acc"]))
		e["acc"] = 0.0


func _player_running() -> bool:
	# A velocidade pedida (não a medida pelo deslocamento): um teleporte não conta como correr.
	var v := player.velocity
	var up := player.global_position.normalized()
	return (v - up * v.dot(up)).length() > player.walk_speed * 1.35


## O ponto (x, y) da célula serve para o animal: dentro da célula e fora dos lotes.
func _free(cell: int, xy: Vector2) -> bool:
	var poly := _poly(cell)
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var e := b - a
		if e.cross(xy - a) / maxf(e.length(), 1e-6) < 1.0:
			return false
	var size := data.lot_size()
	for l: Dictionary in data.chunk(world.chunk_of_cell(cell)).get("lots", []):
		if int(l["cell"]) == cell and Rect2(float(l["x0"]) - 0.4, float(l["y0"]) - 0.4, size + 0.8, size + 0.8).has_point(xy):
			return false
	return true


## Cantos da célula no plano dela, em sentido anti-horário (como Frame.Poly no servidor).
func _poly(cell: int) -> PackedVector2Array:
	if _polys.has(cell):
		return _polys[cell]
	var f := data.frame(cell)
	var c: Vector3 = f["center"]
	var top: float = f["top"]
	var out := PackedVector2Array()
	for v in world.vertices[cell]:
		out.append(WorldData.frame_coords(f, v * (top / v.dot(c))))
	# Garante o sentido anti-horário (área positiva).
	var area := 0.0
	for k in out.size():
		area += out[k].cross(out[(k + 1) % out.size()])
	if area < 0.0:
		out.reverse()
	_polys[cell] = out
	return out


# --- Interação ------------------------------------------------------------------------------

## Animal com modelo mais perto do ponto, até `reach` (mais o tamanho dele).
## {"id", "species", "name", "pos": Vector3} ou {}.
func nearest(pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for id: int in _active:
		var e: Dictionary = _active[id]
		var node: Node3D = e["node"]
		var sp := str(e["animal"]["species"])
		var d := node.global_position.distance_to(pos) - float(species[sp]["height"]) * 0.5
		if d < reach and d < best_d:
			best_d = d
			best = {"id": id, "species": sp, "name": str(species[sp]["name"]), "pos": node.global_position}
	return best


func is_friend(id: int) -> bool:
	return Time.get_ticks_msec() / 1000.0 < float(_local_state(id)["friend_until"])


## Carinho: o animal para, olha para o jogador e faz um pulinho (ou o Idle_2).
func pet(id: int) -> void:
	if not _active.has(id):
		return
	var e: Dictionary = _active[id]
	var sp: Dictionary = species[str(e["animal"]["species"])]
	var anim := str(sp.get("jump", "Idle_2")) if randf() < 0.5 else "Idle_2"
	_hold(id, PET_TIME, anim)
	_hearts(e["node"], 3)


## Comeu a frutinha: come ali parado e depois segue o jogador por um tempo.
func fed(id: int) -> void:
	if not _active.has(id):
		return
	_hold(id, FEED_TIME, "Eating")
	var st := _local_state(id)
	st["friend_until"] = Time.get_ticks_msec() / 1000.0 + FEED_TIME + FRIEND_TIME
	st["flee_until"] = 0.0
	_hearts(_active[id]["node"], 5)


func _hold(id: int, seconds: float, anim: String) -> void:
	var st := _local_state(id)
	st["hold_until"] = Time.get_ticks_msec() / 1000.0 + seconds
	st["hold_xy"] = _active[id]["xy"]
	st["hold_anim"] = anim
	st["flee_until"] = 0.0


func _hearts(node: Node3D, count: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _heart == null:
		_heart = _heart_texture()
	var up := node.global_position.normalized()
	for i in count:
		var s := Sprite3D.new()
		s.texture = _heart
		s.pixel_size = 0.004
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.no_depth_test = true
		s.render_priority = 10
		add_child(s)
		var side := Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35))
		var start := node.global_position + up * 1.0 + side
		s.global_position = start
		s.modulate.a = 0.0
		var tw := s.create_tween()
		tw.tween_interval(i * 0.18)
		tw.tween_property(s, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(s, "global_position", start + up * 0.9, 1.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "modulate:a", 0.0, 0.3)
		tw.tween_callback(s.queue_free)


static func _heart_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			# Coração: x² + (1,2·y − √|x|)² < 1, com bordinha mais escura.
			var u := (float(x) / n - 0.5) * 2.6
			var v := (0.55 - float(y) / n) * 2.6
			var q := u * u + pow(1.2 * v - sqrt(absf(u)) * 0.9, 2.0)
			if q < 1.0:
				var c := Color("ff6b8b") if q < 0.78 else Color("d94a6a")
				if q < 0.2 and u < -0.2 and v > 0.2:
					c = Color("ffc2d0")
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# --- Modo dev -------------------------------------------------------------------------------

## Cria um animal só neste cliente, perto do ponto (teste de animação e interação).
func spawn_debug(sp: String, pos: Vector3) -> bool:
	if not species.has(sp):
		return false
	var cell := world.find_cell(pos)
	var f := data.frame(cell)
	var c := WorldData.frame_coords(f, pos)
	var pts: Array = []
	for k in 8:
		var p := c + Vector2.from_angle(k * TAU / 8.0 + randf()) * randf_range(1.5, 4.0)
		if _free(cell, p):
			pts.append([p.x, p.y])
	if pts.size() < 2:
		return false
	_debug.append({"id": _debug_next, "cell": cell, "species": sp, "points": pts,
		"speed": float(species[sp]["walk"]), "leg": float(species[sp]["leg"])})
	_debug_next -= 1
	_timer = 0.0
	return true


## Lista dos animais com modelo agora (modo dev).
func describe() -> String:
	var lines: Array = []
	for id: int in _active:
		var e: Dictionary = _active[id]
		var sp := str(e["animal"]["species"])
		var d := (e["node"] as Node3D).global_position.distance_to(player.global_position)
		lines.append("%s #%d · %.0f m · %s%s" % [species[sp]["name"], id, d, e["anim"], " · amigo" if is_friend(id) else ""])
	lines.sort()
	return "%d animais carregados (até %d):\n%s" % [_active.size(), MAX_ACTIVE, "\n".join(lines)]
