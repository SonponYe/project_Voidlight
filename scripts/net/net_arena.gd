extends Node2D
## The online match arena. Server-authoritative: the host spawns every
## player, tracks eliminations, decides the winner, runs the arena-wide Gen
## effects (Blackout, bombs), and tells everyone. Clients report "my arena
## is loaded" and then render what the server replicates.
##
## Entered via Network.start_match() from the lobby, so the connection and
## roster already exist by the time _ready() runs here.

const NET_PLAYER_SCENE := "res://scenes/net/net_player.tscn"
const NET_BOMB_SCENE := "res://scenes/net/net_bomb.tscn"

## How long the host waits for every client to load the arena before
## starting without the stragglers. A spawn sent to a peer whose arena
## isn't loaded is lost, not queued, so late peers can only spectate.
const READY_TIMEOUT_SEC := 8.0

const BOMB_TRIGGER_RADIUS := 48.0
const BOMB_BLAST_RADIUS := 90.0
const BOMB_DAMAGE := 3
const EXPLOSION_LIFETIME := 0.35
const EXPLOSION_COLOR := Color(1.0, 0.6, 0.2, 0.8)

## Under Blackout, anyone who isn't the caster only sees this far, in any
## direction — no cone. The caster keeps the normal rule.
const BLACKOUT_VISION_RADIUS := 70.0
const BLACKOUT_COLOR := Color(0.06, 0.06, 0.08)

@onready var players_root: Node2D = $Players
@onready var bombs_root: Node2D = $Bombs
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var bomb_spawner: MultiplayerSpawner = $BombSpawner
@onready var hud: CanvasLayer = $NetHUD
@onready var camera: Camera2D = $Camera
@onready var world_modulate: CanvasModulate = $CanvasModulate

## Floor-cell centers of the Maze layout: the four corners, then the middle.
var _spawn_points := [
	Vector2(96, 96), Vector2(1440, 96), Vector2(96, 928), Vector2(1440, 928), Vector2(800, 480),
]
## Team mode: A spawns down the left edge, B down the right.
var _team_spawn_points := {
	1: [Vector2(96, 96), Vector2(96, 928), Vector2(96, 480)],
	2: [Vector2(1440, 96), Vector2(1440, 928), Vector2(1440, 480)],
}
var _match_started := false
var _match_over := false
## A match that started with a single player is a sandbox, never "won".
var _is_contest := false
var _participants: Array[int] = []
var _bomb_seq := 0

## Peer id of the active Blackout caster, 0 when the lights are on.
## Broadcast by the server via _set_blackout.
var blackout_by := 0


func _ready() -> void:
	spawner.spawn_path = players_root.get_path()
	spawner.spawn_function = _spawn_player
	bomb_spawner.spawn_path = bombs_root.get_path()
	bomb_spawner.spawn_function = _spawn_bomb
	hud.return_pressed.connect(_on_return_pressed)
	hud.leave_pressed.connect(_on_leave_pressed)
	Network.disconnected_from_server.connect(_on_lost_server)

	if Network.is_host():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		hud.set_status("Waiting for players to load...")
		_await_ready_peers()
	else:
		hud.set_status("Loading...")
		Network.report_arena_ready()


func _exit_tree() -> void:
	if Network.disconnected_from_server.is_connected(_on_lost_server):
		Network.disconnected_from_server.disconnect(_on_lost_server)


func _process(_delta: float) -> void:
	var me := _local_player()
	_update_vision(me)
	_update_blackout_visuals(me)
	if me:
		camera.global_position = me.global_position
	_update_hud(me)


func _physics_process(_delta: float) -> void:
	if Network.is_host():
		_server_check_bombs()


# ---------------------------------------------------------------------------
# Match start (host)
# ---------------------------------------------------------------------------

func _await_ready_peers() -> void:
	var deadline := Time.get_ticks_msec() + int(READY_TIMEOUT_SEC * 1000.0)
	while not _all_clients_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_begin_match()


func _all_clients_ready() -> bool:
	for id in Network.players:
		if id != 1 and not Network.ready_peers.has(id):
			return false
	return true


func _begin_match() -> void:
	if _match_started:
		return
	_match_started = true
	_spawn_for_peer(1)
	for id in Network.players:
		if id != 1 and Network.ready_peers.has(id):
			_spawn_for_peer(id)
	_is_contest = _participants.size() >= 2
	_set_status.rpc("Fight!")
	_check_win()


func _spawn_for_peer(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var team := Network.player_team(id) if Network.is_team_mode() else 0
	var pos: Vector2
	if team != 0:
		var slots: Array = _team_spawn_points[team]
		pos = slots[_team_count(team) % slots.size()]
	else:
		pos = _spawn_points[_participants.size() % _spawn_points.size()]
	var data := {"id": id, "pos": pos, "gen": Network.player_gen(id), "team": team}
	var node := spawner.spawn(data) as NetPlayer
	node.died.connect(_on_player_died)
	_participants.append(id)


func _team_count(team: int) -> int:
	var n := 0
	for id in _participants:
		if Network.player_team(id) == team:
			n += 1
	return n


## Runs on every peer with the same data, so the spawn position, Gen and
## team travel with it rather than being derived from server-only state.
func _spawn_player(data: Dictionary) -> Node:
	var scene: PackedScene = load(NET_PLAYER_SCENE)
	var player := scene.instantiate() as NetPlayer
	player.name = str(data["id"])
	player.owner_peer_id = data["id"]
	player.gen = data["gen"]
	player.team = data["team"]
	player.position = data["pos"]
	player.configure_replication()
	return player


# ---------------------------------------------------------------------------
# Eliminations / win (host)
# ---------------------------------------------------------------------------

func _on_player_died(id: int) -> void:
	_announce.rpc("%s was eliminated" % Network.player_name(id))
	_check_win()


func _on_peer_disconnected(id: int) -> void:
	var node := players_root.get_node_or_null(str(id)) as NetPlayer
	if node:
		if node.gen == "blackout" and blackout_by == id:
			end_blackout(id)
		node.queue_free()
	if _match_started:
		_announce.rpc("%s left the match" % Network.player_name(id))
	_participants.erase(id)
	_check_win()


func _alive_ids() -> Array[int]:
	var alive: Array[int] = []
	for id in _participants:
		var node := players_root.get_node_or_null(str(id)) as NetPlayer
		if node and not node.dead and not node.is_queued_for_deletion():
			alive.append(id)
	return alive


func _check_win() -> void:
	if not _match_started or _match_over or not _is_contest:
		return
	var alive := _alive_ids()
	var text := "Nobody survived."
	if Network.is_team_mode():
		var teams_alive := {}
		for id in alive:
			teams_alive[Network.player_team(id)] = true
		if teams_alive.size() > 1:
			return
		if teams_alive.size() == 1:
			text = "%s wins!" % Network.team_name(teams_alive.keys()[0])
	else:
		if alive.size() > 1:
			return
		if alive.size() == 1:
			text = "%s wins!" % Network.player_name(alive[0])
	_match_over = true
	_show_results.rpc(text)


# ---------------------------------------------------------------------------
# Blackout (host decides, everyone renders)
# ---------------------------------------------------------------------------

func begin_blackout(caster_id: int) -> void:
	_set_blackout.rpc(caster_id)


func end_blackout(caster_id: int) -> void:
	if blackout_by == caster_id:
		_set_blackout.rpc(0)


@rpc("authority", "call_local", "reliable")
func _set_blackout(caster_id: int) -> void:
	blackout_by = caster_id


func _is_blind(me: NetPlayer) -> bool:
	return blackout_by != 0 and me != null and not me.dead and me.owner_peer_id != blackout_by


func _update_blackout_visuals(me: NetPlayer) -> void:
	var blind := _is_blind(me)
	world_modulate.color = BLACKOUT_COLOR if blind else Color.WHITE
	hud.set_night_vision(blackout_by != 0 and me != null and me.owner_peer_id == blackout_by)
	for p in players_root.get_children():
		if p is NetPlayer:
			p.glow.enabled = blind and p == me


# ---------------------------------------------------------------------------
# Bomb Voyage (host)
# ---------------------------------------------------------------------------

func place_bomb(owner_id: int, pos: Vector2, manual: bool) -> void:
	_bomb_seq += 1
	var owner := players_root.get_node_or_null(str(owner_id)) as NetPlayer
	bomb_spawner.spawn({
		"id": _bomb_seq, "owner": owner_id, "team": owner.team if owner else 0,
		"pos": pos, "manual": manual,
	})


func _spawn_bomb(data: Dictionary) -> Node:
	var scene: PackedScene = load(NET_BOMB_SCENE)
	var bomb := scene.instantiate() as NetBomb
	bomb.name = "bomb_%d" % data["id"]
	bomb.owner_peer_id = data["owner"]
	bomb.team = data["team"]
	bomb.manual = data["manual"]
	bomb.position = data["pos"]
	return bomb


func detonate_bombs(owner_id: int) -> void:
	for b in bombs_root.get_children():
		if b is NetBomb and b.owner_peer_id == owner_id and b.manual:
			_explode(b)


func _server_check_bombs() -> void:
	for b in bombs_root.get_children():
		if not b is NetBomb or b.manual or b.is_queued_for_deletion():
			continue
		for p in players_root.get_children():
			if p is NetPlayer and not p.dead and b.is_enemy(p) \
					and p.global_position.distance_to(b.global_position) <= BOMB_TRIGGER_RADIUS:
				_explode(b)
				break


## Blasts hurt enemies and the owner themself — never teammates.
func _explode(bomb: NetBomb) -> void:
	if bomb.is_queued_for_deletion():
		return
	var pos := bomb.global_position
	_explosion_fx.rpc(pos)
	for p in players_root.get_children():
		if p is NetPlayer and not p.dead and (bomb.is_enemy(p) or p.owner_peer_id == bomb.owner_peer_id) \
				and p.global_position.distance_to(pos) <= BOMB_BLAST_RADIUS:
			p.apply_damage(BOMB_DAMAGE)
	var owner := players_root.get_node_or_null(str(bomb.owner_peer_id)) as NetPlayer
	if owner:
		owner.bomb_exploded()
	bomb.queue_free()


@rpc("authority", "call_local", "unreliable")
func _explosion_fx(pos: Vector2) -> void:
	var points := PackedVector2Array()
	for i in 24:
		points.append(pos + Vector2.RIGHT.rotated(TAU * i / 24.0) * BOMB_BLAST_RADIUS)
	var blast := Polygon2D.new()
	blast.polygon = points
	blast.color = EXPLOSION_COLOR
	bombs_root.add_child(blast)
	var tween := blast.create_tween()
	tween.tween_property(blast, "modulate:a", 0.0, EXPLOSION_LIFETIME)
	tween.tween_callback(blast.queue_free)


# ---------------------------------------------------------------------------
# Vision (every peer, about its own view)
# ---------------------------------------------------------------------------

## The map is always visible; other players are not. You see an enemy only
## when they're close, or ahead of you inside your view cone, with nothing
## solid in between — or when they just gave themselves away by firing, or
## you're haunting them with Poltergeist. Teammates are always visible.
## Spectators (dead) see everyone. Your own bombs are always visible to
## you and never to enemies.
## This is client-side culling: the server still replicates every position,
## so it's a presentation rule for now, not an anti-cheat one.
func _update_vision(me: NetPlayer) -> void:
	var spectating := me == null or me.dead
	for p in players_root.get_children():
		if not p is NetPlayer or p == me:
			continue
		p.haunted = me != null and me.poltergeist_target == p.owner_peer_id
		var ally: bool = me != null and me.team != 0 and p.team == me.team
		p.visible = spectating or ally or p.haunted or _can_see(me, p)
	for b in bombs_root.get_children():
		if b is NetBomb:
			b.visible = spectating or b.owner_peer_id == me.owner_peer_id


func _can_see(me: NetPlayer, other: NetPlayer) -> bool:
	if other.reveal_timer > 0.0:
		return true
	var offset := other.global_position - me.global_position
	var dist := offset.length()
	if _is_blind(me):
		if dist > BLACKOUT_VISION_RADIUS:
			return false
	else:
		if dist > NetPlayer.VIEW_RANGE:
			return false
		if dist > NetPlayer.VISION_RADIUS \
				and absf(angle_difference(me.rotation, offset.angle())) > NetPlayer.VIEW_HALF_ANGLE:
			return false
	var query := PhysicsRayQueryParameters2D.create(me.global_position, other.global_position, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# ---------------------------------------------------------------------------
# Broadcasts (host -> everyone, including itself)
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _set_status(text: String) -> void:
	hud.set_status(text)


@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	hud.announce(text)


@rpc("authority", "call_local", "reliable")
func _show_results(text: String) -> void:
	_match_over = true
	hud.show_results(text, Network.is_host())


# ---------------------------------------------------------------------------
# HUD / leaving
# ---------------------------------------------------------------------------

func _local_player() -> NetPlayer:
	if not multiplayer.has_multiplayer_peer():
		return null
	return players_root.get_node_or_null(str(multiplayer.get_unique_id())) as NetPlayer


func _update_hud(me: NetPlayer) -> void:
	var alive := 0
	var total := 0
	var team_alive := {1: 0, 2: 0}
	for child in players_root.get_children():
		if child is NetPlayer:
			total += 1
			if not child.dead:
				alive += 1
				if team_alive.has(child.team):
					team_alive[child.team] += 1
	if Network.is_team_mode():
		hud.set_alive_text("Team A  %d   —   Team B  %d" % [team_alive[1], team_alive[2]])
	else:
		hud.set_alive(alive, total)
	hud.set_gen(me)
	if me:
		hud.set_hp(me.hp, me.max_hp)
		if me.dead and not _match_over:
			hud.set_status("You were eliminated — spectating")


func _on_lost_server() -> void:
	hud.show_results("Lost connection to the host.", false)


## Host only. Despawn everything BEFORE switching scenes: if the arena is
## simply freed, its despawn packets reach clients after they've already
## torn down their own arena, and every one logs an ERR_UNAUTHORIZED.
func _on_return_pressed() -> void:
	for child in players_root.get_children():
		child.queue_free()
	for child in bombs_root.get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Network.return_to_lobby()


func _on_leave_pressed() -> void:
	Network.leave()
	get_tree().change_scene_to_file(Network.LOBBY_SCENE)
