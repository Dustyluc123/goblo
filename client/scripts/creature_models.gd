class_name CreatureModels
extends RefCounted
## Criaturas feitas aqui (fase 4.5, ADR 0058): os animais novos, as lendas do folclore e o
## golem das cavernas, no estilo dos pacotes (formas simples, facetadas, cor chapada).
##
## Cada criatura é um esqueleto (Skeleton3D) com uma malha só (uma chamada de desenho),
## cada vértice preso a um osso com peso 1. As animações são geradas por código com os
## mesmos nomes do pacote de animais (Idle, Idle_2, Walk, Gallop, Eating, Jump_toIdle), então
## os animais novos andam pelo mesmo `Animals` que os outros. O golem tem também Slam, Sleep
## e Wake.
##
## As formas ficam viradas para +Z, com o chão em y = 0; quem usa escala pela altura.

const ANIMS := ["Idle", "Idle_2", "Walk", "Gallop", "Eating", "Jump_toIdle"]
const LOOPED := ["Idle", "Idle_2", "Walk", "Gallop", "Eating", "Sleep", "Swim"]

static var _scenes := {}
static var _material: StandardMaterial3D
static var _prims := {}

## Todas as criaturas que este arquivo sabe montar.
const IDS := ["capybara", "macaw", "toucan", "penguin", "polar_bear", "camel", "kangaroo", "koala", "panda",
	"legend_mula", "legend_saci", "legend_bigfoot", "legend_jackalope", "legend_wolpertinger", "legend_alebrije",
	"legend_nessie", "legend_leprechaun", "legend_troll", "legend_firebird", "legend_tanuki", "cave_golem"]


static func has(id: String) -> bool:
	return IDS.has(id.trim_prefix("creature:"))


## A cena pronta (em cache). `id` com ou sem "creature:".
static func scene(id: String) -> PackedScene:
	id = id.trim_prefix("creature:")
	if _scenes.has(id):
		return _scenes[id]
	var root := build(id)
	var ps := PackedScene.new()
	for n in root.find_children("*", "", true, false):
		n.owner = root
	ps.pack(root)
	root.free()
	_scenes[id] = ps
	return ps


static func instance(id: String) -> Node3D:
	return scene(id).instantiate() as Node3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.95
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _material


# --- Montagem -------------------------------------------------------------------------------

## Monta a criatura (nó com Skeleton3D, MeshInstance3D e AnimationPlayer).
static func build(id: String) -> Node3D:
	_make_prims()
	var spec := _spec(id)
	var root := Node3D.new()
	root.name = id
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	var pivots := {}
	for b: Array in spec["bones"]:
		var idx := skel.add_bone(str(b[0]))
		var pivot: Vector3 = b[2]
		pivots[str(b[0])] = pivot
		var parent := str(b[1])
		if not parent.is_empty():
			skel.set_bone_parent(idx, skel.find_bone(parent))
			skel.set_bone_rest(idx, Transform3D(Basis(), pivot - (pivots[parent] as Vector3)))
		else:
			skel.set_bone_rest(idx, Transform3D(Basis(), pivot))
	skel.reset_bone_poses()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var glow := float(spec.get("glow", 0.0))
	for p: Array in spec["parts"]:
		var bone := skel.find_bone(str(p[0]))
		var arrays: Array = _prims[str(p[1])]
		var size: Vector3 = p[2]
		var center: Vector3 = p[3]
		var col: Color = p[4]
		var rot: Vector3 = p[5] if p.size() > 5 else Vector3.ZERO
		var basis := Basis.from_euler(rot * (PI / 180.0)) * Basis.from_scale(size)
		var xf := Transform3D(basis, center)
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var lin := col.srgb_to_linear()
		for t in range(0, idx.size(), 3):
			var a := xf * pv[idx[t]]
			var b2 := xf * pv[idx[t + 1]]
			var d := xf * pv[idx[t + 2]]
			var fn := (b2 - a).cross(d - a)
			if fn.length_squared() < 1e-14:
				continue
			fn = fn.normalized()
			# Mesma ordem do primitivo (frente em sentido horário); a normal para fora é −fn.
			for q in [a, b2, d]:
				v.append(q)
				n.append(-fn)
				c.append(lin)
				bones.append_array([bone, 0, 0, 0])
				weights.append_array([1.0, 0.0, 0.0, 0.0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	if glow > 0.0:
		var m := material().duplicate() as StandardMaterial3D
		m.emission_enabled = true
		m.emission_energy_multiplier = glow
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission = Color.WHITE
		mi.material_override = m
	else:
		mi.material_override = material()
	skel.add_child(mi)
	mi.skin = skel.create_skin_from_rest_transforms()
	mi.skeleton = NodePath("..")
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	var anims := _animations(spec, skel)
	for k: String in anims:
		lib.add_animation(k, anims[k])
	ap.add_animation_library("", lib)
	return root


static func _make_prims() -> void:
	if not _prims.is_empty():
		return
	var box := BoxMesh.new()
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 8
	ball.rings = 5
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 1
	var hex := CylinderMesh.new()
	hex.top_radius = 0.5
	hex.bottom_radius = 0.5
	hex.height = 1.0
	hex.radial_segments = 6
	hex.rings = 1
	var gem := CylinderMesh.new()
	gem.top_radius = 0.0
	gem.bottom_radius = 0.5
	gem.height = 1.0
	gem.radial_segments = 5
	gem.rings = 1
	for pair: Array in [["box", box], ["ball", ball], ["cyl", cyl], ["cone", cone], ["hex", hex], ["gem", gem]]:
		_prims[pair[0]] = (pair[1] as PrimitiveMesh).get_mesh_arrays()


# --- Animações ------------------------------------------------------------------------------

## Gera as animações pelo tipo de andar (gait) e pelos ossos que a criatura tem.
static func _animations(spec: Dictionary, skel: Skeleton3D) -> Dictionary:
	var rig: Dictionary = spec.get("rig", {})
	var gait := str(spec.get("gait", "quad"))
	var out := {}
	var defs := {
		"Idle": [3.0, "idle"], "Idle_2": [3.2, "look"], "Walk": [1.0, "walk"], "Gallop": [0.55, "run"],
		"Eating": [2.0, "eat"], "Jump_toIdle": [0.8, "jump"],
	}
	if gait == "biped" or gait == "big":
		defs["Walk"] = [1.1, "walk"]
		defs["Gallop"] = [0.7, "run"]
	if gait == "hop":
		defs["Walk"] = [0.7, "walk"]
		defs["Gallop"] = [0.5, "run"]
	if gait == "bird":
		defs["Walk"] = [0.5, "walk"]
		defs["Gallop"] = [0.32, "run"]
	if bool(spec.get("boss", false)):
		defs["Slam"] = [1.4, "slam"]
		defs["Sleep"] = [4.0, "sleep"]
		defs["Wake"] = [1.2, "wake"]
	for name: String in defs:
		var d: Array = defs[name]
		out[name] = _make_anim(skel, rig, gait, str(d[1]), float(d[0]), LOOPED.has(name))
	return out


static func _make_anim(skel: Skeleton3D, rig: Dictionary, gait: String, kind: String, period: float, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = period
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var steps := 16
	var rot_tracks := {}
	var pos_tracks := {}
	for b in skel.get_bone_count():
		var bn := skel.get_bone_name(b)
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("Skeleton3D:" + bn))
		rot_tracks[bn] = tr
	for bn: String in [str(rig.get("body", ""))]:
		if bn.is_empty() or skel.find_bone(bn) < 0:
			continue
		var tr := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(tr, NodePath("Skeleton3D:" + bn))
		pos_tracks[bn] = tr
	for k in steps + 1:
		var t := period * k / steps
		var u := float(k) / steps  # 0..1 do ciclo
		var pose := _pose(rig, gait, kind, u)
		for bn: String in rot_tracks:
			var e: Vector3 = (pose["rot"] as Dictionary).get(bn, Vector3.ZERO)
			anim.rotation_track_insert_key(rot_tracks[bn], t, Quaternion.from_euler(e))
		for bn: String in pos_tracks:
			var rest := skel.get_bone_rest(skel.find_bone(bn)).origin
			anim.position_track_insert_key(pos_tracks[bn], t, rest + (pose["pos"] as Dictionary).get(bn, Vector3.ZERO))
	return anim


## Pose num instante do ciclo (u de 0 a 1): rotações (euler, radianos) e deslocamentos.
static func _pose(rig: Dictionary, gait: String, kind: String, u: float) -> Dictionary:
	var rot := {}
	var pos := {}
	var w := TAU * u
	var body := str(rig.get("body", ""))
	var head := str(rig.get("head", ""))
	var tail := str(rig.get("tail", ""))
	var legs: Array = rig.get("legs", [])
	var arms: Array = rig.get("arms", [])
	var wings: Array = rig.get("wings", [])
	var spin := str(rig.get("spin", ""))
	var fire := str(rig.get("fire", ""))
	var add := func(bn: String, e: Vector3) -> void:
		if bn.is_empty():
			return
		rot[bn] = (rot.get(bn, Vector3.ZERO) as Vector3) + e
	var move := func(bn: String, d: Vector3) -> void:
		if bn.is_empty():
			return
		pos[bn] = (pos.get(bn, Vector3.ZERO) as Vector3) + d
	var amp := 0.0
	var fast := 1.0
	match kind:
		"walk":
			amp = 0.45
		"run":
			amp = 0.85
			fast = 1.0
	# Pernas e braços.
	for l: Array in legs:
		var ph := float(l[1])
		if kind == "run" and gait == "quad":
			ph = 0.0 if bool(l[3]) else 0.5
			ph += 0.08 if int(l[2]) > 0 else 0.0
		var a := amp * sin(w * fast + TAU * ph)
		if gait == "hop":
			a = -absf(sin(w)) * (0.25 if kind == "walk" else 0.4) if kind in ["walk", "run"] else 0.0
		if kind == "jump":
			a = -0.5 * sin(PI * u)
		add.call(str(l[0]), Vector3(a, 0, 0))
	for l: Array in arms:
		var a := -amp * 0.8 * sin(w + TAU * float(l[1]))
		if kind == "idle":
			a = 0.04 * sin(w)
		add.call(str(l[0]), Vector3(a, 0, 0))
	# Corpo: balanço do passo, respiração, pulos.
	match kind:
		"idle", "look":
			move.call(body, Vector3(0, 0.008 * sin(w), 0))
		"walk":
			if gait == "hop":
				move.call(body, Vector3(0, 0.16 * absf(sin(w)), 0))
				add.call(body, Vector3(-0.1 * absf(sin(w)), 0, 0))
			elif gait == "bird" or gait == "biped" or gait == "big":
				move.call(body, Vector3(0, 0.02 * absf(sin(w)), 0))
				add.call(body, Vector3(0, 0, 0.08 * sin(w)))
			else:
				move.call(body, Vector3(0, 0.015 * absf(sin(w)), 0))
		"run":
			if gait == "hop":
				move.call(body, Vector3(0, 0.3 * absf(sin(w)), 0))
				add.call(body, Vector3(-0.15 * absf(sin(w)), 0, 0))
			elif gait == "bird":
				move.call(body, Vector3(0, 0.12 + 0.05 * sin(2.0 * w), 0))
			else:
				move.call(body, Vector3(0, 0.04 * absf(sin(w)), 0))
				add.call(body, Vector3(0.1 * sin(w), 0, 0))
		"jump":
			move.call(body, Vector3(0, 0.2 * sin(PI * u), 0))
		"eat":
			move.call(body, Vector3(0, -0.01, 0))
	if gait == "float":
		move.call(body, Vector3(0, 0.05 * sin(w * 2.0), 0))
	# Cabeça.
	match kind:
		"idle":
			add.call(head, Vector3(0.05 * sin(w), 0.08 * sin(w * 0.5), 0))
		"look":
			add.call(head, Vector3(0, 0.55 * sin(w), 0.08 * sin(w)))
		"walk", "run":
			add.call(head, Vector3(0.06 * sin(2.0 * w), 0, 0))
		"eat":
			add.call(head, Vector3(0.75 + 0.1 * sin(w * 4.0), 0, 0))
	# Rabo, asas, redemoinho, fogo.
	add.call(tail, Vector3(0, 0.3 * sin(w * (3.0 if kind == "run" else 2.0)), 0))
	for wg: Array in wings:
		var side := float(wg[1])
		var f := 0.08 * sin(w)
		if kind == "run":
			f = 0.9 * sin(w * 2.0)
		elif kind == "walk":
			f = 0.2 * sin(w * 2.0)
		elif gait == "float":
			f = 0.6 * sin(w * 3.0)
		add.call(str(wg[0]), Vector3(0, 0, side * f))
	if not spin.is_empty():
		add.call(spin, Vector3(0, w * 2.0, 0))
	if not fire.is_empty():
		add.call(fire, Vector3(0.12 * sin(w * 6.0), 0, 0.1 * sin(w * 5.0)))
	# Golem.
	match kind:
		"slam":
			var up := sin(PI * clampf(u / 0.6, 0.0, 1.0))
			var down := clampf((u - 0.6) / 0.15, 0.0, 1.0)
			var arm_a := -2.3 * up * (1.0 - down) + 0.3 * down
			for l: Array in arms:
				add.call(str(l[0]), Vector3(arm_a, 0, 0))
			add.call(body, Vector3(-0.2 * up + 0.25 * down * (1.0 - clampf((u - 0.75) / 0.25, 0.0, 1.0)), 0, 0))
			move.call(body, Vector3(0, 0.08 * up - 0.12 * down * (1.0 - clampf((u - 0.75) / 0.25, 0.0, 1.0)), 0))
		"sleep":
			add.call(body, Vector3(0.35, 0, 0))
			move.call(body, Vector3(0, -0.35 + 0.03 * sin(w), 0))
			add.call(head, Vector3(0.45, 0, 0.1))
			for l: Array in arms:
				add.call(str(l[0]), Vector3(-0.5, 0, 0))
			for l: Array in legs:
				add.call(str(l[0]), Vector3(-1.3, 0, 0))
		"wake":
			var s := sin(PI * u)
			add.call(body, Vector3(0.35 * (1.0 - u), 0, 0))
			move.call(body, Vector3(0, -0.35 * (1.0 - u), 0))
			for l: Array in arms:
				add.call(str(l[0]), Vector3(-2.6 * s, 0, 0))
	return {"rot": rot, "pos": pos}


# --- As criaturas ---------------------------------------------------------------------------

static func _new() -> Dictionary:
	return {"bones": [], "parts": [], "rig": {}, "gait": "quad"}


static func _bone(s: Dictionary, name: String, parent: String, pivot: Vector3) -> void:
	(s["bones"] as Array).append([name, parent, pivot])


static func _part(s: Dictionary, bone: String, shape: String, size: Vector3, center: Vector3, col: Variant, rot := Vector3.ZERO) -> void:
	(s["parts"] as Array).append([bone, shape, size, center, Color(col) if col is String else col, rot])


## Par de olhos fofos (preto com brilho branco), na frente da cabeça.
static func _eyes(s: Dictionary, bone: String, x: float, y: float, z: float, size := 0.05) -> void:
	for side in [-1.0, 1.0]:
		_part(s, bone, "box", Vector3(size, size * 1.2, size * 0.5), Vector3(side * x, y, z), "#1d1b22")
		_part(s, bone, "box", Vector3(size * 0.35, size * 0.35, size * 0.2), Vector3(side * x + size * 0.18, y + size * 0.25, z + size * 0.22), "#ffffff")


## Quadrúpede: ossos root, body, head e as quatro pernas (pivô no alto da perna).
static func _quad(s: Dictionary, body_y: float, head_at: Vector3, legs: Array) -> void:
	_bone(s, "root", "", Vector3.ZERO)
	_bone(s, "body", "root", Vector3(0, body_y, 0))
	_bone(s, "head", "body", head_at)
	var rig_legs: Array = []
	for l: Array in legs:
		_bone(s, str(l[0]), "body", l[1])
		var p: Vector3 = l[1]
		rig_legs.append([l[0], 0.0 if (p.x > 0) == (p.z > 0) else 0.5, 1 if p.x > 0 else -1, p.z > 0])
	s["rig"] = {"body": "body", "head": "head", "legs": rig_legs}


## Perna simples (caixa do pivô até o chão) com pé.
static func _leg(s: Dictionary, bone: String, pivot: Vector3, w: float, col: Variant, foot: Variant = null, depth := -1.0) -> void:
	var d := w if depth < 0 else depth
	_part(s, bone, "box", Vector3(w, pivot.y, d), Vector3(pivot.x, pivot.y * 0.5, pivot.z), col)
	if foot != null:
		_part(s, bone, "box", Vector3(w * 1.08, minf(0.06, pivot.y * 0.2), d * 1.15), Vector3(pivot.x, minf(0.03, pivot.y * 0.1), pivot.z + d * 0.06), foot)


static func _spec(id: String) -> Dictionary:
	var s := _new()
	match id:
		"capybara":
			var fur := "#a0714a"
			var dark := "#7d5535"
			var legs := [["leg_fl", Vector3(0.14, 0.24, 0.24)], ["leg_fr", Vector3(-0.14, 0.24, 0.24)],
				["leg_bl", Vector3(0.15, 0.24, -0.24)], ["leg_br", Vector3(-0.15, 0.24, -0.24)]]
			_quad(s, 0.42, Vector3(0, 0.56, 0.36), legs)
			_part(s, "body", "box", Vector3(0.46, 0.36, 0.78), Vector3(0, 0.44, -0.02), fur)
			_part(s, "body", "box", Vector3(0.42, 0.1, 0.7), Vector3(0, 0.64, -0.04), "#8f6340")
			_part(s, "body", "box", Vector3(0.4, 0.3, 0.12), Vector3(0, 0.42, -0.42), dark)
			_part(s, "head", "box", Vector3(0.32, 0.3, 0.32), Vector3(0, 0.6, 0.46), fur)
			_part(s, "head", "box", Vector3(0.3, 0.24, 0.2), Vector3(0, 0.55, 0.66), dark)
			_part(s, "head", "box", Vector3(0.16, 0.05, 0.03), Vector3(0, 0.6, 0.765), "#3a2a20")
			_part(s, "head", "box", Vector3(0.07, 0.07, 0.05), Vector3(0.13, 0.78, 0.4), dark)
			_part(s, "head", "box", Vector3(0.07, 0.07, 0.05), Vector3(-0.13, 0.78, 0.4), dark)
			_eyes(s, "head", 0.1, 0.68, 0.62, 0.045)
			for l: Array in legs:
				_leg(s, str(l[0]), l[1], 0.11, dark, "#5e3f28")
		"polar_bear":
			var fur := "#f2eee2"
			var shade := "#ddd6c4"
			var legs := [["leg_fl", Vector3(0.2, 0.46, 0.34)], ["leg_fr", Vector3(-0.2, 0.46, 0.34)],
				["leg_bl", Vector3(0.21, 0.46, -0.34)], ["leg_br", Vector3(-0.21, 0.46, -0.34)]]
			_quad(s, 0.7, Vector3(0, 0.82, 0.56), legs)
			_part(s, "body", "box", Vector3(0.62, 0.52, 1.02), Vector3(0, 0.72, 0), fur)
			_part(s, "body", "box", Vector3(0.56, 0.18, 0.5), Vector3(0, 1.0, 0.18), fur)
			_part(s, "body", "box", Vector3(0.56, 0.42, 0.14), Vector3(0, 0.72, -0.53), shade)
			_part(s, "head", "box", Vector3(0.38, 0.34, 0.38), Vector3(0, 0.86, 0.72), fur)
			_part(s, "head", "box", Vector3(0.22, 0.18, 0.2), Vector3(0, 0.78, 0.96), shade)
			_part(s, "head", "box", Vector3(0.09, 0.06, 0.04), Vector3(0, 0.84, 1.06), "#22201f")
			for side in [-1.0, 1.0]:
				_part(s, "head", "ball", Vector3(0.1, 0.1, 0.06), Vector3(side * 0.15, 1.05, 0.66), shade)
			_eyes(s, "head", 0.1, 0.94, 0.9, 0.045)
			for l: Array in legs:
				_leg(s, str(l[0]), l[1], 0.2, fur, shade, 0.22)
			s["rig"]["tail"] = ""
		"camel":
			var fur := "#c99a5b"
			var dark := "#a87b45"
			var legs := [["leg_fl", Vector3(0.16, 1.0, 0.36)], ["leg_fr", Vector3(-0.16, 1.0, 0.36)],
				["leg_bl", Vector3(0.16, 1.0, -0.36)], ["leg_br", Vector3(-0.16, 1.0, -0.36)]]
			_quad(s, 1.2, Vector3(0, 1.28, 0.44), legs)
			_part(s, "body", "ball", Vector3(0.56, 0.56, 1.12), Vector3(0, 1.18, 0), fur)
			_part(s, "body", "ball", Vector3(0.46, 0.5, 0.56), Vector3(0, 1.5, -0.04), dark)
			_part(s, "head", "box", Vector3(0.18, 0.62, 0.2), Vector3(0, 1.52, 0.62), fur, Vector3(30, 0, 0))
			_part(s, "head", "box", Vector3(0.22, 0.2, 0.38), Vector3(0, 1.86, 0.86), fur)
			_part(s, "head", "box", Vector3(0.18, 0.13, 0.1), Vector3(0, 1.8, 1.07), dark)
			for side in [-1.0, 1.0]:
				_part(s, "head", "box", Vector3(0.05, 0.08, 0.04), Vector3(side * 0.09, 2.0, 0.76), dark)
			_eyes(s, "head", 0.11, 1.92, 0.94, 0.04)
			for l: Array in legs:
				_leg(s, str(l[0]), l[1], 0.14, fur, "#8c6a3e")
			_bone(s, "tail", "body", Vector3(0, 1.32, -0.5))
			_part(s, "tail", "box", Vector3(0.05, 0.36, 0.05), Vector3(0, 1.14, -0.54), dark)
			s["rig"]["tail"] = "tail"
		"koala":
			var fur := "#9da3a8"
			var light := "#d8dadb"
			var legs := [["leg_fl", Vector3(0.13, 0.18, 0.14)], ["leg_fr", Vector3(-0.13, 0.18, 0.14)],
				["leg_bl", Vector3(0.13, 0.18, -0.14)], ["leg_br", Vector3(-0.13, 0.18, -0.14)]]
			_quad(s, 0.3, Vector3(0, 0.4, 0.2), legs)
			_part(s, "body", "ball", Vector3(0.42, 0.38, 0.52), Vector3(0, 0.32, 0), fur)
			_part(s, "body", "ball", Vector3(0.3, 0.26, 0.2), Vector3(0, 0.3, 0.16), light)
			_part(s, "head", "ball", Vector3(0.4, 0.34, 0.32), Vector3(0, 0.52, 0.3), fur)
			for side in [-1.0, 1.0]:
				_part(s, "head", "ball", Vector3(0.2, 0.2, 0.08), Vector3(side * 0.2, 0.66, 0.26), fur)
				_part(s, "head", "ball", Vector3(0.12, 0.12, 0.04), Vector3(side * 0.2, 0.66, 0.3), light)
			_part(s, "head", "box", Vector3(0.11, 0.13, 0.07), Vector3(0, 0.5, 0.47), "#2c2a2e")
			_eyes(s, "head", 0.1, 0.58, 0.44, 0.035)
			for l: Array in legs:
				_leg(s, str(l[0]), l[1], 0.1, fur, "#5d6166")
		"panda":
			var white := "#f3f1ea"
			var black := "#26252a"
			var legs := [["leg_fl", Vector3(0.18, 0.34, 0.26)], ["leg_fr", Vector3(-0.18, 0.34, 0.26)],
				["leg_bl", Vector3(0.18, 0.34, -0.26)], ["leg_br", Vector3(-0.18, 0.34, -0.26)]]
			_quad(s, 0.55, Vector3(0, 0.66, 0.42), legs)
			_part(s, "body", "ball", Vector3(0.56, 0.52, 0.86), Vector3(0, 0.56, 0), white)
			_part(s, "body", "box", Vector3(0.58, 0.34, 0.26), Vector3(0, 0.6, 0.2), black)
			_part(s, "head", "ball", Vector3(0.44, 0.4, 0.4), Vector3(0, 0.74, 0.56), white)
			for side in [-1.0, 1.0]:
				_part(s, "head", "ball", Vector3(0.13, 0.13, 0.08), Vector3(side * 0.18, 0.93, 0.52), black)
				_part(s, "head", "ball", Vector3(0.1, 0.13, 0.05), Vector3(side * 0.1, 0.77, 0.74), black, Vector3(0, 0, side * 25))
			_part(s, "head", "box", Vector3(0.18, 0.12, 0.1), Vector3(0, 0.67, 0.75), white)
			_part(s, "head", "box", Vector3(0.08, 0.05, 0.04), Vector3(0, 0.71, 0.8), black)
			for side in [-1.0, 1.0]:
				_part(s, "head", "box", Vector3(0.03, 0.035, 0.02), Vector3(side * 0.1, 0.78, 0.77), "#ffffff")
			for l: Array in legs:
				_leg(s, str(l[0]), l[1], 0.15, black, black)
		"macaw", "toucan", "legend_firebird":
			s = _bird(id)
		"penguin":
			s["gait"] = "biped"
			_bone(s, "root", "", Vector3.ZERO)
			_bone(s, "body", "root", Vector3(0, 0.1, 0))
			_bone(s, "head", "body", Vector3(0, 0.56, 0))
			_bone(s, "arm_l", "body", Vector3(0.17, 0.48, 0))
			_bone(s, "arm_r", "body", Vector3(-0.17, 0.48, 0))
			_bone(s, "leg_l", "root", Vector3(0.08, 0.1, 0))
			_bone(s, "leg_r", "root", Vector3(-0.08, 0.1, 0))
			_part(s, "body", "ball", Vector3(0.36, 0.56, 0.32), Vector3(0, 0.34, 0), "#262a33")
			_part(s, "body", "ball", Vector3(0.28, 0.46, 0.14), Vector3(0, 0.3, 0.11), "#f4f3ee")
			_part(s, "head", "ball", Vector3(0.28, 0.26, 0.26), Vector3(0, 0.66, 0.01), "#262a33")
			_part(s, "head", "ball", Vector3(0.2, 0.14, 0.06), Vector3(0, 0.64, 0.12), "#f4f3ee")
			_part(s, "head", "box", Vector3(0.07, 0.05, 0.12), Vector3(0, 0.63, 0.17), "#f39a2b")
			_eyes(s, "head", 0.06, 0.69, 0.13, 0.035)
			for side in [-1.0, 1.0]:
				var arm := "arm_l" if side > 0 else "arm_r"
				_part(s, arm, "box", Vector3(0.04, 0.28, 0.12), Vector3(side * 0.19, 0.36, 0), "#262a33", Vector3(0, 0, side * 12))
				var leg := "leg_l" if side > 0 else "leg_r"
				_part(s, leg, "box", Vector3(0.1, 0.03, 0.15), Vector3(side * 0.08, 0.015, 0.05), "#f39a2b")
				_part(s, leg, "box", Vector3(0.06, 0.1, 0.06), Vector3(side * 0.08, 0.06, 0), "#f39a2b")
			s["rig"] = {"body": "body", "head": "head", "legs": [["leg_l", 0.0, 1, true], ["leg_r", 0.5, -1, true]],
				"arms": [["arm_l", 0.5], ["arm_r", 0.0]]}
		"kangaroo", "legend_jackalope", "legend_wolpertinger":
			s = _hopper(id)
		"legend_mula":
			var fur := "#8a5a3c"
			var dark := "#6a422b"
			var legs := [["leg_fl", Vector3(0.14, 0.55, 0.3)], ["leg_fr", Vector3(-0.14, 0.55, 0.3)],
				["leg_bl", Vector3(0.14, 0.55, -0.3)], ["leg_br", Vector3(-0.14, 0.55, -0.3)]]
			_quad(s, 0.75, Vector3(0, 0.95, 0.42), legs)
			_part(s, "body", "box", Vector3(0.38, 0.4, 0.86), Vector3(0, 0.78, 0), fur)
			_part(s, "body", "box", Vector3(0.4, 0.06, 0.4), Vector3(0, 1.0, 0.0), "#c0392b")
			_part(s, "head", "box", Vector3(0.2, 0.36, 0.22), Vector3(0, 1.06, 0.5), fur, Vector3(-20, 0, 0))
			_part(s, "head", "box", Vector3(0.06, 0.32, 0.16), Vector3(0, 1.1, 0.42), "#3b2a20", Vector3(-20, 0, 0))
			_bone(s, "fire", "head", Vector3(0, 1.24, 0.56))
			_part(s, "fire", "cone", Vector3(0.3, 0.42, 0.3), Vector3(0, 1.43, 0.56), "#4aa3ff")
			_part(s, "fire", "cone", Vector3(0.2, 0.32, 0.2), Vector3(0.04, 1.42, 0.6), "#9fd2ff")
			_part(s, "fire", "cone", Vector3(0.1, 0.22, 0.1), Vector3(-0.05, 1.5, 0.52), "#e6f4ff")
			for l: Array in legs:
				_leg(s, str(l[0]), l[1], 0.1, fur, "#2e231c")
			_bone(s, "tail", "body", Vector3(0, 0.9, -0.43))
			_part(s, "tail", "box", Vector3(0.07, 0.4, 0.07), Vector3(0, 0.72, -0.48), "#3b2a20", Vector3(-15, 0, 0))
			s["rig"]["tail"] = "tail"
			s["rig"]["fire"] = "fire"
			s["glow"] = 0.0
		"legend_saci":
			s["gait"] = "float"
			_bone(s, "root", "", Vector3.ZERO)
			_bone(s, "body", "root", Vector3(0, 0.0, 0))
			_bone(s, "swirl", "body", Vector3(0, 0, 0))
			_bone(s, "head", "body", Vector3(0, 0.8, 0))
			# Redemoinho de vento com poeira: anéis claros, mais largos em cima.
			var sand := ["#efe7d6", "#e2d5bb", "#f7f2e8", "#d8c9ab"]
			for k in 7:
				var r := 0.1 + k * 0.065
				_part(s, "swirl", "cyl", Vector3(r * 2.0, 0.05, r * 2.0), Vector3(0.04 * sin(k * 1.7), 0.06 + k * 0.1, 0.04 * cos(k * 1.3)), sand[k % 4], Vector3(8 * sin(k * 2.1), 0, 8 * cos(k * 1.4)))
				_part(s, "swirl", "box", Vector3(0.05, 0.03, 0.12), Vector3(r, 0.08 + k * 0.1, 0), "#b9a27c", Vector3(0, k * 40, 0))
			_part(s, "head", "ball", Vector3(0.34, 0.3, 0.32), Vector3(0, 0.86, 0), "#6b4a34")
			_eyes(s, "head", 0.07, 0.88, 0.15, 0.05)
			_part(s, "head", "box", Vector3(0.08, 0.03, 0.02), Vector3(0, 0.79, 0.16), "#3a241a")
			_part(s, "head", "cone", Vector3(0.36, 0.34, 0.36), Vector3(0, 1.12, -0.03), "#d93b3b", Vector3(-16, 0, 0))
			_part(s, "head", "ball", Vector3(0.08, 0.08, 0.08), Vector3(0, 1.28, -0.1), "#f4f1e4")
			s["rig"] = {"body": "body", "head": "head", "spin": "swirl"}
		"legend_bigfoot", "legend_troll", "legend_leprechaun":
			s = _biped(id)
		"legend_alebrije":
			var cols := ["#ff6fa8", "#3fc6c0", "#ffd23f", "#8a5cf6", "#ff8a3d"]
			var legs := [["leg_fl", Vector3(0.14, 0.3, 0.26)], ["leg_fr", Vector3(-0.14, 0.3, 0.26)],
				["leg_bl", Vector3(0.14, 0.3, -0.26)], ["leg_br", Vector3(-0.14, 0.3, -0.26)]]
			_quad(s, 0.5, Vector3(0, 0.62, 0.38), legs)
			_part(s, "body", "box", Vector3(0.36, 0.34, 0.74), Vector3(0, 0.5, 0), cols[0])
			for k in 5:
				_part(s, "body", "box", Vector3(0.38, 0.06, 0.08), Vector3(0, 0.5 + 0.12 * ((k % 2) * 2 - 1), -0.28 + k * 0.14), cols[(k + 1) % 5])
			for k in 4:
				_part(s, "body", "gem", Vector3(0.1, 0.16, 0.1), Vector3(0, 0.72, -0.24 + k * 0.16), cols[(k + 2) % 5])
			_part(s, "head", "box", Vector3(0.3, 0.26, 0.3), Vector3(0, 0.68, 0.48), cols[1])
			_part(s, "head", "box", Vector3(0.22, 0.14, 0.16), Vector3(0, 0.62, 0.66), cols[2])
			for side in [-1.0, 1.0]:
				_part(s, "head", "cone", Vector3(0.08, 0.2, 0.08), Vector3(side * 0.1, 0.88, 0.42), cols[3], Vector3(-20, 0, side * -20))
				_part(s, "head", "ball", Vector3(0.09, 0.09, 0.04), Vector3(side * 0.09, 0.72, 0.63), "#ffffff")
			_eyes(s, "head", 0.09, 0.72, 0.655, 0.04)
			_bone(s, "wing_l", "body", Vector3(0.18, 0.64, 0.05))
			_bone(s, "wing_r", "body", Vector3(-0.18, 0.64, 0.05))
			_part(s, "wing_l", "box", Vector3(0.36, 0.03, 0.2), Vector3(0.36, 0.7, 0.05), cols[4], Vector3(0, 0, 20))
			_part(s, "wing_r", "box", Vector3(0.36, 0.03, 0.2), Vector3(-0.36, 0.7, 0.05), cols[3], Vector3(0, 0, -20))
			for l: Array in legs:
				_leg(s, str(l[0]), l[1], 0.09, cols[(int(absf((l[1] as Vector3).z) * 10) + 3) % 5], "#2b2033")
			_bone(s, "tail", "body", Vector3(0, 0.55, -0.37))
			for k in 4:
				_part(s, "tail", "box", Vector3(0.07, 0.07, 0.14), Vector3(0, 0.6 + 0.08 * k, -0.44 - 0.06 * k), cols[k % 5], Vector3(-25 * k, 0, 0))
			s["rig"]["tail"] = "tail"
			s["rig"]["wings"] = [["wing_l", 1.0], ["wing_r", -1.0]]
		"legend_tanuki":
			var fur := "#8a6a4a"
			var dark := "#3b2f28"
			var legs := [["leg_fl", Vector3(0.12, 0.2, 0.18)], ["leg_fr", Vector3(-0.12, 0.2, 0.18)],
				["leg_bl", Vector3(0.12, 0.2, -0.18)], ["leg_br", Vector3(-0.12, 0.2, -0.18)]]
			_quad(s, 0.36, Vector3(0, 0.44, 0.26), legs)
			_part(s, "body", "ball", Vector3(0.4, 0.38, 0.6), Vector3(0, 0.38, 0), fur)
			_part(s, "body", "ball", Vector3(0.28, 0.24, 0.2), Vector3(0, 0.33, 0.18), "#c9a988")
			_part(s, "head", "ball", Vector3(0.34, 0.3, 0.3), Vector3(0, 0.54, 0.34), fur)
			_part(s, "head", "box", Vector3(0.3, 0.1, 0.06), Vector3(0, 0.56, 0.47), dark)
			_part(s, "head", "box", Vector3(0.12, 0.1, 0.14), Vector3(0, 0.5, 0.52), "#d8c4a8")
			_part(s, "head", "box", Vector3(0.05, 0.04, 0.03), Vector3(0, 0.53, 0.6), dark)
			for side in [-1.0, 1.0]:
				_part(s, "head", "cone", Vector3(0.09, 0.1, 0.06), Vector3(side * 0.1, 0.72, 0.3), dark)
				_part(s, "head", "box", Vector3(0.03, 0.03, 0.02), Vector3(side * 0.07, 0.575, 0.505), "#ffffff")
			_part(s, "head", "box", Vector3(0.2, 0.02, 0.14), Vector3(0, 0.71, 0.33), "#5fae4a", Vector3(10, 30, 0))
			_part(s, "head", "box", Vector3(0.02, 0.06, 0.02), Vector3(0, 0.74, 0.3), "#3f7a32")
			for l: Array in legs:
				_leg(s, str(l[0]), l[1], 0.09, dark, dark)
			_bone(s, "tail", "body", Vector3(0, 0.4, -0.3))
			_part(s, "tail", "ball", Vector3(0.16, 0.16, 0.34), Vector3(0, 0.36, -0.44), fur, Vector3(25, 0, 0))
			_part(s, "tail", "ball", Vector3(0.12, 0.12, 0.08), Vector3(0, 0.3, -0.58), dark)
			s["rig"]["tail"] = "tail"
		"legend_nessie":
			s["gait"] = "float"
			var green := "#4f7d6a"
			var belly := "#a8c9a0"
			_bone(s, "root", "", Vector3.ZERO)
			_bone(s, "body", "root", Vector3(0, 0, 0))
			_bone(s, "neck", "body", Vector3(0, 0.0, 0.0))
			_bone(s, "head", "neck", Vector3(0, 1.3, 0.35))
			_part(s, "body", "ball", Vector3(0.6, 0.36, 0.9), Vector3(0, 0.02, -0.5), green)
			_part(s, "body", "ball", Vector3(0.4, 0.28, 0.5), Vector3(0, 0.02, -1.3), green)
			for k in 6:
				var y := 0.1 + k * 0.2
				_part(s, "neck", "cyl", Vector3(0.26 - k * 0.012, 0.24, 0.26 - k * 0.012), Vector3(0, y, k * 0.055), green, Vector3(12, 0, 0))
				_part(s, "neck", "box", Vector3(0.12, 0.18, 0.06), Vector3(0, y, k * 0.055 + 0.11), belly, Vector3(12, 0, 0))
			_part(s, "head", "box", Vector3(0.26, 0.2, 0.36), Vector3(0, 1.38, 0.46), green)
			_part(s, "head", "box", Vector3(0.2, 0.1, 0.14), Vector3(0, 1.31, 0.64), belly)
			for side in [-1.0, 1.0]:
				_part(s, "head", "cone", Vector3(0.05, 0.1, 0.05), Vector3(side * 0.08, 1.52, 0.38), "#c9e0b6")
			_eyes(s, "head", 0.1, 1.43, 0.6, 0.045)
			s["rig"] = {"body": "body", "head": "head", "tail": "neck"}
		"cave_golem":
			s = _golem()
		_:
			_bone(s, "root", "", Vector3.ZERO)
			_part(s, "root", "box", Vector3(0.4, 0.4, 0.4), Vector3(0, 0.2, 0), "#c8b8a0")
	return s


## Aves: arara, tucano e pássaro de fogo.
static func _bird(id: String) -> Dictionary:
	var s := _new()
	s["gait"] = "float" if id == "legend_firebird" else "bird"
	var body := "#d7262e"
	var head := body
	var wing := "#2d6fd1"
	var wing2 := "#f5c518"
	var tail := body
	var belly := body
	match id:
		"toucan":
			body = "#1f1f24"
			head = body
			wing = "#2a2a30"
			wing2 = "#2a2a30"
			tail = "#1f1f24"
			belly = "#f6e7a1"
		"legend_firebird":
			body = "#ff7a2f"
			head = "#ffb43b"
			wing = "#ff5a1f"
			wing2 = "#ffd23f"
			tail = "#ffb43b"
			belly = "#ffd23f"
	_bone(s, "root", "", Vector3.ZERO)
	_bone(s, "body", "root", Vector3(0, 0.18, 0))
	_bone(s, "head", "body", Vector3(0, 0.46, 0.06))
	_bone(s, "wing_l", "body", Vector3(0.12, 0.44, 0.02))
	_bone(s, "wing_r", "body", Vector3(-0.12, 0.44, 0.02))
	_bone(s, "leg_l", "root", Vector3(0.05, 0.16, 0))
	_bone(s, "leg_r", "root", Vector3(-0.05, 0.16, 0))
	_bone(s, "tail", "body", Vector3(0, 0.26, -0.1))
	_part(s, "body", "ball", Vector3(0.26, 0.36, 0.26), Vector3(0, 0.34, 0), body, Vector3(-15, 0, 0))
	_part(s, "body", "ball", Vector3(0.18, 0.24, 0.1), Vector3(0, 0.34, 0.09), belly, Vector3(-15, 0, 0))
	_part(s, "head", "ball", Vector3(0.22, 0.22, 0.22), Vector3(0, 0.55, 0.06), head)
	match id:
		"macaw":
			_part(s, "head", "box", Vector3(0.16, 0.1, 0.04), Vector3(0, 0.55, 0.16), "#f4f1e4")
			_part(s, "head", "box", Vector3(0.08, 0.1, 0.1), Vector3(0, 0.52, 0.21), "#e8e0d0", Vector3(20, 0, 0))
			_part(s, "head", "box", Vector3(0.06, 0.05, 0.06), Vector3(0, 0.47, 0.2), "#3a3a40")
		"toucan":
			_part(s, "head", "box", Vector3(0.18, 0.14, 0.05), Vector3(0, 0.55, 0.15), "#f6e7a1")
			_part(s, "head", "box", Vector3(0.1, 0.13, 0.32), Vector3(0, 0.53, 0.31), "#f59a23")
			_part(s, "head", "box", Vector3(0.105, 0.04, 0.32), Vector3(0, 0.6, 0.31), "#7cc49a")
			_part(s, "head", "box", Vector3(0.1, 0.12, 0.06), Vector3(0, 0.53, 0.48), "#e8453c")
		"legend_firebird":
			_part(s, "head", "box", Vector3(0.07, 0.06, 0.1), Vector3(0, 0.53, 0.19), "#c0392b", Vector3(20, 0, 0))
			for k in 3:
				_part(s, "head", "box", Vector3(0.03, 0.16, 0.03), Vector3(0, 0.7, 0.02 - k * 0.05), "#ffd23f", Vector3(-20 - k * 15, 0, 0))
	_eyes(s, "head", 0.07, 0.58, 0.15, 0.035)
	for side in [-1.0, 1.0]:
		var wn := "wing_l" if side > 0 else "wing_r"
		_part(s, wn, "box", Vector3(0.06, 0.28, 0.2), Vector3(side * 0.15, 0.33, -0.01), wing, Vector3(-15, 0, side * 8))
		_part(s, wn, "box", Vector3(0.065, 0.1, 0.2), Vector3(side * 0.15, 0.43, 0.01), wing2, Vector3(-15, 0, side * 8))
		var ln := "leg_l" if side > 0 else "leg_r"
		_part(s, ln, "box", Vector3(0.03, 0.16, 0.03), Vector3(side * 0.05, 0.08, 0), "#6e6e74")
		_part(s, ln, "box", Vector3(0.06, 0.02, 0.08), Vector3(side * 0.05, 0.01, 0.02), "#6e6e74")
	var long := 0.45 if id != "toucan" else 0.2
	if id == "legend_firebird":
		long = 0.7
	_part(s, "tail", "box", Vector3(0.08, 0.03, long), Vector3(0, 0.2, -0.1 - long * 0.5), tail, Vector3(-20, 0, 0))
	if id == "macaw":
		_part(s, "tail", "box", Vector3(0.06, 0.03, 0.12), Vector3(0, 0.08, -0.47), "#2d6fd1", Vector3(-20, 0, 0))
	if id == "legend_firebird":
		for side in [-1.0, 1.0]:
			_part(s, "tail", "box", Vector3(0.05, 0.02, 0.6), Vector3(side * 0.08, 0.24, -0.4), "#ffd23f", Vector3(-12, side * 14, 0))
			_part(s, "tail", "ball", Vector3(0.1, 0.03, 0.1), Vector3(side * 0.15, 0.17, -0.7), "#c0392b")
		s["glow"] = 0.0
	s["rig"] = {"body": "body", "head": "head", "tail": "tail", "legs": [["leg_l", 0.0, 1, true], ["leg_r", 0.5, -1, true]],
		"wings": [["wing_l", 1.0], ["wing_r", -1.0]]}
	return s


## Saltadores: canguru, jackalope e wolpertinger.
static func _hopper(id: String) -> Dictionary:
	var s := _new()
	s["gait"] = "hop"
	var fur := "#c7875a"
	var light := "#e4c39d"
	var big := id == "kangaroo"
	if id == "legend_jackalope":
		fur = "#b89470"
		light = "#e9dcc6"
	elif id == "legend_wolpertinger":
		fur = "#a07a52"
		light = "#e8d8b8"
	var k := 1.0 if big else 0.5
	_bone(s, "root", "", Vector3.ZERO)
	_bone(s, "body", "root", Vector3(0, 0.45 * k, 0))
	_bone(s, "head", "body", Vector3(0, (1.0 if big else 0.72) * k, 0.14 * k))
	_bone(s, "leg_l", "body", Vector3(0.14 * k, 0.48 * k, -0.02 * k))
	_bone(s, "leg_r", "body", Vector3(-0.14 * k, 0.48 * k, -0.02 * k))
	_bone(s, "tail", "body", Vector3(0, 0.42 * k, -0.24 * k))
	if big:
		_bone(s, "arm_l", "body", Vector3(0.14, 0.86, 0.16))
		_bone(s, "arm_r", "body", Vector3(-0.14, 0.86, 0.16))
		_part(s, "body", "ball", Vector3(0.42, 0.66, 0.42), Vector3(0, 0.7, 0.0), fur, Vector3(-18, 0, 0))
		_part(s, "body", "ball", Vector3(0.28, 0.44, 0.16), Vector3(0, 0.66, 0.15), light, Vector3(-18, 0, 0))
		_part(s, "head", "box", Vector3(0.22, 0.22, 0.28), Vector3(0, 1.1, 0.18), fur)
		_part(s, "head", "box", Vector3(0.15, 0.13, 0.14), Vector3(0, 1.05, 0.36), fur)
		_part(s, "head", "box", Vector3(0.07, 0.05, 0.03), Vector3(0, 1.08, 0.43), "#2c2420")
		for side in [-1.0, 1.0]:
			_part(s, "head", "box", Vector3(0.07, 0.22, 0.04), Vector3(side * 0.08, 1.3, 0.1), fur, Vector3(-10, 0, side * -12))
			var arm := "arm_l" if side > 0 else "arm_r"
			_part(s, arm, "box", Vector3(0.06, 0.24, 0.06), Vector3(side * 0.15, 0.75, 0.22), fur, Vector3(-30, 0, 0))
		_eyes(s, "head", 0.07, 1.16, 0.32, 0.04)
		_part(s, "tail", "box", Vector3(0.11, 0.1, 0.8), Vector3(0, 0.2, -0.6), fur, Vector3(-22, 0, 0))
	else:
		_part(s, "body", "ball", Vector3(0.36, 0.34, 0.48), Vector3(0, 0.26, -0.02), fur)
		_part(s, "body", "ball", Vector3(0.22, 0.2, 0.14), Vector3(0, 0.24, 0.17), light)
		_part(s, "head", "ball", Vector3(0.26, 0.24, 0.26), Vector3(0, 0.42, 0.2), fur)
		_part(s, "head", "box", Vector3(0.05, 0.04, 0.03), Vector3(0, 0.42, 0.33), "#d97a8a")
		for side in [-1.0, 1.0]:
			_part(s, "head", "box", Vector3(0.06, 0.24, 0.035), Vector3(side * 0.06, 0.62, 0.15), fur, Vector3(-15, 0, side * -15))
			_part(s, "head", "box", Vector3(0.03, 0.18, 0.04), Vector3(side * 0.06, 0.61, 0.165), light, Vector3(-15, 0, side * -15))
			# Chifrinhos (galhos de veado).
			_part(s, "head", "box", Vector3(0.025, 0.16, 0.025), Vector3(side * 0.11, 0.58, 0.2), "#efe3c8", Vector3(0, 0, side * -25))
			_part(s, "head", "box", Vector3(0.02, 0.08, 0.02), Vector3(side * 0.15, 0.62, 0.23), "#efe3c8", Vector3(-30, 0, side * -60))
		_eyes(s, "head", 0.07, 0.45, 0.31, 0.035)
		_part(s, "tail", "ball", Vector3(0.12, 0.12, 0.1), Vector3(0, 0.24, -0.27), "#f4f1e4")
		if id == "legend_wolpertinger":
			_bone(s, "wing_l", "body", Vector3(0.14, 0.36, 0.0))
			_bone(s, "wing_r", "body", Vector3(-0.14, 0.36, 0.0))
			_part(s, "wing_l", "box", Vector3(0.24, 0.02, 0.14), Vector3(0.24, 0.4, -0.02), "#d8c4a0", Vector3(0, 0, 25))
			_part(s, "wing_r", "box", Vector3(0.24, 0.02, 0.14), Vector3(-0.24, 0.4, -0.02), "#d8c4a0", Vector3(0, 0, -25))
			s["rig"]["wings"] = [["wing_l", 1.0], ["wing_r", -1.0]]
	for side in [-1.0, 1.0]:
		var leg := "leg_l" if side > 0 else "leg_r"
		_part(s, leg, "box", Vector3(0.12 * k, 0.34 * k, 0.26 * k), Vector3(side * 0.14 * k, 0.3 * k, -0.04 * k), fur)
		_part(s, leg, "box", Vector3(0.1 * k, 0.06 * k, 0.38 * k), Vector3(side * 0.14 * k, 0.03 * k, 0.06 * k), light if not big else "#a86d45")
	var rig: Dictionary = s["rig"]
	rig["body"] = "body"
	rig["head"] = "head"
	rig["tail"] = "tail"
	rig["legs"] = [["leg_l", 0.0, 1, false], ["leg_r", 0.0, -1, false]]
	if big:
		rig["arms"] = [["arm_l", 0.0], ["arm_r", 0.0]]
	return s


## Bípedes grandes: Pé-Grande, troll e leprechaun.
static func _biped(id: String) -> Dictionary:
	var s := _new()
	s["gait"] = "big"
	var fur := "#7a5536"
	var face := "#b48a64"
	var hgt := 2.0
	match id:
		"legend_troll":
			fur = "#8a9a7a"
			face = "#a9b896"
			hgt = 2.2
		"legend_leprechaun":
			fur = "#3f9b4f"
			face = "#f1c9a5"
			hgt = 0.6
	var k := hgt / 2.0
	_bone(s, "root", "", Vector3.ZERO)
	_bone(s, "body", "root", Vector3(0, 0.9 * k, 0))
	_bone(s, "head", "body", Vector3(0, 1.55 * k, 0.04 * k))
	_bone(s, "arm_l", "body", Vector3(0.36 * k, 1.42 * k, 0))
	_bone(s, "arm_r", "body", Vector3(-0.36 * k, 1.42 * k, 0))
	_bone(s, "leg_l", "body", Vector3(0.16 * k, 0.8 * k, 0))
	_bone(s, "leg_r", "body", Vector3(-0.16 * k, 0.8 * k, 0))
	if id == "legend_leprechaun":
		# Sapateiro miudinho: casaco verde, cartola com fivela, barba ruiva, pote de moedas.
		_part(s, "body", "box", Vector3(0.5, 0.6, 0.36) * k, Vector3(0, 1.12, 0) * k, fur)
		_part(s, "body", "box", Vector3(0.52, 0.08, 0.38) * k, Vector3(0, 0.92, 0) * k, "#3b2a20")
		_part(s, "body", "box", Vector3(0.1, 0.09, 0.03) * k, Vector3(0, 0.92, 0.2) * k, "#f2c14e")
		_part(s, "head", "box", Vector3(0.42, 0.38, 0.38) * k, Vector3(0, 1.7, 0.04) * k, face)
		_part(s, "head", "box", Vector3(0.44, 0.2, 0.2) * k, Vector3(0, 1.52, 0.16) * k, "#d9662c")
		_part(s, "head", "box", Vector3(0.1, 0.08, 0.08) * k, Vector3(0, 1.68, 0.25) * k, "#e8a888")
		_part(s, "head", "cyl", Vector3(0.62, 0.05, 0.62) * k, Vector3(0, 1.9, 0.04) * k, "#2d7a3c")
		_part(s, "head", "cyl", Vector3(0.38, 0.42, 0.38) * k, Vector3(0, 2.12, 0.04) * k, "#2d7a3c")
		_part(s, "head", "cyl", Vector3(0.4, 0.08, 0.4) * k, Vector3(0, 1.98, 0.04) * k, "#3b2a20")
		_part(s, "head", "box", Vector3(0.12, 0.1, 0.04) * k, Vector3(0, 1.98, 0.23) * k, "#f2c14e")
		_eyes(s, "head", 0.1 * k, 1.76 * k, 0.235 * k, 0.07 * k)
		for side in [-1.0, 1.0]:
			var arm := "arm_l" if side > 0 else "arm_r"
			_part(s, arm, "box", Vector3(0.14, 0.44, 0.14) * k, Vector3(side * 0.38, 1.2, 0) * k, fur)
			_part(s, arm, "box", Vector3(0.12, 0.1, 0.12) * k, Vector3(side * 0.38, 0.96, 0) * k, face)
			var leg := "leg_l" if side > 0 else "leg_r"
			_part(s, leg, "box", Vector3(0.18, 0.7, 0.2) * k, Vector3(side * 0.16, 0.45, 0) * k, "#3b6b3f")
			_part(s, leg, "box", Vector3(0.2, 0.12, 0.32) * k, Vector3(side * 0.16, 0.06, 0.06) * k, "#3b2a20")
			_part(s, leg, "box", Vector3(0.08, 0.06, 0.04) * k, Vector3(side * 0.16, 0.13, 0.2) * k, "#f2c14e")
		# Pote de moedas na mão direita.
		_part(s, "arm_r", "cyl", Vector3(0.3, 0.24, 0.3) * k, Vector3(-0.42, 0.86, 0.12) * k, "#2b2b30")
		_part(s, "arm_r", "cyl", Vector3(0.26, 0.06, 0.26) * k, Vector3(-0.42, 1.0, 0.12) * k, "#f2c14e")
	else:
		var troll := id == "legend_troll"
		_part(s, "body", "box", Vector3(0.78, 0.86, 0.5) * k, Vector3(0, 1.22, 0) * k, fur)
		_part(s, "body", "box", Vector3(0.5, 0.56, 0.06) * k, Vector3(0, 1.18, 0.26) * k, face if not troll else "#9aaa86")
		_part(s, "body", "box", Vector3(0.7, 0.3, 0.46) * k, Vector3(0, 0.86, 0) * k, fur)
		_part(s, "head", "box", Vector3(0.5, 0.46, 0.46) * k, Vector3(0, 1.84, 0.04) * k, fur)
		_part(s, "head", "box", Vector3(0.36, 0.28, 0.06) * k, Vector3(0, 1.8, 0.28) * k, face)
		_eyes(s, "head", 0.09 * k, 1.86 * k, 0.315 * k, 0.07 * k)
		if troll:
			_part(s, "head", "ball", Vector3(0.18, 0.2, 0.22) * k, Vector3(0, 1.74, 0.38) * k, "#b5c4a0")
			_part(s, "head", "box", Vector3(0.12, 0.12, 0.12) * k, Vector3(0, 2.12, 0.0) * k, "#5e6e52")
			_part(s, "head", "box", Vector3(0.08, 0.16, 0.08) * k, Vector3(0.05, 2.22, -0.02) * k, "#5fae4a")
			for side in [-1.0, 1.0]:
				_part(s, "head", "cone", Vector3(0.1, 0.14, 0.08) * k, Vector3(side * 0.3, 1.86, 0.02) * k, fur, Vector3(0, 0, side * -70))
			# Musgo nos ombros.
			_part(s, "body", "box", Vector3(0.3, 0.08, 0.3) * k, Vector3(0.24, 1.66, 0) * k, "#6fa84f")
			_part(s, "body", "box", Vector3(0.22, 0.06, 0.24) * k, Vector3(-0.28, 1.66, 0.04) * k, "#6fa84f")
		else:
			_part(s, "head", "box", Vector3(0.14, 0.1, 0.08) * k, Vector3(0, 1.76, 0.34) * k, "#8a6446")
			_part(s, "head", "box", Vector3(0.18, 0.04, 0.02) * k, Vector3(0, 1.68, 0.315) * k, "#5a3c28")
		for side in [-1.0, 1.0]:
			var arm := "arm_l" if side > 0 else "arm_r"
			_part(s, arm, "box", Vector3(0.24, 0.78, 0.26) * k, Vector3(side * 0.48, 1.1, 0) * k, fur)
			_part(s, arm, "box", Vector3(0.22, 0.16, 0.26) * k, Vector3(side * 0.48, 0.66, 0.02) * k, face)
			var leg := "leg_l" if side > 0 else "leg_r"
			_part(s, leg, "box", Vector3(0.28, 0.76, 0.3) * k, Vector3(side * 0.18, 0.42, 0) * k, fur)
			_part(s, leg, "box", Vector3(0.3, 0.1, 0.48) * k, Vector3(side * 0.18, 0.05, 0.08) * k, face)
	s["rig"] = {"body": "body", "head": "head", "legs": [["leg_l", 0.0, 1, true], ["leg_r", 0.5, -1, true]],
		"arms": [["arm_l", 0.5], ["arm_r", 0.0]]}
	return s


## O chefe: golem de pedra rechonchudo e sonolento, com cristais nas costas e musgo.
static func _golem() -> Dictionary:
	var s := _new()
	s["gait"] = "big"
	s["boss"] = true
	var stone := "#8f8a84"
	var light := "#b5afa6"
	var dark := "#6e6964"
	_bone(s, "root", "", Vector3.ZERO)
	_bone(s, "body", "root", Vector3(0, 1.2, 0))
	_bone(s, "head", "body", Vector3(0, 2.3, 0.3))
	_bone(s, "arm_l", "body", Vector3(1.05, 2.0, 0.1))
	_bone(s, "arm_r", "body", Vector3(-1.05, 2.0, 0.1))
	_bone(s, "leg_l", "body", Vector3(0.45, 0.9, 0))
	_bone(s, "leg_r", "body", Vector3(-0.45, 0.9, 0))
	_part(s, "body", "ball", Vector3(2.0, 1.9, 1.7), Vector3(0, 1.6, 0), stone)
	_part(s, "body", "ball", Vector3(1.4, 1.2, 0.4), Vector3(0, 1.5, 0.68), light)
	_part(s, "body", "box", Vector3(0.9, 0.2, 0.8), Vector3(0.3, 2.45, -0.2), "#6fa84f", Vector3(0, 20, 8))
	_part(s, "body", "box", Vector3(0.5, 0.16, 0.5), Vector3(-0.5, 2.3, 0.4), "#7cc49a", Vector3(0, -15, -6))
	# Cristais nas costas.
	var cr := [["#ff8fc8", Vector3(0.0, 2.2, -0.7), Vector3(-35, 0, 0), 0.7], ["#7ee8d8", Vector3(0.45, 2.0, -0.7), Vector3(-30, 0, -20), 0.55],
		["#c9a4ff", Vector3(-0.45, 2.05, -0.65), Vector3(-30, 0, 20), 0.6], ["#ff8fc8", Vector3(0.2, 1.6, -0.85), Vector3(-55, 0, -10), 0.45],
		["#7ee8d8", Vector3(-0.3, 1.5, -0.85), Vector3(-55, 0, 15), 0.4]]
	for c: Array in cr:
		var h := float(c[3])
		_part(s, "body", "gem", Vector3(h * 0.45, h, h * 0.45), c[1], c[0], c[2])
	_part(s, "head", "box", Vector3(1.0, 0.8, 0.85), Vector3(0, 2.55, 0.42), light)
	_part(s, "head", "box", Vector3(1.04, 0.2, 0.89), Vector3(0, 2.9, 0.42), stone)
	# Olhos sonolentos (risquinhos) e bochechas.
	for side in [-1.0, 1.0]:
		_part(s, "head", "box", Vector3(0.22, 0.05, 0.04), Vector3(side * 0.24, 2.6, 0.86), "#2d2a2e")
		_part(s, "head", "box", Vector3(0.16, 0.1, 0.03), Vector3(side * 0.34, 2.42, 0.86), "#e8a3a3")
	_part(s, "head", "box", Vector3(0.2, 0.06, 0.04), Vector3(0, 2.36, 0.86), "#4a4548")
	for side in [-1.0, 1.0]:
		var arm := "arm_l" if side > 0 else "arm_r"
		_part(s, arm, "ball", Vector3(0.6, 0.6, 0.6), Vector3(side * 1.12, 1.95, 0.1), stone)
		_part(s, arm, "box", Vector3(0.48, 1.0, 0.52), Vector3(side * 1.18, 1.3, 0.12), stone)
		_part(s, arm, "ball", Vector3(0.7, 0.6, 0.7), Vector3(side * 1.2, 0.72, 0.16), dark)
		var leg := "leg_l" if side > 0 else "leg_r"
		_part(s, leg, "box", Vector3(0.6, 0.8, 0.65), Vector3(side * 0.48, 0.42, 0), dark)
		_part(s, leg, "box", Vector3(0.68, 0.2, 0.8), Vector3(side * 0.48, 0.1, 0.08), stone)
	s["rig"] = {"body": "body", "head": "head", "legs": [["leg_l", 0.0, 1, true], ["leg_r", 0.5, -1, true]],
		"arms": [["arm_l", 0.5], ["arm_r", 0.0]]}
	return s
