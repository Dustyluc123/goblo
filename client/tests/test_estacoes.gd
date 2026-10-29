extends SceneTree
## Estações no cliente (Seasons) com os mesmos casos de server/internal/game/season_test.go.
##
## Uso: godot --headless --path . -s tests/test_estacoes.gd

func _init() -> void:
	var day := func(m: int, d: int, y := 2027) -> float:
		return float(Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": d, "hour": 12, "minute": 0, "second": 0}))
	var berlin := 52.52
	var sao_paulo := -23.55
	var manaus := -3.12
	var sydney := -33.87
	var cases := [
		[day.call(1, 15), berlin, "winter"], [day.call(1, 15), sao_paulo, "summer"], [day.call(1, 15), manaus, "none"],
		[day.call(7, 15), berlin, "summer"], [day.call(7, 15), sydney, "winter"], [day.call(4, 20), berlin, "spring"],
		[day.call(4, 20), sydney, "autumn"], [day.call(10, 29, 2026), berlin, "autumn"], [day.call(10, 29, 2026), sao_paulo, "spring"],
		[day.call(12, 25), berlin, "winter"], [day.call(3, 1), 60.0, "winter"], [day.call(9, 1), -40.0, "winter"],
	]
	var fails := 0
	for c: Array in cases:
		var got := Seasons.season_at(c[0], c[1])
		var ok: bool = got == c[2]
		if not ok:
			fails += 1
		print("%s %s em %.2f: %s (esperado %s)" % ["ok    " if ok else "FALHOU", Time.get_date_string_from_unix_time(int(c[0])), c[1], got, c[2]])
	# Os pesos somam 1 e mudam aos poucos (transição de ~20 dias).
	for p in [0.0, 0.05, 0.5, 0.97, 1.0, 2.03, 3.5, 3.99]:
		var total := 0.0
		for s in 4:
			total += Seasons.weight(p, s)
		if absf(total - 1.0) > 0.01:
			fails += 1
			print("FALHOU pesos na fase %.2f somam %.3f" % [p, total])
	var a := Seasons.weight(1.95, 2)
	var b := Seasons.weight(2.05, 2)
	if not (a > 0.0 and a < 0.5 and b > 0.5 and b < 1.0):
		fails += 1
		print("FALHOU a virada para o outono não é gradual: %.2f → %.2f" % [a, b])
	print("estações: %s" % ("tudo certo" if fails == 0 else "%d falhas" % fails))
	quit(1 if fails > 0 else 0)
