extends CanvasLayer
## HUD for the online arena: HP, alive count, Gen status + hint, a status
## line, a short announcement feed, the touch controls, the Blackout
## night-vision tint, and the end-of-match overlay. Purely presentational —
## net_arena.gd feeds it values.

signal return_pressed
signal leave_pressed

const ANNOUNCE_SECONDS := 3.0

@onready var hp_label: Label = $HPLabel
@onready var alive_label: Label = $AliveLabel
@onready var gen_label: Label = $GenLabel
@onready var hint_label: Label = $HintLabel
@onready var status_label: Label = $StatusLabel
@onready var announce_label: Label = $AnnounceLabel
@onready var night_vision: ColorRect = $NightVision
@onready var detonate_button: Control = $DetonateButton
@onready var results: Control = $Results
@onready var result_label: Label = $Results/VBox/ResultLabel
@onready var return_button: Button = $Results/VBox/ReturnButton
@onready var leave_button: Button = $Results/VBox/LeaveButton

var _announce_timer := 0.0


func _ready() -> void:
	results.visible = false
	night_vision.visible = false
	announce_label.text = ""
	gen_label.text = ""
	hint_label.text = ""


func _process(delta: float) -> void:
	if _announce_timer > 0.0:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			announce_label.text = ""


func set_hp(hp: int, max_hp: int) -> void:
	hp_label.text = "HP  %d / %d" % [hp, max_hp]


func set_alive(alive: int, total: int) -> void:
	alive_label.text = "Alive  %d / %d" % [alive, total]


func set_status(text: String) -> void:
	status_label.text = text


func set_night_vision(on: bool) -> void:
	night_vision.visible = on


func announce(text: String) -> void:
	announce_label.text = text
	_announce_timer = ANNOUNCE_SECONDS


func set_gen(me: NetPlayer) -> void:
	if me == null:
		gen_label.text = ""
		hint_label.text = ""
		return
	var gen_name := Gens.label(me.gen)
	var is_bomb := me.gen == "bomb_voyage"
	detonate_button.visible = is_bomb and DisplayServer.is_touchscreen_available()
	match me.gen_state:
		NetPlayer.GenState.READY:
			gen_label.text = "%s  —  READY  [Q]" % gen_name
		NetPlayer.GenState.ACTIVE:
			gen_label.text = "%s  —  %ds left" % [gen_name, ceili(me.gen_timer)]
		NetPlayer.GenState.COOLDOWN:
			gen_label.text = "%s  —  recharging %ds" % [gen_name, ceili(me.gen_timer)]
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
		"bomb_voyage":
			hint = "Bombs out  %d / %d  —  tap Q: proximity, hold Q: manual, E: detonate" % [
				me.bombs_placed, Gens.def("bomb_voyage")["max_bombs"]]
	hint_label.text = hint


func show_results(text: String, can_return: bool) -> void:
	result_label.text = text
	return_button.visible = can_return
	results.visible = true


func _on_return_pressed() -> void:
	return_pressed.emit()


func _on_leave_pressed() -> void:
	leave_pressed.emit()
