class_name LotGeom
extends RefCounted
## Contas da grade do lote no cliente (iguais às do servidor, server/internal/game/lots.go).
##
## O lote fica no plano do topo da célula (WorldData.cell_frame). (x0, y0) é o canto
## mínimo; a grade cresce para leste (x) e norte (y) em quadradinhos de `tile` unidades.
## Um objeto de footprint [w, h] girado `rot` vezes 90° ocupa [h, w] quando rot é ímpar.
## O "para frente" do lote é o lado sul (y = 0): é onde fica a plaquinha com o nome.


## Footprint girado.
static func rotated(fp: Vector2i, rot: int) -> Vector2i:
	return Vector2i(fp.y, fp.x) if rot % 2 == 1 else fp


static func footprint_of(item: Dictionary) -> Vector2i:
	var fp: Array = item.get("footprint", [1, 1])
	return Vector2i(int(fp[0]), int(fp[1]))


## Ponto do mundo no plano do lote, em quadradinhos (pode ser fracionário).
static func point(f: Dictionary, lot: Dictionary, tile: float, tx: float, ty: float, lift := 0.0) -> Vector3:
	return WorldData.frame_point(f, float(lot["x0"]) + tx * tile, float(lot["y0"]) + ty * tile) + (f["center"] as Vector3) * lift


## Coordenadas (em quadradinhos, fracionárias) de um ponto do mundo no lote.
static func tile_coords(f: Dictionary, lot: Dictionary, tile: float, p: Vector3) -> Vector2:
	var q := WorldData.frame_coords(f, p)
	return Vector2((q.x - float(lot["x0"])) / tile, (q.y - float(lot["y0"])) / tile)


## Transformação de um modelo colocado no lote: centrado no footprint, apoiado no chão,
## girado em passos de 90°. `aabb` é a caixa do modelo sem escala.
static func model_transform(f: Dictionary, lot: Dictionary, tile: float, fp: Vector2i, x: int, y: int, rot: int, aabb: AABB, scale: float) -> Transform3D:
	var r := rotated(fp, rot)
	var center := point(f, lot, tile, x + r.x * 0.5, y + r.y * 0.5)
	var basis := WorldData.frame_basis(f, rot * PI * 0.5, scale)
	var offset := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	return Transform3D(basis, center - basis * offset)


## O retângulo [x, x+w) × [y, y+h) cabe na grade e não encosta em nenhum dos `taken`?
static func fits(lot_tiles: int, rect: Rect2i, taken: Array) -> bool:
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > lot_tiles or rect.end.y > lot_tiles:
		return false
	for t: Rect2i in taken:
		if t.intersects(rect):
			return false
	return true
