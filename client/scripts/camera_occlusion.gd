class_name CameraOcclusion
extends Node
## Deixa semitransparentes os objetos grandes entre a câmera e o personagem (árvores,
## pedras grandes, casas), para ele nunca sumir atrás de nada.
##
## Tudo no CPU, por objeto, 10 vezes por segundo: as árvores são instâncias de MultiMesh,
## então a instância é escondida e uma cópia com material transparente aparece no lugar;
## nas casas, as superfícies ganham o material transparente. Assim nenhum shader do mundo
## precisa de `discard` (que desligaria o early-z e custaria fps em todo lugar).
## (A propriedade `transparency` do GeometryInstance3D não funciona no renderizador Mobile.)

const UPDATE_EVERY := 0.1
## Opacidade dos objetos no caminho (0 = invisível, 1 = opaco).
const ALPHA := 0.32
## Só objetos com raio de copa a partir disso (grama, flores e pedrinhas ficam de fora).
const MIN_RADIUS := 0.45

var camera: CameraRig
var player: Node3D
var data: ChunkData
var vegetation: Vegetation
var neighborhood: Neighborhood

var _timer := 0.0
## id do objeto → {"ghost": MeshInstance3D, "o": Dictionary}
var _faded := {}
## casas desbotadas: MeshInstance3D → true
var _houses := {}
## material original → cópia transparente
static var _see_through := {}


## Cópia transparente de um material (cacheada).
static func see_through(mat: Material) -> Material:
	if mat == null or not (mat is BaseMaterial3D):
		return mat
	if not _see_through.has(mat):
		var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		m.albedo_color.a = ALPHA
		_see_through[mat] = m
	return _see_through[mat]


func _process(delta: float) -> void:
	if camera == null or data == null or data.world == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_EVERY
	var active := camera.far_amount < 0.3 and camera.distance < 40.0
	var cam := camera.global_position
	var head := player.global_position + player.global_position.normalized() * 0.8
	_update_trees(cam, head, active)
	_update_houses(cam, head, active)


func _update_trees(cam: Vector3, head: Vector3, active: bool) -> void:
	var want := {}
	if active:
		var mid := (cam + head) * 0.5
		var reach := cam.distance_to(head) * 0.5 + 4.0
		for o: Dictionary in data.objects_near(mid, reach):
			var kind := str(o["kind"])
			if not (kind == "tree" or kind == "rock" or kind == "decor"):
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
			var closest := Geometry3D.get_closest_point_to_segment(center, cam, head)
			if closest.distance_to(center) < r and closest.distance_to(head) > 0.3:
				want[o["id"]] = o
	for id: int in _faded.keys():
		if not want.has(id):
			_restore_tree(id)
		else:
			vegetation.set_object_visible(id, false)  # outra coisa pode ter reexibido
	for id: int in want:
		if not _faded.has(id):
			_fade_tree(want[id])


func _fade_tree(o: Dictionary) -> void:
	var lib := ModelLibrary.get_model(o["model"])
	var ghost := MeshInstance3D.new()
	ghost.mesh = lib["mesh"]
	ghost.transform = Transform3D(o["basis"], o["pos"])
	for i in ghost.mesh.get_surface_count():
		ghost.set_surface_override_material(i, see_through(ghost.mesh.surface_get_material(i)))
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	vegetation.set_object_visible(o["id"], false)
	_faded[o["id"]] = {"ghost": ghost, "o": o}


func _restore_tree(id: int) -> void:
	var f: Dictionary = _faded[id]
	(f["ghost"] as Node).queue_free()
	_faded.erase(id)
	var o: Dictionary = f["o"]
	vegetation.set_object_visible(id, not o.get("hidden", false))


func _update_houses(cam: Vector3, head: Vector3, active: bool) -> void:
	var hit := {}
	if active:
		for lot: Dictionary in data.all_lots():
			var node := neighborhood.lot_node(int(lot["id"]))
			if node == null:
				continue
			for c in node.get_children():
				if not (c is MeshInstance3D and c.has_meta("house")):
					continue
				var mi := c as MeshInstance3D
				var inv := mi.global_transform.affine_inverse()
				var a := inv * cam
				var b := inv * head
				var box := mi.get_aabb()
				# Ignora se o personagem está dentro da caixa (encostado na parede).
				if box.has_point(b):
					continue
				if box.intersects_segment(a, b) != null:
					hit[mi] = true
	for mi: MeshInstance3D in _houses.keys():
		if not is_instance_valid(mi):
			_houses.erase(mi)
		elif not hit.has(mi):
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, null)
			_houses.erase(mi)
	for mi: MeshInstance3D in hit:
		if not _houses.has(mi):
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, see_through(mi.mesh.surface_get_material(i)))
			_houses[mi] = true


## Quantos objetos estão desbotados agora (testes).
func faded_count() -> int:
	return _faded.size() + _houses.size()
