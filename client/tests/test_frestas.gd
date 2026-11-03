extends SceneTree
## Frestas entre hexágonos (fase 3.6): monta a colisão do chão como o jogo monta (pedaços em
## thread, pelo Terrain) e joga raios de cima para baixo nas bordas e nos cantos de muitas
## células: montanhas, litoral, pentágonos e a célula 20575 do Chile. Todo raio precisa
## acertar o chão, inclusive exatamente em cima das arestas e dos cantos.
##
## Precisa do mundo em cache (user://cache/world.bin: abra o jogo uma vez com o servidor).
## Uso: godot --headless --path . -s tests/test_frestas.gd

const CHILE := 20575
## Quantas células de cada tipo entram (além das obrigatórias).
const SAMPLE := 400

var _w: WorldData
var _terrain: Terrain
var _fails := 0
var _rays := 0
var _by_kind := {}


func _init() -> void:
	if not FileAccess.file_exists("user://cache/world.bin"):
		print("frestas: sem mundo em cache (abra o jogo uma vez com o servidor rodando)")
		quit(1)
		return
	_w = WorldData.from_binary(FileAccess.get_file_as_bytes("user://cache/world.bin"))
	_run.call_deferred()


func _run() -> void:
	var cells := _pick_cells()
	print("frestas: %d células (montanha, litoral, pentágonos, Chile)" % cells.size())
	_terrain = Terrain.new()
	root.add_child(_terrain)
	_terrain.setup_collision(_w)
	var by_area := {}
	for c in cells:
		var key := _w.chunk_of_cell(c)
		if not by_area.has(key):
			by_area[key] = []
		(by_area[key] as Array).append(c)
	for key: int in by_area:
		for c: int in by_area[key]:
			# Colisão como no jogo: só perto do ponto, pedaços montados em thread, um por quadro.
			_terrain.update_collision(_w.centers[c] * _w.radius, 99)
			while _terrain.pending_collision() > 0:
				await process_frame
			await physics_frame
			await physics_frame
			_cast_cell(c)
	await _check_rescue()
	if not _by_kind.is_empty():
		print("falhas por tipo de ponto: %s" % [_by_kind])
	print("frestas: %d raios, %s" % [_rays, "tudo certo" if _fails == 0 else "%d FALHAS" % _fails])
	quit(1 if _fails > 0 else 0)


## Células com degraus: todas as de montanha com vizinho mais baixo, o litoral e os 12
## pentágonos (amostra espalhada pelo globo para não demorar).
func _pick_cells() -> Array:
	var steps: Array = []
	var coast: Array = []
	var pent: Array = []
	for i in _w.centers.size():
		var nb := _w.neighbors[i]
		if nb.size() == 5:
			pent.append(i)
		if _w.land[i] == 0:
			continue
		var has_sea := false
		var has_step := false
		for j in nb:
			if _w.land[j] == 0:
				has_sea = true
			elif absf(_w.heights[j] - _w.heights[i]) > 0.3:
				has_step = true
		if has_sea:
			coast.append(i)
		elif has_step:
			steps.append(i)
	var out: Array = [CHILE]
	out.append_array(pent)
	for list: Array in [steps, coast]:
		var stride := maxi(1, list.size() / SAMPLE)
		for k in range(0, list.size(), stride):
			out.append(list[k])
	# Os vizinhos do Chile também (os dois lados de cada degrau).
	for j in _w.neighbors[CHILE]:
		out.append(j)
	return out


func _cast_cell(i: int) -> void:
	var c := _w.centers[i]
	var poly := _w.vertices[i]
	var n := poly.size()
	var space := _terrain.get_world_3d().direct_space_state
	var points: Array[Vector3] = []
	var kinds: Array[String] = []
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		points.append(a)  # canto exato
		kinds.append("canto")
		for t in [0.25, 0.5, 0.75]:
			var e := a.slerp(b, t)
			points.append(e)  # em cima da aresta
			kinds.append("aresta")
			# Um pouco para cada lado da aresta (0,02 e 0,15 unidade).
			for d in [0.00002, 0.00015]:
				points.append((e + (c - e).normalized() * d).normalized())
				points.append((e - (c - e).normalized() * d).normalized())
				kinds.append("dentro %.2f" % (d * 1000.0))
				kinds.append("fora %.2f" % (d * 1000.0))
	for pi in points.size():
		var p := points[pi]
		_rays += 1
		var top := p * (_w.radius + 30.0)
		var bottom := p * (_w.radius - 5.0)
		var q := PhysicsRayQueryParameters3D.create(top, bottom)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			_fails += 1
			_by_kind[kinds[pi]] = int(_by_kind.get(kinds[pi], 0)) + 1
			if _fails <= 60:
				var cell := _w.find_cell(p, i)
				print("FALHOU [%s] célula %d (lat %.2f, lon %.2f): raio em %s não acertou o chão (célula do ponto %d, pedaço %d montado %s, %d pedaços)" % [
					kinds[pi], i, _w.lats[i], _w.lons[i], p, cell, _w.chunk_of_cell(cell), _terrain._shapes.has(_w.chunk_of_cell(cell)), _terrain._shapes.size()])


## Rede de segurança: o personagem posto dentro do hexágono do Chile (abaixo do topo) volta
## para cima em poucos quadros.
func _check_rescue() -> void:
	_terrain.update_collision(_w.centers[CHILE] * _w.radius, -1)
	var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	player.autopilot = true
	root.add_child(player)
	player.spawn(_w, CHILE)
	var inside := _w.centers[CHILE] * (_w.surface_radius(CHILE) - 2.0)
	player.global_position = inside
	player.velocity = Vector3.ZERO
	for i in 6:
		await physics_frame
	var r := player.global_position.length()
	var top := _w.surface_radius(CHILE)
	if r >= top - 0.1 and player.global_position.normalized().dot(_w.centers[CHILE]) > 0.9999:
		print("ok     personagem dentro do hexágono %d volta para cima (%.2f → %.2f, topo %.2f)" % [CHILE, inside.length(), r, top])
	else:
		_fails += 1
		print("FALHOU personagem dentro do hexágono %d ficou em %.2f (topo %.2f)" % [CHILE, r, top])
	player.queue_free()
