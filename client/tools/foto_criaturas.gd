extends SceneTree
## Fotos das criaturas feitas em código (fase 4.5): os animais novos, as lendas e o golem,
## todos com a mesma altura, numa pose da animação pedida (--anim=Walk), de frente e de lado.
##
##   tools/sem_foco.sh -s tools/foto_criaturas.gd -- --foto=/tmp/criaturas.png [--anim=Idle]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var anim := str(args.get("anim", "Walk"))
	var root := Node3D.new()
	get_root().add_child(root)
	var ids: Array = CreatureModels.IDS
	var cols := 7
	var models: Array = []
	for i in ids.size():
		var m := CreatureModels.instance(str(ids[i]))
		var h := maxf(Player._model_height(m), 0.01)
		m.scale = Vector3.ONE / h
		m.position = Vector3((i % cols - (cols - 1) * 0.5) * 1.5, -(i / cols) * 1.6, 0)
		root.add_child(m)
		var ap := m.find_child("AnimationPlayer") as AnimationPlayer
		if ap and ap.has_animation(anim):
			ap.play(anim)
			ap.seek(0.27 * ap.get_animation(anim).length, true)
		models.append(m)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.6
	cam.position = Vector3(0, -1.15, 8)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("cfe8f3")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	var out := str(args.get("foto", "user://criaturas.png"))
	for k in 2:
		for m: Node3D in models:
			m.rotation.y = 0.5 if k == 0 else PI / 2.0
		for i in 12:
			await process_frame
		get_root().get_texture().get_image().save_png(out.replace(".png", "_%s.png" % ["frente", "lado"][k]))
	print("criaturas: fotos salvas")
	quit()
