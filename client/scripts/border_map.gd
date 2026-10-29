class_name BorderMap
extends RefCounted
## Fronteiras pela posição exata (ADR 0031). O servidor manda, por célula (GET /borders),
## o país da célula inteira ou os segmentos de fronteira que passam perto dela, com o país
## sempre à ESQUERDA do segmento. O país de um ponto é o do segmento mais perto, se o ponto
## estiver à esquerda dele (a mesma regra que server/internal/world/borders.go testa contra
## o ponto em polígono).
##
## Segmentos "shared" separam dois países (viram a linha tracejada no chão); os outros são
## costa. Tudo em vetores unitários (direção a partir do centro do planeta).

## célula → {"country": código} ou {"segs": Array de [a: Vector3, b: Vector3, código, shared]}
var _cells := {}
## código → nome (todos os países que já apareceram)
var names := {}


func has_cell(cell: int) -> bool:
	return _cells.has(cell)


## Guarda a resposta de GET /borders.
func add_response(data: Dictionary) -> void:
	var codes: Array = []
	for c: Dictionary in data.get("countries", []):
		codes.append(str(c["code"]))
		names[str(c["code"])] = str(c["name"])
	for e: Dictionary in data.get("cells", []):
		var cell := int(e["cell"])
		var raw: Array = e.get("segs", [])
		if raw.is_empty():
			_cells[cell] = {"country": str(e.get("country", ""))}
			continue
		var segs: Array = []
		for k in range(0, raw.size(), 6):
			var a := WorldData.lat_lon_to_vec(float(raw[k]), float(raw[k + 1]))
			var b := WorldData.lat_lon_to_vec(float(raw[k + 2]), float(raw[k + 3]))
			segs.append([a, b, codes[int(raw[k + 4])], int(raw[k + 5]) == 1])
		_cells[cell] = {"segs": segs}


func remove_cell(cell: int) -> void:
	_cells.erase(cell)


func name_of(code: String) -> String:
	return str(names.get(code, code))


## Segmentos da célula ([] se a célula é de um país só ou ainda não chegou).
func segments(cell: int) -> Array:
	return (_cells.get(cell, {}) as Dictionary).get("segs", [])


## País no ponto exato `pos` (célula `cell`). "" = mar ou fora de qualquer país;
## "?" = a célula ainda não chegou do servidor.
func country_at(pos: Vector3, cell: int) -> String:
	var e: Dictionary = _cells.get(cell, {})
	if e.is_empty():
		return "?"
	if e.has("country"):
		return str(e["country"])
	var near := _nearest(pos.normalized(), e["segs"])
	return str(near["country"])


## Segmento mais perto de `dir` e de que lado ele está. Devolve {"country": código ou "",
## "seg": segmento, "dist": distância (radianos), "point": ponto mais perto (unitário)}.
static func _nearest(dir: Vector3, segs: Array) -> Dictionary:
	var ref := Vector3.UP if absf(dir.y) <= 0.999 else Vector3(0, 0, 1)
	var east := ref.cross(dir).normalized()
	var north := dir.cross(east)
	var best_d := INF
	var items: Array = []
	for s: Array in segs:
		var a := Vector2((s[0] as Vector3).dot(east), (s[0] as Vector3).dot(north))
		var b := Vector2((s[1] as Vector3).dot(east), (s[1] as Vector3).dot(north))
		# Só os da frente do planeta (o plano tangente dobra do outro lado).
		if (s[0] as Vector3).dot(dir) < 0.5 and (s[1] as Vector3).dot(dir) < 0.5:
			continue
		var e := b - a
		var l2 := e.length_squared()
		var t := 0.0 if l2 <= 0.0 else clampf(-a.dot(e) / l2, 0.0, 1.0)
		var c := a + e * t
		var d := c.length()
		var side := e.x * (-a.y) - e.y * (-a.x)
		items.append([d, side / maxf(sqrt(l2), 1e-12), s, c])
		best_d = minf(best_d, d)
	var out := {"country": "", "seg": [], "dist": best_d, "point": dir}
	var best_score := -INF
	for it: Array in items:
		if it[0] > best_d + 1e-6:  # Vector3 é float32: empate com folga
			continue
		if it[1] > best_score:
			best_score = it[1]
			out["country"] = it[2][2] if it[1] > 0.0 else ""
			out["seg"] = it[2]
			var c: Vector2 = it[3]
			out["point"] = (dir + east * c.x + north * c.y).normalized()
	return out


## Direção (no plano do chão em `pos`) que aponta para a fronteira mais perto, e a distância
## até ela em unidades. Usado pela barreira do passaporte para o personagem deslizar ao
## longo da linha. {} se não há segmento perto.
func border_normal(pos: Vector3, cell: int, radius: float) -> Dictionary:
	var segs := segments(cell)
	if segs.is_empty():
		return {}
	var dir := pos.normalized()
	var near := _nearest(dir, segs)
	if (near["seg"] as Array).is_empty():
		return {}
	var p: Vector3 = (near["point"] as Vector3) * radius
	var to := p - dir * radius
	to -= dir * to.dot(dir)
	return {"normal": to.normalized() if to.length() > 1e-6 else Vector3.ZERO, "dist": to.length()}
