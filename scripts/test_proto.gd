extends SceneTree

const Proto = preload("res://proto_gen/msg.gd")

func _init():
	print("=== Protobuf Serialization Test ===\n")
	test_request_login()
	test_msg_with_payload()
	test_response_login()
	print("\n=== All Tests Passed ===")
	quit()

func test_request_login():
	print("[Test 1] RequestLogin serialize / deserialize")
	var login = Proto.RequestLogin.new()
	login.set_strName("ruby")
	login.set_strPass("111")

	var bytes = login.to_bytes()
	print("  Serialized %d bytes" % bytes.size())

	var login2 = Proto.RequestLogin.new()
	var result = login2.from_bytes(bytes)
	assert(result == Proto.PB_ERR.NO_ERRORS, "  FAIL: from_bytes returned %d" % result)
	assert(login2.get_strName() == "ruby", "  FAIL: name mismatch")
	assert(login2.get_strPass() == "111", "  FAIL: pass mismatch")
	print("  OK: name=%s, pass=%s" % [login2.get_strName(), login2.get_strPass()])

func test_msg_with_payload():
	print("[Test 2] Msg wrapping RequestLogin via Any")
	var login = Proto.RequestLogin.new()
	login.set_strName("testuser")
	login.set_strPass("pwd123")
	var login_bytes = login.to_bytes()

	var msg = Proto.Msg.new()
	var head = msg.new_head()
	head.set_type(Proto.MsgType.MsgType_Login)
	var payload = msg.new_payload()
	payload.set_type_url("MyGame.RequestLogin")
	payload.set_value(login_bytes)

	var msg_bytes = msg.to_bytes()
	print("  Serialized Msg: %d bytes" % msg_bytes.size())

	var msg2 = Proto.Msg.new()
	var result = msg2.from_bytes(msg_bytes)
	assert(result == Proto.PB_ERR.NO_ERRORS, "  FAIL: Msg from_bytes returned %d" % result)
	assert(msg2.get_head().get_type() == Proto.MsgType.MsgType_Login, "  FAIL: head type mismatch")

	var inner_bytes = msg2.get_payload().get_value()
	var login2 = Proto.RequestLogin.new()
	var inner_result = login2.from_bytes(inner_bytes)
	assert(inner_result == Proto.PB_ERR.NO_ERRORS, "  FAIL: inner from_bytes returned %d" % inner_result)
	assert(login2.get_strName() == "testuser", "  FAIL: inner name mismatch")
	print("  OK: type=%d, payload_url=%s, inner_name=%s" % [
		msg2.get_head().get_type(),
		msg2.get_payload().get_type_url(),
		login2.get_strName()
	])

func test_response_login():
	print("[Test 3] MsgRsp wrapping ResponseLogin")
	var role_info = Proto.RoleInfo.new()
	role_info.set_roleId(10001)
	role_info.set_roleLevel(5)
	var config = Proto.ConfigToClient.new()
	config.set_heartbeatSendInterval(30)

	var resp = Proto.ResponseLogin.new()
	var ri = resp.new_roleInfo()
	ri.set_roleId(10001)
	ri.set_roleLevel(5)
	var ci = resp.new_configInfo()
	ci.set_heartbeatSendInterval(30)
	var resp_bytes = resp.to_bytes()

	var rsp = Proto.MsgRsp.new()
	var head = rsp.new_head()
	head.set_type(Proto.MsgType.MsgType_Login)
	head.set_res(Proto.MsgErrCode.MsgErr_OK)
	var payload = rsp.new_payload()
	payload.set_type_url("MyGame.ResponseLogin")
	payload.set_value(resp_bytes)

	var rsp_bytes = rsp.to_bytes()
	print("  Serialized MsgRsp: %d bytes" % rsp_bytes.size())

	var rsp2 = Proto.MsgRsp.new()
	var result = rsp2.from_bytes(rsp_bytes)
	assert(result == Proto.PB_ERR.NO_ERRORS, "  FAIL: MsgRsp from_bytes returned %d" % result)
	assert(rsp2.get_head().get_res() == Proto.MsgErrCode.MsgErr_OK, "  FAIL: err code mismatch")

	var inner_bytes = rsp2.get_payload().get_value()
	var resp2 = Proto.ResponseLogin.new()
	resp2.from_bytes(inner_bytes)
	assert(resp2.get_roleInfo().get_roleId() == 10001, "  FAIL: roleId mismatch")
	assert(resp2.get_configInfo().get_heartbeatSendInterval() == 30, "  FAIL: heartbeat mismatch")
	print("  OK: err=%d, roleId=%d, level=%d, heartbeat=%ds" % [
		rsp2.get_head().get_res(),
		resp2.get_roleInfo().get_roleId(),
		resp2.get_roleInfo().get_roleLevel(),
		resp2.get_configInfo().get_heartbeatSendInterval()
	])
