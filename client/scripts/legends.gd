class_name LegendsGame
extends Node3D
## Criaturas do folclore (fase 4.5, ADR 0058). O servidor sorteia quem aparece, onde e até
## quando (por célula e janela de tempo, igual para todos); aqui pergunta de tempos em tempos
## quem está perto e mostra. Elas não atacam: andam devagar por perto e, se o jogador chegar
## perto demais (shy), somem num puf. O desafio é fotografar (seção Lendas da Goblopédia).

const POLL := 20.0
const FADE := 0.8

var game: GameMain
var session: Session
var api: Api
var player: Player
var world: WorldData
var data: ChunkData
var net: Net
var shy := 7.0

var _active := {}  # chave → {"node", "sg", "ap", "gone", "base"}
var _timer := 2.0
var _busy := false


func setup(g: GameMain, s: Session, a: Api, p: Player, w: WorldData, d: ChunkData, n: Net) -> void:
	game = g
	session = s
	api = a
	player = p
	world = w
	data = d
	net = n
	shy = float(session.folklore.get("shy", 7.0))


func _key(sg: Dictionary) -> String:
	return "%s:%d:%d" % [sg["legend"], int(sg["cell"]), int(sg["from"])]


func update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0 and not _busy:
		_timer = POLL
		_poll()
	var now := data.server_time()
	var pos := player.global_position
	for k: String in _active.keys():
		var e: Dictionary = _active[k]
		var node: Node3D = e["node"]
		var sg: Dictionary = e["sg"]
		if now > float(sg["until"]) and not bool(e["gone"]):
			_vanish(k)
			continue
		if bool(e["gone"]):
			continue
		# Passeio pequeno em volta do ponto (fica sempre fotografável).
		var t := now * 0.25 + float(int(sg["from"]) % 97)
		var f := data.frame(int(sg["cell"]))
		var off := Vector2(cos(t), sin(t * 0.8)) * (0.0 if bool(sg.get("water", false)) else 1.4)
		var xy := Vector2(float(sg["x"]), float(sg["y"])) + off
		var p := WorldData.frame_point(f, xy.x, xy.y)
		if bool(sg.get("water", false)):
			p = p.normalized() * (world.radius - 0.6 + 0.15 * sin(now * 1.3))
		node.global_transform = Transform3D(WorldData.frame_basis(f, -t + PI, float(e["scale"])), p)
		var ap: AnimationPlayer = e["ap"]
		if ap:
			ap.advance(delta)
		if p.distance_to(pos) < shy:
			_vanish(k)
			game.toast(tr("Puf! %s sumiu... chegue mais devagar e fotografe de longe.") % session.legend_name(str(sg["legend"])))


func _poll() -> void:
	if world == null or player.cell_id < 0:
		return
	_busy = true
	var r := await api.request("GET", "/legends?cell=%d" % player.cell_id)
	_busy = false
	if not r["ok"]:
		return
	var want := {}
	for sg: Dictionary in r["data"].get("legends", []):
		want[_key(sg)] = sg
	for k: String in _active.keys():
		if not want.has(k) and not bool(_active[k]["gone"]):
			_vanish(k)
	for k: String in want:
		if _active.has(k):
			continue
		var sg: Dictionary = want[k]
		var id := str(sg["legend"])
		if not CreatureModels.has(id):
			continue
		var node := CreatureModels.instance(id)
		var h := maxf(Player._model_height(node), 0.01)
		var tall: float = {"legend_bigfoot": 2.1, "legend_troll": 2.3, "legend_nessie": 2.0, "legend_mula": 1.4,
			"legend_leprechaun": 0.7, "legend_firebird": 0.9}.get(id, 0.8)
		var sc := float(tall) / h
		add_child(node)
		var ap := node.find_child("AnimationPlayer") as AnimationPlayer
		if ap:
			ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			ap.play("Walk" if not bool(sg.get("water", false)) else "Idle")
		node.set_meta("legend", id)
		_active[k] = {"node": node, "sg": sg, "ap": ap, "gone": false, "scale": sc}
		_poof(node, true)


func _vanish(k: String) -> void:
	var e: Dictionary = _active[k]
	e["gone"] = true
	var node: Node3D = e["node"]
	_poof(node, false)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 0.01, FADE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		node.queue_free()
		_active.erase(k))


## Nuvenzinha de "puf" ao aparecer e sumir.
func _poof(node: Node3D, appear: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 90.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.6
	p.gravity = Vector3.ZERO
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 6
	s.rings = 3
	p.mesh = s
	p.color = Color(1, 1, 1, 0.9) if appear else Color("e8e0f0")
	add_child(p)
	p.global_position = node.global_position + node.global_position.normalized() * 0.5
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## Criaturas visíveis agora (modo foto): [{"entry", "pos", "node"}].
func visible_now() -> Array:
	var out: Array = []
	for k: String in _active:
		var e: Dictionary = _active[k]
		if not bool(e["gone"]):
			var node: Node3D = e["node"]
			out.append({"entry": str(e["sg"]["legend"]), "pos": node.global_position + node.global_position.normalized() * 0.6, "node": node})
	return out


## Modo dev: faz a lenda aparecer na frente do jogador agora.
func dev_spawn(id: String) -> void:
	var r := await api.request("POST", "/dev/legend", {"id": id})
	if not r["ok"]:
		game.toast(str(r["message"]))
		return
	_timer = 0.0
	game.toast(tr("%s apareceu na sua frente.") % session.legend_name(id))
