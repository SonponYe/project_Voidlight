extends Node
## Authoritative WebSocket client-server multiplayer entry point. Registered
## as the "Network" autoload.
##
## Godot's native multiplayer peer (ENet, raw UDP) does not work in a
## browser at all, so this project uses WebSocketMultiplayerPeer for every
## build target — including native/desktop test runs — so there's exactly
## one networking code path to maintain, not a browser one and a "real"
## one that quietly drifts apart.
##
## One process is the authoritative server (always peer id 1, by Godot's
## own multiplayer convention); every other process is a client connecting
## to it. This autoload owns the connection, the roster of who's connected
## (with names), the player cap, and the scene-level match handshakes
## (start match / arena ready / return to lobby). Those RPCs live HERE and
## not on the lobby or arena because this is the one node that exists at
## the same path (/root/Network) on every peer regardless of which scene
## is currently loaded — an RPC aimed at a node the other side hasn't
## loaded yet is silently dropped.

signal player_list_changed
signal connection_failed
signal disconnected_from_server
## Server turned us away (match full / already running). Fires right before
## disconnected_from_server so the lobby can show the reason.
signal rejected(reason: String)
signal peer_arena_ready(id: int)

const DEFAULT_PORT := 9050
const MAX_PLAYERS := 5
const MAX_NAME_LENGTH := 16
const LOBBY_SCENE := "res://scenes/ui/net_lobby.tscn"
const ARENA_SCENE := "res://scenes/net/net_arena.tscn"
## What a dedicated server sits on between matches: nothing to render.
const IDLE_SCENE := "res://scenes/net/server_idle.tscn"

## peer_id -> { "name": String, "gen": String, "team": int }. Server is
## the source of truth; clients receive a full copy via _sync_players
## whenever it changes. team is 0 in FFA, 1 or 2 in team mode.
var players: Dictionary = {}
var local_name := "Player"
var local_gen := Gens.DEFAULT
## "ffa" or "team" — host-controlled, synced with the roster.
var match_mode := "ffa"
var match_in_progress := false
var last_reject_reason := ""
## True when this process is a headless server with no player of its own
## (--server on the command line, or a Godot dedicated-server export).
var dedicated := false
var _join_seq := 0
## Dev only: a self-signed server certificate this client should accept
## (--tls-trust=<file>). Real certificates (Let's Encrypt etc.) need nothing.
var tls_trust_path := ""

## Server-only: peers whose arena scene is loaded and ready to receive
## spawns. Cleared at every match start.
var ready_peers: Dictionary = {}

const HEARTBEAT_INTERVAL := 0.5

## Smoothed round-trip time to the host in ms (clients only; 0 until the
## first reply). Used to size the owner's prediction-correction threshold.
var rtt_ms := 0.0
## Switchable so a test can simulate a client going quiet.
var heartbeat_enabled := true
var _heartbeat_timer := 0.0
var _leaving := false

## Host only. A client silent for this long is "lagging" (dimmed, not dropped).
const LAG_SECONDS := 3.0
## Host only: peers who pressed Leave (as opposed to crashing/dropping), so
## the arena can remove them at once instead of keeping a dimmed avatar.
var left_cleanly: Dictionary = {}
var _last_heard: Dictionary = {}

## A WebSocketMultiplayerPeer is RefCounted — holding it here too (not just
## in multiplayer.multiplayer_peer) guards against it being freed out from
## under the connection by anything that doesn't realize the engine-side
## reference should count, which looks exactly like an immediate spurious
## server_disconnected right after connecting.
var _peer: MultiplayerPeer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--tls-trust="):
			tls_trust_path = a.trim_prefix("--tls-trust=")
	if OS.has_feature("dedicated_server") or "--server" in args:
		dedicated = true
		_boot_dedicated.call_deferred(args)


func _boot_dedicated(args: PackedStringArray) -> void:
	var port := DEFAULT_PORT
	var cert_path := ""
	var key_path := ""
	for a in args:
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
		elif a.begins_with("--tls-cert="):
			cert_path = a.trim_prefix("--tls-cert=")
		elif a.begins_with("--tls-key="):
			key_path = a.trim_prefix("--tls-key=")
	var tls: TLSOptions = null
	if cert_path != "" or key_path != "":
		var cert := X509Certificate.new()
		var key := CryptoKey.new()
		if cert_path == "" or key_path == "" or cert.load(cert_path) != OK or key.load(key_path) != OK:
			push_error("TLS needs both --tls-cert and --tls-key, and both must be readable PEM files")
			get_tree().quit(1)
			return
		tls = TLSOptions.server(key, cert)
	var err := host(port, tls)
	if err != OK:
		push_error("Dedicated server could not listen on port %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	_server_log("dedicated server listening on port %d (max %d players, %s)" % [
		port, MAX_PLAYERS, "wss:// TLS" if tls else "plain ws://"])
	get_tree().change_scene_to_file(IDLE_SCENE)


func _server_log(msg: String) -> void:
	if dedicated:
		print("[server] ", msg)


func _process(delta: float) -> void:
	if not heartbeat_enabled or not has_peer() or multiplayer.is_server():
		return
	if not is_connected_to_match():
		return
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = HEARTBEAT_INTERVAL
		_ping.rpc_id(1, Time.get_ticks_msec())


@rpc("any_peer", "call_remote", "unreliable")
func _ping(sent_msec: int) -> void:
	if is_host():
		var id := multiplayer.get_remote_sender_id()
		_last_heard[id] = Time.get_ticks_msec()
		_pong.rpc_id(id, sent_msec)


## Host only. 0 = fine, 1 = hasn't been heard from lately. The host itself
## is never laggy.
func link_state(id: int) -> int:
	if id == 1 or not _last_heard.has(id):
		return 0
	return 1 if Time.get_ticks_msec() - _last_heard[id] > int(LAG_SECONDS * 1000.0) else 0


## Resets everyone's "last heard" clock — scene loads stall heartbeats, and a
## fresh match shouldn't start with people already marked as lagging.
func mark_all_heard() -> void:
	var now := Time.get_ticks_msec()
	for id in players:
		_last_heard[id] = now


@rpc("any_peer", "call_remote", "reliable")
func _bye() -> void:
	if is_host():
		left_cleanly[multiplayer.get_remote_sender_id()] = true


@rpc("authority", "call_remote", "unreliable")
func _pong(sent_msec: int) -> void:
	var sample := float(Time.get_ticks_msec() - sent_msec)
	rtt_ms = sample if rtt_ms == 0.0 else lerpf(rtt_ms, sample, 0.3)


## Godot's default peer is an OfflineMultiplayerPeer that reports itself as a
## *connected server with id 1*, so has_multiplayer_peer() is true — and
## is_server() too — before anything has been hosted or joined. Everything
## here asks this instead.
func has_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


## Back to the offline default (what "no connection" looks like).
func _drop_peer() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null


func is_host() -> bool:
	return has_peer() and multiplayer.is_server()


## The room leader controls Start, the mode, and Return to Lobby: whoever has
## been in the room longest. On a hosted game that's the host; on a dedicated
## server (which has no roster entry) it's whoever joined first, and the role
## passes on by itself when they leave. Join order is tracked explicitly —
## Godot hands out random peer ids, so a lower id says nothing about who
## arrived first.
func leader_id() -> int:
	var best := 0
	var best_order := 1 << 30
	for id in players:
		var order: int = players[id].get("order", 1 << 29)
		if order < best_order:
			best_order = order
			best = id
	return best


func is_leader() -> bool:
	return has_peer() and multiplayer.get_unique_id() == leader_id()


## Whether a match could start right now. The host re-checks this itself, so
## it can't be bypassed by a client asking.
func can_start() -> bool:
	if match_in_progress or players.size() < 2:
		return false
	if is_team_mode():
		var counts := _team_sizes()
		return counts[1] > 0 and counts[2] > 0 and absi(counts[1] - counts[2]) <= 1
	return true


func is_connected_to_match() -> bool:
	return not _leaving and has_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func set_local_name(raw: String) -> void:
	var cleaned := raw.strip_edges().substr(0, MAX_NAME_LENGTH)
	local_name = cleaned if cleaned != "" else "Player"


# ---------------------------------------------------------------------------
# Room codes
# ---------------------------------------------------------------------------
# A room code is the host's address in a short, typeable form (8 characters
# for an address on the default port, 11 if the port is custom). It is an
# ENCODING, not a lookup — there's no matchmaking server behind it yet, so
# it's only as reachable as the address inside it (LAN today).

const CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  # no 0/O/1/I


## Codes carry a check value so a mistyped code is rejected instead of
## quietly pointing at some other machine: 8 characters (address + 8-bit
## check) on the default port, 11 (address + port + 7-bit check) otherwise.
static func _code_check(data: int, byte_count: int) -> int:
	var crc := 0
	for i in byte_count:
		crc = (crc * 31 + ((data >> (8 * i)) & 0xFF) + 1) & 0xFF
	return crc


static func encode_room_code(ip: String, port: int = DEFAULT_PORT) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var value := 0
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return ""
		value = (value << 8) | int(p)
	var custom_port := port != DEFAULT_PORT
	if custom_port:
		if port < 1 or port > 65535:
			return ""
		value = (value << 16) | port
	var byte_count := 6 if custom_port else 4
	var check_bits := 7 if custom_port else 8
	var length := 11 if custom_port else 8
	value = (value << check_bits) | (_code_check(value, byte_count) & ((1 << check_bits) - 1))
	var out := ""
	for i in length:
		out = CODE_ALPHABET[value & 31] + out
		value >>= 5
	return out


static func format_room_code(code: String) -> String:
	if code.length() <= 4:
		return code
	if code.length() <= 8:
		return "%s-%s" % [code.substr(0, 4), code.substr(4)]
	return "%s-%s-%s" % [code.substr(0, 4), code.substr(4, 4), code.substr(8)]


## {"address": String, "port": int}, or {} if it isn't a valid code (wrong
## length, a character outside the alphabet, or a failed check value).
static func decode_room_code(text: String) -> Dictionary:
	var clean := text.to_upper().replace("-", "").replace(" ", "")
	if clean.length() != 8 and clean.length() != 11:
		return {}
	var value := 0
	for c in clean:
		var idx := CODE_ALPHABET.find(c)
		if idx < 0:
			return {}
		value = (value << 5) | idx
	var custom_port := clean.length() == 11
	var check_bits := 7 if custom_port else 8
	var check := value & ((1 << check_bits) - 1)
	var data := value >> check_bits
	if (_code_check(data, 6 if custom_port else 4) & ((1 << check_bits) - 1)) != check:
		return {}
	var port := DEFAULT_PORT
	if custom_port:
		port = data & 0xFFFF
		data >>= 16
		if port < 1:
			return {}
	var address := "%d.%d.%d.%d" % [(data >> 24) & 255, (data >> 16) & 255, (data >> 8) & 255, data & 255]
	return {"address": address, "port": port}


## What a player typed into the join box → {"address", "port", "tls"} or {}.
## Accepts "192.168.1.5", "192.168.1.5:9051", a hostname with a dot, a
## "ws://" or "wss://" address (wss defaults to port 443), or a room code.
## Port 443 implies TLS.
static func parse_join_target(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t == "":
		return {}
	var tls := false
	var default_port := DEFAULT_PORT
	var lower := t.to_lower()
	if lower.begins_with("wss://"):
		tls = true
		default_port = 443
		t = t.substr(6)
	elif lower.begins_with("ws://"):
		t = t.substr(5)
	t = t.trim_suffix("/")
	if tls or t.contains(".") or t.contains(":") or t.to_lower() == "localhost":
		var host := t
		var port := default_port
		if t.contains(":"):
			var bits := t.rsplit(":", true, 1)
			host = bits[0]
			if not bits[1].is_valid_int() or int(bits[1]) < 1 or int(bits[1]) > 65535:
				return {}
			port = int(bits[1])
		if host == "":
			return {}
		return {
			"address": "127.0.0.1" if host.to_lower() == "localhost" else host,
			"port": port,
			"tls": tls or port == 443,
		}
	return decode_room_code(t)


func player_name(id: int) -> String:
	if players.has(id):
		return players[id]["name"]
	return "Player %d" % id


func player_gen(id: int) -> String:
	if players.has(id):
		return players[id].get("gen", Gens.DEFAULT)
	return Gens.DEFAULT


func player_team(id: int) -> int:
	if players.has(id):
		return players[id].get("team", 0)
	return 0


func is_team_mode() -> bool:
	return match_mode == "team"


static func team_name(team: int) -> String:
	return "Team A" if team == 1 else "Team B"


## Pick your Gen for the next match. Ignored once a match is running.
func select_gen(key: String) -> void:
	if not Gens.is_valid(key) or match_in_progress:
		return
	local_gen = key
	if is_host():
		if players.has(1):
			players[1]["gen"] = key
			_broadcast_players()
	elif is_connected_to_match():
		_select_gen.rpc_id(1, key)


## Leader only: deal everyone onto new random sides (team mode, before the match).
func shuffle_teams() -> void:
	if not is_team_mode() or match_in_progress:
		return
	if is_host():
		_deal_teams()
		_broadcast_players()
	elif is_leader():
		_shuffle_teams.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _shuffle_teams() -> void:
	if is_host() and multiplayer.get_remote_sender_id() == leader_id() \
			and is_team_mode() and not match_in_progress:
		_deal_teams()
		_broadcast_players()


## Leader only (the host re-checks). Switching to team mode deals everyone
## onto random, balanced sides; switching back clears teams.
func set_match_mode(mode: String) -> void:
	if mode not in ["ffa", "team"] or match_in_progress:
		return
	if is_host():
		_apply_mode(mode)
	elif is_leader():
		_set_mode.rpc_id(1, mode)


@rpc("any_peer", "call_remote", "reliable")
func _set_mode(mode: String) -> void:
	if is_host() and multiplayer.get_remote_sender_id() == leader_id() \
			and not match_in_progress and mode in ["ffa", "team"]:
		_apply_mode(mode)


func _apply_mode(mode: String) -> void:
	match_mode = mode
	if mode == "team":
		_deal_teams()
	else:
		for id in players:
			players[id]["team"] = 0
	_broadcast_players()


## Host only: everyone onto a random side, sizes differing by at most one
## (4 -> 2/2, 5 -> 3/2 with a random side getting the extra player).
func _deal_teams() -> void:
	var ids := players.keys()
	ids.shuffle()
	var first := 1 if randi() % 2 == 0 else 2
	for i in ids.size():
		players[ids[i]]["team"] = first if i % 2 == 0 else 3 - first


## Host only: nudge sides back to within one player of each other, e.g. after
## someone leaves. Moves random players off the bigger side.
func _rebalance_teams() -> void:
	if not is_team_mode():
		return
	while true:
		var sizes := _team_sizes()
		if absi(sizes[1] - sizes[2]) <= 1:
			return
		var bigger := 1 if sizes[1] > sizes[2] else 2
		var pool := []
		for id in players:
			if players[id].get("team", 0) == bigger:
				pool.append(id)
		players[pool.pick_random()]["team"] = 3 - bigger


func _team_sizes() -> Dictionary:
	var counts := {1: 0, 2: 0}
	for id in players:
		var t: int = players[id].get("team", 0)
		if counts.has(t):
			counts[t] += 1
	return counts


## Host only: the side with fewer players, for late joiners (random on a tie).
func _smaller_team() -> int:
	var counts := _team_sizes()
	if counts[1] == counts[2]:
		return 1 if randi() % 2 == 0 else 2
	return 1 if counts[1] < counts[2] else 2


## Starts listening for WebSocket connections on `port`. The host process
## itself becomes peer id 1 and does NOT need a separate join() call.
func host(port: int = DEFAULT_PORT, tls: TLSOptions = null) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port, "*", tls)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	match_in_progress = false
	last_reject_reason = ""
	match_mode = "ffa"
	_join_seq = 0
	players = {} if dedicated else {1: {"name": local_name, "gen": local_gen, "team": 0, "order": 0}}
	player_list_changed.emit()
	return OK


## Connects to a running host at ws://address:port. Success/failure arrive
## later via connected_to_server/connection_failed, not this call's return
## value — WebSocket handshakes aren't instant.
func join(address: String, port: int = DEFAULT_PORT, tls: bool = false) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	# A browser page served over https is not allowed to open a plain ws://
	# connection, so there the secure form is forced.
	var use_tls := tls or _page_is_https()
	var url := "%s://%s:%d" % ["wss" if use_tls else "ws", address, port]
	var options: TLSOptions = null
	if use_tls and not OS.has_feature("web"):  # browsers do their own TLS
		options = _client_tls_options()
	var err := peer.create_client(url, options)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	match_in_progress = false
	last_reject_reason = ""
	rtt_ms = 0.0
	return OK


static func _page_is_https() -> bool:
	return OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.protocol")) == "https:"


func _client_tls_options() -> TLSOptions:
	if tls_trust_path != "":
		var cert := X509Certificate.new()
		if cert.load(tls_trust_path) == OK:
			return TLSOptions.client_unsafe(cert)
		push_warning("--tls-trust file could not be read: %s" % tls_trust_path)
	return TLSOptions.client()


func leave() -> void:
	var current := multiplayer.multiplayer_peer
	# Say goodbye first so the host can tell leaving from crashing. The
	# short wait lets the message out before the socket closes; meanwhile
	# we already count as disconnected so the UI doesn't show a live room.
	if has_peer() and not multiplayer.is_server() and match_in_progress and is_connected_to_match():
		_leaving = true
		_bye.rpc_id(1)
		await get_tree().create_timer(0.15).timeout
		_leaving = false
		if multiplayer.multiplayer_peer != current:
			return  # a new connection was started meanwhile; leave it alone
	if has_peer():
		multiplayer.multiplayer_peer.close()
	_drop_peer()
	players.clear()
	ready_peers.clear()
	match_in_progress = false
	player_list_changed.emit()


# ---------------------------------------------------------------------------
# Match flow (host-driven)
# ---------------------------------------------------------------------------

## Leader only. Asks for the room to move into the arena; the host decides.
func start_match() -> void:
	if is_host():
		_do_start()
	elif is_leader():
		_request_start.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_start() -> void:
	if is_host() and multiplayer.get_remote_sender_id() == leader_id():
		_do_start()


func _do_start() -> void:
	if not can_start():
		return
	_server_log("match starting with %d players (%s)" % [players.size(), match_mode])
	match_in_progress = true
	ready_peers.clear()
	left_cleanly.clear()
	mark_all_heard()
	_load_scene.rpc(ARENA_SCENE)
	_load_scene(ARENA_SCENE)


## Brings every peer back to the lobby, connection intact. Only the host can
## do it; the leader asks via ask_return() and the arena runs its cleanup first.
func return_to_lobby() -> void:
	if not is_host():
		return
	match_in_progress = false
	ready_peers.clear()
	_load_scene.rpc(LOBBY_SCENE)
	if dedicated:
		get_tree().change_scene_to_file(IDLE_SCENE)
	else:
		_load_scene(LOBBY_SCENE)
	_server_log("match over, room back in the lobby")


func ask_return() -> void:
	if is_leader() and not is_host():
		_request_return.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_return() -> void:
	if not is_host() or not match_in_progress or multiplayer.get_remote_sender_id() != leader_id():
		return
	var arena := get_tree().current_scene
	if arena and arena.has_method("_on_return_pressed"):
		arena._on_return_pressed()


## Clients call this from the arena's _ready() once their MultiplayerSpawner
## exists, so the server knows it's safe to send them spawns. A spawn sent
## to a peer whose arena isn't loaded yet is lost, not queued.
func report_arena_ready() -> void:
	if is_host():
		return
	_arena_ready.rpc_id(1)


@rpc("authority", "call_remote", "reliable")
func _load_scene(path: String) -> void:
	match_in_progress = path == ARENA_SCENE
	get_tree().change_scene_to_file(path)


@rpc("any_peer", "call_remote", "reliable")
func _arena_ready() -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	ready_peers[id] = true
	peer_arena_ready.emit(id)


# ---------------------------------------------------------------------------
# Roster
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _register(raw_name: String, gen: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	_last_heard[id] = Time.get_ticks_msec()
	var cleaned := raw_name.strip_edges().substr(0, MAX_NAME_LENGTH)
	_join_seq += 1
	players[id] = {
		"order": _join_seq,
		"name": cleaned if cleaned != "" else "Player %d" % id,
		"gen": gen if Gens.is_valid(gen) else Gens.DEFAULT,
		"team": _smaller_team() if is_team_mode() else 0,
	}
	_broadcast_players()


@rpc("any_peer", "call_remote", "reliable")
func _select_gen(key: String) -> void:
	if not is_host() or match_in_progress or not Gens.is_valid(key):
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["gen"] = key
		_broadcast_players()


@rpc("authority", "call_remote", "reliable")
func _sync_players(roster: Dictionary, mode: String) -> void:
	players = roster
	match_mode = mode
	player_list_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	last_reject_reason = reason
	rejected.emit(reason)


func _broadcast_players() -> void:
	_sync_players.rpc(players, match_mode)
	player_list_changed.emit()


func _reject_peer(id: int, reason: String) -> void:
	_rejected.rpc_id(id, reason)
	# Give the rejection RPC a moment to actually go out before closing the
	# socket — disconnecting in the same frame can drop it unsent.
	await get_tree().create_timer(0.3).timeout
	if has_peer() and id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	_server_log("peer %d connected" % id)
	if match_in_progress:
		_reject_peer(id, "Match already in progress")
		return
	if players.size() >= MAX_PLAYERS:
		_reject_peer(id, "Match is full (%d players)" % MAX_PLAYERS)
		return
	# Roster entry is created when the client sends _register with its name.


func _on_peer_disconnected(id: int) -> void:
	if is_host():
		players.erase(id)
		ready_peers.erase(id)
		_last_heard.erase(id)
		if not match_in_progress:
			_rebalance_teams()
		_broadcast_players()
		_server_log("player %d left (%d in room)" % [id, players.size()])
		# A dedicated server with nobody left resets itself for the next room.
		if dedicated and players.is_empty():
			_reset_empty_server.call_deferred()


## Deferred so every other disconnect handler (the arena's, notably) finishes
## before the scene underneath them is swapped out.
func _reset_empty_server() -> void:
	if not players.is_empty():
		return
	match_in_progress = false
	match_mode = "ffa"
	ready_peers.clear()
	get_tree().change_scene_to_file(IDLE_SCENE)
	_server_log("room empty, reset")


func _on_connected_to_server() -> void:
	_register.rpc_id(1, local_name, local_gen)


func _on_connection_failed() -> void:
	_drop_peer()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	_drop_peer()
	players.clear()
	match_in_progress = false
	disconnected_from_server.emit()
