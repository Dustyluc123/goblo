class_name ShaderWarmup
extends RefCounted
## Pré-aquecimento dos shaders (fase 2.6), na tela de carregamento.
##
## Na primeira vez que um material aparece, a placa de vídeo precisa compilar o shader (e a
## combinação dele com o formato da malha, as sombras, o MultiMesh…). Isso trava o quadro
## em que acontece: uma árvore de outono, um animal novo, a casa ficando transparente na
## frente da câmera, as folhas caindo. Aqui tudo isso é desenhado uma vez, pequeno, na
## frente da câmera, enquanto a tela de carregamento está aberta; depois some.
##
## O Godot guarda os shaders compilados no disco, então das próximas vezes fica mais rápido.

## Quadros desenhados com tudo na tela (o primeiro compila; os outros pegam o que faltar,
## como as sombras e as partículas).
const FRAMES := 4
## Tamanho de cada coisa (unidades) e distância da câmera.
const ITEM := 0.35
const DIST := 7.0


## Desenha tudo uma vez e espera. Devolve quantas coisas foram aquecidas.
static func run(game: Node3D, camera: Camera3D, extra: Array[Node3D]) -> int:
	if DisplayServer.get_name() == "headless":
		return 0
	var root := Node3D.new()
	root.name = "ShaderWarmup"
	game.add_child(root)
	var items: Array[Node3D] = []
	var seen_mats := {}
	for name: String in ModelLibrary.cached_names():
		var lib := ModelLibrary.get_cached(name)
		var mesh: Mesh = lib.get("mesh")
		if mesh == null:
			continue
		# Como no bairro e na casa: malha comum com sombra.
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		items.append(mi)
		# Como na vegetação: MultiMesh com cor por instância e, nos modelos de cor por
		# vértice, o material de folhagem (vento).
		for kind: String in (["tree", "plant", "grass", "still"] if ModelLibrary.is_baked(lib) else [""]):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D.IDENTITY)
			mm.set_instance_color(0, Color.WHITE)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if not kind.is_empty():
				mmi.material_override = ModelLibrary.foliage_material(kind)
			items.append(mmi)
		# Lotes dos vizinhos: as peças viram uma malha juntada (com cor por vértice, outro
		# formato de malha), comum e pontilhada.
		if not ModelLibrary.is_baked(lib):
			var merged := _merged_format(mesh)
			if merged:
				var mm_i := MeshInstance3D.new()
				mm_i.mesh = merged
				items.append(mm_i)
				var mf := MeshInstance3D.new()
				mf.mesh = merged
				var fm := CameraOcclusion._fade_materials(merged)
				for i in fm.size():
					mf.set_surface_override_material(i, fm[i])
				items.append(mf)
		# Transparência na frente da câmera (pontilhado): uma vez por material.
		var key := ""
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			key += str(m.get_rid().get_id() if m else 0) + ","
		if not seen_mats.has(key):
			seen_mats[key] = true
			var faded := MeshInstance3D.new()
			faded.mesh = mesh
			var mats := CameraOcclusion._fade_materials(mesh)
			for i in mats.size():
				faded.set_surface_override_material(i, mats[i])
			items.append(faded)
	for n in extra:
		items.append(n)
	# Em grade, na frente da câmera.
	var cols := ceili(sqrt(float(items.size())))
	var xf := camera.global_transform
	for i in items.size():
		var n := items[i]
		root.add_child(n)
		var gx := (i % cols) - cols * 0.5
		var gy := (i / cols) - cols * 0.5
		var local := Vector3(gx * ITEM * 1.1, gy * ITEM * 1.1, -DIST)
		var size := _size_of(n)
		var s := ITEM / maxf(size, 0.01)
		n.global_transform = Transform3D(xf.basis.scaled(Vector3.ONE * s), xf * local)
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for f in FRAMES:
		await RenderingServer.frame_post_draw
	root.queue_free()
	return items.size()


## A malha no formato das malhas juntadas dos lotes (Neighborhood._merge_arrays).
static func _merged_format(mesh: Mesh) -> ArrayMesh:
	var jobs: Array = []
	for si in mesh.get_surface_count():
		jobs.append(["rest", mesh.surface_get_material(si), mesh.surface_get_arrays(si), Transform3D.IDENTITY])
	var groups: Dictionary = Neighborhood._merge_arrays(jobs)["rest"]
	if groups.is_empty():
		return null
	var out := ArrayMesh.new()
	for mat: Material in groups:
		var g: Dictionary = groups[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g["v"]
		arrays[Mesh.ARRAY_NORMAL] = g["n"]
		arrays[Mesh.ARRAY_TEX_UV] = g["uv"]
		arrays[Mesh.ARRAY_COLOR] = g["c"]
		arrays[Mesh.ARRAY_INDEX] = g["i"]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## Maior lado (aproximado) de uma coisa, para caber na grade.
static func _size_of(n: Node3D) -> float:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a := (n as MeshInstance3D).mesh.get_aabb()
		return maxf(a.size.x, maxf(a.size.y, a.size.z))
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh.mesh:
		var a := (n as MultiMeshInstance3D).multimesh.mesh.get_aabb()
		return maxf(a.size.x, maxf(a.size.y, a.size.z))
	return float(n.get_meta("warm_size", 1.0))
