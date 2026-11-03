class_name FrameWork
extends Node
## Mede quanto o jogo trabalhou em cada quadro (processo + física), sem contar o tempo em
## que o sistema deixou o programa parado. Nos testes headless em segundo plano, o macOS
## pausa o processo ~46 ms a cada ~3,6 s mesmo com um loop vazio do Godot (medido na
## fase 4.0); o tempo entre quadros acusa "travadas" que não são do jogo.
##
## Uso: FrameWork.attach(nó) cria os dois marcadores (primeiro e último a rodar) e
## FrameWork.last_ms traz o trabalho do quadro anterior.

static var last_ms := 0.0
static var _proc_start := 0
static var _phys_start := 0
static var _phys_ms := 0.0
static var _frame_ms := 0.0

var _first := true


static func attach(parent: Node) -> void:
	for first in [true, false]:
		var n := FrameWork.new()
		n.name = "FrameWorkFirst" if first else "FrameWorkLast"
		n._first = first
		n.process_priority = -1000000 if first else 1000000
		n.process_physics_priority = -1000000 if first else 1000000
		parent.add_child(n)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _first:
		last_ms = _frame_ms
		_frame_ms = _phys_ms
		_phys_ms = 0.0
		_proc_start = now
	else:
		_frame_ms += (now - _proc_start) / 1000.0


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _first:
		_phys_start = now
	else:
		_phys_ms += (now - _phys_start) / 1000.0
