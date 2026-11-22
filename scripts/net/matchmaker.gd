class_name Matchmaker
extends Node
## Short room codes. A host picks a 4-character code, the matchmaker checks
## that no other room is using it, starts a room for it, and anyone who types
## the code is sent to that room.
##
## It is a child of the Network autoload on every machine, so its RPCs have the
## same path on the server and on the clients.
##
##   Server (--matchmaker): listens on one port (default 9040). Each room is its
##     own headless copy of the game (`--server --once`) on a port from a range;
##     the room quits by itself when it empties, and the code is free again.
##   Client: connects to the matchmaker, asks to create or join a code, gets a
##     port back, drops that connection and joins the room on that port at the
##     same address.
##
## Where the matchmaker is comes from `--matchmaker-url=` on the command line or
## "server" in assets/config/online.json ("" = not set up: only the old
## same-network hosting and direct addresses work).

signal failed(reason: String, suggestion: String)

const CODE_LENGTH := 4
const ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  # letters and digits, never 0/O/1/I
const CONFIG_PATH := "res://assets/config/online.json"
const DEFAULT_PORT := 9040
const DEFAULT_ROOM_PORT_BASE := 9100
const DEFAULT_MAX_ROOMS := 8
const ROOM_IDLE_SECONDS := 120  # a room nobody ever joins closes after this long
const START_WAIT_TRIES := 40  # x 0.25s for a new room to start listening

# --- client side ---
var active := false  # between asking and being answered
var unreachable := false  # the last ask couldn't even reach the matchmaker
var _op := ""
var _code := ""
var _address := ""
var _port := 0
var _tls := false

# --- server side ---
var rooms: Dictionary = {}  # code -> {"port": int, "pid": int, "ready": bool}
var room_port_base := DEFAULT_ROOM_PORT_BASE
var max_rooms := DEFAULT_MAX_ROOMS
var tls_args: PackedStringArray = []
var _creating: Dictionary = {}  # peer id -> true while their room starts
var _sweep := 0.0


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)


func _exit_tree() -> void:
	for code in rooms:
		if rooms[code]["pid"] > 0:
			OS.kill(rooms[code]["pid"])


# ---------------------------------------------------------------------------
# Codes
# ---------------------------------------------------------------------------

## Upper-cased code if `text` is a valid 4-character room code, else "".
static func normalize(text: String) -> String:
	var clean := text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if clean.length() != CODE_LENGTH:
		return ""
	for c in clean:
		if ALPHABET.find(c) < 0:
			return ""
	return clean


## A random code that isn't in `taken`. Letters and digits, never 0/O/1/I.
static func random_code(taken: Array = []) -> String:
	for attempt in 200:
		var code := ""
		for i in CODE_LENGTH:
			code += ALPHABET[randi() % ALPHABET.length()]
		if code not in taken:
			return code
	return ""


## What the matchmaker can be told about a code that doesn't work.
static func code_rules() -> String:
	return "Use 4 letters or digits (no 0, 1, I or O)."


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

## "host:port" or "wss://host:port" of the matchmaker, "" if there isn't one.
static func configured_url() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--matchmaker-url="):
			return a.trim_prefix("--matchmaker-url=").strip_edges()
	if ResourceLoader.exists(CONFIG_PATH):
		var resource = load(CONFIG_PATH)
		if resource is JSON and resource.data is Dictionary:
			return str(resource.data.get("server", "")).strip_edges()
	return ""


static func is_configured() -> bool:
	return configured_url() != ""


## op is "create" or "join". The answer arrives by joining the room (the
## lobby sees the usual connected_to_server) or by the failed signal.
func request(op: String, raw_code: String) -> Error:
	var code := normalize(raw_code)
	if code == "":
		failed.emit(code_rules(), "")
		return ERR_INVALID_PARAMETER
	var target := Network.parse_join_target(configured_url())
	if target.is_empty():
		failed.emit("The game server address isn't set up.", "")
		return ERR_UNCONFIGURED
	_op = op
	_code = code
	_address = target["address"]
	_port = target["port"]
	_tls = target.get("tls", false)
	unreachable = false
	active = true
	var err := Network.join(_address, _port, _tls)
	if err != OK:
		active = false
		unreachable = true
	return err


func _on_connected() -> void:
	if active:
		ask.rpc_id(1, _op, _code)


func _on_connection_failed() -> void:
	if active:
		active = false
		unreachable = true


@rpc("authority", "call_remote", "reliable")
func answer(ok: bool, port: int, reason: String, code: String, suggestion: String) -> void:
	if not active:
		return
	active = false
	Network.close_connection()
	if not ok:
		failed.emit(reason, suggestion)
		return
	var err := Network.join(_address, port, _tls)
	if err != OK:
		failed.emit("Couldn't connect to the room (error %d)." % err, "")
		return
	Network.room_code = code


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

func boot_server(room_base: int, rooms_max: int, tls: PackedStringArray) -> void:
	room_port_base = room_base
	max_rooms = rooms_max
	tls_args = tls


@rpc("any_peer", "call_remote", "reliable")
func ask(op: String, raw_code: String) -> void:
	if not Network.matchmaker_mode:
		return
	var peer := multiplayer.get_remote_sender_id()
	var code := normalize(raw_code)
	if code == "":
		_reply(peer, false, 0, code_rules(), "", "")
		return
	match op:
		"join":
			if rooms.has(code) and rooms[code]["ready"]:
				_reply(peer, true, rooms[code]["port"], "", code, "")
			else:
				_reply(peer, false, 0, "No room has the code %s. Check it with the host." % code, "", "")
		"create":
			await _create(peer, code)
		_:
			_reply(peer, false, 0, "Unknown request.", "", "")


func _create(peer: int, code: String) -> void:
	if _creating.has(peer):
		return
	if rooms.has(code):
		_log("%s asked for %s: taken" % [peer, code])
		_reply(peer, false, 0, "The code %s is already in use. Try another one." % code, "", random_code(rooms.keys()))
		return
	if rooms.size() >= max_rooms:
		_reply(peer, false, 0, "The server is full of games right now. Try again in a few minutes.", "", "")
		return
	var port := _free_port()
	if port == 0:
		_reply(peer, false, 0, "The server has no free room slots.", "", "")
		return
	_creating[peer] = true
	rooms[code] = {"port": port, "pid": -1, "ready": false}  # reserved while the room starts
	var pid := OS.create_process(OS.get_executable_path(), _room_args(port))
	if pid <= 0:
		rooms.erase(code)
		_creating.erase(peer)
		_reply(peer, false, 0, "The server couldn't start a room.", "", "")
		return
	rooms[code]["pid"] = pid
	var up := await _wait_listening(port, pid)
	_creating.erase(peer)
	if not up:
		if OS.is_process_running(pid):
			OS.kill(pid)
		rooms.erase(code)
		_log("room %s failed to start on port %d" % [code, port])
		_reply(peer, false, 0, "The room didn't start. Try again.", "", "")
		return
	rooms[code]["ready"] = true
	_log("room %s open on port %d (%d rooms)" % [code, port, rooms.size()])
	_reply(peer, true, port, "", code, "")


func _reply(peer: int, ok: bool, port: int, reason: String, code: String, suggestion: String) -> void:
	if peer in multiplayer.get_peers():
		answer.rpc_id(peer, ok, port, reason, code, suggestion)


func _free_port() -> int:
	var used := []
	for code in rooms:
		used.append(rooms[code]["port"])
	for i in max_rooms:
		var port := room_port_base + i
		if port not in used:
			return port
	return 0


func _room_args(port: int) -> PackedStringArray:
	var args := PackedStringArray(["--headless"])
	if not OS.has_feature("template"):  # running from the editor's project folder
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--server", "--once", "--port=%d" % port, "--idle-timeout=%d" % ROOM_IDLE_SECONDS])
	args.append_array(tls_args)
	return args


## True once something is accepting connections on the room's port.
func _wait_listening(port: int, pid: int) -> bool:
	for i in START_WAIT_TRIES:
		if not OS.is_process_running(pid):
			return false
		var probe := StreamPeerTCP.new()
		if probe.connect_to_host("127.0.0.1", port) == OK:
			for j in 5:
				await get_tree().create_timer(0.05).timeout
				probe.poll()
				if probe.get_status() != StreamPeerTCP.STATUS_CONNECTING:
					break
			var ready := probe.get_status() == StreamPeerTCP.STATUS_CONNECTED
			probe.disconnect_from_host()
			if ready:
				return true
		await get_tree().create_timer(0.2).timeout
	return false


func _process(delta: float) -> void:
	if not Network.matchmaker_mode:
		return
	_sweep -= delta
	if _sweep > 0.0:
		return
	_sweep = 1.0
	for code in rooms.keys():
		var pid: int = rooms[code]["pid"]
		if rooms[code]["ready"] and not OS.is_process_running(pid):
			rooms.erase(code)
			_log("room %s closed (%d rooms)" % [code, rooms.size()])


func forget_peer(peer: int) -> void:
	_creating.erase(peer)


func _log(msg: String) -> void:
	print("[matchmaker] ", msg)
