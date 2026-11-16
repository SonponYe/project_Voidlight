extends Control
## Online lobby: host a room or join one by address, then wait in the room
## until the host starts the match. Bare-bones on purpose — no matchmaking,
## no room codes, no Gen picking yet. Those layer onto this once a real
## online match is playable end to end.

@export_file("*.tscn") var main_menu_path := "res://scenes/ui/main_menu.tscn"

@onready var connect_panel: VBoxContainer = $VBox/ConnectPanel
@onready var room_panel: VBoxContainer = $VBox/RoomPanel
@onready var name_edit: LineEdit = $VBox/ConnectPanel/NameRow/NameEdit
@onready var address_edit: LineEdit = $VBox/ConnectPanel/AddressRow/AddressEdit
@onready var host_button: Button = $VBox/ConnectPanel/ButtonRow/HostButton
@onready var join_button: Button = $VBox/ConnectPanel/ButtonRow/JoinButton
@onready var status_label: Label = $VBox/StatusLabel
@onready var room_title: Label = $VBox/RoomPanel/RoomTitle
@onready var player_list: VBoxContainer = $VBox/RoomPanel/PlayerList
@onready var start_button: Button = $VBox/RoomPanel/RoomButtons/StartButton
@onready var leave_button: Button = $VBox/RoomPanel/RoomButtons/LeaveButton
@onready var gen_row: HBoxContainer = $VBox/RoomPanel/GenRow
@onready var gen_blurb: Label = $VBox/RoomPanel/GenBlurb
@onready var ffa_button: Button = $VBox/RoomPanel/ModeRow/FFAButton
@onready var team_mode_button: Button = $VBox/RoomPanel/ModeRow/TeamButton
@onready var team_row: HBoxContainer = $VBox/RoomPanel/TeamRow
@onready var team_a_button: Button = $VBox/RoomPanel/TeamRow/TeamAButton
@onready var team_b_button: Button = $VBox/RoomPanel/TeamRow/TeamBButton

const SELECTED_TINT := Color(1.3, 1.2, 0.7)
const UNSELECTED_TINT := Color(1, 1, 1)

var _connecting := false
var _gen_buttons: Dictionary = {}


func _ready() -> void:
	name_edit.text = Network.local_name
	_build_gen_buttons()
	Network.player_list_changed.connect(_refresh_room)
	Network.connection_failed.connect(_on_connection_failed)
	Network.disconnected_from_server.connect(_on_disconnected)
	Network.rejected.connect(_on_rejected)
	multiplayer.connected_to_server.connect(_on_connected)

	# Coming back from a match keeps the connection alive, so land straight
	# in the room instead of the connect form.
	if Network.is_connected_to_match():
		_show_room()
	else:
		_show_connect("")


func _exit_tree() -> void:
	if Network.player_list_changed.is_connected(_refresh_room):
		Network.player_list_changed.disconnect(_refresh_room)
	if Network.connection_failed.is_connected(_on_connection_failed):
		Network.connection_failed.disconnect(_on_connection_failed)
	if Network.disconnected_from_server.is_connected(_on_disconnected):
		Network.disconnected_from_server.disconnect(_on_disconnected)
	if Network.rejected.is_connected(_on_rejected):
		Network.rejected.disconnect(_on_rejected)
	if multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.disconnect(_on_connected)


func _show_connect(message: String) -> void:
	_connecting = false
	connect_panel.visible = true
	room_panel.visible = false
	host_button.disabled = false
	join_button.disabled = false
	status_label.text = message


func _show_room() -> void:
	_connecting = false
	connect_panel.visible = false
	room_panel.visible = true
	start_button.visible = Network.is_host()
	_refresh_room()


## Built from Gens.DEFS so adding a Gen is a table edit, not a scene edit.
func _build_gen_buttons() -> void:
	for key in Gens.DEFS:
		var def: Dictionary = Gens.DEFS[key]
		var button := Button.new()
		button.text = def["label"]
		button.disabled = not def["available"]
		button.pressed.connect(_on_gen_pressed.bind(key))
		gen_row.add_child(button)
		_gen_buttons[key] = button


func _on_gen_pressed(key: String) -> void:
	Network.select_gen(key)
	_refresh_gen_buttons()


func _refresh_gen_buttons() -> void:
	for key in _gen_buttons:
		_gen_buttons[key].modulate = SELECTED_TINT if key == Network.local_gen else UNSELECTED_TINT
	gen_blurb.text = Gens.def(Network.local_gen)["blurb"]


func _refresh_room() -> void:
	if not room_panel.visible:
		return
	_refresh_gen_buttons()
	_refresh_mode_buttons()
	for child in player_list.get_children():
		child.queue_free()
	var ids := Network.players.keys()
	ids.sort()
	var team_counts := {1: 0, 2: 0}
	for id in ids:
		var label := Label.new()
		var tag := ""
		if id == 1:
			tag = "  (host)"
		if id == multiplayer.get_unique_id():
			tag += "  (you)"
		var side := ""
		if Network.is_team_mode():
			var team := Network.player_team(id)
			side = "[%s]  " % ("A" if team == 1 else "B")
			if team_counts.has(team):
				team_counts[team] += 1
		label.text = "%s%s  —  %s%s" % [side, Network.player_name(id), Gens.label(Network.player_gen(id)), tag]
		player_list.add_child(label)
	room_title.text = "ROOM  —  %d / %d players" % [ids.size(), Network.MAX_PLAYERS]
	if Network.is_host():
		var enough := ids.size() >= 2
		if Network.is_team_mode():
			enough = team_counts[1] > 0 and team_counts[2] > 0
		start_button.disabled = not enough
		if enough:
			status_label.text = "Press Start when everyone's in."
		elif Network.is_team_mode():
			status_label.text = "Both teams need at least one player."
		else:
			status_label.text = "Waiting for at least one more player..."
	else:
		status_label.text = "Waiting for the host to start the match..."


func _refresh_mode_buttons() -> void:
	var host := Network.is_host()
	ffa_button.disabled = not host
	team_mode_button.disabled = not host
	var team_mode := Network.is_team_mode()
	ffa_button.modulate = UNSELECTED_TINT if team_mode else SELECTED_TINT
	team_mode_button.modulate = SELECTED_TINT if team_mode else UNSELECTED_TINT
	team_row.visible = team_mode
	if team_mode:
		var mine := Network.player_team(multiplayer.get_unique_id())
		team_a_button.modulate = SELECTED_TINT if mine == 1 else UNSELECTED_TINT
		team_b_button.modulate = SELECTED_TINT if mine == 2 else UNSELECTED_TINT


func _on_ffa_pressed() -> void:
	Network.set_match_mode("ffa")


func _on_team_mode_pressed() -> void:
	Network.set_match_mode("team")


func _on_team_a_pressed() -> void:
	Network.select_team(1)


func _on_team_b_pressed() -> void:
	Network.select_team(2)


func _on_host_pressed() -> void:
	Network.set_local_name(name_edit.text)
	var err := Network.host()
	if err != OK:
		_show_connect("Couldn't host on port %d (error %d). Is another game already hosting?" % [Network.DEFAULT_PORT, err])
		return
	_show_room()


func _on_join_pressed() -> void:
	Network.set_local_name(name_edit.text)
	var address := address_edit.text.strip_edges()
	if address == "":
		_show_connect("Enter the host's address first.")
		return
	var err := Network.join(address)
	if err != OK:
		_show_connect("Couldn't start connecting (error %d)." % err)
		return
	_connecting = true
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Connecting to %s..." % address


func _on_connected() -> void:
	_show_room()


func _on_connection_failed() -> void:
	_show_connect("Couldn't reach %s. Check the address and that the host is running." % address_edit.text.strip_edges())


func _on_rejected(reason: String) -> void:
	status_label.text = reason


func _on_disconnected() -> void:
	var reason := Network.last_reject_reason
	_show_connect(reason if reason != "" else "Disconnected from host.")


func _on_start_pressed() -> void:
	Network.start_match()


func _on_leave_pressed() -> void:
	Network.leave()
	_show_connect("")


func _on_back_pressed() -> void:
	Network.leave()
	get_tree().change_scene_to_file(main_menu_path)
