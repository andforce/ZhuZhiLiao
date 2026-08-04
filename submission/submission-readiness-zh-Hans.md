# 赛博竹知了 1.0 提交审核准备清单

更新日期：2026 年 8 月 3 日

## 当前状态

- App Store Connect App ID：`6797417293`
- App Store 版本：`1.0`
- 已关联构建：`1`（状态：`VALID`）
- 已上传 iPhone 截图：3 张（全部处理完成）
- 本地自动化测试：37 项通过，0 项失败
- ASC 元数据校验：0 个错误，0 个警告
- ASC 提交预检：0 个阻塞项、1 个警告、1 个待人工确认项

## 已完成

- 简体中文副标题、描述、关键词、推广文本和支持 URL；可选营销 URL 已留空
- 主分类：娱乐
- 年龄分级问卷
- 版本版权信息
- App Review 联系信息和审核说明
- 无演示账号声明
- App 隐私填写依据和隐私政策正文
- 隐私清单申报匿名 User ID 与产品交互；不申报应用未读取的硬件设备标识符
- iPhone 商店截图生成、人工核验和上传
- Release 归档、App Store 分发导出、构建上传和版本关联
- 内容版权声明：仅使用自行录制或自有内容，不使用第三方内容
- 销售范围：全球 175 个国家和地区，并自动包含未来新增地区

## 提交前仍需完成

1. 将 `submission/privacy-policy-zh-Hans.md` 发布到公开 HTTPS 页面，并把 URL 填入简体中文 App 信息。
2. 按 `submission/app-privacy-answers-zh-Hans.md` 在 App Store Connect 发布 App 隐私回答。

完成以上项目后，再运行：

```sh
asc validate --app 6797417293 --version-id 8a455faa-093b-4bda-b546-654571882473 --strict
```

严格预检无阻塞项后，才进入最终“提交审核”步骤。
