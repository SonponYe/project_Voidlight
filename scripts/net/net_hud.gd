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

var _last_hp := -1
var _confirm_leave := false


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
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_text.text = "%d / %d" % [hp, max_hp]
	var ratio := float(hp) / float(maxi(max_hp, 1))
	_set_fill(hp_bar, HP_GOOD if ratio > 0.6 else (HP_WARN if ratio > 0.3 else HP_BAD))
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


func update_minimap(map: NetMap, me: NetPlayer, players: Array, bombs: Array) -> void:
	minimap.update_view(map, me, players, bombs)


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
		return
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
