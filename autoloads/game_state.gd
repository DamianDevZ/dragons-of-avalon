## GameState — Autoload Singleton
##
## Local cache of the current player's data. Populated after sign-in from
## the database and kept in sync as the player acts. This is a convenience
## layer — the database is always the source of truth. Never trust GameState
## values for server-side calculations; they are display-only.

extends Node

# ---------------------------------------------------------------------------
# Signals — UI nodes connect to these to redraw reactively
# ---------------------------------------------------------------------------

## Emitted after player profile is loaded or any field changes.
signal player_loaded(player: PlayerData)
## Emitted whenever displayed resource amounts change (from server refresh).
signal resources_updated(resources: ResourceSnapshot)
## Emitted when a march departs or arrives.
signal march_updated

# ---------------------------------------------------------------------------
# Player profile (loaded once at login)
# ---------------------------------------------------------------------------

class PlayerData extends RefCounted:
	var id            : String
	var display_name  : String
	## Castle level controls the expansion cap (max tiles on world map).
	var castle_level  : int = 1
	## How many world-map tiles this player can currently occupy.
	var expansion_cap : int = 5

var player : PlayerData = null

# ---------------------------------------------------------------------------
# Resources — a snapshot as of last_calculated_at
# ---------------------------------------------------------------------------

class ResourceSnapshot extends RefCounted:
	## Raw values returned by the calculate_resources Edge Function.
	var wood  : float = 0.0
	var food  : float = 0.0
	var stone : float = 0.0
	var gold  : float = 0.0
	## ISO-8601 timestamp string from the server. Used to extrapolate
	## displayed values client-side between refreshes.
	var last_calculated_at : String = ""

var resources : ResourceSnapshot = ResourceSnapshot.new()

# ---------------------------------------------------------------------------
# Active marches (armies currently moving on the world map)
# ---------------------------------------------------------------------------

## Array of Dictionary, each matching the `marches` DB table columns.
var active_marches : Array[Dictionary] = []

# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Listen for auth so we can auto-load the player profile.
	SupabaseClient.auth_success.connect(_on_auth_success)


func _on_auth_success(_session: Dictionary) -> void:
	await load_player_profile()
	await refresh_resources()


## Fetch the player's profile row from the `players` table.
func load_player_profile() -> void:
	var uid    := SupabaseClient.get_user_id()
	var result = await SupabaseClient.select(
		"players",
		"id,display_name,castle_level,expansion_cap",
		"id=eq." + uid
	)

	if result is Dictionary and result.has("error"):
		push_error("[GameState] Could not load player profile: " + result["error"])
		return

	if result is Array and result.size() > 0:
		var row        := result[0] as Dictionary
		player          = PlayerData.new()
		player.id       = row.get("id",            "")
		player.display_name   = row.get("display_name",  "")
		player.castle_level   = row.get("castle_level",  1)
		player.expansion_cap  = row.get("expansion_cap", 5)
		player_loaded.emit(player)


## Call the server-side Edge Function to get accurate resource totals.
## Uses delta-time on the server so we never trust the client clock for
## resource math.
func refresh_resources() -> void:
	var result = await SupabaseClient.call_function("calculate_resources")

	if result is Dictionary and result.has("error"):
		push_error("[GameState] Resource refresh failed: " + result["error"])
		return

	if result is Dictionary:
		resources.wood               = result.get("wood",  0.0)
		resources.food               = result.get("food",  0.0)
		resources.stone              = result.get("stone", 0.0)
		resources.gold               = result.get("gold",  0.0)
		resources.last_calculated_at = result.get("last_calculated_at", "")
		resources_updated.emit(resources)


## Returns the extrapolated current amount of a resource without hitting
## the server. Useful for smooth UI updates between refreshes.
## production_per_sec should come from a locally cached buildings list.
func get_live_resource(base_amount: float, production_per_sec: float) -> float:
	# Parse the ISO-8601 timestamp and compute elapsed seconds locally.
	# This is display-only; the server recalculates on any spend action.
	if resources.last_calculated_at == "":
		return base_amount
	var t := Time.get_unix_time_from_datetime_string(resources.last_calculated_at)
	var elapsed := Time.get_unix_time_from_system() - t
	return base_amount + (production_per_sec * elapsed)
