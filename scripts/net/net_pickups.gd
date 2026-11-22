extends Node2D
class_name NetPickups
## Everything lying on the arena floor, and the rules for it. The host owns all
## of it: it picks where things go, decides who touches what, and spawns and
## removes them; every other peer receives the same pickups through a
## MultiplayerSpawner and only draws them.
##
##   ammo crates       spread around the map, come back 30s after being emptied
##   medical stations  stand beside one ~2.5s and it heals 40% of full health,
##                     then it needs 45s to recharge
##   dropped ammo      a player can drop some for a teammate (key H); a dead
##                     player's remaining rounds fall where they died
##   dropped Gens      a dead player's Gen(s) fall where they died; walk up and
##                     take one (see NetPlayer for the keys)
## Placement is from a fixed seed, so the map is the same every match and
## people can learn where things are.

const PICKUP_SCENE := "res://scenes/net/net_pickup.tscn"
const SEED := 20260520

const STATION_COUNT := 6
const CRATE_COUNT := 9
const STATION_MIN_GAP_CELLS := 9
const CRATE_MIN_GAP_CELLS := 5
const SPAWN_CLEARANCE_CELLS := 4  # stations stay this far from any spawn marker

const CRATE_ROUNDS := 20
const CRATE_RESPAWN := 30.0
const STATION_RADIUS := 38.0
const HEAL_TIME := 2.5
const HEAL_FRACTION := 0.4
const STATION_COOLDOWN := 45.0
const GEN_TAKE_RADIUS := 46.0
const DROP_LIFETIME := 90.0
const DROP_IGNORE := 1.5  # the dropper can't scoop it straight back up

var _spawner: MultiplayerSpawner
var _seq := 0
var _map: NetMap
var _respawns: Dictionary = {}  # site index -> seconds until its crate returns
var _sites: Array = []  # [{"kind": String, "pos": Vector2}] fixed spots


func setup(map: NetMap) -> void:
	_map = map
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("..")  # spawned things go in this node (the spawner is its child)
	_spawner.spawn_function = _spawn_pickup
	add_child(_spawner)


## Runs on every peer with the same data.
func _spawn_pickup(data: Dictionary) -> Node:
	var pickup := (load(PICKUP_SCENE) as PackedScene).instantiate() as NetPickup
	pickup.name = "pk_%d" % data["id"]
	pickup.kind = data["kind"]
	pickup.amount = data["amount"]
	pickup.gen_key = data["gen"]
	pickup.position = data["pos"]
	pickup.configure_replication()
	return pickup


# ---------------------------------------------------------------------------
# Host: placing things
# ---------------------------------------------------------------------------

func begin_match() -> void:
	_sites = _choose_sites()
	for i in _sites.size():
		var site: Dictionary = _sites[i]
		if site["kind"] == "health":
			_make("health", site["pos"], 0, "", i)
		else:
			_make("ammo", site["pos"], CRATE_ROUNDS, "", i)


func _make(kind: String, pos: Vector2, amount := 0, gen_key := "", site := -1) -> NetPickup:
	_seq += 1
	var pickup := _spawner.spawn({"id": _seq, "kind": kind, "amount": amount, "gen": gen_key, "pos": pos}) as NetPickup
	pickup.site = site
	if site < 0:
		pickup.ttl = DROP_LIFETIME
	return pickup


## Open floor with room around it, spread out, away from the spawns.
func _choose_sites() -> Array:
	var layout: PackedStringArray = _map.layout
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var spawns: Array = []
	for kind in ["S", "1", "2"]:
		for world in _map.spawn_cells(kind):
			spawns.append(Vector2i((world / NetMap.CELL).floor()))
	var open: Array = []
	for y in range(1, layout.size() - 1):
		for x in range(1, layout[y].length() - 1):
			if _roomy(layout, x, y):
				open.append(Vector2i(x, y))
	# A seeded shuffle (Fisher-Yates), so the same cells come out first every time.
	for i in range(open.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = open[i]
		open[i] = open[j]
		open[j] = swap
	var chosen: Array = []
	var stations: Array = []
	for cell: Vector2i in open:
		if stations.size() >= STATION_COUNT:
			break
		if _far_from(cell, stations, STATION_MIN_GAP_CELLS) and _far_from(cell, spawns, SPAWN_CLEARANCE_CELLS):
			stations.append(cell)
	var crates: Array = []
	for cell: Vector2i in open:
		if crates.size() >= CRATE_COUNT:
			break
		if _far_from(cell, crates, CRATE_MIN_GAP_CELLS) and _far_from(cell, stations, 3):
			crates.append(cell)
	for cell: Vector2i in stations:
		chosen.append({"kind": "health", "pos": (Vector2(cell) + Vector2(0.5, 0.5)) * NetMap.CELL})
	for cell: Vector2i in crates:
		chosen.append({"kind": "ammo", "pos": (Vector2(cell) + Vector2(0.5, 0.5)) * NetMap.CELL})
	return chosen


## The cell and all eight around it are walkable floor.
func _roomy(layout: PackedStringArray, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var row := layout[y + dy]
			if x + dx >= row.length() or row[x + dx] in NetMap.SOLID:
				return false
	return true


func _far_from(cell: Vector2i, others: Array, gap: int) -> bool:
	for other: Vector2i in others:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) < gap:
			return false
	return true


# ---------------------------------------------------------------------------
# Host: drops
# ---------------------------------------------------------------------------

func drop_ammo(pos: Vector2, rounds: int, dropper_id := 0) -> void:
	if rounds <= 0:
		return
	var pickup := _make("ammo", pos, rounds)
	pickup.ignore_id = dropper_id
	pickup.ignore_until = _now() + DROP_IGNORE


func drop_gen(pos: Vector2, key: String) -> void:
	if Gens.is_valid(key):
		_make("gen", pos, 0, key)


## What a player leaves where they fall: their rounds, and each Gen they held.
func drop_for_death(player: NetPlayer) -> void:
	var around := [Vector2(30, 0), Vector2(-24, 22), Vector2(-24, -22)]
	var i := 0
	if player.ammo > 0:
		drop_ammo(player.global_position + around[i], player.ammo)
		i += 1
	drop_gen(player.global_position + around[i], player.gen)
	i += 1
	if player.spare_gen != "":
		drop_gen(player.global_position + around[i % around.size()], player.spare_gen)


# ---------------------------------------------------------------------------
# Host: every physics frame
# ---------------------------------------------------------------------------

func server_tick(delta: float, players: Array) -> void:
	var alive: Array = []
	for p in players:
		if p is NetPlayer and not p.dead:
			alive.append(p)
	for node in get_children():
		var pickup := node as NetPickup
		if pickup == null or pickup.is_queued_for_deletion():
			continue
		pickup.ttl -= delta
		if pickup.ttl <= 0.0:
			pickup.queue_free()
			continue
		match pickup.kind:
			"ammo":
				_tick_ammo(pickup, alive)
			"health":
				_tick_station(pickup, alive, delta)
	# Emptied crates come back after a while.
	for site: int in _respawns.keys():
		_respawns[site] -= delta
		if _respawns[site] <= 0.0:
			_respawns.erase(site)
			_make("ammo", _sites[site]["pos"], CRATE_ROUNDS, "", site)


func _tick_ammo(pickup: NetPickup, alive: Array) -> void:
	for p: NetPlayer in alive:
		if p.ammo >= NetPlayer.MAX_AMMO or p.global_position.distance_to(pickup.global_position) > NetPickup.RADIUS:
			continue
		if p.owner_peer_id == pickup.ignore_id and _now() < pickup.ignore_until:
			continue
		var taken := mini(pickup.amount, NetPlayer.MAX_AMMO - p.ammo)
		p.ammo += taken
		pickup.amount -= taken
		if pickup.amount <= 0:
			_consume(pickup)
		return


func _tick_station(pickup: NetPickup, alive: Array, delta: float) -> void:
	if pickup.cooldown_left > 0.0:
		pickup.cooldown_left = maxf(0.0, pickup.cooldown_left - delta)
		pickup.charge = 0.0
		return
	var user: NetPlayer = null
	var best := INF
	for p: NetPlayer in alive:
		var d := p.global_position.distance_to(pickup.global_position)
		if d > STATION_RADIUS or p.hp >= p.max_hp:
			continue
		if p.owner_peer_id == pickup.user_id:
			user = p  # whoever started keeps it
			break
		if d < best:
			best = d
			user = p
	if user == null:
		pickup.user_id = 0
		pickup.charge = maxf(0.0, pickup.charge - delta * 1.5)  # walking away loses the progress
		return
	if user.owner_peer_id != pickup.user_id:
		pickup.user_id = user.owner_peer_id
		pickup.charge = 0.0
	pickup.charge += delta / HEAL_TIME
	if pickup.charge >= 1.0:
		user.server_heal(int(user.max_hp * HEAL_FRACTION))
		pickup.charge = 0.0
		pickup.cooldown_left = STATION_COOLDOWN
		pickup.user_id = 0


## Spent: gone for good if it was a drop, back after a while if it was a crate.
func _consume(pickup: NetPickup) -> void:
	if pickup.site >= 0:
		_respawns[pickup.site] = CRATE_RESPAWN
	pickup.queue_free()


# ---------------------------------------------------------------------------
# Taking a dropped Gen (host)
# ---------------------------------------------------------------------------

func nearest_gen(pos: Vector2) -> NetPickup:
	var best: NetPickup = null
	var best_dist := GEN_TAKE_RADIUS
	for node in get_children():
		var pickup := node as NetPickup
		if pickup == null or pickup.kind != "gen" or pickup.is_queued_for_deletion():
			continue
		var d := pos.distance_to(pickup.global_position)
		if d <= best_dist:
			best_dist = d
			best = pickup
	return best


func nearest_station(pos: Vector2) -> NetPickup:
	var best: NetPickup = null
	var best_dist := STATION_RADIUS
	for node in get_children():
		var pickup := node as NetPickup
		if pickup == null or pickup.kind != "health":
			continue
		var d := pos.distance_to(pickup.global_position)
		if d <= best_dist:
			best_dist = d
			best = pickup
	return best


func take(pickup: NetPickup) -> void:
	pickup.queue_free()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
