extends Node

## Global session state: login info and heartbeat management.
## Registered as Autoload singleton named "Session".

const Proto = preload("res://proto_gen/msg.gd")

var role_id: int = 0
var role_level: int = 0

var _heartbeat_interval: float = 0.0
var _heartbeat_timer: float = 0.0
var _logged_in: bool = false

func is_logged_in() -> bool:
	return _logged_in

func get_heartbeat_remaining() -> float:
	return max(_heartbeat_timer, 0.0)

func on_login_success(p_role_id: int, p_role_level: int, p_heartbeat_interval: int) -> void:
	role_id = p_role_id
	role_level = p_role_level
	_heartbeat_interval = float(p_heartbeat_interval)
	_heartbeat_timer = _heartbeat_interval
	_logged_in = true
	print("[Session] Login: roleId=%d, level=%d, heartbeat every %ds" % [role_id, role_level, p_heartbeat_interval])

func on_logout() -> void:
	_logged_in = false
	_heartbeat_timer = 0.0
	role_id = 0
	role_level = 0
	print("[Session] Logged out")

func _process(delta: float) -> void:
	if not _logged_in:
		return
	if _heartbeat_interval <= 0:
		return

	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0:
		_heartbeat_timer = _heartbeat_interval
		_send_heartbeat()

func _send_heartbeat() -> void:
	if not Net.is_connected_to_server():
		return
	var hb = Proto.RequestHeartBeat.new()
	hb.set_roleId(role_id)
	Net.send_message(Proto.MsgType.MsgType_HeartBeat, hb)
	print("[Session] Heartbeat sent (roleId=%d)" % role_id)
