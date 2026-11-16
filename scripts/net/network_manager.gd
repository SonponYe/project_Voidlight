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
## to it. See net_arena.gd/net_player.gd for what actually happens once a
## connection succeeds — this autoload only owns the connection itself and
## the roster of who's connected.

signal player_list_changed
signal connection_failed
signal disconnected_from_server

const DEFAULT_PORT := 9050

## peer_id -> { "name": String }. Server keeps every peer's entry; a client
## only ever has its own entry (it doesn't need to know peer-list detail
## beyond what net_arena.gd's spawner already tells it via spawned nodes).
var players: Dictionary = {}

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


## Starts listening for WebSocket connections on `port`. The host process
## itself becomes peer id 1 and does NOT need a separate join() call.
func host(port: int = DEFAULT_PORT) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	players[1] = {"name": "Host"}
	player_list_changed.emit()
	return OK


## Connects to a running host at ws://address:port. Success/failure arrive
## later via connected_to_server/connection_failed, not this call's return
## value — WebSocket handshakes aren't instant.
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [address, port]
	var err := peer.create_client(url)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_peer = null
	players.clear()


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		players[id] = {"name": "Player %d" % id}
		player_list_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_list_changed.emit()


func _on_connected_to_server() -> void:
	players[multiplayer.get_unique_id()] = {"name": "You"}
	player_list_changed.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	_peer = null
	players.clear()
	disconnected_from_server.emit()
