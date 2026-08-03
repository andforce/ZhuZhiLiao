# 竹知了计数服务

面向 `zhuzhiliao.aimfor.top` 的单实例 Node.js 服务。Node 进程监听
`127.0.0.1:3210`，由 Nginx 提供公网 HTTPS/WSS。该端口避开目标服务器
已有的 3001 服务。

## 数据边界

- “此刻在线”来自当前进程的活跃 WebSocket 数量，重启即归零，不写数据库。
- “全球共鸣”写入 `/var/lib/zhuzhiliao-counter/counter.sqlite`。
- “我的哇声”不属于服务端数据。客户端只发送新增圈数，不发送设备 ID、个人累计或动作数据。

SQLite 使用 WAL、同步单语句递增和 5 秒 busy timeout。生产环境必须只运行一个
Node 实例，否则在线数会被拆分到各进程。

## 接口

### `GET /api/stats`

```json
{"online":3,"wahs":128}
```

### `WSS /api/ws`

连接成功以及在线数/全球计数变化时，服务端广播：

```json
{"t":"stats","online":3,"wahs":128}
```

客户端新增圈数时发送，每条最多 30：

```json
{"t":"wah","n":1}
```

文本 `ping` 会收到 `pong`。服务端还使用 WebSocket ping/pong 清理断线连接。

### `GET /healthz`

```json
{"status":"ok"}
```

## 本地运行

需要 Node.js 20 或兼容的新版本。

```bash
npm ci
npm test
npm start
```

## 火山引擎 Ubuntu 部署

1. 给云服务器安全组放通公网 TCP 80、443；3210 只监听回环地址，不对公网开放。
2. 安装 Node.js 20+，把本目录上传到服务器。
3. 在本目录运行 `sudo ./scripts/install-on-ubuntu.sh`。
4. 在火山引擎云解析中把主机记录 `zhuzhiliao` 的 A 记录指向该服务器公网 IPv4，免费套餐使用最低 TTL 600 秒；删除同名冲突的 A/CNAME 记录。
5. DNS 生效后运行 `sudo ./scripts/enable-https.sh you@example.com`；不希望登记通知邮箱时可省略参数。
6. 公网验收：`npm run smoke -- https://zhuzhiliao.aimfor.top`。

如需从旧计数开始，只能在首次启动前写入
`/etc/zhuzhiliao-counter.env`：

```env
INITIAL_WAHS=12345
```

该值只用于首次创建数据库，后续重启不会覆盖累计值。不要迁移或写入设备 ID。

常用运维命令：

```bash
systemctl status zhuzhiliao-counter
journalctl -u zhuzhiliao-counter -f
systemctl status nginx
nginx -t
certbot renew --cert-name zhuzhiliao.aimfor.top --dry-run
```
