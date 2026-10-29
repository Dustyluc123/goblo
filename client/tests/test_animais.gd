extends SceneTree
## Confere que o trajeto dos animais no cliente (AnimalPath) dá exatamente as mesmas poses
## que o servidor (AnimalAt, em Go). As poses de referência ficam em tests/animal_paths.json,
## gerado por: GOBLO_GOLDEN=1 go test ./internal/game -run AnimalGolden (em server/).
##
## Uso: godot --headless --path . -s tests/test_animais.gd

func _init() -> void:
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/animal_paths.json"))
	var a: Dictionary = g["animal"]
	var fails := 0
	for p: Dictionary in g["poses"]:
		var got := AnimalPath.at(a, float(p["t"]))
		var ok: bool = absf(float(got["x"]) - float(p["x"])) < 1e-6 and absf(float(got["y"]) - float(p["y"])) < 1e-6 \
			and absf(float(got["heading"]) - float(p["heading"])) < 1e-6 and got["state"] == p["state"]
		if not ok:
			fails += 1
		print("%s t=%.3f: cliente (%.4f, %.4f, %s), servidor (%.4f, %.4f, %s)" % [
			"ok    " if ok else "FALHOU", float(p["t"]), got["x"], got["y"], got["state"], p["x"], p["y"], p["state"]])
	# O hash de 32 bits precisa bater com o do Go em valores conhecidos.
	print("hash32(1, 2, 3) = %d" % AnimalPath.hash32(1, 2, 3))
	print("animais: %s" % ("tudo certo" if fails == 0 else "%d falhas" % fails))
	quit(1 if fails > 0 else 0)
