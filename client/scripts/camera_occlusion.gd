class_name CameraOcclusion
extends Node
## Deixa semitransparente tudo o que fica entre a câmera e o personagem (casas inteiras com
## o telhado, árvores, pedras grandes, postes e decorações), com um fade suave entrando e
## saindo. Se a câmera estiver dentro de um objeto, ele some de vez (nada de tela inteira
## com a cor de uma parede). A câmera nunca se mexe sozinha por causa disso.
##
## A transparência é por pontilhado (dither): o objeto continua no passe opaco, com
## profundidade certa, sem problema de ordem de desenho entre as faces da casa. Usa o
## pontilhado do fade por distância do Godot (ruído de gradiente intercalado, bem mais
## regular que o alpha hash), com os limites escolhidos para a opacidade ficar constante
## (ver _set_opacity). Só os poucos objetos desbotados usam esse material (com `discard`);
## o resto do mundo continua com os shaders normais. A sombra continua inteira: uma cópia
## só de sombra fica no lugar.
## (A propriedade `transparency` do GeometryInstance3D não funciona no renderizador Mobile.)
##
## Quem está no caminho: árvores, pedras e decorações grandes (esferas, pelos objetos do
## servidor) e as caixas da casa e das decorações altas de cada lote (`Neighborhood.occluders`).
## A procura roda 10 vezes por segundo; o fade, a cada quadro, só nos desbotados.

const UPDATE_EVERY := 0.1
## Opacidade dos objetos no caminho (0 = invisível, 1 = opaco).
const ALPHA := 0.3
## Segundos para desbotar ou voltar.
const FADE_TIME := 0.25
## Só objetos com raio de copa a partir disso (grama, flores e pedrinhas ficam de fora).
const MIN_RADIUS := 0.45
## Pontos do personagem que precisam ficar visíveis (altura acima dos pés).
const BODY_POINTS := [0.35, 0.9]

var camera: CameraRig
var player: Node3D
var data: ChunkData
var vegetation: Vegetation
var neighborhood: Neighborhood

var _timer := 0.0
## Árvores desbotadas: id do objeto → entrada (ver _entry).
var _trees := {}
## Malhas desbotadas (casas e decorações): MeshInstance3D → entrada.
var _meshes := {}
## Objetos do servidor achados na última procura (id → objeto).
var _last_objects := {}


func _process(delta: float) -> void:
	if camera == null or data == null or data.world == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_EVERY
		_search()
	_animate(delta)


## Procura o que está no caminho e ajusta o alvo de opacidade de cada um.
func _search() -> void:
	var active := camera.far_amount < 0.3 and camera.distance < 40.0
	var cam := camera.global_position
	var up := player.global_position.normalized()
	var points: Array[Vector3] = []
	for h: float in BODY_POINTS:
		points.append(player.global_position + up * h)
	var trees := _trees_in_way(cam, points) if active else {}
	var meshes := _meshes_in_way(cam, points) if active else {}

	for id: int in _trees:
		var e: Dictionary = _trees[id]
		e["target"] = trees.get(id, 1.0)
		vegetation.set_object_visible(id, false)  # outra coisa pode ter reexibido
	for id: int in trees:
		if not _trees.has(id):
			var e := _fade_tree(_last_objects.get(id, {}))
			if not e.is_empty():
				e["target"] = trees[id]
				_trees[id] = e

	for key: Variant in _meshes.keys():
		# O lote pode ter sido refeito (nó apagado): sem tipo na variável até conferir.
		if not is_instance_valid(key):
			_free_entry(_meshes[key])
			_meshes.erase(key)
			continue
		(_meshes[key] as Dictionary)["target"] = meshes.get(key, 1.0)
	for mi: MeshInstance3D in meshes:
		if not _meshes.has(mi):
			var e := _fade_mesh(mi)
			e["target"] = meshes[mi]
			_meshes[mi] = e


## Árvores, pedras e decorações grandes no caminho: id → opacidade alvo.
func _trees_in_way(cam: Vector3, points: Array[Vector3]) -> Dictionary:
	var out := {}
	_last_objects.clear()
	var head: Vector3 = points[points.size() - 1]
	var mid := (cam + head) * 0.5
	var reach := cam.distance_to(head) * 0.5 + 4.0
	for o: Dictionary in data.objects_near(mid, reach):
		var kind := str(o["kind"])
		if not (kind == "tree" or kind == "rock" or kind == "decor") or o.get("hidden", false):
			continue
		var lib := ModelLibrary.get_model(o["model"])
		if lib.is_empty():
			continue
		var aabb: AABB = lib["aabb"]
		var s := float(o["scale"])
		var radius := maxf(aabb.size.x, aabb.size.z) * s * 0.5
		if radius < MIN_RADIUS:
			continue
		var center: Vector3 = (o["pos"] as Vector3) + (o["basis"] as Basis) * aabb.get_center()
		var r := maxf(radius, aabb.size.y * s * 0.5) * 0.85
		var target := 1.0
		if cam.distance_to(center) < r * 0.8:
			target = 0.0  # câmera dentro da copa: some de vez
		else:
			for p in points:
				var closest := Geometry3D.get_closest_point_to_segment(center, cam, p)
				if closest.distance_to(center) < r and closest.distance_to(p) > 0.3:
					target = ALPHA
					break
		if target < 1.0:
			out[o["id"]] = target
			_last_objects[o["id"]] = o
	return out


## Casas e decorações dos lotes no caminho: MeshInstance3D → opacidade alvo.
func _meshes_in_way(cam: Vector3, points: Array[Vector3]) -> Dictionary:
	var out := {}
	var head: Vector3 = points[points.size() - 1]
	var reach := cam.distance_to(head) + 12.0
	for lot: Dictionary in data.all_lots():
		var node := neighborhood.lot_node(int(lot["id"]))
		if node == null or not node.has_meta("occluders"):
			continue
		for occ: Dictionary in node.get_meta("occluders"):
			var mi: MeshInstance3D = occ["mi"]
			if not is_instance_valid(mi):
				continue
			var xf: Transform3D = occ["xf"]
			if xf.origin.distance_to(head) > reach:
				continue
			var half: Vector3 = occ["half"]
			var box := AABB(-half, half * 2.0)
			var inv := xf.affine_inverse()
			var a := inv * cam
			var target := 1.0
			if box.has_point(a):
				target = 0.0  # câmera dentro da casa (ou do telhado): some de vez
			else:
				for p in points:
					var b := inv * p
					if not box.has_point(b) and box.intersects_segment(a, b) != null:
						target = ALPHA
						break
			if target < float(out.get(mi, 1.0)):
				out[mi] = target
	return out


## Fade suave: aproxima a opacidade do alvo; quando volta a 1, devolve o objeto original.
func _animate(delta: float) -> void:
	var step := delta / FADE_TIME
	for id: int in _trees.keys():
		var e: Dictionary = _trees[id]
		if _step_alpha(e, step):
			_free_entry(e)
			_trees.erase(id)
			var o: Dictionary = e["o"]
			vegetation.set_object_visible(id, not o.get("hidden", false))
	for key: Variant in _meshes.keys():
		var e: Dictionary = _meshes[key]
		if not is_instance_valid(key):
			_free_entry(e)
			_meshes.erase(key)
			continue
		if _step_alpha(e, step):
			var mi := key as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, null)
			mi.cast_shadow = e["cast_shadow"]
			_free_entry(e)
			_meshes.erase(key)


## Anda um passo da opacidade. Devolve true quando terminou de voltar ao normal.
func _step_alpha(e: Dictionary, step: float) -> bool:
	var a := move_toward(float(e["alpha"]), float(e["target"]), step)
	if not is_equal_approx(a, float(e["alpha"])):
		e["alpha"] = a
		for m: BaseMaterial3D in e["mats"]:
			_set_opacity(m, a)
	return a >= 1.0 and float(e["target"]) >= 1.0


## Materiais pontilhados (cópias só deste objeto, para o fade ser individual).
static func _fade_materials(mesh: Mesh, overrides: MeshInstance3D = null) -> Array:
	var mats := []
	for i in mesh.get_surface_count():
		var src: Material = overrides.get_active_material(i) if overrides else mesh.surface_get_material(i)
		if not (src is BaseMaterial3D):
			mats.append(src)
			continue
		var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		_set_opacity(m, 1.0)
		mats.append(m)
	return mats


## Opacidade constante `a` com o pontilhado do fade por distância. O shader faz
## fade = smoothstep(min, max, distância); com min = -K enorme, a distância (poucas
## dezenas) quase não muda a conta e fade ≈ smoothstep(c) com c = K / (max + K).
## Basta escolher max para smoothstep(c) = a.
const _FAR := 100000.0


static func _set_opacity(m: BaseMaterial3D, a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	var c := maxf(0.5 - sin(asin(1.0 - 2.0 * a) / 3.0), 0.0001)  # inversa do smoothstep
	m.distance_fade_min_distance = -_FAR
	m.distance_fade_max_distance = _FAR / c - _FAR


static func _shadow_twin(mesh: Mesh, xf: Transform3D, parent: Node) -> MeshInstance3D:
	var twin := MeshInstance3D.new()
	twin.mesh = mesh
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(twin)
	twin.global_transform = xf
	return twin


func _fade_tree(o: Dictionary) -> Dictionary:
	if o.is_empty():
		return {}
	var lib := ModelLibrary.get_model(str(o.get("drawn_model", o["model"])))
	var ghost := MeshInstance3D.new()
	ghost.mesh = lib["mesh"]
	ghost.transform = Transform3D(o["basis"], o["pos"])
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mats := _fade_materials(ghost.mesh)
	for i in mats.size():
		ghost.set_surface_override_material(i, mats[i])
	add_child(ghost)
	var twin := _shadow_twin(ghost.mesh, ghost.transform, self)
	vegetation.set_object_visible(o["id"], false)
	return {"o": o, "nodes": [ghost, twin], "mats": _only_base(mats), "alpha": 1.0, "target": 1.0}


func _fade_mesh(mi: MeshInstance3D) -> Dictionary:
	var mats := _fade_materials(mi.mesh, mi)
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	var e := {"nodes": [], "mats": _only_base(mats), "alpha": 1.0, "target": 1.0, "cast_shadow": mi.cast_shadow}
	if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		e["nodes"] = [_shadow_twin(mi.mesh, mi.global_transform, self)]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return e


static func _only_base(mats: Array) -> Array:
	return mats.filter(func(m: Variant) -> bool: return m is BaseMaterial3D)


static func _free_entry(e: Dictionary) -> void:
	for n: Variant in e.get("nodes", []):
		if is_instance_valid(n):
			(n as Node).queue_free()


## Quantos objetos estão desbotados agora (testes).
func faded_count() -> int:
	return _trees.size() + _meshes.size()


## Opacidade atual mais baixa entre os desbotados (testes): 1 = nada desbotado.
func min_alpha() -> float:
	var a := 1.0
	for e: Dictionary in _trees.values() + _meshes.values():
		a = minf(a, float(e["alpha"]))
	return a
