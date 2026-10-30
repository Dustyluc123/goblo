class_name Npc
extends Node3D
## NPC parado no lugar (fase 3.5, ADR 0043): guia, lojista ou atendente do aeroporto. Usa um
## personagem do Mini Characters com variações para não parecer jogador: um chapeuzinho na
## cor do papel e, se houver, um acessório do pacote (óculos). Em cima da cabeça, o nome, o
## cargo e um balãozinho de fala indicando que dá para conversar (E).

const DIR := "res://assets/kenney/mini-characters/"

var role := ""
var npc_name := ""
var title := ""
var dialog := ""
var country := ""
var _ap: AnimationPlayer
static var _bubble_tex: ImageTexture
static var _scenes := {}


## Monta o NPC. `info` é o papel de npcs.json (title, character, accessory, tint, dialog).
static func create(r: String, info: Dictionary, n: String, c: String) -> Npc:
	var npc := Npc.new()
	npc.role = r
	npc.npc_name = n
	npc.title = str(info.get("title", ""))
	npc.dialog = str(info.get("dialog", ""))
	npc.country = c
	npc.name = "NPC_%s" % r
	npc._build(info)
	return npc


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path) and ResourceLoader.exists(path):
		_scenes[path] = load(path)
	return _scenes.get(path)


func _build(info: Dictionary) -> void:
	var sc := _scene(DIR + str(info.get("character", "character-male-a")) + ".glb")
	if sc == null:
		return
	var model := sc.instantiate() as Node3D
	var h := maxf(Player._model_height(model), 0.01)
	var k := 1.0 / h
	model.scale = Vector3.ONE * k
	model.rotation.y = PI  # os modelos olham para +Z
	add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_ap = aps[0]
		if _ap.has_animation("idle"):
			_ap.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			_ap.play("idle")
			_ap.seek(randf() * 1.5, true)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		var sk := sks[0] as Skeleton3D
		var head := sk.find_bone("head")
		if head >= 0:
			var att := BoneAttachment3D.new()
			att.bone_name = "head"
			sk.add_child(att)
			# Os acessórios do pacote vêm no espaço do personagem: desconta a posição da cabeça.
			var rest := sk.get_bone_global_rest(head)
			var acc := str(info.get("accessory", ""))
			if not acc.is_empty():
				var asc := _scene(DIR + acc + ".glb")
				if asc:
					var a := asc.instantiate() as Node3D
					a.transform = rest.affine_inverse()
					att.add_child(a)
			att.add_child(_hat(Color(str(info.get("tint", "#ffd27f"))), rest, h))
	var label := Label3D.new()
	label.text = "%s\n%s" % [npc_name, title]
	label.font_size = 34
	label.pixel_size = 0.0045
	label.outline_size = 10
	label.modulate = Color("fff6c8")
	label.outline_modulate = Color(0.3, 0.2, 0.1, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 1.45, 0)
	label.visibility_range_end = 30.0
	add_child(label)
	var bubble := Sprite3D.new()
	bubble.texture = bubble_texture()
	bubble.pixel_size = 0.006
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.position = Vector3(0, 1.85, 0)
	bubble.visibility_range_end = 30.0
	add_child(bubble)


## Chapeuzinho de aba (cor do papel) em cima da cabeça. Medidas em fração da altura `h` do
## modelo (no espaço dele, sem escala).
func _hat(tint: Color, rest: Transform3D, h: float) -> Node3D:
	var hat := Node3D.new()
	hat.transform = rest.affine_inverse() * Transform3D(Basis(), Vector3(0, h * 0.96, 0))
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.8
	var brim := CylinderMesh.new()
	brim.top_radius = 0.2 * h
	brim.bottom_radius = 0.2 * h
	brim.height = 0.025 * h
	brim.radial_segments = 10
	brim.material = m
	var crown := CylinderMesh.new()
	crown.top_radius = 0.11 * h
	crown.bottom_radius = 0.13 * h
	crown.height = 0.12 * h
	crown.radial_segments = 10
	crown.material = m
	for part: Array in [[brim, 0.0], [crown, 0.07 * h]]:
		var mi := MeshInstance3D.new()
		mi.mesh = BorderLines._baked(part[0], m)
		mi.position = Vector3(0, part[1], 0)
		hat.add_child(mi)
	return hat


## Vira o NPC para um ponto (quando o jogador vem conversar).
func face(point: Vector3) -> void:
	var up := global_position.normalized()
	var to := point - global_position
	to -= up * to.dot(up)
	if to.length() > 0.01:
		global_basis = Basis.looking_at(to.normalized(), up)


## Balãozinho de fala (desenhado em código).
static func bubble_texture() -> ImageTexture:
	if _bubble_tex:
		return _bubble_tex
	var w := 48
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	for y in w:
		for x in w:
			var cx := (x - 24.0) / 20.0
			var cy := (y - 20.0) / 15.0
			var col := Color(0, 0, 0, 0)
			if cx * cx + cy * cy < 1.0:
				col = Color("fffaf0")
				if cx * cx + cy * cy > 0.8:
					col = Color("b5566b")
			# Rabinho embaixo.
			if y >= 32 and y < 44 and x >= 14 and x < 14 + (44 - y):
				col = Color("fffaf0")
			# Três pontinhos.
			for dx in [-9, 0, 9]:
				if (x - 24 - dx) * (x - 24 - dx) + (y - 20) * (y - 20) < 7:
					col = Color("b5566b")
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	_bubble_tex = ImageTexture.create_from_image(img)
	return _bubble_tex
