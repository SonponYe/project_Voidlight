extends Control
## On-screen fire button — only shown on touchscreens. Handles touch input
## manually via _input + Input.action_press/release (same pattern as
## virtual_joystick.gd/touch_aim_pad.gd) rather than the engine's
## TouchScreenButton, which is Node2D-based and can't use the anchor-based
## responsive layout the rest of the HUD relies on.

@export var action_name: String = "shoot"
## The picture shown on the button (white glyphs from the Kenney pack).
@export var icon: Texture2D
## Words on the button instead of a picture (for the smaller extra buttons).
@export var label_text := ""
## Width and height of the round button, in pixels.
@export var diameter := 90.0

@onready var panel: Panel = $Panel

var _touch_index := -1


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()
	panel.custom_minimum_size = Vector2(diameter, diameter)
	panel.size = Vector2(diameter, diameter)
	var glyph := get_node_or_null("Panel/Icon") as TextureRect
	if glyph:
		glyph.texture = icon
		glyph.visible = label_text == ""
	if label_text != "":
		var label := Label.new()
		label.text = label_text
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_constant_override("outline_size", 5)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		panel.add_child(label)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and panel.get_global_rect().has_point(event.position):
			_touch_index = event.index
			Input.action_press(action_name)
			if panel:
				panel.modulate.a = 1.5
	elif event.index == _touch_index:
		_touch_index = -1
		Input.action_release(action_name)
		if panel:
			panel.modulate.a = 1.0
