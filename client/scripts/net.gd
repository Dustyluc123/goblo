class_name Net
extends Node
## Conexão em tempo real com o servidor (fase 3, ADR 0039; protocolo em docs/PROTOCOLO.md).
##
## Um WebSocketPeer com o token do jogador no cabeçalho Authorization. Reconecta sozinho
## se a conexão cair (espera 1, 2, 4… até 8 s), sem perder o estado: o servidor lembra a
## posição. Movimento vai em binário; o resto, em JSON enxuto.
##
## O modo dev pode simular atraso (0 a 300 ms) e perda de pacotes de movimento (0 a 10%),
## para testar a interpolação dos outros jogadores.

signal state_changed(state: String)  # "conectando", "conectado", "sem conexão"
signal welcomed(info: Dictionary)
signal entered(info: Dictionary)
signal left(id: int)
signal snapshot(server_ms: int, entries: Array)  # [id, pos, yaw, anim, flags]
signal corrected(pos: Vector3, reason: int)
signal teleport_result(why: String, ok: bool)
signal chat_received(id: int, nick: String, text: String)
signal emote_received(id: int, emote: String)
signal act_received(id: int, action: String, animal: int)
signal char_changed(id: int, character: String)
signal object_event(data: Dictionary, by: int)
signal lot_event(lot: Dictionary, by: int)
signal stamped(result: Dictionary)
signal blocked_changed(id: int, on: bool)
signal info(text: String)
signal kicked(reason: String)

const MSG_MOVE := 1
const MSG_SNAPSHOT := 2
const MSG_CORRECTION := 3
const FLAG_ON_FLOOR := 1
const FLAG_RUNNING := 2
const FLAG_NOCLIP := 4
const FLAG_PHOTO := 8
const REASONS := {1: "velocidade", 2: "oceano", 3: "fronteira", 4: "altura", 5: "teleporte"}
const PING_EVERY := 2.0

var url := ""
var token := ""
var state := "sem conexão"
var is_welcomed := false
var player_id := -1
## Do welcome do servidor (rules.json).
var send_hz := 15
var interp_delay_ms := 110
var animated_near := 20
var anim_lod_distance := 30.0
var chat_max := 120
## Atraso medido (ida e volta, ms) e diferença do relógio do servidor.
var ping_ms := 0
var _offset_ms := 0.0
var _has_offset := false
## Simulação do modo dev.
var sim_latency_ms := 0
var sim_loss := 0.0
## Estatísticas (F2): pacotes por segundo recebidos e mandados.
var pps_in := 0
var pps_out := 0
var _count_in := 0
var _count_out := 0
var _stat_t := 0.0

var _ws := WebSocketPeer.new()
var _retry_at := 0.0
var _backoff := 1.0
var _ping_t := 0.0
var _seq := 0
var _kicked := false
var _in: Array = []  # [entrega (ms), pacote, é texto]
var _out: Array = []  # [envio (ms), pacote, é texto]
var _was_open := false


## Começa a conectar (e reconectar sozinho). base_url é o endereço HTTP do servidor.
func start(base_url: String, player_token: String) -> void:
	url = base_url.replace("https://", "wss://").replace("http://", "ws://") + "/ws"
	token = player_token
	_kicked = false
	_connect()


func stop() -> void:
	_kicked = true
	_ws.close()


func connected() -> bool:
	return is_welcomed and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _connect() -> void:
	_ws = WebSocketPeer.new()
	_ws.handshake_headers = PackedStringArray(["Authorization: Bearer " + token])
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 16
	is_welcomed = false
	var err := _ws.connect_to_url(url)
	_set_state("conectando" if err == OK else "sem conexão")
	if err != OK:
		_retry_at = _now() + _backoff * 1000.0


func _set_state(s: String) -> void:
	if s != state:
		state = s
		state_changed.emit(s)


func _now() -> float:
	return Time.get_ticks_msec()


## Agora no relógio do servidor (ms desde que ele subiu), para a interpolação.
func server_ms() -> float:
	return _now() + _offset_ms


func _process(delta: float) -> void:
	_stat_t += delta
	if _stat_t >= 1.0:
		pps_in = _count_in
		pps_out = _count_out
		_count_in = 0
		_count_out = 0
		_stat_t = 0.0
	if url.is_empty():
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		_was_open = true
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			var text := _ws.was_string_packet()
			_count_in += 1
			if not text and sim_loss > 0.0 and randf() < sim_loss and pkt.size() > 0 and pkt[0] == MSG_SNAPSHOT:
				continue  # perda simulada (só movimento)
			_in.append([_now() + sim_latency_ms * 0.5, pkt, text])
		_ping_t -= delta
		if _ping_t <= 0.0 and is_welcomed:
			_ping_t = PING_EVERY
			send_json({"t": "ping", "c": _now()})
		_flush_out()
	elif st == WebSocketPeer.STATE_CLOSED:
		if _was_open or state == "conectando":
			_was_open = false
			is_welcomed = false
			_set_state("sem conexão")
			_retry_at = _now() + _backoff * 1000.0
			_backoff = minf(_backoff * 2.0, 8.0)
		if not _kicked and _now() >= _retry_at and _retry_at > 0.0:
			_retry_at = 0.0
			_connect()
	# Entrega o que chegou (com o atraso simulado).
	var now := _now()
	while not _in.is_empty() and float(_in[0][0]) <= now:
		var item: Array = _in.pop_front()
		if item[2]:
			_on_text((item[1] as PackedByteArray).get_string_from_utf8())
		else:
			_on_binary(item[1])


func _flush_out() -> void:
	var now := _now()
	while not _out.is_empty() and float(_out[0][0]) <= now:
		var item: Array = _out.pop_front()
		var err: int
		if item[2]:
			err = _ws.send_text(item[1])
		else:
			err = _ws.send(item[1], WebSocketPeer.WRITE_MODE_BINARY)
		if err == OK:
			_count_out += 1


func _queue(payload: Variant, text: bool) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_out.append([_now() + sim_latency_ms * 0.5, payload, text])
	if sim_latency_ms <= 0:
		_flush_out()


func send_json(msg: Dictionary) -> void:
	_queue(JSON.stringify(Api._ints(msg)), true)


## Manda a posição (19 bytes). yaw: ângulo no plano tangente (ver yaw_of).
func send_move(pos: Vector3, yaw: float, anim: int, flags: int) -> void:
	if not is_welcomed:
		return
	if sim_loss > 0.0 and randf() < sim_loss:
		return  # perda simulada
	_seq = (_seq + 1) % 65536
	var b := StreamPeerBuffer.new()
	b.put_u8(MSG_MOVE)
	b.put_u16(_seq)
	b.put_float(pos.x)
	b.put_float(pos.y)
	b.put_float(pos.z)
	b.put_16(clampi(roundi(wrapf(yaw, -PI, PI) * 10000.0), -32767, 32767))
	b.put_u8(anim)
	b.put_u8(flags)
	_queue(b.data_array, false)


func teleport(why: String, pos: Vector3) -> void:
	send_json({"t": "tp", "why": why, "pos": [pos.x, pos.y, pos.z]})


# --- Leste e norte locais (a mesma conta do servidor: realtime.Tangent) ---------------------

static func tangent(pos: Vector3) -> Array:
	var up := pos.normalized()
	var ref := Vector3.UP if absf(up.y) <= 0.999 else Vector3(0, 0, 1)
	var east := ref.cross(up).normalized()
	return [east, up.cross(east)]


## Ângulo de uma direção no chão (0 = leste, anti-horário).
static func yaw_of(pos: Vector3, dir: Vector3) -> float:
	var t := tangent(pos)
	return atan2(dir.dot(t[1]), dir.dot(t[0]))


## Direção no chão a partir do ângulo.
static func facing_of(pos: Vector3, yaw: float) -> Vector3:
	var t := tangent(pos)
	return (t[0] as Vector3) * cos(yaw) + (t[1] as Vector3) * sin(yaw)


# --- Recebidas -----------------------------------------------------------------------------

func _on_binary(pkt: PackedByteArray) -> void:
	if pkt.is_empty():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = pkt
	var kind := b.get_u8()
	if kind == MSG_SNAPSHOT and pkt.size() >= 6:
		var ms := b.get_u32()
		var n := b.get_u8()
		var list: Array = []
		for i in n:
			var id := b.get_32()
			var pos := Vector3(b.get_float(), b.get_float(), b.get_float())
			var yaw := b.get_16() / 10000.0
			var anim := b.get_u8()
			var flags := b.get_u8()
			list.append([id, pos, yaw, anim, flags])
		snapshot.emit(ms, list)
	elif kind == MSG_CORRECTION and pkt.size() >= 16:
		b.get_u16()
		var pos := Vector3(b.get_float(), b.get_float(), b.get_float())
		var reason := b.get_u8()
		HitchLog.note("correção do servidor: %s" % REASONS.get(reason, "?"))
		corrected.emit(pos, reason)


func _on_text(text: String) -> void:
	var m: Variant = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	var d: Dictionary = m
	match str(d.get("t", "")):
		"welcome":
			is_welcomed = true
			_backoff = 1.0
			player_id = int(d.get("id", -1))
			send_hz = int(d.get("send_hz", 15))
			interp_delay_ms = int(d.get("interp_delay_ms", 110))
			animated_near = int(d.get("animated_near", 20))
			anim_lod_distance = float(d.get("anim_lod_distance", 30.0))
			chat_max = int(d.get("chat_max", 120))
			_sync_clock(float(d.get("server_ms", 0)), 0.0)
			_set_state("conectado")
			welcomed.emit(d)
		"pong":
			var rtt := _now() - float(d.get("c", _now()))
			ping_ms = int(rtt)
			_sync_clock(float(d.get("s", 0)), rtt)
		"enter":
			var p: Array = d.get("pos", [0, 0, 0])
			d["id"] = int(d["id"])
			d["pos"] = Vector3(float(p[0]), float(p[1]), float(p[2]))
			entered.emit(d)
		"leave":
			left.emit(int(d["id"]))
		"tp":
			teleport_result.emit(str(d.get("why", "")), bool(d.get("ok", false)))
		"chat":
			chat_received.emit(int(d["id"]), str(d.get("nick", "?")), str(d.get("text", "")))
		"emote":
			emote_received.emit(int(d["id"]), str(d.get("e", "")))
		"act":
			act_received.emit(int(d["id"]), str(d.get("a", "")), int(d.get("animal", 0)))
		"char":
			char_changed.emit(int(d["id"]), str(d.get("c", "")))
		"obj":
			object_event.emit(d.get("data", {}), int(d.get("by", 0)))
		"lot":
			lot_event.emit(d.get("lot", {}), int(d.get("by", 0)))
		"stamp":
			stamped.emit(d.get("result", {}))
		"blocked":
			blocked_changed.emit(int(d["id"]), bool(d.get("on", false)))
		"info":
			info.emit(str(d.get("text", "")))
		"kick":
			_kicked = true
			kicked.emit(str(d.get("reason", "")))


## Relógio do servidor: a resposta saiu de lá há rtt/2.
func _sync_clock(server_now: float, rtt: float) -> void:
	var off := server_now + rtt * 0.5 - _now()
	if not _has_offset or absf(off - _offset_ms) > 500.0:
		_offset_ms = off
		_has_offset = true
	else:
		_offset_ms = lerpf(_offset_ms, off, 0.2)
