extends SceneTree
## Análise das cabeças (fase 4.1): linha 1 a cabeça original, 2 o crânio (sem o cabelo), 3 só o
## cabelo (CharacterLook._is_hair_tri). tools/sem_foco.sh -s tools/analisar_cabecas.gd -- --foto=/tmp/c.png
func _key(v: PackedVector3Array, idx: PackedInt32Array, t: int) -> String:
	var ks: Array = []
	for k in 3:
		var p := v[idx[t + k]]
		ks.append("%d,%d,%d" % [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)])
	ks.sort()
	return "|".join(ks)

func _mesh(ha: Array, keep: Callable) -> ArrayMesh:
	var v: PackedVector3Array = ha[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = ha[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = ha[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = ha[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		if not keep.call(t):
			continue
		for k in 3:
			st.set_normal(nn[idx[t + k]]); st.set_uv(uv[idx[t + k]]); st.add_vertex(v[idx[t + k]])
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(CharacterLook.DIR + "Textures/colormap.png")
	st.set_material(m)
	return st.commit()

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--foto="):
			out = a.trim_prefix("--foto=")
	var parts := ["female-a", "female-b", "female-c", "female-d", "female-e", "female-f", "male-a", "male-b", "male-c", "male-d", "male-e", "male-f"]
	CharacterLook.prepare(parts)
	var count := {}
	for p: String in parts:
		var ha: Array = CharacterLook._parts[p]["head"]
		var s := {}
		for t in range(0, (ha[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 3):
			s[_key(ha[Mesh.ARRAY_VERTEX], ha[Mesh.ARRAY_INDEX], t)] = true
		for k in s:
			count[k] = int(count.get(k, 0)) + 1
	var root := Node3D.new()
	get_root().add_child(root)
	for i in parts.size():
		var ha: Array = CharacterLook._parts[parts[i]]["head"]
		var v: PackedVector3Array = ha[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = ha[Mesh.ARRAY_INDEX]
		var rows := [func(_t: int) -> bool: return true,
			func(t: int) -> bool: return not CharacterLook._is_hair_tri(v, idx, t),
			func(t: int) -> bool: return CharacterLook._is_hair_tri(v, idx, t)]
		for r in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh(ha, rows[r])
			mi.position = Vector3((i - 5.5) * 0.6, -r * 0.55, 0)
			mi.rotation.y = 0.5
			root.add_child(mi)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0.0, 6.2)
	cam.fov = 45
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("cfe8f3")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	for k in 2:
		for f in 30:
			await process_frame
		get_root().get_texture().get_image().save_png(out.replace(".png", "_%d.png" % k))
		for c in root.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).rotation.y += PI
	quit()
