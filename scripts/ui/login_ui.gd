extends Control

const Proto = preload("res://proto_gen/msg.gd")

@onready var username_input: LineEdit = %UsernameInput
@onready var password_input: LineEdit = %PasswordInput
@onready var host_input: LineEdit = %HostInput
@onready var port_input: LineEdit = %PortInput
@onready var login_button: Button = %LoginButton
@onready var status_label: Label = %StatusLabel

func _ready() -> void:
	Net.connection_state_changed.connect(_on_connection_state_changed)
	Net.msg_received.connect(_on_msg_received)
	login_button.pressed.connect(_on_login_pressed)
	password_input.text_submitted.connect(func(_t): _on_login_pressed())
	_update_status("Not connected")

func _on_login_pressed() -> void:
	var host := host_input.text.strip_edges()
	var port := port_input.text.strip_edges().to_int()
	var username := username_input.text.strip_edges()
	var password := password_input.text.strip_edges()

	if username.is_empty() or password.is_empty():
		_update_status("Please enter username and password")
		return

	if not Net.is_connected_to_server():
		_update_status("Connecting to %s:%d ..." % [host, port])
		login_button.disabled = true
		var err := Net.connect_to_server(host, port)
		if err != OK:
			_update_status("Connection failed: %d" % err)
			login_button.disabled = false
			return
		await Net.connection_state_changed
		if not Net.is_connected_to_server():
			_update_status("Connection failed")
			login_button.disabled = false
			return

	_send_login(username, password)

func _send_login(username: String, password: String) -> void:
	_update_status("Logging in as %s ..." % username)
	login_button.disabled = true

	var login_req = Proto.RequestLogin.new()
	login_req.set_strName(username)
	login_req.set_strPass(password)
	Net.send_message(Proto.MsgType.MsgType_Login, login_req)

func _on_msg_received(msg_type: int, err_code: int, payload_bytes: PackedByteArray) -> void:
	if msg_type != Proto.MsgType.MsgType_Login:
		return

	if err_code != Proto.MsgErrCode.MsgErr_OK:
		var err_text := "Login failed: "
		match err_code:
			Proto.MsgErrCode.MsgErr_NotExist:
				err_text += "Account not found"
			Proto.MsgErrCode.MsgErr_PasswdWrong:
				err_text += "Wrong password"
			_:
				err_text += "Error %d" % err_code
		_update_status(err_text)
		login_button.disabled = false
		return

	var resp = Proto.ResponseLogin.new()
	resp.from_bytes(payload_bytes)

	var role_id: int = resp.get_roleInfo().get_roleId()
	var role_level: int = resp.get_roleInfo().get_roleLevel()
	var heartbeat_interval: int = resp.get_configInfo().get_heartbeatSendInterval()

	print("[Login] Success: roleId=%d, level=%d, heartbeat=%ds" % [role_id, role_level, heartbeat_interval])

	Session.on_login_success(role_id, role_level, heartbeat_interval)
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")

func _on_connection_state_changed(state: int) -> void:
	const CONNECTED = 2
	const DISCONNECTED = 0
	match state:
		CONNECTED:
			_update_status("Connected")
		DISCONNECTED:
			_update_status("Disconnected")
			login_button.disabled = false

func _update_status(text: String) -> void:
	status_label.text = text
