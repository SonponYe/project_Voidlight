extends Node2D
class_name NetMapPainter
## Paints the arena's ruins (see NetMap). Lives inside a SubViewport that
## renders once, so all this detail costs nothing per frame. Everything is
## drawn from a fixed seed, so every player sees the identical ruins.

const SEED := 20260519
const CELL := 64.0
const BARREL_RADIUS := 24.0

const OUTSIDE := Color(0.09, 0.08, 0.075)
const CONCRETE := Color(0.46, 0.44, 0.41)
const DIRT := Color(0.33, 0.28, 0.21)
const WALL_TOP := Color(0.50, 0.48, 0.45)
const WALL_SIDE := Color(0.27, 0.25, 0.23)
const WALL_EDGE := Color(0.13, 0.12, 0.11)
const SANDBAG := Color(0.68, 0.60, 0.43)
const SANDBAG_DARK := Color(0.36, 0.30, 0.20)
const WOOD := Color(0.50, 0.37, 0.22)
const SOOT := Color(0.05, 0.04, 0.03)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.30)
const EXTRUDE := 9.0
const SHADOW_OFFSET := Vector2(11.0, 14.0)

var bounds := Rect2()
var blocks: Array = []
var barrels: Array = []
var voids: Array = []  # darkness beyond the arena, painted over the ground

var _width := 0
var _height := 0
var _decor := {}
var _spawns := {}
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()


func setup(p_bounds: Rect2, p_width: int, p_height: int, p_blocks: Array, p_barrels: Array, p_decor: Dictionary, p_spawns: Dictionary, p_voids: Array = []) -> void:
	voids = p_voids
	bounds = p_bounds
	_width = p_width
	_height = p_height
	blocks = p_blocks
	barrels = p_barrels
	_decor = p_decor
	_spawns = p_spawns
	_noise.seed = 7
	_noise.frequency = 0.17



func _draw() -> void:
	_rng.seed = SEED
	_draw_ground()
	_draw_grime()
	_draw_decor_cells()
	_draw_spawn_paint()
	for rect: Rect2 in voids:
		draw_rect(rect, OUTSIDE)
	for block in blocks:
		draw_rect(Rect2(block["rect"].position + SHADOW_OFFSET, block["rect"].size), SHADOW_COLOR)
	for center in barrels:
		draw_circle(center + SHADOW_OFFSET * 0.7, BARREL_RADIUS, SHADOW_COLOR)
	for block in blocks:
		match block["kind"]:
			"#":
				_draw_wall(block["rect"])
			"c":
				_draw_cover(block["rect"])
			"v":
				_draw_vehicle(block["rect"])
	for center in barrels:
		_draw_barrel(center)


func _hash(x: int, y: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663)) & 1023) / 1023.0


func _draw_ground() -> void:
	for y in _height:
		for x in _width:
			var origin := Vector2(x, y) * CELL
			var patch := smoothstep(-0.12, 0.28, _noise.get_noise_2d(x, y)) * 0.6  # 0 concrete .. 1 dirt
			var shade := 0.95 + 0.09 * _hash(x, y)
			var base := CONCRETE.lerp(DIRT, patch)
			draw_rect(Rect2(origin, Vector2(CELL, CELL)), Color(base.r * shade, base.g * shade, base.b * shade))
			if patch < 0.55 and _hash(x + 5, y + 9) > 0.3:
				draw_line(origin, origin + Vector2(CELL, 0), Color(0, 0, 0, 0.20), 1.5)
				draw_line(origin, origin + Vector2(0, CELL), Color(0, 0, 0, 0.16), 1.5)


func _blob(center: Vector2, radius: float, color: Color, jag := 0.28, points := 12) -> void:
	var poly := PackedVector2Array()
	var phase := _rng.randf() * TAU
	for i in points:
		var a := phase + TAU * i / points
		poly.append(center + Vector2.from_angle(a) * radius * (1.0 - jag * 0.5 + jag * _rng.randf()))
	draw_colored_polygon(poly, color)


func _random_point() -> Vector2:
	return Vector2(_rng.randf_range(20.0, bounds.size.x - 20.0), _rng.randf_range(20.0, bounds.size.y - 20.0))


func _crack(from: Vector2, color: Color) -> void:
	var p := from
	var angle := _rng.randf() * TAU
	var width := _rng.randf_range(1.0, 2.2)
	for i in _rng.randi_range(4, 8):
		angle += _rng.randf_range(-0.7, 0.7)
		var next := p + Vector2.from_angle(angle) * _rng.randf_range(10.0, 26.0)
		draw_line(p, next, color, width)
		if _rng.randf() < 0.25:  # a fork
			draw_line(next, next + Vector2.from_angle(angle + _rng.randf_range(-1.2, 1.2)) * 12.0, color, 1.0)
		p = next


func _debris(at: Vector2, spread: float, count: int) -> void:
	for i in count:
		var c := at + Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread))
		var s := _rng.randf_range(3.0, 11.0)
		var tone := _rng.randf_range(0.28, 0.62)
		var poly := PackedVector2Array()
		var phase := _rng.randf() * TAU
		for k in _rng.randi_range(3, 5):
			poly.append(c + Vector2.from_angle(phase + k * 1.3 + _rng.randf() * 0.8) * s * _rng.randf_range(0.5, 1.0))
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(tone, tone * 0.96, tone * 0.9, 0.85))


func _draw_grime() -> void:
	# Soft patches of ground-in dirt and pale dust, to break up the tile grid.
	for i in 60:
		_blob(_random_point(), _rng.randf_range(70.0, 180.0), Color(DIRT.r, DIRT.g, DIRT.b, 0.24), 0.4, 14)
	for i in 34:
		_blob(_random_point(), _rng.randf_range(50.0, 140.0), Color(0.60, 0.58, 0.53, 0.10), 0.4, 14)
	# Soot and damp stains: big, faint, overlapping.
	for i in 40:
		_blob(_random_point(), _rng.randf_range(30.0, 120.0), Color(SOOT.r, SOOT.g, SOOT.b, _rng.randf_range(0.05, 0.12)))
	# Oil spills with a dull sheen.
	for i in 18:
		var at := _random_point()
		var r := _rng.randf_range(14.0, 38.0)
		_blob(at, r, Color(0.04, 0.05, 0.07, 0.55), 0.35)
		_blob(at + Vector2(-r * 0.2, -r * 0.2), r * 0.35, Color(0.30, 0.34, 0.42, 0.18), 0.3, 8)
	# Tire tracks.
	for i in 6:
		var start := _random_point()
		var heading := _rng.randf() * TAU
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var p := start
		for k in 22:
			heading += _rng.randf_range(-0.12, 0.12)
			p += Vector2.from_angle(heading) * 34.0
			var side := Vector2.from_angle(heading + PI * 0.5) * 13.0
			left.append(p + side)
			right.append(p - side)
		draw_polyline(left, Color(0, 0, 0, 0.14), 6.0)
		draw_polyline(right, Color(0, 0, 0, 0.14), 6.0)
	for i in 150:
		_crack(_random_point(), Color(0.09, 0.07, 0.05, 0.55))
	for i in 85:
		var at := _random_point()
		draw_circle(at, _rng.randf_range(2.0, 3.6), Color(0.07, 0.06, 0.05, 0.85))
		draw_arc(at, _rng.randf_range(4.0, 6.0), 0.0, TAU, 8, Color(0.75, 0.72, 0.66, 0.25), 1.0)
	for i in 70:
		_debris(_random_point(), 40.0, _rng.randi_range(3, 8))


func _draw_decor_cells() -> void:
	for center in _decor["x"]:  # scorch marks
		_blob(center, 68.0, Color(0, 0, 0, 0.10), 0.35)
		_blob(center, 46.0, Color(0, 0, 0, 0.16), 0.35)
		_blob(center, 26.0, Color(0, 0, 0, 0.26), 0.4)
	for center in _decor["k"]:  # craters
		var r := _rng.randf_range(54.0, 92.0)
		_blob(center, r * 1.28, Color(0.30, 0.24, 0.17, 0.55), 0.3, 14)
		_blob(center, r * 1.05, Color(0.20, 0.15, 0.11), 0.22, 14)
		_blob(center, r * 0.62, Color(0.11, 0.08, 0.06), 0.25, 12)
		_debris(center, r * 1.35, 14)
	for center in _decor["d"]:  # rubble heaps
		_blob(center, 34.0, Color(0.12, 0.10, 0.08, 0.5), 0.4)
		_debris(center, 26.0, 16)
		for i in 2:  # twisted rebar
			var a := _rng.randf() * TAU
			var from: Vector2 = center + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12))
			draw_line(from, from + Vector2.from_angle(a) * _rng.randf_range(18.0, 30.0), Color(0.34, 0.20, 0.12), 2.0)


func _draw_spawn_paint() -> void:
	for center in _spawns["1"]:
		draw_circle(center, 30.0, Color(0.30, 0.60, 0.85, 0.20))
		draw_arc(center, 30.0, 0.0, TAU, 24, Color(0.30, 0.60, 0.85, 0.45), 2.0)
	for center in _spawns["2"]:
		draw_circle(center, 30.0, Color(0.85, 0.35, 0.30, 0.20))
		draw_arc(center, 30.0, 0.0, TAU, 24, Color(0.85, 0.35, 0.30, 0.45), 2.0)


func _draw_wall(rect: Rect2) -> void:
	# Rubble spilled at the foot of the wall, drawn first so the wall sits on it.
	_debris(rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.5 + 10.0, int((rect.size.x + rect.size.y) / 14.0))
	draw_rect(Rect2(rect.position + Vector2(0, EXTRUDE), rect.size), WALL_SIDE)
	var tint := 0.90 + 0.14 * _rng.randf()
	draw_rect(rect, Color(WALL_TOP.r * tint, WALL_TOP.g * tint, WALL_TOP.b * tint))
	# Soot and water staining across the top.
	for i in int(rect.size.x * rect.size.y / 7000.0) + 2:
		var at := rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		_blob(at, _rng.randf_range(10.0, 30.0), Color(SOOT.r, SOOT.g, SOOT.b, _rng.randf_range(0.14, 0.30)))
	# Cracks and bullet scars, kept inside the rectangle.
	for i in int((rect.size.x + rect.size.y) / 55.0) + 1:
		var from := rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		_crack(from, Color(0.10, 0.09, 0.08, 0.7))
	for i in int((rect.size.x + rect.size.y) / 70.0):
		var at := rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		draw_circle(at, _rng.randf_range(2.0, 3.4), Color(0.06, 0.05, 0.05, 0.9))
		draw_arc(at, _rng.randf_range(4.0, 5.5), 0.0, TAU, 8, Color(0.78, 0.75, 0.70, 0.35), 1.0)
	# Chipped, broken edges.
	var perimeter := (rect.size.x + rect.size.y) * 2.0
	for i in int(perimeter / 45.0):
		var t := _rng.randf() * perimeter
		var pos: Vector2
		var inward: Vector2
		if t < rect.size.x:
			pos = rect.position + Vector2(t, 0)
			inward = Vector2(0, 1)
		elif t < rect.size.x + rect.size.y:
			pos = rect.position + Vector2(rect.size.x, t - rect.size.x)
			inward = Vector2(-1, 0)
		elif t < rect.size.x * 2.0 + rect.size.y:
			pos = rect.position + Vector2(rect.size.x - (t - rect.size.x - rect.size.y), rect.size.y)
			inward = Vector2(0, -1)
		else:
			pos = rect.position + Vector2(0, rect.size.y - (t - rect.size.x * 2.0 - rect.size.y))
			inward = Vector2(1, 0)
		var s := _rng.randf_range(5.0, 13.0)
		var along := inward.orthogonal() * s
		draw_colored_polygon(PackedVector2Array([pos - along, pos + along, pos + inward * s * 0.9]), Color(0.17, 0.15, 0.13, 0.85))
		draw_colored_polygon(PackedVector2Array([pos - along * 0.6, pos + along * 0.6, pos + inward * s * 0.5]), Color(0.72, 0.69, 0.64, 0.45))
	draw_line(rect.position + Vector2(1, 1.5), rect.position + Vector2(rect.size.x - 1, 1.5), Color(1, 1, 1, 0.22), 2.0)
	draw_rect(rect, WALL_EDGE, false, 1.5)


func _draw_cover(rect: Rect2) -> void:
	var crates := int(rect.position.x / CELL * 7.0 + rect.position.y / CELL * 13.0) % 3 == 0
	draw_rect(Rect2(rect.position + Vector2(0, EXTRUDE), rect.size), SANDBAG_DARK if not crates else Color(0.27, 0.19, 0.11))
	if crates:
		for cy in int(rect.size.y / CELL):
			for cx in int(rect.size.x / CELL):
				var box := Rect2(rect.position + Vector2(cx, cy) * CELL + Vector2(3, 3), Vector2(CELL - 6, CELL - 6))
				var tone := 0.88 + 0.2 * _rng.randf()
				draw_rect(box, Color(WOOD.r * tone, WOOD.g * tone, WOOD.b * tone))
				for k in 3:
					var y := box.position.y + box.size.y * (k + 1) / 4.0
					draw_line(Vector2(box.position.x, y), Vector2(box.end.x, y), Color(0.20, 0.13, 0.07, 0.8), 1.5)
				draw_line(box.position, box.end, Color(0.25, 0.17, 0.09, 0.85), 3.0)
				draw_line(Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), Color(0.25, 0.17, 0.09, 0.85), 3.0)
				draw_rect(box, Color(0.12, 0.08, 0.05), false, 2.0)
				draw_rect(Rect2(box.position + Vector2(8, 8), Vector2(14, 8)), Color(0.78, 0.74, 0.55, 0.55))
	else:
		var rows := maxi(1, int(round(rect.size.y / 20.0)))
		var bag_h := rect.size.y / rows
		for row in rows:
			var cols := maxi(1, int(round(rect.size.x / 34.0)))
			var bag_w := rect.size.x / cols
			var shift := (bag_w * 0.5) if row % 2 == 1 and cols > 1 else 0.0
			for col in cols + (1 if shift > 0.0 else 0):
				var left := rect.position.x + col * bag_w - shift
				var x0 := maxf(left, rect.position.x)
				var x1 := minf(left + bag_w, rect.end.x)
				if x1 - x0 < 6.0:
					continue
				var c := Vector2((x0 + x1) * 0.5, rect.position.y + (row + 0.5) * bag_h)
				var tone := 0.82 + 0.3 * _rng.randf()
				var color := Color(SANDBAG.r * tone, SANDBAG.g * tone, SANDBAG.b * tone)
				var poly := PackedVector2Array()
				for i in 12:
					var a := TAU * i / 12.0
					poly.append(c + Vector2(cos(a) * (x1 - x0) * 0.5, sin(a) * bag_h * 0.5) * 0.98)
				draw_colored_polygon(poly, color)
				draw_polyline(poly + PackedVector2Array([poly[0]]), SANDBAG_DARK, 1.5)
				draw_line(c + Vector2(-(x1 - x0) * 0.22, 0), c + Vector2((x1 - x0) * 0.22, 0), Color(0.3, 0.25, 0.16, 0.6), 1.2)
	for i in int((rect.size.x + rect.size.y) / 90.0) + 1:
		var at := rect.position + Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y)
		_blob(at, _rng.randf_range(8.0, 22.0), Color(SOOT.r, SOOT.g, SOOT.b, 0.22))
	draw_rect(rect, Color(0.10, 0.08, 0.05), false, 1.5)


func _draw_vehicle(rect: Rect2) -> void:
	var horizontal := rect.size.x >= rect.size.y
	var length := rect.size.x if horizontal else rect.size.y
	var width := rect.size.y if horizontal else rect.size.x
	draw_set_transform(rect.get_center(), 0.0 if horizontal else PI * 0.5, Vector2.ONE)
	var half_l := length * 0.5
	var half_w := width * 0.5
	# A scorched patch of ground under it.
	_blob(Vector2.ZERO, length * 0.62, Color(0, 0, 0, 0.22), 0.2, 14)
	# Wheels poking out at the sides.
	for wx in [-half_l * 0.62, half_l * 0.55]:
		for wy in [-half_w + 4.0, half_w - 4.0]:
			draw_circle(Vector2(wx, wy), 12.0, Color(0.04, 0.04, 0.04))
			draw_circle(Vector2(wx, wy), 5.0, Color(0.22, 0.2, 0.18))
	# Shadowed lower body, then the burnt, rusted roof.
	draw_rect(Rect2(Vector2(-half_l, -half_w + EXTRUDE), Vector2(length, width)), Color(0.12, 0.10, 0.09))
	draw_rect(Rect2(Vector2(-half_l, -half_w), Vector2(length, width)), Color(0.27, 0.24, 0.21))
	# Cab at the front with a smashed windscreen.
	var cab := Rect2(Vector2(half_l - length * 0.34, -half_w + 4.0), Vector2(length * 0.34 - 4.0, width - 8.0))
	draw_rect(cab, Color(0.20, 0.18, 0.16))
	draw_rect(Rect2(cab.position + Vector2(cab.size.x * 0.55, 4.0), Vector2(cab.size.x * 0.38, cab.size.y - 8.0)), Color(0.30, 0.38, 0.44))
	for k in 5:  # shatter lines
		var from := cab.position + Vector2(cab.size.x * 0.74, cab.size.y * 0.5)
		draw_line(from, from + Vector2.from_angle(_rng.randf() * TAU) * 14.0, Color(0.85, 0.9, 0.95, 0.7), 1.0)
	# Cargo ribs, rust and char.
	for i in 5:
		var x := -half_l + 8.0 + i * (length * 0.5 / 5.0)
		draw_line(Vector2(x, -half_w + 5.0), Vector2(x, half_w - 5.0), Color(0.15, 0.13, 0.11), 2.0)
	for i in 6:
		_blob(Vector2(_rng.randf_range(-half_l, half_l), _rng.randf_range(-half_w, half_w)), _rng.randf_range(6.0, 16.0), Color(0.48, 0.25, 0.11, 0.8), 0.45, 7)
	for i in 4:
		_blob(Vector2(_rng.randf_range(-half_l, half_l), _rng.randf_range(-half_w, half_w)), _rng.randf_range(10.0, 22.0), Color(0, 0, 0, 0.45), 0.4)
	draw_rect(Rect2(Vector2(-half_l, -half_w), Vector2(length, width)), Color(0.07, 0.06, 0.05), false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_barrel(center: Vector2) -> void:
	var pick := int(center.x / CELL * 5.0 + center.y / CELL * 11.0) % 3
	var body: Color = [Color(0.31, 0.36, 0.22), Color(0.46, 0.24, 0.13), Color(0.27, 0.34, 0.42)][pick]
	draw_circle(center, BARREL_RADIUS, Color(body.r * 0.55, body.g * 0.55, body.b * 0.55))
	draw_circle(center, BARREL_RADIUS - 3.0, body)
	draw_circle(center + Vector2(-3, -3), BARREL_RADIUS - 8.0, Color(body.r * 1.18, body.g * 1.18, body.b * 1.18))
	draw_arc(center, BARREL_RADIUS - 6.0, 0.0, TAU, 24, Color(0, 0, 0, 0.45), 2.0)
	draw_arc(center, BARREL_RADIUS - 12.0, 0.0, TAU, 20, Color(0, 0, 0, 0.35), 2.0)
	draw_circle(center + Vector2(7, 5), 5.0, Color(0.05, 0.05, 0.05, 0.7))
	_blob(center + Vector2(-6, 8), 7.0, Color(0.5, 0.27, 0.12, 0.7), 0.5, 7)
	draw_arc(center, BARREL_RADIUS, 0.0, TAU, 24, Color(0.05, 0.05, 0.05), 1.5)
