class_name CountryTracker
extends Node
## Acompanha o país exato embaixo do personagem (BorderMap, ADR 0031), 8 vezes por segundo.
## Avisa quando ele muda (HUD, plaquinha de boas-vindas, carimbo do passaporte).
##
## Onde o 1:50m não tem país (um fiapo de mar entre a costa grosseira do globo e a de
## verdade, ou a célula ainda chegando), fica valendo o último país conhecido, ou o país
## principal do hexágono.

## O país embaixo do personagem mudou. `walked` = mudou andando (não por teleporte).
signal country_changed(code: String, walked: bool)

const UPDATE_EVERY := 0.125

var world: WorldData
var data: ChunkData
var player: Player
## País atual (código); "" antes de saber.
var current := ""

var _timer := 0.0
var _teleported := true


## Depois de um teleporte (casa, avião, modo dev): a próxima mudança não conta como "andou".
func mark_teleport() -> void:
	_teleported = true
	_timer = 0.0


func _process(delta: float) -> void:
	if world == null or player == null or not player.visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_EVERY
	var code := exact_at(player.global_position, player.cell_id)
	if code.is_empty() or code == current:
		if not code.is_empty():
			_teleported = false
		return
	var walked := not _teleported and not current.is_empty()
	current = code
	_teleported = false
	country_changed.emit(code, walked)


## País exato no ponto, com as quedas: célula ainda sem fronteiras → país principal do
## hexágono; fora de qualquer país no 1:50m → "" (quem chama mantém o anterior).
func exact_at(pos: Vector3, cell: int) -> String:
	var code := data.borders.country_at(pos, cell)
	if code == "?":
		return world.country_codes[cell] if world.is_land(cell) else ""
	return code


## Nome do país (os do 1:50m que não têm hexágono vêm das fronteiras).
func name_of(code: String) -> String:
	if world.countries.has(code):
		return str(world.countries[code])
	return data.borders.name_of(code)
