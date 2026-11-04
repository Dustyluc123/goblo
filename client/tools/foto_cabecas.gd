extends SceneTree
## Grade de capturas (fase 4.1; cabeça inteira na 4.2): as 12 cabeças originais (colunas) ×
## sem chapéu, os 5 chapéus e os dois óculos (linhas), de frente e de costas. Confere se o
## chapéu cobre o cabelo de cada cabeça sem flutuar e se os óculos ficam nos olhos.
##
##   tools/sem_foco.sh -s tools/foto_cabecas.gd -- --foto=/tmp/cabecas.png

const PARTS := ["female-a", "female-b", "female-c", "female-d", "female-e", "female-f", "male-a", "male-b", "male-c", "male-d", "male-e", "male-f"]
const HATS := ["", "beanie", "fur_hat", "straw_hat", "sun_hat", "cap", "aid-glasses", "aid-sunglasses"]
const COLORS := {"beanie": "#e86a6a", "fur_hat": "#8d6e63", "straw_hat": "#e9c46a", "sun_hat": "#f4f1e4", "cap": "#6d8fe8"}


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
			if HATS[r].begins_with("aid-"):
				look["accessory"] = HATS[r]
			elif not HATS[r].is_empty():
				wear["head"] = {"item": HATS[r], "color": COLORS[HATS[r]]}
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
	cam.size = HATS.size() * 1.12 + 0.1
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
	var out := str(args.get("foto", "user://cabecas.png"))
	for k in 2:
		for m: Node3D in models:
			m.rotation.y = 0.35 + PI * k
		for i in 20:
			await process_frame
		get_root().get_texture().get_image().save_png(out.replace(".png", "_%s.png" % ["frente", "costas"][k]))
	print("cabeças: fotos salvas")
	quit()
