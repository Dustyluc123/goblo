class_name RemotePlayers
extends Node3D
## Os outros jogadores (fase 3, ADR 0039): o personagem escolhido por cada um, com o
## apelido em cima da cabeça, o balão do chat, os emotes e as animações (andar, correr,
## pular, coletar, carinho, foto).
##
## Interpolação: as posições chegam do servidor ~15 vezes por segundo com o horário dele;
## cada jogador é desenhado `Net.interp_delay_ms` atrás (~110 ms), entre as duas fotos
## em volta desse instante, para o movimento ficar liso mesmo com a rede tremendo.
##
## Desempenho: só os `Net.animated_near` mais perto têm a animação a cada quadro; os outros
## (e os além de `anim_lod_distance`) a cada 3 quadros. O servidor já manda no máximo os 40
## mais perto.

const CHAR_DIR := "res://assets/kenney/mini-characters/"
const DEFAULT_CHAR := "character-male-a"
const MAX_SAMPLES := 12
## Quanto tempo dá para continuar o movimento sem foto nova (ms).
const MAX_EXTRAPOLATE := 250.0
const BUBBLE_TIME := 6.0
## Animações por código (o mesmo de Net.send_move / PROTOCOLO.md).
const ANIMS := ["idle", "walk", "sprint", "fall", "interact-right", "pick-up", "holding-right", "sit"]
## Emotes → animação e quantas vezes toca (0 = fica até se mexer).
const EMOTES := {"wave": ["interact-left", 2], "yes": ["emote-yes", 1], "no": ["emote-no", 1], "sit": ["sit", 0], "cheer": ["jump", 2]}

static var _scenes := {}  # personagem → PackedScene
static var _heights := {}

var net: Net
var camera: Camera3D
## Silenciados (só neste computador): sem balão nem chat.
var muted := {}
## Quantos estão aparecendo (F2).
var visible_count := 0
var _avatars := {}  # id → Dictionary
var _frame := 0


## Carrega as cenas dos 12 personagens (tela de carregamento).
static func preload_characters(list: Array, tree: SceneTree) -> void:
	for c: String in list:
		if _scenes.has(c):
			continue
		var path := CHAR_DIR + c + ".glb"
		if ResourceLoader.exists(path):
			_scenes[c] = load(path)
			await tree.process_frame


func setup(n: Net, cam: Camera3D) -> void:
	net = n
	camera = cam
	net.entered.connect(_on_enter)
	net.left.connect(_on_leave)
	net.snapshot.connect(_on_snapshot)
	net.emote_received.connect(play_emote)
	net.act_received.connect(_on_act)
	net.char_changed.connect(_on_char)
	net.state_changed.connect(func(s: String) -> void:
		if s != "conectado":
			clear())


func clear() -> void:
	for id: int in _avatars.keys():
		_on_leave(id)


func ids() -> Array:
	return _avatars.keys()


func info(id: int) -> Dictionary:
	return _avatars.get(id, {}).get("info", {})


## Posição desenhada agora (testes, lista de jogadores).
func position_of(id: int) -> Vector3:
	var a: Dictionary = _avatars.get(id, {})
	return (a["node"] as Node3D).global_position if not a.is_empty() else Vector3.ZERO


func _on_enter(d: Dictionary) -> void:
	var id: int = d["id"]
	if _avatars.has(id):
		_on_leave(id)
	var root := Node3D.new()
	root.name = "Jogador_%d" % id
	add_child(root)
	var a := {"node": root, "info": d, "samples": [], "anim": "", "emote": "", "emote_left": 0,
		"bubble_t": 0.0, "lod_acc": 0.0}
	_avatars[id] = a
	_build_model(a, str(d.get("char", "")))
	var label := Label3D.new()
	label.text = str(d.get("nick", "?"))
	label.font_size = 36
	label.pixel_size = 0.0045
	label.outline_size = 10
	label.modulate = Color("fffaf0")
	label.outline_modulate = Color(0.16, 0.12, 0.2, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.position = Vector3(0, 1.35, 0)
	label.visibility_range_end = 45.0
	root.add_child(label)
	a["label"] = label
	var bubble := Label3D.new()
	bubble.font_size = 30
	bubble.pixel_size = 0.0042
	bubble.outline_size = 12
	bubble.modulate = Color("3a2f45")
	bubble.outline_modulate = Color(1, 1, 1, 0.95)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD
	bubble.width = 420.0
	bubble.position = Vector3(0, 1.7, 0)
	bubble.visible = false
	root.add_child(bubble)
	a["bubble"] = bubble
	_place(a, d["pos"], 0.0)
	visible_count = _avatars.size()


func _build_model(a: Dictionary, character: String) -> void:
	if a.has("model"):
		(a["model"] as Node).queue_free()
	if not _scenes.has(character):
		character = DEFAULT_CHAR
	if not _scenes.has(character):
		var path := CHAR_DIR + character + ".glb"
		if not ResourceLoader.exists(path):
			return
		_scenes[character] = load(path)
	var model := (_scenes[character] as PackedScene).instantiate() as Node3D
	if not _heights.has(character):
		_heights[character] = maxf(Player._model_height(model), 0.01)
	model.scale = Vector3.ONE / float(_heights[character])
	model.rotation.y = PI  # os modelos olham para +Z
	(a["node"] as Node3D).add_child(model)
	a["model"] = model
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
	if ap:
		for n in ["idle", "walk", "sprint", "fall", "holding-right", "sit"]:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	a["ap"] = ap
	a["anim"] = ""


func _on_leave(id: int) -> void:
	var a: Dictionary = _avatars.get(id, {})
	if a.is_empty():
		return
	(a["node"] as Node).queue_free()
	_avatars.erase(id)
	visible_count = _avatars.size()


func _on_char(id: int, character: String) -> void:
	var a: Dictionary = _avatars.get(id, {})
	if not a.is_empty():
		(a["info"] as Dictionary)["char"] = character
		_build_model(a, character)


func _on_snapshot(ms: int, list: Array) -> void:
	for e: Array in list:
		var a: Dictionary = _avatars.get(int(e[0]), {})
		if a.is_empty():
			continue
		var samples: Array = a["samples"]
		if not samples.is_empty() and float(samples[-1][0]) >= ms:
			continue
		samples.append([float(ms), e[1], float(e[2]), int(e[3]), int(e[4])])
		while samples.size() > MAX_SAMPLES:
			samples.pop_front()


## Chat: balão em cima da cabeça (não aparece para silenciados).
func say(id: int, text: String) -> void:
	var a: Dictionary = _avatars.get(id, {})
	if a.is_empty() or muted.has(id):
		return
	var bubble: Label3D = a["bubble"]
	bubble.text = text
	bubble.visible = true
	a["bubble_t"] = BUBBLE_TIME


func play_emote(id: int, emote: String) -> void:
	var a: Dictionary = _avatars.get(id, {})
	if a.is_empty() or not EMOTES.has(emote):
		return
	a["emote"] = EMOTES[emote][0]
	a["emote_left"] = int(EMOTES[emote][1])
	a["anim"] = ""


func _on_act(id: int, action: String, _animal: int) -> void:
	var anim: String = {"pick": "pick-up", "photo": "holding-right"}.get(action, "interact-right")
	var a: Dictionary = _avatars.get(id, {})
	if a.is_empty():
		return
	a["emote"] = anim
	a["emote_left"] = 1
	a["anim"] = ""


func _process(delta: float) -> void:
	_frame += 1
	if net == null or _avatars.is_empty():
		return
	var t := net.server_ms() - float(net.interp_delay_ms)
	var cam := camera.global_position if camera else Vector3.ZERO
	# Os mais perto primeiro: só animated_near ganham animação a cada quadro.
	var order: Array = _avatars.keys()
	order.sort_custom(func(x: int, y: int) -> bool:
		return (_avatars[x]["node"] as Node3D).global_position.distance_squared_to(cam) < (_avatars[y]["node"] as Node3D).global_position.distance_squared_to(cam))
	for i in order.size():
		var a: Dictionary = _avatars[order[i]]
		var anim_code := _interpolate(a, t)
		var near := i < net.animated_near and (a["node"] as Node3D).global_position.distance_to(cam) < net.anim_lod_distance
		a["lod_acc"] = float(a["lod_acc"]) + delta
		if near or (_frame + i) % 3 == 0:
			_animate(a, anim_code, float(a["lod_acc"]))
			a["lod_acc"] = 0.0
		if float(a["bubble_t"]) > 0.0:
			a["bubble_t"] = float(a["bubble_t"]) - delta
			if float(a["bubble_t"]) <= 0.0:
				(a["bubble"] as Label3D).visible = false


## Põe o avatar no instante t (ms do servidor) e devolve o código da animação.
func _interpolate(a: Dictionary, t: float) -> int:
	var s: Array = a["samples"]
	if s.is_empty():
		return 0
	if t <= float(s[0][0]):
		_place(a, s[0][1], s[0][2])
		return int(s[0][3])
	for k in range(s.size() - 1, -1, -1):
		if float(s[k][0]) <= t:
			if k == s.size() - 1:
				# Sem foto nova: continua um pouquinho na mesma direção e depois espera.
				var last: Array = s[k]
				var pos: Vector3 = last[1]
				if k > 0:
					var prev: Array = s[k - 1]
					var dt := float(last[0]) - float(prev[0])
					var ahead := minf(t - float(last[0]), MAX_EXTRAPOLATE)
					if dt > 0.0:
						pos = (last[1] as Vector3) + ((last[1] as Vector3) - (prev[1] as Vector3)) * (ahead / dt)
				_place(a, pos, last[2])
				return int(last[3])
			var p0: Array = s[k]
			var p1: Array = s[k + 1]
			var u := clampf((t - float(p0[0])) / maxf(float(p1[0]) - float(p0[0]), 1.0), 0.0, 1.0)
			var pos2 := (p0[1] as Vector3).lerp(p1[1], u)
			_place(a, pos2, lerp_angle(float(p0[2]), float(p1[2]), u))
			return int(p1[3]) if u > 0.5 else int(p0[3])
	return 0


func _place(a: Dictionary, pos: Vector3, yaw: float) -> void:
	var node: Node3D = a["node"]
	var up := pos.normalized()
	var fwd := Net.facing_of(pos, yaw)
	if fwd.length() < 0.01:
		fwd = Net.tangent(pos)[1]
	node.global_transform = Transform3D(Basis.looking_at(fwd, up), pos)


func _animate(a: Dictionary, code: int, dt: float) -> void:
	var ap: AnimationPlayer = a.get("ap")
	if ap == null:
		return
	var want: String = ANIMS[clampi(code, 0, ANIMS.size() - 1)]
	var emote: String = a["emote"]
	if not emote.is_empty():
		# Emote tocando: acaba depois de N vezes (ou quando anda, no caso de sentar).
		if (int(a["emote_left"]) == 0 and code != 0) or (int(a["emote_left"]) > 0 and a["anim"] == emote and not ap.is_playing()):
			a["emote_left"] = int(a["emote_left"]) - 1
			if int(a["emote_left"]) <= 0:
				a["emote"] = ""
		else:
			want = emote
	if a["anim"] != want and ap.has_animation(want):
		ap.play(want, 0.15)
		a["anim"] = want
	ap.advance(dt)
