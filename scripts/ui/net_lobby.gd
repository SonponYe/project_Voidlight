extends Control
## Online lobby, as two clear steps: first who you are and whether to host or
## join, then the room itself (players on the left, your Gen and the mode on
## the right, one Start button for whoever leads).

@export_file("*.tscn") var main_menu_path := "res://scenes/ui/main_menu.tscn"

@onready var connect_panel: VBoxContainer = $Main/ConnectPanel
@onready var room_panel: VBoxContainer = $Main/RoomPanel
@onready var status_label: Label = $Main/StatusLabel
@onready var name_edit: LineEdit = $Main/ConnectPanel/NameRow/NameEdit
@onready var choices: HBoxContainer = $Main/ConnectPanel/Choices
@onready var host_button: Button = $Main/ConnectPanel/Choices/HostButton
@onready var join_button: Button = $Main/ConnectPanel/Choices/JoinButton
@onready var join_panel: VBoxContainer = $Main/ConnectPanel/JoinPanel
@onready var address_edit: LineEdit = $Main/ConnectPanel/JoinPanel/AddressEdit
@onready var connect_button: Button = $Main/ConnectPanel/JoinPanel/JoinButtons/ConnectButton
@onready var code_card: PanelContainer = $Main/RoomPanel/CodeCard
@onready var code_label: Label = $Main/RoomPanel/CodeCard/CodeBox/CodeLabel
@onready var code_hint: Label = $Main/RoomPanel/CodeCard/CodeBox/CodeHint
@onready var room_title: Label = $Main/RoomPanel/Columns/PlayersCard/PlayersBox/RoomTitle
@onready var player_list: VBoxContainer = $Main/RoomPanel/Columns/PlayersCard/PlayersBox/PlayerList
@onready var gen_radial: RadialPicker = $Main/RoomPanel/Columns/SideColumn/GenCard/GenBox/GenRadial
@onready var gen_blurb: Label = $Main/RoomPanel/Columns/SideColumn/GenCard/GenBox/GenBlurb
@onready var ffa_button: Button = $Main/RoomPanel/Columns/SideColumn/ModeCard/ModeBox/ModeRow/FFAButton
@onready var team_mode_button: Button = $Main/RoomPanel/Columns/SideColumn/ModeCard/ModeBox/ModeRow/TeamButton
@onready var mode_note: Label = $Main/RoomPanel/Columns/SideColumn/ModeCard/ModeBox/ModeNote
@onready var team_radial: RadialPicker = $Main/RoomPanel/Columns/SideColumn/ModeCard/ModeBox/TeamRadial
@onready var start_button: Button = $Main/RoomPanel/FooterBox/Footer/StartButton
@onready var mic_button: Button = $Main/RoomPanel/FooterBox/Footer/MicButton
@onready var leave_button: Button = $Main/RoomPanel/FooterBox/Footer/LeaveButton
@onready var start_hint: Label = $Main/RoomPanel/FooterBox/StartHint

const SELECTED_TINT := Color(1.3, 1.2, 0.7)
const UNSELECTED_TINT := Color(1, 1, 1)
const DIM_TEXT := Color(0.72, 0.78, 0.9)
const TALK_COLOR := Color(0.45, 1.0, 0.6)

var _connecting := false
var _talk_timer := 0.0


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


# ---------------------------------------------------------------------------
# Step 1: connect
# ---------------------------------------------------------------------------

## keep_join: stay on the code field after a failed attempt so a typo can be fixed.
func _show_connect(message: String, keep_join := false) -> void:
	_connecting = false
	connect_panel.visible = true
	room_panel.visible = false
	choices.visible = not keep_join
	join_panel.visible = keep_join
	host_button.disabled = false
	join_button.disabled = false
	connect_button.disabled = false
	status_label.text = message


func _on_host_pressed() -> void:
	Network.set_local_name(name_edit.text)
	var err := Network.host()
	if err != OK:
		_show_connect("Couldn't host on port %d (error %d). Is another game already hosting?" % [Network.DEFAULT_PORT, err])
		return
	_show_room()


## "Join a game" only reveals the code field; the actual join is Connect.
func _on_join_choice_pressed() -> void:
	status_label.text = ""
	choices.visible = false
	join_panel.visible = true
	address_edit.grab_focus()
	address_edit.select_all()


func _on_cancel_join_pressed() -> void:
	_show_connect("")


func _on_join_pressed() -> void:
	Network.set_local_name(name_edit.text)
	var target := Network.parse_join_target(address_edit.text)
	if target.is_empty():
		_show_connect("That doesn't look like a room code or address. Check it and try again.", true)
		return
	var err := Network.join(target["address"], target["port"], target.get("tls", false))
	if err != OK:
		_show_connect("Couldn't start connecting (error %d)." % err, true)
		return
	_connecting = true
	connect_button.disabled = true
	status_label.text = "Connecting to %s..." % target["address"]


func _on_connected() -> void:
	_show_room()


func _on_connection_failed() -> void:
	_show_connect("Couldn't reach %s. Check the code and that the host is running." % address_edit.text.strip_edges(), true)


func _on_rejected(reason: String) -> void:
	status_label.text = reason


func _on_disconnected() -> void:
	var reason := Network.last_reject_reason
	_show_connect(reason if reason != "" else "Disconnected from the host.", true)


# ---------------------------------------------------------------------------
# Step 2: the room
# ---------------------------------------------------------------------------

func _show_room() -> void:
	_connecting = false
	connect_panel.visible = false
	room_panel.visible = true
	status_label.text = ""
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
	_update_mic()
	_refresh_gen_buttons()
	_refresh_mode_buttons()

	for child in player_list.get_children():
		child.queue_free()
	var ids := Network.players.keys()
	ids.sort_custom(func(a, b): return Network.players[a].get("order", 0) < Network.players[b].get("order", 0))
	for id in ids:
		_add_player_row(id)
	room_title.text = "PLAYERS   %d / %d" % [ids.size(), Network.MAX_PLAYERS]

	# The room code, for a host who is also a player (a dedicated server has
	# its own address, which players already used to get here).
	var show_code := Network.is_host() and not Network.dedicated
	code_card.visible = show_code
	if show_code:
		var lan := _lan_address()
		var code := Network.format_room_code(Network.encode_room_code(lan))
		code_label.text = code if code != "" else lan
		code_hint.text = "Friends on your Wi-Fi enter this code%s" % (("  (or the address %s)" % lan) if code != "" else "")

	var leader_name := Network.player_name(Network.leader_id())
	start_button.visible = Network.is_leader()
	if Network.is_leader():
		var can := Network.can_start()
		start_button.disabled = not can
		if can:
			start_hint.text = ""
		elif Network.is_team_mode():
			start_hint.text = "Both teams need at least one player."
		else:
			start_hint.text = "Waiting for another player to join..."
	else:
		start_hint.text = "Waiting for %s to start the match..." % leader_name


func _add_player_row(id: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_meta("pid", id)

	var side := ""
	if Network.is_team_mode():
		side = "[%s]  " % ("A" if Network.player_team(id) == 1 else "B")
	var name_label := Label.new()
	name_label.text = side + Network.player_name(id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 19)
	row.add_child(name_label)

	var talk := Label.new()
	talk.name = "Talk"
	talk.text = "talking"
	talk.add_theme_color_override("font_color", TALK_COLOR)
	talk.add_theme_font_size_override("font_size", 13)
	talk.visible = false
	row.add_child(talk)

	var gen_label := Label.new()
	gen_label.text = Gens.label(Network.player_gen(id))
	gen_label.add_theme_color_override("font_color", DIM_TEXT)
	row.add_child(gen_label)

	var tags := []
	if id == Network.leader_id():
		tags.append("LEADER")
	if Network.has_peer() and id == multiplayer.get_unique_id():
		tags.append("YOU")
	var tag := Label.new()
	tag.text = "  ".join(tags)
	tag.custom_minimum_size = Vector2(110, 0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	tag.add_theme_font_size_override("font_size", 13)
	row.add_child(tag)

	player_list.add_child(row)


func _refresh_mode_buttons() -> void:
	var leader := Network.is_leader()
	ffa_button.disabled = not leader
	team_mode_button.disabled = not leader
	var team_mode := Network.is_team_mode()
	ffa_button.modulate = UNSELECTED_TINT if team_mode else SELECTED_TINT
	team_mode_button.modulate = SELECTED_TINT if team_mode else UNSELECTED_TINT
	mode_note.text = "" if leader else "Only %s can change this." % Network.player_name(Network.leader_id())
	team_radial.visible = team_mode
	if team_mode:
		team_radial.set_selected(str(Network.player_team(multiplayer.get_unique_id())))


## The host's private IPv4 on the local network — what a friend on the same
## Wi-Fi uses. Public-internet play needs the hosted server (or port forwarding).
func _lan_address() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") \
				or (address.begins_with("172.") and int(address.split(".")[1]) in range(16, 32)):
			return address
	return "127.0.0.1"


func _on_ffa_pressed() -> void:
	Network.set_match_mode("ffa")


func _on_team_mode_pressed() -> void:
	Network.set_match_mode("team")


## Show who is talking next to their name in the room.
func _process(delta: float) -> void:
	_talk_timer -= delta
	if _talk_timer > 0.0 or not room_panel.visible:
		return
	_talk_timer = 0.2
	_update_mic()
	for row in player_list.get_children():
		if row.has_meta("pid"):
			var talk := row.get_node_or_null("Talk")
			if talk:
				talk.visible = Voice.is_speaking(row.get_meta("pid"))


func _update_mic() -> void:
	if Voice.muted:
		mic_button.text = "Mic: Off"
	else:
		mic_button.text = "Mic: On" if Voice.available else "Mic: n/a"


func _on_mic_pressed() -> void:
	Voice.set_muted(not Voice.muted)
	_update_mic()


func _on_start_pressed() -> void:
	Network.start_match()


func _on_leave_pressed() -> void:
	Network.leave()
	_show_connect("")


func _on_back_pressed() -> void:
	Network.leave()
	get_tree().change_scene_to_file(main_menu_path)
