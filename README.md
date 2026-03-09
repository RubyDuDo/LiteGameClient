# SampleClient

基于 Godot 4.4 的游戏客户端示例项目，用于与 [GameServer](https://github.com/RubyDuDo/GameServer) 进行通信。  
使用 Protobuf（通过 [Godobuf](https://github.com/oniksan/godobuf) 插件）作为序列化协议，通过 TCP 与服务器交互。

## 项目目标

1. **接入 Protobuf 协议** — 使用 Godobuf 插件将服务器的 `.proto` 文件编译为 GDScript，实现客户端与服务器之间的结构化消息收发。
2. **与服务器完成通信** — 基于 TCP 连接实现完整的客户端—服务器交互流程。

### 支持的功能

| 功能 | 请求消息 | 响应消息 | 说明 |
|------|----------|----------|------|
| 登录 | `RequestLogin` | `ResponseLogin` | 账号密码验证，获取角色信息 |
| 登出 | `RequestLogout` | `ResponseLogout` | 通知服务器下线 |
| 上报分数 | 待定义 | 待定义 | 需要扩展服务器 proto |
| 拉取排行榜 | 待定义 | 待定义 | 需要扩展服务器 proto |

## 计划步骤

### Step 1 — 项目基础搭建 ✅
- 创建 Godot 4.4 项目
- 安装 Godobuf 插件（v0.6.1）
- 编写 README 文档

### Step 2 — 定义并编译 Protobuf 协议 ✅
- 从 GameServer 同步 `msg.proto`（将 `google.protobuf.Any` 内联以兼容 Godobuf）
- 使用 Godobuf 将 `.proto` 编译为 GDScript 类 → `proto_gen/msg.gd`
- 编写 `scripts/test_proto.gd` 验证序列化与反序列化通过

### Step 3 — 网络层封装 ✅
- `TcpConnection` — TCP 连接管理 + 2 字节大端序长度头消息帧协议
- `NetworkManager` — Autoload 单例，protobuf 感知的发送/接收接口，自动重连
- 编写 `scripts/test_network.gd` 验证帧协议、Msg 打包、MsgRsp 解析

### Step 4 — 登录与登出
- 实现登录界面（输入账号密码）
- 发送 `RequestLogin`，处理 `ResponseLogin`
- 实现登出流程，发送 `RequestLogout`
- 实现心跳机制 (`HeartBeat`)

### Step 5 — 上报分数与排行榜
- 扩展 proto 定义（新增分数上报和排行榜拉取消息）
- 实现分数上报功能
- 实现排行榜拉取与展示

### Step 6 — UI 与完善
- 搭建主界面（登录态/游戏态切换）
- 排行榜列表 UI
- 错误提示与网络状态显示
- 整体测试与调试

## 当前进度

> **当前步骤：Step 3 — 网络层封装（已完成）**
>
> 实现了两层网络架构：`TcpConnection`（TCP + 消息帧）和 `NetworkManager`（protobuf 消息收发）。
> 线路格式与 GameServer 完全兼容：2 字节大端序长度头 + protobuf 负载。
> 下一步进入 Step 4：实现登录与登出。

## 服务器协议参考

服务器使用 proto3，消息采用 `Msg` / `MsgRsp` 统一包装格式：

```protobuf
message Msg {
    MsgHead head = 1;              // 消息类型
    google.protobuf.Any payload = 2; // 具体请求
}

message MsgRsp {
    MsgRspHead head = 1;           // 消息类型 + 错误码
    google.protobuf.Any payload = 2; // 具体响应
}
```

消息类型通过 `MsgType` 枚举区分：`Login`、`Logout`、`Act`、`HeartBeat`。

### 线路格式

```
[2 字节大端序长度头][protobuf 负载]
```

- 长度头仅表示负载长度，不包含自身 2 字节
- 最大消息: 32,767 字节（signed short）
- 客户端发送 `Msg`，服务器回复 `MsgRsp`

## 技术栈

- **引擎**: Godot 4.4 (Forward+)
- **语言**: GDScript
- **序列化**: Protobuf (proto3) via Godobuf 0.6.1
- **网络**: TCP (StreamPeerTCP)
- **服务器**: [GameServer](https://github.com/RubyDuDo/GameServer) (C++, 同一作者)

## 项目结构（规划）

```
sampleclient/
├── addons/protobuf/        # Godobuf 插件
├── proto/                  # .proto 源文件
├── proto_gen/              # Godobuf 编译生成的 GDScript
├── scripts/
│   ├── network/
│   │   ├── tcp_connection.gd   # TCP 连接 + 消息帧协议
│   │   └── network_manager.gd  # Autoload 单例，protobuf 消息收发
│   ├── test_proto.gd           # Protobuf 序列化测试
│   └── test_network.gd         # 网络层测试
├── scenes/                 # 场景文件（登录、主界面、排行榜等）
├── project.godot
└── README.md
```
