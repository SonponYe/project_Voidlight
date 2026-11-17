extends Node
## In-match voice chat, registered as the "Voice" autoload.
##
## Who hears whom (decided on the server, never by a client):
##   - Team mode: only your own team.
##   - Free-for-all (including 1v1): everyone — open taunting.
##   - Dead players are heard only by other dead players, because a spectator
##     sees the whole map and could otherwise narrate enemy positions to a
##     living friend (DEAD_HEARD_BY_LIVING to change that).
##
## Transport: the mic is captured with Godot's own audio, downsampled to 8 kHz
## and compressed with G.711 mu-law (8 bytes per ms-ish: ~8 KB/s while
## talking, nothing while silent), then relayed through the game server over
## the existing connection — one code path for desktop and browser, no extra
## infrastructure. Trade-off: WebSocket is TCP, so a lossy connection delays
## voice rather than dropping it; the receiver sheds old audio to catch up.

## Decoded audio from someone, as 8 kHz mono floats. Mostly for tests/UI.
signal frame_received(sender_id: int, samples: PackedFloat32Array)

const WIRE_RATE := 8000
const CHUNK_SAMPLES := 160  # 20 ms
const CHUNKS_PER_PACKET := 3  # 60 ms per network message
const CHUNK_SEC := 0.02
const SPEAK_THRESHOLD := 0.02  # RMS of a 20 ms chunk
const HANGOVER_SEC := 0.4  # keep sending briefly after speech so endings aren't clipped
const MAX_PACKET_BYTES := 1000
const BUDGET_CAP := 16000.0  # bytes a sender may burst
const BUDGET_REFILL := 10000.0  # bytes/second a sender may sustain (normal use is ~8000)
const HEARD_FOR_MS := 250  # how long after a frame someone still counts as "talking"
const MAX_BUFFER_SEC := 0.3  # drop incoming audio past this much queued playback
const BUS_NAME := "VoiceCapture"
const DEAD_HEARD_BY_LIVING := false

var muted := false
## Whether a microphone path could be set up (false in headless runs, or if
## the platform/user refused). Receiving works regardless.
var available := false
## True while our own voice is being sent.
var transmitting := false
## Server-side seam for "is this player dead": defaults to asking the arena.
var dead_check := Callable()

var _enabled := false
var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _phase := 0.0
var _acc := 0.0
var _n := 0
var _pending := PackedFloat32Array()
var _packet := PackedByteArray()
var _hang := 0.0
var _speakers: Dictionary = {}  # peer id -> {"player", "playback"}
var _last_heard: Dictionary = {}  # peer id -> msec
var _budget: Dictionary = {}  # sender id -> [bytes, msec]
var _decode_table := PackedFloat32Array()


func _ready() -> void:
	_decode_table.resize(256)
	for i in 256:
		_decode_table[i] = _ulaw_to_linear(i) / 32768.0


func _process(_delta: float) -> void:
	var want := Network.has_peer() and not Network.dedicated and Network.is_connected_to_match()
	if want and not _enabled:
		enable()
	elif not want and _enabled:
		disable()
	if not _enabled:
		return
	if Input.is_action_just_pressed("voice_mute"):
		set_muted(not muted)
	if _capture:
		_pump_capture()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func enable() -> void:
	_enabled = true
	available = false
	# No audio hardware to capture from in a headless run.
	if DisplayServer.get_name() == "headless":
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
		AudioServer.set_bus_mute(idx, true)  # capture only; never play the mic back
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	if _capture == null:
		return
	_capture.buffer_length = 0.5
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS_NAME
	add_child(_mic_player)
	_mic_player.play()  # the browser's microphone prompt appears here
	available = true


func disable() -> void:
	_enabled = false
	available = false
	transmitting = false
	_hang = 0.0
	_packet.clear()
	_pending.clear()
	if _mic_player:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	_capture = null
	for id in _speakers:
		_speakers[id]["player"].queue_free()
	_speakers.clear()
	_last_heard.clear()
	_budget.clear()


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		_hang = 0.0
		_flush()
		transmitting = false


func status_text() -> String:
	if not available:
		return "Mic: unavailable"
	if muted:
		return "Mic: MUTED  [T]"
	return "Mic: talking" if transmitting else "Mic: on  [T] mute"


func is_speaking(id: int) -> bool:
	if _enabled and Network.has_peer() and id == multiplayer.get_unique_id():
		return transmitting
	return Time.get_ticks_msec() - int(_last_heard.get(id, -100000)) < HEARD_FOR_MS


# ---------------------------------------------------------------------------
# Capture -> encode -> send
# ---------------------------------------------------------------------------

func _pump_capture() -> void:
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	var stereo := _capture.get_buffer(frames)
	var mono := PackedFloat32Array()
	mono.resize(frames)
	for i in frames:
		mono[i] = (stereo[i].x + stereo[i].y) * 0.5
	ingest_pcm(mono, AudioServer.get_mix_rate())


## Feed raw mono audio at `rate` Hz through the same path the microphone uses.
func ingest_pcm(samples: PackedFloat32Array, rate: float) -> void:
	var step := float(WIRE_RATE) / rate
	for s in samples:
		_acc += s
		_n += 1
		_phase += step
		if _phase >= 1.0:  # box-filter downsample: average what fell in this slot
			_phase -= 1.0
			_pending.append(_acc / _n)
			_acc = 0.0
			_n = 0
	while _pending.size() >= CHUNK_SAMPLES:
		var chunk := _pending.slice(0, CHUNK_SAMPLES)
		_pending = _pending.slice(CHUNK_SAMPLES)
		_handle_chunk(chunk)


func _handle_chunk(chunk: PackedFloat32Array) -> void:
	var energy := 0.0
	for v in chunk:
		energy += v * v
	var rms := sqrt(energy / chunk.size())
	var loud := rms >= SPEAK_THRESHOLD and not muted
	if loud:
		_hang = HANGOVER_SEC
	elif _hang > 0.0:
		_hang -= CHUNK_SEC
	if (loud or _hang > 0.0) and not muted:
		transmitting = true
		_packet.append_array(_encode(chunk))
		if _packet.size() >= CHUNK_SAMPLES * CHUNKS_PER_PACKET:
			_flush()
	elif transmitting:
		_flush()  # send the tail now rather than waiting for more speech
		transmitting = false


func _flush() -> void:
	if _packet.is_empty():
		return
	var packet := _packet
	_packet = PackedByteArray()
	if Network.is_host():
		_route(multiplayer.get_unique_id(), packet)
	else:
		_voice_up.rpc_id(1, packet)


func _encode(chunk: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(chunk.size())
	for i in chunk.size():
		out[i] = _linear_to_ulaw(int(clampf(chunk[i], -1.0, 1.0) * 32767.0))
	return out


# ---------------------------------------------------------------------------
# Server: validate and route
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _voice_up(packet: PackedByteArray) -> void:
	if Network.is_host():
		_route(multiplayer.get_remote_sender_id(), packet)


@rpc("authority", "call_remote", "unreliable_ordered")
func _voice_down(sender_id: int, packet: PackedByteArray) -> void:
	_receive(sender_id, packet)


func _route(sender: int, packet: PackedByteArray) -> void:
	if not Network.players.has(sender) or packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		return
	if not _within_budget(sender, packet.size()):
		return
	for id in recipients_for(sender):
		if id == multiplayer.get_unique_id():
			_receive(sender, packet)  # the host is a listener too
		else:
			_voice_down.rpc_id(id, sender, packet)


## Who should hear `sender` right now. Pure function of the roster and the
## dead/alive state, so the rules can be tested without audio.
func recipients_for(sender: int) -> Array[int]:
	var out: Array[int] = []
	var sender_team := Network.player_team(sender)
	var sender_dead := _is_dead(sender)
	for id in Network.players:
		if id == sender:
			continue
		if Network.is_team_mode() and (sender_team == 0 or Network.player_team(id) != sender_team):
			continue
		if sender_dead and not DEAD_HEARD_BY_LIVING and not _is_dead(id):
			continue
		out.append(id)
	return out


func _is_dead(id: int) -> bool:
	if dead_check.is_valid():
		return dead_check.call(id)
	var scene := get_tree().current_scene
	return scene != null and scene.has_method("is_player_dead") and scene.is_player_dead(id)


func _within_budget(sender: int, bytes: int) -> bool:
	var now := Time.get_ticks_msec()
	var entry: Array = _budget.get(sender, [BUDGET_CAP, now])
	var tokens := minf(BUDGET_CAP, float(entry[0]) + (now - int(entry[1])) / 1000.0 * BUDGET_REFILL)
	var ok := tokens >= bytes
	_budget[sender] = [tokens - bytes if ok else tokens, now]
	return ok


# ---------------------------------------------------------------------------
# Receive -> decode -> play
# ---------------------------------------------------------------------------

func _receive(sender_id: int, packet: PackedByteArray) -> void:
	if not Network.has_peer():
		return
	var samples := PackedFloat32Array()
	samples.resize(packet.size())
	for i in packet.size():
		samples[i] = _decode_table[packet[i]]
	_last_heard[sender_id] = Time.get_ticks_msec()
	frame_received.emit(sender_id, samples)
	_play(sender_id, samples)


func _play(sender_id: int, samples: PackedFloat32Array) -> void:
	if not _speakers.has(sender_id):
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = WIRE_RATE
		stream.buffer_length = 0.5
		var player := AudioStreamPlayer.new()
		player.stream = stream
		add_child(player)
		player.play()
		_speakers[sender_id] = {"player": player, "playback": player.get_stream_playback()}
	var playback: AudioStreamGeneratorPlayback = _speakers[sender_id]["playback"]
	if playback == null:
		return
	var queued := int(0.5 * WIRE_RATE) - playback.get_frames_available()
	if queued > int(MAX_BUFFER_SEC * WIRE_RATE):
		return  # running behind: shed this audio so the delay doesn't grow
	var frames := PackedVector2Array()
	frames.resize(samples.size())
	for i in samples.size():
		frames[i] = Vector2(samples[i], samples[i])
	playback.push_buffer(frames)


# ---------------------------------------------------------------------------
# G.711 mu-law
# ---------------------------------------------------------------------------

static func _linear_to_ulaw(sample: int) -> int:
	const BIAS := 0x84
	const CLIP := 32635
	var sign := 0
	if sample < 0:
		sample = -sample
		sign = 0x80
	sample = mini(sample, CLIP) + BIAS
	var exponent := 7
	var mask := 0x4000
	while exponent > 0 and (sample & mask) == 0:
		exponent -= 1
		mask >>= 1
	var mantissa := (sample >> (exponent + 3)) & 0x0F
	return (~(sign | (exponent << 4) | mantissa)) & 0xFF


static func _ulaw_to_linear(byte: int) -> int:
	const BIAS := 0x84
	byte = (~byte) & 0xFF
	var sign := byte & 0x80
	var exponent := (byte >> 4) & 0x07
	var mantissa := byte & 0x0F
	var sample := (((mantissa << 3) + BIAS) << exponent) - BIAS
	return -sample if sign != 0 else sample
