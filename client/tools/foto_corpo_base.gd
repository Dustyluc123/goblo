extends SceneTree
## Corpo base "sem roupa" (fase 4.5, ADR 0054): os 12 corpos sem peças, com regata + short +
## sandália e com regata + short + sandália num tom de pele escolhido, de frente e de costas.
## Confere se braços, pernas e pés à mostra têm o formato do corpo (sem mangas nem barras).
##
##   tools/sem_foco.sh -s tools/foto_corpo_base.gd -- --foto=/tmp/corpo.png

const PARTS := ["female-a", "female-b", "female-c", "female-d", "female-e", "female-f", "male-a", "male-b", "male-c", "male-d", "male-e", "male-f"]
const BARE := {"body": {"item": "tank_top", "color": "#f4f1e4"}, "legs": {"item": "shorts", "color": "#e9c46a"}, "feet": {"item": "sandals", "color": "#c99a6b"}}
const HATS := ["", "bare", "bare-skin"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	CharacterLook.prepare(PARTS)
	var root := Node3D.new()
	get_root().add_child(root)
	var models: Array = []
	for r in HATS.size():
		for c in PARTS.size():
			var look := {"head": PARTS[c], "body": PARTS[c], "legs": PARTS[c], "skin": "", "accessory": "none"}
			var wear := {}
			if HATS[r].begins_with("bare"):
				wear = BARE.duplicate(true)
			if HATS[r] == "bare-skin":
				look["skin"] = "#6b4430"
			var mesh := CharacterLook.build_now(look, wear)
			var scene := load("res://assets/kenney/mini-characters/character-%s.glb" % PARTS[c]) as PackedScene
			var model := scene.instantiate() as Node3D
			root.add_child(model)
			model.position = Vector3((c - 5.5) * 0.74, -r * 1.12, 0)
			CharacterLook.apply(model, mesh, look, [])
			models.append(model)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.2
	cam.position = Vector3(0, -(HATS.size() - 1) * 0.56 + 0.45, 5)
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
	var out := str(args.get("foto", "user://corpo_base.png"))
	for k in 2:
		for m: Node3D in models:
			m.rotation.y = 0.35 + PI * k
		for i in 20:
			await process_frame
		get_root().get_texture().get_image().save_png(out.replace(".png", "_%s.png" % ["frente", "costas"][k]))
	print("corpo base: fotos salvas")
	quit()
