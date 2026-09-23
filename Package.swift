// swift-tools-version:6.0
// SeqAlignMac — SwiftPM 包定义（质量护栏）
//
// 本包把「纯领域逻辑」编译为可测试的 SeqAlignCore 库，并提供 SeqAlignCoreTests
// 单元测试目标（7 解析器往返、引物 Tm/ΔG/GC、翻译、撤销/重做、搜索 IUPAC、
// 质量/列统计、NEXUS charset、数据类型判定、颜色索引一致性）。
//
// 为什么这里只纳入这 10 个纯逻辑文件、而非全部 Sources？
// ContentView / AlignmentCanvasView / SeqAlignMacApp / ColorSchemes / ExportManager
// 依赖 AppKit / SwiftUI，无法在纯逻辑测试目标中编译。领域层（parser / writer /
// translate / primer / columnstats / search / undoredo / core / 残基字母表）保持纯净，
// 是「领域服务与渲染解耦」的具体落地。App 的二进制仍由 build.sh（swiftc）
// 单独构建，与本包互不冲突。

import PackageDescription

let package = Package(
    name: "SeqAlignMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SeqAlignCore", targets: ["SeqAlignCore"]),
    ],
    targets: [
        .target(
            name: "SeqAlignCore",
            path: "Sources",
            // 只用 sources 白名单圈定核心库（不再叠加 exclude）。若两者并存，
            // 新增核心文件时忘记加入 sources 会被静默排除在测试之外、制造假绿灯；
            // 仅保留 sources 后，未列入的文件同样不参与编译，且 CI 可对清单做 diff 检查。
            sources: [
                "AlignmentCore.swift",
                "ResidueAlphabet.swift",
                "AlignmentParsers.swift",
                "AlignmentWriters.swift",
                "TranslationTables.swift",
                "PrimerCalculator.swift",
                "ColumnStats.swift",
                "SearchEngine.swift",
                "UndoRedoManager.swift",
                "ColorLogic.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SeqAlignCoreTests",
            dependencies: ["SeqAlignCore"],
            path: "Tests/SeqAlignCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
