extends Control
class_name RadialPicker
## A hub button that pops its options out in a ring around it. The ring
## overlays neighbouring UI (it takes no layout space of its own), so it can
## sit in a tight column. Built from set_items() so the options come from
## data (Gens.DEFS, the team list) rather than the scene.

signal picked(key: String)

@export var radius := 120.0
@export var item_size := Vector2(116, 38)
@export var hub_size := Vector2(190, 42)
@export var open_time := 0.22
@export var hub_prefix := ""

const SELECTED_TINT := Color(1.3, 1.2, 0.7)
const BACKDROP_COLOR := Color(0.04, 0.04, 0.07)

var selected_key := ""
var is_open := false
## Eased 0..1 while opening/closing; drives the dark disc behind the ring.
var backdrop := 0.0:
	set(value):
		backdrop = value
		queue_redraw()

var _items: Array = []  # [{key, label, disabled}]
var _buttons: Dictionary = {}  # key -> Button
var _hub: Button
var _tween: Tween


func _ready() -> void:
	z_index = 10  # the ring must draw over the controls around us
	custom_minimum_size = Vector2(hub_size.x, hub_size.y + 6.0)
	_hub = Button.new()
	_hub.size = hub_size
	_hub.pressed.connect(toggle)
	add_child(_hub)
	resized.connect(_layout)
	_layout()
	_refresh()


func set_items(items: Array) -> void:
	for b in _buttons.values():
		b.queue_free()
	_buttons.clear()
	_items = items
	for item in items:
		var b := Button.new()
		b.text = item["label"]
		b.disabled = item.get("disabled", false)
		b.size = item_size
		b.pivot_offset = item_size * 0.5
		b.visible = false
		b.modulate.a = 0.0
		b.pressed.connect(_on_item_pressed.bind(item["key"]))
		add_child(b)
		_buttons[item["key"]] = b
	is_open = false
	_layout()
	_refresh()


func set_selected(key: String) -> void:
	selected_key = key
	_refresh()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open or _items.is_empty():
		return
	is_open = true
	_animate(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_animate(false)


func _center() -> Vector2:
	return size * 0.5 if size != Vector2.ZERO else hub_size * 0.5


func _ring_pos(index: int) -> Vector2:
	var angle := -PI * 0.5 + TAU * float(index) / float(maxi(_items.size(), 1))
	return _center() + Vector2.from_angle(angle) * radius - item_size * 0.5


func _layout() -> void:
	if _hub == null:
		return
	_hub.position = _center() - hub_size * 0.5
	var i := 0
	for item in _items:
		var b: Button = _buttons[item["key"]]
		b.position = _ring_pos(i) if is_open else _center() - item_size * 0.5
		i += 1
	queue_redraw()


func _refresh() -> void:
	if _hub == null:
		return
	var label := selected_key
	for item in _items:
		if item["key"] == selected_key:
			label = item["label"]
	_hub.text = "%s%s  ▾" % [hub_prefix, label] if label != "" else "%sChoose  ▾" % hub_prefix
	for key in _buttons:
		var b: Button = _buttons[key]
		var tint := SELECTED_TINT if key == selected_key else Color.WHITE
		b.modulate = Color(tint.r, tint.g, tint.b, b.modulate.a)  # keep the animated alpha


func _animate(opening: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var i := 0
	for item in _items:
		var b: Button = _buttons[item["key"]]
		if opening:
			b.visible = true
		var delay := i * 0.025 if opening else 0.0
		var to_pos := _ring_pos(i) if opening else _center() - item_size * 0.5
		var to_scale := Vector2.ONE if opening else Vector2(0.3, 0.3)
		var to_alpha := 1.0 if opening else 0.0
		var pos_tween := _tween.tween_property(b, "position", to_pos, open_time).set_delay(delay)
		pos_tween.set_trans(Tween.TRANS_BACK if opening else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(b, "scale", to_scale, open_time).set_delay(delay)
		_tween.tween_property(b, "modulate:a", to_alpha, open_time).set_delay(delay)
		i += 1
	_tween.tween_property(self, "backdrop", 1.0 if opening else 0.0, open_time)
	if not opening:
		_tween.chain().tween_callback(_hide_buttons)


func _hide_buttons() -> void:
	if is_open:
		return
	for b in _buttons.values():
		b.visible = false


func _on_item_pressed(key: String) -> void:
	selected_key = key
	_refresh()
	close()
	picked.emit(key)


func _draw() -> void:
	if backdrop <= 0.001:
		return
	var reach := radius + maxf(item_size.x, item_size.y) * 0.5 + 10.0
	draw_circle(_center(), reach, Color(BACKDROP_COLOR, 0.92 * backdrop))
	draw_arc(_center(), reach, 0.0, TAU, 48, Color(1, 1, 1, 0.12 * backdrop), 1.5)
