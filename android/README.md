# 赛博竹知了 Android

Android 客户端使用 Kotlin、传统 View 与 OpenGL ES 3.0，支持 Android 10（API 29）及以上手机。它与 iOS 客户端共享物理参数、录音、四季主题、匿名身份、排行榜、在线统计和哇声地球后端。

## 运行

用 Android Studio 打开本目录并运行 `app`，或使用 JDK 17 执行：

```bash
./gradlew assembleDebug
```

输出 APK：`app/build/outputs/apk/debug/app-debug.apk`。

## 发布签名

Release 构建会从本地 `keystore.properties` 读取 `storeFile`、`storePassword`、`keyAlias` 和 `keyPassword`。属性文件与 `keystore/` 目录均已被 Git 忽略，签名库不得提交或附加到公开 Release。

```bash
./gradlew assembleRelease bundleRelease
```

输出 APK 与 AAB 分别位于 `app/build/outputs/apk/release/` 和 `app/build/outputs/bundle/release/`。

## 测试

```bash
./gradlew testDebugUnitTest
```

体感玩法需要加速度计；有融合姿态、重力和陀螺仪时会一并使用。缺少动作传感器的设备会进入自动演示，并始终保留全屏触控玩法。

## 隐私

动作数据仅在设备本地参与物理模拟。哇声地球可在不授权定位时浏览；主动加入后只申请粗略位置，并在上传前量化为约 20 公里格网，服务器不会收到原始坐标。
