extends CharacterBody2D
class_name NetPlayer
## A networked player avatar with the online Gen system.
##
## Authority model (first pass, documented tradeoff):
## - The SERVER simulates every remote player's movement from received
##   input and is the authoritative source of position/rotation/hp and all
##   Gen state, replicated to everyone via the MultiplayerSynchronizer
##   (default authority is always peer 1 = server).
## - The OWNING client ALSO simulates its own movement locally, immediately,
##   so input feels instant ("prediction"). It does not yet reconcile or
##   smooth against the server's correction; the raw snap is visible.
## - Hits and Gen activations are server-authoritative: a client's press
##   only SENDS a request; the server alone decides. The host's own avatar
##   skips the RPC and calls the server logic directly, since an RPC
##   targeted at yourself isn't delivered in call_remote mode.

signal died(owner_peer_id: int)

enum GenState { READY, ACTIVE, COOLDOWN }
enum GenAction { USE, USE_ALT, DETONATE }

const COLORS := [
	Color(0.3, 0.8, 0.5), Color(0.9, 0.4, 0.3), Color(0.35, 0.6, 1.0),
	Color(1.0, 0.8, 0.3), Color(0.8, 0.4, 0.9), Color(0.4, 0.9, 0.9),
]
const TEAM_COLORS := {1: Color(0.35, 0.6, 1.0), 2: Color(0.95, 0.4, 0.3)}
const AIM_SEND_INTERVAL := 0.05
const TRACER_LIFETIME := 0.12

## Vision rule (see net_arena.gd): enemies inside VISION_RADIUS are seen in
## any direction; out to VIEW_RANGE only inside the forward cone.
const VISION_RADIUS := 180.0
const VIEW_RANGE := 420.0
const VIEW_HALF_ANGLE := deg_to_rad(40.0)
## Firing gives your position away to everyone for this long.
const REVEAL_ON_SHOT := 0.5
const VISION_GUIDE_COLOR := Color(1, 1, 1, 0.08)
const SHIELD_COLOR := Color(0.4, 0.9, 1.0)
const HAUNT_COLOR := Color(0.8, 0.4, 1.0)
## Holding the Gen key this long drops a manual bomb instead of a proximity one.
const BOMB_HOLD_SECONDS := 0.4
const DISGUISE_SIZE := 44.0

## Movement smoothing. The server's position is replicated as net_pos (NOT
## as the node's own position, which would overwrite the owner's local
## prediction every sync). Remote avatars glide toward it; the owner only
## corrects when it has genuinely drifted.
const REPLICATION_INTERVAL := 0.05
const REMOTE_SMOOTH := 18.0
const TELEPORT_DIST := 300.0
const SNAP_MIN := 96.0
const STILL_GRACE := 0.25
const CORRECT_RATE := 6.0

@export var speed := 160.0
@export var max_hp := 5
@export var shoot_range := 400.0
@export var fire_cooldown := 0.3

## Set once at spawn time (net_arena.gd) — which peer this avatar belongs
## to. Not multiplayer authority (that's always the server); just "whose
## input do I predict locally and whose requests do I accept."
var owner_peer_id: int = 1
var gen := Gens.DEFAULT
## 0 in free-for-all, 1 or 2 in team mode. Set at spawn time.
var team := 0

# --- replicated by the server (see configure_replication) ---
var hp: int
var dead := false
var gen_state := GenState.READY
var gen_timer := 0.0
var camouflaged := false
var shield_hp := 0
var poltergeist_target := 0
var bombs_placed := 0
var net_pos := Vector2.ZERO
var net_rot := 0.0
## 0 fine, 1 lagging (host hasn't heard from them lately), 2 connection lost
## (kept in the match, dimmed, until the host's grace period runs out).
var link_state := 0
## Travels with the avatar from spawn so it survives the roster entry being
## erased when the player drops.
var display_name := ""

## Local-only presentation state.
var dbg_snaps := 0  # times the owner was snapped back to the server (diagnostic)
var _still_time := 0.0
var reveal_timer := 0.0
var haunted := false  # set by net_arena.gd when the LOCAL player is tracking this avatar

var _input_dir := Vector2.ZERO
var _aim := 0.0
var _last_sent_aim := 0.0
var _aim_send_timer := 0.0
var _cooldown_left := 0.0
var _gen_hold := 0.0
var _joystick: Control = null
var _aim_pad: Control = null

@onready var visual: Polygon2D = $Visual
@onready var disguise: Sprite2D = $Disguise
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var name_label: Label = $NameLabel
@onready var glow: PointLight2D = $Glow


func _ready() -> void:
	hp = max_hp
	net_pos = position
	net_rot = rotation
	add_to_group("net_player")
	visual.color = TEAM_COLORS[team] if TEAM_COLORS.has(team) else COLORS[absi(owner_peer_id) % COLORS.size()]
	disguise.scale = Vector2.ONE * (DISGUISE_SIZE / disguise.texture.get_width())
	_refresh_name()
	Network.player_list_changed.connect(_refresh_name)
	if _is_mine():
		_joystick = get_tree().get_first_node_in_group("touch_joystick_p1")
		_aim_pad = get_tree().get_first_node_in_group("touch_aim_p1")


func _exit_tree() -> void:
	if Network.player_list_changed.is_connected(_refresh_name):
		Network.player_list_changed.disconnect(_refresh_name)


## The MultiplayerSynchronizer needs its replication_config set BEFORE this
## node is added to the tree — the engine wires up spawn-replication as
## part of add_child() itself, ahead of this node's own _ready(), so
## building the config in _ready() loses that race and corrupts the peer's
## replication state (ERR_UNCONFIGURED, then a dropped connection).
## net_arena.gd's spawn function calls this right after instantiate().
func configure_replication() -> void:
	var sync := get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var config := SceneReplicationConfig.new()
	for prop in ["net_pos", "net_rot", "link_state", "hp", "dead", "gen_state", "gen_timer",
			"camouflaged", "shield_hp", "poltergeist_target", "bombs_placed"]:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	sync.replication_interval = REPLICATION_INTERVAL


func _is_mine() -> bool:
	return multiplayer.has_multiplayer_peer() and owner_peer_id == multiplayer.get_unique_id()


func _arena() -> Node:
	return get_parent().get_parent()


func is_enemy(other: NetPlayer) -> bool:
	return other != self and (team == 0 or other.team != team)


func _refresh_name() -> void:
	var base := display_name if display_name != "" else Network.player_name(owner_peer_id)
	match link_state:
		1:
			base += " (lagging)"
		2:
			base += " (connection lost)"
	name_label.text = base


# ---------------------------------------------------------------------------
# Presentation (every peer)
# ---------------------------------------------------------------------------

func _smooth_remote(delta: float) -> void:
	if position.distance_to(net_pos) > TELEPORT_DIST:
		position = net_pos
	else:
		position = position.lerp(net_pos, 1.0 - exp(-delta * REMOTE_SMOOTH))
	rotation = lerp_angle(rotation, net_rot, 1.0 - exp(-delta * REMOTE_SMOOTH))


## Owner only (clients). Our prediction normally matches the server; this
## only acts on real drift. Snap when the gap is bigger than latency alone
## can explain; when standing still, ease the last few pixels together —
## but only after the server has had time to catch up to where we stopped,
## otherwise we'd tug ourselves back toward its stale, mid-walk position.
func _reconcile(delta: float, dir: Vector2) -> void:
	var rtt := Network.rtt_ms / 1000.0
	var snap_dist := maxf(SNAP_MIN, speed * rtt * 1.5 + 32.0)
	if position.distance_to(net_pos) > snap_dist:
		position = net_pos
		dbg_snaps += 1
		return
	if dir != Vector2.ZERO:
		_still_time = 0.0
		return
	_still_time += delta
	if _still_time > rtt + STILL_GRACE:
		position = position.lerp(net_pos, 1.0 - exp(-delta * CORRECT_RATE))


func _process(delta: float) -> void:
	# After the host drops, the arena lingers behind the "lost connection"
	# overlay with no peer assigned; asking multiplayer anything then errors.
	if not multiplayer.has_multiplayer_peer():
		return
	reveal_timer = maxf(0.0, reveal_timer - delta)
	if not multiplayer.is_server() and not _is_mine():
		_smooth_remote(delta)
	name_label.rotation = -rotation
	disguise.rotation = -rotation
	var alpha := 0.25 if dead else (0.45 if link_state != 0 else 1.0)
	visual.modulate.a = alpha
	disguise.modulate.a = alpha
	name_label.modulate.a = alpha
	_refresh_name()
	visual.visible = not camouflaged
	disguise.visible = camouflaged
	name_label.visible = not camouflaged
	if dead and not collision.disabled:
		collision.set_deferred("disabled", true)
	queue_redraw()


func _draw() -> void:
	if shield_hp > 0:
		var strength := float(shield_hp) / float(Gens.def("shield").get("shield_hp", 1))
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, Color(SHIELD_COLOR, 0.35 + 0.5 * strength), 2.5)
	if haunted:
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 24, HAUNT_COLOR, 2.0)
		draw_circle(Vector2(0, -44).rotated(-rotation), 5.0, HAUNT_COLOR)
	if not _is_mine():
		return
	# Faint guides for your own vision: the close ring and the forward cone's
	# far edge. Local space, so the cone turns with your aim for free.
	draw_arc(Vector2.ZERO, VISION_RADIUS, 0.0, TAU, 48, VISION_GUIDE_COLOR, 1.0)
	draw_arc(Vector2.ZERO, VIEW_RANGE, -VIEW_HALF_ANGLE, VIEW_HALF_ANGLE, 24, VISION_GUIDE_COLOR, 1.0)
	var edge_start := Vector2.RIGHT * VISION_RADIUS
	var edge_end := Vector2.RIGHT * VIEW_RANGE
	draw_line(edge_start.rotated(-VIEW_HALF_ANGLE), edge_end.rotated(-VIEW_HALF_ANGLE), VISION_GUIDE_COLOR, 1.0)
	draw_line(edge_start.rotated(VIEW_HALF_ANGLE), edge_end.rotated(VIEW_HALF_ANGLE), VISION_GUIDE_COLOR, 1.0)


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if multiplayer.is_server():
		_server_gen_tick(delta)
		_server_link_tick()
	if not dead:
		if _is_mine():
			_local_update(delta)
		elif multiplayer.is_server():
			# Remote avatars: only the server drives movement from received
			# input; clients render them from net_pos (see _smooth_remote).
			velocity = _input_dir * speed
			move_and_slide()
			rotation = _aim
	if multiplayer.is_server():
		net_pos = position
		net_rot = rotation


func _local_update(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO and _joystick and _joystick.visible:
		dir = _joystick.get_vector()
	dir = dir.limit_length(1.0)
	if dir != _input_dir:
		_input_dir = dir
		if not multiplayer.is_server():
			_send_move.rpc_id(1, dir)
	velocity = dir * speed
	move_and_slide()
	if not multiplayer.is_server():
		_reconcile(delta, dir)

	if _aim_pad and _aim_pad.visible:
		_aim = _aim_pad.get_vector().angle()
	else:
		_aim = (get_global_mouse_position() - global_position).angle()
	rotation = _aim
	_aim_send_timer -= delta
	if _aim_send_timer <= 0.0 and absf(angle_difference(_last_sent_aim, _aim)) > 0.01:
		_aim_send_timer = AIM_SEND_INTERVAL
		_last_sent_aim = _aim
		if not multiplayer.is_server():
			_send_aim.rpc_id(1, _aim)

	if Input.is_action_just_pressed("shoot") and _cooldown_left <= 0.0 and not camouflaged:
		_cooldown_left = fire_cooldown
		if multiplayer.is_server():
			_server_shoot(_aim)
		else:
			_request_shoot.rpc_id(1, _aim)

	_gen_input(delta)


func _gen_input(delta: float) -> void:
	if gen == "bomb_voyage":
		if Input.is_action_pressed("use_power"):
			_gen_hold += delta
		elif _gen_hold > 0.0:
			_send_gen(GenAction.USE_ALT if _gen_hold >= BOMB_HOLD_SECONDS else GenAction.USE)
			_gen_hold = 0.0
		if Input.is_action_just_pressed("gen_detonate"):
			_send_gen(GenAction.DETONATE)
	elif Input.is_action_just_pressed("use_power"):
		_send_gen(GenAction.USE)


func _send_gen(action: int) -> void:
	if multiplayer.is_server():
		_server_gen(action)
	else:
		_request_gen.rpc_id(1, action)


# ---------------------------------------------------------------------------
# Client -> server requests
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _send_move(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return  # a peer can only drive the avatar it owns
	_input_dir = dir.limit_length(1.0)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_aim(aim: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	_aim = aim


@rpc("any_peer", "call_remote", "reliable")
func _request_shoot(aim: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	_server_shoot(aim)


@rpc("any_peer", "call_remote", "reliable")
func _request_gen(action: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	_server_gen(action)


# ---------------------------------------------------------------------------
# Server-side rules
# ---------------------------------------------------------------------------

## Uses the server's own idea of where this player stands, not a
## client-supplied origin, so a client can't shoot from somewhere it isn't.
func _server_shoot(aim: float) -> void:
	if dead or camouflaged:
		return
	if not _is_mine() and _cooldown_left > 0.0:
		return
	_cooldown_left = fire_cooldown
	_aim = aim
	var from := global_position
	var to := from + Vector2.RIGHT.rotated(aim) * shoot_range
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [self]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	var hit_point := to
	if result:
		hit_point = result.position
		if result.collider is NetPlayer and is_enemy(result.collider):
			(result.collider as NetPlayer).apply_damage(1)
		elif result.collider is NetDecoy and (result.collider as NetDecoy).is_enemy_of(self):
			(result.collider as NetDecoy).apply_damage(1)
	_shot_fx.rpc(from, hit_point)


func _server_gen(action: int) -> void:
	if dead:
		return
	var def := Gens.def(gen)
	match gen:
		"camouflage":
			if gen_state == GenState.ACTIVE:
				_end_gen()  # the manual "turn back" — the only way to shoot again
			elif gen_state == GenState.READY:
				_activate_gen(def)
				camouflaged = true
		"shield":
			if gen_state == GenState.READY:
				_activate_gen(def)
				shield_hp = def["shield_hp"]
		"poltergeist":
			if gen_state == GenState.READY:
				var target := _nearest_enemy()
				if target:
					_activate_gen(def)
					poltergeist_target = target.owner_peer_id
		"blackout":
			if gen_state == GenState.READY:
				_activate_gen(def)
				_arena().begin_blackout(owner_peer_id)
		"decoy":
			if gen_state == GenState.READY:
				var prey := _nearest_enemy()
				if prey:
					_activate_gen(def)
					_arena().spawn_decoy(self, prey, def["duration"])
		"bomb_voyage":
			if action == GenAction.DETONATE:
				_arena().detonate_bombs(owner_peer_id)
				return
			if gen_state == GenState.COOLDOWN or bombs_placed >= int(def["max_bombs"]):
				return
			_arena().place_bomb(owner_peer_id, global_position, action == GenAction.USE_ALT)
			bombs_placed += 1
			gen_state = GenState.COOLDOWN
			gen_timer = def["cooldown"]


func _activate_gen(def: Dictionary) -> void:
	gen_state = GenState.ACTIVE
	gen_timer = def["duration"]


func _end_gen() -> void:
	camouflaged = false
	shield_hp = 0
	poltergeist_target = 0
	if gen == "blackout":
		_arena().end_blackout(owner_peer_id)
	gen_state = GenState.COOLDOWN
	gen_timer = Gens.def(gen)["cooldown"]


func _server_gen_tick(delta: float) -> void:
	if gen_state == GenState.READY:
		return
	gen_timer -= delta
	if gen_timer > 0.0:
		return
	if gen_state == GenState.ACTIVE:
		_end_gen()
	else:
		gen_state = GenState.READY
		gen_timer = 0.0


func _server_link_tick() -> void:
	if link_state == 2:
		_input_dir = Vector2.ZERO  # a lost connection stands still
	else:
		link_state = Network.link_state(owner_peer_id)


## Host: the connection dropped. The avatar stays (dimmed, still killable)
## so the match keeps going around it; the arena eliminates it after a grace.
func mark_connection_lost() -> void:
	link_state = 2
	_input_dir = Vector2.ZERO


func force_eliminate() -> void:
	if dead:
		return
	hp = 0
	dead = true
	died.emit(owner_peer_id)


func _nearest_enemy() -> NetPlayer:
	var best: NetPlayer = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("net_player"):
		var other := node as NetPlayer
		if other.dead or not is_enemy(other):
			continue
		var d := global_position.distance_squared_to(other.global_position)
		if d < best_dist:
			best_dist = d
			best = other
	return best


## Called by net_arena.gd when one of this player's bombs goes off.
func bomb_exploded() -> void:
	bombs_placed = maxi(0, bombs_placed - 1)


@rpc("authority", "call_local", "unreliable")
func _shot_fx(from: Vector2, to: Vector2) -> void:
	reveal_timer = REVEAL_ON_SHOT
	var tracer := Line2D.new()
	tracer.width = 2.0
	tracer.default_color = Color(1.0, 0.95, 0.6)
	tracer.points = PackedVector2Array([from, to])
	get_parent().add_child(tracer)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "modulate:a", 0.0, TRACER_LIFETIME)
	tween.tween_callback(tracer.queue_free)


## Server-only, direct call (not an RPC) — the server already holds the
## authoritative NetPlayer instance, so it just mutates it; the
## MultiplayerSynchronizer's own replication is what informs every client.
## A shield absorbs the whole hit that breaks it.
func apply_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if dead:
		return
	if shield_hp > 0:
		shield_hp -= amount
		if shield_hp <= 0:
			_end_gen()
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		dead = true
		died.emit(owner_peer_id)
