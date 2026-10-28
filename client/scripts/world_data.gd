class_name WorldData
extends RefCounted
## Definição do mundo recebida do servidor (GET /world).
## O cliente nunca gera o mundo: só lê o que o servidor manda e desenha.
##
## Convenções (iguais às do servidor):
## - o planeta fica na origem, com o polo norte em +Y;
## - (lat 0°, lon 0°) fica em +Z e (0°, 90° L) em +X;
## - vertices[i] está em sentido anti-horário visto de fora;
## - neighbors[i][k] fica do outro lado da aresta vertices[i][k] → vertices[i][k+1].

var frequency := 0
var radius := 100.0
var countries: Dictionary = {}  # código ISO A3 → nome
var centers := PackedVector3Array()
var lats := PackedFloat32Array()
var lons := PackedFloat32Array()
var land := PackedByteArray()  # 1 = terra, 0 = oceano
var heights := PackedFloat32Array()  # altura do topo da célula acima do nível do mar
var country_codes := PackedStringArray()
var neighbors: Array[PackedInt32Array] = []
var vertices: Array[PackedVector3Array] = []


## Monta o mundo a partir do JSON do servidor. Devolve null se o formato estiver errado.
static func from_json(text: String) -> WorldData:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("cells"):
		return null
	var w := WorldData.new()
	w.frequency = int(data["frequency"])
	w.radius = float(data["radius"])
	w.countries = data.get("countries", {})
	var cells: Array = data["cells"]
	var n := cells.size()
	w.centers.resize(n)
	w.lats.resize(n)
	w.lons.resize(n)
	w.land.resize(n)
	w.country_codes.resize(n)
	w.heights.resize(n)
	for i in n:
		var c: Dictionary = cells[i]
		if int(c["id"]) != i:
			push_error("célula fora de ordem: posição %d tem id %s" % [i, c["id"]])
			return null
		w.centers[i] = _vec(c["center"])
		w.lats[i] = float(c["lat"])
		w.lons[i] = float(c["lon"])
		w.land[i] = 1 if c["terrain"] == "land" else 0
		w.heights[i] = 0.8 if w.land[i] == 1 else 0.0
		w.country_codes[i] = str(c["country"])
		var nb := PackedInt32Array()
		for x: Variant in c["neighbors"]:
			nb.append(int(x))
		w.neighbors.append(nb)
		var vs := PackedVector3Array()
		for v: Variant in c["vertices"]:
			vs.append(_vec(v))
		w.vertices.append(vs)
	return w


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func cell_count() -> int:
	return centers.size()


func is_land(id: int) -> bool:
	return land[id] == 1


## Distância do centro do planeta até o topo da célula.
func surface_radius(id: int) -> float:
	return radius + heights[id]


## Célula que contém o ponto (a de centro mais próximo da direção do ponto).
## Com `hint` (a célula anterior), anda pelos vizinhos até não melhorar: O(1) por quadro.
func find_cell(point: Vector3, hint: int = -1) -> int:
	var d := point.normalized()
	if hint < 0 or hint >= centers.size():
		var best := 0
		var best_dot := -2.0
		for i in centers.size():
			var v := centers[i].dot(d)
			if v > best_dot:
				best_dot = v
				best = i
		return best
	var cur := hint
	var cur_dot := centers[cur].dot(d)
	var moved := true
	while moved:
		moved = false
		for nb in neighbors[cur]:
			var v := centers[nb].dot(d)
			if v > cur_dot:
				cur_dot = v
				cur = nb
				moved = true
	return cur


## Célula de terra mais próxima (busca em largura pelos vizinhos).
func nearest_land(id: int) -> int:
	var seen := {id: true}
	var queue: Array[int] = [id]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if is_land(cur):
			return cur
		for nb in neighbors[cur]:
			if not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	return id


func country_name(id: int) -> String:
	var code := country_codes[id]
	if code.is_empty():
		return "Oceano" if not is_land(id) else "Terra sem país"
	return str(countries.get(code, code))


static func lat_lon_to_vec(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


## "23,55° S · 46,63° O"
static func format_lat_lon(lat: float, lon: float) -> String:
	var ns := "N" if lat >= 0.0 else "S"
	var ew := "L" if lon >= 0.0 else "O"
	var text := "%.2f° %s · %.2f° %s" % [absf(lat), ns, absf(lon), ew]
	return text.replace(".", ",")
