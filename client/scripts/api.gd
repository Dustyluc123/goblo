class_name Api
extends Node
## Cliente HTTP do servidor do jogo. Cada pedido usa um HTTPRequest próprio, então vários
## pedidos podem correr ao mesmo tempo. O token do jogador vai no cabeçalho Authorization.
##
## Uso: var r := await api.request("POST", "/interact", {"object": 12, "action": "shake"})
## r = {"ok": bool, "status": int, "data": Variant, "error": código, "message": texto}

var base_url := "http://127.0.0.1:8080"
var token := ""
## Pedidos em andamento (para o painel F2).
var in_flight := 0


## O JSON do Godot lê todo número como float e escreve 12.0; o servidor (Go) recusa
## decimal em campo inteiro. Números sem parte decimal viram int antes de enviar.
static func _ints(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 9.0e15:
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _ints(x))
	return v


func request(method: String, path: String, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var payload := ""
	if body != null:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(_ints(body))
	var methods := {"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST}
	in_flight += 1
	var err := http.request(base_url + path, headers, methods.get(method, HTTPClient.METHOD_GET), payload)
	var out := {"ok": false, "status": 0, "data": null, "error": "", "message": "", "details": null}
	if err != OK:
		in_flight -= 1
		http.queue_free()
		out["error"] = "request"
		out["message"] = "Não consegui falar com o servidor."
		return out
	var res: Array = await http.request_completed
	in_flight -= 1
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var raw: PackedByteArray = res[3]
	out["status"] = code
	if result != HTTPRequest.RESULT_SUCCESS:
		out["error"] = "offline"
		out["message"] = "Sem resposta do servidor."
		return out
	var data: Variant = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
	out["data"] = data
	out["ok"] = code >= 200 and code < 300
	if not out["ok"] and data is Dictionary:
		out["error"] = str(data.get("error", "http"))
		out["message"] = str(data.get("message", "Erro %d." % code))
		out["details"] = data.get("details")
	elif not out["ok"]:
		out["error"] = "http"
		out["message"] = "Erro %d no servidor." % code
	return out
