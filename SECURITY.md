# 安全政策 / Security Policy

## 支持的版本 / Supported Versions

| 版本 | 支持 |
|---|---|
| 最新版（见 `Info.plist` `CFBundleShortVersionString`） | ✅ |
| 上一 minor | ⚠️ 尽力而为 |
| 更早版本 | ❌ |

## 报告漏洞 / Reporting a Vulnerability

**请勿在公开 Issue 中报告安全漏洞。**

通过 GitHub 私有安全通告（Security ▸ Report a vulnerability）或维护者公布的加密邮箱私下报告，
并尽量附上：复现步骤、受影响版本、潜在影响、可选的修复建议。

我们承诺：

- 3 个工作日内确认收到；
- 评估后给出修复时间表；
- 修复发布后在 Release 说明中致谢（如你愿意署名）。

## 攻击面说明

SeqAlignMac 是**离线、无网络、无账号**的桌面应用，不收集个人数据（见 `PRIVACY.md`）。
主要潜在风险面：

- **解析不受信任的比对文件**：畸形输入应显式报错而非崩溃 / 越界 / 静默截断。
  若发现某文件导致崩溃或内存不安全行为，请附最小复现样本。
- **外部比对器（仅非沙盒 / 直发版）**：由**用户主动指定可执行文件路径**后以 `Process` 调用，
  等同"运行一条你自己输入的命令"，不构成越权，但请勿在不可信环境粘贴恶意命令模板。
- **撤销栈内存上限**：快照型命令受条数（50）与内存（256MB）双上限约束，避免 OOM。

## 分发完整性

- Mac App Store 版由 Apple 分发与公证托管。
- GitHub 直发的 Developer ID 版应经 `notarytool` 公证（见 `build.sh` 中 `SEQALIGN_SANDBOX` /
  `NOTARY_PROFILE` 开关），用户可通过 `spctl -a -vv` 与 `codesign --verify` 校验。
