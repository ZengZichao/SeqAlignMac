# 贡献指南 / Contributing

感谢你对 SeqAlignMac 的兴趣！本文说明如何构建、测试并提交改动。

## 环境要求

- macOS 14+ 与 Xcode 15+（或含 XCTest 的完整 Command Line Tools）
- Swift 6 工具链（`Package.swift` 声明 swift-tools-version 6.0）

## 构建与运行

```bash
# 构建领域核心 + 运行单元测试
swift build
swift test

# 构建完整 .app（swiftc 直接编译全部 Sources 并打包/签名/压缩）
./build.sh            # 常规开发构建（ad-hoc 签名）
./build.sh --open     # 构建后启动
./build.sh --skip-tests   # 跳过测试（CI 已单独跑测试时用）
```

产物 `SeqAlignMac.app` 与 `SeqAlignMac.app.zip` 已被 `.gitignore` 忽略。

## 架构约定（务必遵守）

- **领域层 / 渲染层分离**：`SeqAlignCore`（解析 / 写出 / 翻译 / 引物 / 列统计 / 搜索 /
  撤销 / 颜色逻辑）必须保持**纯逻辑、不依赖 AppKit/SwiftUI**，只由 `Package.swift` 的
  `sources` 白名单纳入并覆盖单元测试。
- **新增纯逻辑文件请同时加入 `Package.swift` 的 `sources` 白名单**，否则会被静默排除在测试之外。
- **设计令牌**：界面颜色 / 字号 / 间距 / 圆角一律消费 `MinimalTheme.swift` 的 `Minimal.*`，
  **禁止在视图层硬编码色值**。深色判定统一用 `NSAppearance.isDarkNow`。
- **本地化**：所有面向用户的字符串走 `Localization.swift` 的 `L.s`，中英文各一份、键对称；
  不要在视图/解析器里写死中文或英文。CI 会检查视图层硬编码中文。
- **并发纪律**：后台队列**禁止**读取活的 `Alignment`，必须先 `align.snapshot()`；
  对 `@State` / `@Published` 的写必须回主线程。

## 测试

- 新功能 / 修 bug 请附回归测试（`Tests/SeqAlignCoreTests/`）。
- 涉及解析 / 写出 / 统计 / 搜索 / 撤销的改动，必须保证 `swift test` 全绿。
- AppKit 依赖部分（画布 / 导出 / 保存）暂无 SwiftPM 测试通道；如需覆盖，请先说明理由，
  我们讨论是否为 App 目标增设测试通道。

## 提交流程

1. 从 `main` 切出分支，命名如 `fix/<简述>` 或 `feat/<简述>`。
2. 本地 `swift test && ./build.sh` 通过。
3. 提交信息用祈使句、说清"为什么"；一个提交只做一件事。
4. 开 Pull Request，描述动机、改动范围、测试情况，关联相关 Issue。
5. 等待 CI（`swift test` + `swift build -c release` + `build.sh`）转绿并获维护者 review。

## 行为准则

参与即同意 [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md)。

## 许可

贡献即以 MIT 许可证授权你的代码。详见 [`LICENSE`](./LICENSE)。
