class_name WorldData
extends RefCounted
## Definição do mundo recebida do servidor (GET /world.bin).
## O cliente nunca gera o mundo: só lê o que o servidor manda e desenha.
##
## Convenções (iguais às do servidor):
## - o planeta fica na origem, com o polo norte em +Y;
## - (lat 0°, lon 0°) fica em +Z e (0°, 90° L) em +X;
## - vertices[i] está em sentido anti-horário visto de fora;
## - neighbors[i][k] fica do outro lado da aresta vertices[i][k] → vertices[i][k+1];
## - canto k = normalize(centro + vizinho[k-1] + vizinho[k]) (não vem no arquivo).
##
## O formato binário está descrito em server/internal/world/binary.go.

const FORMAT_VERSION := 1

enum Biome { OCEAN, BEACH, TROPICAL_FOREST, FOREST, GRASSLAND, DESERT, MOUNTAIN, TUNDRA, ICE }

const BIOME_LABELS := {
	Biome.OCEAN: "Oceano", Biome.BEACH: "Praia", Biome.TROPICAL_FOREST: "Floresta tropical",
	Biome.FOREST: "Floresta", Biome.GRASSLAND: "Campo", Biome.DESERT: "Deserto",
	Biome.MOUNTAIN: "Montanha", Biome.TUNDRA: "Tundra", Biome.ICE: "Gelo",
}

## Pedaços (chunks): cada face de um cubo projetado na esfera é dividida em
## CHUNK_GRID × CHUNK_GRID quadrados. Com n = 50, ~16 células e ~100 unidades por pedaço.
const CHUNK_GRID := 16
## Até quantas células de distância da costa o oceano fica "raso".
const MAX_WATER_DEPTH := 6

var version := ""
var frequency := 0
var radius := 1000.0
var countries: Dictionary = {}  # código ISO A3 → nome
var biome_names := PackedStringArray()
var centers := PackedVector3Array()
var lats := PackedFloat32Array()
var lons := PackedFloat32Array()
var biomes := PackedByteArray()
var land := PackedByteArray()  # 1 = terra, 0 = oceano
var heights := PackedFloat32Array()  # topo da célula acima do nível do mar
var country_codes := PackedStringArray()
var neighbors: Array[PackedInt32Array] = []
var vertices: Array[PackedVector3Array] = []
## Distância (em células) até a terra mais próxima, para o oceano: 0 em terra.
var water_depth := PackedByteArray()

## Pedaço de cada célula, e as células, o centro e o raio (em unidades) de cada pedaço.
var cell_chunk := PackedInt32Array()
var chunk_cells: Dictionary = {}  # chave → PackedInt32Array
var chunk_center: Dictionary = {}  # chave → Vector3 unitário
var chunk_radius: Dictionary = {}  # chave → float
# As mesmas informações em arrays compactos, para buscas rápidas.
var _chunk_keys := PackedInt32Array()
var _chunk_dirs := PackedVector3Array()
var _chunk_rads := PackedFloat32Array()


## Monta o mundo a partir do binário do servidor. Devolve null se o formato estiver errado.
static func from_binary(data: PackedByteArray) -> WorldData:
	if data.size() < 24 or data.slice(0, 4).get_string_from_ascii() != "GOBW":
		push_error("mundo: assinatura inválida")
		return null
	var off := 4
	if data.decode_u16(off) != FORMAT_VERSION:
		push_error("mundo: formato %d não suportado" % data.decode_u16(off))
		return null
	off += 4  # formato + reservado
	var w := WorldData.new()
	w.frequency = data.decode_u32(off)
	w.radius = data.decode_float(off + 4)
	var n := data.decode_u32(off + 8)
	off += 12
	var codes := PackedStringArray()
	var nc := data.decode_u16(off)
	off += 2
	for i in nc:
		var code := data.slice(off, off + 3).get_string_from_ascii()
		var l := data[off + 3]
		w.countries[code] = data.slice(off + 4, off + 4 + l).get_string_from_utf8()
		codes.append(code)
		off += 4 + l
	var nb := data[off]
	off += 1
	for i in nb:
		var l := data[off]
		w.biome_names.append(data.slice(off + 1, off + 1 + l).get_string_from_ascii())
		off += 1 + l
	var expected := off + n * (12 + 1 + 24 + 1 + 2 + 4)
	if data.size() != expected:
		push_error("mundo: tamanho %d, esperado %d" % [data.size(), expected])
		return null

	var cf := data.slice(off, off + n * 12).to_float32_array()
	off += n * 12
	var counts := data.slice(off, off + n)
	off += n
	var neigh := data.slice(off, off + n * 24).to_int32_array()
	off += n * 24
	w.biomes = data.slice(off, off + n)
	off += n
	var cidx_off := off
	off += n * 2
	w.heights = data.slice(off, off + n * 4).to_float32_array()

	w.centers.resize(n)
	w.lats.resize(n)
	w.lons.resize(n)
	w.land.resize(n)
	w.country_codes.resize(n)
	for i in n:
		var c := Vector3(cf[3 * i], cf[3 * i + 1], cf[3 * i + 2])
		w.centers[i] = c
		w.lats[i] = rad_to_deg(asin(clampf(c.y, -1.0, 1.0)))
		w.lons[i] = rad_to_deg(atan2(c.x, c.z))
		w.land[i] = 1 if w.biomes[i] != Biome.OCEAN else 0
		var ci := data.decode_u16(cidx_off + 2 * i)
		w.country_codes[i] = codes[ci] if ci != 0xFFFF else ""
		var list := PackedInt32Array()
		for k in counts[i]:
			list.append(neigh[6 * i + k])
		w.neighbors.append(list)
	w._compute_corners()
	w._compute_water_depth()
	w._compute_chunks()
	return w


func _compute_corners() -> void:
	vertices.resize(centers.size())
	for i in centers.size():
		var c := centers[i]
		var nb := neighbors[i]
		var count := nb.size()
		var vs := PackedVector3Array()
		vs.resize(count)
		for k in count:
			vs[k] = (c + centers[nb[(k + count - 1) % count]] + centers[nb[k]]).normalized()
		vertices[i] = vs


func _compute_water_depth() -> void:
	var n := centers.size()
	water_depth.resize(n)
	water_depth.fill(MAX_WATER_DEPTH)
	var queue: Array[int] = []
	for i in n:
		if land[i] == 1:
			water_depth[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var d := water_depth[cur] + 1
		if d >= MAX_WATER_DEPTH:
			continue
		for nb in neighbors[cur]:
			if water_depth[nb] > d:
				water_depth[nb] = d
				queue.append(nb)


func _compute_chunks() -> void:
	var n := centers.size()
	cell_chunk.resize(n)
	var lists := {}
	for i in n:
		var key := chunk_key(centers[i])
		cell_chunk[i] = key
		if not lists.has(key):
			lists[key] = []  # Array é referência; PackedInt32Array seria copiado
		(lists[key] as Array).append(i)
	for key: int in lists:
		var cells := PackedInt32Array(lists[key])
		chunk_cells[key] = cells
		var sum := Vector3.ZERO
		for i in cells:
			sum += centers[i]
		var center := sum.normalized()
		var r := 0.0
		for i in cells:
			r = maxf(r, center.angle_to(centers[i]))
		chunk_center[key] = center
		chunk_radius[key] = r * radius + 15.0  # + meio hexágono
		_chunk_keys.append(key)
		_chunk_dirs.append(center)
		_chunk_rads.append(r * radius + 15.0)


## Pedaço de uma direção: face do cubo (0–5) e posição na grade dessa face.
static func chunk_key(dir: Vector3) -> int:
	var a := dir.abs()
	var face := 0
	var u := 0.0
	var v := 0.0
	if a.x >= a.y and a.x >= a.z:
		face = 0 if dir.x > 0 else 1
		u = dir.y / a.x
		v = dir.z / a.x
	elif a.y >= a.z:
		face = 2 if dir.y > 0 else 3
		u = dir.x / a.y
		v = dir.z / a.y
	else:
		face = 4 if dir.z > 0 else 5
		u = dir.x / a.z
		v = dir.y / a.z
	var iu := clampi(int((u + 1.0) * 0.5 * CHUNK_GRID), 0, CHUNK_GRID - 1)
	var iv := clampi(int((v + 1.0) * 0.5 * CHUNK_GRID), 0, CHUNK_GRID - 1)
	return (face * CHUNK_GRID + iv) * CHUNK_GRID + iu


## Pedaços cujo conteúdo pode estar a menos de `distance` unidades do ponto.
func chunks_near(point: Vector3, distance: float) -> Array[int]:
	var out: Array[int] = []
	for pair: Array in chunks_near_with_distance(point, distance):
		out.append(pair[0])
	return out


## Como chunks_near, mas devolve [chave, distância até a borda do pedaço].
## Primeiro descarta pelo produto escalar (barato) e só calcula o ângulo dos candidatos.
func chunks_near_with_distance(point: Vector3, distance: float) -> Array:
	var dir := point.normalized()
	var out: Array = []
	var max_angle := (distance + 120.0) / radius  # 120 ≥ maior raio de pedaço
	var min_dot := cos(minf(max_angle, PI))
	for i in _chunk_keys.size():
		var dot := dir.dot(_chunk_dirs[i])
		if dot < min_dot:
			continue
		var d := acos(clampf(dot, -1.0, 1.0)) * radius - _chunk_rads[i]
		if d <= distance:
			out.append([_chunk_keys[i], d])
	return out


## Sistema de coordenadas do topo plano da célula, igual ao Frame do servidor
## (server/internal/game/frame.go): P = center·top + east·x + north·y.
func cell_frame(id: int) -> Dictionary:
	var c := centers[id].normalized()
	var ref := Vector3.UP if absf(c.y) <= 0.999 else Vector3(0, 0, 1)
	var east := ref.cross(c).normalized()
	var north := c.cross(east)
	return {"center": c, "east": east, "north": north, "top": surface_radius(id)}


## Ponto (x, y) do plano da célula em coordenadas do mundo.
static func frame_point(f: Dictionary, x: float, y: float) -> Vector3:
	return (f["center"] as Vector3) * float(f["top"]) + (f["east"] as Vector3) * x + (f["north"] as Vector3) * y


## Coordenadas (x, y) de um ponto do mundo no plano da célula.
static func frame_coords(f: Dictionary, p: Vector3) -> Vector2:
	return Vector2(p.dot(f["east"]), p.dot(f["north"]))


## Base de um objeto em pé no plano da célula, girado `yaw` em volta do "para cima".
static func frame_basis(f: Dictionary, yaw: float, s: float = 1.0) -> Basis:
	var up: Vector3 = f["center"]
	var x := (f["east"] as Vector3).rotated(up, yaw)
	var z := x.cross(up)
	return Basis(x * s, up * s, z * s)


## Centro do pedaço (chunk) de uma célula.
func chunk_of_cell(id: int) -> int:
	return cell_chunk[id]


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
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
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


func biome_label(id: int) -> String:
	return BIOME_LABELS.get(biomes[id], "?")


static func lat_lon_to_vec(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


static func vec_to_lat_lon(v: Vector3) -> Vector2:
	var d := v.normalized()
	return Vector2(rad_to_deg(asin(clampf(d.y, -1.0, 1.0))), rad_to_deg(atan2(d.x, d.z)))


## "23,55° S · 46,63° O"
static func format_lat_lon(lat: float, lon: float) -> String:
	var ns := "N" if lat >= 0.0 else "S"
	var ew := "L" if lon >= 0.0 else "O"
	var text := "%.2f° %s · %.2f° %s" % [absf(lat), ns, absf(lon), ew]
	return text.replace(".", ",")
