extends SceneTree
## Monta as cenas das casas (scenes/houses/house_level_N.tscn) a partir das peças do
## Kenney Fantasy Town Kit. Rode de dentro de client/:
##
##   godot --headless --path . -s tools/montar_casas.gd          # só gera as cenas
##   godot --path . -s tools/montar_casas.gd -- --fotos=/tmp/c   # gera e tira fotos (janela)
##
## As peças do kit medem 1 × 1 × 1 e são escaladas por KIT_SCALE (1,5), o que deixa cada
## peça com 3 quadradinhos do lote (0,5) e a porta mais alta que o personagem (1,0).
## Paredes ficam na borda +X da sua casa da grade; `rot` gira em volta de Y (graus):
##   0 → borda leste (+X), 90 → norte (−Z), 180 → oeste (−X), 270 → sul (+Z, a frente).
## A frente da casa (porta) fica em +Z, que no lote é o lado sul, onde fica a plaquinha.
## Depois de gerar, dá para abrir e ajeitar as cenas no editor normalmente; só não rode
## este script de novo, senão ele sobrescreve.

const KIT := "res://assets/kenney/fantasy-town-kit/"
const KIT_SCALE := 1.5
const OUT := "res://scenes/houses/"

## Cada casa: largura × profundidade (em peças) e a lista [peça, x, andar, z, rot, escala].
## x e z contam peças a partir do canto; o script centraliza tudo na origem.
var houses := {
	1: _house_level_1(),
	2: _house_level_2(),
	3: _house_level_3(),
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for level: int in houses:
		var scene := _build(level, houses[level])
		var packed := PackedScene.new()
		packed.pack(scene)
		var path := OUT + "house_level_%d.tscn" % level
		var err := ResourceSaver.save(packed, path)
		print("casa %d → %s (erro %d, %d peças)" % [level, path, err, (houses[level]["pieces"] as Array).size()])
		scene.free()
	var photos := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos="):
			photos = a.substr(8)
	if photos.is_empty():
		quit()
		return
	_take_photos(photos)


## Paredes em volta de um retângulo w × d no andar `floor`. `special` troca peças:
## {"lado:índice": peça} com lado = s (sul/frente), n, l (leste), o (oeste).
static func _walls(w: int, d: int, floor: int, base: String, special: Dictionary) -> Array:
	var out: Array = []
	for i in w:
		out.append([special.get("s:%d" % i, base), i, floor, d - 1, 270])
		out.append([special.get("n:%d" % i, base), i, floor, 0, 90])
	for j in d:
		out.append([special.get("l:%d" % j, base), w - 1, floor, j, 0])
		out.append([special.get("o:%d" % j, base), 0, floor, j, 180])
	return out


## Barraca: 2 × 2 peças de madeira, porta na frente, janela de lado e telhado baixo.
func _house_level_1() -> Dictionary:
	var p := _walls(2, 2, 0, "wall-wood", {"s:0": "wall-wood-door", "l:1": "wall-wood-window-small", "o:0": "wall-wood-window-small"})
	# Telhado de duas águas baixo cobrindo as 2 × 2 peças (cumeeira de leste a oeste).
	p.append(["roof-gable", 0.5, 1, 0.5, 90, Vector3(2.0, 1.25, 1.9)])
	return {"w": 2, "d": 2, "pieces": p}


## Casinha: 3 × 2 de madeira, porta no meio, janelas com venezianas, duas águas e chaminé.
func _house_level_2() -> Dictionary:
	var p := _walls(3, 2, 0, "wall-wood-window-shutters", {
		"s:1": "wall-wood-door", "n:1": "wall-wood", "l:0": "wall-wood", "o:1": "wall-wood"})
	# Uma cumeeira só, de leste a oeste: cada peça cobre uma coluna e as duas fileiras.
	for i in 3:
		p.append(["roof-gable", i, 1, 0.5, 0, Vector3(1.0, 1.35, 2.0)])
	p.append(["chimney", 2, 1, 0, 0, Vector3(1, 1.4, 1)])
	return {"w": 3, "d": 2, "pieces": p}


## Casa grande: térreo de pedra 3 × 3, andar de cima de madeira 3 × 2 com sacada na
## frente, telhado alto e chaminé.
func _house_level_3() -> Dictionary:
	var p := _walls(3, 3, 0, "wall-window-stone", {"s:1": "wall-door", "n:1": "wall", "l:1": "wall", "o:1": "wall"})
	# Piso do andar de cima (também é o teto do térreo) e o andar de cima recuado.
	for i in 3:
		for j in 3:
			p.append(["planks", i, 1, j, 0, Vector3.ONE])
	var upper := _walls(3, 2, 1, "wall-wood-window-shutters", {"n:1": "wall-wood", "l:0": "wall-wood", "o:0": "wall-wood", "s:1": "wall-wood-door"})
	p.append_array(upper)
	# Sacada na frente do andar de cima (fileira z = 2), com grade de cerquinha.
	for i in 3:
		p.append(["fence", i, 1, 2, 270, Vector3.ONE])
	p.append(["fence", 0, 1, 2, 180, Vector3.ONE])
	p.append(["fence", 2, 1, 2, 0, Vector3.ONE])
	p.append(["lantern", 2.35, 1, 2.35, 0, Vector3(0.6, 0.45, 0.6)])
	for i in 3:
		p.append(["roof-high-gable", i, 2, 0.5, 0, Vector3(1.0, 1.0, 2.0)])
	p.append(["chimney", 0, 2, 0, 180, Vector3(1, 1.3, 1)])
	return {"w": 3, "d": 3, "pieces": p}


func _build(level: int, house: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "HouseLevel%d" % level
	var pieces := Node3D.new()
	pieces.name = "Pieces"
	pieces.scale = Vector3.ONE * KIT_SCALE
	root.add_child(pieces)
	pieces.owner = root
	var ox := (int(house["w"]) - 1) * 0.5
	var oz := (int(house["d"]) - 1) * 0.5
	var i := 0
	for entry: Array in house["pieces"]:
		var scene := load(KIT + str(entry[0]) + ".glb") as PackedScene
		if scene == null:
			push_error("peça não encontrada: %s" % entry[0])
			continue
		var node := scene.instantiate() as Node3D
		node.name = "%02d_%s" % [i, entry[0]]
		node.position = Vector3(float(entry[1]) - ox, float(entry[2]), float(entry[3]) - oz)
		node.rotation.y = deg_to_rad(float(entry[4]))
		if entry.size() > 5:
			node.scale = entry[5]
		pieces.add_child(node)
		node.owner = root
		i += 1
	return root


func _take_photos(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("bfe3f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7, 7)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("b9d77a")
	ground.material_override = gm
	world.add_child(ground)
	var cam := Camera3D.new()
	world.add_child(cam)
	var character := (load("res://assets/kenney/mini-characters/character-male-a.glb") as PackedScene).instantiate() as Node3D
	character.scale = Vector3.ONE / 0.671325
	world.add_child(character)
	for level: int in houses:
		var house := (load(OUT + "house_level_%d.tscn" % level) as PackedScene).instantiate() as Node3D
		world.add_child(house)
		var half := float(houses[level]["d"]) * KIT_SCALE * 0.5
		character.position = Vector3(0.9, 0, half + 0.6)
		character.rotation.y = 0.4
		for view in [["frente", Vector3(4.5, 3.6, 7.5)], ["tras", Vector3(-5.5, 4.5, -6.5)]]:
			cam.look_at_from_position(view[1], Vector3(0, 1.4, 0))
			for f in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/casa_%d_%s.png" % [dir, level, view[0]]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("foto: " + path)
		house.queue_free()
		await process_frame
	quit()
