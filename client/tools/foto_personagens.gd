extends SceneTree
## Fotos e medição do visual dos personagens (fase 4.0): monta vários visuais lado a lado
## (partes misturadas, pele, cabelo, penteados, óculos, roupas e capa), mede quanto custa
## montar cada malha e, com janela, salva uma foto.
##
## Medir (sem janela):  godot --headless --path . -s tools/foto_personagens.gd
## Foto (sem roubar o foco):  tools/sem_foco.sh -s tools/foto_personagens.gd -- --foto=/tmp/p.png

const LOOKS := [
	[{"head": "female-a", "body": "female-a", "legs": "female-a", "skin": "", "accessory": "none"}, {}],
	[{"head": "male-c", "body": "female-d", "legs": "male-a", "skin": "#6b4430", "accessory": "aid-glasses"},
		{"head": {"item": "beanie", "color": "#e86a6a"}, "body": {"item": "coat", "color": "#6d8fe8"}, "legs": {"item": "pants", "color": "#5b6f8c"}, "feet": {"item": "boots", "color": "#7a5233"}}],
	[{"head": "female-e", "body": "male-b", "legs": "female-c", "skin": "#f6d5b8", "accessory": "aid-sunglasses"},
		{"head": {"item": "straw_hat", "color": "#e9c46a"}, "body": {"item": "tank_top", "color": "#f4f1e4"}, "legs": {"item": "shorts", "color": "#e9c46a"}, "feet": {"item": "sandals", "color": "#c99a6b"}}],
	[{"head": "male-f", "body": "male-e", "legs": "male-e", "skin": "#9c6644", "accessory": "none"},
		{"head": {"item": "cap", "color": "#6d8fe8"}, "body": {"item": "scarf", "color": "#e86a6a"}, "back": {"item": "flag_cape", "color": "#f4f1e4"}}],
	[{"head": "female-b", "body": "female-f", "legs": "female-b", "skin": "#c98e62", "accessory": "none"},
		{"head": {"item": "fur_hat", "color": "#8d6e63"}, "body": {"item": "poncho", "color": "#c0392b"}}],
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var parts := ["female-a", "female-b", "female-c", "female-d", "female-e", "female-f", "male-a", "male-b", "male-c", "male-d", "male-e", "male-f"]
	var t0 := Time.get_ticks_usec()
	CharacterLook.prepare(parts)
	print("personagens: preparar as 12 partes %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var root := Node3D.new()
	get_root().add_child(root)
	var times := []
	for i in LOOKS.size():
		var look: Dictionary = LOOKS[i][0]
		var wear: Dictionary = LOOKS[i][1]
		var t1 := Time.get_ticks_usec()
		var arrays := CharacterLook._build(CharacterLook._job(look, wear))
		var t2 := Time.get_ticks_usec()
		var mesh := CharacterLook._finish(arrays)
		var t3 := Time.get_ticks_usec()
		times.append("thread %.1f ms + principal %.1f ms (%d vértices)" % [(t2 - t1) / 1000.0, (t3 - t2) / 1000.0, mesh.surface_get_array_len(0)])
		var scene := load("res://assets/kenney/mini-characters/character-%s.glb" % look["body"]) as PackedScene
		var model := scene.instantiate() as Node3D
		root.add_child(model)
		model.position = Vector3((i - (LOOKS.size() - 1) * 0.5) * 0.75, 0, 0)
		model.rotation.y = 0.35 if i % 2 == 0 else -0.35
		CharacterLook.apply(model, mesh, look, ["BRA", "ARG", "JPN", "FRA", "CAN"] if wear.has("back") else [])
		var aps := model.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			(aps[0] as AnimationPlayer).play("idle")
	for i in times.size():
		print("personagens: visual %d: %s" % [i + 1, times[i]])
	if not args.has("foto"):
		quit()
		return
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0.55, 2.6)
	cam.look_at(Vector3(0, 0.38, 0))
	cam.fov = 45
	if args.has("perto"):
		# --perto=N: só o visual N (1 a 5), de perto.
		var x := (int(args["perto"]) - 1 - (LOOKS.size() - 1) * 0.5) * 0.75
		cam.position = Vector3(x, 0.5, 1.1)
		cam.look_at(Vector3(x, 0.45, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("cfe8f3")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	# Uma volta: de frente e de costas (a capa).
	for k in 2:
		for i in 40:
			await process_frame
		get_root().get_texture().get_image().save_png(str(args["foto"]).replace(".png", "_%d.png" % k))
		for m in root.get_children():
			if m is Node3D and not (m is Camera3D) and not (m is DirectionalLight3D) and not (m is WorldEnvironment):
				(m as Node3D).rotation.y += PI
	print("personagens: fotos salvas")
	quit()
