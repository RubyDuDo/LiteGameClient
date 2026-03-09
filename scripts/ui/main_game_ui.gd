extends Control

const Proto = preload("res://proto_gen/msg.gd")

@onready var role_id_label: Label = %RoleIdLabel
@onready var role_level_label: Label = %RoleLevelLabel
@onready var connection_label: Label = %ConnectionLabel
@onready var heartbeat_label: Label = %HeartbeatLabel
@onready var logout_button: Button = %LogoutButton
@onready var log_output: RichTextLabel = %LogOutput

const CONNECTED = 2
const DISCONNECTED = 0

func _ready() -> void:
	Net.connection_state_changed.connect(_on_connection_state_changed)
	Net.msg_received.connect(_on_msg_received)
	logout_button.pressed.connect(_on_logout_pressed)
	_refresh_info()
	_log("Logged in as roleId=%d, level=%d" % [Session.role_id, Session.role_level])

func _process(_delta: float) -> void:
	if Session.is_logged_in():
		heartbeat_label.text = "HB: %.0fs" % Session.get_heartbeat_remaining()

func _refresh_info() -> void:
	role_id_label.text = "Role ID: %d" % Session.role_id
	role_level_label.text = "Level: %d" % Session.role_level
	_update_connection_status()

func _on_logout_pressed() -> void:
	logout_button.disabled = true
	_log("Logging out...")

	var logout_req = Proto.RequestLogout.new()
	logout_req.set_roleId(Session.role_id)
	Net.send_message(Proto.MsgType.MsgType_Logout, logout_req)

func _on_msg_received(msg_type: int, err_code: int, payload_bytes: PackedByteArray) -> void:
	match msg_type:
		Proto.MsgType.MsgType_Logout:
			_on_logout_response(err_code, payload_bytes)
		Proto.MsgType.MsgType_HeartBeat:
			_log("Heartbeat ACK")
		_:
			_log("Received msg type=%d, err=%d" % [msg_type, err_code])

func _on_logout_response(err_code: int, _payload_bytes: PackedByteArray) -> void:
	if err_code == Proto.MsgErrCode.MsgErr_OK:
		_log("Logout success")
		Session.on_logout()
		Net.disconnect_from_server()
		#get_tree().change_scene_to_file("res://scenes/login.tscn")
	else:
		_log("Logout failed: err=%d" % err_code)
		logout_button.disabled = false

func _on_connection_state_changed(state: int) -> void:
	_update_connection_status()
	if state == DISCONNECTED:
		_log("Connection lost")
		Session.on_logout()
		get_tree().change_scene_to_file("res://scenes/login.tscn")

func _update_connection_status() -> void:
	var state := Net.get_state()
	match state:
		CONNECTED:
			connection_label.text = "Status: Connected"
			connection_label.add_theme_color_override("font_color", Color.GREEN)
		1: # CONNECTING
			connection_label.text = "Status: Connecting..."
			connection_label.add_theme_color_override("font_color", Color.YELLOW)
		_:
			connection_label.text = "Status: Disconnected"
			connection_label.add_theme_color_override("font_color", Color.RED)

func _log(text: String) -> void:
	var time_str := Time.get_time_string_from_system()
	log_output.append_text("[%s] %s\n" % [time_str, text])
	print("[MainGame] %s" % text)
