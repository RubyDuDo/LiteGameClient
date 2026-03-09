extends SceneTree

## Headless test for network layer serialization correctness.
## Tests message packing/unpacking without requiring a live server.

const Proto = preload("res://proto_gen/msg.gd")

func _init():
	print("=== Network Layer Tests ===\n")
	test_tcp_framing()
	test_msg_pack_unpack()
	test_rsp_parse()
	print("\n=== All Network Tests Passed ===")
	quit()

func test_tcp_framing():
	print("[Test 1] TCP length-prefix framing (big-endian)")

	# Simulate what send_data does: encode length as 2-byte big-endian
	var payload := PackedByteArray([0x08, 0x01, 0x12, 0x05])
	var size := payload.size()
	var header := PackedByteArray()
	header.resize(2)
	header[0] = (size >> 8) & 0xFF
	header[1] = size & 0xFF

	assert(header[0] == 0x00, "  FAIL: high byte")
	assert(header[1] == 0x04, "  FAIL: low byte")

	# Simulate receive: parse header back
	var decoded_len := (header[0] << 8) | header[1]
	assert(decoded_len == 4, "  FAIL: decoded length mismatch")

	# Test with larger size (e.g. 300 = 0x012C)
	var big_size := 300
	header[0] = (big_size >> 8) & 0xFF
	header[1] = big_size & 0xFF
	assert(header[0] == 0x01, "  FAIL: big high byte")
	assert(header[1] == 0x2C, "  FAIL: big low byte")
	var big_decoded := (header[0] << 8) | header[1]
	assert(big_decoded == 300, "  FAIL: big decoded mismatch")
	print("  OK: 4 bytes -> [0x00, 0x04], 300 bytes -> [0x01, 0x2C]")

func test_msg_pack_unpack():
	print("[Test 2] Client Msg packing (simulating send_message)")

	# Build a Msg the same way NetworkManager.send_message does
	var login = Proto.RequestLogin.new()
	login.set_strName("ruby")
	login.set_strPass("111")
	var login_bytes = login.to_bytes()

	var msg = Proto.Msg.new()
	var head = msg.new_head()
	head.set_type(Proto.MsgType.MsgType_Login)
	var any = msg.new_payload()
	any.set_type_url("type.googleapis.com/MyGame.RequestLogin")
	any.set_value(login_bytes)

	var msg_bytes = msg.to_bytes()
	assert(msg_bytes.size() > 0, "  FAIL: msg_bytes empty")
	assert(msg_bytes.size() <= 32767, "  FAIL: msg too large")
	print("  Packed Msg: %d bytes" % msg_bytes.size())

	# Verify we can parse it back
	var msg2 = Proto.Msg.new()
	var result = msg2.from_bytes(msg_bytes)
	assert(result == Proto.PB_ERR.NO_ERRORS, "  FAIL: parse error %d" % result)
	assert(msg2.get_head().get_type() == Proto.MsgType.MsgType_Login, "  FAIL: type mismatch")
	assert(msg2.get_payload().get_type_url() == "type.googleapis.com/MyGame.RequestLogin", "  FAIL: type_url mismatch")

	var inner = Proto.RequestLogin.new()
	inner.from_bytes(msg2.get_payload().get_value())
	assert(inner.get_strName() == "ruby", "  FAIL: name")
	print("  OK: Msg round-trip verified, type_url=%s" % msg2.get_payload().get_type_url())

func test_rsp_parse():
	print("[Test 3] Server MsgRsp parsing (simulating _on_raw_message)")

	# Build a MsgRsp as the server would
	var resp_login = Proto.ResponseLogin.new()
	var ri = resp_login.new_roleInfo()
	ri.set_roleId(10001)
	ri.set_roleLevel(5)
	var ci = resp_login.new_configInfo()
	ci.set_heartbeatSendInterval(30)

	var rsp = Proto.MsgRsp.new()
	var head = rsp.new_head()
	head.set_type(Proto.MsgType.MsgType_Login)
	head.set_res(Proto.MsgErrCode.MsgErr_OK)
	var payload = rsp.new_payload()
	payload.set_type_url("type.googleapis.com/MyGame.ResponseLogin")
	payload.set_value(resp_login.to_bytes())

	var rsp_bytes = rsp.to_bytes()
	print("  Simulated MsgRsp: %d bytes" % rsp_bytes.size())

	# Parse like _on_raw_message does
	var rsp2 = Proto.MsgRsp.new()
	var result = rsp2.from_bytes(rsp_bytes)
	assert(result == Proto.PB_ERR.NO_ERRORS, "  FAIL: parse error %d" % result)

	var msg_type: int = rsp2.get_head().get_type()
	var err_code: int = rsp2.get_head().get_res()
	assert(msg_type == Proto.MsgType.MsgType_Login, "  FAIL: msg_type")
	assert(err_code == Proto.MsgErrCode.MsgErr_OK, "  FAIL: err_code")

	var payload_bytes: PackedByteArray = rsp2.get_payload().get_value()
	var resp2 = Proto.ResponseLogin.new()
	resp2.from_bytes(payload_bytes)
	assert(resp2.get_roleInfo().get_roleId() == 10001, "  FAIL: roleId")
	assert(resp2.get_configInfo().get_heartbeatSendInterval() == 30, "  FAIL: heartbeat")
	print("  OK: type=%d, err=%d, roleId=%d, heartbeat=%ds" % [
		msg_type, err_code,
		resp2.get_roleInfo().get_roleId(),
		resp2.get_configInfo().get_heartbeatSendInterval()
	])
