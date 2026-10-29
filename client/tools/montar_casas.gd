extends SceneTree
## Monta as cenas das casas (scenes/houses/house_level_N.tscn) a partir das peças do
## Kenney Fantasy Town Kit. Rode de dentro de client/:
##
##   godot --headless --path . -s tools/montar_casas.gd          # só gera as cenas
##   godot --path . -s tools/montar_casas.gd -- --fotos=/tmp/c   # gera e tira fotos (janela)
##   godot --path . -s tools/montar_casas.gd -- --fotos=/tmp/c --so-fotos   # só fotografa
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
		if "--so-fotos" in OS.get_cmdline_user_args():
			break
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


## Espessura das paredes do kit, de dentro da peça até a face de fora (borda +X).
## As paredes comuns têm 0,1; a de pedra com janela é mais grossa (sai 0,025 para fora).
const WALL_DEPTH := {"wall-window-stone": 0.125}
const WALL_DEPTH_DEFAULT := 0.1
## Recuo das bordas de fora do piso de tábuas, para a ponta ficar dentro da parede ou da
## grade em vez de no mesmo plano que a face de fora delas.
const PLANKS_INSET := 0.015


## Paredes em volta de um retângulo w × d no andar `floor`. `special` troca peças:
## {"lado:índice": peça} com lado = s (sul/frente), n, l (leste), o (oeste).
##
## As peças do kit vão de ponta a ponta da casa da grade. Nos cantos, a parede sul (ou
## norte) e a leste (ou oeste) ocupariam o mesmo cantinho, com faces no mesmo plano: era
## isso que fazia a textura piscar (z-fighting). Então as paredes norte e sul vão até o
## canto e as paredes leste e oeste param na face de dentro delas (encurtadas).
static func _walls(w: int, d: int, floor: int, base: String, special: Dictionary) -> Array:
	var out: Array = []
	for i in w:
		out.append([special.get("s:%d" % i, base), i, floor, d - 1, 270])
		out.append([special.get("n:%d" % i, base), i, floor, 0, 90])
	for side in [["l", w - 1, 0], ["o", 0, 180]]:
		var col: int = side[1]
		for j in d:
			var piece: String = special.get("%s:%d" % [side[0], j], base)
			var cut_n := _depth(special.get("n:%d" % col, base)) if j == 0 else 0.0
			var cut_s := _depth(special.get("s:%d" % col, base)) if j == d - 1 else 0.0
			# Encurta no eixo z da peça e desloca o centro para longe dos cantos.
			var length := 1.0 - cut_n - cut_s
			out.append([piece, col, floor, j + (cut_n - cut_s) * 0.5, side[2], Vector3(1, 1, length)])
	return out


static func _depth(piece: String) -> float:
	return WALL_DEPTH.get(piece, WALL_DEPTH_DEFAULT)


## Piso de tábuas w × d no andar `floor`, com as bordas de fora recuadas (PLANKS_INSET).
static func _floor(w: int, d: int, floor: int) -> Array:
	var out: Array = []
	for i in w:
		for j in d:
			var x0 := PLANKS_INSET if i == 0 else 0.0
			var x1 := PLANKS_INSET if i == w - 1 else 0.0
			var z0 := PLANKS_INSET if j == 0 else 0.0
			var z1 := PLANKS_INSET if j == d - 1 else 0.0
			out.append(["planks", i + (x0 - x1) * 0.5, floor, j + (z0 - z1) * 0.5, 0, Vector3(1.0 - x0 - x1, 1, 1.0 - z0 - z1)])
	return out


## Telhado de duas águas inteiro numa peça só, esticada no comprimento (cumeeira de leste
## a oeste, de largura `w` peças). Peças lado a lado se sobrepunham (cada uma tem 1,1 de
## largura) e as águas piscavam; o kit usa uma paleta de cores (colormap), então esticar
## não deforma nada.
##
## A peça tem o triângulo do oitão nas duas pontas, recuado em x = ±GABLE_X (dentro da
## espessura da parede de uma peça). O esticão é escolhido para o oitão cair no meio da
## parede leste/oeste (face de fora em w/2, espessura 0,1): se ficasse por dentro, sobrava
## uma fresta entre o topo da parede e o oitão, e dava para ver o lado de dentro. O beiral
## das pontas fica um pouco maior que o do kit (0,18 em vez de 0,05).
const GABLE_X := 0.475


static func _roof(piece: String, w: int, floor: int, z: float, depth_scale: float, height_scale: float) -> Array:
	var sx := (w * 0.5 - WALL_DEPTH_DEFAULT * 0.5) / GABLE_X
	return [piece, (w - 1) * 0.5, floor, z, 0, Vector3(sx, height_scale, depth_scale)]


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
	# Uma cumeeira só, de leste a oeste, cobrindo as 3 colunas e as duas fileiras.
	p.append(_roof("roof-gable", 3, 1, 0.5, 2.0, 1.35))
	p.append(["chimney", 2, 1, 0, 0, Vector3(1, 1.4, 1)])
	return {"w": 3, "d": 2, "pieces": p}


## Casa grande: térreo de pedra 3 × 3, andar de cima de madeira 3 × 2 com sacada na
## frente, telhado alto e chaminé.
func _house_level_3() -> Dictionary:
	var p := _walls(3, 3, 0, "wall-window-stone", {"s:1": "wall-door", "n:1": "wall", "l:1": "wall", "o:1": "wall"})
	# Piso do andar de cima (também é o teto do térreo) e o andar de cima recuado.
	p.append_array(_floor(3, 3, 1))
	var upper := _walls(3, 2, 1, "wall-wood-window-shutters", {"n:1": "wall-wood", "l:0": "wall-wood", "o:0": "wall-wood", "s:1": "wall-wood-door"})
	p.append_array(upper)
	# Sacada na frente do andar de cima (fileira z = 2), com grade de cerquinha.
	for i in 3:
		p.append(["fence", i, 1, 2, 270, Vector3.ONE])
	# As laterais param na face de dentro da grade da frente (0,075), sem cruzar com ela.
	const FENCE_DEPTH := 0.075
	p.append(["fence", 0, 1, 2 - FENCE_DEPTH * 0.5, 180, Vector3(1, 1, 1.0 - FENCE_DEPTH)])
	p.append(["fence", 2, 1, 2 - FENCE_DEPTH * 0.5, 0, Vector3(1, 1, 1.0 - FENCE_DEPTH)])
	p.append(["lantern", 2.35, 1, 2.35, 0, Vector3(0.6, 0.45, 0.6)])
	p.append(_roof("roof-high-gable", 3, 2, 0.5, 2.0, 1.0))
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
	if "--no-focus" in OS.get_cmdline_user_args():
		# Pelo tools/sem_foco.sh: janela que não pega o foco de quem está usando o Mac.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_size(Vector2i(1280, 800))
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
		var views := [["frente", Vector3(4.5, 3.6, 7.5), Vector3(0, 1.4, 0)], ["tras", Vector3(-5.5, 4.5, -6.5), Vector3(0, 1.4, 0)]]
		# De perto, nos cantos (onde as paredes se encontram) e no telhado.
		var hw := float(houses[level]["w"]) * KIT_SCALE * 0.5
		var hd := float(houses[level]["d"]) * KIT_SCALE * 0.5
		views.append(["canto_frente", Vector3(hw + 1.6, 1.2, hd + 1.4), Vector3(hw, 1.0, hd)])
		views.append(["canto_tras", Vector3(-hw - 1.5, 1.6, -hd - 1.2), Vector3(-hw, 1.2, -hd)])
		views.append(["telhado", Vector3(hw * 0.4, 5.5, hd + 2.5), Vector3(0, 2.5, 0)])
		# Encontros do telhado com as paredes: oitões de perto (leste e oeste, um pouco de
		# cima) e de cima em diagonal pelos quatro lados (equivale às quatro rotações).
		var top := 1.5 * KIT_SCALE if level < 3 else 2.5 * KIT_SCALE
		views.append(["oitao_leste", Vector3(hw + 2.2, top + 1.2, 0.6), Vector3(hw, top - 0.3, 0)])
		views.append(["oitao_oeste", Vector3(-hw - 2.2, top + 1.2, -0.6), Vector3(-hw, top - 0.3, 0)])
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			views.append(["cima_%d" % k, Vector3(cos(a) * 4.5, top + 3.0, sin(a) * 4.5), Vector3(0, top - 0.5, 0)])
		for view in views:
			cam.look_at_from_position(view[1], view[2])
			for f in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/casa_%d_%s.png" % [dir, level, view[0]]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("foto: " + path)
		house.queue_free()
		await process_frame
	quit()
