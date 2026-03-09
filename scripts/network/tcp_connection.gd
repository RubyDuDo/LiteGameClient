class_name TcpConnection
extends RefCounted

## Low-level TCP connection with length-prefixed message framing.
## Wire format: [2-byte big-endian payload length][protobuf bytes]
## Compatible with GameServer's NetSlot send/recv protocol.

signal connected
signal disconnected
signal message_received(data: PackedByteArray)

enum State { DISCONNECTED, CONNECTING, CONNECTED }

const HEADER_SIZE := 2
const MAX_PAYLOAD_SIZE := 32767 # signed short max

var _tcp: StreamPeerTCP
var _recv_buffer: PackedByteArray
var _state: State = State.DISCONNECTED
var _host: String
var _port: int

func _init():
	_tcp = StreamPeerTCP.new()
	_tcp.set_no_delay(true)
	_recv_buffer = PackedByteArray()

func get_state() -> State:
	return _state

func connect_to_server(host: String, port: int) -> Error:
	if _state != State.DISCONNECTED:
		disconnect_from_server()

	_host = host
	_port = port
	_recv_buffer.clear()

	var err := _tcp.connect_to_host(host, port)
	if err != OK:
		push_error("TcpConnection: connect_to_host failed: %d" % err)
		return err

	_state = State.CONNECTING
	return OK

func disconnect_from_server() -> void:
	_tcp.disconnect_from_host()
	_recv_buffer.clear()
	if _state != State.DISCONNECTED:
		_state = State.DISCONNECTED
		disconnected.emit()

func poll() -> void:
	_tcp.poll()
	var tcp_status := _tcp.get_status()

	match tcp_status:
		StreamPeerTCP.STATUS_NONE:
			if _state != State.DISCONNECTED:
				_state = State.DISCONNECTED
				disconnected.emit()

		StreamPeerTCP.STATUS_CONNECTING:
			pass

		StreamPeerTCP.STATUS_CONNECTED:
			if _state == State.CONNECTING:
				_state = State.CONNECTED
				connected.emit()
			_read_available()

		StreamPeerTCP.STATUS_ERROR:
			if _state != State.DISCONNECTED:
				_state = State.DISCONNECTED
				disconnected.emit()

## Pack data with 2-byte big-endian length header and send.
func send_data(payload: PackedByteArray) -> Error:
	if _state != State.CONNECTED:
		push_error("TcpConnection: not connected")
		return ERR_CONNECTION_ERROR

	var size := payload.size()
	if size > MAX_PAYLOAD_SIZE:
		push_error("TcpConnection: payload too large (%d > %d)" % [size, MAX_PAYLOAD_SIZE])
		return ERR_PARAMETER_RANGE_ERROR

	# 2-byte big-endian length header
	var header := PackedByteArray()
	header.resize(HEADER_SIZE)
	header.encode_u16(0, ((size >> 8) & 0xFF) | ((size & 0xFF) << 8))

	var err := _tcp.put_data(header)
	if err != OK:
		return err
	return _tcp.put_data(payload)

## Read all available bytes and extract complete messages.
func _read_available() -> void:
	var available := _tcp.get_available_bytes()
	if available <= 0:
		return

	var result := _tcp.get_data(available)
	if result[0] != OK:
		return

	_recv_buffer.append_array(result[1])
	_process_recv_buffer()

## Extract complete messages from the receive buffer.
func _process_recv_buffer() -> void:
	while _recv_buffer.size() >= HEADER_SIZE:
		var payload_len := (_recv_buffer[0] << 8) | _recv_buffer[1]
		var total_len := HEADER_SIZE + payload_len

		if _recv_buffer.size() < total_len:
			break

		var payload := _recv_buffer.slice(HEADER_SIZE, total_len)
		_recv_buffer = _recv_buffer.slice(total_len)
		message_received.emit(payload)
