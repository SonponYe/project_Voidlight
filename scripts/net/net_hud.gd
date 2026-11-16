extends CanvasLayer
## HUD for the online arena: HP, alive count, a status line, a short
## announcement feed, the touch controls, and the end-of-match overlay.
## Purely presentational — net_arena.gd feeds it values.

signal return_pressed
signal leave_pressed

const ANNOUNCE_SECONDS := 3.0

@onready var hp_label: Label = $HPLabel
@onready var alive_label: Label = $AliveLabel
@onready var status_label: Label = $StatusLabel
@onready var announce_label: Label = $AnnounceLabel
@onready var results: Control = $Results
@onready var result_label: Label = $Results/VBox/ResultLabel
@onready var return_button: Button = $Results/VBox/ReturnButton
@onready var leave_button: Button = $Results/VBox/LeaveButton

var _announce_timer := 0.0


func _ready() -> void:
	results.visible = false
	announce_label.text = ""


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


func announce(text: String) -> void:
	announce_label.text = text
	_announce_timer = ANNOUNCE_SECONDS


func show_results(text: String, can_return: bool) -> void:
	result_label.text = text
	return_button.visible = can_return
	results.visible = true


func _on_return_pressed() -> void:
	return_pressed.emit()


func _on_leave_pressed() -> void:
	leave_pressed.emit()
