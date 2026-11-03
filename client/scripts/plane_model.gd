class_name PlaneModel
extends RefCounted
## Avião low-poly (fase 3.5): não há modelo de avião nos pacotes, então ele é montado em
## código no mesmo estilo: formas simples, cantos chanfrados (fuselagem octogonal), cores
## pastel e proporções gordinhas. Uma malha só, com cor por vértice (o material dos modelos
## da ModelLibrary), olhando para -Z. Cerca de 4 unidades de comprimento e 3,8 de envergadura.
## Fase 3.6: porta do lado esquerdo (-X), perto do nariz, e trem de pouso; as rodas encostam
## em y = GROUND.

const BODY := Color("fbf3e4")
const STRIPE := Color("ff9fb8")
const WING := Color("a9d8ee")
const DARK := Color("5b6f8c")
const ENGINE := Color("d9dde6")
const TAIL := Color("ff9fb8")
const DOOR := Color("c9d6e3")
## Altura (no modelo) de baixo das rodas: o avião parado fica `-GROUND × escala` acima do chão.
const GROUND := -0.95
## Porta (no modelo): centro e altura. Na praça, a escadinha encosta nela.
const DOOR_CENTER := Vector3(-0.53, 0.1, -1.15)
const DOOR_HEIGHT := 0.48

static var _mesh: ArrayMesh
static var _flying: ArrayMesh
## Centro da peça sendo montada: cada triângulo é virado para fora dele (frente no sentido
## horário, como o Godot quer), sem depender da ordem em que os cantos foram escritos.
static var _ref := Vector3.ZERO


static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = _build(true)
	return _mesh


## O mesmo avião com o trem de pouso recolhido (no arco do voo).
static func flying_mesh() -> ArrayMesh:
	if _flying == null:
		_flying = _build(false)
	return _flying


static func _build(gear: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Fuselagem: anéis octogonais ao longo de Z (nariz em -Z), gordinha no meio.
	var rings := [[-2.0, 0.08, 0.10], [-1.8, 0.32, 0.30], [-1.45, 0.5, 0.48], [-0.9, 0.58, 0.56],
		[0.2, 0.58, 0.56], [1.0, 0.5, 0.5], [1.6, 0.3, 0.36], [2.0, 0.1, 0.22]]
	var sides := 8
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var col := STRIPE if i == 3 else BODY
		for k in sides:
			var t0 := (k + 0.5) * TAU / sides
			var t1 := (k + 1.5) * TAU / sides
			var p00 := Vector3(cos(t0) * a[1], sin(t0) * a[2] + 0.05 * i, a[0])
			var p01 := Vector3(cos(t1) * a[1], sin(t1) * a[2] + 0.05 * i, a[0])
			var p10 := Vector3(cos(t0) * b[1], sin(t0) * b[2] + 0.05 * (i + 1), b[0])
			var p11 := Vector3(cos(t1) * b[1], sin(t1) * b[2] + 0.05 * (i + 1), b[0])
			var c := col
			# Janelinhas do piloto: a faixa de cima perto do nariz fica escura.
			if i == 1 and (k == 1 or k == 2):
				c = DARK
			_ref = Vector3(0, 0.05 * (i + 0.5), (float(a[0]) + float(b[0])) * 0.5)
			_quad(st, p00, p10, p11, p01, c)
	# Tampa do nariz e da cauda.
	for end in [0, rings.size() - 1]:
		var r: Array = rings[end]
		var center := Vector3(0, 0.05 * end, r[0] + (-0.06 if end == 0 else 0.06))
		_ref = Vector3(0, 0.05 * end, 0.0)
		for k in sides:
			var t0 := (k + 0.5) * TAU / sides
			var t1 := (k + 1.5) * TAU / sides
			var p0 := Vector3(cos(t0) * r[1], sin(t0) * r[2] + 0.05 * end, r[0])
			var p1 := Vector3(cos(t1) * r[1], sin(t1) * r[2] + 0.05 * end, r[0])
			if end == 0:
				_tri(st, center, p1, p0, BODY)
			else:
				_tri(st, center, p0, p1, BODY)
	# Janelinhas dos passageiros: quadradinhos escuros dos dois lados.
	for side in [-1.0, 1.0]:
		for j in 5:
			var z := -0.9 + j * 0.32
			var x: float = 0.575 * side
			_box(st, Vector3(x, 0.2, z), Vector3(0.03, 0.14, 0.16), DARK)
	# Asas (um pouco para trás do meio), com a ponta arredondada por um chanfro.
	_wedge(st, Vector3(0, -0.12, -0.15), 1.9, 0.62, 0.42, 0.08, WING)
	# Motores embaixo das asas.
	for side in [-1.0, 1.0]:
		_cyl(st, Vector3(1.05 * side, -0.32, -0.25), 0.17, 0.62, ENGINE)
	# Porta do lado esquerdo, perto do nariz (com moldura escura).
	_box(st, DOOR_CENTER + Vector3(-0.005, 0, 0), Vector3(0.05, DOOR_HEIGHT + 0.06, 0.3), DARK)
	_box(st, DOOR_CENTER + Vector3(-0.03, 0, 0), Vector3(0.03, DOOR_HEIGHT, 0.22), DOOR)
	# Trem de pouso: perna do nariz e duas pernas principais, com rodas gordinhas.
	for g: Vector3 in ([Vector3(0, 0, -1.45), Vector3(-0.32, 0, 0.05), Vector3(0.32, 0, 0.05)] if gear else []):
		var top := -0.36 if g.z < -1.0 else -0.42
		_box(st, Vector3(g.x, (top + GROUND + 0.14) * 0.5, g.z), Vector3(0.06, top - GROUND - 0.14, 0.06), ENGINE)
		for side: float in ([-1.0, 1.0] if g.z > -1.0 else [0.0]):
			_box(st, Vector3(g.x + side * 0.07, GROUND + 0.09, g.z), Vector3(0.09 if side != 0.0 else 0.1, 0.18, 0.18), DARK)
	# Cauda: leme em pé e estabilizadores.
	_box(st, Vector3(0, 0.75, 1.65), Vector3(0.08, 0.75, 0.5), TAIL)
	_wedge(st, Vector3(0, 0.3, 1.75), 0.75, 0.32, 0.22, 0.06, WING)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, ModelLibrary.baked_material())
	return m


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var out := (a + b + c) / 3.0 - _ref
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


## Quadrilátero (a, b, c, d em volta), visto de fora.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	_ref = c
	var h := s * 0.5
	var v := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	for f: Array in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		_quad(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], col)


## Asa simétrica: meia-envergadura `span`, corda na raiz `root` e na ponta `tip`, espessura `th`.
static func _wedge(st: SurfaceTool, c: Vector3, span: float, root: float, tip: float, th: float, col: Color) -> void:
	for side in [-1.0, 1.0]:
		var r0 := c + Vector3(0, 0, -root * 0.5)
		var r1 := c + Vector3(0, 0, root * 0.5)
		var t0 := c + Vector3(span * side, 0.06, -tip * 0.5 + 0.18)
		var t1 := c + Vector3(span * side, 0.06, tip * 0.5 + 0.18)
		var up := Vector3(0, th * 0.5, 0)
		_ref = (r0 + r1 + t0 + t1) * 0.25
		var pts := [r0 + up, r1 + up, t1 + up, t0 + up, r0 - up, r1 - up, t1 - up, t0 - up]
		var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2]]
		for f: Array in faces:
			if side < 0:
				_quad(st, pts[f[3]], pts[f[2]], pts[f[1]], pts[f[0]], col)
			else:
				_quad(st, pts[f[0]], pts[f[1]], pts[f[2]], pts[f[3]], col)


## Cilindro octogonal deitado (eixo Z), para os motores.
static func _cyl(st: SurfaceTool, c: Vector3, r: float, length: float, col: Color) -> void:
	var sides := 8
	_ref = c
	var z0 := c.z - length * 0.5
	var z1 := c.z + length * 0.5
	for k in sides:
		var t0 := (k + 0.5) * TAU / sides
		var t1 := (k + 1.5) * TAU / sides
		var a := Vector3(c.x + cos(t0) * r, c.y + sin(t0) * r, z0)
		var b := Vector3(c.x + cos(t1) * r, c.y + sin(t1) * r, z0)
		var a2 := Vector3(a.x, a.y, z1)
		var b2 := Vector3(b.x, b.y, z1)
		_quad(st, a, a2, b2, b, col)
		_tri(st, Vector3(c.x, c.y, z0), b, a, DARK)
		_tri(st, Vector3(c.x, c.y, z1), a2, b2, col)
