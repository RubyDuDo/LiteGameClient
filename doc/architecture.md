# SampleClient 架构文档

## 总体架构

```
┌─────────────────────────────────────────────────────┐
│                     Godot 场景层                      │
│              UI / 游戏逻辑 (待实现)                    │
│                                                     │
│   调用 Net.send_message()    监听 Net.msg_received   │
└─────────────────┬───────────────────┬───────────────┘
                  │                   │
                  ▼                   ▲
┌─────────────────────────────────────────────────────┐
│              NetworkManager (Autoload 单例)           │
│                                                     │
│  职责:                                               │
│  · 构建 Msg (head + Any(payload))，序列化后下发       │
│  · 解析收到的 MsgRsp，提取 type/errCode/payload       │
│  · 自动重连管理                                      │
│                                                     │
│  信号:                                               │
│  · connection_state_changed(state)                   │
│  · msg_received(msg_type, err_code, payload_bytes)   │
└─────────────────┬───────────────────┬───────────────┘
                  │                   │
                  ▼                   ▲
┌─────────────────────────────────────────────────────┐
│                   TcpConnection                      │
│                                                     │
│  职责:                                               │
│  · TCP 连接生命周期 (连接/断开/状态轮询)               │
│  · 消息帧协议: [2字节大端序长度头][protobuf负载]        │
│  · 接收缓冲区管理，处理 TCP 粘包/拆包                  │
│                                                     │
│  信号:                                               │
│  · connected / disconnected                          │
│  · message_received(data: PackedByteArray)            │
└─────────────────┬───────────────────┬───────────────┘
                  │                   │
                  ▼                   ▲
            ┌───────────┐      ┌───────────┐
            │  TCP 发送  │      │  TCP 接收  │
            │ put_data() │      │ get_data() │
            └─────┬─────┘      └─────┬─────┘
                  │                   │
                  ▼                   ▲
         ═════════════════════════════════════
                    网络 (TCP)
         ═════════════════════════════════════
                  │                   │
                  ▼                   ▲
         ┌─────────────────────────────────┐
         │         GameServer (C++)         │
         │   NetSlot::sendMsg / getRecv    │
         └─────────────────────────────────┘
```

## 线路格式 (Wire Format)

客户端与服务器通过 TCP 通信，每条消息的二进制格式为：

```
┌──────────────────┬──────────────────────────────┐
│  Length (2 bytes) │      Payload (N bytes)        │
│   big-endian      │    serialized protobuf        │
└──────────────────┴──────────────────────────────┘
```

| 字段 | 大小 | 字节序 | 说明 |
|------|------|--------|------|
| Length | 2 字节 (uint16) | 大端序 (网络字节序) | 仅表示 Payload 的长度，不包含自身 |
| Payload | 0 ~ 32,767 字节 | — | 序列化后的 protobuf 消息 |

- 客户端 → 服务器: Payload 是 `Msg` 的序列化结果
- 服务器 → 客户端: Payload 是 `MsgRsp` 的序列化结果

## 消息结构 (Protobuf)

### 请求 (客户端 → 服务器)

```
Msg
├── head: MsgHead
│   └── type: MsgType          // 消息类型枚举
└── payload: Any
    ├── type_url: string       // "type.googleapis.com/MyGame.RequestXxx"
    └── value: bytes           // 具体请求消息的序列化字节
```

### 响应 (服务器 → 客户端)

```
MsgRsp
├── head: MsgRspHead
│   ├── type: MsgType          // 与请求对应的消息类型
│   └── res: MsgErrCode        // 错误码 (0 = OK)
└── payload: Any
    ├── type_url: string       // "type.googleapis.com/MyGame.ResponseXxx"
    └── value: bytes           // 具体响应消息的序列化字节
```

### 消息类型

| MsgType | 值 | 请求消息 | 响应消息 |
|---------|---|---------|---------|
| MsgType_Login | 1 | RequestLogin | ResponseLogin |
| MsgType_Logout | 2 | RequestLogout | ResponseLogout |
| MsgType_Act | 3 | RequestAct | ResponseAct |
| MsgType_HeartBeat | 4 | RequestHeartBeat | ResponseHeartBeat |

### 错误码

| MsgErrCode | 值 | 含义 |
|------------|---|------|
| MsgErr_OK | 0 | 成功 |
| MsgErr_Fail | 1 | 通用失败 |
| MsgErr_NotExist | 2 | 账号不存在 |
| MsgErr_PasswdWrong | 3 | 密码错误 |

### Any 字段说明

服务器使用 C++ protobuf 的 `google.protobuf.Any`，客户端使用内联的兼容定义。
两者在二进制层面完全相同（相同的字段编号和类型），因此可以互通。

`type_url` 必须遵循格式 `"type.googleapis.com/MyGame.<MessageName>"`，
服务器的 `UnpackTo<T>()` 会验证此前缀。

## 代码结构

```
scripts/network/
├── tcp_connection.gd      底层 TCP + 消息帧
└── network_manager.gd     高层 protobuf 消息收发
```

### TcpConnection

```
class_name TcpConnection extends RefCounted

信号:
  connected()
  disconnected()
  message_received(data: PackedByteArray)

方法:
  connect_to_server(host, port) -> Error
  disconnect_from_server()
  poll()                        // 每帧调用，驱动状态机和数据接收
  send_data(payload) -> Error   // 自动添加长度头后发送
```

**状态机:**

```
  DISCONNECTED ──connect_to_server()──► CONNECTING
       ▲                                    │
       │                          TCP 连接成功
       │                                    │
       │                                    ▼
  disconnect / error ◄──────────── CONNECTED
                                  (收发数据)
```

### NetworkManager

```
class_name NetworkManager extends Node  (Autoload, 建议命名 "Net")

信号:
  connection_state_changed(state)
  msg_received(msg_type: int, err_code: int, payload_bytes: PackedByteArray)

方法:
  connect_to_server(host, port, auto_reconnect) -> Error
  disconnect_from_server()
  send_message(msg_type, payload) -> Error
  is_connected_to_server() -> bool
  get_state() -> TcpConnection.State
```

**发送流程:**

```
send_message(MsgType_Login, login_request)
  │
  ├─ 1. 创建 Msg 对象
  ├─ 2. 设置 head.type = MsgType_Login
  ├─ 3. 将 login_request.to_bytes() 打包到 Any.value
  ├─ 4. 设置 Any.type_url = "type.googleapis.com/MyGame.RequestLogin"
  ├─ 5. msg.to_bytes() → protobuf 字节
  └─ 6. TcpConnection.send_data(bytes) → [长度头 + 字节] → TCP
```

**接收流程:**

```
TCP 数据到达
  │
  ├─ 1. TcpConnection 缓冲并按长度头拆分完整消息
  ├─ 2. 发射 message_received(raw_bytes)
  ├─ 3. NetworkManager._on_raw_message():
  │     ├─ 解析为 MsgRsp
  │     ├─ 提取 head.type, head.res, payload.value
  │     └─ 发射 msg_received(type, err_code, payload_bytes)
  └─ 4. 业务层根据 type 解析 payload_bytes 为具体响应消息
```

## 重连机制

当 `auto_reconnect = true` 时，`NetworkManager` 在检测到断开后每隔 3 秒自动尝试重连。
断开时停止重连计时器，重新连接成功时重置计时器。

```
CONNECTED ──断开──► DISCONNECTED
                        │
                   等待 3 秒
                        │
                        ▼
                   尝试重连 ──失败──► 继续等待 3 秒
                        │
                      成功
                        │
                        ▼
                    CONNECTED
```

## 协议兼容性说明

| 方面 | 客户端 (GDScript) | 服务器 (C++) |
|------|-------------------|-------------|
| Protobuf 版本 | proto3 (Godobuf 0.6.1) | proto3 (libprotobuf) |
| Any 实现 | 内联定义 (field 1: type_url, field 2: value) | google.protobuf.Any |
| 帧协议 | 手动编码 2 字节大端序 | htons/ntohs |
| type_url 格式 | `type.googleapis.com/MyGame.Xxx` | `PackFrom()` 自动生成，格式相同 |

二进制层面完全兼容，客户端和服务器可以直接通信。
