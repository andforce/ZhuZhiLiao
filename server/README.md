# 竹知了计数与排行榜服务

面向 `zhuzhiliao.aimfor.top` 的单实例 Node.js 服务。Node 进程监听
`127.0.0.1:3210`，由 Nginx 提供公网 HTTPS/WSS。

## 数据边界

- “此刻在线”只保存在进程内，重启归零。
- “全球共鸣”、匿名玩家、公开六位短码和累计成绩保存在 SQLite。
- 玩家令牌仅在创建时返回明文；数据库只保存 SHA-256 哈希。
- 服务不接收 iPhone 硬件 ID、昵称、位置或动作传感器原始数据。
- 旧版本仍可匿名连接并贡献全球聚合数，但不会出现在排行榜中。

SQLite 使用 WAL、事务性个人/全球递增和 5 秒 busy timeout。生产环境必须只运行一个 Node 实例。

## HTTP 接口

- `POST /api/players`：创建匿名玩家，返回 `{id, code, token}`。
- `GET /api/leaderboard?limit=100`：Bearer 认证，返回前 100 名、参与人数和当前玩家。
- `DELETE /api/players/me`：Bearer 认证，删除匿名身份和排名。
- `GET /api/stats`：返回 `{online, wahs}`。
- `GET /healthz`：健康检查。

## WebSocket 协议

新客户端连接 `/api/ws` 时通过 `Authorization: Bearer <token>` 认证。服务端首先发送玩家状态：

```json
{"t":"player","id":"…","code":"A7K3M9","score":12,"migrated":true}
```

旧本地成绩只允许迁移一次：

```json
{"t":"migrate","personal":12,"pendingGlobal":2}
```

正常计分提交累计目标值，每次最多推进 30；服务端返回已确认成绩。重复目标值不会重复计数：

```json
{"t":"score","value":15}
{"t":"score","score":15}
```

连接成功和统计变化时广播：

```json
{"t":"stats","online":3,"wahs":128}
```

每位玩家每 10 秒最多增加 300。文本 `ping` 会收到 `pong`；服务端也使用 WebSocket ping/pong 清理断线连接。

## 本地运行与部署

需要 Node.js 20 或兼容的新版本。

```bash
npm ci
npm test
npm start
```

生产部署沿用 `deploy/` 和 `scripts/` 中的 systemd、Nginx 与 HTTPS 脚本。SQLite 默认路径为 `./data/counter.sqlite`，可通过 `SQLITE_PATH` 覆盖；`INITIAL_WAHS` 只在首次创建数据库时生效。
