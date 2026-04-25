## SupabaseClient — Autoload Singleton
##
## Central wrapper for all Supabase communication.
## Handles authentication state and provides async helpers for:
##   - REST (PostgREST) calls: select, insert, update, delete
##   - RPC calls (Edge Functions via /rest/v1/rpc or /functions/v1/)
##   - Realtime WebSocket subscriptions (world map live updates)
##
## Configuration: Set SUPABASE_URL and SUPABASE_ANON_KEY in
## Project Settings → Globals, or replace the constants below
## with your actual project values before first run.

extends Node

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
const SUPABASE_URL  := "https://oyoeksaytiitszzmohvp.supabase.co"
const ANON_KEY      := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im95b2Vrc2F5dGlpdHN6em1vaHZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxNTA3MDEsImV4cCI6MjA5MjcyNjcwMX0.G7zXEgWFUI5dnGGmQZHSfoxgrRjTt0oNwIQ_Uqsz8t0"

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted after a successful sign-in or sign-up. Carries the session dict.
signal auth_success(session: Dictionary)
## Emitted when auth fails. Carries the error message string.
signal auth_error(message: String)
## Emitted when the access token is refreshed automatically.
signal token_refreshed

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _access_token  : String = ""
var _refresh_token : String = ""
var _user_id       : String = ""

# Tracks in-flight HTTPRequest nodes so they can be freed after use.
var _pending_requests : Array[HTTPRequest] = []

# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------

## Sign up a new player with email + password.
## On success, stores the session and emits auth_success.
func sign_up(email: String, password: String) -> void:
	var body := JSON.stringify({"email": email, "password": password})
	_post_auth("/auth/v1/signup", body, _on_auth_response)


## Sign in an existing player.
func sign_in(email: String, password: String) -> void:
	var body := JSON.stringify({
		"email": email,
		"password": password
	})
	_post_auth("/auth/v1/token?grant_type=password", body, _on_auth_response)


## Sign out and clear local session data.
func sign_out() -> void:
	_access_token  = ""
	_refresh_token = ""
	_user_id       = ""


## True if the player currently has a valid session token.
func is_authenticated() -> bool:
	return _access_token != ""


func get_user_id() -> String:
	return _user_id

# ---------------------------------------------------------------------------
# REST (PostgREST) helpers
# ---------------------------------------------------------------------------

## SELECT — returns a Signal that yields Array[Dictionary] or an error dict.
## Example: await SupabaseClient.select("world_tiles", "tile_type,occupied_by", "x=eq.5&y=eq.10")
func select(table: String, columns: String = "*", filters: String = "") -> Signal:
	var path := "/rest/v1/%s?select=%s" % [table, columns]
	if filters != "":
		path += "&" + filters
	return _request("GET", path, "")


## INSERT a row. Pass a Dictionary of column→value pairs.
func insert(table: String, row: Dictionary) -> Signal:
	return _request("POST", "/rest/v1/" + table, JSON.stringify(row))


## UPDATE rows matching filter. filter example: "id=eq.abc-123"
func update(table: String, filter: String, data: Dictionary) -> Signal:
	return _request("PATCH", "/rest/v1/%s?%s" % [table, filter], JSON.stringify(data))


## DELETE rows matching filter.
func delete(table: String, filter: String) -> Signal:
	return _request("DELETE", "/rest/v1/%s?%s" % [table, filter], "")


## Call a Postgres RPC function (stored procedure) via PostgREST.
## params is a Dictionary of named arguments.
## Named call_rpc to avoid conflict with Godot's built-in Node.rpc() multiplayer method.
func call_rpc(function_name: String, params: Dictionary = {}) -> Signal:
	return _request("POST", "/rest/v1/rpc/" + function_name, JSON.stringify(params))


## Call a Supabase Edge Function (Deno).
## endpoint example: "calculate_resources"
func call_function(endpoint: String, body: Dictionary = {}) -> Signal:
	return _request("POST", "/functions/v1/" + endpoint, JSON.stringify(body))

# ---------------------------------------------------------------------------
# Realtime WebSocket (live world-map updates)
# ---------------------------------------------------------------------------

var _ws : WebSocketPeer = null
## Emitted when a realtime postgres_changes event arrives.
## payload contains: { "table", "eventType", "new", "old" }
signal realtime_event(payload: Dictionary)

## Subscribe to INSERT/UPDATE/DELETE changes on a Supabase table.
## Call this after sign-in to start receiving live world-map tile changes.
func realtime_subscribe(table: String, filter: String = "") -> void:
	if _ws != null:
		return  # Already connected; add channel logic here for multiple subs.

	_ws = WebSocketPeer.new()
	var ws_url := SUPABASE_URL.replace("https://", "wss://") + "/realtime/v1/websocket?apikey=" + ANON_KEY
	_ws.connect_to_url(ws_url)


## Must be called every frame (from _process) to poll the WebSocket.
func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			var raw  := _ws.get_packet().get_string_from_utf8()
			var parsed := JSON.parse_string(raw)
			if parsed and parsed.get("type") == "postgres_changes":
				realtime_event.emit(parsed.get("payload", {}))
	elif state == WebSocketPeer.STATE_CLOSED:
		_ws = null

# ---------------------------------------------------------------------------
# Internal — shared HTTP machinery
# ---------------------------------------------------------------------------

# Creates an HTTPRequest node, fires it, and returns a one-shot Signal.
# The node auto-frees itself after the response arrives.
func _request(method_str: String, path: String, body: String) -> Signal:
	var req := HTTPRequest.new()
	add_child(req)
	_pending_requests.append(req)

	var method := HTTPClient.METHOD_GET
	match method_str:
		"POST":   method = HTTPClient.METHOD_POST
		"PATCH":  method = HTTPClient.METHOD_PATCH
		"DELETE": method = HTTPClient.METHOD_DELETE

	var headers := _build_headers()
	var url     := SUPABASE_URL + path

	# We use a lambda to capture req so we can free it after response.
	var result_signal := SignalResponseWrapper.new()
	req.request_completed.connect(
		func(result, code, _headers, body_bytes):
			_pending_requests.erase(req)
			req.queue_free()
			var text     := body_bytes.get_string_from_utf8()
			var parsed   = JSON.parse_string(text)
			if code >= 200 and code < 300:
				result_signal.emit_success(parsed if parsed != null else {})
			else:
				var err_msg := text if text != "" else "HTTP %d" % code
				result_signal.emit_error(err_msg)
	)

	req.request(url, headers, method, body)
	return result_signal.completed


func _build_headers() -> PackedStringArray:
	var h := PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + ANON_KEY,
		"Prefer: return=representation",  # PostgREST: return the affected row(s)
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
		PackedStringArray([
			"Content-Type: application/json",
			"apikey: " + ANON_KEY,
		]),
		HTTPClient.METHOD_POST,
		body
	)


func _on_auth_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	var text   := body.get_string_from_utf8()
	var parsed  = JSON.parse_string(text)
	if parsed == null or code >= 400:
		auth_error.emit(text)
		return

	# Store session tokens — these are passed in Authorization headers going forward.
	_access_token  = parsed.get("access_token",  "")
	_refresh_token = parsed.get("refresh_token", "")
	var user       = parsed.get("user", {})
	_user_id       = user.get("id", "")
	auth_success.emit(parsed)

# ---------------------------------------------------------------------------
# Helper inner class — wraps a one-shot "completed" signal per request
# ---------------------------------------------------------------------------

## Lightweight signal carrier so each _request() call has its own signal.
class SignalResponseWrapper extends RefCounted:
	signal completed(data)   # data is Array/Dictionary on success, or {"error": msg}

	func emit_success(data) -> void:
		completed.emit(data)

	func emit_error(message: String) -> void:
		completed.emit({"error": message})
