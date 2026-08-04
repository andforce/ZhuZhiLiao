# 赛博竹知了

把传统民间童玩“竹知了”装进 iPhone。轻轻往复摇动手机或用手指在屏幕上画圈，竹知了会随动作旋转，并根据转速发出不同节奏和响度的叫声。

<p align="center">
  <img src="screenshots/raw/zh-Hans/iphone69/02-自动演示.png" alt="自动演示" width="30%">
  <img src="screenshots/raw/zh-Hans/iphone69/03-手指控制.png" alt="手指控制" width="30%">
  <img src="screenshots/raw/zh-Hans/iphone69/01-安全提示.png" alt="安全提示" width="30%">
</p>

## 特性

- 基于 SwiftUI 和 Metal 的全原生 iOS 体验
- Core Motion 三轴动作识别与固定步长绳系物理模拟
- 体感、全屏触控和自动演示三种玩法
- 根据转速动态调整速度、音高和音量的真实录音
- 春、夏、秋、冬四套季节画面
- 匿名汇总的实时在线连接数与“哇声”计数
- 可旋转缩放的“哇声地球”、匿名粗略位置圆点与两分钟共鸣波纹
- 基于镜头缩放的地理预聚合与屏幕空间圆点聚合
- 无账号、无广告、无内购

## 技术栈

- 客户端：Swift 6、SwiftUI、Metal / MetalKit、Core Motion、AVFoundation
- 服务端：Node.js、WebSocket、SQLite
- 平台：iPhone，iOS 17.0+，竖屏

## 从源码运行

### iOS 客户端

1. 使用 Xcode 26 或兼容版本打开 `ZhuZhiLiao.xcodeproj`。
2. 在 `ZhuZhiLiao` target 的 Signing & Capabilities 中选择你的开发团队；如果使用真机，同时换用可用的 Bundle Identifier 和描述文件。
3. 选择 iOS 17+ 的 iPhone 或模拟器，运行 `ZhuZhiLiao` scheme。

真机可使用完整的体感玩法。模拟器会自动演示，也可按住画面并拖动鼠标来控制。

工程已提交 Xcode 项目文件，无需额外生成。如需根据 `project.yml` 重新生成，请先安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)，然后运行：

```bash
xcodegen generate
```

### 计数服务

本地运行需要 Node.js 20 或更高兼容版本：

```bash
cd server
npm ci
npm start
```

服务默认监听 `127.0.0.1:3210`，提供 `GET /healthz`、`GET /api/stats` 和 `WS /api/ws`。如需修改配置，可参考 `server/.env.example` 设置 `HOST`、`PORT`、`SQLITE_PATH` 和 `INITIAL_WAHS` 环境变量。客户端默认连接线上服务；要调试本地服务，请修改 `ZhuZhiLiao/Network/CounterService.swift` 中的 `endpoint`。部署和协议详情见 [`server/README.md`](server/README.md)。

## 测试

在 Xcode 中按 `⌘U`，或使用命令行运行 iOS 单元测试：

```bash
xcodebuild test \
  -project ZhuZhiLiao.xcodeproj \
  -scheme ZhuZhiLiao \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

服务端测试：

```bash
cd server
npm test
```

## 项目结构

```text
ZhuZhiLiao/          iOS 应用源码与资源
ZhuZhiLiaoTests/     物理、动作滤波、计圈与网络编解码测试
server/              全球计数与在线统计服务
metadata/            App Store 元数据
screenshots/         App Store 截图与审核记录
submission/          隐私政策与提审材料
project.yml          XcodeGen 工程配置
```

## 隐私与安全

动作数据仅在本机用于控制玩具，不会上传。在线服务接收匿名累计数；只有用户主动加入哇声地球时，才接收客户端量化后的约 20 公里格网编号。服务不接收设备标识、原始精确坐标或动作传感器数据。详见 [`submission/privacy-policy-zh-Hans.md`](submission/privacy-policy-zh-Hans.md)。

体感游玩时请稳握手机，只做短幅、轻柔、连续的动作，并与他人和物品保持距离。
