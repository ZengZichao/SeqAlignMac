# 隐私政策 / Privacy Policy

**最近更新日期 / Last updated: 2026-09-15**

## 一句话结论

SeqAlignMac **不收集、不传输、不存储任何个人数据到云端**。所有比对文件的读取、编辑、
统计、翻译、导出都在你的本机本地完成，应用**没有网络访问能力**。

SeqAlignMac **collects, transmits, and stores no personal data.** All file reading, editing,
analysis, translation and export happen entirely on your device. The app has **no network access**.

## 我们如何处理数据

| 项目 | 说明 |
|---|---|
| 个人身份信息 | 不收集，应用无账号系统 |
| 序列 / 比对数据 | 仅在你主动打开的文件中读写，不上传；不读取你未选择的文件 |
| 界面偏好（字号、配色、语言、最近文件列表等） | 通过系统 `UserDefaults` 存储在**本机**，不离开设备 |
| 诊断 / 遥测 / 广告 / 追踪 | 无任何形式的遥测、崩溃上报、广告或跨应用追踪 |
| 网络 | 应用不联网，`NSPrivacyTracking = false`，隐私清单见 `Resources/PrivacyInfo.xcprivacy` |

## 第三方内容

- 「外部比对器」功能（MAFFT / MUSCLE / ClustalW2）仅在你本机、由你主动指定可执行文件路径后调用，
  数据不离开本机。**Mac App Store 版本因沙盒限制不含此功能**（详见下文）。
- 应用不嵌入任何第三方追踪 SDK。

## 儿童隐私

应用为通用科研 / 生产力工具，不专门面向儿童，也不收集任何用户数据，符合 COPPA / GDPR-K 相关要求。

## 数据保留与删除

由于不收集任何个人数据，服务端不存在需要保留或删除的数据。卸载应用即移除全部本机构建与偏好数据；
在 macOS「系统设置 ▸ 隐私与安全」中也可清除应用的相关权限与数据。

## Mac App Store 隐私"营养标签"

在 App Store Connect 中，本应用应申报为：

- **Data Used to Track You**：无
- **Data Linked to You**：无
- **Data Collected**：无（"We do not collect data from this app."）
- **Encryption**：不使用非豁免加密（`ITSAppUsesNonExemptEncryption = false`）

## 外部比对器与 Mac App Store 的说明

App Store 的 App Sandbox 不允许应用启动用户自行安装的外部可执行文件。因此
**上架 Mac App Store 的版本将隐藏「外部比对器」入口**；GitHub 直发版本（Developer ID 签名 + 公证）
保留完整的外部比对器功能。两个版本除该功能外行为一致。

## 联系我们

安全问题请见 `SECURITY.md`；一般咨询请通过仓库 Issues 或作者联系方式。

---

如本政策有实质变更，将更新顶部日期并通过仓库 Release 说明。
