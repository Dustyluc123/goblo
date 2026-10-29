class_name GlobeBuilder
extends RefCounted
## Monta as malhas do globo a partir do mundo do servidor.
##
## Terra: cada célula vira um "azulejo" na altura do seu bioma: um polígono plano no meio
## (o topo) e um anel um pouco mais escuro em volta (a borda sutil do hexágono). Onde o
## vizinho é mais baixo, desce uma parede. A geometria é indexada e o sombreamento flat é
## calculado no shader (terrain.gdshader), o que deixa a montagem rápida.
##
## Oceano: um leque por célula no nível do mar, com a profundidade (distância até a costa)
## e a espuma na cor do vértice, para o shader animado (ocean.gdshader).
##
## Os triângulos são pensados em sentido anti-horário visto de fora (a convenção do
## servidor) e gravados em sentido horário, que é a face da frente no Godot.

const INSET := 0.86
## As paredes da costa descem abaixo do nível do mar, para as ondas não mostrarem frestas.
const SEA_FLOOR := -0.6
const EDGE_DARKEN := 0.88

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const OCEAN_SHADER := preload("res://shaders/ocean.gdshader")

static var _land_material: ShaderMaterial
static var _ocean_material: ShaderMaterial


static func land_material() -> ShaderMaterial:
	if _land_material == null:
		_land_material = ShaderMaterial.new()
		_land_material.shader = TERRAIN_SHADER
	return _land_material


static func ocean_material() -> ShaderMaterial:
	if _ocean_material == null:
		_ocean_material = ShaderMaterial.new()
		_ocean_material.shader = OCEAN_SHADER
	return _ocean_material


## Malhas [terra, oceano] de um conjunto de células (qualquer uma pode ser null).
static func build_meshes(world: WorldData, cells: PackedInt32Array) -> Array[ArrayMesh]:
	var land := _land_arrays(world, cells)
	var ocean := _ocean_arrays(world, cells)
	var out: Array[ArrayMesh] = [null, null]
	if (land[2] as PackedInt32Array).size() > 0:
		out[0] = _mesh(land, land_material())
	if (ocean[2] as PackedInt32Array).size() > 0:
		out[1] = _mesh(ocean, ocean_material())
	return out


## Triângulos soltos (terra + oceano) de um conjunto de células, para ConcavePolygonShape3D.
static func collision_faces(world: WorldData, cells: PackedInt32Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for arrays in [_land_arrays(world, cells), _ocean_arrays(world, cells)]:
		var verts: PackedVector3Array = arrays[0]
		var idx: PackedInt32Array = arrays[2]
		var start := faces.size()
		faces.resize(start + idx.size())
		for i in idx.size():
			faces[start + i] = verts[idx[i]]
	return faces


## Arrays [vértices, cores, índices] da terra.
static func _land_arrays(world: WorldData, cells: PackedInt32Array) -> Array:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var r := world.radius
	for i in cells:
		if world.land[i] == 0:
			continue
		var c := world.centers[i]
		var top_h := r + world.heights[i]
		var top := BiomeStyle.top_color(world, i)
		# Alfa da cor = o chão muda com as estações (o shader do terreno usa; ver Seasons).
		top.a = 1.0 if BiomeStyle.seasonal_ground(world, i) else 0.0
		var edge := Color(top.r * EDGE_DARKEN, top.g * EDGE_DARKEN, top.b * EDGE_DARKEN, top.a)
		var wall := BiomeStyle.wall_color(world, i)
		var poly := world.vertices[i]
		var nb := world.neighbors[i]
		var n := poly.size()
		var base := verts.size()
		# 0: centro; 1..n: topo interno; n+1..2n: borda interna; 2n+1..3n: canto externo.
		verts.append(c * top_h)
		colors.append(top)
		for k in n:
			var d := c.lerp(poly[k], INSET).normalized()
			verts.append(d * (top_h / d.dot(c)))
			colors.append(top)
		for k in n:
			verts.append(verts[base + 1 + k])
			colors.append(edge)
		for k in n:
			verts.append(poly[k] * top_h)
			colors.append(edge)
		for k in n:
			var k2 := (k + 1) % n
			var it := base + 1
			var ie := base + 1 + n
			var oc := base + 1 + 2 * n
			idx.append_array([base, it + k2, it + k])
			idx.append_array([ie + k, oc + k2, oc + k])
			idx.append_array([ie + k, ie + k2, oc + k2])
			var j := nb[k]
			var low_h := world.heights[j] if world.land[j] == 1 else SEA_FLOOR
			if low_h < world.heights[i] - 0.01:
				var w0 := verts.size()
				verts.append_array([poly[k] * top_h, poly[k2] * top_h, poly[k] * (r + low_h), poly[k2] * (r + low_h)])
				colors.append_array([wall, wall, wall.darkened(0.15), wall.darkened(0.15)])
				idx.append_array([w0, w0 + 3, w0 + 2, w0, w0 + 1, w0 + 3])
	return [verts, colors, idx]


## Arrays [vértices, cores, índices] do oceano. Cor: r = profundidade (0 costa → 1 alto-mar),
## g = espuma (1 em cantos que encostam na terra).
static func _ocean_arrays(world: WorldData, cells: PackedInt32Array) -> Array:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var r := world.radius
	var max_depth := float(WorldData.MAX_WATER_DEPTH)
	for i in cells:
		if world.land[i] == 1:
			continue
		var c := world.centers[i]
		var poly := world.vertices[i]
		var nb := world.neighbors[i]
		var n := poly.size()
		var base := verts.size()
		var d0 := world.water_depth[i]
		verts.append(c * r)
		colors.append(Color(clampf((d0 - 0.5) / max_depth, 0.0, 1.0), 0.0, 0.0))
		for k in n:
			var a := nb[(k + n - 1) % n]
			var b := nb[k]
			var d := mini(d0, mini(world.water_depth[a], world.water_depth[b]))
			var foam := 1.0 if (world.land[a] == 1 or world.land[b] == 1) else 0.0
			verts.append(poly[k] * r)
			colors.append(Color(clampf((d - 0.5) / max_depth, 0.0, 1.0), foam, 0.0))
		for k in n:
			idx.append_array([base, base + 1 + (k + 1) % n, base + 1 + k])
	return [verts, colors, idx]


static func _mesh(arrays_in: Array, mat: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = arrays_in[0]
	arrays[Mesh.ARRAY_COLOR] = arrays_in[1]
	arrays[Mesh.ARRAY_INDEX] = arrays_in[2]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


## Contorno de destaque da célula embaixo do personagem (um anel claro perto da borda).
static func highlight(world: WorldData, id: int) -> ArrayMesh:
	var c := world.centers[id]
	var h := world.surface_radius(id) + 0.05
	var poly := world.vertices[id]
	var n := poly.size()
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for corner in poly:
		for f in [0.9, 0.96]:
			var d := c.lerp(corner, f).normalized()
			verts.append(d * (h / d.dot(c)))
	for k in n:
		var a := 2 * k
		var b := 2 * ((k + 1) % n)
		idx.append_array([a, b + 1, a + 1, a, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh
