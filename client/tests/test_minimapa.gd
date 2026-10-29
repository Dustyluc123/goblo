extends SceneTree
## Teste da setinha do mini mapa: olhando para norte, leste, sul e oeste em vários lugares
## do planeta, o ângulo da seta (a partir do norte, sentido horário) bate com a direção.
##
##   godot --headless --path . -s tests/test_minimapa.gd


func _init() -> void:
	var places := [Vector2(-23.55, -46.63), Vector2(0, 0), Vector2(48.85, 2.35), Vector2(35.7, 139.7), Vector2(-33.9, 151.2), Vector2(64, -21)]
	var expected := {"norte": 0.0, "leste": 90.0, "sul": 180.0, "oeste": -90.0}
	var fails := 0
	for ll in places:
		var up := WorldData.lat_lon_to_vec(ll.x, ll.y)
		# Norte e leste geográficos, pela variação de latitude e longitude (independe do mapa).
		var north := (WorldData.lat_lon_to_vec(ll.x + 0.01, ll.y) - up).normalized()
		var east := (WorldData.lat_lon_to_vec(ll.x, ll.y + 0.01) - up).normalized()
		var dirs := {"norte": north, "leste": east, "sul": -north, "oeste": -east}
		for name in dirs:
			var got := rad_to_deg(Minimap.heading(up, dirs[name]))
			if absf(angle_difference(deg_to_rad(got), deg_to_rad(expected[name]))) > deg_to_rad(1.0):
				fails += 1
				print("FALHOU %s em %s: seta %.1f°, esperado %.1f°" % [name, ll, got, expected[name]])
	print("mini mapa: %s" % ("ok" if fails == 0 else "%d falhas" % fails))
	quit(1 if fails else 0)
