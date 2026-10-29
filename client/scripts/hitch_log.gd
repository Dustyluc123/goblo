class_name HitchLog
extends Node
## Registro de travadas (fase 2.6): todo quadro que demorar mais que LIMIT_MS vira uma
## linha em user://travadas.log com a hora, a duração, a posição, a qualidade e o que
## estava acontecendo naquele quadro.
##
## As partes do jogo contam o que fizeram com `HitchLog.note("lote 123 montado", ms)`
## (carga e descarga de pedaços, pedidos ao servidor, animais, troca de estação, objetos
## novos…). A compilação de shader vem dos contadores do Godot (pipelines compiladas na
## hora de desenhar travam o quadro; as do carregamento correm em segundo plano).
##
## A duração de um quadro só é conhecida no começo do seguinte, então a linha junta o que
## foi anotado no quadro anterior (o que travou) e no atual.

const LOG_FILE := "user://travadas.log"
const LIMIT_MS := 25.0
## Quantas travadas ficam na memória para o painel F2.
const KEEP := 8
## Arquivo maior que isto começa de novo (com a sessão atual).
const MAX_BYTES := 2_000_000

## Travadas desta sessão (as mais novas no fim): {"time", "ms", "where", "what"}.
static var recent: Array = []
static var total := 0
## Anotações do quadro atual e do anterior.
static var _now: PackedStringArray = []
static var _prev: PackedStringArray = []
static var _enabled := false

## Quem diz onde o personagem está e o que está acontecendo (GameMain).
var game: GameMain
## Só registra depois que o jogo começou (a carga inicial trava de propósito).
var armed := false
var _last_us := 0
var _pipes := {}
var _frames := 0


## Anota algo que aconteceu neste quadro (com o tempo gasto, se souber).
static func note(text: String, ms := -1.0) -> void:
	if not _enabled:
		return
	_now.append(text if ms < 0.0 else "%s (%.1f ms)" % [text, ms])


func _ready() -> void:
	_enabled = true
	# Antes de todos os outros nós: mede o quadro inteiro (processo + física + desenho).
	process_priority = -1000
	process_physics_priority = -1000
	for m in _pipe_monitors():
		_pipes[m] = Performance.get_monitor(m)


func _exit_tree() -> void:
	_enabled = false


static func _pipe_monitors() -> Array:
	return [Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SURFACE,
		Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
		Performance.PIPELINE_COMPILATIONS_CANVAS]


## Liga o registro: escreve o cabeçalho da sessão no arquivo.
func start(header: String) -> void:
	armed = true
	_last_us = Time.get_ticks_usec()
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(LOG_FILE) else FileAccess.WRITE
	var f := FileAccess.open(LOG_FILE, mode)
	if f == null:
		return
	if f.get_length() > MAX_BYTES:
		f.close()
		f = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	f.seek_end()
	f.store_line("")
	f.store_line("== sessão %s · %s" % [Time.get_datetime_string_from_system(false, true), header])
	f.close()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	_frames += 1
	var shader := _shader_note()
	if not shader.is_empty():
		_now.append(shader)
	if armed and ms > LIMIT_MS and _frames > 2:
		_record(ms)
	_prev = _now
	_now = PackedStringArray()


## Pipelines compiladas desde o último quadro ("" se nenhuma).
func _shader_note() -> String:
	var parts := PackedStringArray()
	var names := {Performance.PIPELINE_COMPILATIONS_DRAW: "na hora de desenhar",
		Performance.PIPELINE_COMPILATIONS_SURFACE: "de superfície", Performance.PIPELINE_COMPILATIONS_MESH: "de malha",
		Performance.PIPELINE_COMPILATIONS_SPECIALIZATION: "especialização", Performance.PIPELINE_COMPILATIONS_CANVAS: "da interface"}
	for m: int in _pipes:
		var v := Performance.get_monitor(m)
		var d := int(v - float(_pipes[m]))
		_pipes[m] = v
		if d > 0:
			parts.append("%d %s" % [d, names[m]])
	return "" if parts.is_empty() else "shaders compilados: " + ", ".join(parts)


func _record(ms: float) -> void:
	var what := PackedStringArray()
	what.append_array(_prev)
	what.append_array(_now)
	if game:
		what.append_array(game.hitch_context())
	what.append("processo %.1f ms, física %.1f ms, %d draw calls" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	var where := game.hitch_where() if game else ""
	var t := Time.get_time_string_from_system()
	var entry := {"time": t, "ms": ms, "where": where, "what": what}
	recent.append(entry)
	total += 1
	while recent.size() > KEEP:
		recent.pop_front()
	var line := "%s  %5.1f ms  %s  |  %s" % [t, ms, where, "; ".join(what) if not what.is_empty() else "nada anotado"]
	var f := FileAccess.open(LOG_FILE, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_FILE) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()


## Texto curto das últimas travadas, para o painel F2.
static func summary(count := 5) -> String:
	if recent.is_empty():
		return "Travadas (> %d ms): nenhuma" % int(LIMIT_MS)
	var lines := PackedStringArray(["Travadas (> %d ms): %d nesta sessão" % [int(LIMIT_MS), total]])
	for i in range(recent.size() - 1, maxi(-1, recent.size() - 1 - count), -1):
		var e: Dictionary = recent[i]
		var what: PackedStringArray = e["what"]
		var text := "; ".join(what.slice(0, 3)) if not what.is_empty() else "nada anotado"
		if text.length() > 90:
			text = text.substr(0, 87) + "…"
		lines.append("%s  %d ms  %s" % [e["time"], int(e["ms"]), text])
	return "\n".join(lines)
