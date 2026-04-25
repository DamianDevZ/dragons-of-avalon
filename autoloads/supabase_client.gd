extends Node

const SUPABASE_URL := "https://oyoeksaytiitszzmohvp.supabase.co"
const ANON_KEY     := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im95b2Vrc2F5dGlpdHN6em1vaHZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxNTA3MDEsImV4cCI6MjA5MjcyNjcwMX0.G7zXEgWFUI5dnGGmQZHSfoxgrRjTt0oNwIQ_Uqsz8t0"

signal auth_success(session: Dictionary)
signal auth_error(message: String)
signal realtime_event(payload: Dictionary)

var _access_token  : String = ""
var _refresh_token : String = ""
var _user_id       : String = ""
var _pending_requests : Array[HTTPRequest] = []
var _ws : WebSocketPeer = null


func sign_up(email: String, password: String) -> void:
	var body := JSON.stringify({"email": email, "password": password})
	_post_auth("/auth/v1/signup", body, _on_auth_response)


func sign_in(email: String, password: String) -> void:
	var body := JSON.stringify({"email": email, "password": password})
	_post_auth("/auth/v1/token?grant_type=password", body, _on_auth_response)


func sign_out() -> void:
	_access_token  = ""
	_refresh_token = ""
	_user_id       = ""


func is_authenticated() -> bool:
	return _access_token != ""


func get_user_id() -> String:
	return _user_id


func select(table: String, columns: String = "*", filters: String = "") -> Signal:
	var path := "/rest/v1/%s?select=%s" % [table, columns]
	if filters != "":
		path += "&" + filters
	return _request("GET", path, "")


func insert(table: String, row: Dictionary) -> Signal:
	return _request("POST", "/rest/v1/" + table, JSON.stringify(row))


func db_update(table: String, filter: String, data: Dictionary) -> Signal:
	return _request("PATCH", "/rest/v1/%s?%s" % [table, filter], JSON.stringify(data))


func db_delete(table: String, filter: String) -> Signal:
	return _request("DELETE", "/rest/v1/%s?%s" % [table, filter], "")


func call_rpc(function_name: String, params: Dictionary = {}) -> Signal:
	return _request("POST", "/rest/v1/rpc/" + function_name, JSON.stringify(params))


func call_function(endpoint: String, body: Dictionary = {}) -> Signal:
	return _request("POST", "/functions/v1/" + endpoint, JSON.stringify(body))


func realtime_subscribe(_table: String) -> void:
	if _ws != null:
		return
	_ws = WebSocketPeer.new()
	var ws_url := SUPABASE_URL.replace("https://", "wss://") + "/realtime/v1/websocket?apikey=" + ANON_KEY
	_ws.connect_to_url(ws_url)


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			var raw : String = _ws.get_packet().get_string_from_utf8()
			var parsed : Variant = JSON.parse_string(raw)
			if parsed != null and typeof(parsed) == TYPE_DICTIONARY:
				var pd := parsed as Dictionary
				if pd.get("type") == "postgres_changes":
					realtime_event.emit(pd.get("payload", {}) as Dictionary)
	elif state == WebSocketPeer.STATE_CLOSED:
		_ws = null


func _request(method_str: String, path: String, body: String) -> Signal:
	var req := HTTPRequest.new()
	add_child(req)
	_pending_requests.append(req)
	var method : int = HTTPClient.METHOD_GET
	match method_str:
		"POST":   method = HTTPClient.METHOD_POST
		"PATCH":  method = HTTPClient.METHOD_PATCH
		"DELETE": method = HTTPClient.METHOD_DELETE
	var headers := _build_headers()
	var url     := SUPABASE_URL + path
	var wrapper := SignalResponseWrapper.new()
	req.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			_pending_requests.erase(req)
			req.queue_free()
			var text : String = body_bytes.get_string_from_utf8()
			var parsed : Variant = JSON.parse_string(text)
			if code >= 200 and code < 300:
				wrapper.emit_success(parsed if parsed != null else {})
			else:
				var err_msg : String = text if text != "" else "HTTP %d" % code
				wrapper.emit_error(err_msg)
	)
	req.request(url, headers, method, body)
	return wrapper.completed


func _build_headers() -> PackedStringArray:
	var h := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + ANON_KEY,
		"Prefer: return=representation",
	])
	if _access_token != "":
		h.append("Authorization: Bearer " + _access_token)
	return h


func _post_auth(path: String, body: String, callback: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(callback.bind(req))
	req.request(
		SUPABASE_URL + path,
		PackedStringArray(["Content-Type: application/json", "apikey: " + ANON_KEY]),
		HTTPClient.METHOD_POST,
		body
	)


func _on_auth_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	var text : String = body.get_string_from_utf8()
	var parsed : Variant = JSON.parse_string(text)
	if parsed == null or code >= 400:
		auth_error.emit(text)
		return
	var pd := parsed as Dictionary
	_access_token  = pd.get("access_token",  "")
	_refresh_token = pd.get("refresh_token", "")
	var user : Variant = pd.get("user", {})
	if typeof(user) == TYPE_DICTIONARY:
		_user_id = (user as Dictionary).get("id", "")
	auth_success.emit(pd)


class SignalResponseWrapper extends RefCounted:
	signal completed(data: Variant)

	func emit_success(data: Variant) -> void:
		completed.emit(data)

	func emit_error(message: String) -> void:
		completed.emit({"error": message})