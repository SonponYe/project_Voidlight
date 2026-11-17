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
@onready var gen_radial: RadialPicker = $VBox/RoomPanel/GenRadial
@onready var gen_blurb: Label = $VBox/RoomPanel/GenBlurb
@onready var ffa_button: Button = $VBox/RoomPanel/ModeRow/FFAButton
@onready var team_mode_button: Button = $VBox/RoomPanel/ModeRow/TeamButton
@onready var team_radial: RadialPicker = $VBox/RoomPanel/TeamRadial

const SELECTED_TINT := Color(1.3, 1.2, 0.7)
const UNSELECTED_TINT := Color(1, 1, 1)

var _connecting := false


func _ready() -> void:
	name_edit.text = Network.local_name
	_build_pickers()
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
	start_button.visible = Network.is_leader()
	_refresh_room()


## Built from Gens.DEFS so adding a Gen is a table edit, not a scene edit.
func _build_pickers() -> void:
	var gens := []
	for key in Gens.DEFS:
		gens.append({"key": key, "label": Gens.DEFS[key]["label"], "disabled": not Gens.DEFS[key]["available"]})
	gen_radial.hub_prefix = "Gen:  "
	gen_radial.set_items(gens)
	gen_radial.picked.connect(_on_gen_picked)

	team_radial.hub_prefix = "Team:  "
	team_radial.radius = 62.0
	team_radial.set_items([
		{"key": "1", "label": Network.team_name(1)},
		{"key": "2", "label": Network.team_name(2)},
	])
	team_radial.picked.connect(_on_team_picked)


func _on_gen_picked(key: String) -> void:
	Network.select_gen(key)
	_refresh_gen_buttons()


func _on_team_picked(key: String) -> void:
	Network.select_team(int(key))


func _refresh_gen_buttons() -> void:
	gen_radial.set_selected(Network.local_gen)
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
	start_button.visible = Network.is_leader()
	var where := ""
	if Network.is_host() and not Network.dedicated:
		var lan := _lan_address()
		var code := Network.format_room_code(Network.encode_room_code(lan))
		where = "Friends on your Wi-Fi join with:  %s" % lan
		if code != "":
			where += "   or code  %s" % code
	if Network.is_leader():
		var enough := Network.can_start()
		start_button.disabled = not enough
		if enough:
			status_label.text = "Press Start when everyone's in.   %s" % where
		elif Network.is_team_mode():
			status_label.text = "Both teams need at least one player.   %s" % where
		else:
			status_label.text = "Waiting for at least one more player...   %s" % where
		status_label.text = status_label.text.strip_edges()
	else:
		status_label.text = "Waiting for %s to start the match..." % Network.player_name(Network.leader_id())


## The host's private IPv4 on the local network — what a friend on the
## same Wi-Fi types into the Host IP box. Public-internet play needs the
## host's public IP plus port forwarding (or the hosted server, later).
func _lan_address() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") \
				or (address.begins_with("172.") and int(address.split(".")[1]) in range(16, 32)):
			return address
	return "127.0.0.1 (no LAN address found)"


func _refresh_mode_buttons() -> void:
	var leader := Network.is_leader()
	ffa_button.disabled = not leader
	team_mode_button.disabled = not leader
	var team_mode := Network.is_team_mode()
	ffa_button.modulate = UNSELECTED_TINT if team_mode else SELECTED_TINT
	team_mode_button.modulate = SELECTED_TINT if team_mode else UNSELECTED_TINT
	team_radial.visible = team_mode
	if team_mode:
		team_radial.set_selected(str(Network.player_team(multiplayer.get_unique_id())))


func _on_ffa_pressed() -> void:
	Network.set_match_mode("ffa")


func _on_team_mode_pressed() -> void:
	Network.set_match_mode("team")


func _on_host_pressed() -> void:
	Network.set_local_name(name_edit.text)
	var err := Network.host()
	if err != OK:
		_show_connect("Couldn't host on port %d (error %d). Is another game already hosting?" % [Network.DEFAULT_PORT, err])
		return
	_show_room()


func _on_join_pressed() -> void:
	Network.set_local_name(name_edit.text)
	var target := Network.parse_join_target(address_edit.text)
	if target.is_empty():
		_show_connect("Enter the host's IP address, room code (like K7M2-QP4X) or wss:// address.")
		return
	var err := Network.join(target["address"], target["port"], target.get("tls", false))
	if err != OK:
		_show_connect("Couldn't start connecting (error %d)." % err)
		return
	_connecting = true
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Connecting to %s..." % target["address"]


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
