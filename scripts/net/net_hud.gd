extends CanvasLayer
## HUD for the online arena: a health bar, alive count and mic status (top
## left), a Gen card with a live cooldown bar (bottom centre), a stacked
## message feed, a damage flash, the Blackout night-vision tint, the minimap,
## the touch controls, a pause menu (Esc or the Menu button) and the
## end-of-match overlay. Purely presentational — net_arena.gd feeds it values.

signal return_pressed
signal leave_pressed

const ANNOUNCE_SECONDS := 3.5
const MAX_ANNOUNCEMENTS := 4
const BAR_BACK := Color(0.11, 0.11, 0.14, 0.95)
const HP_GOOD := Color(0.35, 0.82, 0.5)
const HP_WARN := Color(0.95, 0.72, 0.25)
const HP_BAD := Color(0.9, 0.3, 0.28)
const GEN_READY := Color(0.35, 0.85, 0.55)
const GEN_ACTIVE := Color(0.4, 0.8, 1.0)
const GEN_COOLDOWN := Color(0.5, 0.55, 0.66)

@onready var hp_bar: ProgressBar = $StatusCard/Box/HPRow/HPBar
@onready var hp_text: Label = $StatusCard/Box/HPRow/HPBar/HPText
@onready var hp_label: Label = $StatusCard/Box/HPRow/HPLabel
@onready var alive_label: Label = $StatusCard/Box/AliveLabel
@onready var mic_label: Label = $StatusCard/Box/MicLabel
@onready var gen_label: Label = $GenCard/Box/NameRow/GenLabel
@onready var key_label: Label = $GenCard/Box/NameRow/KeyLabel
@onready var gen_bar: ProgressBar = $GenCard/Box/GenBar
@onready var hint_label: Label = $GenCard/Box/HintLabel
@onready var minimap: NetMinimap = $Minimap
@onready var status_label: Label = $StatusLabel
@onready var announce_box: VBoxContainer = $AnnounceBox
@onready var night_vision: ColorRect = $NightVision
@onready var damage_flash: ColorRect = $DamageFlash
@onready var detonate_button: Control = $DetonateButton
@onready var results: Control = $Results
@onready var result_label: Label = $Results/Panel/VBox/ResultLabel
@onready var flavor_label: Label = $Results/Panel/VBox/FlavorLabel
@onready var return_button: Button = $Results/Panel/VBox/ReturnButton
@onready var leave_button: Button = $Results/Panel/VBox/LeaveButton
@onready var pause_menu: Control = $PauseMenu
@onready var pause_note: Label = $PauseMenu/Panel/VBox/PauseNote
@onready var leave_match_button: Button = $PauseMenu/Panel/VBox/LeaveMatchButton

## Below this share of full health you're "dying": the screen edges go red and
## stay red, the heartbeat starts and the ambient sound swells (see _danger()).
const LOW_HEALTH := 0.4

var _last_hp := -1
var _confirm_leave := false
var _hp := 0
var _max_hp := 1
var _hp_shown := -1.0  # the bar's own value, which eases toward the real one
var _low_overlay: TextureRect
var _ammo_label: Label
var _spare_label: Label
var _prompt_label: Label
var _clock := 0.0


func _ready() -> void:
	add_to_group("net_hud")
	for label in [alive_label, mic_label, gen_label, key_label, hint_label, status_label, hp_label, hp_text]:
		_outline(label)
	_style_bar(hp_bar, HP_GOOD)
	_style_bar(gen_bar, GEN_READY)
	results.visible = false
	pause_menu.visible = false
	night_vision.visible = false
	gen_label.text = ""
	key_label.text = ""
	hint_label.text = ""
	_add_volume_row()
	_add_low_health_overlay()
	_add_extra_labels()


## A "Sound" slider in the pause menu, so anyone can turn the game down without
## leaving the match. The setting is remembered between sessions.
func _add_volume_row() -> void:
	var box := pause_note.get_parent()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "Sound"
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Sfx.volume
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value_changed.connect(Sfx.set_volume)
	slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.play("ui_click"))  # lets you hear the new level
	row.add_child(label)
	row.add_child(slider)
	box.add_child(row)
	box.move_child(row, pause_note.get_index() + 1)


## A red glow around the screen edges, drawn on top of the world but under the
## text. It's built here rather than in the scene because it only needs a texture.
func _add_low_health_overlay() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	gradient.colors = PackedColorArray([Color(0.8, 0.02, 0.02, 0.0), Color(0.8, 0.02, 0.02, 0.0), Color(0.75, 0.02, 0.02, 0.95)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_low_overlay = TextureRect.new()
	_low_overlay.texture = texture
	_low_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_low_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_low_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_overlay.modulate.a = 0.0
	add_child(_low_overlay)
	move_child(_low_overlay, 1)  # just above the soft vignette, below everything else


## The ammo count, the spare-Gen line and the "what can I do here" prompt. Built
## in code beside the labels the scene already has.
func _add_extra_labels() -> void:
	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", 14)
	_outline(_ammo_label)
	var box := hp_label.get_parent().get_parent()  # StatusCard/Box
	box.add_child(_ammo_label)
	box.move_child(_ammo_label, hp_label.get_parent().get_index() + 1)
	_spare_label = Label.new()
	_spare_label.add_theme_font_size_override("font_size", 13)
	_outline(_spare_label)
	hint_label.get_parent().add_child(_spare_label)
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.62))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -330.0
	_prompt_label.offset_right = 330.0
	_prompt_label.offset_top = -158.0
	_prompt_label.offset_bottom = -132.0
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline(_prompt_label)
	add_child(_prompt_label)


func set_ammo(me: NetPlayer) -> void:
	if me == null:
		_ammo_label.text = ""
		return
	_ammo_label.text = "Ammo  %d" % me.ammo
	_ammo_label.add_theme_color_override("font_color", HP_BAD if me.ammo <= 5 else Color(0.92, 0.9, 0.78))


func set_prompt(text: String) -> void:
	_prompt_label.text = text


## 0 while healthy, rising from about 0.3 just under the threshold to 1 at no health.
func _danger() -> float:
	if _hp <= 0:
		return 0.0
	var ratio := float(_hp) / float(maxi(_max_hp, 1))
	if ratio > LOW_HEALTH:
		return 0.0
	return 0.3 + 0.7 * (1.0 - ratio / LOW_HEALTH)


func _process(delta: float) -> void:
	_clock += delta
	if _hp_shown >= 0.0:
		# The bar slides down (or up, when healing) instead of jumping.
		_hp_shown = move_toward(_hp_shown, float(_hp), delta * _max_hp * 0.9)
		hp_bar.value = _hp_shown
	var danger := _danger()
	var beat := 0.5 + 0.5 * sin(_clock * TAU * (1.1 + 0.9 * danger))  # faster the closer to death
	_low_overlay.modulate.a = danger * (0.5 + 0.5 * beat)
	hp_bar.modulate.a = 1.0 if danger == 0.0 else 0.6 + 0.4 * beat
	Sfx.set_danger(danger)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not results.visible:
		_set_menu(not pause_menu.visible)


func _outline(label: Label) -> void:
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))


func _style_bar(bar: ProgressBar, fill: Color) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = BAR_BACK
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", back)
	_set_fill(bar, fill)


func _set_fill(bar: ProgressBar, color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)


# ---------------------------------------------------------------------------
# Values fed by the arena
# ---------------------------------------------------------------------------

func set_hp(hp: int, max_hp: int) -> void:
	_hp = hp
	_max_hp = max_hp
	if _hp_shown < 0.0:
		_hp_shown = float(hp)
	hp_bar.max_value = max_hp
	hp_text.text = "%d" % hp
	var ratio := float(hp) / float(maxi(max_hp, 1))
	_set_fill(hp_bar, HP_GOOD if ratio > 0.6 else (HP_WARN if ratio > LOW_HEALTH else HP_BAD))
	if _last_hp >= 0 and hp < _last_hp:
		_flash_damage()
	_last_hp = hp


func _flash_damage() -> void:
	damage_flash.color.a = 0.38
	create_tween().tween_property(damage_flash, "color:a", 0.0, 0.4)


func set_alive(alive: int, total: int) -> void:
	alive_label.text = "Alive  %d / %d" % [alive, total]


func set_alive_text(text: String) -> void:
	alive_label.text = text


func update_minimap(map: NetMap, me: NetPlayer, players: Array, bombs: Array, pickups: Array) -> void:
	minimap.update_view(map, me, players, bombs, pickups)


func set_mic(text: String) -> void:
	mic_label.text = text


func set_status(text: String) -> void:
	status_label.text = text


func set_night_vision(on: bool) -> void:
	night_vision.visible = on


## Messages stack and fade on their own, so several can be read at once.
func announce(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	_outline(label)
	announce_box.add_child(label)
	while announce_box.get_child_count() > MAX_ANNOUNCEMENTS:
		announce_box.get_child(0).queue_free()
		announce_box.remove_child(announce_box.get_child(0))
	var tween := label.create_tween()
	tween.tween_interval(ANNOUNCE_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func set_gen(me: NetPlayer) -> void:
	if me == null:
		gen_label.text = ""
		key_label.text = ""
		hint_label.text = ""
		_spare_label.text = ""
		return
	_spare_label.text = _spare_text(me)
	var def := Gens.def(me.gen)
	gen_label.text = Gens.label(me.gen)
	detonate_button.visible = me.gen == "bomb_voyage" and DisplayServer.is_touchscreen_available()
	match me.gen_state:
		NetPlayer.GenState.READY:
			key_label.text = "[Q]  ready"
			gen_bar.value = 1.0
			_set_fill(gen_bar, GEN_READY)
		NetPlayer.GenState.ACTIVE:
			key_label.text = "%ds" % ceili(me.gen_timer)
			gen_bar.value = clampf(me.gen_timer / maxf(float(def["duration"]), 0.01), 0.0, 1.0)
			_set_fill(gen_bar, GEN_ACTIVE)
		NetPlayer.GenState.COOLDOWN:
			key_label.text = "recharging  %ds" % ceili(me.gen_timer)
			gen_bar.value = clampf(1.0 - me.gen_timer / maxf(float(def["cooldown"]), 0.01), 0.0, 1.0)
			_set_fill(gen_bar, GEN_COOLDOWN)
	var hint := ""
	match me.gen:
		"camouflage":
			if me.camouflaged:
				hint = "Disguised. You can't shoot — press Q to drop it."
		"shield":
			if me.shield_hp > 0:
				hint = "Shield  %d hits left" % me.shield_hp
		"poltergeist":
			if me.poltergeist_target != 0:
				hint = "Haunting %s" % Network.player_name(me.poltergeist_target)
		"blackout":
			if me.gen_state == NetPlayer.GenState.ACTIVE:
				hint = "Lights out. Only you can see."
		"decoy":
			if me.gen_state == NetPlayer.GenState.ACTIVE:
				hint = "Your decoy is hunting the nearest enemy."
		"bomb_voyage":
			hint = "Bombs  %d / %d   ·   tap Q proximity  ·  hold Q manual  ·  E detonate" % [
				me.bombs_placed, def["max_bombs"]]
	hint_label.text = hint


func _spare_text(me: NetPlayer) -> String:
	if me.spare_gen == "":
		return ""
	var state := "ready"
	match me.spare_state:
		NetPlayer.GenState.COOLDOWN:
			state = "recharging  %ds" % ceili(me.spare_timer)
		NetPlayer.GenState.ACTIVE:
			state = "active"
	return "Spare: %s  (%s)    [R] swap" % [Gens.label(me.spare_gen), state]


# ---------------------------------------------------------------------------
# Overlays
# ---------------------------------------------------------------------------

func show_results(text: String, can_return: bool, flavor := "") -> void:
	pause_menu.visible = false
	result_label.text = text
	flavor_label.text = flavor
	flavor_label.visible = flavor != ""
	return_button.visible = can_return
	results.visible = true


## While a menu is up the match goes on (it can't pause), but clicks meant for
## the menu must not fire your gun or use your Gen.
func blocks_play() -> bool:
	return pause_menu.visible or results.visible


func _set_menu(open: bool) -> void:
	pause_menu.visible = open
	_confirm_leave = false
	leave_match_button.text = _leave_text()
	if Network.is_host() and not Network.dedicated:
		pause_note.text = "You're hosting: leaving ends the match for everyone."
	else:
		pause_note.text = "The match keeps going — you can still be hit."


func _leave_text() -> String:
	return "End the match for everyone" if Network.is_host() and not Network.dedicated else "Leave the match"


## The host IS the server of a hosted game, so their leaving closes the room.
## Ask twice before doing that.
func _on_leave_match_pressed() -> void:
	if Network.is_host() and not Network.dedicated and not _confirm_leave:
		_confirm_leave = true
		leave_match_button.text = "Really end it for everyone?"
		get_tree().create_timer(4.0).timeout.connect(func():
			if _confirm_leave and is_instance_valid(leave_match_button):
				_confirm_leave = false
				leave_match_button.text = _leave_text())
		return
	leave_pressed.emit()


func _on_menu_pressed() -> void:
	_set_menu(not pause_menu.visible)


func _on_resume_pressed() -> void:
	_set_menu(false)


func _on_mic_pressed() -> void:
	Voice.set_muted(not Voice.muted)


func _on_return_pressed() -> void:
	return_pressed.emit()


func _on_leave_pressed() -> void:
	leave_pressed.emit()
