# SeqAlignMac 项目说明文档

**版本：** 0.1.0 · **文档类型：** 技术／项目说明文档 · **主语言：** 英文

> **语言说明：** 本系列的权威版本是英文 [DOCUMENTATION.md](DOCUMENTATION.md)。本中文版本与英文版逐节对应；如有任何出入，以英文版为准。文档索引见 [README.md](README.md)，任务导向的使用指南中文版见 [USAGE_ZH.md](USAGE_ZH.md)。

本文档中所有 `file.swift:LINE` 形式的代码引用都相对于仓库根目录（`Sources/…`、`Tests/…`、`build.sh`、`Package.swift`）。它们描述的是标签 `v0.1.0` 处提交的代码，也是核验本文任何一条陈述的最快途径。

---

## 目录

1. [目的与文档地图](#1-目的与文档地图)
2. [项目概述](#2-项目概述)
3. [仓库结构](#3-仓库结构)
4. [架构总览](#4-架构总览)
5. [数据模型参考](#5-数据模型参考)
6. [模块参考](#6-模块参考)
7. [格式读写规范](#7-格式读写规范)
8. [算法与方法](#8-算法与方法)
9. [渲染与性能](#9-渲染与性能)
10. [本地化架构](#10-本地化架构)
11. [持久化](#11-持久化)
12. [构建系统与质量门禁](#12-构建系统与质量门禁)
13. [命令行接口契约](#13-命令行接口契约)
14. [扩展指南](#14-扩展指南)
15. [已知限制与工程偏差](#15-已知限制与工程偏差)
16. [治理、发布元数据与参考文献](#16-治理发布元数据与参考文献)

---

## 1. 目的与文档地图

本文档回答的是**"它是怎么构建的、又是怎么工作的？"**。它的读者是开发者、评审者，以及任何需要本软件所产出数值之规范定义的读者。关于架构、格式行为、指标定义、构建规则与已知偏差，本文是唯一成文的来源。

| 问题 | 回答该问题的文档 |
|---|---|
| 这是个什么项目，值得看一眼吗？ | [`README.md`](../README.md)（以及 `README_ZH.md`） |
| 我怎样打开文件、着色、搜索、导出、运行比对器？ | [`docs/USAGE_ZH.md`](USAGE_ZH.md)（任务导向指南） |
| 软件内部如何工作，每个指标究竟算了什么？ | **本文档** |
| 我如何贡献、构建、测试？ | [`CONTRIBUTING.md`](../CONTRIBUTING.md)，加上本文的 §12 与 §14 |
| 攻击面、签名、撤销内存上限？ | [`SECURITY.md`](../SECURITY.md)，加上本文的 §12.5 与 §15 |
| 数据收集、隐私清单？ | [`PRIVACY.md`](../PRIVACY.md)，加上本文的 §12.6 |
| 最终用户参考手册（20 个编号小节，双语） | [`MANUAL_EN.md`](../MANUAL_EN.md) / `MANUAL_ZH.md` |
| 行为准则、许可证、引用 | [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md)、[`LICENSE`](../LICENSE)、[`CITATION.cff`](../CITATION.cff) |

**语言政策。** 英文为主；中文文件是由英文文本生成的镜像版本。`README.md` 与 `MANUAL_*.md` 是自成一体的双语配对。`CONTRIBUTING.md`、`SECURITY.md`、`PRIVACY.md` 与 `CODE_OF_CONDUCT.md` 目前是以中文为主导的文档，本文只加引用而不重复其内容。

**为什么现有文档保持原位。** `README.md` 与 `MANUAL_EN.md` 是既有的入口文档，带有稳定的外部链接（Zenodo、GitHub）。把它们挪走会破坏这些链接而毫无收益。真正改变的是*权威归属*：当既有文档与代码不一致时，以本文档为准，且该不一致会记录在 §15 中。旧文档行文里有两类常见错误，本文刻意不予复现——一是从 `Localization.swift` 里过时的应用内字符串继承而来的说法，二是对某个模块早期版本成立、如今已不成立的陈述。

---

## 2. 项目概述

### 2.1 它是什么

SeqAlignMac 是一个原生 macOS 应用，用于查看、编辑和分析多序列比对（MSA），并附带一个编译进同一可执行文件的无界面命令行模式。它读写七种比对格式——FASTA、FASTQ、NEXUS、PHYLIP、CLUSTAL、MSF、Stockholm——并透明处理 `gzip`/BGZF 解压；通过虚拟化的 Core Text 画布渲染任意规模的多序列比对（MSA）；计算比对质量统计、共识序列、序列 Logo、邻接法系统发育树、滑动窗口一致度、基于 17 张 NCBI 遗传密码表的六阅读框翻译，以及引物热力学。

分发元数据（`Info.plist:13-18`）将包标识命名为 `com.seqalign.mac`，显示名为 `序列对齐`，版本为 `0.1.0`。该可执行文件同时充当 CLI：`SeqAlignMac cli …`（`SeqAlignMacApp.swift:22-27`）。

### 2.2 设计目标

| 目标 | 在代码中的落实 |
|---|---|
| 原生 macOS 14+ | `LSMinimumSystemVersion` 14.0（`Info.plist:27-28`）、`.macOS(.v14)`（`Package.swift:19`）、`-target arm64-apple-macosx14.0`（`build.sh:70`）。SwiftUI 外壳内承载 AppKit 画布；不使用跨平台 UI 工具包。 |
| 极简单色界面 | 设计令牌位于 `MinimalTheme.swift`（`Minimal.*`）；默认配色方案是 `minimal`（`AlignmentCore.swift:15`、`SeqAlignMacApp.swift:123-132`）；没有 `.toolbar`，所有命令都经由侧边栏和菜单栏路由。 |
| 键盘驱动 | 完整的菜单快捷键映射（`SeqAlignMacApp.swift:433-567`）、一个含 32 条目的命令面板（`CommandPaletteView.swift:38-72`）、画布方向键、弹出面板级的 `.escape`/`.return` 绑定。 |
| 色觉障碍无障碍支持 | Okabe-Ito 调色板（`ColorSchemes.swift:138-149`，出处署名 Wong 2011）、高对比度模式（`SeqAlignMac.highContrast`）、空位斜线纹理、保守度轨道与灰度梯度——在单色打印下依然可辨。 |
| 双语界面 | 一张可在运行时切换的字符串表（§10）；没有 `.lproj`，也没有 `.strings`。 |
| 可复现的流程 | 具备显式错误的确定性解析器、`declared_aligned` 来源信息披露、生成的树中内嵌 NHX 抽样／模型来源信息（§8.7）、保留 gzip 的保存路径（§7.10），以及 CSV 契约固定的无界面命令行接口（§13）。 |

### 2.3 刻意的领域层／渲染层分离

后果最为重大的架构决策是：**没有任何分析结果依赖渲染器，渲染器也不承担任何分析**。全部数值工作——解析、统计、翻译、热力学、搜索、编辑命令、颜色*类别*的选择——都在十个不含 UI 的文件里，它们共同构成 `SeqAlignCore` 库。一切触及像素、窗口或响应链的内容都在应用层。

`ColorLogic.swift:2-7` 就最后剩下的那个边界情形给出了规则：核心只返回*索引*（`UInt8` 类别编号），而索引 → `NSColor` 的映射属于渲染关注点，保存在 `ColorSchemes.swift:199`。由此带来：

* 同一份颜色索引矩阵同时供给屏幕画布（`AlignmentCanvasView.swift:709, 811, 1005`）、图像导出器（`ExportManager.swift:139, 444, 604`）与离屏共识序列渲染器（`AlignmentRenderer.swift:106`）——屏幕、PNG/PDF/SVG 与打印三者不会互相漂移。
* 核心无需 AppKit 即可编译，也无需 AppKit 即可测试；这正是 110 项测试的测试套件得以成立的前提（§12.4），也是未来任何非 GUI 分发形态（服务端统计、Linux CI 校验器）成本极低的原因。
* 指标只在核心里定义一次，本文引用它们时取自核心的标识符，而非 UI 标签（§8）。

---

## 3. 仓库结构

纳入版本管理的内容共 59 个路径（`git ls-files`），名称全部为 ASCII；没有资源目录，没有 `.lproj`，也没有测试夹具目录（夹具直接内嵌在测试源码中，`SeqAlignCoreTests.swift:21`）。

```
SeqAlignMac-项目代码/
├── Package.swift                 (51)   SwiftPM manifest: SeqAlignCore library + test target
├── build.sh                      (172)  Whole-app pipeline: swiftc → .app → sign → zip
├── gen_icon.swift                (109)  Standalone AppKit script emitting icon.iconset (10 PNGs)
├── logo.svg                               Vector logo, copied into the bundle (build.sh:102)
├── Info.plist                    (283)  Bundle metadata, document types, UTI import declarations
├── SeqAlignMac.entitlements      (17)   App Store sandbox entitlements (opt-in, SEQALIGN_SANDBOX)
├── Resources/
│   └── PrivacyInfo.xcprivacy     (25)   Privacy manifest (NSPrivacyTracking=false, CA92.1)
├── .github/workflows/ci.yml      (62)   One workflow: test (macos-15) + lint (ubuntu-latest)
├── Sources/                               36 .swift files, flat directory, all compiled by build.sh
│   ├── [core, allow-listed in Package.swift:30-41]
│   │   ├── AlignmentCore.swift          (415)  Model, enums, SequenceUtils, error type
│   │   ├── ResidueAlphabet.swift        (276)  Residue semantics, names, charset remapping
│   │   ├── AlignmentParsers.swift      (1441)  Detection, 7 readers, .fai, GFF3, gzip/BGZF
│   │   ├── AlignmentWriters.swift       (394)  7 writers, name uniquification, checksums
│   │   ├── TranslationTables.swift      (479)  17 codon tables, six-frame translation, warnings
│   │   ├── PrimerCalculator.swift       (399)  IUPAC expansion, NN Tm, salt, dimer ΔG
│   │   ├── ColumnStats.swift            (694)  Quality, consensus, logo, p-distance, NJ, windows
│   │   ├── SearchEngine.swift           (376)  IUPAC/regex/KMP search
│   │   ├── UndoRedoManager.swift        (469)  Command pattern, transactions, memory budget
│   │   └── ColorLogic.swift             (216)  Byte → colour category index, viewport matrices
│   ├── [app / UI / CLI layer — not in the SwiftPM target]
│   │   ├── SeqAlignMacApp.swift        (1458)  @main, CLI dispatch, menus, Workspace, open/save
│   │   ├── AlignmentCanvasView.swift   (2029)  AppKit Core Text canvas
│   │   ├── Localization.swift          (2002)  AppStrings (433 fields), LanguageManager, L.s
│   │   ├── ContentView.swift, ContentView+Actions.swift, CenterPanelView.swift,
│   │   │   LeftSidebarView.swift, TabbedWindow.swift, TitleBarTabStrip.swift (10, dead),
│   │   │   CommandPaletteView.swift, SettingsView.swift, SheetViews.swift,
│   │   │   AnalysisSheets.swift, ExportPreviewSheet.swift, PrimerCalculatorView.swift,
│   │   │   TranslationOptionsView.swift, ExternalAlignerView.swift, StatsPanel.swift,
│   │   │   SharedUIComponents.swift, MinimalControls.swift, MinimalTheme.swift,
│   │   │   PanelResizer.swift, ColorSchemes.swift, AlignmentRenderer.swift,
│   │   │   ExportManager.swift, CLIRunner.swift (303)
├── Tests/SeqAlignCoreTests/
│   ├── SeqAlignCoreTests.swift     (717)  2 classes: SeqAlignCoreTests (30), CoreEnhancementTests (11)
│   ├── FormatRoundTripTests.swift  (614)  1 class (41)
│   └── EdgeCaseTests.swift         (360)  1 class (28)
├── README.md · README_ZH.md · MANUAL_EN.md · MANUAL_ZH.md
├── CONTRIBUTING.md · SECURITY.md · PRIVACY.md · CODE_OF_CONDUCT.md
├── LICENSE · CITATION.cff · .zenodo.json
├── docs/                                  This document set (DOCUMENTATION.md, USAGE.md, …)
└── [generated, git-ignored — .gitignore:14-16; NOT part of the source tree]
    ├── SeqAlignMac.app/                   build.sh output (arm64 Mach-O, Resources, _CodeSignature)
    ├── SeqAlignMac.app.zip                ditto distribution zip
    ├── .build/                            SwiftPM working directory from a previous build
    └── icon.iconset/                      transient icon staging (build.sh:87-99)
```

阅读这棵树时需要留意的几点：

* `Sources/` 是**扁平**目录，`build.sh:66-67` 会编译其中*所有* `*.swift` 文件，没有任何排除清单。随手丢进 `Sources/` 的多余文件会成为交付二进制的一部分。
* `Sources/` 里 26 个非核心文件对 SwiftPM 不可见（§12.1）。
* `TitleBarTabStrip.swift` 是一个只有 10 行注释的占位文件，保留它是为了让旧构建说明里的文件清单仍然对得上；真正在用的标签条是 `TabbedWindow.swift:294-356` 中的 `FloatingTabBar`（§15）。
* `SeqAlignMac.app/`、`SeqAlignMac.app.zip`、`.build/`、`.DS_Store`，以及工作树中可能存在的任何 `.mimosa/` 目录，都是**构建或工具产物**，不属于项目内容；提交中若新增前两者，CI 会直接失败（`ci.yml:49-54`）。

---

## 4. 架构总览

### 4.1 层级栈

核心分为四层。层的边界是*单向*的：某一层可以使用它之下的任意层，绝不允许使用它之上的层。

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  L3  SearchEngine · UndoRedoManager · ColorLogic                                  │
│      (search, edit commands + memory budget, residue → colour index)             │
├──────────────────────────────────────────────────────────────────────────────────┤
│  L2  TranslationTables · ColumnStats · PrimerCalculator                           │
│      (17 codon tables + six-frame engine · quality/consensus/logo/NJ/window ·    │
│       IUPAC degeneracy, nearest-neighbour Tm, dimer ΔG)                           │
├──────────────────────────────────────────────────────────────────────────────────┤
│  L1  AlignmentParsers · AlignmentWriters                                          │
│      (7 readers + detection + gzip/BGZF + .fai + GFF3 · 7 writers)                │
├──────────────────────────────────────────────────────────────────────────────────┤
│  L0  AlignmentCore  ⇄  ResidueAlphabet                                            │
│      (Alignment/Sequence/CharsetInfo, enums, SequenceUtils, DatatypeDetector,     │
│       CoreError)  ·  (gap/unassignable/undetermined semantics, name handling,     │
│       CharsetRemapper, AlignmentProvenance)                                       │
├──────────────────────────────────────────────────────────────────────────────────┤
│  APP  SeqAlignMacApp · Workspace · AlignmentCanvasView · sheets · ExportManager · │
│       ColorSchemes · CLIRunner                          (AppKit / SwiftUI, Foundation)│
└──────────────────────────────────────────────────────────────────────────────────┘
```

| 层 | 文件 | 契约（一句话） |
|---|---|---|
| L0 | `AlignmentCore.swift`、`ResidueAlphabet.swift` | 拥有数据模型，以及每个残基字节的*语义*；两个文件在文件层面互相引用，在类型层面无环。 |
| L1 | `AlignmentParsers.swift`、`AlignmentWriters.swift` | 把磁盘上的字节变成 `Alignment` 并写回原样，负责格式检测并抛出显式错误。 |
| L2 | `TranslationTables.swift`、`ColumnStats.swift`、`PrimerCalculator.swift` | 在 `Alignment` 之上做纯数值／生物学变换；无 I/O，无 UI。 |
| L3 | `SearchEngine.swift`、`UndoRedoManager.swift`、`ColorLogic.swift` | 交互形态的服务（查找、编辑、着色），其中仍然不含 AppKit。 |

核心内部观察到的向上调用记录于此，以免新代码无意间加深某一层：L3 模块会调用 L2/L0——`SearchEngine.swift:69, 118-126` 使用 `IUPACCode`（L2），`UndoRedoManager.swift:87, 294` 使用 `CharsetRemapper`（L0），`ColorLogic.swift:103` 使用 `AlignmentStatsCalculator.columnIdentities`（L2）。L0 的两个文件互相引用对方的类型（`AlignmentCore.swift:267-269, 325` → `ResidueAlphabet`；`ResidueAlphabet.swift:49-75, 85, 141, 204-241, 264` → `Datatype`/`CharsetInfo`/`Sequence`）。

### 4.2 导入规则

十个核心文件中在任何位置导入过的框架只有 **`Foundation`**（十个文件全部）与 **`Compression`**（`AlignmentParsers.swift`，用于 gzip/BGZF 的 raw-DEFLATE inflate/deflate）。这是一条可构建的不变式，而不是风格偏好：`Package.swift:30-41` 恰好只把这十个文件编译进 `SeqAlignCore`，因此其中任何一个文件一旦写了 `import AppKit` 或 `import SwiftUI`，`swift build`/`swift test` 就会失败——在测试为强制项的 CI 上同样如此。

### 4.3 应用侧拥有什么

| 关注点 | 归属 | 说明 |
|---|---|---|
| 场景图、菜单、键盘快捷键 | `SeqAlignMacApp.swift:34-45, 424-569` | 用的是 `WindowGroup` 而非 `DocumentGroup`；一棵 `SeqAlignCommands: Commands` 命令树。 |
| 每个标签页的视图模型 | `Workspace: ObservableObject`（`SeqAlignMacApp.swift:103-322`） | 持有共享的 `Alignment` 以及全部视图状态。 |
| 窗口／标签路由 | `WindowRegistry.shared`（`SeqAlignMacApp.swift:324-420`） | 见 §4.5。 |
| 文本渲染 | `AlignmentCanvasView.swift`（AppKit `NSView` + Core Text） | 见 §9。 |
| 调色板（索引 → `NSColor`） | `ColorSchemes.swift`（`ColorResolver`、7 套配色方案、按外观提供变体） | `minimal`、`defaultNucleotide`、`transitionTransversion`、`okabeIto` 提供浅色＋深色两种变体；`clustalX`/`zappo`/`seaView` 与外观无关，因此截图可与参考工具直接比对。 |
| 离屏渲染几何 | `AlignmentRenderer.swift`、`ExportManager.swift` | 复用画布的几何计算，使导出图像与屏幕一致。 |
| 子进程封装 | `ExternalAlignerView.swift` | 见 §15.4、§6.2.19。 |
| 本地化表 | `Localization.swift` | 见 §10。 |
| 偏好设置 | `SettingsView.swift`（加上 `AppSettings`） | 见 §11。 |

### 4.4 基于通知的菜单到视图桥接

`WindowGroup` 的命令是**全局**的，而每一处有意义的状态都是**按标签页**的。二者的桥接是一组 18 个 `Notification.Name`，声明在 `SeqAlignMacApp.swift:1426-1443`（`removeSelectedSeq`、`reverseComplement`、`insertGap`、`renameSeq`、`moveSeq`、`runAlignment`、`showPrimer`、`showSettings`、`showTranslate`、`showAbout`、`showGuide`、`showQualityReport`、`showCommandPalette`、`showExportPreview`、`pasteFromClipboard`、`tabStateChanged`、`tabDataChanged` 与 `lastTabClosed`），外加来自 `Localization.swift:1928` 的 `languageChanged`。其中 `tabStateChanged`、`tabDataChanged`、`lastTabClosed`、`languageChanged` 这四个名字由窗口根视图用 `.onReceive` 消费（`TabbedWindow.swift:160-173`），其余十五个由每个标签页的 `ContentView` 消费。

菜单按钮负责发出通知；每个 `ContentView` 通过一个私有的 `observe(_:_:)` 包装函数来观察——它封装 `NotificationCenter.addObserver(forName:object:queue:using:)` 并收集令牌（定义在 `ContentView+Actions.swift:17`，**15 处调用**位于 `:20-108`）——并且**每个处理函数都以同一个守卫开头**：

```swift
guard isActiveWorkspace() else { return }   // WindowRegistry.shared.activeForAction === workspace
```

由于每个打开的标签页都存在一个 `ContentView`，未加守卫的处理函数会在后台窗口里打开弹出面板；正是这个守卫（`ContentView+Actions.swift:113-115`），加上 `onDisappear`（`ContentView.swift:118-124`）里的令牌拆除，使这种一对多扇出成为安全。菜单可用状态与重新本地化用了第二个技巧：`SeqAlignCommands.body` 在 `body` 内部*读取* `registry.editRevision` 与 `lang.language`（`SeqAlignMacApp.swift:430-431`），于是二者任一变化时 SwiftUI 会让菜单树失效（撤销／重做条目的置灰、运行时的语言切换）。

有一处使用了错误模式的已知实例仍然存在：`performExport` 针对 `WindowRegistry.shared.activeForAction` 而不是拥有它的工作区发出提示浮层（`ExportPreviewSheet.swift:~250`）——见 §15。

### 4.5 窗口、标签页与注册表

* **没有 `DocumentGroup`。** 因此没有基于文档控制器的"最近打开"菜单，没有按文档的自动保存，窗口标题也是命令式设置的（`"SeqAlignMac — <name>"`，`TabbedWindow.swift`）。打开／保存由 `OpenFileManager` 与 `SaveManager` 手工实现（`SeqAlignMacApp.swift:623-760, 789-1010`）。
* **禁用原生标签页**（`NSWindow.allowsAutomaticWindowTabbing = false`，`SeqAlignMacApp.swift:573-585`），好让自研的标签条独占标签管理：`FloatingTabBar` 是一个 `NSTitlebarAccessoryViewController(.left)`，承载一个 36 点的 `NSHostingView`（`TabbedWindow.swift:294-356`）。
* `WindowRegistry.shared` 以 `ObjectIdentifier` 为键索引工作区，在一张弱引用映射中保存每个窗口的 `WindowTabsState`，并对外暴露 `workspaceOrder`、`allDirtyWorkspaces`、`editRevision`，以及——最关键的一个——`activeForAction = workspace(for: NSApp.keyWindow) ?? activeWorkspace`（`SeqAlignMacApp.swift:~400`）。每条菜单命令和每个通知处理函数都通过这个表达式解析自己的目标。
* `TabbedWindow` 保留**最近激活的 3 个**标签页的视图（LRU），其余标签用 `Color.clear` 占位，因此切换标签页不会重建状态。
* 每个标签页拥有自己的 `UndoRedoManager`（按标签页独立的撤销历史；`SeqAlignMacApp.swift:218, 1015-1090`）。
* 由 Finder／Dock 打开文件走 AppKit 的 `application(_:open urls:)`（`SeqAlignMacApp.swift:573-619`）——代码库里没有 `.onOpenURL`。窗口内的拖放打开是 `ContentView` 里的 `.onDrop`（`ContentView+Actions.swift:381-420`）：第一个文件载入当前标签页，之后的每个文件各开一个新标签页（间隔 0.1 秒）。
* 退出受守卫保护：只要有工作区处于脏状态，`applicationShouldTerminate` 就会弹出 `NSAlert`；而任何文档执行"保存并退出"失败时则**中止退出**（`SeqAlignMacApp.swift:587-619`）。`Info.plist:278-281` 中 `NSSupportsSuddenTermination` 为 `false`，正是为了让系统无法绕过该守卫。
* `SEQALIGN_DEBUG_OPEN_N`（环境变量）通过 `debugTargetWindowCount` 自动打开 N 个窗口——一个测试钩子。

### 4.6 GenerationToken 与版本失效

两套彼此不同的机制，二者都必需。

**`revision: UInt64`** 是*内容*令牌。它只在 `align.performLocked { … align.revision += 1 }` 内部被修改（`AlignmentCore.swift:105, 166`；应用侧的统一收口点是 `SeqAlignMacApp.swift:1042-1049`）。核心内部的生产者有 `padToMaxLength()`（`AlignmentCore.swift:166`）、`AddSeqCommand.undo`（`UndoRedoManager.swift:203`）、`MoveSeqCommand`（`:231, 238`）以及 `RemoveColumnsCommand`（`:307, 312`）。`BatchReplaceCommand`、`InsertGapCommand` 这类单独命令刻意*不*递增它——递增由应用包装层完成，因此每一条变更路径（直接编辑、撤销、重做、事务）都恰好递增一次。以其为键的缓存包括：`Alignment.length`（`AlignmentCore.swift:138-148`）、画布一致度缓存（`SeqAlignMacApp.swift:222-240`）、统计面板的去重键 `(ObjectIdentifier, revision, ConsensusMode)`（`StatsPanel.swift:51-66`），以及以 `(Alignment identity, revision at snapshot time)` 为键的滑动窗口一致度缓存（`AnalysisSheets.swift:296-323`）。

**`GenerationToken`**（`SeqAlignMacApp.swift:93-101`）是*意图*令牌：一个由 `NSLock` 保护的单调计数器。后台任务在提交时捕获其值，并在回到主线程的完成回调中，若令牌已经前移就直接提前返回。这正是快速反复开关弹出面板和搜索框也无害的原因：搜索（`SeqAlignMacApp.swift:291-311`）、文件载入（`loadGeneration`，`:691-745`）、画布列统计（`AlignmentCanvasView.swift:605, 646-659`，它额外三重校验 `=== align`、`revision` 和共识 `mode`）、质量面板（`SheetViews.swift:158-192`）、序列 Logo／树／滑动窗口分析的弹出面板预览（`AnalysisSheets.swift:72-84, 213-232, 296-323`），以及导出预览（`previewGeneration`）。`revision` 递增无法取消一个已过期的任务，而代次变化也无法告知你内容已经改变；设计上两者都保留。

### 4.7 四个微型视图模型

`Workspace` 刻意不拥有全部细碎状态，否则搜索框里敲一个键就会让整棵 SwiftUI 树失效。四个小型 `ObservableObject` 吸收了这些高频变更：

| 类型 | 行号 | 拥有什么 | 为什么要独立出来 |
|---|---|---|---|
| `SearchTextModel` | `SeqAlignMacApp.swift:51` | 搜索框的字符串 | 只有 `SearchBarView` 订阅它；输入不会触及画布。 |
| `LoadProgressModel` | `:59-69` | 进度值与 `cancelLoading`，由 `NSLock` 保护 | 进度由解析器线程写入；该标志必须能被任一线程读取和置位。 |
| `ToastModel` | `:72-89` | `ToastKind` 与消息，2.5 秒后自动清除 | 短暂的浮层状态不应参与文档级失效。 |
| `GenerationToken` | `:93-101` | 一个单调计数器 | 严格来说不是视图模型，但它纳入同一套拆分，方便弹出面板低成本地捕获令牌。 |

### 4.8 数据流

```
 file on disk
      │  (extension == .gz ? Gzip.decompress : identity)        AlignmentParsers.swift:1188-1234
      ▼
   Data bytes
      │  FormatDetector.detect(data.prefix(65_536))              AlignmentParsers.swift:14-42
      ▼
 AlignmentParser.parse(_:format:progress:)  ── .unknown → FASTA AlignmentParsers.swift:1425-1441
      │
      ├─ per-format reader → raw (name, description, residues, quality)
      ▼
 ParsedAlignment.finalize()                                      AlignmentParsers.swift:74-111
      │   · provenance from the RAGGED input  (ResidueAlphabet.swift:256-275)
      │   · empty→"SeqN", duplicate names→"_2/_3"
      │   · every byte through ResidueAlphabet.normalize
      │   · reject empty / all-gap rows  (CoreError.format)
      ▼
 Alignment  (class, NSRecursiveLock, revision, charsets, metadata)  ── shared by reference
      │        │                     │                    │
      │  snapshot()          snapshot()           snapshot()          snapshot()
      ▼        ▼                     ▼                    ▼                   ▼
 StatsPanel  SearchEngine      LogoCalculator        PhyloBuilder       AlignmentCanvasView
 (fusedScan) (KMP/IUPAC/regex) (Schneider–Stephens)  (p-dist + NJ)      (Core Text, virtualised)
      │                                                     │                    │
      └───────────────►  CLIRunner stats CSV  ◄─────────────┘                    │
                                                                            draw(_:)
      ▼
 AlignmentWriter.write*()  ──► bytes ──► (re-gzip if sourceIsCompressed) ──► file   ExportManager
                                                                                          │
                                                            PNG / PDF / SVG ◄──────────────┘
```

载入路径运行在 `DispatchQueue.global(qos: .userInitiated)` 上，进度回调按 ≥ 1 % 的变化量节流（`SeqAlignMacApp.swift:696, 723-735`）；无界面命令行路径则对整块缓冲区做格式检测，而不是只看开头 64 KB（`CLIRunner.swift:34-36`）。

---

## 5. 数据模型参考

### 5.1 `final class Alignment`

`AlignmentCore.swift:97-212`。它是一个**由 `NSRecursiveLock` 保护的引用类型**，而不是 struct，其理由记录在 `AlignmentCore.swift:91-96`：后台工作者（统计、搜索、序列 Logo、系统发育树、导出）会在主线程编辑模型的同时读取它。若采用拷贝语义，就只能在"无锁并发下的数据竞争"与"每次变更做一次完整拷贝"之间二选一。

| 成员 | 签名 | 行为与不变量 |
|---|---|---|
| `init` | `init(sequences:datatype:metadata:charsets:)` | 默认值 `[]`、`.nucleicAcid`、`[:]`、`[]`（`:115-121`）。 |
| `performLocked` | `<T> (() -> T) -> T` | 编辑命令的**唯一变更通道**；可重入，因此命令可以嵌套（`:125-129`）。 |
| `seqCount` | `Int` | 加锁计数（`:131-135`）。 |
| `length` | `Int` | 每条序列残基数的**最大值**——并非"公共长度"；模型允许长度参差的行。以 `revision` 为键通过 `_cachedLength` / `_cachedLengthRevision` 缓存，初值为 `UInt64.max`，因此首次访问一定会重新计算（`:138-148`）。 |
| `padToMaxLength()` | `Void` | 用 `'-'` 对每一行做右端填充，并用 `0`（Q0，刻意不用 `'!'`，从而模型不在质量值中保留任何 ASCII 语义）填充每个 `quality` 数组，然后 `revision += 1`（`:154-167`）。 |
| `residue(row:col:)` | `UInt8` | 任何越界的行**或**列（包括负数）都返回 `0x2D`；在范围内时返回原始字节，**不**做 `.`→`-` 归一化（`:170-178`）。 |
| `columnResidues(col:)` | `[UInt8]` | `col < 0` → 返回全空位数组；较短的行贡献 `'-'`（`:181-188`）。 |
| `snapshot()` | `Alignment` | 对残基*和*质量数组的深拷贝，并连同数据类型、元数据、字符集一起复制（`:193-202`）。后台调用方必须使用它，不得引用那个活跃的类实例。 |
| `lockedSequences` | `<T> (([Sequence]) -> T) -> T` | 在锁内的读取访问；返回的值不得把内部数组引用带出闭包（`:204-211`）。 |

存储属性：`sequences`、`datatype`、`metadata: [String:String]`、`charsets: [CharsetInfo]`、`revision: UInt64 = 0`、`provenance: AlignmentProvenance.Status = .unknown`、`private let lock = NSRecursiveLock()`。

### 5.2 `struct Sequence` 与 `struct CharsetInfo`

```swift
struct Sequence {                       // AlignmentCore.swift:68-81
    var name: String
    var description: String             // header text after the first whitespace
    var residues: [UInt8]               // one ASCII byte per residue, uppercased by parsers
    var quality: [UInt8]?               // FASTQ Phred values, positional; nil unless FASTQ
}

struct CharsetInfo {                    // AlignmentCore.swift:83-89
    var name: String
    var ranges: [(start: UInt32, end: UInt32)]   // 1-based, inclusive
    var originalSpec: String? = nil               // raw NEXUS CHARSET text, e.g. "1-60\3"
}
```

* 解析器会把残基**转为大写**，并且用 `CoreError.format`**拒绝非法字节**而不是把它们丢弃；悄悄丢掉一个字节会使下游每一个残基都发生位移（`AlignmentParsers.swift:151-168, 780-784`）。
* 按声明，`quality` 与残基一一对应。填充时插入 `0`（`AlignmentCore.swift:150-165`）；`+33` 的 ASCII 转换只发生在写出阶段（`AlignmentWriters.swift:373-393`）。
* 保留 `originalSpec` 原文，是为了让 NEXUS 写出器能够往返步进记法，而不必把 `1-60\3` 展开成 `1-1 4-4 7-7 …`（`AlignmentWriters.swift:100-109`）。**任何**列重映射都会将其丢弃（`ResidueAlphabet.swift:220-221, 241`）。

### 5.3 残基字母表：三个层级

`ResidueAlphabet.swift` 的存在是为了消除一类有记录的缺陷——字节 `'.'` 在各解析器之间曾有三种不同行为，而蛋白数据却在用*核苷酸*的 IUPAC 集合做过滤（`:4-13`）。因此残基语义被刻意划分为三个互不相同的集合，混淆它们会得出错误的数值：

| 层级 | 集合 | 适用位置 | 定义 |
|---|---|---|---|
| **空位（gap）** | `'-'` (0x2D)、`'.'` (0x2E)、`'~'` (0x7E) | 从所有分母与所有分子中排除 | `gap = 0x2D`（`:22`）；`isGap(_:)`（`:27-29`）；`normalize(_:)` 把任何写法都映射为 `'-'`（`:32`） |
| **不可指派**（"该性状无法计分"） | 核苷酸 14 个符号：`N R Y S W K M B D H V X ? *`；蛋白 5 个符号：`B Z X ? *` | **位点统计**（变异 / 简约信息 / 单态位点）的准入闸门 | `unassignableStates(datatype:)`（`:49-64`） |
| **未判定**（更小的集合） | 核苷酸：`N X ?`；蛋白：`X ? B Z` | 从列一致度的**分子与分母中同时移除** | `undeterminedSymbols(datatype:)`（`:70-75`） |

第 2 层与第 3 层之间的区分是有意为之且至关重要：一整列都是 `R`*确实*代表真实的保守（每条序列都同意它是嘌呤），而一整列都是 `N`，否则会被算成一致度 1.0。因此，全空位列**或**全未判定列的一致度为 `identity = 0`，并被计入"空位列"（`ColumnStats.swift:142-148`）。

本文件中还有：`nucleotideCharacters`——检测用的白名单 `"ACGTUNRYSWKMBDHV-.*"`，外加数字 `0x30…0x39` 以及 `?` 和 `~`（`:86-92`）——以及 Newick 名称辅助函数 `newickSafeName`（把 `" (),:;"` 替换为 `_`，`:105-107`）和 `uniqueNewickNames`（先做合法化清理，空名 → `"seq"`，冲突名 → `_2`、`_3`、…，`:111-128`）。

### 5.4 空位归一化

规范化发生在**解析期**，即在 `ParsedAlignment.finalize` 中，它把每一个字节都送入 `ResidueAlphabet.normalize`（`AlignmentParsers.swift:95`）。但直接构造或在外部被改动过的 `Alignment` 仍可能含有 `'.'`/`'~'`——例如经过某个 `ReverseComplementCommand`，或是手工搭出的测试模型——所以消费方必须用 `isGap` 重新判定，而不是与 `0x2D` 比较。`ColumnStats.swift:118-120` 和写出器自身的归一化路径（`AlignmentWriters.swift:13-18`）就是这么做的。`SequenceUtils.effectiveLength`（`AlignmentCore.swift:304-306`）是有记录的例外：它只判定 `!= '-'`，因此在"按长度排序（不计空位）"这个键上，`'.'` 和 `'~'` 会被当作残基计数。

> **坐标系——在针对该模型编写任何代码之前请先读这一段。**
>
> **内部索引是 0 基的。所有面向用户的坐标都是 1 基的。**
>
> * 0 基：`Sequence.residues` 的偏移、`Alignment.residue(row:col:)`、`columnResidues(col:)`、选区范围、画布列号、`dirtyColumns: Set<Int>`、`CharsetRemapper.shift` 中的 `removedColumns`，以及 `crop` 的 `startCol`/`endCol` 闭区间窗口。
> * 1 基：`CharsetInfo.ranges`（闭区间，NEXUS 语义）、GFF3 坐标（`AlignmentParsers.swift:1153-1154`）、CLI 的 `--start` / `--end`（`CLIRunner.swift:182-184`）、状态栏的 `Pos`（`cursorRow+1, cursorCol+1`）、导出序列的坐标，以及警告信息中的每一个帧号/列号（`.frameshift(name:column:)` 报告的是 `column + 1`）。
> * 越界哨兵值是**空位字节** `0x2D`，而不是错误：越界读取会静默返回 `'-'`（`AlignmentCore.swift:170-188`）。

### 5.5 比对来源信息

`AlignmentProvenance.Status` 是一个 `String` 枚举，case 为 `aligned`、`unknown`、`not-aligned`（`ResidueAlphabet.swift:256-261`）。`status(ofRaggedSequences:)`（`:264-275`）是在填充**之前**计算的：

| 条件 | 结果 |
|---|---|
| 输入为空 | `.unknown` |
| 原始长度不全相等 | `.notAligned` |
| 全部相等**且**至少有一个内部空位（列范围 `1..<count-1`，行需满足 `count > 2`） | `.aligned` |
| 全部相等且没有内部空位 | `.unknown`（与无空位的比对无法区分） |

消费方：`ParsedAlignment.finalize`（`AlignmentParsers.swift:77, 108`）、CSV 字段 `declared_aligned`（`CLIRunner.swift:91`）、统计面板中的橙色横幅（`StatsPanel.swift:239-245`）、`cli convert` 的传递（`CLIRunner.swift:265`），以及 `ignoreGaps` 的翻译输出——后者被强制设为 `.unknown`，因为去除空位后的行已与源列解耦（`TranslationTables.swift:371`）。

有两个事实必须分清：参差的输入**确实**会被显示——各行会被右端填充到 `length`；而定量分析**不会**被阻断；只有警告横幅加那个 CSV 字段在向用户提供提示。任何"未比对输入会使统计功能不可用"的说法都是错的。

### 5.6 辅助枚举

| 类型 | 取值（原始值） | 参考位置 |
|---|---|---|
| `Datatype` | `nucleicAcid = 0`、`aminoAcid = 1` | `AlignmentCore.swift:9-12` |
| `ColorScheme` | `defaultNucleotide = 0`、`clustalX = 1`、`zappo = 2`、`seaView = 3`、**`minimal = 4`（默认值）**、`transitionTransversion = 5`、`okabeIto = 6` | `:14-22`；原始值为 `Int32`，因为要与菜单 tag 和 `UserDefaults` 互通 |
| `GeneticCodeTable` | 17 个 case，其原始值为 NCBI 表编号 1–6、9–16、24、25、30 | `:24-42`，§8.10 |
| `PhylipVariant` | `sequential = 0`、`interleaved = 1`、`strict10Char = 2`、`fullnamePadded = 3` | `:44-49` |
| `TmMethod` | `nearestNeighbor = 0`、`wallace = 1` | `:51-54` |
| `DimerMode` | `selfDimer = 0`、`hetero = 1` | `:56-59` |
| `MsfType` | `na = 0`、`aa = 1` | `:61-64` |
| `AlignmentFormat` | `fasta, fastq, nexus, phylip, clustal, msf, stockholm, unknown` | `AlignmentParsers.swift:9-11` |
| `SearchScope` | `content = 0`、`name = 1` | `SearchEngine.swift:23-26` |
| `ConsensusMode` | `majority = 0`、`iupac = 1`、`strict = 2` | `ColumnStats.swift:54-58`；原始值与设置项选择器对应 |
| `TranslationDisplayMode` | `codonOnly = 0`、`aminoAcidOnly = 1`、`both = 2`、`ignoreGaps = 3` | `TranslationTables.swift:9-14` |
| `CoreError` | `io, format, noMem, invalidArg, outOfRange, unsupported, external, partial` | `AlignmentCore.swift:387-410` |
| `ProgressCallback` | `typealias (UInt64, UInt64) -> Void` = `(processed, total)` | `:383` |

`CoreError` 是全项目统一的错误通道：领域函数 `throw CoreError`，不存在全局可变的错误状态（`AlignmentCore.swift:412-415`），并且每个 case 渲染时都带一个中文前缀（`"IO 错误: …"`、`"格式错误: …"`、`"不支持的操作: …"`）。由于这些前缀被固化在 `LocalizedError` 的实现里，CLI 与抛出错误的文本都不做本地化——见 §15.7。

### 5.7 `DatatypeDetector`

`AlignmentCore.swift:323-379`。采样上限为 `maxSampleSeqs = 100`、`maxSampleResidues = 100`。`detect(_:)`（`:332-355`）：输入为空 → `.nucleicAcid`；步长 `step = ceil(seqCount / 100)`，因此最多检查 100 条序列；每条被采样的序列贡献**两个窗口**，一个长度为 `min(50, len)` 的头部窗口，以及一个从 `len / 2` 开始、长 50 字节的窗口（`:349-352`）。只要有一个字节不在 `ResidueAlphabet.nucleotideCharacters` 中，就立即判定为 `.aminoAcid`。

`datatype(fromDeclaration:)`（`:360-378`）是处理 NEXUS `DATATYPE=` 声明的唯一入口：转大写，把 `=` 换成空格，然后分词；若存在 `DATATYPE` 这个标记，就把它后面的内容与前缀 `PROT|AMINO|AA` → `.aminoAcid`、`DNA|RNA|NUC` → `.nucleicAcid` 做匹配；不含 `DATATYPE` 标记的裸声明，也会在去除空白后按同样方式匹配；无法识别 → `nil`，由调用方保留核苷酸默认值（由 `AlignmentParsers.swift:368` 调用）。

### 5.8 `SequenceUtils`

`AlignmentCore.swift:216-307`，共享的字节级工具箱：

* `reverseComplement(_:)` = 先反转再互补（`:224-226`）。
* `complement(_:)`（`:229-253`）先处理小写 `a/c/g/t/u`，然后是 `A↔T`、`U→A`、`C↔G`，完整的 IUPAC 简并配对 `R↔Y`、`K↔M`、`B↔V`、`D↔H`，自互补的 `S`/`W`/`N`，`'-','.','~' → '-'`，其余（`? * 0-9`）原样返回。`:220-223` 处给出的理由是：对简并编码做朴素的透传会得到*错误*的反向互补；`FormatRoundTripTests.swift:156-173` 与 `SeqAlignCoreTests.swift:492-503` 对配对表做了穷尽覆盖。
* `mutationType(_:_:)` → `0` 匹配、`1` 转换、`2` 颠换、`-1` 无法判定（`:264-282`）。空位对空位以及 `N` 对 `N` **不**算匹配；空位与核苷酸不可指派集合的判定先于相等性判定。注意该函数**没有数据类型参数**，因此不得用于蛋白数据（§15.9）。
* `gcContent(_:)` = `GC / (A+C+G+T+U)`——空位、`N` 以及所有简并编码都从**分母**中排除（EMBOSS 约定，`:285-301`）；当不含 ACGTU 时返回 `0`。这是唯一的 GC 实现；CLI 按序列对其做汇总（`CLIRunner.swift:122-139`）。
* `effectiveLength(_:)` — 见 §5.4。

## 6. 模块参考

### 6.1 核心模块（`SeqAlignCore`，10 个文件）

#### 6.1.1 `Sources/AlignmentCore.swift`（415 行）

**职责：** 数据模型、作为共享词汇表的各枚举、字节级序列工具、数据类型检测以及错误类型。**关键公开类型：** `Datatype`、`ColorScheme`、`GeneticCodeTable`、`PhylipVariant`、`TmMethod`、`DimerMode`、`MsfType`、`Sequence`、`CharsetInfo`、`Alignment`、`SequenceUtils`、`DatatypeDetector`、`ProgressCallback`、`CoreError`（§5）。**不变量：** 每次变更都经由 `performLocked`；`revision` 由调用方包装器每次变更递增一次；越界的残基读取返回空位字节而不抛异常；`length` 是一个*最大值*，因此参差模型既可表达也合法（§5.5）。

#### 6.1.2 `Sources/ResidueAlphabet.swift`（276 行）

**职责：** 残基*语义*的唯一权威来源，外加名称处理、字符集坐标重映射，以及"这到底算不算一个比对？"的判定。**关键公开类型：** `ResidueAlphabet`、`BlockAwareResidueCollector`、`CharsetRemapper`、`AlignmentProvenance`。**不变量：** 三层级残基模型（§5.3）不得被合并；`isGap` 是唯一合法的空位判定谓词；*任何*重映射都会丢弃 `originalSpec`，因此步进规格永远不会悄悄指向错误的列。

`BlockAwareResidueCollector`（`:140-185`）被 CLUSTAL（`:830`）、MSF（`:929`）和 Stockholm（`:1089`）使用。规则：空行会冲刷暂存的块；若该块对每个已有记录恰好给出一行，则归属**按行序**判定——正是这一点让重名的每条序列都能拿到自己的那一行；否则按名称归属并使用一个 `claimed` 集合，而同一个块内某名称的*第二次*出现会**新建记录**而不是拼接。以字典键做聚合会把两条同名序列焊成一条双倍长度的假序列（`:132-139`）；`FormatRoundTripTests.swift:354-366` 看守着这一点。

`CharsetRemapper`（`:193-244`）：`shift(_:removedColumns:)` 接受 0 基的被删列，在删除点处切分每个 1 基闭区间，把存活的索引按其之前被删除的列数向左平移，重新合并相邻区段，并丢弃 `originalSpec`；删除集为空 → 原样透传。`crop(_:startCol:endCol:)` 与一个 0 基闭区间窗口求交，并从 1 开始重新编号。`shift` 被 `RemoveColumnsCommand`（`UndoRedoManager.swift:294`）使用，`crop` 被 `cli convert --start/--end`（`CLIRunner.swift:249`）使用；`:246-248` 处的注释解释了另一种做法的后果——过期的 `CHARSET` 区间会为 MrBayes/RAxML/IQ-TREE 悄悄切错数据分区。

#### 6.1.3 `Sources/AlignmentParsers.swift`（1,441 行——最大的核心文件）

**职责：** 格式自动检测、七个比对读取器、`.fai` 读取/写出器、GFF3 读取器、gzip/BGZF 容器编解码、共享的后处理步骤，以及统一的解析入口。**关键公开类型：** `AlignmentFormat`、`FormatDetector`、`ParsedAlignment`、`FastaParser`、`FastqParser`、`NexusParser`、`PhylipParser`、`ClustalParser`、`MsfParser`、`StockholmParser`、`FaiIndex`/`FaiIndexer`、`GffFeature`/`GffParser`、`Gzip`、`AlignmentParser`。**不变量：** 检测只采样前 65,536 字节；每个读取器都以 `ParsedAlignment.finalize` 收尾（§7.11）；格式错误的输入抛出 `CoreError.format`，而不是悄悄产出一个看似合理的模型。逐格式规范见 §7。

#### 6.1.4 `Sources/AlignmentWriters.swift`（394 行）

**职责：** 七个写出器，包括交错式分块布局、名称的合法化与唯一化、CLUSTAL 的共识行、GCG 校验和，以及 Phred+33 的质量输出。**关键公开 API：** `AlignmentWriter.writeFasta/writeFastq/writeNexus/writePhylip/writeClustal/writeMsf/writeStockholm`（§7）。**不变量：** 空位在输出路径上被归一化（`:13-18`）；参差模型经由 `paddedSlice(_:from:to:)` 写出，从而每行恰好有 `NCHAR` 个字符（`:20-34`）；名称字段在 NEXUS/CLUSTAL/MSF 中补齐到 `max(20, longest)`，但在 PHYLIP 中被**截断**（§7.5）；`phylipUniqueName` 在固定宽度内用 `.1`、`.2`、… 消歧（`:121-140`），`msfUniqueName` 用 `_1`、`_2`、…（`:142-158`）。

#### 6.1.5 `Sources/TranslationTables.swift`（479 行）

**职责：** NCBI 密码子表，以及带披露警告的阅读框/显示模式翻译。**关键公开类型：** `TranslationDisplayMode`、`TranslationTables`、`TranslationWarning`、`TranslationResult`、`AlignmentTranslator`（§8.9–8.10）。**不变量：** 拒绝蛋白输入；移码绝不编造残基（它发出 `'X'`）；密码子+氨基酸混合轨道会在 `metadata` 中标记，以便下游消费方可以拒绝它；显示模式到数据类型的映射是固定的（`codonOnly`/`both` → `.nucleicAcid`）。

#### 6.1.6 `Sources/PrimerCalculator.swift`（399 行）

**职责：** IUPAC 简并度与展开、带盐校正的最近邻 Tm、基于 `String` 的 GC 含量，以及二聚体 ΔG。**关键公开类型：** `TmOptions`、`IUPACCode`、`NNTeplexParameters`、`PrimerCalculator`（§8.11–8.13）。**不变量：** 所有带参数的浓度在使用前都要校验（`:200-202`）；简并展开在 4,096 个变体处提前中止；结果是一个跨越各变体的 `(min, max)` 区间，而不是单个数字。

#### 6.1.7 `Sources/ColumnStats.swift`（694 行）

**职责：** 融合式列扫描、质量报告、共识解析、增量列统计、FASTQ 质量摘要、序列 Logo、p-distance + 邻接法，以及滑动窗口平均。**关键公开类型：** `AlignmentQuality`、`ColumnStats`、`ConsensusMode`、`AlignmentStatsCalculator`、`FastqQualitySummary`、`LogoColumn`、`LogoComputation`、`LogoCalculator`、`PhyloTreeResult`、`PhyloBuilder`（§8）。**不变量：** 在单一把锁下的一次行优先扫描同时产出一致度、共识序列与质量（`:110-126`）；`columnIdentities(_:)` 是声明中的逐列一致度唯一来源（`:338-340`，由 `ColorLogic.swift:103` 与 `CLIRunner.swift:117` 消费）；NJ 树总是带有来源信息注释（§8.7）。

#### 6.1.8 `Sources/SearchEngine.swift`（376 行）

**职责：** 针对残基内容或序列名称的 IUPAC 简并搜索与正则表达式搜索，带有 KMP 快速路径。**关键公开类型：** `SearchHit`、`SearchScope`、`SearchEngine`（§8.14）。**不变量：** `validateRegex(_:scope:)` 运行与初始化器*完全相同*的流水线，因此 UI 预检查绝不会与引擎产生分歧（`:362-375`）；KMP 命中保留重叠，正则命中则刻意不重叠；**引擎读取 `alignment.sequences[...]` 时不加锁**（`:190, 220, 247, 286`），因此它只在快照上才是安全的——应用正是这样使用它的（`SeqAlignMacApp.swift:295-297`）。

#### 6.1.9 `Sources/UndoRedoManager.swift`（469 行）

**职责：** 命令模式的编辑栈、事务、内存预算，以及脏列契约。**关键公开类型：** `EditCommand`、`sequenceBytes(_:)`、`RenameCommand`、`RemoveSeqCommand`、`ReverseComplementCommand`、`InsertGapCommand`、`BatchReplaceCommand`、`AddSeqCommand`、`MoveSeqCommand`、`SortSequencesCommand`、`RemoveColumnsCommand`、`ReplaceAlignmentCommand`、`UndoRedoManager`、`CompositeCommand`（§8.15）。**不变量：** 命令保存*增量*（有两个例外保留整个数组）；`pushUndo` 在超出任一预算时淘汰**最旧**的条目，但始终至少保留一条命令；新的 `execute` 会清空重做栈，而一个*空的*事务不会。

#### 6.1.10 `Sources/ColorLogic.swift`（216 行）

**职责：** 残基字节 → 颜色*类别索引*，以及视口索引矩阵，完全不涉及 AppKit。**关键公开类型：** `ColorComputer`（§8.16）。**不变量：** 索引 `0` 始终表示背景/空位，索引 `1…7` 是调色板类别；`effectiveScheme(_:datatype:)`（`:28-35`）保证荒谬的搭配永远到不了渲染器（核苷酸数据配蛋白专用方案 → `.defaultNucleotide`；蛋白数据配 `.transitionTransversion` → `.minimal`）；图例文本由驱动着色的同一个 `clustalXThresholdDefault` 常量生成，因此标签与行为不可能漂移（`:55-79`）。

### 6.2 应用侧模块

#### 6.2.1 `Sources/SeqAlignMacApp.swift`（1,458 行）— 引导与外壳

`@main struct SeqAlignMacApp: App`，配有 `@NSApplicationDelegateAdaptor`（`:20-21`），以及一个在构造任何 GUI *之前*就运行的 CLI 分支（`:22-27`）。它声明了唯一的 `WindowGroup`（`:34-45`，`minWidth 1100 × minHeight 520`，`.defaultSize 1500 × 880`，id `"seqalign-main"`）、整个 `SeqAlignCommands` 菜单树（`:424-569`）、`AppDelegate`（`:573-619`）、`OpenFileManager`（`:623-760`）、`SaveManager`（`:789-1010`）、`Workspace`（`:103-322`）、`WindowRegistry`（`:324-420`）、四个微型视图模型（`:51-101`）、`ZoomManager`（`:1112-1126`）、`CopyPasteRouter`（`:1187-1233`）、`UndoRedoCoordinator`（`:1012-1103`）、`ExportCoordinator`（`:1235-1326`）、`AppearanceStore`/`AppearanceManager`（`:1337-1377`）、`ColorSchemeManager`（`:1105`）、`CommandPalette`（`:1379`）、内置示例（4 条 BRCA1 序列，`:1396-1405`）、一次性的首次运行提示（`:1449-1458`），以及 18 个通知名（`:1425-1445`）。

值得注意的不变量：打开面板的扩展名允许清单是 `fasta, fa, fas, fastq, fq, nexus, nex, phy, phylip, aln, msf, sto, stockholm, gz`（`:623-700`）——决定使用哪个解析器的是*内容*嗅探，而非扩展名；最近文件上限为 10 个并做符号链接解析（`:781`）；`Workspace` 的初始化中有一个显式的"键缺失 ⇒ `.minimal`"特例（`:123-132`），任何向 `registerDefaults` 的迁移都必须保留它，否则默认配色方案会悄悄变成 `defaultNucleotide`（原始值 0）。

#### 6.2.2 `Sources/ContentView.swift` + `Sources/ContentView+Actions.swift`

每个窗口的根布局：侧栏 | 中心面板 | 统计面板，带 `PanelResizer` 分隔边界（`ContentView.swift:55-101`）以及 `.onDrop` 处理函数。`+Actions` 承载经其私有 `observe(_:_:)` 包装函数注册的 15 个通知处理函数（每个都由 `isActiveWorkspace()` 把关，`:113-115`；令牌拆除在 `ContentView.swift:118-124`）、排序动作（后台 Schwartzian 变换，带 `revision` 复检与 `attempts: 2` 重试，`:163-266`）、粘贴处理（`:340-379`）、空位列移除命令（`removeGapColumns(threshold: 1.0 / 0.5)`，以及它自己那段位于 `:322-334` 的空位计数循环），以及三处内联的中/英字符串分支（`:247, 258, 368`，§10.4）。已知缺陷：`.observingAppearanceChanges()` 被应用了两次（`:98` 与 `:103`）。

#### 6.2.3 `Sources/CenterPanelView.swift`

搜索栏、标尺、画布容器与状态栏（`:365-427`）。它持有 300 ms 的搜索去抖（`:36-40`）、范围胶囊与正则开关（`:28-40, 105-168`），以及 `AlignmentCanvasRepresentable` 的接线（`:294-344`：`differenceReferenceRow`、`dirtyColumnsProvider`、`onFontSizeChanged`、重命名/删除/移动/上下文动作/已复制/选区回调，其中选区回调只在确实发生变化时才写入 `@State`）。状态栏的字符集计数使用**硬编码的英文标签 `"Charset"`**（`:384`）。

#### 6.2.4 `Sources/LeftSidebarView.swift`（363 行）

应用中唯一的工具栏，分为五组（文件 / 分析 / 视图 / 导出 / 系统）。覆盖全部 7 种方案的方案选择器（`:245-296`）、提供六种格式的序列导出——**不含 FASTQ**（`:347-358`）、外观与语言按钮（`:192-200`）。翻译（Translate）与引物（Primer）是唯一会因蛋白质数据而额外禁用的按钮（`:78, 84`）；所有依赖数据的按钮在未加载比对时都会被禁用（`:58, 72, 90-114, 136, 149`）。

#### 6.2.5 `Sources/TabbedWindow.swift`（450 行）

`WindowRootView`（3 个标签页的 LRU 视图保留）、`FloatingTabBar`（`NSTitlebarAccessoryViewController(.left)`，`:294-356`）、`FloatingTabItem`（脏标记 `"• "`、悬停 ✕、右键关闭）、`WindowDelegateHandler`（`windowShouldClose` 的脏状态级联 → `UnsavedChangesView`；`windowDidBecomeKey` 重新登记路由），以及动态标题。`Sources/TitleBarTabStrip.swift` 是一个只有 10 行注释的占位文件：死代码（§15.1）。

#### 6.2.6 `Sources/AlignmentCanvasView.swift`（2,029 行）

`NSScrollView` 的 AppKit 文档视图。完整流水线见 §9；选区与命中测试契约见 §9.7。它还持有增量列统计的调度器（`:602-662`）和上下文菜单（`:1699-1760`），后者重复列出全部 7 种配色方案和各项排序键，其中包括 GC 含量（`:1711`）。其画布本地字符串是硬编码的中文（`:323, 350, 352, 380-388, 744, 784`），见 §10.4。

#### 6.2.7 `Sources/SharedUIComponents.swift`、`MinimalControls.swift`、`MinimalTheme.swift`、`PanelResizer.swift`

共享的 SwiftUI 构件。`MinimalTheme.swift` 是设计令牌（`Minimal.*`）**唯一**允许的来源（视图不得硬编码颜色，§14.6）；`NSAppearance.isDarkNow` 是唯一允许的暗色模式探测；`Minimal.shouldReduceMotion`（`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`）控制着空状态淡入、悬停动画与命令面板滚动。`SharedUIComponents.swift` 提供 `ThinScroller` 与 `ThinScrollerModifier`（`:281-287, 396-407`）、`EmptyStateView`（`:506-564`，从 bundle 中一次性加载 `logo.svg`，回退字符 "Σ"）、`LoadingOverlayView`（400×140，300-pt 进度条 + 取消按钮）、`ToastOverlayView`、`ErrorBannerView`（lineLimit 3），以及唯一的全局 `PendingWindowData` 元组（`:568-580`——既不保证线程安全，也不是按窗口隔离的，§15.8）。`PanelResizer.swift:23-24, 36-37` 定义了侧栏（150…320 pt）与统计面板（220…460 pt）的取值范围。

#### 6.2.8 `Sources/Localization.swift`（2,002 行）

`AppLanguage`、`LanguageManager`、`AppStrings`（433 个字段）、`L.s`，以及约 18 个计算属性。第 10 节对其做完整说明。

#### 6.2.9 `Sources/ColorSchemes.swift`

`ColorResolver`：七个调色板（索引 → `NSColor`），各有浅色与深色变体；`ColorSchemeLegend` 提供逐方案的图例文本（`:212-269`，Minimal 使用保守度分档）；以及 Okabe-Ito 代码块（`:138-149`，出处记为 Wong 2011）。它不属于 `SeqAlignCore`，因此调色板取值没有单元测试（§12.5）。

#### 6.2.10 `Sources/AlignmentRenderer.swift`

离屏绘制共识行以及其他导出图层，复用 `AlignmentRenderGeometry` 与 `ColorComputer`（`:106`），从而导出器与画布保持一致。

#### 6.2.11 `Sources/ExportManager.swift`

`ExportOptions`（`:24-47`）与用于 PNG/PDF/SVG 的 `exportImage(_:options:)`。参数：`format`、`dpi = 300`、`colorScheme`、`rowRange`、`colRange`、`fontSize = 13`、`nameColWidth = 150`、`showConsensus = true`、`dark`、`maxPixelWidth`。拒绝密码子+氨基酸混合轨道（`:70`，`CoreError.unsupported`）。PNG 应用位图预算护栏（`:342-345`，2,000,000,000 B）；PDF 显式关闭 `CGDataConsumer`，以便 xref 尾部正确；SVG 使用预留 1 MB 的分块缓冲区，配合 `escapeXML`、按名称的 `clipPath`，以及 `fill-opacity 0.16` 的空位矩形。错误字符串只有中文（§10.4）。`dpi` 在**任何地方都没有 UI 控件**，而 `showConsensus` 在两条导出路径上都被硬编码为 `true`（§15.5）。

#### 6.2.12 `Sources/ExportPreviewSheet.swift`（620×420）

336×256 缩略图、PNG/PDF/SVG 分段控件、"仅导出选区"（无选区时禁用）、暗色模式开关、体积估算、`.escape`/`.return` 绑定。预览**总是**一次 PNG 渲染，并被钳制到 `maxPixelWidth = 1600`，由 `previewGeneration` 丢弃过期图像；切换格式分段并不会重新渲染缩略图（§15.6）。它提供的是格式、仅选区、暗色模式和体积读数——**不包括**配色方案或字号，这两者只存在于 `ExportOptions` 和 CLI 标志中。

#### 6.2.13 `Sources/StatsPanel.swift`

常驻可见的右侧面板（可调整 220…460，默认 264）。卡片包括：概览；质量（当 `provenance == .notAligned` 时显示橙色 `statsUnalignedBanner`，`:239-245`，随后是池化一致度 `:247`、列一致度的均值/最小/最大 `:247-250`、空位列、总列数）；系统发育信息——变异位点/简约信息位点/单态位点就**在这里**，`:267-269`；保守度——5 个直方图分桶 `min(4, Int(v*5))`，并给出高保守（≥ 80 %）数字，`:270-298`；共识序列（可拖动、可复制，按列数报告）；适用时的 FASTQ 读段质量；光标；页脚 `statsMethodNote`（其措辞已过时——§8.2、§15.2）。去重键为 `(ObjectIdentifier, revision, ConsensusMode)`（`:51-66`），计算在 `.utility` 队列上进行并拥有自己的代次。

#### 6.2.14 `Sources/SheetViews.swift`

关于（`:26` 版本读数）、快速指南（8 + 8 条内联中英文步骤，`:84-111`）、重命名、移动、添加序列、未保存更改，以及**质量报告表单**。`QualityReportView` 的行（`:217-230, 240-253`）依次是：池化一致度、列一致度最小/最大、空位列、总列数、共识长度、FASTQ 平均 Phred / Q20 / Q30，然后是 NEXUS 字符集列表。它**不**显示 GC 含量，也**不**显示变异/简约信息/单态位点。质量刷新在 `:158-192` 上于主线程之外执行。

#### 6.2.15 `Sources/AnalysisSheets.swift`

Logo（720×400，`colsPerPage = 120`、截断提示、`maxBits` 2.0 / 4.3）、NJ 树（640×380，采样/钳制/模型的披露说明、`Copy Newick`）、滑动窗口图（640×380，滑块 `5…500` 步长 5，默认 50，`:245-364`，以 `(align, revision)` 为键的一致度缓存），以及 GFF3 注释浏览器（720×440，四列 Sequence/Type/Range/Name，每行带一个跳转按钮，**没有筛选控件**，`:369-430`；空位感知的 `sequenceToColumn` 映射 `:440-463`；`:494` 处调用 `GffParser.parse`）。

#### 6.2.16 `Sources/SettingsView.swift`（186 行）

`AppSettings` 加上偏好设置表单（宽 480，minHeight 440 / maxHeight 560，标签宽 92）。实际清单（`:50-162`）：外观分段控件；配色方案菜单（7 项）；字号步进器 8…28 pt（`:84-90`）；显示共识序列 / 高对比模式 / 聚焦变暗三个开关（`:96-101`）；ClustalX 相似度滑块 0.1…0.9 步长 0.05，以百分比显示（`:114-129`）；共识模式菜单 majority / IUPAC / strict（`:134-138`）；外部比对器超时步进器 30…3600 s 步长 30，默认 300（`:16-22, 150-162`）。只有一个 `settingsDone` 按钮（`.defaultAction`）——没有 Escape。语言**不在**这里（它在 视图（View）▸ 语言（Language）以及侧栏按钮上）；"密码子三联体显示"选项也不存在：`settingsCodonTriplet` 键虽在，却没有任何读取点（§10.4、§15.1）。

#### 6.2.17 `Sources/PrimerCalculatorView.swift`（500×460）

三个 `@AppStorage` 盐浓度字段（`:48-50`）被转换为 `TmOptions`（`:52-55`）；Tm 以 `"%.1f°C ~ %.1f°C"` 打印，并附带参数回显；GC 为 `%.2f%%`；二聚体 ΔG 为 `%.2f kcal/mol`，当 **ΔG < −5** 时以 `primerWarnDimer` 标记（`:252, 265`）。"从选区填入"会剥除空位。负值与非有限输入被拒绝；进行中的字符串被忽略。`dntpMolar` 在核心中已有建模（`PrimerCalculator.swift:16, 254-269`），但**没有对应的 UI 字段**（§15.3）。

#### 6.2.18 `Sources/TranslationOptionsView.swift`（560×400）

遗传密码选择器带 17 条字面英文条目并标注 NCBI 表编号（未本地化）、阅读框分段控件 −3…+3（`:79-86`）、显示模式分段控件（`:97-102`）、名称处理保留原名 / 追加 `_AA`（`:113-119, 171-175`），以及恰好**一个**开关——`translateNewWindow`，默认开启（`:124`）。执行流程：非核苷酸守卫 → toast；后台执行 `translateChecked`；警告用 `warningText(_:)` 以 `" · "` 连接；结果打开一个新窗口（`PendingWindowData.prepare` + `openWindow`），或者通过 `ReplaceAlignmentCommand` 替换当前比对，从而可撤销。没有 Escape 绑定（§15.10）。

#### 6.2.19 `Sources/ExternalAlignerView.swift`

预设（`:22-31, 28-33`）：

```
mafft     → mafft --quiet {input}                     (stdout capture)
muscle    → muscle -align {input} -output {output}
clustalw  → clustalw2 -infile={input} -outfile={output} -quiet
custom    → (empty, user text)
```

`captureStdout` 由用户实际键入的命令串推导——`!cmd.contains("{output}")`（`:146`）——而不是由预设名推导。流水线：主线程快照 → 在临时目录后台以 FASTA 写出 `seqalign_input_<UUID>.fasta` / `seqalign_output_<UUID>.fasta` → 占位符展开，或在没有占位符时通过 stdin 管道喂入（`feedsStdin`）→ 引号感知的 `parseCommandLine` → 可执行文件解析（先展开 `~`，否则依次探测 PATH 中的 `/opt/homebrew/bin`、`/opt/homebrew/sbin`、`/usr/local/bin`、`/usr/local/sbin`、`/usr/bin`、`/bin`，然后是 `/usr/bin/which`——六个候选，`:407`）→ 使用 `Process`，其 stdout 与 stderr 与 `waitUntilExit()` **并发**排空（避免管道缓冲死锁）→ 超时为 `max(10, AppSettings.externalAlignerTimeoutSeconds)`，先发 SIGTERM，+5 s 后发 SIGKILL（`:239-258`）→ 临时文件在 `defer` 中删除。**结果与输入的完整性校验** `resultMismatchReport` 比较序列数、名称集合（缺失与多余各最多报告 3 个名称）以及参差性，并且对于不匹配的结果**拒绝加载**。成功时打开一个新窗口，名称为 `"<file> (aligned)"`（后缀未本地化）。结果格式由同一个内容嗅探器自动检测；输入用 `AlignmentWriter.writeFasta` 写出（`:154`）。

#### 6.2.20 `Sources/CommandPaletteView.swift`

⇧⌘P；`CommandPalette.shared.toggle()` 只是发出 `.showCommandPalette`（`SeqAlignMacApp.swift:1379`）。32 个缓存条目（`:38-72`），每种语言只构建一次；过滤是在标题上做朴素的 `localizedCaseInsensitiveContains`——**子串匹配，不是模糊匹配**（`:80`）。↑/↓ 通过 `.onKeyPress`，Enter 执行，表单上的 `.keyboardShortcut(.escape)`，`selectedIndex` 在查询变化时重置，`ScrollViewReader` 居中定位受 `Minimal.shouldReduceMotion` 控制。配色方案条目覆盖 7 种中的 6 种——**没有** Okabe-Ito 条目（`:54-61`）；导出动作、查找下一个/上一个、撤销/重做、新建标签页/新建窗口、关闭标签页，以及 Logo/树/滑动窗口/注释这些表单也都不在其中（§15.11）。

#### 6.2.21 `Sources/CLIRunner.swift`（303 行）

无头前端；契约见 §13。分派发生在 `@main init()`（`SeqAlignMacApp.swift:19-25`）中，经由 `CLIRunner.run(args)` 完成，该函数签名为 `-> Never`，总是退出。

---

## 7. 格式读写规范

### 7.1 检测

`FormatDetector.detect(_ data: Data) -> AlignmentFormat`（`AlignmentParsers.swift:14-42`）
只解码**前 65,536 字节**（`data.prefix(65_536)`，`:16-17`），裁剪空白字符与字节序标记
（`:21, 46-58`），然后按下列严格优先级顺序依次测试：

| 顺序 | 测试 | 结果 |
|---|---|---|
| 1 | 大写化后的前缀 `#NEXUS` | nexus（`:26`） |
| 2 | 前缀 `# STOCKHOLM` | stockholm（`:27`） |
| 3 | 前缀 `!!AA_MULTIPLE_ALIGNMENT` / `!!NA_MULTIPLE_ALIGNMENT` | msf（`:28`） |
| 4 | 前缀 `@` | fastq（`:29`） |
| 5 | 前缀 `>` | fasta（`:30`） |
| 6 | *包含* `#=GF` | stockholm（`:31`） |
| 7 | *包含* `CLUSTAL` | clustal（`:32`） |
| 8 | 首行按空格/制表符切分为恰好 2 个 token，且两者都能解析为正 `Int` | phylip（`:34-40`） |
| 9 | 其他 | `.unknown` → **交给 FASTA 读取器处理**（`:1436-1438`） |

`decodeText`（`:46-50`）先尝试 UTF-8，再尝试 ASCII，并剥掉开头的 BOM —— 带 BOM 的文件过去会以
"illegal character 'ï'" 失败（`:44-45`）。唯一的分发点是
`AlignmentParser.parse(_:format:progress:)`（`:1425-1441`）。App 在分发之前对
`data.prefix(65_536)` 运行检测（`SeqAlignMacApp.swift:720-727`）；CLI 则对整个缓冲区运行检测
（`CLIRunner.swift:34-36`）。由于检测基于内容，扩展名标注错误通常仍能解析出正确格式 ——
但要注意到一个限制：超出 64 KB 采样窗口的标志性特征对它不可见。

### 7.2 FASTA

| 方面 | 行为 | 参考 |
|---|---|---|
| 检测 | 行首为 `>` | `AlignmentParsers.swift:30` |
| 解析 | 头部仅按**第一个空格**拆为 `name` + `description`；换行续行的序列行拼接；转大写；跳过空行 | `:116-193`, `:144-147`, `:150-168`, `:135` |
| 接受的残基字节 | `A-Z`, `0-9`, `-`, `*`, `?`, `.`；其他字节抛出 `非法字符 'x' 在第 N 行` | `:160-167` |
| 错误 | 文本无法解码；头部之后没有残基（文件中部与文件末尾）；完全没有记录 | `:118-120, 139-141, 178-180, 184-186` |
| 进度 | 每 **1,000 行**回调一次字节位置，最后给出 `(total,total)` | `:171-173, 189` |
| 数据类型 | 由 `DatatypeDetector.detect` 推断 | `:188` |
| 写出 | `>name[ description]`，`wrapWidth = 0` → 每条序列一行；当 `> 0` 时按 `Character` 偏移换行；空位归一化 | `AlignmentWriters.swift:37-56`, `:44-50`, `:16-18` |
| 有损 | FASTQ 质量值；结构化的逐头部字段 | — |

任何 app 或 CLI 调用点都从未传入非零的 `wrapWidth`
（`SeqAlignMacApp.swift:991`、`CLIRunner.swift:216`、`ExternalAlignerView.swift:154`），因此输出
始终是每条记录一长行。`:158` 处的白名单注释写的是"数字简并码（1-7）"，但实现出的范围是
`0x30…0x39`（`0-9`）—— 见 §15.9。

### 7.3 FASTQ

| 方面 | 行为 | 参考 |
|---|---|---|
| 检测 | 行首为 `@` | `AlignmentParsers.swift:29` |
| 解析 | 严格的 4 行记录；跳过空行；头部按第一个空格拆分；第三行必须以 `+` 开头 | `:197-275`, `:209, 214-217, 235-237` |
| 接受的残基字节 | `A-Z`, `-`, `*`；其他字节抛出错误 | `:225-230` |
| 质量解码 | 默认 `Phred+33`。**Phred+64 的判定是文件级、基于证据的：**只要曾经见到任何质量字节 `< 0x40`，该文件即固定为 Phred+33（`sawPhred33Evidence`）；仅当*迄今所有*字节都 `≥ 64` **且**存在某个字节 `> 74` 时，才按 `+64` 读取。低于偏移量的字节钳制为 0。以普通 Phred 数值存储在 `Sequence.quality` 中。 | `:249-260` |
| 错误 | 缺少残基行/`+` 行/质量行；头部不以 `@` 开头；质量字节数 ≠ 残基字节数（按 **UTF-8 字节**比较）；非法残基；空读段；没有记录 | `:211, 219, 233, 235, 239, 243-247, 262-264, 272` |
| 数据类型 | 强制为 `.nucleicAcid` | `:273` |
| 进度 | 节流至每 **4,000 条记录**一次，以避免每个读段一次主线程跳转 | `:266-270` |
| 写出 | `@name[ desc]`、残基、单独的 `+`、质量行 `0x21 + min(phred, 93)`；缺失位置用 `'!'`（Q0）填充 | `AlignmentWriters.swift:377-393`, `:386-388` |
| 有损 | `+` 行从不重复头部；读段组 / `B` 标签字段不解析；描述只作为第一个空格之后的自由文本保留；由于质量填充使用 `0`，被填充过的 FASTQ 列导出为 `'!'` | `AlignmentCore.swift:150-165` |

FASTQ 在保存时、以及在 `cli convert --format fastq` 时都**不会**被降级为 FASTA：会输出真实的
Phred+33 质量（`AlignmentWriters.swift:373-393`，回归测试 `EdgeCaseTests.swift:287`，CLI 路径
`CLIRunner.swift:217-223`）。任何声称相反的文稿都是错的。上限 `93` 是 ASCII 可打印的 Phred
极限（`0x21 + 93 = 0x7E`）：超过它的值在写出时钳制为 `~`。注意 `convert --format fastq` 要求至少
有一条带质量值的序列，否则抛 `CoreError.unsupported`（`CLIRunner.swift:221-223`）。

### 7.4 NEXUS

| 方面 | 行为 | 参考 |
|---|---|---|
| 检测 | 前缀 `#NEXUS` | `AlignmentParsers.swift:26` |
| 预处理 | `[...]` 注释在一切之前于**字节层面**剥离；用正则 `BEGIN\s+(\w+)\s*;(.*?)END\s*;` 查找块（大小写不敏感，`.` 匹配换行） | `:323-335`, `:337-352` |
| 消费的块 | `DATA`/`CHARACTERS`（matrix + datatype）与 `SETS`（charsets）。`TAXA` 被显式忽略（"标签来自 matrix"）；FEATURES、TREES、ASSUMPTIONS 以及任何其他块都**被静默丢弃** | `:302-303` |
| 数据类型 | 从 `FORMAT` 语句经 `DatatypeDetector.datatype(fromDeclaration:)` 得出 | `:365-371` |
| `DIMENSIONS` | `NCHAR` 会被捕获，且**仅**用于区分"同一分类单元的换行续行"与"同名的第二个分类单元" | `:373-383`, `:481-493` |
| 矩阵 | 支持带引号的分类单元名（`'…'`/`"…"`）；`&` 注释被替换为一个空格（于是 `&n` 模糊态简写丢失）；空行 = 交错式块边界；无名的续行一次性决定布局（`isInterleavedLayout = blockLineIdx >= nameOrder.count`）—— 交错式按块内行索引归属，顺序式归到最后一个具名分类单元；重复的分类单元名获得内部键 `name#orderIndex`，并且只在未达 `NCHAR` 时合并；每 2,000 行矩阵回调一次进度 | `:385-514`, `:426-442, 421-424, 419, 461-478, 479-496, 414-417` |
| 接受的残基字节 | `A-Z`, `-`, `?`, `*` —— **`'.'` 不被接受**，会抛出 "illegal character" | `:404-409`, `:455-459` |
| `SETS` | 正则 `CHARSET\s+(\S+)\s*=\s*([^;]+)`；各部分是 `start-end\step`、`start-end` 或单个值；step > 1 会展开为单列区间，而 `originalSpec` 保留字面文本 | `:531-535, 543-552, 555, 562-578` |
| 不支持的记法 | `PARTITIONS`、`STATES`、`SYMBOLS`、`LABELS`；小写的矩阵输入无论如何都会被转为大写 | `:448` |
| `metadata` | 硬编码为 `[:]` —— 没有任何 NEXUS 注释或 `[$NOTE=…]` 得以保留 | `:293` |
| 写出 | `#NEXUS`；`BEGIN TAXA; DIMENSIONS NTAX=…; TAXLABELS …; END;`；`BEGIN CHARACTERS; DIMENSIONS NCHAR=…; FORMAT DATATYPE=DNA\|PROTEIN MISSING=? GAP=-; MATRIX …`；可选 `BEGIN SETS; CHARSET name = spec; END;`；必要时给名字加引号；名字列填充到 `max(20, longest)` 且**从不截断**；行填充到恰好 `NCHAR` | `AlignmentWriters.swift:71-111`, `:61-69, 77-79, 91-95, 100-109, 20-34` |
| 有损 | 所有非 DATA/SETS 块、`[...]` 注释、逐字符与状态/频率注释，以及 `.` 与 `-` 两种空位写法之间的区别 | — |

`writeNexus(_:includeMetadata:)` 的 `includeMetadata` 默认为 `true`，但这个标志名有误导性：它
只控制 `BEGIN SETS` 块，因为元数据从来不会被写出（`AlignmentWriters.swift:71, 100`）。`'.'`
的不对称是一个真实的互操作性陷阱 —— 使用 `GAP=.` 的 NEXUS 文件会失败，而同一份文件作为 PHYLIP
或 CLUSTAL 却能解析：**不要宣称各格式对空位写法的容忍度是一致的。**

### 7.5 PHYLIP

| 方面 | 行为 | 参考 |
|---|---|---|
| 检测 | 首行 = 两个正整数 | `AlignmentParsers.swift:34-40` |
| 解析 | `ntax nchar`；丢弃空行；`dataLines.count < ntax` → `PHYLIP 数据行数不足：期望 N，实际 M` | `:591-611` |
| 接受的残基字节 | `A-Z`, `-`, `?`, `*`, `0-9`，以及 `'.'`/`'~'` **映射为 `'-'`**（丢弃它们会让下游每一个残基位移） | `:785-793`, 注释 `:780-784` |
| 变体判别 | `isStrict10Char` 要求 ≥ 11 个字符、第 1-10 列是不含空白的字母/数字/`._-` 名称、且第 11 列是形似残基的字节（"名称恰好填满 10 列"的情形，例如 `AF123456.1`，被显式处理）；随后解析并打分**四个候选**（顺序式 × 交错式 × 两种命名解释）：所有长度 > 0 加 2，全部相等加 3，全部相等且 `== nchar` 加 4，全部相等且 `<= nchar` 加 1，任一长度 > `nchar` 减 6；得分并列时保留在先的候选，即优先宽松命名 | `:613-638, 660-676, 679-697, 628-635` |
| 填充 / 错误 | 短于 `nchar` 的行用 `'-'` 右填充；某行读出到**零**个残基 → 显式报错，而不是静默给出一幅全横画布 | `:639-644, 652-656` |
| 写出 | 默认 `.interleaved`；头部 `ntax nchar`；`fullnamePadded` = `name + 2 spaces + full row`；`sequential` = 9 列名字 + 1 个分隔符，每行 60 个残基，续行缩进 10；`strict10Char` = 同样的 9+1 字段，每条序列一行；`interleaved` = 60 列的块，第一块为 `name + 2 spaces`，后续块缩进 12，块之间空行 | `AlignmentWriters.swift:161-220`, `:167-172, 173-193, 194-200, 201-217` |
| 有损 | 长于字段的名称被**截断**（`:123`）；描述丢弃；空位写法归一；顺序式/交错式的区别只能启发式地恢复 | `:113-120, 121-140, 620-627` |

app（`SeqAlignMacApp.swift:987`）与 CLI（`CLIRunner.swift:204`）都以默认变体调用
`writePhylip`，因此 `sequential`、`strict10Char` 和 `fullnamePadded` 的输出**具备写出能力但从
UI 或 CLI 无法到达**；只有测试会用到它们（`FormatRoundTripTests.swift:34, 48, 226, 577`）。
9+1 分隔符布局是有意不做成与经典 strict-10 字节严格一致的，而交错式的续行缩进 12 个空格、名字
字段却是 10 列 —— 所以"符合规范的 PHYLIP"这一说法必须始终加上限定（§15.9）。

### 7.6 CLUSTAL

| 方面 | 行为 | 参考 |
|---|---|---|
| 检测 | 前 64 KB 内任意位置出现 `CLUSTAL` | `AlignmentParsers.swift:32` |
| 无头部输入 | 接受 MAFFT 风格的正文：任何第 2 个及以后的 token 全为 `A-Z`/`-`/`*` 且不是保守性行的行；否则 `CLUSTAL 文件缺少 CLUSTAL 头` | `:810-828` |
| 解析 | 跳过版本横幅与 `MAFFT` 前缀；跳过保守性行（只含 `* : .` 与空格）；空行 = 块边界；`name residues…` 同时按空格**和**制表符切分；名字之后的所有 token 拼接，但仅由 `*:.` 构成的 token 除外 | `:841-874, 889-893` |
| 接受的残基字节 | `A-Z`, `-`, `*`, `?`；`'.'` → `'-'`；其他 → `CLUSTAL：非法字符 'x' 在行 N` | `:861-873` |
| 错误 | 残基为空的记录在 finalize 之前丢弃；没有记录 → `CLUSTAL：未找到任何序列` | `:881-884` |
| 写出 | 横幅 `CLUSTAL W (1.0) multiple sequence alignment`；60 列的块；名字填充到 `max(20, longest)`（不截断）；每块之后空行；可选共识行 | `AlignmentWriters.swift:266-290` |
| 共识符号 | 当所有非空位字节都相同时为 `*`；蛋白质：强相似组用 `:`，弱相似组用 `.`；**核苷酸：只用 `:`，绝不用 `.`** —— 借用蛋白质弱组 `["A","T","V"]` 会把一个 A/T 颠换列标成半保守；组表 `:233-245`，`IVL`/`FYW` 的抄录修正记录在 `:229-232` | `:247-264` |
| 有损 | 保守性行与质量分数不予保留；写出的横幅是固定字符串，而非来源版本 | — |

`writeClustal(_:withConsensus:)` 传 `true` 的用法**没有任何 app 或 CLI 调用点**
—— 只有测试（`FormatRoundTripTests.swift:344`）。

### 7.7 MSF

| 方面 | 行为 | 参考 |
|---|---|---|
| 检测 | 前缀 `!!AA_MULTIPLE_ALIGNMENT` / `!!NA_MULTIPLE_ALIGNMENT` | `AlignmentParsers.swift:28` |
| 解析 | 数据类型取自头部 token（AA → protein，NA → nucleotide）；声明长度取自 `MSF:` 行的 `Len:`；矩阵从恰好是 `//` 的那一行之后的行开始，否则 `MSF 文件缺少 '//' 分隔符` | `:905-906, 911-921, 924-927, 1000` |
| 名字/残基边界 | GCG MSF 的名字可占最多 20 列**并且可以包含空格**，因此每一行按空格切分为 token，并从右向左扫描，找到第一个非残基 token；其左侧全部是名字（保留内部空格），其右侧全部是残基 | `:941-958` |
| 接受的残基字节 | `A-Z`, `-`, `*`, `?`；`'.'` → `'-'`；其他 → `MSF：非法字符 'x' 在行 N` | `:961-975` |
| 一致性 | 若声明了 `Len`，任何实际长度与之不同的记录抛出 `MSF：序列 X 实际长度 … 与 MSF 头声称长度 … 不一致`；随后较短的记录用 `'-'` 右填充 | `:983-988, 991-997` |
| 写出 | `!!AA/NA_MULTIPLE_ALIGNMENT` 头部；`MSF: <checksum>  Type: P\|N  Len: <nchar>  Check: <checksum>  ..`；每条序列一行 ` Name: <padded> Len: <n>  Check: <"%4d">  Weight: 1.00`；`\n//\n\n`；50 列的块再细分为 10 残基一组；名字填充到 `max(20, longest)`，不截断，并以 `_1`、`_2`、… 去重 | `AlignmentWriters.swift:302-346`, `:142-158` |
| 按实现计算的校验和 | `Σ_i ((i mod 57) + 1) × ASCII(residue_i)`，然后 `mod 10000`；文件级数值是各序列校验和之和，mod 10000 | `:293-300, 307-309, 321` |
| 有损 | `Weight:` 恒为 `1.00`（任何原始权重都被丢弃且从不读回）；逐序列的 `Len:` 反映真实行长度，而矩阵按 `nchar` 写出，所以长度参差的模型会报出两个不同的长度；原始注释、超出 P/N 的 `Type:`、非规范的空位写法都不保留；读取时名字块区段（包括真实的 GCG ` DNA …`/` Rank` 参考行）被完全跳过，因为解析只在 `//` 之后才开始 | — |

`MSF:` 字段承载的是**校验和**，不是序列条数（`AlignmentWriters.swift:307-309,
321`，测试 `testMsfChecksumIsGcgValue`）；不要把它描述为记录数。

### 7.8 Stockholm

| 方面 | 行为 | 参考 |
|---|---|---|
| 检测 | 前缀 `# STOCKHOLM`，或头部任意位置出现字符串 `#=GF` | `AlignmentParsers.swift:27, 31` |
| 解析 | 头部必须是裁剪空白后的第一条非空白行，否则 `Stockholm 文件缺少 '# STOCKHOLM' 头`；解析在 `//` 处停止；`#=GF ID …` 与 `#=GF AC …` 成为仅有的两个 `metadata` 键；其他 `#` 行忽略；空行 = 块边界；序列行 `name residues` 按第一个空格切分 | `:1079-1146`, `:1084-1087, 1102, 1105-1109, 1103, 1114, 1101, 1117-1118` |
| `#=GC RF` | 追加到局部数组 `rf`，而该数组**从未被使用** —— 参考共识被读入后即丢弃 | `:1091, 1110-1113` |
| 接受的残基字节 | `A-Z`, `-`, `*`, `?`；`'.'` → `'-'`；其他 → `Stockholm：非法字符 'x'` | `:1120-1133` |
| 错误 | 没有序列行 → `Stockholm：未找到序列行` | `:1138` |
| 写出 | `# STOCKHOLM 1.0`；可选 `#=GF AC`（显式参数或 `metadata["AC"]`）；`#=GF ID`；`#=GF SQ <n>`；以空行分隔的 80 列块；含空格的名字中的空格替换为 `_`；结尾 `//` | `AlignmentWriters.swift:349-371`, `:365` |
| 有损 | 两个方向都**没有 `#=GC RF`**，没有 `#=GC SEQFILE` 或 `#=GS` 逐序列注释，除 `AC`/`ID`/`SQ` 之外没有 `#=GF` 键，没有插入/缺失状态列；`#=GF SQ` 会写出但不读回 | — |

### 7.9 非比对辅助格式

* **`.fai`**（`FaiIndex`/`FaiIndexer`，`AlignmentParsers.swift:1005-1072`）：读取器期望
  `name\tlength\toffset\tbasesPerLine\tbytesPerLine`（`:1026-1045`，错误
  `.fai 索引格式错误：<line>`）；写出器自行声明一个与默认 `wrapWidth = 0` FASTA 布局相符的
  **虚拟索引**，把 `length` 写为**无空位**的残基计数，并跳过长度为零的条目（`:1056-1067`）。
  app、CLI 或测试中都没有调用这两个函数中的任何一个：应把它描述为内部/工具例程，而非用户功能
  （§15.1）。
* **GFF3**（`GffFeature`/`GffParser`，`:1148-1184`）：宽容的行解析器，要求 ≥ 5 个制表符列且
  `start <= end`；第 9 列中的 `Name=` 属性会覆盖特征类型而成为显示名（`:1171-1177`）；对无法
  解码的输入返回 `[]` 而不抛错；坐标为**基于 1 的闭区间**（`:1153-1154`）。由注释浏览器消费
  （`AnalysisSheets.swift:494`）。

### 7.10 gzip 与 BGZF

`enum Gzip`（`AlignmentParsers.swift:1186-1423`）位于各格式读取器之外。
当**文件名扩展**为 `.gz` 时调用 `Gzip.decompress(_:) -> Data?`
（`SeqAlignMacApp.swift:705-711`、`CLIRunner.swift:284-293`），因此名为 `.fasta` 的 gzip 负载
不会被解压。

* 要求 `> 18` 字节且魔数为 `1F 8B 08`（`:1195-1197`）；只要魔数重复出现就循环处理成员
  （`:1203-1212`）；若什么都没解码出来则返回 `nil`。
* `decodeMember`（`:1293-1340`）跳过 10 字节头部，遍历 `FEXTRA` 子字段以寻找 BGZF 的 `BC`
  子字段（`0x42 0x43`，`slen 2`）从而得到 `BSIZE = value + 1`，处理 `FNAME`（`0x08`）、
  `FCOMMENT`（`0x10`）和 `FHCRC`（`0x02`）；对 BGZF 而言 deflate 负载止于
  `start + BSIZE - 8`，否则把文件的剩余部分当作一个成员；解压使用 `COMPRESSION_ZLIB`
  （raw DEFLATE）。
* **拒绝串联 gzip**（`:1214-1232`）：如果恰好只解码出一个非 BGZF 成员，而
  `hasBelievableSecondMemberBoundary`（`:1240-1260`）找到了一个可信的第二成员起点 ——
  `p` 处是魔数、`FLG` 的保留位 `0xE0` 为 0、且前 4 个字节作为小端 ISIZE 满足 `0 < le ≤ p` ——
  则返回 `nil`，于是 `cat a.gz b.gz` 会响亮地失败，而不是静默丢掉尾部。该启发式忽略了它的
  `firstUncompressedLength` 参数（`_ = firstUncompressedLength`，`:1241`），所以这项检查比周围
  注释所声称的更弱；而 `trailerMatches`（`:1263-1273`）和 `countGzipHeaders`
  （`:1276-1288`）**从未被调用** —— CRC32+ISIZE 尾部校验在代码里有文档却没有接线（§15.9）。
  去扫描*压缩*流中的 3 字节魔数会是错误的检验：10 MB 文件的假失败概率约 45 %，100 MB 时接近
  100 %（注释 `:1219-1228`）。
* `compress(_:)`（`:1346-1355`）：通过 `compression_encode_buffer` 做 raw DEFLATE，外面套上
  10 字节头部 `1F 8B 08 00 00 00 00 00 00 FF`，再加上 CRC32 + ISIZE 小端尾部；CRC 多项式
  `0xEDB88320`（`:1364-1376`）。保存来源为 `.gz` 的文档时会就地重新压缩
  （`SeqAlignMacApp.swift:890-893, 924-931`）；"另存为"会清除 `sourceIsCompressed`，所以副本是
  未压缩的（`:940`）。`cli convert`/`export` 从不压缩：它们把序列化得到的字节原样写出
  （`CLIRunner.swift:109, 170, 233`），命令行侧唯一与 gzip 有关的判断是*输入*解压，由输入文件的扩展名
  决定（`:284-294`）——应用在 `SeqAlignMacApp.swift:913-954` 的那条路径同样只看 `sourceIsCompressed`，
  从不看输出扩展名。
* 缓冲区大小：deflate 从 `max(input + input/1000 + 64, 64 KB)` 起步，带 6 次四倍扩容重试
  （`:1379-1400`）；inflate 从 `max(input × 8, 64 KB)` 起步，带 8 次重试（`:1402-1422`）。

### 7.11 共享后处理与错误策略

每个解析器都在 `ParsedAlignment.finalize(_:datatype:charsets:metadata:)`
（`AlignmentParsers.swift:74-111`）中收尾，顺序是：原始集合为空 →
`CoreError.format("未解析到任何序列")`（`:76`）；由**长度参差的**输入算出来源信息（`:77`）；
空名字 → `"Seq\(index+1)"`，重复名字 → `name_2`、`name_3`、…（`:85-94`）；每一个字节都过一遍
`ResidueAlphabet.normalize`（`:95`）；残基数组为空 →
`CoreError.format("序列 X 没有任何残基…")`（`:96-98`）；残基数组全为空位 →
`CoreError.format("序列 X 的残基全部为空位…")`（`:99-101`）；记录来源信息；然后
`padToMaxLength()`（`:108-109`）。

**策略：畸形输入显式报错。** SeqAlignMac 从不丢弃残基字节，从不静默截断记录，也从不返回某个
字节被跳过的部分模型 —— 因为删掉一个字节会让下游每一个残基位移，从而破坏同源性判断。可见的后果
是：不支持的字符抛出带定位信息的 `非法字符 'x' 在行/第 N 行` 错误；PHYLIP 缺少分隔符时抛出
"未读到任何残基"，而不是打开一幅全横画布；MSF 的 `Len` 不符时抛错而不是悄悄重新填充。两个有意
为之的例外是：(i) 未知的 NEXUS *块*，跳过它们是因为它们的缺失不会破坏矩阵（§7.4）；
(ii) GFF3，它返回空的特征列表而不抛错（§7.9）。

### 7.12 有损性汇总

| 格式 | **写出**时的截断 / 丢弃 | **读取**时的丢弃 | 静默回退 |
|---|---|---|---|
| FASTA | 质量值；结构化头部字段 | — | `.unknown` 格式路由到这里 |
| FASTQ | Phred 钳制在 93；填充的质量是 `'!'`；`+` 行省略头部 | 读段组/`B` 标签；第一个空格之后的描述 | Phred+64 只在有正面证据时才采用 |
| NEXUS | — | 每一个非 DATA/SETS 块；`[...]` 注释；`&` 注释；`metadata`（`[:]`） | 矩阵中的 `'.'` 是错误，不是回退 |
| PHYLIP | **名字被截断**为 10（或 9）列；描述丢弃；空位写法归一 | — | 变体由打分启发式选择 |
| CLUSTAL | 保守性行不保留；横幅是固定字面量 | 仅含 `*:.` 的 token | 接受无头部的 MAFFT 正文 |
| MSF | `Weight:` 固定为 `1.00`；名字块的参考行不写出 | 权重、注释、超出 P/N 的 `Type:` | — |
| Stockholm | 没有 `#=GC RF`，没有 `#=GS`/`#=GC SEQFILE`，只有 `AC`/`ID`/`SQ` | 所有其他 `#` 行、插入/缺失状态 | `#=GF SQ` 写出不读回 |

面向用户的导出入口是有意不对称的，文稿应当描述这种不对称而不是意图：侧边栏的序列导出菜单提供
**六种**格式（没有 FASTQ，`LeftSidebarView.swift:347-358`），通用"另存为"面板提供**五种**扩展
（`fasta/nexus/phy/aln/msf`，`SeqAlignMacApp.swift:822-828`），而 `saveAs(format:)` 本身支持全部
**七种**（`:846-874`）。

## 8. 算法与方法

每个小节给出**按实现写出的公式**（不是教科书形式）、源代码中记录的文献参考、参数取值与引用
位置。当 app 内的工具提示或较旧的文稿说法与此不同时，本节具有规范性，分歧则列在 §15。

### 8.1 融合列扫描与列一致度

`AlignmentStatsCalculator.fusedScan(_:columns:mode:)`（`ColumnStats.swift:62-205`）在**单一把
锁下按行主序遍历矩阵一次**（`:110-126`），逐列累加 `freqs[col]: [UInt8: Int]`（收录所有非空位
字节）与 `informativeCounts[col]`（收录既非空位、也不属于 `undeterminedSymbols` 的字节）
（`:106-124`）。动机（`:70-78`）很具体：三个公共 API 过去是三次列主序扫描，对一个
10,000 × 50,000 的模型而言这意味着约 50,000 次锁操作和约 100,000 个临时数组。可选的
`columns: ClosedRange<Int>` 会限制累加范围，但结果数组仍保持全长
（`:79-83, 116, 140`）；空模型（`nSeq == 0 || nCol == 0`）返回全空位共识、零一致度、以及清零的
`AlignmentQuality`（`:84-91`）。

**列一致度**（`ColumnStats.swift:142-160`）：

```
I_c = bestCount_c / informative_c
bestCount_c = max over residue bytes b of freqs[c][b]      (ties broken by the SMALLER byte value)
informative_c = |{ residues in column c that are neither a gap nor in undeterminedSymbols }|
```

若 `informative_c == 0` —— 该列全为空位，或者完全由 `N`/`X`/`?`（核苷酸）或 `X`/`?`/`B`/`Z`
（蛋白质）构成 —— 那么 `I_c = 0`，共识字节为 `'-'`，该列计为一个**空位列**（`:142-148`）。
以较小字节值决胜并不是装饰性的：正是它让共识输出与着色在各次运行、各平台之间保持确定性
（`:151-156`，增量路径在 `:301-307` 处镜像了同一条规则）。

> 分母是最常被描述错的部分。早先的一张公式表（"最高频非空位残基所占比例，不含空位"）漏掉了
> 对模糊态的排除；按那个定义，一列全 `N` 会得到 1.0 的一致度，而代码明确阻止了这一点。

### 8.2 池化一致度（位点加权），而非平均成对一致度

头条质量数值是字段 `pooledPairwiseIdentity`（`ColumnStats.swift:16-17`，在 `:166-171` 累加，
在 `:194` 定稿）：

```
                      Σ_c Σ_k f_k,c (f_k,c − 1)
pooled identity  =  -------------------------------
                      Σ_c  n_c (n_c − 1)
```

只对 `n_c ≥ 2` 的列求和，其中 `f_k,c` 是列 `c` 中残基类别 `k` 的频数，`n_c` 是该列的信息计数。
这是**按位点加权的池化一致度** —— 在信息位点上随机选取的*两个观测*相互一致的概率。它**不是**
对序列对取平均，

```
                     mean over pairs i<j of ( matches_ij / comparable_ij )
```

后者是加权方式不同的另一种统计量：池化形式按每个序列对拥有的可比位点数加权、按每一列的信息含量
加权，而且只需要单次遍历而非 O(n²m)。命名理由与这一区分写在 `ColumnStats.swift:9-16`，
UI 标签是正确的（"Pooled identity (site-weighted)"，`Localization.swift:1514, 1737`，
用于 `StatsPanel.swift:247` 与 `SheetViews.swift:218`），并且存在一个用于区分的测试
（`FormatRoundTripTests.swift:248`）。

两点相关说明，都很容易写错：

* **精确的**平均成对一致度在代码中确实存在 ——
  `meanPairwiseIdentityExact(_:maxSequencesForExact:)`（`ColumnStats.swift:342-372`）—— 对每个
  序列对按 `matches / comparable` 计算，其中某个位置可比当且仅当两个字节都不是空位
  （`:359-364`），可比位点数为零的序列对被排除（`:365`），并且除非
  `2 ≤ n ≤ maxSequencesForExact`（默认 **400**，`:348-351`）否则返回 `nil`，以便 UI 可以退回到
  标注池化数值。**它在整个 `Sources/` 中没有任何调用点**，因此绝不能把它呈现为用户会看到的
  数字。
* 统计面板的工具提示字符串 `statsMethodNote`（`Localization.swift:1639, 1863`）仍然写着
  "mean pairwise identity via column-frequency method"。这句话与代码矛盾，不得作为定义引用。

### 8.3 列一致度的最小值、最大值与均值；空位列

`minIdentity` / `maxIdentity` 是在 `informative > 0` 的列上递推的极值；`minIdentity` 以哨兵值
`2.0` 起始，若没有任何列符合条件则报 `0`（`ColumnStats.swift:136-137, 162-163, 197`）。
CLI CSV（`mean_column_identity`）中显示的均值是在本地按
`AlignmentStatsCalculator.columnIdentities` 取算术平均算出的（`CLIRunner.swift:116-120`），
即对各列取**非加权**均值，这同样是与 §8.2 不同的另一个量。

**空位列**统计的是*不存在可指派残基*的列：全为空位 **或** 完全为未判定（全 `N`、全 `X`、
全 `?`，或蛋白质侧的对应符号）（`ColumnStats.swift:142-147`，配合 `ResidueAlphabet.swift:49-64`
的 `unassignableStates`；测试 `FormatRoundTripTests.swift:265, 272`）。英文标签 "Gap columns"
以及尤其是中文标签"含空位列数"，都低估了它的含义；规范描述应为"没有可计分残基的列"。

### 8.4 变异位点、简约信息位点与单态位点

位点统计是针对 `unassignableStates(datatype:)` —— **更大的**那个集合，而非一致度排除集 ——
计算的，因此一个残基必须是*可指派*的才会被计入（`ColumnStats.swift:98, 173-191`；字段文档
`:22-24`）。对每一列，令 `definedTotal` 为已定义残基的计数、`definedDistinct` 为不同已定义状态的
数量、`definedMax` 为最大的状态频数、`definedMinTwo` 为出现至少两次的状态数量：

| 位点类别 | 按代码写出的判定 | 行 |
|---|---|---|
| 变异位点 | `definedTotal > 0 && definedDistinct >= 2` | `:184` |
| 简约信息位点 | 变异位点 **且** `definedMinTwo >= 2` | `:186-187` |
| 单态位点 | 其余情形下，`definedMax == definedTotal − 1` | `:188-189` |

按数据类型分流修正了一个蛋白质侧的 bug：标准氨基酸此前是用核苷酸的 IUPAC 集合来过滤的
（`:94-97`；测试 `testProteinVariableSitesCountStandardAminoAcids`）。这三个数值显示在右侧的
实时统计面板（`StatsPanel.swift:267-269`）以及 CLI CSV 中 —— **不**出现在质量报告表单里。

### 8.5 共识模式

`resolveConsensusByte`（`ColumnStats.swift:207-256`），由 `ConsensusMode` 选择
（`:54-58`，其 raw 值接到 `SettingsView.swift:24-25, 134-138` 的三选一选择器）：

| 模式 | 规则 | 行 |
|---|---|---|
| `.majority` | 最高频的残基字节（以较小字节值决胜） | `:215-216` |
| `.iupac` | 仅核苷酸（蛋白质退回多数模式）：位掩码 `A=1, C=2, G=4, T/U=8`；任何不在 ACGTU 之内的字节 → 退回多数模式；掩码 → 符号 `1→A 2→C 4→G 8→T 5→R 10→Y 6→S 9→W 12→K 3→M 14→B 13→D 11→H 7→V 15→N`，其他任何掩码 → 多数模式 | `:217-228, 237-256` |
| `.strict` | 若 `freq.count == 1` 则取该残基，否则为 `N`（核苷酸）/ `X`（蛋白质） | `:230-233` |

正交性在 `:51-53` 有文档说明，并且对可复现性很重要：**模式只改变共识字形。** 列一致度、保守度轨道、着色、NJ 树以及池化一致度始终使用多数规则，所以切换模式不可能改变任何定量结果。（注意
质量报告表单中 "consensus length"（共识长度）这一行实际上是**列数**，`SheetViews.swift:224` 处的代码
注释也承认了这一点。）

### 8.6 FASTQ 质量汇总

`FastqQualitySummary` / `computeQualitySummary`（`ColumnStats.swift:375-419`）在所有带有非空
`quality` 数组的行上做聚合（`:395-408`）：

```
meanPhred = Σ q / total bases      minPhred = min q          (0 when there is no data, :410)
q20Ratio  = #{ q ≥ 20 } / total    q30Ratio = #{ q ≥ 30 } / total   (:404-405)
readCount = number of rows carrying quality                   (:413-417)
hasData   = readCount > 0                                     (:383)
```

`readCount` 统计的是**行**；各项比率是按**碱基**计算的。这四个数值出现在统计面板、质量报告表单中，
并且 —— 只有在存在质量数据时 —— 出现在 CSV 字段 `fastq_mean_phred`、`fastq_q20_ratio`、
`fastq_q30_ratio` 中（`CLIRunner.swift:101-105`）。

### 8.7 香农熵与序列 logo

`LogoCalculator`（`ColumnStats.swift:421-489`）实现了带小样本校正的信息含量，依据 `README.md:82`
与应用内说明（`Localization.swift:1640`），其文献出处 **Schneider & Stephens 1990** 记录在 `:421`：

```
H(l) = − Σ_k p_k · log2 p_k                    over the STANDARD (assignable, non-gap) residues of the column
e(n) = (K − 1) / (2 · ln 2 · n)                n = number of counted residues in the column
R(l) = max(0, log2 K − H(l) − e(n))            K = 4 (nucleotide) or 20 (amino acid)
```

代码中的公式见 `:441-445` 与 `:466-474`。模糊残基**不会**被按比例重新分配——只有可指派状态
（assignable states）参与计数（`:455-459`），这正是模糊码很多的比对会得到比朴素实现更低的 `R`
的原因。logo 为每一列输出一个 `stacks`，元素为 `(residue, fraction)`，按 fraction 降序排列，
fraction 之和为 1（`:476-479`）；字母高度为 `fraction × R(l)`。

截断是有意为之并且是公开披露的：`maxColumns = 4000`（`:444`，另见 `:486`），而 `LogoComputation`
携带 `alignmentColumns`、`maxColumns`、`isTruncated` 与 `omittedColumns`（`:432-438`），UI 必须
显示它们（`AnalysisSheets.swift:19-20, 32-37, 76-85`；测试 `testLogoReportsTruncation`，
见 `FormatRoundTripTests.swift:465-474`）。之所以可能设置这种上限，是因为各列是通过*列主序* API
`AlignmentResidues`/`columnResidues(col:)` 读取的（`:457`），因此跳过尾部不会带来其他任何代价。
logo 工作表以每页 120 列分页，核苷酸使用 `maxBits = 2.0`，氨基酸使用 `4.3`
（`AnalysisSheets.swift`）。

### 8.8 基于未校正 p 距离的邻接法

**距离。** `PhyloBuilder.pDistance`（`ColumnStats.swift:524-538`）：

```
d_ij = 1 − matches_ij / comparable_ij
comparable  ⟺  neither byte is a gap (isGap)  AND  neither byte is N or X     (:531-533)
d_ij = 1.0 when no comparable site exists                                       (:537)
```

明确**不**施加 Jukes-Cantor 与 Kimura 校正（`:543`，注释"仍未做 Jukes-Cantor / Kimura 校正"）。
其后果由代码自己陈述，并且在任何文档中都必须写明：这棵树**只对低分化程度的近缘序列**站得住脚，
因为此时每个位点发生多次替换的情形很罕见。应用内的披露字符串是 `treeModelUncorrected`。

**抽样。** `sampledSequences(_:maxSeqs:)`（`ColumnStats.swift:511-522`）采用**等间隔（equidistant）**
步长，`step = count / maxSeqs`，默认 `maxSeqs = 200`（`:544, 560, 568`）——*不是*"取前 200 条"。
`:541-542` 处的意图注释（"而非固定取前 maxSeqs 条"）之所以存在，恰恰是因为那个误解曾被写进过文档；
NHX 注释写的是 "(even sampling)"（`:506`），并且有一个测试锁定了该行为
（`FormatRoundTripTests.swift:478`）。仍有两份文档和一条 UI 提示（`Localization.swift:1641, 1865`）
声称"前 200 条"；它们是错的，而同源字符串 `treeSampledNote` "抽样建树（等距）"是对的。

**树的构建。** `njTree(_:maxSeqs:provenanceComment:)`（`ColumnStats.swift:568-665`），参考文献
**Saitou & Nei 1987**（`:558`）。末端（tip）名称经过 `ResidueAlphabet.uniqueNewickNames`（`:574`）
处理。退化的规模：0 或 1 个分类单元 → `();` / `(name);`（`:590-595`）；**2 个分类单元 →
`(A:d/2,B:d/2);`**，从而保留该距离而不把它坍缩掉（`:596-603`，测试
`FormatRoundTripTests.swift:494-502`）。对于 ≥ 3 个分类单元，使用预先分配的 `(2n−1)²` 矩阵
（`:605-615`），并在 `active.count > 2` 期间套用经典判据（`:619-656`）：

```
rowSum_i = Σ_{j≠i} D[i][j]
Q(i,j)   = (m − 2) · D[i][j] − rowSum_i − rowSum_j
limb_i   = 0.5 · d_ij + (rowSum_i − rowSum_j) / (2 · (m − 2))
limb_j   = d_ij − limb_i
D[new,k] = (D[i,k] + D[j,k] − d_ij) / 2
```

负分支长度会被**截断（clamped）为 0 并加以计数**（`:576-580, 647, 651, 660`），以
`clampedBranchLengths` 报告，并由 `treeClampedBranches` 呈现给用户。Newick 中的数值使用 `"%.5f"`
（`:598, 647, 661`）。

**来源信息注释。** 默认开启，插入在根节点处（`:582-587`）：

```
[&sampled=<used>_of_<total>;model=p-distance;clamped=<n>]
```

其中 `distanceModel = "uncorrected p-distance"`（`:576`），`samplingNote` 由 `PhyloTreeResult`
生成（`:505-507`）。其伦理依据——一个只读 Newick 字符串的人也必须能够判断出该拓扑是从一个未校正
模型等距抽样得到的近似结果——记录在 `:493-495` 和 `AnalysisSheets.swift:214-217`。遗留的便捷 API：
`njNewick`（只返回 Newick，`:560-562`）与 `pDistanceMatrix`（`:544-556`）。

### 8.9 滑动窗口一致度

`slidingWindowIdentity(_:window:)`（`ColumnStats.swift:669-671`）在窗口内对逐列一致度取平均。
`windowAverages(from:window:)`（`:676-693`）要求 `window >= 2` 且输入非空，把 `w = min(window, n)`
截断，以 `max(1, w/2)` 为步长前进，将每个点放在窗口中心 `(start + end − 1) / 2`，并且**总是额外
输出一个末尾短窗口**，以免丢失右边缘（`:677-692`）。之所以拆成"一致度向量"与"窗口平均"两部分，
是为了让该向量能够独立于滑块缓存（`:672-675`；UI 缓存见 `AnalysisSheets.swift:252-254, 300-323`），
这正是拖动窗口滑块只花费 O(n) 而不是一次完整重扫的原因。UI 默认窗口 50，范围 5…500，步长 5。

### 8.10 六阅读框翻译、移码与内部空位

`AlignmentTranslator`（`TranslationTables.swift:267-479`）。入口点为
`translate(_:table:frame:displayMode:) throws -> Alignment`（`:277-282`）与
`translateChecked(...) -> TranslationResult`（`:289-373`）；`isMixedCodonTrack(_:)` 读取元数据键
`seqalign.translation.mixedTrack`（`:269, 376-378`）。

* **数据类型门禁。** 蛋白质输入会被拒绝：`translate` 抛出 `CoreError.format`（`:280`），
  `translateChecked` 返回 `.notNucleotideInput` 并把输入原样回送（`:296-300`）。所规避的缺陷类别在
  `:271-276` 有说明。（代价方面的提示：`translate` 是先通过 `translateChecked` *完成计算*再抛出的，
  因此一个蛋白质比对会被白白扫描一遍——§15.9。）
* **阅读框**（`:316-328`）。`frame < 0` → 先做反向互补，再偏移 `|frame| − 1`（`:320-324`）；
  `frame > 0` → 偏移 `frame`；`frame == 0` → 参考阅读框。UI 选择器把标签 −3, −2, −1, +1, +2, +3
  映射到**标识值（tag）−3…2**（`TranslationOptionsView.swift:79-85`），因此 "+1" 是 tag 0，"+2" 是
  tag 1，"+3" 是 tag 2。这种耦合对 API 使用者是个陷阱：直接调用 `translate(frame: 3)` 会偏移 3
  而不是 0——这套类枚举的阅读框语义是与 UI 耦合的，并不自洽（§15.9）。
* **显示模式**（`:330-349`）。`codonOnly` 返回经过阅读框校正的**核苷酸**序列；`aminoAcidOnly`
  使用 `translateFrameAware(padToCodon(work))`；`both` 按每个密码子 3 个碱基 + 1 个氨基酸交错排列
  （即仅供显示之用的混合密码子轨道）；`ignoreGaps` 移除全部空位，并对去空位后的字符串按列取碱基
  组成密码子进行翻译。
* **内部空位。** `translateCodon`（`:390-396`）：**密码子内出现任何空位 → `'X'`**；查表未命中 →
  `'X'`；表项为非 ASCII → `'X'`。`padToCodon` 用 `'-'` 在右侧补齐，使末尾不完整密码子不会被悄然
  丢弃（`:380-387`），这正是 `.lengthNotMultipleOfThree` 警告所描述的情形。
* **移码相位检测。** `translateFrameAware`（`:408-449`）找出第一段长度不是 3 的倍数的**内部**空位
  连续段（该段必须从下标 > 0 处开始，`:419`）；该列成为 `firstBadColumn`，从此往后的输出无条件为
  `'X'`，并返回第一个受影响密码子的*密码子序号*，用于 `.frameshift(name:column:)` 警告
  （`:424-448`）。另一种做法——反向翻译或凭空编造残基——会捏造数据；`FormatRoundTripTests.swift:194-208`
  锁定了 `X` 行为。
* **警告**（`TranslationWarning`，`:240-252`）：`frameshift`、`lengthNotMultipleOfThree(Int)`、
  `mixedCodonTrack`、`raggedOutput`、`notNucleotideInput`。当
  `mixedCodonTrack | raggedOutput | frameshift | notNucleotideInput` 中任意一项存在时，
  `TranslationResult.isSafeForPhylogenetics` 为 `false`（`:256-265`）。UI 会把适用的文本用 `" · "`
  连接起来（`TranslationOptionsView.swift`）。
* **输出标记**（`:356-372`）：`codonOnly`/`both` → `.nucleicAcid`（`both` 附带混合轨道元数据）；
  `aminoAcidOnly`/`ignoreGaps` → `.aminoAcid`；`ignoreGaps` 的输出被强制设为
  `provenance = .unknown`，因为它的各行已与源列脱钩。`:357-361` 处的注释解释了此举所避免的"把 A
  读成丙氨酸"这一隐患。序列名称并**不**由核心库加上后缀；`_AA` 是一个 UI 选项（`:350-353`，
  `TranslationOptionsView.swift:17, 113-119`）。
* 废弃的辅助函数 `translateNoGaps` / `translateBoth`（`:462-478`）已被 `translateFrameAware`
  取代，不得作为 API 写入文档（§15.1）。

### 8.11 17 张遗传密码表

`TranslationTables.standardTable`（NCBI 表 1）枚举了全部 64 个密码子
（`TranslationTables.swift:18-73`）；其余 16 种情形以叠加在其上的增量（deltas）方式表达，分派由
`table(for:)` 完成，采用**穷尽的 17 分支 switch 且没有 default**（`:214-234`）——因此不被支持的
NCBI 表号既无法到达，也不会静默回退。来源标注 "NCBI 标准翻译表（公开数据）" 见 `:3`。已实现的表号：
**1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14, 15, 16, 24, 25, 30。**

| 情形 | NCBI 表号 | 代码中写明的偏离 | 行号 |
|---|---|---|---|
| `.standardTable` | 1 | 完整的 64 密码子枚举 | `:18-73` |
| `.vertebrateMito` | 2 | ATA→M, TGA→W, AGA→\*, AGG→\* | `:76-83` |
| `.yeast` | 3 | ATA→M, CTT/CTC/CTA/CTG→T, TGA→W | `:87-96` |
| `.moldProtozoanMito` | 4 | TGA→W | `:99-103` |
| `.invertebrateMito` | 5 | ATA→M, TGA→W, AGA→S, AGG→S | `:106-113` |
| `.ciliate` | 6 | TAA→Q, TAG→Q | `:116-121` |
| `.echinodermMito` | 9 | AAA→N, AGA→S, AGG→S, TGA→W | `:124-132` |
| `.bacterial` | 11 | 与标准表相同（差异仅在起始密码子，不在表项中） | `:134-138` |
| `.altYeast` | 12 | CTG→S | `:141-145` |
| `.ascidianMito` | 13 | ATA→M, TGA→W, AGA→G, AGG→G | `:148-155` |
| `.flatwormMito` | 14 | AAA→N, AGA→S, AGG→S, TAA→Y, TGA→W | `:158-167` |
| `.blepharismaMito` | 15 | TAG→Q | `:170-174` |
| `.euplotid` | 10 | TGA→C | `:177-181` |
| `.chlorophycean` | 16 | TAG→L | `:184-188` |
| `.pterobranchMito` | 24 | TGA→W, AGA→S, AGG→K | `:191-197` |
| `.sr1` | 25 | TGA→G | `:200-204` |
| `.peritrichNuclear` | 30 | TAA→E, TAG→E | `:207-212` |

针对官方 `gc.prt` 语义的抽查由 `SeqAlignCoreTests.swift:634-686` 覆盖。这 17 个表号**是对本代码库
的陈述**；任何关于 NCBI 目前定义了多少张表的说法，都属于本仓库无法核实的外部事实，而"27 张中的 17 张"
这种措辞不应被当作代码事实重复引用。

### 8.12 熔解温度（Tm）

`PrimerCalculator.tm(_:method:options:)`（`PrimerCalculator.swift:179-223`）在所有 IUPAC 变体上
返回一个 `(min, max)` 区间。

**Wallace 规则**（`:184-196`，`README`/`MANUAL_EN.md:197`）：
`Tm = 2·(A+T+U) + 4·(G+C)`。

**最近邻法**（`:197-221`，核心在 `calculateNNTm`，`:226-282`），参考文献 **SantaLucia 1998
统一参数**（`:4`，参数表见 `:138-149`），ΔH 单位为 kcal/mol，ΔS 单位为 cal/(mol·K)：

| 最近邻 | ΔH | ΔS | 最近邻 | ΔH | ΔS |
|---|---|---|---|---|---|
| AA/TT | −7.9 | −22.2 | CT/AG | −7.8 | −21.0 |
| AT | −7.2 | −20.4 | GA/TC | −8.2 | −22.2 |
| TA | −7.2 | −21.3 | CG | −10.6 | −27.2 |
| CA/TG | −8.5 | −22.7 | GC | −9.8 | −24.4 |
| GT/AC | −8.4 | −22.4 | GG/CC | −8.0 | −19.9 |

十个唯一的双链堆叠（duplex）已与其反向互补等价项折叠合并（`:136-137`）；当直接给出的二核苷酸查不到
时，查找会再尝试其反向互补（`:239-252`）。

**末端（螺旋起始）校正**（`:151-167`），施加于两端：5′/3′ 端的 G·C 使 `ΔH += 0.1`、`ΔS += −2.8`；
A·T 末端使 `ΔH += 2.3`、`ΔS += 4.1`。`:152-155` 处的注释明确警告不要再同时加上通用的 `0.2 / −5.7`
起始项，否则会造成重复计算。

**盐浓度校正 —— von Ahsen 路线**（参考文献见 `:4`，实现见 `:254-270`）：

```
saltMm = [Na+] · 1000
if [Mg2+] > 0:  freeMg = [Mg2+] − [dNTP]        (mM)
                if freeMg > 0:  saltMm += 120 · √freeMg      ← dNTP chelation modelled
ΔS += 0.368 · (n − 1) · ln( max(saltMm / 1000, 0.001) )
```

**方程**（`:272-281`）：

```
Tm = ΔH · 1000 / ( ΔS_salt + R · ln(C_T / x) ) − 273.15
R = 1.987 cal/(mol·K);   C_T = oligo concentration;
x = 1.0 for a self-complementary (palindromic) sequence, else 4.0;
guarded by |denominator| > 1e-10.
```

回文性是通过与反向互补比较来判定的，使用本地的 `complementChar`（`:284-299`），它只处理
`A/T/C/G/U`。

**校验与失败模式**（全部为 `CoreError.unsupported`）：`naMolar > 0`、`mgMolar >= 0`、
`oligoMolar > 0`（`:200-202`）；变体中含有 `A C G T` 以外的字符——例如 `U` 或空位（`:208-210`）；
简并展开超过 **4,096** 个变体（`:195, 220`）；没有任何可计算的变体（`:215-217`）。默认值
（`TmOptions`，`:10-18`）：`naMolar = 0.05` M、`mgMolar = 0.0`、`oligoMolar = 0.25e-6` M、
`dntpMolar = nil`；UI 把它们呈现为 50 mM Na⁺、0 mM Mg²⁺、0.25 µM 寡链
（`PrimerCalculatorView.swift:48-56`）。**`dntpMolar` 没有对应的 UI 输入框**，因此用户目前无法校正
Mg²⁺ 的螯合效应（§15.3）。参考向量测试：`SeqAlignCoreTests.swift:517`（源自 OligoCalc 的基准样例，
NN 法 Tm 误差在 1 °C 以内），`FormatRoundTripTests.swift:517-537`（相对 Biopython `Tm_NN` 的
55.46 °C / 62.13 °C ±1.5，Mg → 等效 Na 的一致性达 1e-6，以及螯合会移除 Mg 项）。

### 8.13 简并度与二聚体自由能

**简并度**（`IUPACCode.degeneracy`，`:77-107`）：逐位置相乘，其中 **min** 跳过空位并把简并码按 1
计，**max** 把空位按 ×1 计、把模糊码按 × |展开集| 计（`:93-105`）；溢出时通过
`multipliedReportingOverflow` 饱和到 `UInt32.max`（`:88-92`）——用 4^16 做了测试
（`EdgeCaseTests.swift:130-151`）。**展开**（`expand(_:)`，`:24-47`）使用标准的 IUPAC 集合，其中
`N → [A,C,G,T]` 有意不含 `N` 自身（`:41-44`）。`expandAll(_:limit:)`（`:110-130`）一旦
`results.count * expanded.count > limit` 就立即停止（默认 **4096**，`:114-117`）。
`DegeneracyScope`（`:69-72`）已定义但从未使用（§15.1）。

**搜索专用的展开** `expandForSearch(_:)`（`:56-62`）是有意不同的：它在 `expand(code)` 之外**再加上
字面字符本身**，再加上 `T↔U` 等价，然后去重并排序——这是为了让非正则查询 `NNN` 能匹配数据中字面
出现的 `N`，与正则字符类 `[ACGTN]` 的语义相同（`:49-55`）。

**二聚体 ΔG**（`dimer(_:b:mode:)`，`:322-370`；ΔG 核心 `:379-398`）：

```
inputs truncated to maxDimerInputLength = 200 characters          (:320, 324-331)
partner strand = reverseComplement(a) for .selfDimer, reverseComplement(b) for .hetero   (:326-332)
both strands must be ≥ 4 nt, else ΔG = 0.0                        (:334)
enumerate every 3′ suffix of a × every offset in the partner; extend the longest contiguous
complementary run over pairs AT TA GC CG AU UA                     (:360, 372-376)
score each qualifying run (run ≥ 4) with calculateWindowDg; keep the MOST NEGATIVE   (:336-369)

ΔG = Σ ( ΔH·1000 − T·ΔS )   over terminal correction + NN dinucleotides, with T = 310.15 K (37 °C)
```

返回值的单位为 kcal/mol。UI 在 `ΔG < −5` 时以 `primerWarnDimer` 给出警告
（`PrimerCalculatorView.swift:252, 265`）。有一处值得在调参前了解的实现不对称：窗口 ΔG 循环只查
`nnParams[direct]`，**没有反向互补回退**，这与 Tm 路径不同（`:390-395` 对比 `:239-252`）。

**字符串上的 GC**（`:308-314`）对 `String` 应用与 `SequenceUtils.gcContent`（§5.8）相同的规则——
即 `G+C` 除以 `A+C+G+T+U`。

### 8.14 搜索：IUPAC 匹配、正则转换与 KMP

`SearchEngine.swift`。构造（`:51-80`）按正则模式分支：

* **正则模式：** 通过 `uppercasingLiterals` 只对字面量做大写化（`:84-115`），它保留转义序列与字符类，
  从而 `\d`、`\b`、`\w`、`\s` 不会被反转成 `\D`、`\B`、`\W`、`\S`（`:82-83`）；随后**仅对 `.content`
  范围**执行 IUPAC 转换 `translatePattern`（`:308-342`）并使用
  `NSRegularExpression(options: [.caseInsensitive])`。若编译失败，则 `regex == nil`，内容搜索不返回
  任何结果——它**不会**退化到 IUPAC 路径（`:175-177`）。IUPAC→正则字符类对照表（`:345-360`）：
  `R→[AG] Y→[CT] S→[GC] W→[AT] K→[GT] M→[AC] B→[CGT] D→[AGT] H→[ACT] V→[ACG] N→[ACGTN]`，
  其余保持不变；用户自行书写的字符类 `[...]` 原样复制（`:321-333`），转义对同样原样复制
  （`:314-320`）。
* **非正则模式：** `patternSets = rawPattern.map(IUPACCode.expandForSearch)`（`:69`）；若每个集合
  都是单元素集，则构建 KMP 表（`:71-78`，`tryExactPattern` `:118-126`，`buildKMPNext` `:129-143`）。

三种匹配引擎：

| 引擎 | 行号 | 推进方式 | 重叠 |
|---|---|---|---|
| KMP | `:187-213` | 状态以 `kmpState = next[m-1]` 跨 `next()` 调用保留（`:196-200`），并配合持久化的扫描游标，因此 `findAll` 为 O(n)（`:44-46`） | 保留重叠——在 poly-A 中查找 "AA" 会报告全部 9 个位置（`EdgeCaseTests.swift:114-126`） |
| Regex | `:216-241` | `location + max(len, 1)`（`:231-233`） | 不重叠，因此 `\d+` 不会在 "12345" 内部重复命中；按序列缓存解码后的字符串（`:47-49, 218-222`） |
| IUPAC 集合匹配器 | `:244-261` | `currentPos += 1` | 重叠；对 ASCII 残基字节做 `assert`（`:268-270`），并留有 `T↔U` 等价的豁免出口（`:273-275`） |

**名称范围**（`:283-302`）：使用正则，或使用 `range(of:options:.caseInsensitive)`；名称命中以
`SearchHit(seqIndex:, position: 0, matchLen: 0, isNameHit: true)` 返回，从而画布会高亮整行。
`validateRegex(_:scope:)`（`:365-375`）运行与初始化器*相同*的大写化 + 转换流水线，因此 UI 的
预检不会与引擎的判定不一致（`:362-364`）；它在主线程被调用，见 `SeqAlignMacApp.swift:281`。空模式不
产生内容命中（`:171`），但 `validateRegex("")` 返回 `true`（`:366`）。协作式取消（cancellation）通过
`findAll(shouldStop:)` 实现（`:156-166`）。

### 8.15 撤销与重做：命令、事务与预算

`UndoRedoManager.swift`。设计思路是：**命令对象，而非整篇文档的快照**，只有两个存储完整数组的例外。
`protocol EditCommand`（`:8-20`）要求实现 `execute(on:)`、`undo(on:)`、`description`，并提供
`estimatedMemoryBytes`（默认 0，`:23`）与 `dirtyColumns: Set<Int>?`（默认 `nil`，`:24`）；
`sequenceBytes(_:)` 按每个残基一字节来估算快照大小（`:28-30`）。

`dirtyColumns` 契约（`:14-19`）是性能的关键所在：

| 取值 | 含义 | 效果 |
|---|---|---|
| `nil` | 影响范围未知 | 全量重算列统计 |
| `Set()`（空集） | 该编辑不涉及任何列统计（重命名、重排、移动） | 原样复用缓存 |
| 非空 | 仅这些列 | 精确重算这些列 |

| 命令 | 行号 | 保留的状态 | `dirtyColumns` |
|---|---|---|---|
| `RenameCommand` | `:34-50` | 旧名/新名 | `Set()` |
| `RemoveSeqCommand` | `:52-77` | 被移除的序列 | `nil`（撤销时把插入下标截断（clamped）到数组边界，`:66-76`） |
| `ReverseComplementCommand` | `:79-93` | 原始残基 | `nil` |
| `InsertGapCommand` | `:98-129` | 记录 `actualInsertPos` 的 `class` 对象 | `nil`，理由见 `:104-109` |
| `BatchReplaceCommand` | `:131-164` | 旧/新残基 | 若保持长度则为 `Set(pos..<pos+len)`，否则 `nil`（`:138-144`） |
| `AddSeqCommand` | `:169-205` | `class`，新增的序列 + 每行的前部补齐长度 | `nil`；撤销时通过裁剪抵消 `padToMaxLength` 的副作用，并递增 `revision`（`:195-201`） |
| `MoveSeqCommand` | `:210-240` | `class`，记录下来的 `actualInsertIndex` | `Set()`；针对 `from == to` 的空操作保护（`:224-225`） |
| `SortSequencesCommand` | `:244-266` | 完整的前/后数组 | `Set()`；内存 = 两个数组（`:256`） |
| `RemoveColumnsCommand` | `:270-314` | 完整的前数组**以及 charsets** | `nil`；单遍就地移除列（`:291-306`），`CharsetRemapper.shift` 的重映射（`:294`）在撤销时还原（`:311`） |
| `ReplaceAlignmentCommand` | `:316-352` | 数据类型/序列/charsets/元数据，**前**与**后**都保留 | `nil`；供就地翻译使用 |
| `CompositeCommand` | `:449-469` | 子命令 | 取并集，任一子命令为 `nil` 则结果为 `nil`（`:454-461`）；按逆序撤销（`:466-468`） |

**栈策略**（`:359-445`）：`maxStackDepth = 50`（`:361`）与 `maxStackBytes = 256 MiB`（`:365`，
理由见 `:356-358`）。当超出任一预算（budget）时，`pushUndo` 会驱逐**最老**的命令，但始终至少保留一条
记录（`:413-419`）；`undoCommand`/`redoCommand` 返回该命令，以便提示条能说出它的名字（`:422-435`）；
新的 `execute` 会清空重做栈（`:408`）；`clear()` 同时重置 `stackBytes`（`:437-444`）。测试：
`EdgeCaseTests.swift:236-248`。

**事务**（`:379-398`）：`beginTransaction()` 压入一个空帧（支持嵌套）；`execute` 追加到栈顶帧而不是
撤销栈；`commitTransaction()` **忽略空事务**，从而让重做历史得以保留（`:383-388`，测试
`testEmptyTransactionKeepsRedoStack`），把子帧折叠进父帧（`:389-392`），并在根层级把 2 条或更多命令
包装成一个 `CompositeCommand`（`:393-398`）。

**对于重复的相同编辑，不存在任何按键合并（keystroke coalescing）或归并规则。** 连续的按键会产生各自
独立的命令；唯一的聚合手段是显式的事务 API，由 `SeqAlignMacApp.swift:1066-1075` 的
`executeTransaction(_:)` 驱动。任何"输入会被合并成一步撤销"的说法都是错的。撤销/重做的执行在 app 层
被包装在 `performLocked { … revision += 1 }` 中（`SeqAlignMacApp.swift:1037-1057`），并且每个标签页
持有一个全新的管理器实例（`:218`）。

### 8.16 颜色类别索引

`ColorComputer`（`ColorLogic.swift`），是唯一把残基字节变成颜色*类别*的地方。

| 配色方案 | 索引表 | 行号 |
|---|---|---|
| `.minimal` | 单字节上下文：空位为 `0`，其余为 `3`（单个字节拿不到列一致度信息；这是已文档化的中性灰回退） | `:40-50` |
| `.defaultNucleotide`、`.transitionTransversion`、`.okabeIto` | `residueToDefaultIndex`：A→1, C→2, G→3, T/U→4, N→5, 空位→6，其余全部（所有简并码与未知残基）→7 | `:160-175` |
| `.clustalX` | `AVLIMFW`→1, `KRH`→2, `DE`→3, `NQST`→4, `CGP`→5, `Y`→6, 空位→0, 其他→7 | `:178-189` |
| `.zappo` | `AVLIMC`→1, `FWY`→2, `KRH`→3, `DE`→4, `STNQ`→5, `GP`→6, 空位→0, 其他→7 | `:192-203` |
| `.seaView` | `AILMVFWC`→1, `KR`→2, `STNDEQGP`→3, `HY`→4, 空位→0, 其他→7 | `:206-215` |

`computeViewport(_:scheme:rowStart:rowCount:colStart:colCount:identities:clustalXThresholdOverride:)`
（`:83-157`）返回一个大小为 `rowCount × colCount` 的行主序 `[UInt8]`，其中 `0` 表示背景/空位
（`:81-82, 90`）。它是边界安全的（超出模型的行/列保持 `0`，`:113, 118, 131`）；列一致度在调用方提供时
取自其缓存，并且只为需要它的两种方案重新计算（`:97-106`）；`.minimal` 把一致度映射到 5 级灰阶
`UInt8(max(1, min(5, round(identity·4) + 1)))`（`:115`），空位仍为 `0`（`:121`）；`.clustalX` 仅当
`identity >= threshold` 时才为该列上色，否则写入索引 `7`（`:139-153`），该阈值可注入以便测试
（`:138-139`）。`clustalXThresholdDefault = 0.3`，实际值在 `> 0` 的保护下从
`UserDefaults["SeqAlignMac.clustalXThreshold"]` 读取/写入（`:52-64`）；`isProteinOnlyScheme` 为
`{clustalX, zappo, seaView}`（`:19-24`），`effectiveScheme` 即 §6.1.10 中所描述的那层保护。

### 8.17 参数与常量清单

| 数值 | 含义 | 出处 |
|---|---|---|
| `65_536` | 用于格式探测的解码字节数 | `AlignmentParsers.swift:17`; `SeqAlignMacApp.swift:722` |
| `100` 条序列 / `50+50` 个残基 | 数据类型探测的采样（头部 + 中部窗口） | `AlignmentCore.swift:328-330, 349-352` |
| `1000 / 4000 / 2000` | 进度节流行数（FASTA / FASTQ / 其他读取器） | `AlignmentParsers.swift:171, 268, 417, 607, 837, 937, 1099` |
| `0.01` | 跳回主线程之前所需的最小进度增量 | `SeqAlignMacApp.swift:730` |
| `2.0` | `minIdentity` 中"无信息列"的哨兵值 | `ColumnStats.swift:136, 197` |
| `400` | 精确平均成对一致度的 `maxSequencesForExact` | `ColumnStats.swift:348` |
| `4 / 20`, `4000` | logo 字母表大小（K）与 `maxColumns` | `ColumnStats.swift:444, 446, 486` |
| `200` | NJ / p-distance 的 `maxSeqs`，按等距抽样 | `ColumnStats.swift:511-522, 544, 560, 568` |
| `"%.5f"` | Newick 分支长度精度 | `ColumnStats.swift:598, 647, 661` |
| `4096` | 简并引物展开上限 | `PrimerCalculator.swift:110, 195, 220` |
| `200`, `4`, `310.15` | 二聚体输入长度上限、最短互补连续段、ΔG 温度（K） | `PrimerCalculator.swift:320, 334, 360, 382` |
| `120`, `0.368`, `1.987`, `273.15`, `1e-10`, `0.001`, `1.0/4.0` | 盐系数、SantaLucia ΔS 系数、R、摄氏偏移、分母保护、盐浓度下限、自互补因子 | `PrimerCalculator.swift:257, 266, 269-280` |
| `0.05 M / 0.0 M / 0.25e-6 M / nil` | Tm 默认值 Na⁺ / Mg²⁺ / 寡链 / dNTP | `PrimerCalculator.swift:11-15` |
| `50` 条命令、`256 MiB`、`≥1` | 撤销深度上限、字节上限、至少保留一条 | `UndoRedoManager.swift:361-365, 416-418` |
| `0.3` | ClustalX 保守度阈值默认值 | `ColorLogic.swift:55` |
| `64` | 回退到全量扫描之前的 `maxIncrementalDirtyColumns` | `AlignmentCanvasView.swift:634-635` |
| `6.0` px | 低于该值时不再绘制字母的字形密度阈值 | `AlignmentCanvasView.swift:163` |
| `512` | 每次 `CTFontDrawGlyphs` 批处理的最大字形数 | `AlignmentCanvasView.swift:~919-997` |
| `60 / 50+10 / 80 / 20 / 10 / 9 / 12` | 块宽度与名称列常量（PHYLIP 与 CLUSTAL 为 60，MSF 为 50 且每 10 个残基一组，Stockholm 为 80，名称列最小 20，PHYLIP 名称列 10/9，交错式缩进 12） | `AlignmentWriters.swift:79, 122, 178, 186, 197, 204, 213, 268-269, 318, 329-330, 359` |
| `(i % 57) + 1`, `mod 10000`, `"%4d"` | GCG 校验和 | `AlignmentWriters.swift:294-300, 309, 321, 325` |
| `43 / 64 / 74 / 0x21 / 93` | Phred+33 偏移、Phred+64 偏移、Phred+64 判据阈值、Q0 写入字符、Phred 写入上限 | `AlignmentParsers.swift:254-257`; `AlignmentWriters.swift:386-388` |
| `10 / 18 / 8`, `0xEDB88320` | gzip 头部、最小文件大小、尾部大小；CRC-32 多项式 | `AlignmentParsers.swift:1195, 1203, 1328-1333, 1350-1353, 1367` |
| `13 pt`（范围 8…28）、`150`（80…2000）、`180`（150…320）、`264`（220…460） | 默认字号 / 名称列 / 侧栏 / 统计面板宽度 | `SeqAlignMacApp.swift:105, 1117-1125`; `AlignmentCanvasView.swift:118-190`; `PanelResizer.swift:23-24, 36-37` |
| `300`, `30…3600 step 30` | 外部比对器的超时默认值与 UI 范围；SIGKILL 在 SIGTERM 之后 5 s | `SettingsView.swift:16-22, 150-162`; `ExternalAlignerView.swift:239-258` |
| `300 ms` | 搜索去抖 | `CenterPanelView.swift:36-40` |
| `2.5 s` | 提示条自动清除 | `SeqAlignMacApp.swift:72-89` |
| `3` | 保持实体化的标签页数（LRU） | `TabbedWindow.swift` |
| `2 000 000 000` B / `1600` px | PNG 位图预算上限 / 预览最大像素宽度 | `ExportManager.swift:342-345`; `ExportPreviewSheet.swift` |
| `10` | 最近文件数量上限 | `SeqAlignMacApp.swift:781` |

---

## 9. 渲染与性能

### 9.1 虚拟化

`AlignmentCanvasView` 是 `NSScrollView` 的文档视图（几何信息见 `:118-190`；由
`AlignmentCanvasRepresentable` 包装，`SharedUIComponents.swift:375-410`）。可见的单元格条带由裁剪
矩形计算得出（`:439-442`）：

```swift
minCol = Int((clipRect.minX - nameColWidth) / cellWidth)
maxCol = Int((clipRect.maxX - nameColWidth) / cellWidth) + 1
minRow = Int((clipRect.minY - topBarHeight - consensusHeight) / cellHeight)
maxRow = Int((clipRect.maxY - topBarHeight - consensusHeight) / cellHeight) + 1
```

这四个值在任何 `stride` 之前都要先用 `max(0, …)` 夹紧、并用 `min(…, count-1)` 限制上界——注释
指出，未夹紧的 `0..<negative` 区间属于硬崩溃，而不是警告。只有 `[minRow…maxRow] × [minCol…maxCol]`
会被绘制，并且 `draw(_:)` 会把可见条带与 `dirtyRect` 求交集，因此滚动时只重绘新出现的那一条。
几何量：`cellHeight = fontSize × 1.4`；`cachedCellWidth = max(4, advance width of "A" in the
monospace font)`（即等宽字体中 "A" 的前进宽度），每次字体变更时测量一次（`:400`）；
`rulerHeight = 24`、`conservationRailHeight = 12`、
`topBarHeight = 36`、`consensusHeight = showConsensus ? cellHeight + 4 : 0`。

### 9.2 密度自适应字形：6.0 px 阈值

```swift
private static let glyphDensityThreshold: CGFloat = 6.0   // AlignmentCanvasView.swift:163
```

该阈值应用于残基（`glyphsEnabled = cachedCellWidth >= threshold && glyphCTFont != nil`，`:1017`）
以及共识行（`:833`）。当每列宽度低于 6 px 时，画布变成纯粹的颜色热力图：矩形仍然承载完整的列一致度
与调色板信息，但不再绘制任何字母。由于 `cachedCellWidth` 随字号线性缩放，阈值大约是在 8…28 pt 缩放
范围的底部被跨越——因此诚实的、面向用户的描述是"在最小的几档缩放级别下字母会消失，只剩下色块"，
而不是某个固定的缩放百分比。行高不受影响；这个开关只取决于宽度。

### 9.3 批处理的 Core Text 绘制与颜色分桶

`:919-997` 构建了快速路径：一张 128 项的字形表、`ensureGlyphCache` 在每个字号下解析一次
`CTFont`/`CGFont`/字形/前进宽度/ascent/descent，以及 `flushGlyphs()` 以每批 **≤ 512 个字形**发起
`CTFontDrawGlyphs`。`fillBundled(_:)` 把所有同色单元格的矩形合并进一条 `CGMutablePath` 并只填充
一次。残基被分桶为 **8 组背景/文字颜色对**（`:999-1204`），因此最坏情况下每次重绘约需 16 次路径
填充加上少量字形批处理，**与选区大小无关**。

绘制顺序（`draw(_:)`，`:417-543`）：表面背景 → 保守度轨道 → 搜索概览刻度线 → 悬停下划线 →
列标尺 → 共识行 → 序列名称 → 残基 → 选区 → 整列块 → 搜索高亮 → 拖动指示器 → 名称列分隔线 →
焦点环 → 列悬停提示 → **最后绘制冻结的名称条带**。

### 9.4 冻结的名称条带

`pinnedNamesRange`（`:138`）在 `clip.bounds.origin.x >= nameColWidth` 时启用，也就是真正的名称列
已经滚出视口之后。`activeNamesRange`（`:146`）与 `namesBoundaryX`（`:151`）会对命中测试重新映射，
使得落在浮动条带内的点击仍然能定位到正确的行。针对裁剪视图 `boundsDidChangeNotification` 的观察者
（`installScrollObserverIfNeeded` / `clipBoundsChanged`，`:236-264`）会同时使旧条带与新条带的矩形
失效；条带最后重绘（`:524-542`），其下垫有一层卡片色底，因此是不透明的。

### 9.5 传统滚动条

`SharedUIComponents.swift:375-410`：两个滚动条都存在，`autohidesScrollers = false`，滚动条类被
替换为 `ThinScroller`（6 pt 的圆角滑块，悬停或拖动时 α 为 0.55，其余情况为 0.35），并设置
`scrollView.scrollerStyle = .legacy`（`:408`）——注释解释叠层式滚动条会自动隐藏，而长比对序列需要
一条始终可以抓取的横向滚动条。`ThinScrollerModifier.applyToAllScrollViews` **有意跳过**那些
`documentView is AlignmentCanvasView` 的滚动视图（`:284`），因此画布保留传统滚动条，而侧边栏、
统计面板和弹窗列表得到细滚动条；由于 SwiftUI 会重建视图，它会在 1.5 s 后再运行一次。

### 9.6 主线程外的列统计

画布在一个专用串行队列（`DispatchQueue(label: "seqalign.canvas.stats", qos: .userInitiated)`）上
调度列统计，并且最多只有**一个在途任务**（`AlignmentCanvasView.swift:640-662`）。每次编辑之后它都会
取出 `Workspace.takeCanvasDirtyColumns()`（`:602-632`）：若该集合非空且列数不超过
`maxIncrementalDirtyColumns = 64`，就用 `computeColumnStats(_:prevStats:dirtyColumns:mode:)`
（`ColumnStats.swift:271-314`）增量重算，规则**完全相同**（包含同票裁决，`:284-311`）；`nil` 表示
范围未知，`[]` 表示没有任何变化；超过 64 列则回退为后台全量扫描（`:631, 640-662`）。除非
`=== align`、`revision` 与共识 `mode` 三者全部仍然匹配，否则结果会被丢弃（`:605, 646-659`）。
当统计不可用时，画布**降级为不上色，而不是阻塞主线程**（`:999-1204`）。

### 9.7 交互与命中测试契约

坐标转换集中在一组三个函数——`cellRange(for:)`、`rect(for:)`、`setSelectionRect(_:…)`
（`:1941-1962`）——再加上 `pointToCell(_:)`（`:1964`，结果被夹到数据区域内），因此只有唯一一条规则
需要记住：

```
col = floor((x − nameColWidth) / cellWidth)
row = floor((y − topBarHeight  − consensusHeight) / cellHeight)
```

`SelectionRange{rowStart,rowEnd,colStart,colEnd}` 是闭区间并且符合 `Equatable`（`:25-30`）。
`currentSelectionRange()`/`reportSelection()`（`:1874-1912`）中的选区优先级：整列块 → 框选单元格
范围 → 单个光标单元格 → 整条比对（⌘A）；`hasActiveSelection` **有意排除单独的光标单元格**
（`:1918`），这样在刚刚点击之后"仅导出选区"和复制才会有合理的表现。`mouseDown`（`:1302-1381`）的
优先级：保守度轨道拖擦（`y < 12 && x ≥ nameColWidth`）→ 名称列宽度调整（`namesBoundaryX` 周围
−2…+5 px 的抓取区）→ 在名称带内双击 = 打开重命名弹窗 → 在名称带内拖动以重新排序 → Option =
整列块选择 → 常规光标定位。`mouseDragged`（`:1383-1456`）负责宽度调整、轨道拖擦
（`scrollColumnToVisibleCentered`）、行带的拖动指示器，以及带"矩形并集"失效处理的框选，并把
`reportSelection()` **推迟到 `mouseUp`**——注释记录，每个拖动事件都发布一次 `@Published` 选区
曾引发约 120 Hz 的 SwiftUI 失效风暴。只有四个方向键（123/124/125/126）和 Escape（53 →
`clearSelection()`）会被消费（`:1485-1497`）；Option+方向键从 `selectionAnchor` 起扩展选区；
`moveCursor` 会把光标重新滚动回可视区域。缩放：`magnify(with:)` 阈值 ±0.06（`:1641-1678`），以及
⌘+滚动把 `deltaY` 累积超过 ±0.5（注释记录 `event.magnification` 在 `scrollWheel` 内始终为 0，
所以原先那里的一个分支是死代码）；`zoomIn`/`zoomOut` 优先使用 `onFontSizeChanged` 回调，从而让
`Workspace` 继续作为字号的唯一权威来源，`ZoomManager` 把字号夹在 8…28 pt
（`SeqAlignMacApp.swift:1112-1126`）。

### 9.8 画布上的颜色图层

保守度轨道：`.minimal` 配色使用 `Minimal.chartColor(identity:)`——一种 5 级灰度；在科学配色下，
取共识残基所属调色板颜色的 α = `0.35 + 0.65 × identity`，共识为空位 → `Minimal.gapTint`，而
`identity ≥ 1.0` 会再加一条 2 px 的亮色顶条（`:678-737`）。残基颜色来自
`ColorComputer.computeViewport(...)`，配合缓存的一致度向量。空位单元格得到一层中性底色加上带下划线的
`−`（在高对比度模式下还带斜线）。差异模式会把与缓存参考行快照相同的残基压暗，并且**不填充背景**；
`cachedDiffRefRow` 以 `(row, revision)` 为键（`:1046-1058`）。聚焦变暗与有效选区同时存在时，会在
非选中单元格上覆盖 `Minimal.dimOverlay`；偶数行有斑马条纹。搜索命中使用整个应用中唯一的蓝色
`Minimal.searchHighlight`；当前命中以 2.5 px 的 `Minimal.primary` 描边，其余命中以 1.5 px 的
`Minimal.borderStrong` 描边，全部按视口裁剪。

### 9.9 性能纪律

* **先取快照**（"规则 B3"）：任何后台任务都通过在主线程上取得的 `align.snapshot()` 读取模型；
  变更只在 `performLocked` 之下发生，并执行 `revision += 1`。导出、统计、系统发育树、序列 Logo、
  滑动窗口图、搜索、外部比对器、保存都遵循这一条。
* **队列：** 加载使用 `.userInitiated` 全局队列（`SeqAlignMacApp.swift:696`）、搜索
  （`:295-310`，快照*在*后台任务内部取得，因此主线程不做任何拷贝）、翻译
  （`TranslationOptionsView.swift:140-148`）、导出/保存（`:920-953`）、序列 Logo 以及 NJ 以及
  滑动窗口图（`AnalysisSheets.swift:75-86, 213-232, 311-323`）；画布有自己的专用串行统计队列；
  质量面板使用 `.utility`（`SheetViews.swift:158-192`）；每一次 UI 写入都在 `DispatchQueue.main`。
* **上限与抽样：** 如 §8.17 的表格所列。
* **协作式取消：** `LoadProgressModel.cancelLoading`（`:59-69`，在 `:712-719, 736-742` 处检查）
  以及 `findAll(shouldStop:)`（`SearchEngine.swift:156-166`）。
* **锁纪律：** 每个 `Alignment` 一把 `NSRecursiveLock`；行主序扫描**只获取一次**该锁
  （`ColumnStats.swift:110-126`）；`lockedSequences` 在闭包内部完成拷贝，以遵守"引用不得逃逸"的
  约定（`AlignmentCore.swift:204-211`、`TranslationTables.swift:306-314`、
  `PhyloBuilder.swift:511-522`）。
* **惰性求值：** 长度按 `revision` 缓存；在 64 列预算之内使用增量统计；正则搜索每行只解码一次
  （`SearchEngine.swift:47-49`）；KMP 状态在多次 `next()` 之间保持。

本文档在任何地方都没有宣称吞吐量数据。仓库中没有基准测试、没有性能回归预算、也没有大文件测试装置
（fixture 采用内联写法正是为了避免引入外部样本），因此关于序列容量或运行时间的说法在本代码库中无法
验证（§15.12）。

---

## 10. 本地化架构

### 10.1 机制

`Sources/Localization.swift`（2,002 行）中**没有 `.strings`，没有 `.xcstrings`，也没有
`LocalizedStringKey`**——整个 UI 词表都存放在一张 Swift 表里，并在运行时切换。

| 组件 | 细节 | 行号 |
|---|---|---|
| `AppLanguage` | `enum AppLanguage: String, CaseIterable { case zh, en }`，带 `displayName`（"中文"/"English"）与 `systemImage`（`character.bubble`/`globe`） | `:12-29` |
| `LanguageManager` | 单例 `ObservableObject`；`static let key = "SeqAlignMac.language"`；`@Published var language` 的 `didSet` 会写入 `UserDefaults` **并**发出 `.languageChanged`；首次启动时默认值取自 `Locale.preferredLanguages.first?.hasPrefix("zh")`；`toggle()` 与 `set(_:)` | `:33-62` |
| `L.s` | `enum L { static var s: AppStrings { LanguageManager.shared.language == .zh ? .zh : .en } }`；每个视图和菜单都在 body 求值时读取 `L.s.xxx` | `:66-70` |
| `AppStrings` | 一个 **`final class`，含 433 个存储字段**（`:75-1925`），两个 `static let` 实例 `zh`（`:1455-1676`）与 `en`（`:1678-1900`），一个显式手写的成员化 `init`（`:78-512`），并按 `// MARK:` 小节分组（`:948-1454`） | `:72-74` |
| 格式名称 | `formatName(_ f: AlignmentFormat, zh: Bool)` 外加 8 个静态字符串；除 `Unknown`/`未知` 之外格式名称与语言无关 | `:1902-1924` |
| 计算得到的字符串 | 扩展中的约 18 个属性（`:1931-2002`）按 `private var isZh` 分支，而不是作为存储字段，以避免让 433 个参数的初始化器继续膨胀：`translationNeedsNucleotide`、`translationFrameshift`、`translationMixedTrack`、`translationRagged`、`translationLengthNotMultipleOfThree`、`logoTruncated`、`gffFeatureNotInAlignment`、`treeModelUncorrected`、`treeClampedBranches`、`unalignedWarning`、`statsUnalignedBanner`、`alignerResultMismatch`、`alignerMismatchCount/Missing/Extra/Ragged`、`treeSampledNote`、`settingsAlignerTimeout`、`exportConsensusLabel` | `:1931-2002` |
| 通知 | `Notification.Name.languageChanged` | `:1928` |

`AppStrings` 之所以是类而不是结构体，原因是在 `:72-74` 记录的一次实测：结构体版本每次访问 `L.s`
都要拷贝约 400 个字段——单次 body 求值大约有 16,000 次 retain/release。值语义被舍弃，并且由于类不会
自动合成成员化初始化器，所以手写了显式的 `init`。

### 10.2 界面在语言切换时如何刷新

菜单：`SeqAlignCommands` 观察 `LanguageManager`，并在 `body` 内读取 `lang.language`
（`SeqAlignMacApp.swift:426, 431`）。窗口标题：`.onReceive(.languageChanged)`
（`TabbedWindow.swift:171`）。视图：每个根视图都持有
`@ObservedObject var langManager = LanguageManager.shared`（`ContentView.swift:19`、
`StatsPanel.swift:106`、`SharedUIComponents.swift:625`）。命令面板以语言为键重建自己的缓存
（`CommandPaletteView.swift:34, 73`）。入口点：视图（View）▸ 语言（Language）▸ 中文/English
（`SeqAlignMacApp.swift:534-537`）、侧边栏的 `LanguageSwitchButton`
（`LeftSidebarView.swift:192-200`），以及 `LanguageManager.toggle()`。

需要注意，语言**不是**偏好设置项；它的入口只有 视图（View）▸ 语言（Language）与侧栏按钮
（§10.2）。`Info.plist` 中没有 `CFBundleLocalizations`：这套双语 UI 是运行时切换的，
不基于 `.lproj`。

### 10.3 术语纪律

下面这份英文↔中文术语表对整套文档具有规范性——它是整套文档的术语权威表。承重的对应关系：
colour scheme/配色方案 · conservation (threshold)/保守度（阈值） · column identity/列一致度 ·
**pooled identity (site-weighted)/池化一致度（位点加权）** · consensus sequence/共识序列 ·
consensus mode/共识模式（majority rule / IUPAC degenerate / strict = 多数规则 / IUPAC 简并 /
严格共识）· gap column / 空位列（统计面板自身的标签 含空位列数 有误导性，§8.3）· all-gap columns/全空位列 ·
high-gap columns (>50 %)/空位富集列 · gap trimming/空位精简 · undetermined/未判定 与
degenerate/简并（保持区分）· variable / parsimony-informative / singleton site/变异位点 ·
简约信息位点 · 单态位点 · reading frame/阅读框 · codon track/密码子轨道 · reverse complement/
反向互补 · difference mode/差异模式 · focus dim/聚焦变暗 · melting temperature/熔解温度
（Tm 保持原样）· neighbour-joining tree/邻接法系统发育树 · 短复合形式 neighbour-joining/NJ 树
仅在引用界面标签时可用，正文一律使用术语表的长形 · nearest-neighbour (Tm, salt correction)/最近邻法——
切勿写作 近邻法（裸形），它与 邻接法 在视觉上极易混淆 · sliding window/滑动窗口 · sequence logo/
序列 Logo · annotation browser/注释浏览器 · command palette/命令面板 · frozen name column/名称列冻结 ·
density-adaptive glyphs/密度自适应 · pill（范围切换控件）/胶囊 · external aligner/外部比对器 · consensus row/共识行（显示中的那
一行；共识序列 指的是*序列*本身，是另一个对象）· sandbox/沙箱 · allow-list/允许清单 与
whitelist/白名单——英文有意区分这两个词（allow-list 管的是 `Package.swift` 的 `sources` 与打开面板的
扩展名，whitelist 指解析器的残基字符集），因此中文必须随它所面对的英文用词对应。

有两处空白需要"造词"而不是翻译：**"charset"**（NEXUS 的 `SETS`）没有既成的中文术语——界面直接显示
英文原词 "Charset"——而 **window chart** 只用光秃秃的 窗口 标注，与 "window" 冲突；应优先使用
滑动窗口图 / *sliding-window chart*。

### 10.4 未本地化的界面（如实清单）

下列内容**不是**由 `L.s` 驱动的，因此无论界面语言如何设置都只会显示一种语言。这就是当前实际存在的
i18n 欠债；CI 会 grep 检查它，但不据此阻断（§12.7）。

1. **解析器与领域层错误文本。** 所有 `CoreError.format` 消息都是中文字面量
   （`AlignmentParsers.swift` 全文），而 `CoreError` 的 `errorDescription` 前缀也是硬编码的中文
   （`AlignmentCore.swift:387-410`）。
2. **整个 CLI**——中文的 `已写入`、`已导出`、`无法读取文件`、`错误: …` 与英文的 `Error: …`、
   `Warning: …`、`Converted to … → …` 混杂在一起（`CLIRunner.swift:30, 51, 110, 171, 234`）。
3. **画布本地字符串，仅中文：**`请先在画布中选择区域`（`:323`）、
   `已复制光标所在行（N 列）` / `已复制 R 行 × C 列`（`:350, 352`）、光标播报
   `行 R 列 C，残基 X，一致度 N%` / `空位`（`:380-388`）、`共识序列`（`:784`）、列悬停提示
   `列 N · 共识 X · 一致度 Y%`（`:744`），以及无障碍标签/帮助/自定义操作（`:300-303`）。
4. **颜色图例说明**位于 `ColorSchemeLegend.entries`——除 ClustalX 索引 7 那一项外基本上全是中文，
   因此在英文 UI 下图例弹出框仍会显示中文（`ColorSchemes.swift:212-269`）。
5. **快速指南步骤**——内联的 8 条中文 + 8 条英文（`SheetViews.swift:84-111`），另有三处内联分支
   （`ContentView+Actions.swift:247, 258, 368`，用于复制和添加序列的提示条）。
6. **`ExportManager` 的图像导出前置校验错误**，仅中文（`:324-460`）。
7. **17 个遗传密码选择项**是英文原词加上括号中的 NCBI 编号（`TranslationOptionsView.swift`）。
8. **文件名后缀** `(aligned)`、`(translation)`、`_AA`；状态栏中的 **"Charset"** 标签
   （`CenterPanelView.swift:384`）；导出预览的格式分段标签。
9. **20 个从不通过 `L.s` 读取的死 `AppStrings` 键**（`ok`、`search`、`searchFind`、
   `searchRegexOn`、`searchRegexOff`、`toolbarAlign`、`toolbarExport`、`toolbarNewTab`、
   `menuExport`、`menuHelp`、`menuZoom`、`ctxSelectCodonPos`、`ctxCodonPos1`、`ctxCodonPos2`、
   `ctxCodonPos3`、`settingsCodonTriplet`、`statsSamplingHint`、`translateSixFrameOverview`、
   `translateHighlightStop`、`translateHighlightStart`）。`ctx*` 这一组显示的是一次计划过但从未
   发布的 "Select Codon Position" 子菜单；`translate*` 三项加上 `settingsCodonTriplet` 是一次未发布
   的六框概览留下的残留。**这些键一律不得作为功能写入文档。**

---

## 11. 持久化

SeqAlignMac 持久化的一切都经由本机的 `UserDefaults`；没有钥匙串条目，没有 application-support
文件，没有数据库，也没有网络同步（§12.7）。隐私清单只声明了一个 reason API，即 `CA92.1`
（`Resources/PrivacyInfo.xcprivacy:13-23`）。

### 11.1 持久化的键，含默认值与作用

| 键 | 写入者 | 类型 / 默认值 | 作用 | 参考 |
|---|---|---|---|---|
| `SeqAlignMac.language` | `LanguageManager.didSet` | `String`，`"zh"`/`"en"`；初始值取自 `Locale.preferredLanguages` | 所有 UI 文本 | `Localization.swift:33-62` |
| `SeqAlignMac.appearance` | `AppearanceStore` | light / dark / system | 全应用的 `NSAppearance`，以及渲染时使用哪套调色板变体 | `SeqAlignMacApp.swift:1337-1377` |
| `SeqAlignMac.currentScheme` | `ColorSchemeManager` / `Workspace` | `ColorScheme` 的 `Int32` 原值；**缺失 ⇒ `.minimal`**（原值 4） | 画布与导出的调色板 | `:123-132`；之所以有这一特例，是因为原值 0 是 `defaultNucleotide` |
| `SeqAlignMac.fontSize` | `Workspace` | `CGFloat`，默认 **13**，夹在 8…28 | 字形大小；缩放百分比即 `fontSize / 13` | `:105, 1117-1125` |
| `SeqAlignMac.nameColWidth` | 画布 `mouseUp` | `CGFloat`，默认 **150**，夹在 80…2000 | 冻结的序列名称列宽度；也是 CLI `export` 的默认值 | `AlignmentCanvasView.swift:118-190`；`CLIRunner.swift:163-164` |
| `SeqAlignMac.highContrast` | 设置 / workspace | `Bool`，默认 `false` | 空位斜线与对比度强调 | `SettingsView.swift:96-101` |
| `SeqAlignMac.focusDimMode` | 设置 / workspace | `Bool`，默认 `false` | 压暗非选中单元格 | `SettingsView.swift:96-101` |
| `SeqAlignMac.consensusMode` | 设置 | `ConsensusMode` 原值，默认 `.majority` | 共识行中的字形、序列 Logo、统计、导出 | `ColumnStats.swift:54-58`；`SettingsView.swift:24-25, 134-138` |
| `SeqAlignMac.externalAlignerTimeout` | 设置 | `Int` 秒，默认 **300**（存储值 ≤ 0 时会重新取默认）；UI 步进器 30…3600，步长 30 | 子进程终止期限，下限取 `max(10, n)`；5 s 之后再发 SIGKILL | `SettingsView.swift:16-22, 150-162`；`ExternalAlignerView.swift:239-258` |
| `SeqAlignMac.statsPanelWidth` | `ContentView.onChange` | `CGFloat`，默认 **264**，夹在 220…460 | 右侧面板宽度 | `PanelResizer.swift:23-24, 36-37` |
| `SeqAlignMac.leftSidebarWidth` | `ContentView.onChange` | `CGFloat`，默认 **180**，夹在 150…320 | 侧边栏宽度 | `ContentView.swift:55-101` |
| `SeqAlignMac.recentFiles` | `RecentFilesManager` | `[String]`，**最多 10 项**，解析符号链接；不存在的文件置灰显示 | 文件（File）▸ 打开最近（Open Recent） | `SeqAlignMacApp.swift:781` |
| `SeqAlignMac.firstRunHintShown` | `showFirstRunHintIfNeeded()` | `Bool` | 一次性首次运行提示条 | `:1449-1458` |
| `SeqAlignMac.primerNa_mM` | `@AppStorage` | `Double`，默认 **50**（mM） | `TmOptions` 中的 `[Na+]`（除以 `/1000`） | `PrimerCalculatorView.swift:48-55` |
| `SeqAlignMac.primerMg_mM` | `@AppStorage` | `Double`，默认 **0**（mM） | `TmOptions` 中的 `[Mg2+]` | 同上 |
| `SeqAlignMac.primerOligo_uM` | `@AppStorage` | `Double`，默认 **0.25**（µM） | 寡链浓度（除以 `/1e6`） | 同上 |

`@AppStorage` 恰好只在三个地方使用，全都在引物弹窗里；整个 target 中**没有任何地方使用
`@SceneStorage`**。

### 11.2 刻意不持久化的状态

| 状态 | 行为 | 对读者为何重要 |
|---|---|---|
| 共识行可见性（`showConsensus`） | 每次启动重置 | 导出的图像无论如何总会显示共识行，与该设置无关（§15.5） |
| 差异模式与参考行 | 每次启动重置 | 无法保存一个可复现的"差异视图" |
| **ClustalX 保守度阈值** | 滑块写入 `ColorComputer.clustalXThreshold`，但重新启动后**不会**恢复——这是唯一不生效的设置 | `SettingsView.swift:114-129` 对比 `ColorLogic.swift:52-64`；§15.4 |
| 窗口与标签页内容 | 仅存在于内存中（`WindowRegistry`）；退出时全部关闭，只有 "Open Recent" 能找回的部分除外 | 没有会话恢复 |
| 搜索查询与命中 | 按 workspace 保存，属于转瞬状态 | — |
| 撤销/重做历史 | 按标签页保存，关闭即丢弃 | 50 条命令 / 256 MiB 预算只在一轮会话内适用 |

---

## 12. 构建系统与质量门禁

### 12.1 两条编译路径，两者都由 CI 执行

| 路径 | 命令 | 构建内容 | 用途 |
|---|---|---|---|
| SwiftPM | `swift build`、`swift build -c release`、`swift test` | 仅 `SeqAlignCore` **库**（10 个文件）+ `SeqAlignCoreTests` | 质量护栏：一条纯逻辑的编译与测试通道 |
| `build.sh` | `bash build.sh [--open] [--skip-tests]` | 把 `Sources/` 下全部 36 个文件编译为 `SeqAlignMac.app` 与 `SeqAlignMac.app.zip` | 得到实际交付产品的唯一途径 |

`Package.swift:1` 声明 `swift-tools-version:6.0`，`:19` 是 `.macOS(.v14)`，`:20-22` 只有一个产物
`.library(name: "SeqAlignCore")`，target 与测试的语言模式都被钉在 **Swift 5**（`:42, 48`）——
因此 Swift 6 的数据竞争检查被有意*不*应用于核心。仓库所隐含的工具链下限是 **Swift 6 工具链**
（`Package.swift:1` 的 tools-version 6.0，CI 在 `macos-15` 上挑选最新版 Xcode，`ci.yml:23-27`）；
写"Xcode 15+"的文档与清单和 CI 注释都相矛盾，不应继续复述。

### 12.2 `sources:` 允许清单，以及为何用允许清单而不是排除清单

`Package.swift:30-41` 把**恰好十个**文件编译进 `SeqAlignCore`：`AlignmentCore`、
`ResidueAlphabet`、`AlignmentParsers`、`AlignmentWriters`、`TranslationTables`、
`PrimerCalculator`、`ColumnStats`、`SearchEngine`、`UndoRedoManager`、`ColorLogic`。记录在
`Package.swift:8-13` 与 `:27-29` 中文注释里的取舍，可以译为三点：

1. **必要性。** `ContentView`、`AlignmentCanvasView`、`SeqAlignMacApp`、`ColorSchemes`、
   `ExportManager` 以及其余外壳代码依赖 AppKit/SwiftUI，无法在纯逻辑测试 target 内编译。领域层——
   解析器、写出器、翻译、引物、列统计、搜索、撤销/重做、核心模型、残基字母表——被有意保持与 UI
   无关；这份清单*就是*"领域服务与渲染解耦"的具体实现。
2. **共存。** app 二进制仍由 `build.sh` 用普通的 `swiftc` 单独构建；SwiftPM 清单并不与之竞争，
   也没有增加任何可执行产物。
3. **为何是 `sources` 而不是 `exclude`。** 用 `exclude` 时，忘记列出新加入的纯逻辑文件，会使它
   被编译但**没有测试**，从而产生虚假的绿色。只用 `sources` 时，未被列出的文件根本不会被该 package
   编译，所以一旦有人试图从测试中使用它，遗漏就会立刻显现。

需要记住的后果：**其余全部 26 个 `Sources/` 文件，包括 `CLIRunner.swift` 在内，对 SwiftPM 都
不可见**，只由 `build.sh:66-67` 编译。

### 12.3 `build.sh` 阶段表

`#!/bin/bash`，同时带 `set -e` **和** `set -o pipefail`——`:3-5` 解释 `pipefail` 的存在是为了让
`swift test | tail` 无法掩盖失败。脚本会 `cd` 到自身所在目录（`:12-18`），因此相对路径是安全的。
未知参数会被 `case` 循环静默忽略（`:19-24`）；没有 `--help`。

| # | 行号 | 阶段 | 说明 / 失败类别 |
|---|---|---|---|
| 1 | `:28-31` | 把旧 bundle 移开 | 用 `mv SeqAlignMac.app /tmp/SeqAlignMac_old_$$` 而不是删除；带 `\|\| true`，绝不致命 |
| 2 | `:33-36` | 创建 `Contents/MacOS`、`Contents/Resources` | 无法创建则硬失败 |
| 3 | `:38-40` | 复制 `Info.plist` | 无保护的 `cp` → 缺少 `Info.plist` 会中止 |
| 3.5 | `:42-61` | **测试门禁** | **仅当** `swift` 存在（`:49`）且 `echo "import XCTest" \| swiftc -typecheck -` 成功（`:50`）时才运行 `swift test 2>&1 \| tail -20`；失败 → `❌ 单元测试失败` + `exit 1`；XCTest 缺失（只有 Command Line Tools）→ 警告 `⚠️ 本机缺少 XCTest…` 并继续构建。`--skip-tests` 会打印跳过提示。**本地这道门禁是尽力而为；CI 使其成为强制。** |
| 4 | `:63-80` | 编译 | 一次 `swiftc` 调用，输入来自 `find Sources -name "*.swift" \| sort`，带 `-target arm64-apple-macosx14.0`、`-sdk $(xcrun --sdk macosx --show-sdk-path)`、`-parse-as-library`（`@main` 所要求）、`-O`、`-framework Cocoa`、`-framework SwiftUI`、`-o Contents/MacOS/SeqAlignMac`。**没有排除清单。**任何编译错误都是硬失败 |
| 5 | `:82-99` | 图标 | 把任何陈旧的 `icon.iconset` 移到 `/tmp`，运行 `swift gen_icon.swift`，然后若 `icon_512x512.png` 存在就执行 `iconutil -c icns icon.iconset -o Contents/Resources/AppIcon.icns`；否则**只告警**，构建在没有图标的情况下继续。（`gen_icon.swift:77-88` 会输出 10 个 PNG；`:85-86` 处声称 56 的注释已经过期。） |
| 6 | `:101-103` | 把 `logo.svg` 复制进 Resources | 无保护的 `cp` → 文件缺失会中止 |
| 6.5 | `:105-109` | 把 `PrivacyInfo.xcprivacy` 复制进 bundle | App Store 提交所要求 |
| 7 | `:111-112` | 对可执行文件 `chmod +x` | |
| 7.5 | `:114-140` | 代码签名 | 见 §12.5 |
| 8 | `:142-149` | 分发 zip | 旧 zip 移到 `/tmp`，然后 `ditto -c -k --keepParent SeqAlignMac.app SeqAlignMac.app.zip` |
| 8.5 | `:151-158` | 公证 | **仅当 `DEVELOPER_ID` 与 `NOTARY_PROFILE` 都被设置时**：`xcrun notarytool submit <zip> --keychain-profile <profile> --wait`，然后 `xcrun stapler staple SeqAlignMac.app`；每处失败都是 `\|\| echo`——**非致命** |
| 9 | `:160-166` | 摘要 | bundle 路径，bundle 与 zip 的 `du -sh` |
| 10 | `:168-172` | 可选启动 | 传入 `--open` 时执行 `open SeqAlignMac.app` |

输出：`SeqAlignMac.app/`、`SeqAlignMac.app.zip`、临时的 `icon.iconset/`，以及
`/tmp/SeqAlignMac_{old,iconset,zip}_$$`。硬失败：`swift test`（XCTest 存在时）、`swiftc`、
`swift gen_icon.swift`、`iconutil`、缺少 `Info.plist`/`logo.svg`/`Sources`、`codesign --verify`、
`ditto`。警告并继续：图标生成、临时签名（ad-hoc）、notarytool 与 stapler、XCTest 缺失、旧
bundle/zip 不存在。

### 12.4 CLI 无法用 SwiftPM 构建

`Package.swift:20-22` **没有声明任何可执行产物**，而 `CLIRunner.swift` 不在 `sources` 允许清单
之内。因此 `swift build` 只产出一个库；`swift run` 无从运行任何东西。CLI 仅仅作为 `build.sh`
构建的 `SeqAlignMac` Mach-O 可执行文件的一种模式存在（§13）。任何诸如"用 SwiftPM 构建 CLI"的说法
都是错的。

### 12.5 签名、沙箱、公证：都是可选项，不是默认值

| 开关 | 设置后的效果 | 行号 |
|---|---|---|
| `DEVELOPER_ID` | `codesign --force --options runtime --timestamp ${ENT_ARG} --sign "$DEVELOPER_ID" <bundle>`（加固运行时 + 安全时间戳），随后执行 `codesign --verify --verbose`，其失败**是**致命的 | `:128-134` |
| `SEQALIGN_SANDBOX` | 在 codesign 参数后追加 `--entitlements SeqAlignMac.entitlements`，并打印一条提示说明沙箱会使外部比对器不可用；若 `DEVELOPER_ID` 为空则告警，因为对 MAS 提交而言这一组合毫无意义 | `:117-126` |
| `NOTARY_PROFILE` | 启用 `notarytool submit` + `stapler staple` 路径，但只在与 `DEVELOPER_ID` 同时设置时才生效 | `:151-158` |
| *（都不设置）* | 临时签名（ad-hoc）回退：`codesign --force --deep --sign - <bundle>`；失败被容忍并给出警告——注释解释未签名的 arm64 二进制会被 Gatekeeper 终止，并失去网络隔离许可 | `:135-140` |

`SeqAlignMac.entitlements` 只授予 `app-sandbox`、`files.user-selected.read-write` 和
`security-scoped-bookmarks.app-sandbox`，并以注释（`:15`）记录没有请求任何网络、麦克风或摄像头
权限。由于沙箱禁止对用户提供的二进制执行 `exec`，外部比对器功能是**由该 entitlement 关闭的，而不是
由运行时切换关闭的**：`Sources/` 中没有任何代码会条件性地隐藏这一 UI（§15.8）。构建只针对 arm64
（`-target arm64-apple-macosx14.0`，没有 `x86_64` 切片，也没有成对的 `-arch`），因此随包分发的 zip
**不是**通用二进制，Intel Mac 需要重新编译——这一限制是其他任何文档都未指出的。

### 12.6 测试

`swift test` 运行分布在 3 个文件中的 **4 个 `XCTestCase` 类、共 110 个测试方法**：

| 文件 | 类 | 方法数 | 定义于 |
|---|---|---|---|
| `SeqAlignCoreTests.swift` | `SeqAlignCoreTests` | 30 | `:19` |
| `SeqAlignCoreTests.swift` | `CoreEnhancementTests` | 11 | `:522` |
| `FormatRoundTripTests.swift` | `FormatRoundTripTests` | 41 | `:12` |
| `EdgeCaseTests.swift` | `EdgeCaseTests` | 28 | `:18` |
| **合计** | 4 个类 | **110** | |

按领域分组（各组在不同文件之间存在重叠；**以上按类列出的表才是唯一权威计数**）：

* **解析器往返** — 7 个共用 `assertRoundtrip` 辅助函数的具名往返（3 条序列 × 60 列，
  `SeqAlignCoreTests.swift:147-197`）、Stockholm 的 `#=GF ID` 得以保留（`:525-538`）、PHYLIP
  strict-10/sequential 且 accession 名称恰好 10 个字符（`FormatRoundTripTests.swift:32-54`）、
  FASTA/PHYLIP/CLUSTAL/Stockholm 中的点号空位归一化（`:64-79`）、重复的 CLUSTAL 名称各自独立保留
  （`:354-366`）、含多个块的 CLUSTAL 单行被保留（`:370-381`）、sequential NEXUS 的折行仍留在其
  taxon 上（`:280-299`）、NEXUS interleaved 的聚合（`EdgeCaseTests.swift:63-82`）、PHYLIP 折行的
  sequential 与 strict-10（`:22-59`）、无标题的 CLUSTAL（`:275-283`），以及覆盖 4 个 PHYLIP 变体
  + NEXUS + CLUSTAL + Stockholm + MSF 的字节级精确往返（`FormatRoundTripTests.swift:565-595`）。
* **数据类型检测**，包括 NEXUS `DATATYPE=` 声明的各种写法以及对 `.`/`*`/数字的容忍
  （`SeqAlignCoreTests.swift:201-214`；`FormatRoundTripTests.swift:303-321`）。
* **引物热力学** — 一张源自 OligoCalc 的参考表，含 10 个 fixture，NN/Wallace Tm 在 1 °C 以内、
  GC 在 0.02 以内，hetero-dimer ΔG 在 3.0 以内且符号一致（`SeqAlignCoreTests.swift:245-281`），
  简并度 > 4096 时抛错（`:277-281`），盐浓度依赖（`:689-696`），与 Biopython `Tm_NN` 在考虑
  Mg/dNTP 螯合后相符（`FormatRoundTripTests.swift:517-537`），简并度饱和与负盐拒绝
  （`EdgeCaseTests.swift:130-151`）。
* **翻译** — 0 框、单个密码子、负框 ≡ 先反向互补再翻译（`SeqAlignCoreTests.swift:285-311`），
  对照 `gc.prt` 的 17 张表抽查（`:634-686`），名称保留（`EdgeCaseTests.swift:344-348`），混合轨道
  不被标注为蛋白，蛋白输入被拒绝，移码 → `X`（`FormatRoundTripTests.swift:177-208`）。
* **撤销/重做** — 七个场景（`SeqAlignCoreTests.swift:323-411`）、被夹取位置之后的撤销、栈内存上限、
  空事务保留 redo 栈，插入空位列时 `dirtyColumns == nil`（`EdgeCaseTests.swift:224-261, 352-355`），
  以及删除列时的 charset 重映射与撤销恢复分区（`FormatRoundTripTests.swift:385-402`）。
* **搜索** — IUPAC 精确/简并（`SeqAlignCoreTests.swift:415-428`）、正则字面量大写化不会把 `\d`
  变成 `\D`、对数字使用正则、`validateRegex` ≡ 引擎、KMP 重叠命中（`EdgeCaseTests.swift:86-126`）、
  字面 `N` 匹配与 T↔U 互换（`FormatRoundTripTests.swift:425-443`）。
* **统计** — 质量/列统计的单一来源（`SeqAlignCoreTests.swift:432-449`）、FASTQ 的 Q20/Q30/最小
  Phred 以及 Phred+33 与 +64 的判定（`:541-551`；`FormatRoundTripTests.swift:541-549`）、蛋白与
  核苷酸的位点计数规则（`:108-140`）、歧义字符排除（`EdgeCaseTests.swift:200-220`）、
  **池化一致度 ≠ 精确的成对均值**（`FormatRoundTripTests.swift:248-261`）、全 `N`/全 `X` 列不算
  保守（`:265-276`）、共识模式（`EdgeCaseTests.swift:322-340`）、GC 的单一来源（`:455-461`）、
  变异类型中的空位对空位（`:206-210`）。
* **系统发育与序列 Logo** — NJ 的 2 taxon 与 3 taxon Newick（`SeqAlignCoreTests.swift:594-612`）、
  抽样披露、2 taxon 分支长度、末端名称去重（`FormatRoundTripTests.swift:478-513`）、滑动窗口一致度
  （`:615-622`）、p-distance 的空位处理（`:88-104`）、Logo 的比特数（`:582-591`）、氨基酸覆盖
  （`:142-152`）、截断报告（`:465-474`）。
* **颜色逻辑** — default-nucleotide、ClustalX、Okabe-Ito 索引以及视口的单一来源
  （`SeqAlignCoreTests.swift:466-488, 625-631`）、蛋白配色在核苷酸轨道上回退
  （`FormatRoundTripTests.swift:325-337`）、CLUSTAL 共识不为 A/T 伪造保守性（`:339-350`）。
* **NEXUS charset** — 三个 `codons_*` charset，步长 `\3`、20 个区间（`SeqAlignCoreTests.swift:453-462`），
  列未被改动时步进规格原样保留（`FormatRoundTripTests.swift:404-421`）。
* **I/O、压缩、写出器** — gzip 解压（`SeqAlignCoreTests.swift:554-560`）、GFF3（`:699-709`）、
  FASTQ 质量往返与非法残基拒绝（`EdgeCaseTests.swift:265-302`）、gzip 压缩→解压的字节相等
  （`:306-312`）、补齐之后质量与残基的对应关系、载荷中包含 `1F 8B 08` 魔数的单成员 gzip 仍能解码
  而真正的拼接仍然被拒（`FormatRoundTripTests.swift:599-613`）、ragged 写出器的安全性、MSF GCG
  校验和、NEXUS 引号、截断后 PHYLIP strict-10 的唯一性（`EdgeCaseTests.swift:155-196`）、声明的
  NCHAR 与实际写出的行长度（`:212-231`）、快照独立性——并发安全的基础
  （`SeqAlignCoreTests.swift:507-516`）、反向互补的 IUPAC 完备性，以及未比对 FASTA 的来源信息
  （`:235-244`）。

**测试套件未覆盖的内容** — 不要声称超过以下这些：

* **`CLIRunner.swift` 的测试数量为零。** 没有任何测试触及参数解析、四个退出码、stdout 与 stderr
  的行为、CSV 字段集、`-o`/`--out`/`--output` 的语义、`--scheme`/`--fontsize` 的处理，或
  `--start/--end` 切片（`subAlignment` 的 `crop` 路径从未被执行；只有 `shift` 被执行过，且是通过
  `RemoveColumnsCommand`）。CI 从不以 `cli` 模式运行该二进制。
* **没有 AppKit/SwiftUI 覆盖：**画布渲染、`ExportManager` 的 PNG/PDF/SVG 字节、`ColorSchemes` 的
  调色板数值、`AlignmentRenderer`、外部比对器的 `Process` 管道，以及 UI 层面的撤销行为。
  `CONTRIBUTING.md:43` 记录，依赖 AppKit 的代码没有 SwiftPM 测试通道，需要先经过讨论并给出理由。
* **本地化键对称性在此无法测试**——`Localization.swift` 导入 SwiftUI/AppKit，有意被排除在 target
  之外（`EdgeCaseTests.swift:357-359`）；这项被推迟的检查属于一个在 SwiftPM 中并不存在的 app
  target。
* 没有大文件测试装置（fixture 采用内联写法正是为了避免引入外部样本，
  `SeqAlignCoreTests.swift:21`），**没有覆盖测量、没有性能/回归预算、没有解析器模糊测试**
  （只有手写的畸形用例），也没有任何在 Linux 或 Intel 上的测试。
* 某些断言是刻意偏弱的：自身二聚体 ΔG 只是契约检查（`:270-275`），简并引物的简并度只与*上*界比较
  （`:236`），而 `FormatRoundTripTests.swift:56-60`——`testPhylipAllGapResultIsRejectedNotSilent`——
  实际断言的是 `XCTAssertNoThrow`，也就是说它的名字与函数体相互矛盾，因此不得把它引用为"畸形
  PHYLIP 会被拒绝"的证据。

### 12.7 持续集成

`.github/workflows/ci.yml` 是唯一的工作流。触发条件：向 `main` 的 `push` 以及所有 `pull_request`
（`:3-6`）；按 workflow+ref 并发，并设 `cancel-in-progress: true`（`:9-11`，注释：macOS 分钟数
稀缺）。**没有** `workflow_dispatch`，没有 release 或 tag 触发，没有 `secrets:`，没有工作流级的
`env:` 块，也**没有缓存步骤**——每次运行都重新解析依赖并从头重建。

| 作业 | Runner | 步骤 |
|---|---|---|
| `test` — "Tests & build (macOS)"，`timeout-minutes: 45`（`:14-17`） | `macos-15` | `actions/checkout@v5`（`:19`）；"Select latest Xcode (Swift 6 toolchain)"——列出 `/Applications/Xcode*.app`，用 `sudo xcode-select -s` 指向 `sort -V` 中的最高版本，打印 `xcodebuild -version` 与 `swift --version`（`:20-27`；因此 Swift 版本就是 `macos-15` 上最新 Xcode 自带的那个，并未钉定）；`swift test`（`:28-29`，完整未经管道截断的输出——全部 110 个测试成为强制要求的唯一场所）；`swift build -c release`（`:30-33`，另一次 release 配置的编译，用于暴露单靠 `swiftc -O` 不会发现的优化器问题）；`./build.sh --skip-tests`（`:34-35`，完整 bundle，**临时签名（ad-hoc）**，并产出 zip）；`actions/upload-artifact@v4`，name `SeqAlignMac-app`，path `SeqAlignMac.app.zip`，`retention-days: 14`（`:36-41`） |
| `lint` — "Repo lint"，`timeout-minutes: 5`（`:43-46`） | `ubuntu-latest` | `actions/checkout@v5`（`:48`）；"Ensure build artifacts are not committed"——若 `git ls-files` 匹配 `^SeqAlignMac\.app(\.zip)?$` 或 `…/SeqAlignMac.app/` 则失败（`:49-54`）；"i18n hardcode audit (**non-blocking**)"，带 `continue-on-error: true`——用 `grep -rP` 统计 `Sources/**/*.swift` 中排除 `Localization.swift` 与注释行之后的 CJK 字符串字面量数量并打印该计数（`:55-62`） |

这张表编码了三处更正：产物防护确实存在，但 **CJK 审计不门禁任何东西**——该步骤自己的注释承认视图层
与解析层仍有硬编码中文，因此任何声称 CI 强制执行本地化规则的说法都言过其实；CI 只做临时签名
（ad-hoc），因此上传的产物**不是**可分发的构建，CI 也不以公证作为门禁；而 `Package.swift:29` 断言
"…且 CI 可对清单做 diff检查"（即"CI 可以对清单做 diff 检查"），但**并不存在这样的 CI 步骤**
（§15.3）。必需状态检查的配置位于仓库之外——既没有分支保护文件，也没有 `.github/settings.yml`。

### 12.8 按实际实现描述的安全与隐私姿态

攻击面，依据 `SECURITY.md:24-33` 与代码：畸形的比对文件必须报错而不是崩溃（§7.11）；在未启用沙箱的
构建中，外部比对器功能会执行由用户选择的二进制路径（§6.2.19）；撤销栈的上限为 50 个条目与 256 MiB
（`UndoRedoManager.swift:361-365`，测试 `EdgeCaseTests.swift:236`）。`Info.plist:33-35` 设置
`ITSAppUsesNonExemptEncryption = false`；隐私清单声明 `NSPrivacyTracking = false`、空的跟踪域名、
空的数据收集类型，以及唯一的 `UserDefaults` API 理由 `CA92.1`；应用中没有任何东西执行网络 I/O。
`SECURITY.md:15, 20` 中的响应时限与安全公告处理承诺是**政策声明，而非代码事实**，并且仓库中任何地方
都不存在联系地址或密钥指纹（§15.13）。

---

## 13. 命令行接口契约

CLI 是受支持的接口，而不是调试后门：它的退出码与 CSV 列名都是可复现性叙述的一部分。**面向任务的配方收录在 [`USAGE_ZH.md`](USAGE_ZH.md) §14「命令行用法」；本节负责确立契约。**

调用方式——与 GUI 使用同一个 Mach-O 二进制，在任何窗口创建之前完成分派（`SeqAlignMacApp.swift:19-25`、`CLIRunner.swift:21-25`）：

```
<Path>/SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli <subcommand> <file> [options]
```

`run()` 要求至少剩余两个 token（子命令 + 输入路径），否则打印用法并以退出码 64 退出。通用流水线为 读取 → 探测 → **解析** → 分派 → `exit(0)`；解析发生在子命令 switch *之前*，因此对一个损坏的文件给出无效子命令时，报告的是解析错误而非用法错误（`:29-56`）。

### 13.1 子命令

| 子命令 | 语法 | 说明 |
|---|---|---|
| `stats` | `cli stats <alignment-file> [--out results.csv]` | 缺少 `--out` 时把 CSV 输出到标准输出；给出 `--out` 时标准输出只收到 `已写入 <path>`。**`stats` 只读取 `--out`——此处没有 `-o` 别名。** `--start`/`--end` 被忽略 |
| `export` | `cli export <alignment-file> [--format png\|pdf\|svg] [-o output] [--fontsize N] [--dark] [--scheme minimal\|clustalx\|zappo\|seaview\|default\|titv\|okabeito]` | `--format` 可选，默认 `png`；没有 `--start`/`--end`；选区／行／列范围在 CLI 中不可达 |
| `convert` | `cli convert <alignment-file> --format nexus\|phylip\|clustal\|msf\|stockholm\|fasta\|fastq [-o output-file] [--start N] [--end M]` | `--format` **必填**；别名 `nexus\|nex`、`phylip\|phy`、`clustal\|aln`、`msf`、`stockholm\|sto`、`fasta\|fa\|fas`、`fastq\|fq`；此处**不**识别 `--out` |

**既没有 `--help`，也没有 `--version`，更没有 `-v`/`-q`/`--verbose`**；`cli --help` 得到用法块并以退出码 64 退出。用法文本用 `print` 打印，也就是输出到**标准输出**，即便用法错误也是如此（`:58-66`）。`MANUAL_EN.md:333` 在 `convert` 列表中遗漏了 `fastq`，`:330` 在 `export` 中遗漏了 `--scheme`；应以 `:63` 处二进制内置的用法文本为准。

### 13.2 选项语义与静默回退

| 选项 | 契约 | 回退行为 |
|---|---|---|
| `--format`（export）| 大小写不敏感的 `png\|pdf\|svg` | 未知取值 → 标准错误 `Error: unknown --format '<x>' (expected png\|pdf\|svg)` + **退出码 64**（`:150-153`）|
| `--format`（convert）| 大小写不敏感，7 个别名见上；`fastq` 要求至少有一条带质量值的序列 | 缺失或未知 → 退出码 64（`:177-180, 228`）；无质量值的 FASTQ → `CoreError.unsupported` → 退出码 70（`:221-223`）|
| `--scheme`（export）| `clustalx`、`zappo`、`seaview`、`default`、`titv`、`okabeito`、`minimal`；缺省 ⇒ `minimal` | **任何其他取值都会静默变为 `minimal`，且没有任何警告**（`:269-279`）——这是相对 `--format` 严格性的一个已知偏差；另需注意它与 GUI／`ExportOptions` 的默认值 `.defaultNucleotide` 不同 |
| `--fontsize`（export）| 仅当可解析为 `Double` **且** 满足 `6 ≤ N ≤ 40` 时被接受 | 越界 → 标准错误 `Warning: invalid --fontsize, using default 13`，非致命（`:157-161`）|
| `--dark` | 只看是否出现的开关（`params.contains("--dark")`）| — |
| `--start` / `--end` | **1 基闭区间**；默认值为 `1` 与 `alignment.length`；仅当窗口窄于整个比对时才执行切片（`:186`）| 非数字取值会使 `Int()` 失败并被**静默忽略**（`:183-184`）；越界的边界值会被**截断（钳制）**（`:238-240`）；`start > end` → `CoreError.invalidArg` → 退出码 70（`:241-243`）|
| `-o` / `--output` / `--out` | `export`/`convert` 使用 `-o` 与 `--output`；`stats` 使用 `--out` | 拼写不匹配等同于缺失，因此 `convert … --out x.nexus` 会静默地把一个默认命名的文件写入工作目录；`--output` 出现在代码中，却**没有**出现在任何用法字符串里 |
| 选项解析器 | 只支持 `--key value` / `-o value` 与位置参数；以 `-` 开头的取值会被拒绝；重复出现的选项以第一次为准 | 取值看起来像开关的选项被视为缺失 → 使用默认值 |
| 名称列 | 从 `UserDefaults["SeqAlignMac.nameColWidth"]` 读取，否则为 150 | 因此无头运行会继承 GUI 偏好设置——它**并非**完全封闭自洽（`:163-164`）|

`subAlignment` 的切片语义（`:238-267`）：`s = max(1,start) − 1`、`e = min(length,end)`；短于窗口的行用 `'-'` 右填充到统一宽度，与写出器的 `paddedSlice` 一致；NEXUS `CHARSET` 分区通过 `CharsetRemapper.crop(charsets, startCol: s, endCol: e-1)` 重新投影；`provenance` 会复制到切片后的比对上，`metadata`／`datatype` 直接透传。输出命名：`convert` 默认为 `<input-basename>.<canonical ext>` 并打印 `Converted to <fmt> → <path>`；`export` 默认为 `<input-basename>_alignment.<fmt>` 并打印 `已导出 <path>`；压缩**输入**由文件扩展名决定（`:284-294`），CLI 不会压缩输出（`:109, 170, 233`）。

### 13.3 `stats` CSV 字段表（`:82-105`）

字段以 `metric,value` 行的形式给出，仅当取值包含 `,`、`"` 或换行时才按 RFC-4180 加引号（`:75-81`）。

| 字段 | 含义 | 备注 |
|---|---|---|
| `file` | 仅路径的最后一个组件 | |
| `sequences` | 行数 | |
| `columns` | `Alignment.length`，即**最大**行宽 | §5.1 |
| `datatype` | `nucleotide` \| `aminoacid` | |
| `pooled_identity_site_weighted` | `%.4f`，即 §8.2 的按位点加权池化一致度 | 字段名是有意为之，命名理由见 `:87-88` |
| `declared_aligned` | `aligned` \| `unknown` \| `not-aligned` | 来源信息，§5.5 |
| `mean_column_identity` | `%.4f`，`columnIdentities` 的未加权算术平均 | 在 `:116-120` 计算 |
| `min_column_identity`、`max_column_identity` | 在信息列上取的极值 | §8.3 |
| `gap_columns` | **无可归属残基**的列 | §8.3 |
| `total_columns` | `UInt64(nCol)` | |
| `variable_sites`、`parsimony_informative_sites`、`singleton_sites` | §8.4 | **这三项仅出现在此处与统计面板中，绝不出现在质量报告表单中** |
| `gc_content` | `%.4f`，蛋白质为 0 | 对 `SequenceUtils.gcContent` 跨序列做 ACGT 加权聚合（`:122-139`）|
| `fastq_mean_phred`、`fastq_q20_ratio`、`fastq_q30_ratio` | `%.2f`、`%.4f`、`%.4f` | **仅当存在质量数据时**才输出 |

### 13.4 退出码

| 退出码 | 符号 | 触发位置 | 含义 |
|---|---|---|---|
| `0` | 成功 | `:51` | 子命令执行完毕 |
| `64` | `EX_USAGE` | `:24`（少于 2 个 token）、`:49`（未知子命令）、`:152`（`export --format` 非法）、`:179`（缺少 `convert --format`）、`:228`（`convert --format` 非法）| 用法错误；用法块输出到**标准输出** |
| `65` | `EX_DATAERR` | `:195` | 拒绝密码子＋氨基酸混合轨——**实践中不可达**，因为该标记位于进程内翻译元数据中（`TranslationTables.swift:376-378`），而 CLI 从不执行翻译（§15.1）|
| `66` | `EX_NOINPUT` | `:30-32` | 文件不可读或 gzip 解压失败；标准错误 `无法读取文件: <path>` |
| `70` | `EX_SOFTWARE` | `:52-55` | 任何抛出的错误——解析失败、区域非法、无质量值的 FASTQ、输出写入失败；标准错误 `错误: <localizedDescription>` |

尽管 GUI 是双语的，CLI 输出**并未本地化**：文件与解析错误以及 `已写入`/`已导出` 进度行是中文，而格式／配色方案／混合轨错误、`--fontsize` 警告以及 `Converted to … → …` 是英文。

---

## 14. 扩展指南

每个配方都列出了完整改动必须触及的文件。反复出现的规则是：**新的纯逻辑文件必须加入 `Package.swift` 的 `sources` 允许清单，否则包不会编译它，也没有任何一条测试覆盖它**（`CONTRIBUTING.md:30`）。

### 14.1 新增文件格式

| 步骤 | 文件 | 细节 |
|---|---|---|
| 1 | `Sources/AlignmentParsers.swift:9-11` | 在 `AlignmentFormat` 中新增该 case（保持 `.unknown` 位于最后）|
| 2 | `Sources/AlignmentParsers.swift:14-42` | 在 `FormatDetector.detect` 中新增一条探测规则，其顺序必须保证不会从既有格式那里抢占前缀；并测试新的标记能在 65,536 字节的采样窗口内存活 |
| 3 | `Sources/AlignmentParsers.swift` | 新的 `XxxParser.parse(_:progress:)`：复用 `decodeText`、`ProgressCallback` 的节流惯用法（2,000 行）、用于分块布局的 `BlockAwareResidueCollector`，并以 `ParsedAlignment.finalize` 收尾，从而使规范化、名称去重、来源信息以及全空位拒绝都自动生效 |
| 4 | `Sources/AlignmentWriters.swift` | 新增 `writeXxx`，若该格式限制名称宽度还需一个名称处理器；通过共享辅助函数规范化空位（`:13-18`），并通过 `paddedSlice` 写出参差不齐的行 |
| 5 | `Sources/AlignmentParsers.swift:1425-1441` | 在 `AlignmentParser.parse` 的分派中注册 |
| 6 | `Sources/CLIRunner.swift:58-66, 199-229` | **同时**扩展用法文本与别名表，包括规范扩展名 |
| 7 | `Sources/SeqAlignMacApp.swift` | 打开面板的扩展名允许清单（`:623-700`）、保存／另存为格式菜单（`:822-874`）、`LeftSidebarView.swift:347-358` 的导出分组 |
| 8 | `Info.plist:39-137, 140-270` | `CFBundleDocumentTypes` 条目以及 `UTImportedTypeDeclarations` 扩展名列表 |
| 9 | `Sources/Localization.swift` | 通过 `formatName(_:zh:)`（`:1902-1924`）提供 `AlignmentFormat` 显示字符串，**并且**给出中文镜像 |
| 10 | `Sources/ColorLogic.swift`、`Sources/ColumnStats.swift` | 仅当该格式携带新语义（逐列打分、注释）时才需要 |
| 11 | `Tests/SeqAlignCoreTests/FormatRoundTripTests.swift` | 一条字节精确的往返测试，外加畸形输入用例并断言抛出*错误*而非部分恢复出的模型 |
| 12 | docs | §7 表格、§15.9 的有损性行、`README.md`/`README_ZH.md` 的格式计数，若计数变化还需 `.zenodo.json:9` 与 `aboutFeatures` |

### 14.2 新增配色方案

1. `Sources/AlignmentCore.swift:14-22` —— 新增一个 `ColorScheme` case，取下一个 `Int32` 原始值
   （原始值会桥接到菜单 tag 与 `UserDefaults`；**绝不可为既有 case 重新编号**）。
2. `Sources/ColorLogic.swift` —— 在 `colorIndex(for:scheme:datatype:)`（`:40-50`）中追加分支，
   仿照 `:160-215` 的写法增加一张类别索引表，如适用还要更新 `isProteinOnlyScheme`（`:19-24`）；
   仅当该方案需要列上下文时才扩展 `computeViewport`（`:83-157`）。
3. `Sources/ColorSchemes.swift` —— 给出**浅色与深色两套**调色板（索引 → `NSColor`），
   或者像 `clustalX`/`zappo`/`seaView` 那样声明它与外观无关并加注释说明理由，
   同时在 `ColorSchemeLegend`（`:212-269`）中用 `L.s` 而非字面量补充图例条目。
4. `Sources/SeqAlignMacApp.swift:502-538` —— 一个「视图」菜单按钮（要有意识地决定是否给它快捷键；
   ⇧⌘1…5 已被占用），并且为了可发现性更新 `CommandPaletteView.swift:54-61`。
5. `Sources/LeftSidebarView.swift:245-296` 与 `Sources/SettingsView.swift` —— 两处选择器。
6. `Sources/Localization.swift` —— 在**两张**表中都给出 `scheme*` 名称与工具提示。
7. `Tests/SeqAlignCoreTests/SeqAlignCoreTests.swift` —— 仿照 `:466-488, 625-631` 的索引表断言，
   包括核苷酸数据配蛋白质方案时的回退。
8. `Sources/ExportManager.swift` / `ColorResolver` 的使用方会自动获得该方案，因为二者都经由
   `ColorComputer`；要去验证，不要想当然。

### 14.3 新增遗传密码表

1. `Sources/AlignmentCore.swift:24-42` —— 新增一个 `GeneticCodeTable` case，其原始值为
   **NCBI 表编号**。
2. `Sources/TranslationTables.swift` —— 仿照 `:76-212` 在 `standardTable` 之上写一个增量块
   （只声明差异，绝不重新推导那 64 个密码子），并在穷举的 `table(for:)` switch
   （`:214-234`）中加入新 case。在那里加入该 case 是**强制要求**：该 switch 没有
   default，因此未处理的 case 会是编译错误，而这正是防止不支持的表编号静默回退的机制。
3. `Sources/TranslationOptionsView.swift` —— 选择器条目（目前是英文硬编码字面量，括号里带
   NCBI 编号；把它移入 `L.s` 会是一项改进，见 §10.4）。
4. `Tests/SeqAlignCoreTests/SeqAlignCoreTests.swift:634-686` —— 针对该表，对照官方
   `gc.prt` 的语义抽查被改动的密码子。
5. 在计数被重复出现的地方一并更新：`README.md:8`、`MANUAL_EN.md:181`、
   `MANUAL_ZH.md:183`，以及本文的 §8.11。按 §8.11 的裁定，这个计数是对**本代码库**的陈述——
   英文 "17 NCBI genetic code tables"（连字符与否沿用所在文档的写法），中文「17 张 NCBI 遗传密码表」——并不声称 NCBI 自己定义了多少
   张表，因此不存在需要重新核实的外部分母。

### 14.4 新增本地化字符串

1. `Sources/Localization.swift` —— 在 `AppStrings`（`:75-1925`）中声明该字段，然后**同时提供**
   `zh`（`:1455-1676`）与 `en`（`:1678-1900`）取值，并把该参数加入显式的成员化 `init`
   （`:78-512`），否则构建失败。带参数的字符串应遵循 `:1931-2002` 扩展中的计算属性模式，
   而不要继续增大初始化器的规模。
2. 在 body 求值时以 `L.s.key` 的形式使用它。绝不要在视图里放任何一侧语言的字面量——
   这正是（非阻塞的）CI grep 所统计的内容（§12.7）。
3. 若出现了新的菜单项或面板条目，要让 `CommandPaletteView.swift` 保持同步；它的 32
   个条目按语言缓存（`:34, 73`）。
4. key 的对称性无法在 `SeqAlignCoreTests` 中测试（`Localization.swift` 位于该 target
   之外）；需要 app target 的测试，而 `CONTRIBUTING.md:43` 要求先讨论这样做的必要性。
5. **不要**把 §10.4 死代码清单中的 key 当作仍在使用的 key 复用；要么正式废弃，要么显式接线。

### 14.5 新增测试

1. 按领域选择文件：解析器／写出器往返 → `FormatRoundTripTests.swift`；模型、
   统计、搜索、颜色、撤销场景与增强功能 → `SeqAlignCoreTests.swift`
   （`:522` 起的 `CoreEnhancementTests`）；畸形／边界输入 → `EdgeCaseTests.swift`。
2. 测试数据保持内联（`SeqAlignCoreTests.swift:21` 说明了原因）；在合适处使用
   `Alignment(sequences:…)` 加 `assertRoundtrip`（`:147-160`）。
3. 涉及并发的测试必须经由 `snapshot()` / `lockedSequences`，与 §5.1 的契约一致。
4. 优先断言抛出了错误，而不是断言某个特定的恢复模型，这与 §7.11 保持一致；也不要给测试起一个
   它并未校验的名字（§12.6，最后一条）。
5. **仅**当你新增了核心源文件时，才把该文件加入 `Package.swift:30-41`；随后在本地运行
   `swift test` 与 `bash build.sh`，并预期 CI 会运行 `swift test`、
   `swift build -c release` 与 `./build.sh --skip-tests`。
6. 若总数变化，更新 §12.6 的计数以及 `README.md:8` / `.zenodo.json:9`。

### 14.6 横切规则

领域层保持无 UI（十个核心文件不得 import AppKit/SwiftUI；唯一允许的 import 是
`Foundation` 与 `Compression`，§4.2）。新的重负载工作必须在后台队列上针对
`snapshot()` 运行，并在触碰 `@State`/`@Published` 之前跳回主 actor
（`CONTRIBUTING.md:36`）。任何新的后台任务都必须捕获 `GenerationToken`
并丢弃过期结果（§4.6）。设计令牌取自 `MinimalTheme.swift` 的 `Minimal.*`；视图不得硬编码
颜色，深色模式检测只能用 `NSAppearance.isDarkNow`。新 UI 字符串中的指标名必须与**代码
标识符**一致，绝不能沿用过期的工具提示（§8.2）。

---

## 15. 已知限制与工程偏差

本节是一本台账而非一份辩解：每条都已对照代码核实，且每条都是读者可能从既有文档中错误获得的认识。

### 15.1 死代码与不可达能力

| 条目 | 状态 | 证据 |
|---|---|---|
| `TitleBarTabStrip.swift` | 仅含 10 行注释的占位文件；真正生效的实现是 `FloatingTabBar` | `Sources/TitleBarTabStrip.swift`、`TabbedWindow.swift:294-356` |
| `FaiIndexer` / `.fai` 读写 | 已定义，但在 `Sources/` 或 `Tests/` 中**零调用点**——是内部工具，不是用户功能 | `AlignmentParsers.swift:1005-1072` |
| PHYLIP `sequential`、`strict10Char`、`fullnamePadded` 输出 | 在写出器中可选，但从 app 或 CLI **不可达**（两者都传入默认变体）；只有测试会执行它们 | `AlignmentWriters.swift:161-220`；`SeqAlignMacApp.swift:987`；`CLIRunner.swift:204` |
| `writeFasta(wrapWidth > 0)` 与 `writeClustal(withConsensus: true)` | 受支持，但除测试之外从未被请求 | `:37-56, 266-290`；`FormatRoundTripTests.swift:344` |
| `ResidueAlphabet.gapCount`、`.isNucleotideCharacter`、`.missingDataSymbols`；`IUPACCode.DegeneracyScope`；`AlignmentTranslator.translateNoGaps` / `translateBoth` | 未被使用的**内部**（internal）定义——`Sources/` 中没有任何声明是 `public` 的，而 `translateNoGaps` / `translateBoth` 实为 `private`；不要把它们当作功能呈现 | `ResidueAlphabet.swift:35, 94, 100`；`PrimerCalculator.swift:69-72`；`TranslationTables.swift:462, 467` |
| `Gzip.trailerMatches` / `countGzipHeaders` | 已实现但从未被调用——CRC32+ISIZE 尾部校验只在代码注释中被描述，并未接线；实际生效的拒绝启发式是 `hasBelievableSecondMemberBoundary`，它同样忽略了自身的 `firstUncompressedLength` 参数 | `AlignmentParsers.swift:1214-1288` |
| CLI `exit 65` 的混合轨拒绝 | 仅为防御性代码：该标记位于进程内翻译元数据中，而 CLI 从不产生它 | `CLIRunner.swift:193-196`；`TranslationTables.swift:376-378` |
| `meanPairwiseIdentityExact` | 实现正确，但**除测试外没有调用方**（`Tests/SeqAlignCoreTests/FormatRoundTripTests.swift:258`） | `ColumnStats.swift:342-372` |
| 20 个死本地化 key，包括整个“Select Codon Position”子菜单以及六框概览的残留项 | 见 §10.4 | `Localization.swift` |

### 15.2 被代码推翻的文档表述

一旦某个错误句子在它所在的文档里被改正，对应的行就被删除——所以下表中的任何文字都不得当作定义
引用。剩下的是与代码矛盾、却无法从文档侧修复的 UI 字符串，以及任何文档都无法裁定的说法。

| 错误表述（及其出现位置） | 代码的实际行为 |
|---|---|
| `statsMethodNote`，统计面板底部说明（`Localization.swift:1639, 1863`）："列一致度 = 主频残基占比（空位不计）；平均成对一致度 = 列频次法（空位位点不计）；变异/简约/单态位点按非空位残基统计" | 列一致度除以**信息位点数**，其中空位与未判定符号一并排除，且整列模糊的列得 0 分，§8.1；头条数值是**按位点加权的池化一致度**，§8.2；三个位点计数过滤的是 `unassignableStates`——那个更大的集合，§8.4 |
| `treeHint`，NJ 对话框提示（`Localization.swift:1641, 1865`）："序列数 >200 时取前 200 条" | 按**等间隔**抽样，`step = count / maxSeqs`，§8.8；同族的 `samplingNote`（"……（等距抽样）"，`ColumnStats.swift:506`）才是正确的字符串 |
| `statsGapCols`（"Gap columns" / 「含空位列数」，`Localization.swift:1516, 1739`） | 判定条件是**无可归属残基**，因此也涵盖整列为 `N`/`X`/`?` 的列——以及蛋白质下整列 `B` 或整列 `Z`，§8.3 |
| "可处理多达约 10,000 条序列的比对"；"即将提供 .dmg 与 Homebrew cask"；第三方功能对比行 | 无法从本仓库验证——没有基准测试、没有制品、没有外部核对，§9.9 |
| "CI 会检查视图层硬编码中文"（`CONTRIBUTING.md:34`） | 该 grep 作业确实存在，但带 `continue-on-error: true`，永远无法让构建失败，§12.7 |

### 15.3 并未实现的构建说法

`Package.swift:29` 声称 CI 可以对 `sources` 允许清单做差异检查；**并不存在这样的 CI
步骤**——仅有的 lint 任务是制品守卫和非阻塞的 CJK grep。后果是：新加入的核心文件仍可能在无人
察觉的情况下完全没有测试，而 §14 的检查清单才是实际的控制手段。与此相关，`README.md:171`
把 `./build.sh` 描述为“swift test → 编译 → ad-hoc 签名 → zip”，但本地测试闸门是尽力而为
（§12.3，阶段 3.5）；`CONTRIBUTING.md:48` 的“本地 `swift test && ./build.sh` 必须通过”才是
准确说法。

### 15.4 交互缺陷

* **⇧⌘G 被注册了两次**——视图（View）▸ 显示/隐藏共识序列（Toggle Consensus）（`SeqAlignMacApp.swift:526-527`）与
  工具（Tools）▸ 查找上一个（Find Previous）（`:551-552`）。在 `SeqAlignCommands.body` 中「视图」菜单先于「工具」菜单
  发出，而 AppKit 的 `performKeyEquivalent` 会把事件交给第一个已启用的匹配项，因此 Find
  Previous 实际上无法通过键盘触达；命令面板只为共识序列切换标注 ⇧⌘G，所以这个冲突很难被用户
  发现。（确切的运行期优先级应先经实证复核，然后才能作为定论陈述。）
* **放大**同时绑定到 ⌘+ **以及**第二个标题为空的、携带 `"="`
  的菜单按钮（`:516-520`）——这是一行不可见的菜单项，只为在美式键盘布局上暴露 ⌘=
  而存在，而在该布局上 ⌘+ 从不触发。任何快捷键表都必须把 ⌘= 与 ⌘+ 并列列出
  （`CommandPaletteView.swift:60-61`）。
* **⌘X 语义过载**：画布存在活动选区时它会复制*并且*插入空位（`CopyPasteRouter.cut()`，
  `:1187-1233`）；没有选区时则是标准的 responder cut。删除序列恰恰为了避免冲突而使用 ⇧⌘X。
* Okabe-Ito 有菜单快捷键（⇧⌘5）但**没有命令面板条目**；Default 与 Ti/Tv 方案、
  Move Sequence、Primer、Quality 以及所有图像导出动作**都没有快捷键**
  （`:497, 511-512, 545-546`）。
* Escape/Return 的覆盖并不均衡：Translation 与 Settings 两个表单没有 Escape 绑定，而
  Primer、Logo、Tree、Window、Annotation、Quality、Guide、导出预览以及命令面板都有。
* `.observingAppearanceChanges()` 被应用了两次（`ContentView.swift:98, 103`）。

### 15.5 导出的不对称性

`ExportOptions.dpi` 接受任意取值，但**在任何地方都没有对应的 UI 控件**：PNG 恒为 300
DPI，而尺寸标签硬编码了字符串 "(300 DPI)"（`ExportManager.swift:24-47`）。
`showConsensus` 在两条导出路径上都被硬编码为 `true`，因此在屏幕上隐藏共识行并**不会**在导出
图像中隐藏它。预览缩略图始终是被截断（钳制）到 1,600 px 的 PNG 渲染，与所选的 PNG/PDF/SVG
段无关，而且切换该段也不会重新渲染。序列导出界面彼此不对称：侧栏提供六种格式（没有
FASTQ），通用「另存为」面板提供五种扩展名，而写出器支持七种（§7.12）。

### 15.6 多窗口正确性

`performExport` 依据 `WindowRegistry.shared.activeForAction` 而非所属工作区弹出提示条
（`ExportPreviewSheet.swift:~250`），因此在多窗口会话中该消息可能落到错误的窗口。
`PendingWindowData` 是**单个全局静态元组**
（`SharedUIComponents.swift:568-580`）——既非线程安全也非按窗口隔离——因此两次快速的“在新窗口
中打开”动作（翻译外加外部比对器）可能交叉投递。

### 15.7 测量与指标限制

状态栏的逐列一致度缓存**只**把 `0x2D` 当作空位过滤
（`SeqAlignMacApp.swift:225-240`），而画布与扫描使用
`ResidueAlphabet.isGap`（`'-'`、`'.'`、`'~'`）——因此对于非规范的空位写法，悬停读数可能与画布
不一致。`SearchEngine` **不加锁**地读取 `alignment.sequences`，其安全性仅仅来自 app
总是把快照交给它（§6.1.8）。
`SequenceUtils.mutationType` 尽管注释讨论了按 datatype 分支，却没有 datatype
参数，因此任何转换／颠换的说法只对核苷酸输入成立（仅蛋白质的方案由
`ColorComputer.effectiveScheme` 另行防护）。
`FormatRoundTripTests.swift:56-60` 断言的内容与它自己的名字相反（§12.6）。

### 15.8 平台与分发限制

仅 arm64（`build.sh:70`），因此随附的 zip 在 Intel Mac 上不重新编译无法运行，而
`README` 与 `CONTRIBUTING` 都没有说明这一点。沙箱是**可选启用**的（`SEQALIGN_SANDBOX`），构建
**并未**普遍做 Developer-ID 签名：默认路径是 ad-hoc 签名，而公证只有当 `DEVELOPER_ID` 与
`NOTARY_PROFILE` 同时具备时才执行，且失败时非致命。CI 上传的是 ad-hoc 签名的 zip，保留期 14
天，并且不向 Release 发布任何内容。没有 `.fileImporter`/`DocumentGroup`
的会话恢复，没有自动保存，也没有 `CFBundleLocalizations`。`Info.plist` 在 FASTA 的 UTI
中声明了 `.fna`、`.faa`、`.mpfa`，但打开面板并不接受它们；反过来 `.gz`
既是打开面板的扩展名，也是一种 *Viewer* 文档类型，却没有配套的保存方案。同样地，写出器接受七种
格式，侧栏导出六种，而「另存为」面板只列出五种扩展名（§7.12）。

### 15.9 格式行为限制

`'.'` 会被 NEXUS 矩阵解析器拒绝，而 PHYLIP、CLUSTAL、MSF 与 Stockholm 都接受它并加以规范化，
因此 NEXUS 中的 `GAP=.` 会加载失败。MSF 的 `Weight:` 值在读取时被丢弃、写出时固定为 `1.00`；
名称块中的逐序列 `Len:` 与矩阵宽度在参差不齐的模型下可能不一致。Stockholm 的 `#=GC RF`
会被读取后丢弃且从不写出，因此参考行不能往返。NEXUS 的 `metadata` 永远是 `[:]`，而
`writeNexus(includeMetadata:)` 实际上只控制 `BEGIN SETS`。PHYLIP 名称会被截断到固定字段宽度，
并且写出器的 9+1 与 12 空格布局是有意不做成与经典 PHYLIP 字节一致的。FASTA
残基白名单注释说数字是 "1-7"，而代码接受 `0-9`。`translate(frame: 3)` 以 3
为偏移，而 UI 的 "+3" 是 tag 2（§8.10）。`AlignmentTranslator.translate`
对蛋白质输入是先扫描再抛出（§8.10，只是开销问题）。

### 15.10 静默的 CLI 回退

`--scheme` 拼错会变成 `minimal` 且没有任何警告；非数字的 `--start`/`--end`
被忽略；越界的区域边界被截断（钳制）；超出 6…40 的 `--fontsize`
只警告但继续执行；`--out` 只被 `stats` 识别，因此 `convert … --out x`
会把默认命名的文件写进工作目录。`MANUAL_EN.md:337` 的“没有静默回退”这一精神因此对
`export --scheme` 并**不**成立（§13.2）。

### 15.11 无障碍与本地化欠账

图例浮层在英文界面下显示中文（§10.4 第 4 条）；画布提示条、光标播报、共识序列标签与列悬停提示
只有中文；状态栏字符集标签只有英文；17 个遗传密码选择器条目只有英文。纯键盘工作流大体
完整，但 ⇧⌘G 冲突（§15.4）以及 Okabe-Ito——那个色觉障碍配色方案——缺少命令面板条目，这两者本身
就属于无障碍缺陷。

### 15.12 未经核实的数字

本文没有给出任何性能或容量数字。相关的缺失还有：没有覆盖率测量、没有模糊测试、没有基准测试、
没有 CHANGELOG 或发布说明流程、仓库内部没有 `date-released`
的旁证，也没有 `.dmg` 或 Homebrew formula。

### 15.13 元数据与治理缺口

仓库中**没有**电子邮箱地址、PGP 密钥指纹或表单 URL，然而 `SECURITY.md:15` 与
`CODE_OF_CONDUCT.md:31` 都提到“维护者公布的渠道”；GitHub 的私有漏洞报告是今天唯一可行的路径。
发布元数据同样无法在仓库内部交叉核对：`.zenodo.json` **不含版本号、不含发布日期、也没有 DOI
字段**，因此 `CITATION.cff:10` 的 `0.2.0` 与 `CITATION.cff:12-13` 中的概念 DOI（同样出现在
`README.md:4` 的徽章中）完全依赖于存档记录本身。`CITATION.cff` 本身是合法的 CFF 1.2.0，其作者条目
使用的是规范的 `family-names`/`given-names` key（`:6-7`）。`CODE_OF_CONDUCT.md` 已不再是本节
曾经描述的“翻译失败样本”——标题已完成本地化（`## 可接受的行为示例`，`:9`），
「坦然接受建设性批评」（`:13`）取代了未翻译的 "gracefully"——但它是对 Contributor Covenant 2.0 的
*压缩*中文版，而非该准则的正文：不可接受行为的条目清单被压缩成了一句（`:17-18`），只有一级标题是
双语的（`:2`），而其执行章节把举报指向了 `SECURITY.md` 以及仓库并未公布的维护者联系方式（`:31`）。

---

## 16. 治理、发布元数据与参考文献

### 16.1 文档地图与单一事实来源策略

| 文件 | 职责 |
|---|---|
| [`README.md`](../README.md) / `README_ZH.md` | 项目首页；功能与方法概述 |
| [`docs/USAGE_ZH.md`](USAGE_ZH.md) | 面向任务的用户指南 |
| **`docs/DOCUMENTATION.md`**（权威版本）／`docs/DOCUMENTATION_ZH.md`（本文件） | 规范性的架构、格式、指标、构建与偏差说明 |
| [`MANUAL_EN.md`](../MANUAL_EN.md) / `MANUAL_ZH.md` | 20 节的最终用户参考手册，1:1 双语 |
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) | 环境、命令、架构规则、测试政策、提交流程 |
| [`SECURITY.md`](../SECURITY.md) | 受支持版本、报告途径、声明的攻击面、分发完整性 |
| [`PRIVACY.md`](../PRIVACY.md) | 数据处理表、App Store 营养标签、MAS 与直接分发 |
| [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) | Contributor Covenant 2.0 |
| [`LICENSE`](../LICENSE)、[`CITATION.cff`](../CITATION.cff)、[`.zenodo.json`](../.zenodo.json) | MIT 许可证、引用、存档元数据 |

各类计数（格式数、测试数、表数）目前同时存在于多处——`README.md:8`、`README_ZH.md:8`、`.zenodo.json:9`，以及 `Localization.swift:1528` 中的 `aboutFeatures`。新写的文字应引用本文而不要重述这些数字，这样下一次改动只需在一处修正。

### 16.2 版本与发布元数据

`0.2.0` 记录在 `Info.plist:15-18`（`CFBundleShortVersionString` 与 `CFBundleVersion`，即打包的
事实来源）、`CITATION.cff:10`（`"0.2.0"`）、git 标签 `v0.2.0`、`README.md:35`，以及
**硬编码字符串** `Localization.swift:1542`（`aboutVersion`，中文）和 `:1768`（英文）中。`Sources/`
中没有任何地方去查询 `CFBundleShortVersionString`，因此「关于」窗口显示的是第四份手工维护的副本，
而 `build.sh` 并不嵌入版本信息（它逐字复制 `Info.plist`）。git 历史的起点是压缩后的初始导入
（`8ac0015`，2026-09-24）；`v0.1.0` 标签指向那次导入，`v0.2.0` 标签指向 `5d73c26`（2026-11-14），
因此只有界面 refinement 提交 `694caf5` 在被标记的树之外。本 `docs/` 目录在 `v0.1.0` 打出之后
才进入仓库（该标签的树中没有它），但已包含在 `v0.2.0` 中。

两个 Zenodo DOI 是*有意*并行使用的，凡引用都应明确标注：**概念 DOI**
`10.5281/zenodo.23053513`（`README.md:4` 徽章；解析到最新发布版本）与**版本 DOI**
`10.5281/zenodo.23053514`（仅由存档记录引用——本仓库没有任何文件引用它）。`README.md:108-120`
的 BibTeX 条目带 `note = {v0.2.0}`（`:115`）与概念 DOI（`:117`）。二者都无法在本仓库内部验证，
因为 `.zenodo.json` 没有 DOI 字段。许可证：MIT。
只有两个文件把许可证作为*数据*声明——`CITATION.cff:14`（`license: MIT`，即 SPDX id）与
`.zenodo.json:10-12`（`license.name`）；`LICENSE:3`、`README.md:187` 与 `Info.plist:26` 的
`NSHumanReadableCopyright` 只是以散文表述。

### 16.3 参考文献

源码中所记录的方法文献，外加实现所依赖的软件与格式引用：

1. Saitou, N. & Nei, M. (1987) *The neighbor-joining method: a new method for reconstructing
   phylogenetic trees*, Mol. Biol. Evol. 4:406–425 —— 引用于 `ColumnStats.swift:558`。
2. SantaLucia, J. Jr. (1998) *A unified system for nucleic acid thermodynamic parameters*,
   Biochemistry 37:1–5 —— ΔH/ΔS 参数集与末端校正，引用于
   `PrimerCalculator.swift:4, 138-167`。
3. von Ahsen, K. et al. (1999) *Tm predictions with salt correction including divalent cations and
   dNTP chelation* —— `PrimerCalculator.swift:4, 254-270`。
4. Schneider, T. D. & Stephens, R. M. (1990) *Sequence logos: a new way to display consensus
   frequencies*, Nucleic Acids Res. 18:6097–6100，并含小样本校正
   `e(n) = (K−1)/(2 ln 2 n)` —— `ColumnStats.swift:421, 441-445`。
5. Wong, B. (2011) *Colour picks: points to make on the palette designed for colour-vision
   deficiency*, Nature Methods 8:123 —— Okabe-Ito 调色板的出处归属，
   `ColorSchemes.swift:138-149`。
6. NCBI *The Genetic Code Translation Tables* (`gc.prt`) —— 已实现的 17 张表及其密码子增量，
   `TranslationTables.swift:3, 16-234`；公共数据的出处记录就在此处。
7. Wallace, R. B. et al. (1979) *the 2·(A+T) + 4·(G+C) rule*，`PrimerCalculator.swift:185`。
8. GC 含量采用 EMBOSS 的分母约定（仅计入已定义残基），
   `AlignmentCore.swift:285-301`。
9. IUPAC 核苷酸与氨基酸简并码 —— 简并集合、反向互补所用的配对表
   （`AlignmentCore.swift:220-253`）以及正则字符类（`SearchEngine.swift:345-360`）。
10. 格式规范：GCG MSF（`AlignmentWriters.swift:293-309`，校验和
    `Σ ((i mod 57)+1)·ASCII` mod 10000）、ClustalX 着色与保守性记号
    （`ColorLogic.swift:178-189`、`AlignmentWriters.swift:233-264`）、Pfam Stockholm 1.0
    （`AlignmentWriters.swift:349-371`）、NEXUS/PAUP 的 `SETS`/`CHARSET` 步进记法
    （`AlignmentParsers.swift:531-578`）、FASTQ Phred+33/+64（SAM/BAM 规范，
    `AlignmentParsers.swift:249-260`）、gzip RFC 1952 与 BGZF（samtools）
    （`AlignmentParsers.swift:1186-1423`）、GFF3（Sequence Ontology）。
11. BibTeX `@software` 条目与完整引用块：`README.md:105-166`；CITATION.cff 与
    `.zenodo.json` 如前所述。

`README.md:90-99` 中的对比表（针对 Jalview、AliView 与 UGENE）是关于第三方软件的论断，无法从本
仓库验证；因此此处不予转载。

---

*`docs/DOCUMENTATION_ZH.md` 全文完。本中文版与权威英文版本 [DOCUMENTATION.md](DOCUMENTATION.md)
逐节对应；如有出入，以英文版为准。面向操作的说明见 [USAGE_ZH.md](USAGE_ZH.md)；文档索引见
[README.md](README.md)。*

