# SeqAlignMac — Project Documentation

**Version:** 0.1.0 · **Document type:** technical / project documentation (说明文档) · **Primary language:** English

**Language:** English is the primary language of this documentation set. A mirrored Chinese
version is available at [DOCUMENTATION_ZH.md](DOCUMENTATION_ZH.md).
See the [docs index](README.md) for the full map, and the task-oriented user guide at
[USAGE.md](USAGE.md).

All `file.swift:LINE` citations in this document are relative to the repository root
(`Sources/…`, `Tests/…`, `build.sh`, `Package.swift`). They describe the code as committed at
tag `v0.1.0`; they are the fastest way to verify any statement made here.

---

## Table of contents

1. [Purpose, audience, and document map](#1-purpose-audience-and-document-map)
2. [Project overview](#2-project-overview)
3. [Repository layout](#3-repository-layout)
4. [Architecture](#4-architecture)
5. [Data model reference](#5-data-model-reference)
6. [Module reference](#6-module-reference)
7. [Format I/O specification](#7-format-io-specification)
8. [Algorithms and methods](#8-algorithms-and-methods)
9. [Rendering and performance](#9-rendering-and-performance)
10. [Localisation architecture](#10-localisation-architecture)
11. [Persistence](#11-persistence)
12. [Build system and quality gates](#12-build-system-and-quality-gates)
13. [Command-line interface as a documented contract](#13-command-line-interface-as-a-documented-contract)
14. [Extension guide](#14-extension-guide)
15. [Known limitations and engineering discrepancies](#15-known-limitations-and-engineering-discrepancies)
16. [Governance, release metadata, and references](#16-governance-release-metadata-and-references)

---

## 1. Purpose, audience, and document map

This document answers **"how is it built and how does it work?"**. It is written for
developers, reviewers, and any reader who needs the normative definition of a number the
software produces. It is the single narrative source for architecture, format behaviour,
metric definitions, build rules, and known deviations.

| Question | Document that answers it |
|---|---|
| What is this project, is it worth a look? | [`README.md`](../README.md) (and `README_ZH.md`) |
| How do I open a file, colour it, search, export, run an aligner? | [`docs/USAGE.md`](USAGE.md) (task-oriented guide) |
| How does the software work internally, and what exactly does each metric compute? | **this document** |
| How do I contribute, build, test? | [`CONTRIBUTING.md`](../CONTRIBUTING.md), plus §12 and §14 here |
| Attack surface, signing, undo memory limits? | [`SECURITY.md`](../SECURITY.md), plus §12.5 and §15 here |
| Data collection, privacy manifest? | [`PRIVACY.md`](../PRIVACY.md), plus §12.6 here |
| End-user reference manual (20 numbered sections, bilingual) | [`MANUAL_EN.md`](../MANUAL_EN.md) / `MANUAL_ZH.md` |
| Conduct, licence, citation | [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md), [`LICENSE`](../LICENSE), [`CITATION.cff`](../CITATION.cff) |

**Language policy.** English is primary; Chinese files are mirrors produced from the English
text. `README.md` and `MANUAL_*.md` are self-contained bilingual pairs. `CONTRIBUTING.md`,
`SECURITY.md`, `PRIVACY.md`, and `CODE_OF_CONDUCT.md` are currently Chinese-led documents and
are referenced rather than duplicated here.

**Why the existing documents stay where they are.** `README.md` and `MANUAL_EN.md` are
established entry points with stable external links (Zenodo, GitHub). Moving them would break
those links for no gain. What changes instead is the *authority*: where an existing document
disagrees with the code, this document is correct and the disagreement is recorded in §15. Two
classes of error are common in the older prose and are deliberately not reproduced here —
statements inherited from stale in-app strings in `Localization.swift`, and statements that
were true of an earlier revision of a module.

---

## 2. Project overview

### 2.1 What it is

SeqAlignMac is a native macOS application for viewing, editing, and analysing multiple
sequence alignments (MSAs), together with a headless command-line mode compiled into the same
binary. It reads and writes seven alignment formats — FASTA, FASTQ, NEXUS, PHYLIP, CLUSTAL,
MSF, Stockholm — with transparent `gzip`/BGZF decompression, renders arbitrarily large
alignments through a virtualised Core Text canvas, and computes alignment quality statistics,
consensus sequences, sequence logos, neighbour-joining trees, sliding-window identities,
six-frame translations over 17 NCBI genetic-code tables, and primer thermodynamics.

Distribution metadata (`Info.plist:13-18`) names the bundle `com.seqalign.mac`, display name
`序列对齐`, version `0.1.0`. The executable doubles as a CLI: `SeqAlignMac cli …`
(`SeqAlignMacApp.swift:22-27`).

### 2.2 Design goals

| Goal | Realisation in code |
|---|---|
| Native macOS 14+ | `LSMinimumSystemVersion` 14.0 (`Info.plist:27-28`), `.macOS(.v14)` (`Package.swift:19`), `-target arm64-apple-macosx14.0` (`build.sh:70`). AppKit canvas inside SwiftUI shell; no cross-platform UI toolkit. |
| Minimalist monochrome UI | Design tokens in `MinimalTheme.swift` (`Minimal.*`); the default colour scheme is `minimal` (`AlignmentCore.swift:15`, `SeqAlignMacApp.swift:123-132`); no `.toolbar`, all commands route through the sidebar and menu bar. |
| Keyboard-driven | Full menu shortcut map (`SeqAlignMacApp.swift:433-567`), a 32-entry command palette (`CommandPaletteView.swift:38-72`), canvas cursor keys, sheet-level `.escape`/`.return` bindings. |
| Colour-vision-deficiency accessibility | Okabe-Ito palette (`ColorSchemes.swift:138-149`, attribution Wong 2011), high-contrast mode (`SeqAlignMac.highContrast`), gap diagonals, conservation rail and greyscale ramp that survive monochrome printing. |
| Bilingual UI | One runtime-switched string table (§10); no `.lproj`, no `.strings`. |
| Reproducible pipelines | Deterministic parsers with explicit errors, `declared_aligned` provenance disclosure, NHX sampling/model provenance embedded in generated trees (§8.7), gzip-preserving save path (§7.10), and a CLI whose CSV contract is fixed (§13). |

### 2.3 The deliberate domain/rendering separation

The most consequential architectural decision is that **no analysis result depends on the
renderer, and the renderer owns no analysis**. Numerical work — parsing, statistics,
translation, thermodynamics, search, edit commands, colour *category* selection — lives in ten
UI-free files that together form the `SeqAlignCore` library. Everything that touches pixels,
windows, or the responder chain lives in the app layer.

`ColorLogic.swift:2-7` states the rule for the last remaining boundary case: the core returns
*indices only* (`UInt8` category numbers), and the mapping index → `NSColor` is a rendering
concern held in `ColorSchemes.swift:199`. Consequences:

* The same colour-index matrix feeds the on-screen canvas (`AlignmentCanvasView.swift:709, 811, 1005`),
  the image exporter (`ExportManager.swift:139, 444, 604`), and the off-screen consensus
  renderer (`AlignmentRenderer.swift:106`) — screen, PNG/PDF/SVG, and print cannot drift.
* The core compiles and is testable without AppKit, which is what makes the 110-test suite
  possible (§12.4) and what makes a future non-GUI distribution (server-side statistics, a
  Linux CI checker) cheap.
* Metrics are defined once, in the core, and are cited here from the core's identifiers rather
  than from UI labels (§8).

---

## 3. Repository layout

Tracked content is 59 paths (`git ls-files`), all ASCII-named; there is no asset catalogue, no
`.lproj`, and no test-fixtures directory (fixtures are inline in the test sources,
`SeqAlignCoreTests.swift:21`).

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

Notes that matter when reading the tree:

* `Sources/` is **flat** and `build.sh:66-67` compiles *every* `*.swift` it finds, with no
  exclusion list. A stray file dropped in `Sources/` becomes part of the shipped binary.
* The 26 non-core `Sources/` files are invisible to SwiftPM (§12.1).
* `TitleBarTabStrip.swift` is a 10-line comment-only placeholder kept so that the file list in
  older build notes still resolves; the live tab strip is `FloatingTabBar` in
  `TabbedWindow.swift:294-356` (§15).
* `SeqAlignMac.app/`, `SeqAlignMac.app.zip`, `.build/`, `.DS_Store`, and any `.mimosa/`
  directory present in a working tree are **build or tooling artefacts**, not project content;
  CI fails a commit that adds the first two (`ci.yml:49-54`).

---

## 4. Architecture

### 4.1 Layer stack

The core is organised in four layers. Layer boundaries are *directional*: a layer may use any
layer below it, never above.

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

| Layer | Files | Contract (one line) |
|---|---|---|
| L0 | `AlignmentCore.swift`, `ResidueAlphabet.swift` | Owns the data model and the *meaning* of every residue byte; mutually referencing at file level, acyclic at type level. |
| L1 | `AlignmentParsers.swift`, `AlignmentWriters.swift` | Turns bytes on disk into `Alignment` and back, with format detection and explicit errors. |
| L2 | `TranslationTables.swift`, `ColumnStats.swift`, `PrimerCalculator.swift` | Pure numerical/biological transforms over an `Alignment`; no I/O, no UI. |
| L3 | `SearchEngine.swift`, `UndoRedoManager.swift`, `ColorLogic.swift` | Interaction-shaped services (find, edit, paint) that still contain no AppKit. |

Observed upward uses inside the core (recorded so that new code does not accidentally deepen a
layer): L3 modules call into L2/L0 — `SearchEngine.swift:69, 118-126` uses
`IUPACCode` (L2), `UndoRedoManager.swift:87, 294` uses `CharsetRemapper` (L0), and
`ColorLogic.swift:103` uses `AlignmentStatsCalculator.columnIdentities` (L2). L0's two files
reference each other's types (`AlignmentCore.swift:267-269, 325` → `ResidueAlphabet`;
`ResidueAlphabet.swift:49-75, 85, 141, 204-241, 264` → `Datatype`/`CharsetInfo`/`Sequence`).

### 4.2 The import rule

The only frameworks imported anywhere in the ten core files are **`Foundation`** (all ten) and
**`Compression`** (`AlignmentParsers.swift`, for raw-DEFLATE inflate/deflate of gzip/BGZF).
This is a buildable invariant, not a style preference: `Package.swift:30-41` compiles exactly
those ten files into `SeqAlignCore`, so an `import AppKit` or `import SwiftUI` in any of them
would fail `swift build`/`swift test` — including on CI, where the tests are mandatory.

### 4.3 What lives app-side

| Concern | Owner | Notes |
|---|---|---|
| Scene graph, menus, keyboard shortcuts | `SeqAlignMacApp.swift:34-45, 424-569` | `WindowGroup`, not `DocumentGroup`; one `SeqAlignCommands: Commands` tree. |
| Per-tab view model | `Workspace: ObservableObject` (`SeqAlignMacApp.swift:103-322`) | Holds the shared `Alignment` plus every view state. |
| Window/tab routing | `WindowRegistry.shared` (`SeqAlignMacApp.swift:324-420`) | §4.5. |
| Text rendering | `AlignmentCanvasView.swift` (AppKit `NSView` + Core Text) | §9. |
| Palette (index → `NSColor`) | `ColorSchemes.swift` (`ColorResolver`, 7 palettes, per-appearance variants) | Light+dark variants for `minimal`, `defaultNucleotide`, `transitionTransversion`, `okabeIto`; `clustalX`/`zappo`/`seaView` are appearance-invariant so screenshots stay comparable with the reference tools. |
| Off-screen render geometry | `AlignmentRenderer.swift`, `ExportManager.swift` | Reuses the canvas geometry so exported images match the screen. |
| Subprocess plumbing | `ExternalAlignerView.swift` | §15.4, §6.2.19. |
| Localisation table | `Localization.swift` | §10. |
| Preferences | `SettingsView.swift` (+ `AppSettings`) | §11. |

### 4.4 Notification-based menu-to-view bridging

`WindowGroup` commands are **global**, but every interesting piece of state is **per tab**. The
bridge is a set of 18 `Notification.Name`s declared at `SeqAlignMacApp.swift:1426-1443`
(`removeSelectedSeq`, `reverseComplement`, `insertGap`, `renameSeq`, `moveSeq`, `runAlignment`,
`showPrimer`, `showSettings`, `showTranslate`, `showAbout`, `showGuide`, `showQualityReport`,
`showCommandPalette`, `showExportPreview`, `pasteFromClipboard`, `tabStateChanged`,
`tabDataChanged`, and `lastTabClosed`), plus `languageChanged` from `Localization.swift:1928`.
The four names `tabStateChanged`, `tabDataChanged`, `lastTabClosed`, and `languageChanged` are
consumed by the window root with `.onReceive` (`TabbedWindow.swift:160-173`); the other fifteen
are consumed per tab by `ContentView`.

A menu button posts; each `ContentView` observes through a private `observe(_:_:)` wrapper around
`NotificationCenter.addObserver(forName:object:queue:using:)` that collects the tokens (defined at
`ContentView+Actions.swift:17`, **15 call sites** at `:20-108`), and **every handler opens with the
same guard**:

```swift
guard isActiveWorkspace() else { return }   // WindowRegistry.shared.activeForAction === workspace
```

Because a `ContentView` exists for every open tab, an unguarded handler would open a sheet in
a background window; the guard (`ContentView+Actions.swift:113-115`) plus the token teardown in
`onDisappear` (`ContentView.swift:118-124`) is what makes the fan-out safe. Menu enablement
state and re-localisation use a second trick: `SeqAlignCommands.body` *reads* `registry.editRevision`
and `lang.language` inside `body` (`SeqAlignMacApp.swift:430-431`), so SwiftUI invalidates the
menu tree when either changes (undo/redo greying, language switching at runtime).

One known instance of the wrong pattern survives: `performExport` posts its toast against
`WindowRegistry.shared.activeForAction` instead of the owning workspace
(`ExportPreviewSheet.swift:~250`) — see §15.

### 4.5 Windows, tabs, and the registry

* **No `DocumentGroup`.** Consequently no document-controller Recent menu, no per-document
  autosave, and imperative window titles (`"SeqAlignMac — <name>"`, `TabbedWindow.swift`).
  Open/Save are hand-rolled via `OpenFileManager` and `SaveManager`
  (`SeqAlignMacApp.swift:623-760, 789-1010`).
* **Native tabbing disabled** (`NSWindow.allowsAutomaticWindowTabbing = false`,
  `SeqAlignMacApp.swift:573-585`) so the bespoke strip owns tabs: `FloatingTabBar` is an
  `NSTitlebarAccessoryViewController(.left)` hosting a 36-pt `NSHostingView`
  (`TabbedWindow.swift:294-356`).
* `WindowRegistry.shared` keys workspaces by `ObjectIdentifier`, keeps per-window
  `WindowTabsState` in a weak map, and exposes `workspaceOrder`, `allDirtyWorkspaces`,
  `editRevision`, and — the important one — `activeForAction = workspace(for: NSApp.keyWindow)
  ?? activeWorkspace` (`SeqAlignMacApp.swift:~400`). Every menu command and notification
  handler resolves its target through that expression.
* `TabbedWindow` retains the views of the **3 most recently active** tabs (LRU) and substitutes
  `Color.clear` placeholders for the rest, so tab switching does not rebuild state.
* Each tab owns its own `UndoRedoManager` (per-tab undo history;
  `SeqAlignMacApp.swift:218, 1015-1090`).
* Finder/dock opening goes through AppKit `application(_:open urls:)`
  (`SeqAlignMacApp.swift:573-619`) — there is no `.onOpenURL` in the codebase. In-window
  drop-to-open is `.onDrop` in `ContentView` (`ContentView+Actions.swift:381-420`), which
  loads the first file into the current tab and one new tab per later file (0.1 s apart).
* Termination is guarded: `applicationShouldTerminate` raises an `NSAlert` when any workspace
  is dirty and **aborts** if "Save and Quit" fails for any document
  (`SeqAlignMacApp.swift:587-619`); `NSSupportsSuddenTermination` is `false` in `Info.plist:278-281` precisely so the system cannot bypass that guard.
* `SEQALIGN_DEBUG_OPEN_N` (env) auto-opens N windows via `debugTargetWindowCount` — a test hook.

### 4.6 GenerationToken and revision invalidation

Two distinct mechanisms, both required.

**`revision: UInt64`** is the *content* token. It is mutated only inside
`align.performLocked { … align.revision += 1 }`
(`AlignmentCore.swift:105, 166`; app choke point `SeqAlignMacApp.swift:1042-1049`). Producers
inside the core are `padToMaxLength()` (`AlignmentCore.swift:166`),
`AddSeqCommand.undo` (`UndoRedoManager.swift:203`), `MoveSeqCommand` (`:231, 238`), and
`RemoveColumnsCommand` (`:307, 312`). Individual commands such as `BatchReplaceCommand` and
`InsertGapCommand` deliberately do *not* bump it — the app wrapper does, so every mutation
path (direct edit, undo, redo, transaction) bumps it exactly once. Caches keyed on it:
`Alignment.length` (`AlignmentCore.swift:138-148`), the canvas identity cache
(`SeqAlignMacApp.swift:222-240`), the stats panel dedupe key
`(ObjectIdentifier, revision, ConsensusMode)` (`StatsPanel.swift:51-66`), and the sliding-window
identity cache keyed on `(Alignment identity, revision at snapshot time)`
(`AnalysisSheets.swift:296-323`).

**`GenerationToken`** (`SeqAlignMacApp.swift:93-101`) is the *intent* token: an
`NSLock`-protected monotonic counter. A background job captures a value at submission and, in
its completion on the main thread, returns early if the token has moved on. This is what makes
rapid toggling of sheets and search boxes harmless: search
(`SeqAlignMacApp.swift:291-311`), file loading (`loadGeneration`, `:691-745`), canvas column
stats (`AlignmentCanvasView.swift:605, 646-659`, which additionally triple-checks `=== align`,
`revision`, and consensus `mode`), quality panel (`SheetViews.swift:158-192`), logo / tree /
window sheet previews (`AnalysisSheets.swift:72-84, 213-232, 296-323`), and export preview
(`previewGeneration`). A `revision` bump cannot cancel a stale job and a generation change
cannot tell you the content changed; the design keeps both.

### 4.7 The four micro-view-models

`Workspace` deliberately does not own every scrap of state, because a keystroke in a search
field would otherwise invalidate the whole SwiftUI tree. Four small `ObservableObject`s
absorb the high-frequency mutations:

| Type | Line | Owns | Why it is separate |
|---|---|---|---|
| `SearchTextModel` | `SeqAlignMacApp.swift:51` | the search field's string | Only `SearchBarView` subscribes; typing does not touch the canvas. |
| `LoadProgressModel` | `:59-69` | progress value + `cancelLoading`, behind an `NSLock` | The parser thread writes progress; the flag must be readable/coercible from either thread. |
| `ToastModel` | `:72-89` | `ToastKind` + message, auto-cleared after 2.5 s | Transient overlay state must not participate in document invalidation. |
| `GenerationToken` | `:93-101` | a monotonic counter | Not a view model strictly, but it is published through the same decomposition so sheets can capture cheaply. |

### 4.8 Data flow

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

The load path is `DispatchQueue.global(qos: .userInitiated)` with progress throttled to ≥ 1 %
deltas (`SeqAlignMacApp.swift:696, 723-735`); the CLI path calls detection on the whole buffer
rather than the 64 KB head (`CLIRunner.swift:34-36`).

---

## 5. Data model reference

### 5.1 `final class Alignment`

`AlignmentCore.swift:97-212`. It is a **reference type guarded by an `NSRecursiveLock`**, not a
struct, and the rationale is recorded at `AlignmentCore.swift:91-96`: background workers
(stats, search, logo, tree, export) read the model while the main thread edits it. Copy
semantics would have forced either a lock-free race or a full copy per mutation.

| Member | Signature | Behaviour and invariants |
|---|---|---|
| `init` | `init(sequences:datatype:metadata:charsets:)` | Defaults `[]`, `.nucleicAcid`, `[:]`, `[]` (`:115-121`). |
| `performLocked` | `<T> (() -> T) -> T` | The **single mutation channel** for edit commands; reentrant, so commands may nest (`:125-129`). |
| `seqCount` | `Int` | Locked count (`:131-135`). |
| `length` | `Int` | **Maximum** per-sequence residue count — not a "common" length; the model tolerates ragged rows. Cached on `revision` via `_cachedLength` / `_cachedLengthRevision`, initialised to `UInt64.max` so first access always computes (`:138-148`). |
| `padToMaxLength()` | `Void` | Right-pads each row with `'-'` and each `quality` array with `0` (Q0, deliberately not `'!'`, so the model keeps no ASCII semantics in quality), then `revision += 1` (`:154-167`). |
| `residue(row:col:)` | `UInt8` | Any out-of-range row **or** column, including negatives, returns `0x2D`; in range it returns the raw byte **without** `.`→`-` normalisation (`:170-178`). |
| `columnResidues(col:)` | `[UInt8]` | `col < 0` → an all-gap array; short rows contribute `'-'` (`:181-188`). |
| `snapshot()` | `Alignment` | Deep copy of residues *and* quality plus datatype, metadata, and charsets (`:193-202`). Background callers must use this and must not assign the live class. |
| `lockedSequences` | `<T> (([Sequence]) -> T) -> T` | Read access inside the lock; the returned value must not carry internal array references out of the closure (`:204-211`). |

Stored properties: `sequences`, `datatype`, `metadata: [String:String]`,
`charsets: [CharsetInfo]`, `revision: UInt64 = 0`,
`provenance: AlignmentProvenance.Status = .unknown`, `private let lock = NSRecursiveLock()`.

### 5.2 `struct Sequence` and `struct CharsetInfo`

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

* Parsers **uppercase** residues and **reject illegal bytes with `CoreError.format`** rather
  than dropping them; silently dropping a byte shifts every downstream residue
  (`AlignmentParsers.swift:151-168, 780-784`).
* `quality` is one value per residue by declaration. Padding inserts `0`
  (`AlignmentCore.swift:150-165`); the `+33` ASCII conversion happens only on write
  (`AlignmentWriters.swift:373-393`).
* `originalSpec` is kept verbatim so the NEXUS writer can round-trip step notation instead of
  expanding `1-60\3` into `1-1 4-4 7-7 …` (`AlignmentWriters.swift:100-109`). **Any** column
  remapping discards it (`ResidueAlphabet.swift:220-221, 241`).

### 5.3 The residue alphabet: three tiers

`ResidueAlphabet.swift` exists to remove a documented bug class — the byte `'.'` had three
different behaviours across parsers, and protein data was being filtered with the *nucleotide*
IUPAC set (`:4-13`). Residue semantics are therefore partitioned into three deliberately
different sets, and conflating them produces wrong numbers:

| Tier | Set | Where it applies | Definition |
|---|---|---|---|
| **gap** | `'-'` (0x2D), `'.'` (0x2E), `'~'` (0x7E) | excluded from every denominator and numerator | `gap = 0x2D` (`:22`); `isGap(_:)` (`:27-29`); `normalize(_:)` maps any spelling to `'-'` (`:32`) |
| **unassignable** ("the trait cannot be scored") | nucleotide, 14 symbols: `N R Y S W K M B D H V X ? *`; protein, 5 symbols: `B Z X ? *` | the gate for **site statistics** (variable / parsimony-informative / singleton) | `unassignableStates(datatype:)` (`:49-64`) |
| **undetermined** (smaller set) | nucleotide: `N X ?`; protein: `X ? B Z` | removed from **both numerator and denominator of column identity** | `undeterminedSymbols(datatype:)` (`:70-75`) |

The distinction between tiers 2 and 3 is deliberate and matters: a column that is entirely `R`
*is* real conservation (every sequence agrees it is a purine), whereas an all-`N` column would
otherwise score identity 1.0. Hence an all-gap **or** all-undetermined column scores `identity
= 0` and is counted as a "gap column" (`ColumnStats.swift:142-148`).

Also in this file: `nucleotideCharacters` — the detection whitelist `"ACGTUNRYSWKMBDHV-.*"` plus
digits `0x30…0x39` plus `?` and `~` (`:86-92`) — and the Newick name helpers
`newickSafeName` (replaces `" (),:;"` with `_`, `:105-107`) and `uniqueNewickNames` (sanitise,
empty → `"seq"`, collisions → `_2`, `_3`, …, `:111-128`).

### 5.4 Gap normalisation

Canonicalisation happens **at parse time**, in `ParsedAlignment.finalize`, which pushes every
byte through `ResidueAlphabet.normalize` (`AlignmentParsers.swift:95`). But a directly
constructed or externally mutated `Alignment` may still contain `'.'`/`'~'` — for example a
`ReverseComplementCommand` or a hand-built test model — so consumers must re-test with `isGap`
rather than comparing against `0x2D`. This is what `ColumnStats.swift:118-120` and the writers'
own normalisation path (`AlignmentWriters.swift:13-18`) do. `SequenceUtils.effectiveLength`
(`AlignmentCore.swift:304-306`) is the documented exception: it tests `!= '-'` only, so `'.'`
and `'~'` count as residues for the "sort by length (no gaps)" key.

> **Coordinate systems — read this before writing any code against the model.**
>
> **Internal indices are 0-based. All user-facing coordinates are 1-based.**
>
> * 0-based: `Sequence.residues` offsets, `Alignment.residue(row:col:)`,
>   `columnResidues(col:)`, selection ranges, canvas columns,
>   `dirtyColumns: Set<Int>`, `removedColumns` in `CharsetRemapper.shift`, and `crop`'s
>   `startCol`/`endCol` closed window.
> * 1-based: `CharsetInfo.ranges` (inclusive, NEXUS semantics), GFF3 coordinates
>   (`AlignmentParsers.swift:1153-1154`), CLI `--start` / `--end`
>   (`CLIRunner.swift:182-184`), status-bar `Pos` (`cursorRow+1, cursorCol+1`),
>   exported sequence coordinates, and every frame/column in a warning message
>   (`.frameshift(name:column:)` reports `column + 1`).
> * The out-of-range sentinel is the **gap byte** `0x2D`, not an error: an out-of-range read
>   returns `'-'` silently (`AlignmentCore.swift:170-188`).

### 5.5 Alignment provenance

`AlignmentProvenance.Status` is a `String` enum with cases `aligned`, `unknown`,
`not-aligned` (`ResidueAlphabet.swift:256-261`). `status(ofRaggedSequences:)` (`:264-275`) is
computed **before** padding:

| Condition | Result |
|---|---|
| empty input | `.unknown` |
| raw lengths not all equal | `.notAligned` |
| all equal **and** ≥ 1 internal gap (columns `1..<count-1`, rows with `count > 2`) | `.aligned` |
| all equal, no internal gap | `.unknown` (indistinguishable from an ungapped alignment) |

Consumers: `ParsedAlignment.finalize` (`AlignmentParsers.swift:77, 108`), the CSV field
`declared_aligned` (`CLIRunner.swift:91`), the orange banner in the stats panel
(`StatsPanel.swift:239-245`), `cli convert` propagation (`CLIRunner.swift:265`), and
`ignoreGaps` translation output, which is forced to `.unknown` because gap-free rows are
decoupled from source columns (`TranslationTables.swift:371`).

Two facts to keep straight: ragged input **is** displayed — rows are right-padded to `length` —
and quantitative analysis is **not** blocked; only a warning banner plus the CSV field inform
the user. Any statement that unaligned input disables statistics would be wrong.

### 5.6 Supporting enums

| Type | Values (raw) | Reference |
|---|---|---|
| `Datatype` | `nucleicAcid = 0`, `aminoAcid = 1` | `AlignmentCore.swift:9-12` |
| `ColorScheme` | `defaultNucleotide = 0`, `clustalX = 1`, `zappo = 2`, `seaView = 3`, **`minimal = 4` (the default)**, `transitionTransversion = 5`, `okabeIto = 6` | `:14-22`; raw values are `Int32` because they bridge to menu tags and `UserDefaults` |
| `GeneticCodeTable` | 17 cases whose raw values are NCBI table numbers 1–6, 9–16, 24, 25, 30 | `:24-42`, §8.10 |
| `PhylipVariant` | `sequential = 0`, `interleaved = 1`, `strict10Char = 2`, `fullnamePadded = 3` | `:44-49` |
| `TmMethod` | `nearestNeighbor = 0`, `wallace = 1` | `:51-54` |
| `DimerMode` | `selfDimer = 0`, `hetero = 1` | `:56-59` |
| `MsfType` | `na = 0`, `aa = 1` | `:61-64` |
| `AlignmentFormat` | `fasta, fastq, nexus, phylip, clustal, msf, stockholm, unknown` | `AlignmentParsers.swift:9-11` |
| `SearchScope` | `content = 0`, `name = 1` | `SearchEngine.swift:23-26` |
| `ConsensusMode` | `majority = 0`, `iupac = 1`, `strict = 2` | `ColumnStats.swift:54-58`; raw maps to the settings picker |
| `TranslationDisplayMode` | `codonOnly = 0`, `aminoAcidOnly = 1`, `both = 2`, `ignoreGaps = 3` | `TranslationTables.swift:9-14` |
| `CoreError` | `io, format, noMem, invalidArg, outOfRange, unsupported, external, partial` | `AlignmentCore.swift:387-410` |
| `ProgressCallback` | `typealias (UInt64, UInt64) -> Void` = `(processed, total)` | `:383` |

`CoreError` is the project-wide error channel: domain functions `throw CoreError`, there is no
global mutable error state (`AlignmentCore.swift:412-415`), and each case renders with a
Chinese prefix (`"IO 错误: …"`, `"格式错误: …"`, `"不支持的操作: …"`). Because those
prefixes are baked into the `LocalizedError` implementation, CLI and thrown-error text is not
localised — see §15.7.

### 5.7 `DatatypeDetector`

`AlignmentCore.swift:323-379`. Sampling caps `maxSampleSeqs = 100`, `maxSampleResidues = 100`.
`detect(_:)` (`:332-355`): empty input → `.nucleicAcid`; stride `step = ceil(seqCount / 100)` so
at most 100 sequences are inspected; each sampled sequence contributes **two windows**, a head
window of `min(50, len)` bytes and a 50-byte window starting at `len / 2` (`:349-352`). A single
byte outside `ResidueAlphabet.nucleotideCharacters` → `.aminoAcid` immediately.

`datatype(fromDeclaration:)` (`:360-378`) is the only entry point for NEXUS `DATATYPE=`
declarations: uppercase, `=`→space, tokenise; if the token `DATATYPE` is present the suffix is
matched against prefixes `PROT|AMINO|AA` → `.aminoAcid`, `DNA|RNA|NUC` → `.nucleicAcid`; a bare
declaration is matched the same way after whitespace removal; unknown → `nil`, and the caller
keeps the nucleic-acid default (called from `AlignmentParsers.swift:368`).

### 5.8 `SequenceUtils`

`AlignmentCore.swift:216-307`, the shared byte-level toolbox:

* `reverseComplement(_:)` = reverse then complement (`:224-226`).
* `complement(_:)` (`:229-253`) handles lowercase `a/c/g/t/u` first, then `A↔T`, `U→A`, `C↔G`,
  full IUPAC degenerate pairing `R↔Y`, `K↔M`, `B↔V`, `D↔H`, self-complementary `S`/`W`/`N`,
  `'-','.','~' → '-'`, and returns anything else (`? * 0-9`) unchanged. The rationale at
  `:220-223` is that a naive pass-through of degenerate codes yields a *wrong* reverse
  complement; `FormatRoundTripTests.swift:156-173` and `SeqAlignCoreTests.swift:492-503`
  cover the pairing table exhaustively.
* `mutationType(_:_:)` → `0` match, `1` transition, `2` transversion, `-1` undeterminable
  (`:264-282`). Gap-vs-gap and `N`-vs-`N` are **not** matches; gaps and the nucleotide
  unassignable set are tested before equality. Note the function has **no datatype parameter**,
  so it must not be used on protein data (§15.9).
* `gcContent(_:)` = `GC / (A+C+G+T+U)` — gaps, `N`, and all degenerate codes are excluded from
  the **denominator** (the EMBOSS convention, `:285-301`); returns `0` when no ACGTU is present.
  This is the only GC implementation; the CLI aggregates it per sequence
  (`CLIRunner.swift:122-139`).
* `effectiveLength(_:)` — see §5.4.

## 6. Module reference

### 6.1 Core modules (`SeqAlignCore`, 10 files)

#### 6.1.1 `Sources/AlignmentCore.swift` (415 lines)

**Responsibility:** the data model, the shared vocabulary of enums, byte-level sequence
utilities, datatype detection, and the error type. **Key public types:** `Datatype`,
`ColorScheme`, `GeneticCodeTable`, `PhylipVariant`, `TmMethod`, `DimerMode`, `MsfType`,
`Sequence`, `CharsetInfo`, `Alignment`, `SequenceUtils`, `DatatypeDetector`,
`ProgressCallback`, `CoreError` (§5). **Invariants:** every mutation goes through
`performLocked`; `revision` is bumped once per mutation by the caller wrapper; out-of-range
residue reads return the gap byte rather than throwing; `length` is a *max*, so a ragged model
is representable and legal (§5.5).

#### 6.1.2 `Sources/ResidueAlphabet.swift` (276 lines)

**Responsibility:** the single source of truth for residue *semantics*, plus name handling,
charset coordinate remapping, and the "is this really an alignment?" test.
**Key public types:** `ResidueAlphabet`, `BlockAwareResidueCollector`, `CharsetRemapper`,
`AlignmentProvenance`. **Invariants:** the three-tier residue model (§5.3) must not be
collapsed; `isGap` is the only legal gap predicate; `originalSpec` is discarded by *any*
remapping so a step specification can never silently address the wrong columns.

`BlockAwareResidueCollector` (`:140-185`) is used by CLUSTAL (`:830`), MSF (`:929`), and
Stockholm (`:1089`). Rules: a blank line flushes the pending block; if the block has exactly
one line per existing record, attribution is **by row order** — which is what lets duplicate-
named sequences each get their own line; otherwise attribution is by name with a `claimed` set,
and a *second* occurrence of a name in the same block starts a **new record** rather than
concatenating. Dictionary-keyed aggregation would weld two same-named sequences into one
double-length fake sequence (`:132-139`); `FormatRoundTripTests.swift:354-366` guards this.

`CharsetRemapper` (`:193-244`): `shift(_:removedColumns:)` takes 0-based removed columns, splits
each 1-based closed range at deletions, shifts surviving indices left by the number of removed
columns before them, re-merges adjacent runs, and discards `originalSpec`; empty removal set →
passthrough. `crop(_:startCol:endCol:)` intersects with a 0-based closed window and renumbers
from 1. `shift` is used by `RemoveColumnsCommand` (`UndoRedoManager.swift:294`) and `crop` by
`cli convert --start/--end` (`CLIRunner.swift:249`); the comment at `:246-248` explains the
alternative — stale `CHARSET` ranges silently mis-partitioning data for MrBayes/RAxML/IQ-TREE.

#### 6.1.3 `Sources/AlignmentParsers.swift` (1,441 lines — the largest core file)

**Responsibility:** format auto-detection, the seven alignment readers, the `.fai`
reader/writer, the GFF3 reader, the gzip/BGZF container codec, the shared post-processing step,
and the unified parse entry point. **Key public types:** `AlignmentFormat`, `FormatDetector`,
`ParsedAlignment`, `FastaParser`, `FastqParser`, `NexusParser`, `PhylipParser`, `ClustalParser`,
`MsfParser`, `StockholmParser`, `FaiIndex`/`FaiIndexer`, `GffFeature`/`GffParser`, `Gzip`,
`AlignmentParser`. **Invariants:** detection samples the first 65,536 bytes only; every reader
ends in `ParsedAlignment.finalize` (§7.11); malformed input throws `CoreError.format` rather
than producing a silently plausible model. See §7 for the per-format specification.

#### 6.1.4 `Sources/AlignmentWriters.swift` (394 lines)

**Responsibility:** the seven writers, with interleaved block layouts, name sanitising and
uniquification, the CLUSTAL consensus line, the GCG checksum, and Phred+33 quality emission.
**Key public API:** `AlignmentWriter.writeFasta/writeFastq/writeNexus/writePhylip/writeClustal/
writeMsf/writeStockholm` (§7). **Invariants:** gaps are normalised on the way out
(`:13-18`); ragged models are written with `paddedSlice(_:from:to:)` so every row has exactly
`NCHAR` characters (`:20-34`); name fields are padded to `max(20, longest)` for NEXUS/CLUSTAL/
MSF but **truncated** for PHYLIP (§7.5); `phylipUniqueName` disambiguates inside the fixed
width with `.1`, `.2`, … (`:121-140`) and `msfUniqueName` with `_1`, `_2`, … (`:142-158`).

#### 6.1.5 `Sources/TranslationTables.swift` (479 lines)

**Responsibility:** the NCBI codon tables and frame/display-mode translation with disclosure
warnings. **Key public types:** `TranslationDisplayMode`, `TranslationTables`,
`TranslationWarning`, `TranslationResult`, `AlignmentTranslator` (§8.9–8.10). **Invariants:**
protein input is refused; frameshift never fabricates residues (it emits `'X'`); the mixed
codon+amino-acid track is marked in `metadata` so downstream consumers can refuse it; the
display-mode-to-datatype mapping is fixed (`codonOnly`/`both` → `.nucleicAcid`).

#### 6.1.6 `Sources/PrimerCalculator.swift` (399 lines)

**Responsibility:** IUPAC degeneracy and expansion, nearest-neighbour Tm with salt correction,
GC content on `String`, and dimer ΔG. **Key public types:** `TmOptions`, `IUPACCode`,
`NNTeplexParameters`, `PrimerCalculator` (§8.11–8.13). **Invariants:** all parameterised
concentrations are validated before use (`:200-202`); degenerate expansion bails early at
4,096 variants; results are a `(min, max)` interval over variants, not a single number.

#### 6.1.7 `Sources/ColumnStats.swift` (694 lines)

**Responsibility:** the fused column scan, quality report, consensus resolution, incremental
column statistics, FASTQ quality summary, sequence logo, p-distance + neighbour-joining, and
sliding-window averaging. **Key public types:** `AlignmentQuality`, `ColumnStats`,
`ConsensusMode`, `AlignmentStatsCalculator`, `FastqQualitySummary`, `LogoColumn`,
`LogoComputation`, `LogoCalculator`, `PhyloTreeResult`, `PhyloBuilder` (§8). **Invariants:**
one row-major scan under a single lock produces identities, consensus, and quality together
(`:110-126`); `columnIdentities(_:)` is the declared single source for per-column identity
(`:338-340`, consumed by `ColorLogic.swift:103` and `CLIRunner.swift:117`); the NJ tree always
carries a provenance comment (§8.7).

#### 6.1.8 `Sources/SearchEngine.swift` (376 lines)

**Responsibility:** IUPAC-degenerate and regular-expression search over residue content or
sequence names, with a KMP fast path. **Key public types:** `SearchHit`, `SearchScope`,
`SearchEngine` (§8.14). **Invariants:** `validateRegex(_:scope:)` runs the *same* pipeline as
the initialiser so a UI pre-check can never disagree with the engine (`:362-375`); KMP hits
are overlap-preserving, regex hits deliberately non-overlapping; **the engine reads
`alignment.sequences[...]` without the lock** (`:190, 220, 247, 286`) and is therefore only
safe on a snapshot — which is how the app uses it (`SeqAlignMacApp.swift:295-297`).

#### 6.1.9 `Sources/UndoRedoManager.swift` (469 lines)

**Responsibility:** the command-pattern edit stack, transactions, the memory budget, and the
dirty-column contract. **Key public types:** `EditCommand`, `sequenceBytes(_:)`,
`RenameCommand`, `RemoveSeqCommand`, `ReverseComplementCommand`, `InsertGapCommand`,
`BatchReplaceCommand`, `AddSeqCommand`, `MoveSeqCommand`, `SortSequencesCommand`,
`RemoveColumnsCommand`, `ReplaceAlignmentCommand`, `UndoRedoManager`, `CompositeCommand`
(§8.15). **Invariants:** commands store *deltas* (two exceptions keep whole arrays); `pushUndo`
evicts the **oldest** entries while over either budget but always keeps at least one command; a
new `execute` clears the redo stack, an *empty* transaction does not.

#### 6.1.10 `Sources/ColorLogic.swift` (216 lines)

**Responsibility:** residue byte → colour *category index*, and viewport index matrices, with no
AppKit at all. **Key public type:** `ColorComputer` (§8.16). **Invariants:** index `0` always
means background/gap, indices `1…7` are palette categories; `effectiveScheme(_:datatype:)`
(`:28-35`) guarantees a nonsense pairing never reaches the renderer (nucleotide data with a
protein-only scheme → `.defaultNucleotide`; protein data with `.transitionTransversion` →
`.minimal`); legend text is generated from the same `clustalXThresholdDefault` constant that
drives the colouring, so label and behaviour cannot drift (`:55-79`).

### 6.2 App-side modules

#### 6.2.1 `Sources/SeqAlignMacApp.swift` (1,458 lines) — bootstrap and shell

`@main struct SeqAlignMacApp: App` with `@NSApplicationDelegateAdaptor` (`:20-21`), and a CLI
branch that runs *before* any GUI is constructed (`:22-27`). Declares the single `WindowGroup`
(`:34-45`, `minWidth 1100 × minHeight 520`, `.defaultSize 1500 × 880`, id `"seqalign-main"`),
the whole `SeqAlignCommands` menu tree (`:424-569`), `AppDelegate` (`:573-619`),
`OpenFileManager` (`:623-760`), `SaveManager` (`:789-1010`), `Workspace` (`:103-322`),
`WindowRegistry` (`:324-420`), the four micro-view-models (`:51-101`), `ZoomManager`
(`:1112-1126`), `CopyPasteRouter` (`:1187-1233`), `UndoRedoCoordinator` (`:1012-1103`),
`ExportCoordinator` (`:1235-1326`), `AppearanceStore`/`AppearanceManager` (`:1337-1377`),
`ColorSchemeManager` (`:1105`), `CommandPalette` (`:1379`), the built-in example (4 BRCA1
sequences, `:1396-1405`), the one-shot first-run hint (`:1449-1458`), and the 18 notification
names (`:1425-1445`).

Notable invariants: the extension allow-list for the open panel is `fasta, fa, fas, fastq, fq,
nexus, nex, phy, phylip, aln, msf, sto, stockholm, gz` (`:623-700`) — *content* sniffing, not
extension, decides the parser; recent files are capped at 10 and symlink-resolved (`:781`);
`Workspace` initialisation contains an explicit "key absent ⇒ `.minimal`" special case
(`:123-132`) that any migration to `registerDefaults` must preserve, or the default scheme
silently becomes `defaultNucleotide` (raw value 0).

#### 6.2.2 `Sources/ContentView.swift` + `Sources/ContentView+Actions.swift`

The per-window root layout: sidebar | centre panel | stats panel, with `PanelResizer`
boundaries (`ContentView.swift:55-101`) and the `.onDrop` handler. `+Actions` holds the 15
notification handlers registered through its private `observe(_:_:)` wrapper (each guarded by
`isActiveWorkspace()`, `:113-115`; token teardown in `ContentView.swift:118-124`), the sort actions
(background Schwartzian transform with a `revision` re-check and
`attempts: 2` retry, `:163-266`), paste handling (`:340-379`), the gap-column removal commands
(`removeGapColumns(threshold: 1.0 / 0.5)`, and its own gap-counting loop at `:322-334`), and
three inline zh/en string branches (`:247, 258, 368`, §10.4). Known defect:
`.observingAppearanceChanges()` is applied twice (`:98` and `:103`).

#### 6.2.3 `Sources/CenterPanelView.swift`

Search bar, ruler, canvas container, and status bar (`:365-427`). Owns the 300 ms search
debounce (`:36-40`), the scope pills and regex toggle (`:28-40, 105-168`), and
`AlignmentCanvasRepresentable` wiring (`:294-344`: `differenceReferenceRow`,
`dirtyColumnsProvider`, `onFontSizeChanged`, rename/delete/move/context-action/copied/selection
callbacks, with the selection callback writing `@State` only on an actual change). The status
bar's charset count uses a **hard-coded English label `"Charset"`** (`:384`).

#### 6.2.4 `Sources/LeftSidebarView.swift` (363 lines)

The only toolbar in the app, in five groups (File / Analysis / View / Export / System). Scheme
picker over all 7 schemes (`:245-296`), sequence export offering six formats — **no FASTQ**
(`:347-358`), appearance and language buttons (`:192-200`). Translate and Primer are the only
buttons additionally disabled for protein data (`:78, 84`); every data-dependent button is disabled
when no alignment is loaded (`:58, 72, 90-114, 136, 149`).

#### 6.2.5 `Sources/TabbedWindow.swift` (450 lines)

`WindowRootView` (3-tab LRU view retention), `FloatingTabBar`
(`NSTitlebarAccessoryViewController(.left)`, `:294-356`), `FloatingTabItem` (dirty marker
`"• "`, hover ✕, context close), `WindowDelegateHandler` (`windowShouldClose` dirty cascade →
`UnsavedChangesView`; `windowDidBecomeKey` re-routes the registry), and the dynamic title.
`Sources/TitleBarTabStrip.swift` is a 10-line comment-only placeholder: dead code (§15.1).

#### 6.2.6 `Sources/AlignmentCanvasView.swift` (2,029 lines)

The AppKit document view of the `NSScrollView`. Full pipeline in §9; selection and hit-testing
contract in §9.7. It also owns the incremental column-stats scheduler
(`:602-662`) and the context menu (`:1699-1760`), which repeats all 7 colour schemes and the
sort keys including GC content (`:1711`). Its canvas-local strings are hard-coded Chinese
(`:323, 350, 352, 380-388, 744, 784`), §10.4.

#### 6.2.7 `Sources/SharedUIComponents.swift`, `MinimalControls.swift`, `MinimalTheme.swift`, `PanelResizer.swift`

Shared SwiftUI building blocks. `MinimalTheme.swift` is the **only** permitted source of design
tokens (`Minimal.*`) — views must not hard-code colours (§14.6); `NSAppearance.isDarkNow` is the
only permitted dark-mode probe; `Minimal.shouldReduceMotion`
(`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) gates the empty-state fade, hover
animations, and palette scroll. `SharedUIComponents.swift` provides `ThinScroller` and
`ThinScrollerModifier` (`:281-287, 396-407`), `EmptyStateView` (`:506-564`, loads `logo.svg`
from the bundle once, fallback "Σ"), `LoadingOverlayView` (400×140, 300-pt bar + Cancel),
`ToastOverlayView`, `ErrorBannerView` (lineLimit 3), and the single global `PendingWindowData`
tuple (`:568-580` — not thread-safe and not per-window, §15.8). `PanelResizer.swift:23-24,
36-37` defines the sidebar (150…320 pt) and stats panel (220…460 pt) ranges.

#### 6.2.8 `Sources/Localization.swift` (2,002 lines)

`AppLanguage`, `LanguageManager`, `AppStrings` (433 fields), `L.s`, and ~18 computed
properties. Section 10 covers it in full.

#### 6.2.9 `Sources/ColorSchemes.swift`

`ColorResolver`: the seven palettes (index → `NSColor`) with light and dark variants,
`ColorSchemeLegend` per-scheme legend text (`:212-269`, Minimal uses conservation bands), and
the Okabe-Ito block (`:138-149`, attributed to Wong 2011). Not part of `SeqAlignCore`, so
palette values are not unit-tested (§12.5).

#### 6.2.10 `Sources/AlignmentRenderer.swift`

Off-screen drawing of the consensus row and other exported layers, reusing
`AlignmentRenderGeometry` and `ColorComputer` (`:106`) so the exporter and the canvas agree.

#### 6.2.11 `Sources/ExportManager.swift`

`ExportOptions` (`:24-47`) and `exportImage(_:options:)` for PNG/PDF/SVG. Parameters:
`format`, `dpi = 300`, `colorScheme`, `rowRange`, `colRange`, `fontSize = 13`,
`nameColWidth = 150`, `showConsensus = true`, `dark`, `maxPixelWidth`. Mixed codon+AA tracks
are refused (`:70`, `CoreError.unsupported`). PNG applies a bitmap budget guard
(`:342-345`, 2,000,000,000 B); PDF closes the `CGDataConsumer` explicitly so the xref trailer is
correct; SVG uses a chunked 1 MB-reserved buffer with `escapeXML`, per-name `clipPath`, and gap
rects at `fill-opacity 0.16`. Error strings are Chinese-only (§10.4). `dpi` has **no UI
control anywhere** and `showConsensus` is hard-coded `true` on both export paths (§15.5).

#### 6.2.12 `Sources/ExportPreviewSheet.swift` (620×420)

336×256 thumbnail, segmented PNG/PDF/SVG control, "Export selection only" (disabled without a
selection), dark-mode toggle, estimated size, `.escape`/`.return` bindings. The preview is
**always** a PNG render clamped to `maxPixelWidth = 1600`, with `previewGeneration` discarding
stale images; changing the format segment does not re-render the thumbnail (§15.6). It offers
format, selection-only, dark mode, and a size readout — **not** colour scheme or font size,
which exist only in `ExportOptions` and as CLI flags.

#### 6.2.13 `Sources/StatsPanel.swift`

The always-visible right-hand panel (resizable 220…460, default 264). Cards: Overview; Quality
(orange `statsUnalignedBanner` when `provenance == .notAligned` at `:239-245`, then pooled
identity `:247`, mean/min/max column identity `:247-250`, gap columns, total columns);
Phylogenetic Information — variable/parsimony/singleton sites live **here**, `:267-269`;
Conservation — 5 histogram buckets `min(4, Int(v*5))` with a high-conserved (≥ 80 %) figure,
`:270-298`; Consensus (draggable, copyable, reported in columns); FASTQ read quality when
applicable; Cursor; footer `statsMethodNote` (whose wording is stale — §8.2, §15.2).
Dedupe key `(ObjectIdentifier, revision, ConsensusMode)` (`:51-66`), computation on `.utility`
with its own generation.

#### 6.2.14 `Sources/SheetViews.swift`

About (`:26` version readout), Quick Guide (8 + 8 inline ZH/EN steps, `:84-111`), Rename, Move,
Add-sequence, Unsaved-changes, and the **quality report sheet**. `QualityReportView` rows
(`:217-230, 240-253`) are: pooled identity, min/max column identity, gap columns, total columns,
consensus length, FASTQ mean Phred / Q20 / Q30, then the NEXUS charset list. It does **not**
show GC content and does **not** show variable/parsimony/singleton sites. The quality refresh
runs off-main at `:158-192`.

#### 6.2.15 `Sources/AnalysisSheets.swift`

Logo (720×400, `colsPerPage = 120`, truncation notice, `maxBits` 2.0 / 4.3), NJ tree
(640×380, sampling/clamped/model disclosures, `Copy Newick`), sliding-window chart (640×380,
slider `5…500` step 5, default 50, `:245-364`, identity cache keyed on `(align, revision)`),
and the GFF3 annotation browser (720×440, four columns Sequence/Type/Range/Name with a per-row
Jump, **no filter controls**, `:369-430`; gap-aware `sequenceToColumn` mapping `:440-463`;
`GffParser.parse` at `:494`).

#### 6.2.16 `Sources/SettingsView.swift` (186 lines)

`AppSettings` plus the preferences sheet (width 480, minHeight 440 / maxHeight 560, label
width 92). Real inventory (`:50-162`): appearance segmented control; colour scheme menu (7);
font-size stepper 8…28 pt (`:84-90`); show consensus / high contrast / focus dim toggles
(`:96-101`); ClustalX similarity slider 0.1…0.9 step 0.05 shown as a percentage (`:114-129`);
consensus mode menu majority / IUPAC / strict (`:134-138`); external-aligner timeout stepper
30…3600 s step 30 with default 300 (`:16-22, 150-162`). Only a `settingsDone` button
(`.defaultAction`) — no Escape. Language is **not** here (it is View ▸ Language and the sidebar
button); neither is a "codon triplet display" option: the `settingsCodonTriplet`
key exists but has no read site (§10.4, §15.1).

#### 6.2.17 `Sources/PrimerCalculatorView.swift` (500×460)

Three `@AppStorage` salt fields (`:48-50`) converted to `TmOptions` (`:52-55`); Tm printed as
`"%.1f°C ~ %.1f°C"` with the parameter echo; GC `%.2f%%`; dimer ΔG `%.2f kcal/mol` flagged
`primerWarnDimer` when **ΔG < −5** (`:252, 265`). "Fill from selection" strips gaps. Negatives
and non-finite input are rejected; in-progress strings are ignored. `dntpMolar` is modelled in
the core (`PrimerCalculator.swift:16, 254-269`) but **has no UI field** (§15.3).

#### 6.2.18 `Sources/TranslationOptionsView.swift` (560×400)

Genetic-code picker with 17 literal English entries carrying NCBI table numbers (unlocalised),
frame segmented −3…+3 (`:79-86`), display mode segmented (`:97-102`), name handling keep
original / add `_AA` (`:113-119, 171-175`), and exactly **one** toggle —
`translateNewWindow`, default on (`:124`). Execution: non-nucleotide guard → toast; background
`translateChecked`; warnings joined with `" · "` from `warningText(_:)`; result opens a new
window (`PendingWindowData.prepare` + `openWindow`) or replaces the current alignment through
`ReplaceAlignmentCommand` so it is undoable. No Escape binding (§15.10).

#### 6.2.19 `Sources/ExternalAlignerView.swift`

Presets (`:22-31, 28-33`):

```
mafft     → mafft --quiet {input}                     (stdout capture)
muscle    → muscle -align {input} -output {output}
clustalw  → clustalw2 -infile={input} -outfile={output} -quiet
custom    → (empty, user text)
```

`captureStdout` is derived from the command actually typed — `!cmd.contains("{output}")`
(`:146`) — not from the preset name. Pipeline: main-thread snapshot → background FASTA write of
`seqalign_input_<UUID>.fasta` / `seqalign_output_<UUID>.fasta` in the temp directory →
placeholder expansion, or stdin piping when no placeholder is present (`feedsStdin`) →
quote-aware `parseCommandLine` → executable resolution (`~` expansion, else a PATH probe of
`/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`, `/usr/local/sbin`, `/usr/bin`,
`/bin`, then `/usr/bin/which` — six candidates, `:407`) → `Process` with stdout and stderr
drained **concurrently** with `waitUntilExit()` (pipe-buffer deadlock avoidance) → timeout
`max(10, AppSettings.externalAlignerTimeoutSeconds)` with SIGTERM then SIGKILL after +5 s
(`:239-258`) → temp files deleted in `defer`. The **result-vs-input integrity check**
`resultMismatchReport` compares sequence count, name sets (up to 3 names each for missing and
unexpected), and raggedness, and **refuses to load** a mismatched result. Success opens a new
window named `"<file> (aligned)"` (suffix unlocalised). Result format is auto-detected by the
same content sniffer; the input is written with `AlignmentWriter.writeFasta` (`:154`).

#### 6.2.20 `Sources/CommandPaletteView.swift`

⇧⌘P; `CommandPalette.shared.toggle()` merely posts `.showCommandPalette`
(`SeqAlignMacApp.swift:1379`). 32 cached entries (`:38-72`) built once per language; filtering
is plain `localizedCaseInsensitiveContains` on the title — **substring, not fuzzy** (`:80`).
↑/↓ via `.onKeyPress`, Enter executes, `.keyboardShortcut(.escape)` on the sheet,
`selectedIndex` resets on query change, `ScrollViewReader` centring gated by
`Minimal.shouldReduceMotion`. Scheme entries cover 6 of 7 — there is **no Okabe-Ito entry**
(`:54-61`); export actions, Find Next/Previous, Undo/Redo, New Tab/Window, Close Tab, and the
Logo/Tree/Window/Annotation sheets are also absent (§15.11).

#### 6.2.21 `Sources/CLIRunner.swift` (303 lines)

The headless front end; contract in §13. Dispatch happens in `@main init()`
(`SeqAlignMacApp.swift:19-25`) via `CLIRunner.run(args)`, which is `-> Never` and always exits.

---

## 7. Format I/O specification

### 7.1 Detection

`FormatDetector.detect(_ data: Data) -> AlignmentFormat` (`AlignmentParsers.swift:14-42`)
decodes only the **first 65,536 bytes** (`data.prefix(65_536)`, `:16-17`), trims whitespace and
byte-order marks (`:21, 46-58`), and then tests in this strict priority order:

| Order | Test | Result |
|---|---|---|
| 1 | uppercased prefix `#NEXUS` | nexus (`:26`) |
| 2 | prefix `# STOCKHOLM` | stockholm (`:27`) |
| 3 | prefix `!!AA_MULTIPLE_ALIGNMENT` / `!!NA_MULTIPLE_ALIGNMENT` | msf (`:28`) |
| 4 | prefix `@` | fastq (`:29`) |
| 5 | prefix `>` | fasta (`:30`) |
| 6 | *contains* `#=GF` | stockholm (`:31`) |
| 7 | *contains* `CLUSTAL` | clustal (`:32`) |
| 8 | first line splits into exactly 2 space/tab tokens, both parsing as positive `Int` | phylip (`:34-40`) |
| 9 | otherwise | `.unknown` → **dispatched to the FASTA reader** (`:1436-1438`) |

`decodeText` (`:46-50`) tries UTF-8, then ASCII, and strips leading BOMs — BOM'd files used to
fail with "illegal character 'ï'" (`:44-45`). The single dispatch point is
`AlignmentParser.parse(_:format:progress:)` (`:1425-1441`). The app runs detection on
`data.prefix(65_536)` before dispatch (`SeqAlignMacApp.swift:720-727`); the CLI runs it on the
whole buffer (`CLIRunner.swift:34-36`). Because detection is content-based, a mislabelled
extension usually still resolves correctly — with the caveat that a distinctive marker beyond
the 64 KB sampling window is invisible to it.

### 7.2 FASTA

| Aspect | Behaviour | Reference |
|---|---|---|
| Detection | line begins with `>` | `AlignmentParsers.swift:30` |
| Parsed | header split into `name` + `description` on the **first space only**; wrapped sequence lines concatenated; uppercased; blank lines skipped | `:116-193`, `:144-147`, `:150-168`, `:135` |
| Accepted residue bytes | `A-Z`, `0-9`, `-`, `*`, `?`, `.`; anything else throws `非法字符 'x' 在第 N 行` | `:160-167` |
| Errors | undecodable text; header with no following residues (mid-file and at EOF); no records at all | `:118-120, 139-141, 178-180, 184-186` |
| Progress | byte-position callback every **1,000 lines**, final `(total,total)` | `:171-173, 189` |
| Datatype | inferred by `DatatypeDetector.detect` | `:188` |
| Written | `>name[ description]`, `wrapWidth = 0` → one line per sequence; when `> 0`, wrapping is by `Character` offsets; gaps normalised | `AlignmentWriters.swift:37-56`, `:44-50`, `:16-18` |
| Lossy | FASTQ quality values; structured per-header fields | — |

`wrapWidth` is never passed as non-zero by any app or CLI call site
(`SeqAlignMacApp.swift:991`, `CLIRunner.swift:216`, `ExternalAlignerView.swift:154`), so output
is always one long line per record. The whitelist comment at `:158` says "数字简并码（1-7）" but
the implemented range is `0x30…0x39` (`0-9`) — see §15.9.

### 7.3 FASTQ

| Aspect | Behaviour | Reference |
|---|---|---|
| Detection | line begins with `@` | `AlignmentParsers.swift:29` |
| Parsed | strict 4-line records; blank lines skipped; header split on first space; third line must begin with `+` | `:197-275`, `:209, 214-217, 235-237` |
| Accepted residue bytes | `A-Z`, `-`, `*`; anything else throws | `:225-230` |
| Quality decoding | `Phred+33` by default. **Phred+64 detection is file-level and evidence-based:** if any quality byte `< 0x40` was ever seen the file is pinned Phred+33 (`sawPhred33Evidence`); only if *all* bytes so far are `≥ 64` **and** some byte is `> 74` is it read as `+64`. Bytes below the offset clamp to 0. Stored as plain Phred numbers in `Sequence.quality`. | `:249-260` |
| Errors | missing residue/`+`/quality line; header not starting with `@`; quality byte count ≠ residue byte count (compared in **UTF-8 bytes**); illegal residue; empty read; no records | `:211, 219, 233, 235, 239, 243-247, 262-264, 272` |
| Datatype | forced `.nucleicAcid` | `:273` |
| Progress | throttled to every **4,000 records** to avoid a main-thread hop per read | `:266-270` |
| Written | `@name[ desc]`, residues, bare `+`, quality line `0x21 + min(phred, 93)`; missing positions filled with `'!'` (Q0) | `AlignmentWriters.swift:377-393`, `:386-388` |
| Lossy | the `+` line never repeats the header; read-group / `B`-tag fields are not parsed; description survives only as free text after the first space; padded FASTQ columns export as `'!'` because quality padding uses `0` | `AlignmentCore.swift:150-165` |

FASTQ is **not** downgraded to FASTA on save or on `cli convert --format fastq`: real Phred+33
quality is emitted (`AlignmentWriters.swift:373-393`, regression test
`EdgeCaseTests.swift:287`, CLI path `CLIRunner.swift:217-223`). Any document claiming otherwise
is wrong. The `93` ceiling is the ASCII-printable Phred limit (`0x21 + 93 = 0x7E`): qualities
above it clamp to `~` on write. Note that `convert --format fastq` requires at least one
sequence with quality values, else `CoreError.unsupported` (`CLIRunner.swift:221-223`).

### 7.4 NEXUS

| Aspect | Behaviour | Reference |
|---|---|---|
| Detection | prefix `#NEXUS` | `AlignmentParsers.swift:26` |
| Preprocessing | `[...]` comments stripped **at byte level** before anything else; blocks found with regex `BEGIN\s+(\w+)\s*;(.*?)END\s*;` (case-insensitive, `.` matches newlines) | `:323-335`, `:337-352` |
| Blocks consumed | `DATA`/`CHARACTERS` (matrix + datatype) and `SETS` (charsets). `TAXA` is explicitly ignored ("labels come from the matrix"); FEATURES, TREES, ASSUMPTIONS and any other block are **silently dropped** | `:302-303` |
| Datatype | from the `FORMAT` statement via `DatatypeDetector.datatype(fromDeclaration:)` | `:365-371` |
| `DIMENSIONS` | `NCHAR` is captured and used **only** to distinguish "wrapped continuation of the same taxon" from "a second taxon with the same name" | `:373-383`, `:481-493` |
| Matrix | quoted taxon names (`'…'`/`"…"`) supported; `&` annotations replaced by a space (so `&n` ambiguous-state shorthand is lost); blank line = interleaved block boundary; nameless continuation lines decide the layout once (`isInterleavedLayout = blockLineIdx >= nameOrder.count`) — interleaved attributes by block row index, sequential to the last named taxon; duplicate taxon names get internal keys `name#orderIndex` and merge only while short of `NCHAR`; progress every 2,000 matrix lines | `:385-514`, `:426-442, 421-424, 419, 461-478, 479-496, 414-417` |
| Accepted residue bytes | `A-Z`, `-`, `?`, `*` — **`'.'` is not accepted** and raises "illegal character" | `:404-409`, `:455-459` |
| `SETS` | regex `CHARSET\s+(\S+)\s*=\s*([^;]+)`; parts are `start-end\step`, `start-end`, or a single value; a step > 1 expands into single-column ranges while `originalSpec` keeps the literal text | `:531-535, 543-552, 555, 562-578` |
| Unsupported notation | `PARTITIONS`, `STATES`, `SYMBOLS`, `LABELS`; lowercase matrix input is uppercased anyway | `:448` |
| `metadata` | hard-coded to `[:]` — no NEXUS comment or `[$NOTE=…]` survives | `:293` |
| Written | `#NEXUS`; `BEGIN TAXA; DIMENSIONS NTAX=…; TAXLABELS …; END;`; `BEGIN CHARACTERS; DIMENSIONS NCHAR=…; FORMAT DATATYPE=DNA\|PROTEIN MISSING=? GAP=-; MATRIX …`; optional `BEGIN SETS; CHARSET name = spec; END;`; names quoted when needed; name column padded to `max(20, longest)` and **never truncated**; rows padded to exactly `NCHAR` | `AlignmentWriters.swift:71-111`, `:61-69, 77-79, 91-95, 100-109, 20-34` |
| Lossy | all non-DATA/SETS blocks, `[...]` comments, per-character and state/frequency annotations, and the distinction between `.` and `-` gap spellings | — |

`writeNexus(_:includeMetadata:)` has `includeMetadata = true` by default, but the flag name is
misleading: it gates only the `BEGIN SETS` block, since no metadata is ever written
(`AlignmentWriters.swift:71, 100`). The `'.'` asymmetry is a real interoperability trap — a
NEXUS file using `GAP=.` fails while the same file as PHYLIP or CLUSTAL parses: **do not claim
uniform gap-spelling tolerance across formats.**

### 7.5 PHYLIP

| Aspect | Behaviour | Reference |
|---|---|---|
| Detection | first line = two positive integers | `AlignmentParsers.swift:34-40` |
| Parsed | `ntax nchar`; blank lines dropped; `dataLines.count < ntax` → `PHYLIP 数据行数不足：期望 N，实际 M` | `:591-611` |
| Accepted residue bytes | `A-Z`, `-`, `?`, `*`, `0-9`, and `'.'`/`'~'` **mapped to `'-'`** (dropping them would shift every downstream residue) | `:785-793`, comment `:780-784` |
| Variant discrimination | `isStrict10Char` requires ≥ 11 chars, a whitespace-free letters/digits/`._-` name in columns 1-10, and a residue-like byte at column 11 (the "name exactly fills 10 columns" case, e.g. `AF123456.1`, is handled explicitly); then **four candidates** (sequential × interleaved × both naming interpretations) are parsed and scored: +2 all lengths > 0, +3 all equal, +4 all equal and `== nchar`, +1 all equal and `<= nchar`, −6 any length > `nchar`; ties keep the earlier candidate, i.e. relaxed naming is preferred | `:613-638, 660-676, 679-697, 628-635` |
| Padding / errors | rows shorter than `nchar` right-padded with `'-'`; a row with **zero** residues read → explicit error rather than a silently all-dash canvas | `:639-644, 652-656` |
| Written | default `.interleaved`; header `ntax nchar`; `fullnamePadded` = `name + 2 spaces + full row`; `sequential` = 9-column name + 1 separator, 60 residues/line, continuation indented 10; `strict10Char` = same 9+1 field, one row per sequence; `interleaved` = 60-column blocks, first block `name + 2 spaces`, later blocks indented 12, blank line between blocks | `AlignmentWriters.swift:161-220`, `:167-172, 173-193, 194-200, 201-217` |
| Lossy | names longer than the field are **truncated** (`:123`); descriptions dropped; gap spellings collapsed; the sequential/interleaved distinction is only heuristically recoverable | `:113-120, 121-140, 620-627` |

Both the app (`SeqAlignMacApp.swift:987`) and the CLI (`CLIRunner.swift:204`) call
`writePhylip` with the default variant, so `sequential`, `strict10Char`, and `fullnamePadded`
output is **write-capable but unreachable from the UI or CLI**; it is exercised only by tests
(`FormatRoundTripTests.swift:34, 48, 226, 577`). The 9+1 separator layout is deliberately not
byte-exact classical strict-10, and interleaved continuation lines are indented 12 spaces while
the name field is 10 columns — so "spec-exact PHYLIP" should always be qualified (§15.9).

### 7.6 CLUSTAL

| Aspect | Behaviour | Reference |
|---|---|---|
| Detection | `CLUSTAL` anywhere in the first 64 KB | `AlignmentParsers.swift:32` |
| Headerless input | MAFFT-style bodies are accepted: any line whose 2nd+ tokens are all `A-Z`/`-`/`*` and which is not a conservation line; otherwise `CLUSTAL 文件缺少 CLUSTAL 头` | `:810-828` |
| Parsed | version banners and `MAFFT` prefixes skipped; conservation lines (only `* : .` and spaces) skipped; blank line = block boundary; `name residues…` split on space **and** tab; all tokens after the name concatenated except tokens made only of `*:.` | `:841-874, 889-893` |
| Accepted residue bytes | `A-Z`, `-`, `*`, `?`; `'.'` → `'-'`; other → `CLUSTAL：非法字符 'x' 在行 N` | `:861-873` |
| Errors | records with empty residues dropped before finalize; no records → `CLUSTAL：未找到任何序列` | `:881-884` |
| Written | banner `CLUSTAL W (1.0) multiple sequence alignment`; 60-column blocks; name padded to `max(20, longest)` (not truncated); blank line after each block; optional consensus line | `AlignmentWriters.swift:266-290` |
| Consensus symbols | `*` when all non-gap bytes identical; protein: `:` for a strong group, `.` for a weak group; **nucleotide: only `:`, never `.`** — borrowing the protein weak group `["A","T","V"]` would mark an A/T transversion column semi-conserved; group tables `:233-245`, transcription fixes for `IVL`/`FYW` recorded at `:229-232` | `:247-264` |
| Lossy | conservation lines and quality scores are not retained; the written banner is a fixed string, not the originating version | — |

`writeClustal(_:withConsensus:)` with `true` is requested by **no app or CLI call site** — tests
only (`FormatRoundTripTests.swift:344`).

### 7.7 MSF

| Aspect | Behaviour | Reference |
|---|---|---|
| Detection | prefix `!!AA_MULTIPLE_ALIGNMENT` / `!!NA_MULTIPLE_ALIGNMENT` | `AlignmentParsers.swift:28` |
| Parsed | datatype from the header token (AA → protein, NA → nucleotide); declared length from the `MSF:` line's `Len:`; matrix starts after a line that is exactly `//`, else `MSF 文件缺少 '//' 分隔符` | `:905-906, 911-921, 924-927, 1000` |
| Name/residue boundary | GCG MSF names may occupy up to 20 columns **and contain spaces**, so each line is tokenised on spaces and scanned right-to-left for the first non-residue token; everything left of it is the name (inner spaces preserved), everything right is residues | `:941-958` |
| Accepted residue bytes | `A-Z`, `-`, `*`, `?`; `'.'` → `'-'`; other → `MSF：非法字符 'x' 在行 N` | `:961-975` |
| Consistency | if `Len` is declared, every record whose actual length differs throws `MSF：序列 X 实际长度 … 与 MSF 头声称长度 … 不一致`; shorter records are then right-padded with `'-'` | `:983-988, 991-997` |
| Written | `!!AA/NA_MULTIPLE_ALIGNMENT` header; `MSF: <checksum>  Type: P\|N  Len: <nchar>  Check: <checksum>  ..`; one ` Name: <padded> Len: <n>  Check: <"%4d">  Weight: 1.00` per sequence; `\n//\n\n`; 50-column blocks subdivided into 10-residue groups; names padded to `max(20, longest)`, not truncated, uniquified `_1`, `_2`, … | `AlignmentWriters.swift:302-346`, `:142-158` |
| Checksum as implemented | `Σ_i ((i mod 57) + 1) × ASCII(residue_i)`, then `mod 10000`; the file-level value is the sum of the per-sequence checksums, mod 10000 | `:293-300, 307-309, 321` |
| Lossy | `Weight:` is always `1.00` (any original weighting is dropped and never read back); the per-sequence `Len:` reflects the real row length while the matrix is written to `nchar`, so a ragged model reports two different lengths; original comments, `Type:` beyond P/N, and non-canonical gap spellings are not preserved; the name-block section (including real GCG ` DNA …`/` Rank` reference lines) is skipped entirely on read because parsing starts only after `//` | — |

The `MSF:` field carries the **checksum**, not the sequence count (`AlignmentWriters.swift:307-309,
321`, test `testMsfChecksumIsGcgValue`); do not describe it as a record count.

### 7.8 Stockholm

| Aspect | Behaviour | Reference |
|---|---|---|
| Detection | prefix `# STOCKHOLM`, or the string `#=GF` anywhere in the head | `AlignmentParsers.swift:27, 31` |
| Parsed | header must be the trimmed first non-space line, else `Stockholm 文件缺少 '# STOCKHOLM' 头`; parsing stops at `//`; `#=GF ID …` and `#=GF AC …` become the only two `metadata` keys; other `#` lines ignored; blank line = block boundary; sequence lines `name residues` split on the first space | `:1079-1146`, `:1084-1087, 1102, 1105-1109, 1103, 1114, 1101, 1117-1118` |
| `#=GC RF` | appended to a local `rf` array which is **never used** — the reference consensus is read and then dropped | `:1091, 1110-1113` |
| Accepted residue bytes | `A-Z`, `-`, `*`, `?`; `'.'` → `'-'`; other → `Stockholm：非法字符 'x'` | `:1120-1133` |
| Errors | no sequence lines → `Stockholm：未找到序列行` | `:1138` |
| Written | `# STOCKHOLM 1.0`; optional `#=GF AC` (explicit argument or `metadata["AC"]`); `#=GF ID`; `#=GF SQ <n>`; 80-column blocks separated by blank lines; names with spaces replaced by `_`; trailing `//` | `AlignmentWriters.swift:349-371`, `:365` |
| Lossy | **no `#=GC RF`** in either direction, no `#=GC SEQFILE` or `#=GS` per-sequence annotations, no `#=GF` keys beyond `AC`/`ID`/`SQ`, no insert/missing-state columns; `#=GF SQ` is written but not read back | — |

### 7.9 Non-alignment side formats

* **`.fai`** (`FaiIndex`/`FaiIndexer`, `AlignmentParsers.swift:1005-1072`): the reader expects
  `name\tlength\toffset\tbasesPerLine\tbytesPerLine` (`:1026-1045`, error
  `.fai 索引格式错误：<line>`); the writer self-declares a **virtual index** matching the default
  `wrapWidth = 0` FASTA layout, writes `length` as the **ungapped** residue count, and skips
  zero-length entries (`:1056-1067`). Neither function is called anywhere in the app, the CLI,
  or the tests: describe it as an internal/utility routine, not a user feature (§15.1).
* **GFF3** (`GffFeature`/`GffParser`, `:1148-1184`): a tolerant line parser requiring ≥ 5 tab
  columns and `start <= end`; the `Name=` attribute in column 9 overrides the feature type as the
  display name (`:1171-1177`); returns `[]` for undecodable input instead of throwing;
  coordinates **1-based inclusive** (`:1153-1154`). Consumed by the annotation browser
  (`AnalysisSheets.swift:494`).

### 7.10 gzip and BGZF

`enum Gzip` (`AlignmentParsers.swift:1186-1423`) sits outside the format readers.
`Gzip.decompress(_:) -> Data?` is invoked when the **filename extension** is `.gz`
(`SeqAlignMacApp.swift:705-711`, `CLIRunner.swift:284-293`), so a gzip payload named `.fasta` is
not decompressed.

* Requires `> 18` bytes and magic `1F 8B 08` (`:1195-1197`); loops members while the magic
  repeats (`:1203-1212`); returns `nil` if nothing decoded.
* `decodeMember` (`:1293-1340`) skips the 10-byte header, walks `FEXTRA` subfields looking for
  the BGZF `BC` subfield (`0x42 0x43`, `slen 2`) to obtain `BSIZE = value + 1`, handles
  `FNAME` (`0x08`), `FCOMMENT` (`0x10`), and `FHCRC` (`0x02`); for BGZF the deflate payload ends
  at `start + BSIZE - 8`, otherwise the rest of the file is treated as one member; inflation
  uses `COMPRESSION_ZLIB` (raw DEFLATE).
* **Concatenated-gzip rejection** (`:1214-1232`): if exactly one non-BGZF member was decoded and
  `hasBelievableSecondMemberBoundary` (`:1240-1260`) finds a plausible second member start —
  magic at `p`, `FLG` reserved bits `0xE0` clear, and the preceding 4 bytes as a little-endian
  ISIZE satisfying `0 < le ≤ p` — `nil` is returned, so `cat a.gz b.gz` fails loudly instead of
  silently dropping the tail. The heuristic ignores its `firstUncompressedLength` parameter
  (`_ = firstUncompressedLength`, `:1241`), so the check is weaker than the surrounding comment
  claims, and `trailerMatches` (`:1263-1273`) and `countGzipHeaders` (`:1276-1288`) are **never
  called** — CRC32+ISIZE trailer verification is documented in code but not wired (§15.9).
  Scanning the *compressed* stream for the 3-byte magic would be the wrong test: ≈45 %
  false-failure probability for a 10 MB file, near 100 % for 100 MB (comment `:1219-1228`).
* `compress(_:)` (`:1346-1355`): raw DEFLATE via `compression_encode_buffer` wrapped in a
  10-byte header `1F 8B 08 00 00 00 00 00 00 FF` plus a CRC32 + ISIZE little-endian trailer; CRC
  polynomial `0xEDB88320` (`:1364-1376`). Saving a document whose source was `.gz` re-compresses
  in place (`SeqAlignMacApp.swift:890-893, 924-931`); "Save As" clears
  `sourceIsCompressed`, so the copy is uncompressed (`:940`). `cli convert`/`export` never
  compress: they write the serialised bytes as they are (`CLIRunner.swift:109, 170, 233`), and the
  only gzip decision on the CLI side is *input* gunzip, selected by the input file's extension
  (`:284-294`) — the app-side path at `SeqAlignMacApp.swift:913-954` likewise keys off
  `sourceIsCompressed`, never off an output extension.
* Buffer sizing: deflate starts at `max(input + input/1000 + 64, 64 KB)` with 6 quadrupling
  retries (`:1379-1400`); inflate at `max(input × 8, 64 KB)` with 8 retries (`:1402-1422`).

### 7.11 Shared post-processing and the error policy

Every parser finishes in `ParsedAlignment.finalize(_:datatype:charsets:metadata:)`
(`AlignmentParsers.swift:74-111`), in this order: empty raw set →
`CoreError.format("未解析到任何序列")` (`:76`); provenance computed from the **ragged** input
(`:77`); empty name → `"Seq\(index+1)"` and duplicate name → `name_2`, `name_3`, … (`:85-94`);
every byte through `ResidueAlphabet.normalize` (`:95`); empty residue array →
`CoreError.format("序列 X 没有任何残基…")` (`:96-98`); all-gap residue array →
`CoreError.format("序列 X 的残基全部为空位…")` (`:99-101`); provenance recorded; then
`padToMaxLength()` (`:108-109`).

**Policy: explicit error on malformed input.** SeqAlignMac never drops a residue byte, never
silently truncates a record, and never returns a partial model where a byte was skipped —
because deleting a byte shifts every downstream residue and would corrupt homology statements.
The visible consequences are that an unsupported character raises a located
`非法字符 'x' 在行/第 N 行` error, that PHYLIP with a missing separator raises "未读到任何残基"
rather than opening an all-dash canvas, and that an MSF `Len` mismatch raises instead of
re-padding quietly. The two deliberate exceptions are (i) unknown NEXUS *blocks*, which are
skipped because their absence cannot corrupt the matrix (§7.4), and (ii) GFF3, which returns an
empty feature list rather than throwing (§7.9).

### 7.12 Lossiness summary

| Format | Truncation / discard on **write** | Discard on **read** | Silent fallback |
|---|---|---|---|
| FASTA | quality values; structured header fields | — | `.unknown` format routes here |
| FASTQ | Phred clamped at 93; padded quality is `'!'`; `+` line omits header | read-group/`B` tags; description beyond first space | Phred+64 only on positive evidence |
| NEXUS | — | every non-DATA/SETS block; `[...]` comments; `&` annotations; `metadata` (`[:]`) | `'.'` in matrix is an error, not a fallback |
| PHYLIP | **names truncated** to 10 (or 9) columns; descriptions dropped; gap spellings collapsed | — | variant chosen by scoring heuristic |
| CLUSTAL | conservation lines not retained; banner is a fixed literal | `*:.`-only tokens | headerless MAFFT bodies accepted |
| MSF | `Weight:` fixed at `1.00`; name-block reference lines not emitted | weights, comments, `Type:` beyond P/N | — |
| Stockholm | no `#=GC RF`, no `#=GS`/`#=GC SEQFILE`, only `AC`/`ID`/`SQ` | all other `#` lines, insert/missing states | `#=GF SQ` written but not read |

The user-facing export surfaces are deliberately asymmetric, and documents should describe the
asymmetry rather than the intent: the sidebar's sequence-export menu offers **six** formats
(no FASTQ, `LeftSidebarView.swift:347-358`), the generic Save-As panel offers **five**
extensions (`fasta/nexus/phy/aln/msf`, `SeqAlignMacApp.swift:822-828`), while
`saveAs(format:)` itself supports all **seven** (`:846-874`).

## 8. Algorithms and methods

Each subsection gives the **formula as implemented** (not the textbook form), the literature
reference recorded in the source, the parameter values, and the citation. Where the in-app
tooltip or an older document states something different, this section is normative and the
divergence is listed in §15.

### 8.1 The fused column scan and column identity

`AlignmentStatsCalculator.fusedScan(_:columns:mode:)` (`ColumnStats.swift:62-205`) walks the
matrix **row-major, once, under a single lock** (`:110-126`) accumulating per column
`freqs[col]: [UInt8: Int]` for all non-gap bytes and `informativeCounts[col]` for bytes that
are neither a gap nor a member of `undeterminedSymbols` (`:106-124`). The motivation
(`:70-78`) is concrete: the three public APIs used to be three column-major scans, which for a
10,000 × 50,000 model meant ~50,000 lock operations and ~100,000 temporary arrays.
An optional `columns: ClosedRange<Int>` restricts accumulation while keeping the result arrays
full length (`:79-83, 116, 140`); an empty model (`nSeq == 0 || nCol == 0`) returns an all-gap
consensus, zero identities, and a zeroed `AlignmentQuality` (`:84-91`).

**Column identity** (`ColumnStats.swift:142-160`):

```
I_c = bestCount_c / informative_c
bestCount_c = max over residue bytes b of freqs[c][b]      (ties broken by the SMALLER byte value)
informative_c = |{ residues in column c that are neither a gap nor in undeterminedSymbols }|
```

If `informative_c == 0` — the column is all-gap, or entirely `N`/`X`/`?` (nucleotide) or
`X`/`?`/`B`/`Z` (protein) — then `I_c = 0`, the consensus byte is `'-'`, and the column is
counted as a **gap column** (`:142-148`). The tie-break on the smaller byte value is not
cosmetic: it is what makes consensus output and colouring deterministic across runs and
platforms (`:151-156`, mirrored in the incremental path at `:301-307`).

> The denominator is the part most often mis-described. An earlier formula table
> ("proportion of the most frequent non-gap residue, gaps excluded") omits the ambiguity
> exclusion; with that definition an all-`N` column scores identity 1.0, which the code
> explicitly prevents.

### 8.2 Pooled identity (site-weighted), not mean pairwise identity

The headline quality number is the field `pooledPairwiseIdentity`
(`ColumnStats.swift:16-17`, accumulated at `:166-171`, finalised at `:194`):

```
                      Σ_c Σ_k f_k,c (f_k,c − 1)
pooled identity  =  -------------------------------
                      Σ_c  n_c (n_c − 1)
```

summed only over columns with `n_c ≥ 2`, where `f_k,c` is the frequency of residue class `k` in
column `c` and `n_c` is that column's informative count. This is **site-weighted pooled
identity** — the probability that two randomly chosen *observations at informative sites* agree.
It is **not** the mean over sequence pairs,

```
                     mean over pairs i<j of ( matches_ij / comparable_ij )
```

which is a different statistic with different weighting: the pooled form weights each pair by
how many comparable sites it has and each column by its information content, and it needs one
pass instead of O(n²m). The naming rationale and the distinction are spelled out at
`ColumnStats.swift:9-16`, the UI label is correct ("Pooled identity (site-weighted)",
`Localization.swift:1514, 1737`, used at `StatsPanel.swift:247` and `SheetViews.swift:218`),
and a distinguishing test exists (`FormatRoundTripTests.swift:248`).

Two related points, both easy to get wrong:

* The **exact** mean pairwise identity does exist in code —
  `meanPairwiseIdentityExact(_:maxSequencesForExact:)` (`ColumnStats.swift:342-372`) — as
  `matches / comparable` per pair, where a position is comparable iff neither byte is a gap
  (`:359-364`), pairs with zero comparable sites excluded (`:365`), returning `nil` unless
  `2 ≤ n ≤ maxSequencesForExact` (default **400**, `:348-351`) so the UI can fall back to
  labelling the pooled figure. **It has no call site anywhere in `Sources/`**, so it must not be
  presented as a number the user ever sees.
* The stats-panel tooltip string `statsMethodNote` (`Localization.swift:1639, 1863`) still says
  "mean pairwise identity via column-frequency method". That string contradicts the code and
  must not be quoted as a definition.

### 8.3 Min, max, and mean column identity; gap columns

`minIdentity` / `maxIdentity` are running extrema over columns with `informative > 0`;
`minIdentity` is seeded with the sentinel `2.0` and reported as `0` if no column qualified
(`ColumnStats.swift:136-137, 162-163, 197`). The mean shown in the CLI CSV
(`mean_column_identity`) is computed locally as the arithmetic mean of
`AlignmentStatsCalculator.columnIdentities` (`CLIRunner.swift:116-120`), i.e. an **unweighted**
mean over columns, which is again a different quantity from §8.2.

**Gap columns** count columns in which *no assignable residue exists*: all-gap **or**
entirely undetermined (all-`N`, all-`X`, all-`?`, or the protein equivalents)
(`ColumnStats.swift:142-147` with `unassignableStates` from `ResidueAlphabet.swift:49-64`;
tests `FormatRoundTripTests.swift:265, 272`). The English label "Gap columns" and especially the
Chinese label "含空位列数" (*columns containing gaps*) both understate this; the normative
description is "columns with no scorable residue".

### 8.4 Variable, parsimony-informative, and singleton sites

Site statistics are computed against `unassignableStates(datatype:)` — the **larger** set, not
the identity-exclusion set — so a residue must be *assignable* to count at all
(`ColumnStats.swift:98, 173-191`; field docs `:22-24`). Per column let `definedTotal` be the
count of defined residues, `definedDistinct` the number of distinct defined states,
`definedMax` the largest state frequency, and `definedMinTwo` the number of states occurring at
least twice:

| Site class | Predicate as coded | Line |
|---|---|---|
| Variable | `definedTotal > 0 && definedDistinct >= 2` | `:184` |
| Parsimony-informative | variable **and** `definedMinTwo >= 2` | `:186-187` |
| Singleton | otherwise, `definedMax == definedTotal − 1` | `:188-189` |

The datatype split fixed a protein-side bug in which standard amino acids were filtered with the
nucleotide IUPAC set (`:94-97`; test
`testProteinVariableSitesCountStandardAminoAcids`). These three numbers are surfaced in the
right-hand live stats panel (`StatsPanel.swift:267-269`) and in the CLI CSV — **not** in the
quality report sheet.

### 8.5 Consensus modes

`resolveConsensusByte` (`ColumnStats.swift:207-256`), selected by `ConsensusMode`
(`:54-58`, raw values wired to the three-way picker in `SettingsView.swift:24-25, 134-138`):

| Mode | Rule | Line |
|---|---|---|
| `.majority` | the most frequent residue byte (smaller-byte tie-break) | `:215-216` |
| `.iupac` | nucleotides only (falls back to majority for protein): bitmask `A=1, C=2, G=4, T/U=8`; any byte outside ACGTU → majority fallback; mask → symbol `1→A 2→C 4→G 8→T 5→R 10→Y 6→S 9→W 12→K 3→M 14→B 13→D 11→H 7→V 15→N`, any other mask → majority | `:217-228, 237-256` |
| `.strict` | if `freq.count == 1` that residue, else `N` (nucleotide) / `X` (protein) | `:230-233` |

Orthogonality, documented at `:51-53` and important for reproducibility: **the mode changes
only the consensus glyph.** Column identity, the conservation rail, colouring, the NJ tree, and
pooled identity always use the majority rule, so switching mode cannot alter a quantitative
result. (Note that the "consensus length" row in the quality sheet is really a **column count**,
as the code comment at `SheetViews.swift:224` admits.)

### 8.6 FASTQ quality summary

`FastqQualitySummary` / `computeQualitySummary` (`ColumnStats.swift:375-419`) aggregate over all
rows that have a non-empty `quality` array (`:395-408`):

```
meanPhred = Σ q / total bases      minPhred = min q          (0 when there is no data, :410)
q20Ratio  = #{ q ≥ 20 } / total    q30Ratio = #{ q ≥ 30 } / total   (:404-405)
readCount = number of rows carrying quality                   (:413-417)
hasData   = readCount > 0                                     (:383)
```

`readCount` counts **rows**; the ratios are per **base**. These four figures appear in the stats
panel, the quality sheet, and — only when quality data exists — the CSV fields
`fastq_mean_phred`, `fastq_q20_ratio`, `fastq_q30_ratio` (`CLIRunner.swift:101-105`).

### 8.7 Shannon entropy and the sequence logo

`LogoCalculator` (`ColumnStats.swift:421-489`) implements information content with the
small-sample correction, per `README.md:82` and the in-app note
(`Localization.swift:1640`), with the literature reference **Schneider & Stephens 1990**
recorded at `:421`:

```
H(l) = − Σ_k p_k · log2 p_k                    over the STANDARD (assignable, non-gap) residues of the column
e(n) = (K − 1) / (2 · ln 2 · n)                n = number of counted residues in the column
R(l) = max(0, log2 K − H(l) − e(n))            K = 4 (nucleotide) or 20 (amino acid)
```

Formulas as coded: `:441-445` and `:466-474`. Ambiguity is **not** fractionally
redistributed — only assignable states enter the counts (`:455-459`), which is why an
ambiguity-rich alignment yields a lower `R` than a naive implementation would. Per column the
logo emits `stacks` of `(residue, fraction)` sorted by descending fraction, fractions summing to
1 (`:476-479`); letter height is `fraction × R(l)`.

Truncation is deliberate and disclosed: `maxColumns = 4000` (`:444`, also `:486`), and
`LogoComputation` carries `alignmentColumns`, `maxColumns`, `isTruncated`, and `omittedColumns`
(`:432-438`) which the UI must display (`AnalysisSheets.swift:19-20, 32-37, 76-85`; test
`testLogoReportsTruncation` at `FormatRoundTripTests.swift:465-474`). The reason a cap is
possible at all is that columns are read through the *column-major* API
`AlignmentResidues`/`columnResidues(col:)` (`:457`), so skipping the tail costs nothing else.
The logo sheet pages at 120 columns and uses `maxBits = 2.0` for nucleotides, `4.3` for amino
acids (`AnalysisSheets.swift`).

### 8.8 Neighbour-joining on uncorrected p-distance

**Distance.** `PhyloBuilder.pDistance` (`ColumnStats.swift:524-538`):

```
d_ij = 1 − matches_ij / comparable_ij
comparable  ⟺  neither byte is a gap (isGap)  AND  neither byte is N or X     (:531-533)
d_ij = 1.0 when no comparable site exists                                       (:537)
```

Jukes-Cantor and Kimura corrections are explicitly **not** applied (`:543`, comment
"仍未做 Jukes-Cantor / Kimura 校正"). Consequence, stated by the code itself and mandatory in any
document: the tree is defensible **only for low-divergence relatives**, where multiple
substitutions per site are rare. The in-app disclosure string is `treeModelUncorrected`.

**Subsampling.** `sampledSequences(_:maxSeqs:)` (`ColumnStats.swift:511-522`) takes an
**equal-interval (equidistant)** stride, `step = count / maxSeqs`, default `maxSeqs = 200`
(`:544, 560, 568`) — *not* "the first 200". The intent comment at `:541-542` ("而非固定取前
maxSeqs 条") exists precisely because that misconception had been documented; the NHX comment
says "(even sampling)" (`:506`) and a test pins the behaviour (`FormatRoundTripTests.swift:478`).
Two documents and one UI hint (`Localization.swift:1641, 1865`) still claim "first 200"; they are
wrong, and the sibling string `treeSampledNote` "抽样建树（等距）" is right.

**Tree construction.** `njTree(_:maxSeqs:provenanceComment:)` (`ColumnStats.swift:568-665`),
reference **Saitou & Nei 1987** (`:558`). Tip names pass through
`ResidueAlphabet.uniqueNewickNames` (`:574`). Degenerate sizes: 0 or 1 taxa → `();` / `(name);`
(`:590-595`); **2 taxa → `(A:d/2,B:d/2);`** preserving the distance rather than collapsing it
(`:596-603`, test `FormatRoundTripTests.swift:494-502`). For ≥ 3 taxa a pre-allocated
`(2n−1)²` matrix is used (`:605-615`) and the classic criterion applied while `active.count > 2`
(`:619-656`):

```
rowSum_i = Σ_{j≠i} D[i][j]
Q(i,j)   = (m − 2) · D[i][j] − rowSum_i − rowSum_j
limb_i   = 0.5 · d_ij + (rowSum_i − rowSum_j) / (2 · (m − 2))
limb_j   = d_ij − limb_i
D[new,k] = (D[i,k] + D[j,k] − d_ij) / 2
```

Negative branch lengths are **clamped to 0 and counted** (`:576-580, 647, 651, 660`), reported as
`clampedBranchLengths` and surfaced by `treeClampedBranches`. Newick numbers use `"%.5f"`
(`:598, 647, 661`).

**Provenance comment.** On by default, inserted at the root (`:582-587`):

```
[&sampled=<used>_of_<total>;model=p-distance;clamped=<n>]
```

with `distanceModel = "uncorrected p-distance"` (`:576`) and `samplingNote` produced by
`PhyloTreeResult` (`:505-507`). The ethics rationale — a reader of the Newick alone must be able
to tell that the topology is a subsampled approximation from an uncorrected model — is recorded
at `:493-495` and `AnalysisSheets.swift:214-217`. Legacy convenience APIs: `njNewick` (Newick
only, `:560-562`) and `pDistanceMatrix` (`:544-556`).

### 8.9 Sliding-window identity

`slidingWindowIdentity(_:window:)` (`ColumnStats.swift:669-671`) averages per-column identity in
windows. `windowAverages(from:window:)` (`:676-693`) requires `window >= 2` and non-empty input,
clamps `w = min(window, n)`, steps by `max(1, w/2)`, places each point at the window centre
`(start + end − 1) / 2`, and **always emits a final short window** so the right edge is not lost
(`:677-692`). The split into "identity vector" and "window averages" exists so the vector can be
cached independently of the slider (`:672-675`; UI cache at `AnalysisSheets.swift:252-254,
300-323`), which is why dragging the window slider costs O(n) rather than a full re-scan. UI
default window 50, range 5…500 step 5.

### 8.10 Six-frame translation, frameshifts, and internal gaps

`AlignmentTranslator` (`TranslationTables.swift:267-479`). Entry points
`translate(_:table:frame:displayMode:) throws -> Alignment` (`:277-282`) and
`translateChecked(...) -> TranslationResult` (`:289-373`);
`isMixedCodonTrack(_:)` reads metadata key `seqalign.translation.mixedTrack` (`:269, 376-378`).

* **Datatype gate.** Protein input is refused: `translate` throws `CoreError.format` (`:280`) and
  `translateChecked` returns `.notNucleotideInput` with the input echoed back (`:296-300`). The
  bug class avoided is explained at `:271-276`. (Cost caveat: `translate` performs the work via
  `translateChecked` *before* throwing, so a protein alignment is scanned wastefully — §15.9.)
* **Frames** (`:316-328`). `frame < 0` → reverse-complement first, then offset `|frame| − 1`
  (`:320-324`); `frame > 0` → offset `frame`; `frame == 0` → reference frame. The UI picker maps
  the labels −3, −2, −1, +1, +2, +3 to **tags −3…2** (`TranslationOptionsView.swift:79-85`), so
  "+1" is tag 0, "+2" is tag 1, "+3" is tag 2. This coupling is a trap for API users: calling
  `translate(frame: 3)` directly offsets by 3, not by 0 — the enum-like frame semantics are
  UI-coupled, not self-consistent (§15.9).
* **Display modes** (`:330-349`). `codonOnly` returns the frame-adjusted **nucleotide** sequence;
  `aminoAcidOnly` uses `translateFrameAware(padToCodon(work))`; `both` interleaves 3 bases + 1
  amino acid per codon (the display-only mixed track); `ignoreGaps` strips all gaps and
  translates per-column codons of the gap-free string.
* **Internal gaps.** `translateCodon` (`:390-396`): **any gap inside a codon → `'X'`**; lookup
  miss → `'X'`; non-ASCII table entry → `'X'`. `padToCodon` right-pads with `'-'` so a trailing
  partial codon is not silently dropped (`:380-387`), which is what the
  `.lengthNotMultipleOfThree` warning describes.
* **Frameshift phase detection.** `translateFrameAware` (`:408-449`) finds the first **internal**
  gap run whose length is not a multiple of 3 (the run must start at index > 0, `:419`); that
  column becomes `firstBadColumn`, output from there onward is unconditionally `'X'`, and the
  *codon index* of the first affected codon is returned for the `.frameshift(name:column:)`
  warning (`:424-448`). The alternative — back-translating or inventing residues — would fabricate
  data; `FormatRoundTripTests.swift:194-208` pins the `X` behaviour.
* **Warnings** (`TranslationWarning`, `:240-252`): `frameshift`,
  `lengthNotMultipleOfThree(Int)`, `mixedCodonTrack`, `raggedOutput`, `notNucleotideInput`.
  `TranslationResult.isSafeForPhylogenetics` is `false` when any of
  `mixedCodonTrack | raggedOutput | frameshift | notNucleotideInput` is present (`:256-265`).
  The UI joins the applicable texts with `" · "` (`TranslationOptionsView.swift`).
* **Output labelling** (`:356-372`): `codonOnly`/`both` → `.nucleicAcid` (with the mixed-track
  metadata for `both`); `aminoAcidOnly`/`ignoreGaps` → `.aminoAcid`; `ignoreGaps` output is forced
  to `provenance = .unknown` because its rows are decoupled from source columns. The comment at
  `:357-361` explains the "A read as alanine" hazard that this prevents. Sequence names are
  **not** suffixed by the core; `_AA` is a UI option (`:350-353`,
  `TranslationOptionsView.swift:17, 113-119`).
* Dead helpers `translateNoGaps` / `translateBoth` (`:462-478`) are superseded by
  `translateFrameAware` and must not be documented as API (§15.1).

### 8.11 The 17 genetic-code tables

`TranslationTables.standardTable` (NCBI table 1) enumerates all 64 codons
(`TranslationTables.swift:18-73`); the other 16 cases are expressed as deltas on top of it, and
dispatch is `table(for:)` with an **exhaustive 17-case switch and no default** (`:214-234`) — so
an unsupported NCBI table number cannot be reached and cannot silently fall back. Source
attribution "NCBI 标准翻译表（公开数据）" at `:3`. Implemented table numbers:
**1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14, 15, 16, 24, 25, 30.**

| Case | NCBI no. | Deviations as coded | Line |
|---|---|---|---|
| `.standardTable` | 1 | full 64-codon enumeration | `:18-73` |
| `.vertebrateMito` | 2 | ATA→M, TGA→W, AGA→\*, AGG→\* | `:76-83` |
| `.yeast` | 3 | ATA→M, CTT/CTC/CTA/CTG→T, TGA→W | `:87-96` |
| `.moldProtozoanMito` | 4 | TGA→W | `:99-103` |
| `.invertebrateMito` | 5 | ATA→M, TGA→W, AGA→S, AGG→S | `:106-113` |
| `.ciliate` | 6 | TAA→Q, TAG→Q | `:116-121` |
| `.echinodermMito` | 9 | AAA→N, AGA→S, AGG→S, TGA→W | `:124-132` |
| `.bacterial` | 11 | identical to standard (differences are initiation codons only, not table entries) | `:134-138` |
| `.altYeast` | 12 | CTG→S | `:141-145` |
| `.ascidianMito` | 13 | ATA→M, TGA→W, AGA→G, AGG→G | `:148-155` |
| `.flatwormMito` | 14 | AAA→N, AGA→S, AGG→S, TAA→Y, TGA→W | `:158-167` |
| `.blepharismaMito` | 15 | TAG→Q | `:170-174` |
| `.euplotid` | 10 | TGA→C | `:177-181` |
| `.chlorophycean` | 16 | TAG→L | `:184-188` |
| `.pterobranchMito` | 24 | TGA→W, AGA→S, AGG→K | `:191-197` |
| `.sr1` | 25 | TGA→G | `:200-204` |
| `.peritrichNuclear` | 30 | TAA→E, TAG→E | `:207-212` |

Spot checks against the official `gc.prt` semantics are covered by
`SeqAlignCoreTests.swift:634-686`. The 17 table numbers are **a statement about this codebase**;
any claim about how many tables NCBI currently defines is an external fact that this repository
cannot verify, and the "17 of 27" phrasing should not be repeated as a code fact.

### 8.12 Melting temperature

`PrimerCalculator.tm(_:method:options:)` (`PrimerCalculator.swift:179-223`) returns a
`(min, max)` interval over all IUPAC variants.

**Wallace rule** (`:184-196`, `README`/`MANUAL_EN.md:197`):
`Tm = 2·(A+T+U) + 4·(G+C)`.

**Nearest-neighbour** (`:197-221` core at `calculateNNTm`, `:226-282`), reference **SantaLucia
1998 unified parameters** (`:4`, table at `:138-149`), ΔH in kcal/mol, ΔS in cal/(mol·K):

| Neighbour | ΔH | ΔS | Neighbour | ΔH | ΔS |
|---|---|---|---|---|---|
| AA/TT | −7.9 | −22.2 | CT/AG | −7.8 | −21.0 |
| AT | −7.2 | −20.4 | GA/TC | −8.2 | −22.2 |
| TA | −7.2 | −21.3 | CG | −10.6 | −27.2 |
| CA/TG | −8.5 | −22.7 | GC | −9.8 | −24.4 |
| GT/AC | −8.4 | −22.4 | GG/CC | −8.0 | −19.9 |

Ten unique duplexes with reverse-complement equivalents folded (`:136-137`); the lookup tries
the reverse complement when the direct dinucleotide is absent (`:239-252`).

**Terminal (helix-initiation) corrections** (`:151-167`), applied to both ends: a 5′/3′ end G·C
adds `ΔH += 0.1`, `ΔS += −2.8`; an A·T end adds `ΔH += 2.3`, `ΔS += 4.1`. The comment at
`:152-155` warns explicitly against also adding the generic `0.2 / −5.7` initiation term, which
would double-count.

**Salt correction — the von Ahsen route** (reference `:4`, implementation `:254-270`):

```
saltMm = [Na+] · 1000
if [Mg2+] > 0:  freeMg = [Mg2+] − [dNTP]        (mM)
                if freeMg > 0:  saltMm += 120 · √freeMg      ← dNTP chelation modelled
ΔS += 0.368 · (n − 1) · ln( max(saltMm / 1000, 0.001) )
```

**Equation** (`:272-281`):

```
Tm = ΔH · 1000 / ( ΔS_salt + R · ln(C_T / x) ) − 273.15
R = 1.987 cal/(mol·K);   C_T = oligo concentration;
x = 1.0 for a self-complementary (palindromic) sequence, else 4.0;
guarded by |denominator| > 1e-10.
```

Palindromy is tested against the reverse complement with the local `complementChar`
(`:284-299`), which handles `A/T/C/G/U` only.

**Validation and failure modes** (all `CoreError.unsupported`): `naMolar > 0`, `mgMolar >= 0`,
`oligoMolar > 0` (`:200-202`); a variant containing anything other than `A C G T` — e.g. `U` or a
gap (`:208-210`); degenerate expansion exceeding **4,096** variants (`:195, 220`); no computable
variant (`:215-217`). Defaults (`TmOptions`, `:10-18`): `naMolar = 0.05` M, `mgMolar = 0.0`,
`oligoMolar = 0.25e-6` M, `dntpMolar = nil`; the UI presents them as 50 mM Na⁺, 0 mM Mg²⁺,
0.25 µM oligo (`PrimerCalculatorView.swift:48-56`). **`dntpMolar` has no UI field**, so Mg²⁺
chelation cannot currently be corrected for by the user (§15.3). Reference-vector tests:
`SeqAlignCoreTests.swift:517` (OligoCalc-derived fixtures, NN Tm within 1 °C),
`FormatRoundTripTests.swift:517-537` (55.46 °C / 62.13 °C ±1.5 against Biopython `Tm_NN`, Mg →
equivalent-Na identity to 1e-6, chelation removing the Mg term).

### 8.13 Degeneracy and dimer free energy

**Degeneracy** (`IUPACCode.degeneracy`, `:77-107`): per-position multiplication where **min**
skips gaps and counts degenerate codes as 1, and **max** counts gaps ×1 and ambiguous codes ×
|expansion| (`:93-105`); overflow saturates to `UInt32.max` via `multipliedReportingOverflow`
(`:88-92`) — tested with 4^16 (`EdgeCaseTests.swift:130-151`).
**Expansion** (`expand(_:)`, `:24-47`) uses the standard IUPAC sets, with `N → [A,C,G,T]`
deliberately excluding `N` itself (`:41-44`). `expandAll(_:limit:)` (`:110-130`) bails as soon as
`results.count * expanded.count > limit` (default **4096**, `:114-117`).
`DegeneracyScope` (`:69-72`) is defined and never used (§15.1).

**Search-specific expansion** `expandForSearch(_:)` (`:56-62`) differs on purpose: it returns
`expand(code)` **plus the literal character itself**, plus `T↔U` equivalence, deduplicated and
sorted — needed so a non-regex query `NNN` matches a literal `N` in the data, the same semantics
as the regex class `[ACGTN]` (`:49-55`).

**Dimer ΔG** (`dimer(_:b:mode:)`, `:322-370`; ΔG core `:379-398`):

```
inputs truncated to maxDimerInputLength = 200 characters          (:320, 324-331)
partner strand = reverseComplement(a) for .selfDimer, reverseComplement(b) for .hetero   (:326-332)
both strands must be ≥ 4 nt, else ΔG = 0.0                        (:334)
enumerate every 3′ suffix of a × every offset in the partner; extend the longest contiguous
complementary run over pairs AT TA GC CG AU UA                     (:360, 372-376)
score each qualifying run (run ≥ 4) with calculateWindowDg; keep the MOST NEGATIVE   (:336-369)

ΔG = Σ ( ΔH·1000 − T·ΔS )   over terminal correction + NN dinucleotides, with T = 310.15 K (37 °C)
```

returned in kcal/mol. The UI flags `ΔG < −5` as `primerWarnDimer` (`PrimerCalculatorView.swift:252,
265`). Note an implementation asymmetry worth knowing before tuning: the window ΔG loop consults
only `nnParams[direct]`, with **no reverse-complement fallback**, unlike the Tm path
(`:390-395` vs `:239-252`).

**GC on strings** (`:308-314`) applies the same rule as `SequenceUtils.gcContent` (§5.8) but on
`String` — `G+C` over `A+C+G+T+U`.

### 8.14 Search: IUPAC matching, regex translation, and KMP

`SearchEngine.swift`. Construction (`:51-80`) branches on regex mode:

* **Regex mode:** literal-only uppercasing via `uppercasingLiterals` (`:84-115`), which preserves
  escape sequences and character classes so that `\d`, `\b`, `\w`, `\s` are not inverted into
  `\D`, `\B`, `\W`, `\S` (`:82-83`); then, **for `.content` scope only**, IUPAC translation
  `translatePattern` (`:308-342`) and `NSRegularExpression(options: [.caseInsensitive])`. If
  compilation fails, `regex == nil` and content search returns nothing — it does **not** degrade
  to the IUPAC path (`:175-177`). IUPAC→regex class table (`:345-360`):
  `R→[AG] Y→[CT] S→[GC] W→[AT] K→[GT] M→[AC] B→[CGT] D→[AGT] H→[ACT] V→[ACG] N→[ACGTN]`,
  everything else unchanged; user-written character classes `[...]` are copied verbatim
  (`:321-333`) and escape pairs verbatim (`:314-320`).
* **Non-regex mode:** `patternSets = rawPattern.map(IUPACCode.expandForSearch)` (`:69`); if every
  set is a singleton a KMP table is built (`:71-78`, `tryExactPattern` `:118-126`,
  `buildKMPNext` `:129-143`).

Three matching engines:

| Engine | Line | Advancement | Overlap |
|---|---|---|---|
| KMP | `:187-213` | state carried across `next()` as `kmpState = next[m-1]` (`:196-200`) with a persistent scan cursor, so `findAll` is O(n) (`:44-46`) | preserved — "AA" in poly-A reports all 9 positions (`EdgeCaseTests.swift:114-126`) |
| Regex | `:216-241` | `location + max(len, 1)` (`:231-233`) | non-overlapping, so `\d+` does not re-hit inside "12345"; per-sequence decoded-string cache (`:47-49, 218-222`) |
| IUPAC set matcher | `:244-261` | `currentPos += 1` | overlapping; `assert`s ASCII residue bytes (`:268-270`) with a `T↔U` equivalence escape hatch (`:273-275`) |

**Name scope** (`:283-302`): regex, or `range(of:options:.caseInsensitive)`; name hits are
returned as `SearchHit(seqIndex:, position: 0, matchLen: 0, isNameHit: true)` so the canvas
highlights the whole row. `validateRegex(_:scope:)` (`:365-375`) runs the *same* uppercasing +
translation pipeline as the initialiser, so a UI pre-check cannot disagree with the engine
(`:362-364`); it is called on the main thread at `SeqAlignMacApp.swift:281`. Empty pattern → no
content hits (`:171`) although `validateRegex("")` returns `true` (`:366`). Cooperative
cancellation is via `findAll(shouldStop:)` (`:156-166`).

### 8.15 Undo and redo: commands, transactions, budgets

`UndoRedoManager.swift`. Design: **command objects, not full-document snapshots**, with two
exceptions that store whole arrays. `protocol EditCommand` (`:8-20`) requires `execute(on:)`,
`undo(on:)`, `description`, and offers `estimatedMemoryBytes` (default 0, `:23`) and
`dirtyColumns: Set<Int>?` (default `nil`, `:24`); `sequenceBytes(_:)` estimates a snapshot at one
byte per residue (`:28-30`).

The `dirtyColumns` contract (`:14-19`) is the performance-critical part:

| Value | Meaning | Effect |
|---|---|---|
| `nil` | scope unknown | full column-stats recompute |
| `Set()` (empty) | the edit touches no column statistics (rename, reorder, move) | reuse the cache unchanged |
| non-empty | these columns only | recompute exactly those columns |

| Command | Line | State kept | `dirtyColumns` |
|---|---|---|---|
| `RenameCommand` | `:34-50` | old/new name | `Set()` |
| `RemoveSeqCommand` | `:52-77` | removed sequences | `nil` (undo clamps the insertion index to array bounds, `:66-76`) |
| `ReverseComplementCommand` | `:79-93` | original residues | `nil` |
| `InsertGapCommand` | `:98-129` | `class` records of `actualInsertPos` | `nil`, rationale `:104-109` |
| `BatchReplaceCommand` | `:131-164` | old/new residues | `Set(pos..<pos+len)` if length-preserving, else `nil` (`:138-144`) |
| `AddSeqCommand` | `:169-205` | `class`, added sequence + per-row pre-padding lengths | `nil`; undoes `padToMaxLength` side effects by trimming and bumps `revision` (`:195-201`) |
| `MoveSeqCommand` | `:210-240` | `class`, recorded `actualInsertIndex` | `Set()`; no-op guard for `from == to` (`:224-225`) |
| `SortSequencesCommand` | `:244-266` | full before/after arrays | `Set()`; memory = both arrays (`:256`) |
| `RemoveColumnsCommand` | `:270-314` | full previous arrays **and charsets** | `nil`; single-pass in-place column removal (`:291-306`), `CharsetRemapper.shift` remapping (`:294`) restored on undo (`:311`) |
| `ReplaceAlignmentCommand` | `:316-352` | datatype/sequences/charsets/metadata before **and** after | `nil`; used by translation-in-place |
| `CompositeCommand` | `:449-469` | child commands | union, `nil` if any child is `nil` (`:454-461`); undo in reverse order (`:466-468`) |

**Stack policy** (`:359-445`): `maxStackDepth = 50` (`:361`) and `maxStackBytes = 256 MiB`
(`:365`, rationale `:356-358`). `pushUndo` evicts the **oldest** commands while over either
budget but always keeps at least one entry (`:413-419`); `undoCommand`/`redoCommand` return the
command so the toast can name it (`:422-435`); a new `execute` clears the redo stack (`:408`);
`clear()` also resets `stackBytes` (`:437-444`). Test: `EdgeCaseTests.swift:236-248`.

**Transactions** (`:379-398`): `beginTransaction()` pushes an empty frame (nesting supported);
`execute` appends to the top frame instead of the undo stack; `commitTransaction()` **ignores
empty transactions** so redo history survives (`:383-388`, test
`testEmptyTransactionKeepsRedoStack`), folds child frames into the parent (`:389-392`), and at
the root level wraps 2 or more commands into a `CompositeCommand` (`:393-398`).

**There is no coalescing or merging rule for repeated identical edits.** Consecutive keystrokes
produce separate commands; the only aggregation is the explicit transaction API, driven by
`executeTransaction(_:)` at `SeqAlignMacApp.swift:1066-1075`. Any statement that "typing is
merged into one undo step" would be false. Undo/redo execution is wrapped by the app in
`performLocked { … revision += 1 }` (`SeqAlignMacApp.swift:1037-1057`), and per-tab the manager is
a fresh instance (`:218`).

### 8.16 Colour category indexing

`ColorComputer` (`ColorLogic.swift`), the only place residue bytes become colour *categories*.

| Scheme | Index table | Lines |
|---|---|---|
| `.minimal` | single-byte context: `0` for gaps else `3` (no column identity is available per byte; documented neutral-grey fallback) | `:40-50` |
| `.defaultNucleotide`, `.transitionTransversion`, `.okabeIto` | `residueToDefaultIndex`: A→1, C→2, G→3, T/U→4, N→5, gap→6, everything else (all degenerate codes and unknowns)→7 | `:160-175` |
| `.clustalX` | `AVLIMFW`→1, `KRH`→2, `DE`→3, `NQST`→4, `CGP`→5, `Y`→6, gap→0, other→7 | `:178-189` |
| `.zappo` | `AVLIMC`→1, `FWY`→2, `KRH`→3, `DE`→4, `STNQ`→5, `GP`→6, gap→0, other→7 | `:192-203` |
| `.seaView` | `AILMVFWC`→1, `KR`→2, `STNDEQGP`→3, `HY`→4, gap→0, other→7 | `:206-215` |

`computeViewport(_:scheme:rowStart:rowCount:colStart:colCount:identities:clustalXThresholdOverride:)`
(`:83-157`) returns a row-major `[UInt8]` of size `rowCount × colCount` where `0` means
background/gap (`:81-82, 90`). It is bounds-safe (rows/columns beyond the model stay `0`,
`:113, 118, 131`); column identities come from the caller's cache when supplied and are
recomputed only for the two schemes that need them (`:97-106`); `.minimal` maps identity to the
5-step grey ramp `UInt8(max(1, min(5, round(identity·4) + 1)))` (`:115`) with gaps staying `0`
(`:121`); `.clustalX` colours a column only when `identity >= threshold`, writing index `7`
otherwise (`:139-153`), with the threshold injectable for tests (`:138-139`).
`clustalXThresholdDefault = 0.3` and the live value is read from / written to
`UserDefaults["SeqAlignMac.clustalXThreshold"]` behind a `> 0` guard (`:52-64`); `isProteinOnlyScheme`
is `{clustalX, zappo, seaView}` (`:19-24`) and `effectiveScheme` is the guard described in §6.1.10.

### 8.17 Parameter and constant catalogue

| Value | Meaning | Reference |
|---|---|---|
| `65_536` | bytes decoded for format detection | `AlignmentParsers.swift:17`; `SeqAlignMacApp.swift:722` |
| `100` seqs / `50+50` residues | datatype detection sampling (head + mid windows) | `AlignmentCore.swift:328-330, 349-352` |
| `1000 / 4000 / 2000` | progress throttle lines (FASTA / FASTQ / other readers) | `AlignmentParsers.swift:171, 268, 417, 607, 837, 937, 1099` |
| `0.01` | minimum progress delta before a main-thread hop | `SeqAlignMacApp.swift:730` |
| `2.0` | sentinel for "no informative column" in `minIdentity` | `ColumnStats.swift:136, 197` |
| `400` | `maxSequencesForExact` for exact mean pairwise identity | `ColumnStats.swift:348` |
| `4 / 20`, `4000` | logo alphabet sizes (K) and `maxColumns` | `ColumnStats.swift:444, 446, 486` |
| `200` | NJ / p-distance `maxSeqs`, sampled equidistantly | `ColumnStats.swift:511-522, 544, 560, 568` |
| `"%.5f"` | Newick branch-length precision | `ColumnStats.swift:598, 647, 661` |
| `4096` | degenerate primer expansion limit | `PrimerCalculator.swift:110, 195, 220` |
| `200`, `4`, `310.15` | dimer input cap, minimum complementary run, ΔG temperature (K) | `PrimerCalculator.swift:320, 334, 360, 382` |
| `120`, `0.368`, `1.987`, `273.15`, `1e-10`, `0.001`, `1.0/4.0` | salt coefficient, SantaLucia ΔS coefficient, R, Celsius offset, denominator guard, salt floor, self-complementarity factor | `PrimerCalculator.swift:257, 266, 269-280` |
| `0.05 M / 0.0 M / 0.25e-6 M / nil` | Tm defaults Na⁺ / Mg²⁺ / oligo / dNTP | `PrimerCalculator.swift:11-15` |
| `50` commands, `256 MiB`, `≥1` | undo depth cap, byte cap, keep-last-one | `UndoRedoManager.swift:361-365, 416-418` |
| `0.3` | ClustalX conservation threshold default | `ColorLogic.swift:55` |
| `64` | `maxIncrementalDirtyColumns` before falling back to a full scan | `AlignmentCanvasView.swift:634-635` |
| `6.0` px | glyph density threshold below which letters are not drawn | `AlignmentCanvasView.swift:163` |
| `512` | maximum glyphs per `CTFontDrawGlyphs` batch | `AlignmentCanvasView.swift:~919-997` |
| `60 / 50+10 / 80 / 20 / 10 / 9 / 12` | block widths and name-column constants (PHYLIP & CLUSTAL 60, MSF 50 with 10-residue groups, Stockholm 80, minimum name column 20, PHYLIP name columns 10/9, interleaved indent 12) | `AlignmentWriters.swift:79, 122, 178, 186, 197, 204, 213, 268-269, 318, 329-330, 359` |
| `(i % 57) + 1`, `mod 10000`, `"%4d"` | GCG checksum | `AlignmentWriters.swift:294-300, 309, 321, 325` |
| `43 / 64 / 74 / 0x21 / 93` | Phred+33 offset, Phred+64 offset, Phred+64 evidence threshold, Q0 write character, Phred write ceiling | `AlignmentParsers.swift:254-257`; `AlignmentWriters.swift:386-388` |
| `10 / 18 / 8`, `0xEDB88320` | gzip header, minimum file size, trailer size; CRC-32 polynomial | `AlignmentParsers.swift:1195, 1203, 1328-1333, 1350-1353, 1367` |
| `13 pt` (range 8…28), `150` (80…2000), `180` (150…320), `264` (220…460) | default font size / name column / sidebar / stats panel widths | `SeqAlignMacApp.swift:105, 1117-1125`; `AlignmentCanvasView.swift:118-190`; `PanelResizer.swift:23-24, 36-37` |
| `300`, `30…3600 step 30` | external-aligner timeout default and UI range; SIGKILL +5 s after SIGTERM | `SettingsView.swift:16-22, 150-162`; `ExternalAlignerView.swift:239-258` |
| `300 ms` | search debounce | `CenterPanelView.swift:36-40` |
| `2.5 s` | toast auto-clear | `SeqAlignMacApp.swift:72-89` |
| `3` | tabs kept materialised (LRU) | `TabbedWindow.swift` |
| `2 000 000 000` B / `1600` px | PNG bitmap budget cap / preview max pixel width | `ExportManager.swift:342-345`; `ExportPreviewSheet.swift` |
| `10` | recent-files cap | `SeqAlignMacApp.swift:781` |

---

## 9. Rendering and performance

### 9.1 Virtualisation

`AlignmentCanvasView` is the document view of an `NSScrollView`
(`:118-190` geometry; wrapped by `AlignmentCanvasRepresentable`,
`SharedUIComponents.swift:375-410`). The visible cell band is computed from the clip rect
(`:439-442`):

```swift
minCol = Int((clipRect.minX - nameColWidth) / cellWidth)
maxCol = Int((clipRect.maxX - nameColWidth) / cellWidth) + 1
minRow = Int((clipRect.minY - topBarHeight - consensusHeight) / cellHeight)
maxRow = Int((clipRect.maxY - topBarHeight - consensusHeight) / cellHeight) + 1
```

Every one is clamped `max(0, …)` and bounded `min(…, count-1)` **before** any `stride` — the
comment notes an unclamped `0..<negative` range is a hard crash, not a warning. Only
`[minRow…maxRow] × [minCol…maxCol]` is drawn, and `draw(_:)` intersects the visible band with
`dirtyRect`, so scrolling repaints only the new strip. Geometry: `cellHeight = fontSize × 1.4`;
`cachedCellWidth = max(4, advance width of "A" in the monospace font)`, measured once per font
change (`:400`); `rulerHeight = 24`, `conservationRailHeight = 12`, `topBarHeight = 36`,
`consensusHeight = showConsensus ? cellHeight + 4 : 0`.

### 9.2 Density-adaptive glyphs: the 6.0 px threshold

```swift
private static let glyphDensityThreshold: CGFloat = 6.0   // AlignmentCanvasView.swift:163
```

Applied to residues (`glyphsEnabled = cachedCellWidth >= threshold && glyphCTFont != nil`,
` :1017`) and to the consensus row (`:833`). Below 6 px per column the canvas becomes a pure
colour heatmap: rectangles still carry full identity and palette information, but no letters are
drawn. Because `cachedCellWidth` scales linearly with font size, the threshold is crossed near
the bottom of the 8…28 pt zoom range — so the honest user-facing description is "at the smallest
zoom levels the letters disappear and only colour blocks remain", not a fixed zoom percentage.
Row height is unaffected; the switch is width-only.

### 9.3 Batched Core Text drawing and colour bucketing

`:919-997` build the fast path: a 128-entry glyph table, `ensureGlyphCache` resolving
`CTFont`/`CGFont`/glyphs/advances/ascent/descent once per font size, and `flushGlyphs()` issuing
`CTFontDrawGlyphs` in batches of **≤ 512 glyphs**. `fillBundled(_:)` merges all same-colour cell
rects into one `CGMutablePath` and fills it once. Residues are bucketed into **8 background/text
colour pairs** (`:999-1204`), giving a worst case of roughly 16 path fills plus a handful of
glyph batches per repaint **regardless of selection size**.

Draw order (`draw(_:)`, `:417-543`): surface background → conservation rail → search-overview tick
marks → hover underline → column ruler → consensus row → sequence names → residues → selection →
column block → search highlights → drag indicator → name-column divider → focus ring →
column-peek tooltip → **pinned name strip last**.

### 9.4 Frozen name strip

`pinnedNamesRange` (`:138`) activates once `clip.bounds.origin.x >= nameColWidth`, i.e. once the
real name column has scrolled out of the viewport. `activeNamesRange` (`:146`) and
`namesBoundaryX` (`:151`) remap hit-testing so a click inside the floating strip still addresses
the right row. An observer on the clip view's `boundsDidChangeNotification`
(`installScrollObserverIfNeeded` / `clipBoundsChanged`, `:236-264`) invalidates both the old and
the new strip rectangles; the strip is repainted last (`:524-542`) over a card-coloured backing
so it is opaque.

### 9.5 Legacy scrollers

`SharedUIComponents.swift:375-410`: both scrollers present, `autohidesScrollers = false`, scroller
class replaced by `ThinScroller` (a 6-pt rounded knob, α 0.55 hovered/dragged else 0.35), and
`scrollView.scrollerStyle = .legacy` (`:408`) — the comment explains that overlay scrollers
disappear and long alignments need a permanently grabbable horizontal bar.
`ThinScrollerModifier.applyToAllScrollViews` **deliberately skips** scroll views whose
`documentView is AlignmentCanvasView` (`:284`), so the canvas keeps legacy bars while the sidebar,
stats panel, and sheet lists get thin ones; it re-runs after 1.5 s because SwiftUI rebuilds views.

### 9.6 Off-main column statistics

The canvas schedules column statistics on a dedicated serial queue
(`DispatchQueue(label: "seqalign.canvas.stats", qos: .userInitiated)`) with **one in-flight job**
(`AlignmentCanvasView.swift:640-662`). On each edit it drains `Workspace.takeCanvasDirtyColumns()`
(`:602-632`): a non-empty set of at most `maxIncrementalDirtyColumns = 64` columns is recomputed
incrementally with `computeColumnStats(_:prevStats:dirtyColumns:mode:)`
(`ColumnStats.swift:271-314`, *exactly* the same rules including the tie-break, `:284-311`);
`nil` means unknown scope and `[]` means nothing changed; anything larger than 64 falls back to a
background full scan (`:631, 640-662`). Results are discarded unless all three of `=== align`,
`revision`, and consensus `mode` still match (`:605, 646-659`). While statistics are unavailable
the canvas **degrades to uncoloured rather than blocking the main thread** (`:999-1204`).

### 9.7 Interaction and hit-testing contract

Coordinate conversion is centralised in one trio — `cellRange(for:)`, `rect(for:)`,
`setSelectionRect(_:…)` (`:1941-1962`) plus `pointToCell(_:)` (`:1964`, clamped to the data area) —
so there is exactly one rule to remember:

```
col = floor((x − nameColWidth) / cellWidth)
row = floor((y − topBarHeight  − consensusHeight) / cellHeight)
```

`SelectionRange{rowStart,rowEnd,colStart,colEnd}` is inclusive and `Equatable` (`:25-30`).
Selection precedence in `currentSelectionRange()`/`reportSelection()` (`:1874-1912`): column
block → marquee cell range → single cursor cell → whole alignment (⌘A); `hasActiveSelection`
**intentionally excludes a lone cursor cell** (`:1918`) so that "Export selection only" and Copy
behave sensibly right after a click. `mouseDown` (`:1302-1381`) priority: conservation-rail scrub
(`y < 12 && x ≥ nameColWidth`) → name-column resize (grab zone −2…+5 px around `namesBoundaryX`) →
double-click in the name band = Rename sheet → drag-to-reorder in the name band → Option =
whole-column block selection → normal cursor placement. `mouseDragged` (`:1383-1456`) performs
resize, rail scrub (`scrollColumnToVisibleCentered`), the row-band drag indicator, and marquee
selection with union-of-rects invalidation, and **defers `reportSelection()` to `mouseUp`** — the
comment records that publishing a `@Published` selection per drag event caused a ~120 Hz SwiftUI
invalidation storm. Only the four arrow keys (123/124/125/126) and Escape (53 → `clearSelection()`)
are consumed (`:1485-1497`); Option+arrows extend from `selectionAnchor`; `moveCursor` scrolls the
cursor back into view. Zoom: `magnify(with:)` threshold ±0.06 (`:1641-1678`) and ⌘+scroll
accumulating `deltaY` past ±0.5 (the comment records that `event.magnification` is always 0 inside
`scrollWheel`, so an earlier branch there was dead code); `zoomIn`/`zoomOut` prefer the
`onFontSizeChanged` callback so `Workspace` stays the single source of truth for font size, and
`ZoomManager` clamps to 8…28 pt (`SeqAlignMacApp.swift:1112-1126`).

### 9.8 Colour layers on the canvas

Conservation rail: for `.minimal`, `Minimal.chartColor(identity:)` — a 5-step grey; for scientific
schemes, α = `0.35 + 0.65 × identity` of the consensus residue's palette colour, gap consensus →
`Minimal.gapTint`, and `identity ≥ 1.0` adds a 2 px bright cap (`:678-737`). Residues come from
`ColorComputer.computeViewport(...)` with the cached identity vector. Gap cells get a neutral tint
plus an underlined `−` (and diagonals in high-contrast mode). Difference mode dims residues equal
to the cached reference-row snapshot with **no background fill**; `cachedDiffRefRow` is keyed on
`(row, revision)` (`:1046-1058`). Focus dim plus an active selection lays `Minimal.dimOverlay`
over non-selected cells; even rows get zebra banding. Search hits use the app's only blue,
`Minimal.searchHighlight`; the current hit is stroked 2.5 px `Minimal.primary`, others 1.5 px
`Minimal.borderStrong`, all viewport-clipped.

### 9.9 Performance disciplines

* **Snapshot first** ("rule B3"): any background job reads the model through
  `align.snapshot()` taken on the main thread; mutations happen only under `performLocked` with
  `revision += 1`. Used by export, stats, tree, logo, window chart, search, external aligner, save.
* **Queues:** `.userInitiated` global queue for load (`SeqAlignMacApp.swift:696`), search
  (`:295-310`, snapshot taken *inside* the background task so the main thread does no copy),
  translate (`TranslationOptionsView.swift:140-148`), export/save (`:920-953`), logo and NJ and
  window chart (`AnalysisSheets.swift:75-86, 213-232, 311-323`); the canvas has its dedicated
  serial stats queue; `.utility` for the quality panel (`SheetViews.swift:158-192`);
  `DispatchQueue.main` for every UI write.
* **Caps and subsampling:** as tabulated in §8.17.
* **Cooperative cancellation:** `LoadProgressModel.cancelLoading` (`:59-69`, checked at
  `:712-719, 736-742`) and `findAll(shouldStop:)` (`SearchEngine.swift:156-166`).
* **Locking discipline:** one `NSRecursiveLock` per `Alignment`; row-major scans take it **once**
  (`ColumnStats.swift:110-126`); `lockedSequences` copies inside the closure to honour the
  no-reference-escape contract (`AlignmentCore.swift:204-211`,
  `TranslationTables.swift:306-314`, `PhyloBuilder.swift:511-522`).
* **Laziness:** length cached on `revision`; incremental stats under the 64-column budget; regex
  search decodes each row once (`SearchEngine.swift:47-49`); KMP state persists across `next()`.

No throughput figure is claimed anywhere in this document. There is no benchmark, no performance
regression budget, and no large-file test harness in the repository (fixtures are inline
precisely to avoid external samples), so statements about capacity in sequences or run time are
not verifiable from this codebase (§15.12).

---

## 10. Localisation architecture

### 10.1 Mechanism

`Sources/Localization.swift` (2,002 lines) contains **no `.strings`, no `.xcstrings`, no
`LocalizedStringKey`** — the entire UI vocabulary lives in one Swift table and is switched at
runtime.

| Component | Detail | Line |
|---|---|---|
| `AppLanguage` | `enum AppLanguage: String, CaseIterable { case zh, en }` with `displayName` ("中文"/"English") and `systemImage` (`character.bubble`/`globe`) | `:12-29` |
| `LanguageManager` | singleton `ObservableObject`; `static let key = "SeqAlignMac.language"`; `@Published var language` whose `didSet` writes `UserDefaults` **and** posts `.languageChanged`; first launch defaults from `Locale.preferredLanguages.first?.hasPrefix("zh")`; `toggle()` and `set(_:)` | `:33-62` |
| `L.s` | `enum L { static var s: AppStrings { LanguageManager.shared.language == .zh ? .zh : .en } }`; every view and menu reads `L.s.xxx` at body-evaluation time | `:66-70` |
| `AppStrings` | a **`final class` with 433 stored fields** (`:75-1925`), two `static let` instances `zh` (`:1455-1676`) and `en` (`:1678-1900`), an explicit memberwise `init` (`:78-512`), grouped by `// MARK:` sections (`:948-1454`) | `:72-74` |
| Format names | `formatName(_ f: AlignmentFormat, zh: Bool)` plus 8 static strings; format names are language-invariant except `Unknown`/`未知` | `:1902-1924` |
| Computed strings | ~18 properties in an extension (`:1931-2002`) that branch on `private var isZh` instead of being fields, to avoid growing the 433-argument initialiser: `translationNeedsNucleotide`, `translationFrameshift`, `translationMixedTrack`, `translationRagged`, `translationLengthNotMultipleOfThree`, `logoTruncated`, `gffFeatureNotInAlignment`, `treeModelUncorrected`, `treeClampedBranches`, `unalignedWarning`, `statsUnalignedBanner`, `alignerResultMismatch`, `alignerMismatchCount/Missing/Extra/Ragged`, `treeSampledNote`, `settingsAlignerTimeout`, `exportConsensusLabel` | `:1931-2002` |
| Notification | `Notification.Name.languageChanged` | `:1928` |

`AppStrings` is a class, not a struct, for a measured reason recorded at `:72-74`: the struct
version copied roughly 400 fields on every `L.s` access — on the order of 16,000
retain/release operations per body evaluation. Value semantics were dropped and an explicit
memberwise initialiser written because classes do not synthesise one.

### 10.2 How the UI refreshes on a language switch

Menus: `SeqAlignCommands` observes `LanguageManager` and reads `lang.language` inside `body`
(`SeqAlignMacApp.swift:426, 431`). Window titles: `.onReceive(.languageChanged)`
(`TabbedWindow.swift:171`). Views: each root view holds
`@ObservedObject var langManager = LanguageManager.shared` (`ContentView.swift:19`,
`StatsPanel.swift:106`, `SharedUIComponents.swift:625`). The command palette rebuilds its cache
keyed on the language (`CommandPaletteView.swift:34, 73`). Entry points: View ▸ Language ▸
中文/English (`SeqAlignMacApp.swift:534-537`), the sidebar `LanguageSwitchButton`
(`LeftSidebarView.swift:192-200`), and `LanguageManager.toggle()`.

Note that language is **not** a preferences control; the only entry points are View ▸ Language and
the sidebar button (§10.2). `Info.plist` carries no `CFBundleLocalizations`: the bilingual UI is
runtime-switched, not `.lproj`-based.

### 10.3 Terminology discipline

The EN↔ZH glossary below is normative for this document set — it is the terminology table of
record for the docs set. The load-bearing pairs:
colour scheme/配色方案 · conservation (threshold)/
保守度（阈值） · column identity/列一致度 · **pooled identity (site-weighted)/池化一致度（位点加权）**
· consensus sequence/共识序列 · consensus mode/共识模式 (majority rule / IUPAC degenerate / strict
= 多数规则 / IUPAC 简并 / 严格共识) · gap column / 空位列 (the stats panel's own label 含空位列数 is misleading, §8.3) · all-gap columns/全空位列 · high-gap columns (>50 %)/空位富集列 · gap trimming/
空位精简 · undetermined/未判定 versus degenerate/简并 (kept distinct) · variable /
parsimony-informative / singleton site/变异位点 · 简约信息位点 · 单态位点 · reading frame/阅读框 ·
codon track/密码子轨道 · reverse complement/反向互补 · difference mode/差异模式 · focus dim/
聚焦变暗 · melting temperature/熔解温度 (Tm as-is) · neighbour-joining tree/邻接法系统发育树 ·
the *short* compound neighbour-joining/NJ 树 is fine when quoting a UI label, but prose uses the
glossary form · nearest-neighbour (Tm, salt correction)/最近邻法 — never 近邻法, which collides
visually with 邻接法 · sliding window/滑动窗口 · sequence logo/序列 Logo · annotation browser/注释浏览器 · command palette/
命令面板 · frozen name column/名称列冻结 · density-adaptive glyphs/密度自适应 · pill (the scope toggle)/胶囊 · external aligner/
外部比对器 · consensus row/共识行 (the display row; 共识序列 is the *sequence*, a different object) ·
sandbox/沙箱 · allow-list/允许清单 versus whitelist/白名单 — EN deliberately keeps these two
distinct (an allow-list gates `Package.swift: sources` and the open-panel extensions; a whitelist
is the parser's residue-character set), so ZH must mirror whichever EN word it faces.

Two gaps need coining rather than translating: **"charset"** (NEXUS `SETS`) has no established
Chinese term — the UI shows the literal English "Charset" — and **window chart** is labelled with
the bare 窗口, which collides with "window"; prefer 滑动窗口图 / *sliding-window chart*.

### 10.4 Unlocalised surfaces (honest list)

The following are **not** driven by `L.s` and will therefore show one language regardless of the
UI setting. This is the live i18n debt; CI greps for it but does not block on it (§12.7).

1. **Parser and domain error text.** All `CoreError.format` messages are Chinese literals
   (`AlignmentParsers.swift` throughout), and `CoreError`'s `errorDescription` prefixes are
   hard-coded Chinese (`AlignmentCore.swift:387-410`).
2. **The CLI as a whole** — Chinese `已写入`, `已导出`, `无法读取文件`, `错误: …` mixed with English
   `Error: …`, `Warning: …`, `Converted to … → …` (`CLIRunner.swift:30, 51, 110, 171, 234`).
3. **Canvas-local strings, Chinese-only:** `请先在画布中选择区域` (`:323`),
   `已复制光标所在行（N 列）` / `已复制 R 行 × C 列` (`:350, 352`), the cursor announcement
   `行 R 列 C，残基 X，一致度 N%` / `空位` (`:380-388`), `共识序列` (`:784`), the column-peek tooltip
   `列 N · 共识 X · 一致度 Y%` (`:744`), and accessibility label/help/custom action (`:300-303`).
4. **Colour legend notes** in `ColorSchemeLegend.entries` — essentially all Chinese except the
   ClustalX index-7 entry — so the Legend popover shows Chinese under an English UI
   (`ColorSchemes.swift:212-269`).
5. **The Quick Guide steps** — 8 ZH + 8 EN inline (`SheetViews.swift:84-111`) — and three other
   inline branches (`ContentView+Actions.swift:247, 258, 368` for copy and add-sequence toasts).
6. **`ExportManager` image-export guard errors**, Chinese-only (`:324-460`).
7. **The 17 genetic-code picker entries** are literal English with the NCBI number in parentheses
   (`TranslationOptionsView.swift`).
8. **Filename suffixes** `(aligned)`, `(translation)`, `_AA`; the status-bar **"Charset"** label
   (`CenterPanelView.swift:384`); the export-preview format segment labels.
9. **20 dead `AppStrings` keys** never read via `L.s` (`ok`, `search`, `searchFind`,
   `searchRegexOn`, `searchRegexOff`, `toolbarAlign`, `toolbarExport`, `toolbarNewTab`,
   `menuExport`, `menuHelp`, `menuZoom`, `ctxSelectCodonPos`, `ctxCodonPos1`, `ctxCodonPos2`,
   `ctxCodonPos3`, `settingsCodonTriplet`, `statsSamplingHint`, `translateSixFrameOverview`,
   `translateHighlightStop`, `translateHighlightStart`). The `ctx*` group shows a planned "Select
   Codon Position" submenu that never shipped; the `translate*` trio plus `settingsCodonTriplet`
   are the residue of an unshipped six-frame overview. **None may be documented as a feature.**

---

## 11. Persistence

Everything SeqAlignMac persists goes through `UserDefaults` on the device; there is no keychain
item, no application-support file, no database, and no network sync (§12.7). The privacy
manifest declares exactly one reason API, `CA92.1` (`Resources/PrivacyInfo.xcprivacy:13-23`).

### 11.1 Persisted keys, with defaults and effects

| Key | Written by | Type / default | Effect | Reference |
|---|---|---|---|---|
| `SeqAlignMac.language` | `LanguageManager.didSet` | `String` `"zh"`/`"en"`; initial value from `Locale.preferredLanguages` | all UI text | `Localization.swift:33-62` |
| `SeqAlignMac.appearance` | `AppearanceStore` | light / dark / system | app-wide `NSAppearance`, and which palette variant renders | `SeqAlignMacApp.swift:1337-1377` |
| `SeqAlignMac.currentScheme` | `ColorSchemeManager` / `Workspace` | `ColorScheme` `Int32` raw; **absent ⇒ `.minimal`** (raw 4) | canvas and export palette | `:123-132`; the special case exists because raw value 0 is `defaultNucleotide` |
| `SeqAlignMac.fontSize` | `Workspace` | `CGFloat`, default **13**, clamped 8…28 | glyph size; zoom percentage is `fontSize / 13` | `:105, 1117-1125` |
| `SeqAlignMac.nameColWidth` | canvas `mouseUp` | `CGFloat`, default **150**, clamped 80…2000 | frozen name-column width; also the CLI `export` default | `AlignmentCanvasView.swift:118-190`; `CLIRunner.swift:163-164` |
| `SeqAlignMac.highContrast` | settings / workspace | `Bool`, default `false` | gap diagonals and contrast emphasis | `SettingsView.swift:96-101` |
| `SeqAlignMac.focusDimMode` | settings / workspace | `Bool`, default `false` | dims non-selected cells | `SettingsView.swift:96-101` |
| `SeqAlignMac.consensusMode` | settings | `ConsensusMode` raw, default `.majority` | consensus glyph in the row, logo, stats, export | `ColumnStats.swift:54-58`; `SettingsView.swift:24-25, 134-138` |
| `SeqAlignMac.externalAlignerTimeout` | settings | `Int` seconds, default **300** (and re-defaulted when stored ≤ 0); UI stepper 30…3600 step 30 | subprocess kill deadline, floored at `max(10, n)`; SIGKILL +5 s later | `SettingsView.swift:16-22, 150-162`; `ExternalAlignerView.swift:239-258` |
| `SeqAlignMac.statsPanelWidth` | `ContentView.onChange` | `CGFloat`, default **264**, clamped 220…460 | right panel width | `PanelResizer.swift:23-24, 36-37` |
| `SeqAlignMac.leftSidebarWidth` | `ContentView.onChange` | `CGFloat`, default **180**, clamped 150…320 | sidebar width | `ContentView.swift:55-101` |
| `SeqAlignMac.recentFiles` | `RecentFilesManager` | `[String]`, **max 10**, symlink-resolved; missing files shown disabled | File ▸ Open Recent | `SeqAlignMacApp.swift:781` |
| `SeqAlignMac.firstRunHintShown` | `showFirstRunHintIfNeeded()` | `Bool` | one-shot first-run toast | `:1449-1458` |
| `SeqAlignMac.primerNa_mM` | `@AppStorage` | `Double`, default **50** (mM) | `[Na+]` in `TmOptions` (`/1000`) | `PrimerCalculatorView.swift:48-55` |
| `SeqAlignMac.primerMg_mM` | `@AppStorage` | `Double`, default **0** (mM) | `[Mg2+]` in `TmOptions` | as above |
| `SeqAlignMac.primerOligo_uM` | `@AppStorage` | `Double`, default **0.25** (µM) | oligo concentration (`/1e6`) | as above |

`@AppStorage` is used in exactly three places, all in the primer sheet; there is **no
`@SceneStorage` anywhere** in the target.

### 11.2 State that is deliberately not persisted

| State | Behaviour | Why it matters to a reader |
|---|---|---|
| Consensus row visibility (`showConsensus`) | resets each launch | the exported image always shows the consensus row regardless (§15.5) |
| Difference mode and reference row | reset each launch | a reproducible "diff view" cannot be saved |
| **ClustalX conservation threshold** | the slider writes `ColorComputer.clustalXThreshold` but it is **not** restored on relaunch — the only setting that does not stick | `SettingsView.swift:114-129` vs `ColorLogic.swift:52-64`; §15.4 |
| Window and tab contents | in-memory only (`WindowRegistry`); quitting closes everything except what "Open Recent" can recover | no session restore |
| Search query and hits | per-workspace, transient | — |
| Undo/redo history | per tab, discarded on close | 50-command / 256 MiB budget applies within a session only |

---

## 12. Build system and quality gates

### 12.1 Two compile paths, both exercised by CI

| Path | Command | What it builds | Purpose |
|---|---|---|---|
| SwiftPM | `swift build`, `swift build -c release`, `swift test` | the `SeqAlignCore` **library** only (10 files) + `SeqAlignCoreTests` | the quality guardrail: a pure-logic compile and test channel |
| `build.sh` | `bash build.sh [--open] [--skip-tests]` | all 36 files under `Sources/` into `SeqAlignMac.app` and `SeqAlignMac.app.zip` | the only way to obtain the shipped product |

`Package.swift:1` declares `swift-tools-version:6.0`, `:19` `.macOS(.v14)`, `:20-22` one product
`.library(name: "SeqAlignCore")`, target language mode pinned to **Swift 5** for both target and
tests (`:42, 48`) — so Swift 6 data-race checking is deliberately *not* applied to the core.
The toolchain floor implied by the repository is the **Swift 6 toolchain** (tools-version 6.0 in
`Package.swift:1`, CI selecting the newest Xcode on `macos-15`, `ci.yml:23-27`); documents that
say "Xcode 15+" contradict both the manifest and the CI comment and should not be repeated.

### 12.2 The `sources:` allow-list, and why an allow-list rather than an exclude list

`Package.swift:30-41` compiles **exactly ten** files into `SeqAlignCore`:
`AlignmentCore`, `ResidueAlphabet`, `AlignmentParsers`, `AlignmentWriters`, `TranslationTables`,
`PrimerCalculator`, `ColumnStats`, `SearchEngine`, `UndoRedoManager`, `ColorLogic`. The rationale
recorded in the Chinese comments at `Package.swift:8-13` and `:27-29` translates to three points:

1. **Necessity.** `ContentView`, `AlignmentCanvasView`, `SeqAlignMacApp`, `ColorSchemes`,
   `ExportManager` and the rest of the shell depend on AppKit/SwiftUI and cannot be compiled
   inside a pure-logic test target. The domain layer — parser, writer, translation, primer,
   column statistics, search, undo/redo, core model, residue alphabet — is deliberately kept
   UI-free; this list *is* the concrete realisation of "domain services decoupled from rendering".
2. **Coexistence.** The app binary is still built separately by `build.sh` with plain `swiftc`;
   the SwiftPM manifest does not compete with it, and adds no executable product.
3. **Why `sources` and not `exclude`.** With `exclude`, forgetting to list a newly added pure-
   logic file leaves it compiled but **untested**, which produces a false green. With `sources`
   only, a non-listed file simply is not compiled by the package at all, so the omission is
   visible the moment someone tries to use it from a test.

The consequence to remember: **all 26 other `Sources/` files, `CLIRunner.swift` included, are
invisible to SwiftPM** and are compiled only by `build.sh:66-67`.

### 12.3 `build.sh` stage table

`#!/bin/bash` with `set -e` **and** `set -o pipefail` — `:3-5` explains that `pipefail` exists so
`swift test | tail` cannot hide a failure. It `cd`s to its own directory (`:12-18`), so relative
paths are safe. Unknown arguments are silently ignored by the `case` loop (`:19-24`); there is no
`--help`.

| # | Lines | Stage | Notes / failure class |
|---|---|---|---|
| 1 | `:28-31` | Move the old bundle aside | `mv SeqAlignMac.app /tmp/SeqAlignMac_old_$$` rather than deleting; `\|\| true`, never fatal |
| 2 | `:33-36` | Create `Contents/MacOS`, `Contents/Resources` | hard failure if it cannot |
| 3 | `:38-40` | Copy `Info.plist` | unguarded `cp` → missing `Info.plist` aborts |
| 3.5 | `:42-61` | **Test gate** | runs `swift test 2>&1 \| tail -20` **only if** `swift` exists (`:49`) and `echo "import XCTest" \| swiftc -typecheck -` succeeds (`:50`); failure → `❌ 单元测试失败` + `exit 1`; XCTest absent (Command Line Tools only) → warning `⚠️ 本机缺少 XCTest…` and the build continues. `--skip-tests` prints a skip notice. **Locally the gate is best-effort; CI makes it mandatory.** |
| 4 | `:63-80` | Compile | one `swiftc` invocation over `find Sources -name "*.swift" \| sort` with `-target arm64-apple-macosx14.0`, `-sdk $(xcrun --sdk macosx --show-sdk-path)`, `-parse-as-library` (required by `@main`), `-O`, `-framework Cocoa`, `-framework SwiftUI`, `-o Contents/MacOS/SeqAlignMac`. **No exclusion list.** Hard failure on any compile error |
| 5 | `:82-99` | Icon | moves any stale `icon.iconset` to `/tmp`, runs `swift gen_icon.swift`, then `iconutil -c icns icon.iconset -o Contents/Resources/AppIcon.icns` if `icon_512x512.png` exists; otherwise **warning only** and the build continues without an icon. (`gen_icon.swift:77-88` emits 10 PNGs; the comment at `:85-86` claiming 56 is stale.) |
| 6 | `:101-103` | Copy `logo.svg` into Resources | unguarded `cp` → missing file aborts |
| 6.5 | `:105-109` | Copy `PrivacyInfo.xcprivacy` into the bundle | required by App Store submission |
| 7 | `:111-112` | `chmod +x` the executable | |
| 7.5 | `:114-140` | Code signing | see §12.5 |
| 8 | `:142-149` | Distribution zip | old zip moved to `/tmp`, then `ditto -c -k --keepParent SeqAlignMac.app SeqAlignMac.app.zip` |
| 8.5 | `:151-158` | Notarisation | **only when both `DEVELOPER_ID` and `NOTARY_PROFILE` are set**: `xcrun notarytool submit <zip> --keychain-profile <profile> --wait` then `xcrun stapler staple SeqAlignMac.app`; each failure is `\|\| echo` — **non-fatal** |
| 9 | `:160-166` | Summary | bundle path, `du -sh` of bundle and zip |
| 10 | `:168-172` | Optional launch | `open SeqAlignMac.app` when `--open` was passed |

Outputs: `SeqAlignMac.app/`, `SeqAlignMac.app.zip`, transient `icon.iconset/`, and
`/tmp/SeqAlignMac_{old,iconset,zip}_$$`. Hard failures: `swift test` (when XCTest is present),
`swiftc`, `swift gen_icon.swift`, `iconutil`, missing `Info.plist`/`logo.svg`/`Sources`,
`codesign --verify`, `ditto`. Warn-and-continue: icon generation, ad-hoc signing, notarytool and
stapler, absent XCTest, absent old bundle/zip.

### 12.4 The CLI is not SwiftPM-buildable

`Package.swift:20-22` declares **no executable product**, and `CLIRunner.swift` is not in the
`sources` allow-list. `swift build` therefore produces a library only; `swift run` has nothing to
run. The CLI exists solely as a mode of the `SeqAlignMac` Mach-O executable built by `build.sh`
(§13). Any instruction such as "build the CLI with SwiftPM" is false.

### 12.5 Signing, sandboxing, notarisation: opt-ins, not defaults

| Knob | Effect when set | Lines |
|---|---|---|
| `DEVELOPER_ID` | `codesign --force --options runtime --timestamp ${ENT_ARG} --sign "$DEVELOPER_ID" <bundle>` (hardened runtime + secure timestamp), followed by `codesign --verify --verbose`, whose failure **is** fatal | `:128-134` |
| `SEQALIGN_SANDBOX` | appends `--entitlements SeqAlignMac.entitlements` to the codesign arguments and prints a note that sandboxing disables the external aligners; warns if `DEVELOPER_ID` is empty, since the combination is pointless for a MAS submission | `:117-126` |
| `NOTARY_PROFILE` | enables the `notarytool submit` + `stapler staple` path, but only in combination with `DEVELOPER_ID` | `:151-158` |
| *(none set)* | ad-hoc fallback `codesign --force --deep --sign - <bundle>`; failure tolerated with a warning — the comment explains that unsigned arm64 binaries are killed by Gatekeeper and lose network quarantine allowances | `:135-140` |

`SeqAlignMac.entitlements` grants `app-sandbox`,
`files.user-selected.read-write`, and `security-scoped-bookmarks.app-sandbox` only, with a comment
(`:15`) recording that no network, microphone, or camera entitlement is requested. Because the
sandbox forbids `exec` of user-supplied binaries, the external-aligner feature is **disabled by
the entitlement, not by a runtime switch**: nothing in `Sources/` conditionally hides the UI
(§15.8). Builds are arm64-only (`-target arm64-apple-macosx14.0`, no `x86_64` slice, no `-arch`
pair), so the shipped zip is **not** a universal binary and Intel Macs would require
recompiling — a limitation no other document states.

### 12.6 Tests

`swift test` runs **110 test methods in 4 `XCTestCase` classes** across 3 files:

| File | Class | Methods | Defined at |
|---|---|---|---|
| `SeqAlignCoreTests.swift` | `SeqAlignCoreTests` | 30 | `:19` |
| `SeqAlignCoreTests.swift` | `CoreEnhancementTests` | 11 | `:522` |
| `FormatRoundTripTests.swift` | `FormatRoundTripTests` | 41 | `:12` |
| `EdgeCaseTests.swift` | `EdgeCaseTests` | 28 | `:18` |
| **Total** | 4 classes | **110** | |

Grouped by area (the groups overlap across files; **the per-class table above is the only
authoritative count**):

* **Parser round-trips** — 7 named round-trips sharing an `assertRoundtrip` helper (3 sequences ×
  60 columns, `SeqAlignCoreTests.swift:147-197`), Stockholm `#=GF ID` survival (`:525-538`), PHYLIP
  strict-10/sequential with exactly-10-character accession names
  (`FormatRoundTripTests.swift:32-54`), dot-gap normalisation in FASTA/PHYLIP/CLUSTAL/Stockholm
  (`:64-79`), duplicate CLUSTAL names kept separate (`:354-366`), multi-block CLUSTAL line
  preserved (`:370-381`), sequential NEXUS wrapped lines staying on their taxon (`:280-299`),
  NEXUS interleaved aggregation (`EdgeCaseTests.swift:63-82`), PHYLIP wrapped sequential and
  strict-10 (`:22-59`), headerless CLUSTAL (`:275-283`), and byte-exact round-trips over 4 PHYLIP
  variants + NEXUS + CLUSTAL + Stockholm + MSF (`FormatRoundTripTests.swift:565-595`).
* **Datatype detection**, including NEXUS `DATATYPE=` declaration variants and `.`/`*`/digit
  tolerance (`SeqAlignCoreTests.swift:201-214`; `FormatRoundTripTests.swift:303-321`).
* **Primer thermodynamics** — an OligoCalc-derived reference table of 10 fixtures with NN/Wallace
  Tm within 1 °C and GC within 0.02, hetero-dimer ΔG within 3.0 and sign-matched
  (`SeqAlignCoreTests.swift:245-281`), degeneracy > 4096 throwing (`:277-281`), salt dependence
  (`:689-696`), Biopython `Tm_NN` agreement with Mg/dNTP chelation
  (`FormatRoundTripTests.swift:517-537`), degeneracy saturation and negative-salt rejection
  (`EdgeCaseTests.swift:130-151`).
* **Translation** — frame 0, single codon, negative frame ≡ reverse-complement-then-translate
  (`SeqAlignCoreTests.swift:285-311`), 17-table spot checks against `gc.prt` (`:634-686`), name
  preservation (`EdgeCaseTests.swift:344-348`), mixed track not labelled protein, protein input
  refused, frameshift → `X` (`FormatRoundTripTests.swift:177-208`).
* **Undo/redo** — the seven scenarios (`SeqAlignCoreTests.swift:323-411`), clamped-position undo,
  stack memory caps, empty transaction keeping the redo stack, `dirtyColumns == nil` for insert-gap
  (`EdgeCaseTests.swift:224-261, 352-355`), and charset remapping on column removal with undo
  restoring partitions (`FormatRoundTripTests.swift:385-402`).
* **Search** — IUPAC exact/degenerate (`SeqAlignCoreTests.swift:415-428`), regex literal
  uppercasing not flipping `\d`→`\D`, regex on digits, `validateRegex` ≡ engine, KMP overlapping
  hits (`EdgeCaseTests.swift:86-126`), literal-`N` matching and T↔U swapping
  (`FormatRoundTripTests.swift:425-443`).
* **Statistics** — quality/column stats single source (`SeqAlignCoreTests.swift:432-449`), FASTQ
  Q20/Q30/min Phred and the Phred+33 versus +64 decision (`:541-551`;
  `FormatRoundTripTests.swift:541-549`), protein versus nucleotide site-counting rules
  (`:108-140`), ambiguity exclusion (`EdgeCaseTests.swift:200-220`), **pooled ≠ exact mean
  pairwise** (`FormatRoundTripTests.swift:248-261`), all-`N`/all-`X` columns not conserved
  (`:265-276`), consensus modes (`EdgeCaseTests.swift:322-340`), GC single source
  (`:455-461`), mutation-type gap-vs-gap (`:206-210`).
* **Phylogenetics and logo** — NJ 2- and 3-taxon Newick (`SeqAlignCoreTests.swift:594-612`),
  sampling disclosure, 2-taxon branch length, tip-name uniquification
  (`FormatRoundTripTests.swift:478-513`), sliding-window identity (`:615-622`), p-distance gap
  handling (`:88-104`), logo bits (`:582-591`), amino-acid coverage
  (`:142-152`), truncation reporting (`:465-474`).
* **Colour logic** — default-nucleotide, ClustalX, Okabe-Ito indices and the viewport single
  source (`SeqAlignCoreTests.swift:466-488, 625-631`), protein schemes falling back on nucleotide
  tracks (`FormatRoundTripTests.swift:325-337`), CLUSTAL consensus not faking conservatism for A/T
  (`:339-350`).
* **NEXUS charsets** — three `codons_*` charsets with step `\3` and 20 ranges
  (`SeqAlignCoreTests.swift:453-462`), step specification preserved verbatim when columns are
  untouched (`FormatRoundTripTests.swift:404-421`).
* **I/O, compression, writers** — gzip decompress (`SeqAlignCoreTests.swift:554-560`), GFF3
  (`:699-709`), FASTQ quality round-trip and illegal-residue rejection
  (`EdgeCaseTests.swift:265-302`), gzip compress→decompress byte equality (`:306-312`),
  quality/residue correspondence after padding, single-member gzip whose payload contains the
  `1F 8B 08` magic still decoding while true concatenations stay rejected
  (`FormatRoundTripTests.swift:599-613`), ragged-writer safety, MSF GCG checksum, NEXUS quoting,
  PHYLIP strict-10 uniqueness after truncation (`EdgeCaseTests.swift:155-196`), declared NCHAR
  versus written row length (`:212-231`), snapshot independence — the concurrency basis
  (`SeqAlignCoreTests.swift:507-516`), reverse-complement IUPAC completeness, and unaligned-FASTA
  provenance flagging (`:235-244`).

**What the suite does not cover** — do not claim more than this:

* **`CLIRunner.swift` has zero tests.** Nothing exercises argument parsing, the four exit codes,
  stdout-versus-stderr behaviour, the CSV field set, `-o`/`--out`/`--output` semantics,
  `--scheme`/`--fontsize` handling, or `--start/--end` slicing (`subAlignment`'s `crop` path is
  never exercised; only `shift` is, through `RemoveColumnsCommand`). CI never runs the binary in
  `cli` mode.
* **No AppKit/SwiftUI coverage:** canvas rendering, `ExportManager` PNG/PDF/SVG bytes,
  `ColorSchemes` palette values, `AlignmentRenderer`, external-aligner `Process` plumbing, and
  UI-level undo behaviour. `CONTRIBUTING.md:43` records that AppKit-dependent code has no SwiftPM
  test channel and needs a discussed justification first.
* **Localisation key symmetry is not testable here** — `Localization.swift` imports
  SwiftUI/AppKit and is intentionally outside the target (`EdgeCaseTests.swift:357-359`); the
  deferred check belongs to an app target that does not exist in SwiftPM.
* No large-file harness (fixtures are inline precisely to avoid external samples,
  `SeqAlignCoreTests.swift:21`), **no coverage measurement, no performance/regression budget, no
  parser fuzzing** (only hand-written malformed cases), and nothing tested on Linux or Intel.
* Some assertions are deliberately weak: self-dimer ΔG is a contract check only (`:270-275`),
  degeneracy for degenerate primers is compared against the *upper* bound only (`:236`), and
  `FormatRoundTripTests.swift:56-60` — `testPhylipAllGapResultIsRejectedNotSilent` — actually
  asserts `XCTAssertNoThrow`, i.e. its name contradicts its body, so it must not be cited as
  evidence that malformed PHYLIP is rejected.

### 12.7 Continuous integration

`.github/workflows/ci.yml` is the only workflow. Triggers: `push` to `main` and all
`pull_request` (`:3-6`); concurrency per workflow+ref with `cancel-in-progress: true` (`:9-11`,
comment: macOS minutes are scarce). There is **no** `workflow_dispatch`, no release or tag
trigger, no `secrets:`, no workflow `env:` block, and **no cache step** — every run re-resolves
and rebuilds from scratch.

| Job | Runner | Steps |
|---|---|---|
| `test` — "Tests & build (macOS)", `timeout-minutes: 45` (`:14-17`) | `macos-15` | `actions/checkout@v5` (`:19`); "Select latest Xcode (Swift 6 toolchain)" — lists `/Applications/Xcode*.app`, `sudo xcode-select -s` the highest `sort -V`, prints `xcodebuild -version` and `swift --version` (`:20-27`; the Swift version is therefore whatever the newest Xcode on `macos-15` ships, not pinned); `swift test` (`:28-29`, full unpiped output — the only place all 110 tests are mandatory); `swift build -c release` (`:30-33`, a separate release-config compile that exposes optimiser issues `swiftc -O` alone would not); `./build.sh --skip-tests` (`:34-35`, full bundle, **ad-hoc signed**, zip produced); `actions/upload-artifact@v4` name `SeqAlignMac-app`, path `SeqAlignMac.app.zip`, `retention-days: 14` (`:36-41`) |
| `lint` — "Repo lint", `timeout-minutes: 5` (`:43-46`) | `ubuntu-latest` | `actions/checkout@v5` (`:48`); "Ensure build artifacts are not committed" — fails if `git ls-files` matches `^SeqAlignMac\.app(\.zip)?$` or `…/SeqAlignMac.app/` (`:49-54`); "i18n hardcode audit (**non-blocking**)" with `continue-on-error: true` — `grep -rP` counts CJK string literals in `Sources/**/*.swift` excluding `Localization.swift` and comment lines, and prints the count (`:55-62`) |

Three corrections this table encodes: the artefact guard is real, but the **CJK audit does not
gate anything** — its own comment admits hardcoded Chinese remains in view and parser layers, so
any statement that CI enforces the localisation rule overstates it; CI signs ad-hoc only, so the
uploaded artefact is **not** a distributable build and CI does not gate on notarisation; and
`Package.swift:29` asserts "…且 CI 可对清单做 diff检查" ("CI can diff-check the manifest") while
**no such CI step exists** (§15.3). Required-status configuration lives outside the repository —
there is no branch-protection file and no `.github/settings.yml`.

### 12.8 Security and privacy posture, as implemented

Attack surface, per `SECURITY.md:24-33` and the code: malformed alignment files must error rather
than crash (§7.11); the external-aligner feature executes a user-chosen binary path in
non-sandboxed builds (§6.2.19); the undo stack is capped at 50 entries and 256 MiB
(`UndoRedoManager.swift:361-365`, test `EdgeCaseTests.swift:236`). `Info.plist:33-35` sets
`ITSAppUsesNonExemptEncryption = false`; the privacy manifest declares `NSPrivacyTracking =
false`, empty tracking domains, empty collected data types, and the single `UserDefaults` API
reason `CA92.1`; nothing in the app performs network I/O. Response-time and advisory-handling
commitments in `SECURITY.md:15, 20` are **policy statements, not code facts**, and no contact
address or key fingerprint exists anywhere in the repository (§15.13).

---

## 13. Command-line interface as a documented contract

The CLI is a supported interface, not a debug back door: its exit codes and CSV columns are part
of the reproducibility story. **Task-oriented recipes belong in
[`USAGE.md`](USAGE.md) §14 "Command-line usage"; this section fixes the contract.**

Invocation — the same Mach-O binary as the GUI, dispatched before any window is created
(`SeqAlignMacApp.swift:19-25`, `CLIRunner.swift:21-25`):

```
<Path>/SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli <subcommand> <file> [options]
```

`run()` requires at least two remaining tokens (subcommand + input path) or it prints usage and
exits 64. The common pipeline is read → detect → **parse** → dispatch → `exit(0)`; parsing happens
*before* the subcommand switch, so a bogus subcommand on a broken file reports a parse error
rather than a usage error (`:29-56`).

### 13.1 Subcommands

| Subcommand | Syntax | Notes |
|---|---|---|
| `stats` | `cli stats <alignment-file> [--out results.csv]` | CSV to stdout when `--out` is absent; with `--out`, stdout receives only `已写入 <path>`. **`stats` reads `--out` only — there is no `-o` alias here.** `--start`/`--end` are ignored |
| `export` | `cli export <alignment-file> [--format png\|pdf\|svg] [-o output] [--fontsize N] [--dark] [--scheme minimal\|clustalx\|zappo\|seaview\|default\|titv\|okabeito]` | `--format` optional, default `png`; no `--start`/`--end`; selection/row/column ranges are unreachable from the CLI |
| `convert` | `cli convert <alignment-file> --format nexus\|phylip\|clustal\|msf\|stockholm\|fasta\|fastq [-o output-file] [--start N] [--end M]` | `--format` **required**; aliases `nexus\|nex`, `phylip\|phy`, `clustal\|aln`, `msf`, `stockholm\|sto`, `fasta\|fa\|fas`, `fastq\|fq`; `--out` is **not** recognised here |

There is **no `--help`, no `--version`, no `-v`/`-q`/`--verbose`**; `cli --help` yields the usage
block and exit 64. The usage text is printed with `print`, i.e. to **stdout**, even on usage
errors (`:58-66`). `MANUAL_EN.md:333` omits `fastq` from the `convert` list and `:330` drops
`--scheme` from `export`; the in-binary usage text at `:63` is authoritative.

### 13.2 Option semantics and silent fallbacks

| Option | Contract | Fallback behaviour |
|---|---|---|
| `--format` (export) | case-insensitive `png\|pdf\|svg` | unknown → stderr `Error: unknown --format '<x>' (expected png\|pdf\|svg)` + **exit 64** (`:150-153`) |
| `--format` (convert) | case-insensitive, 7 aliases above; `fastq` requires at least one sequence with quality values | missing or unknown → exit 64 (`:177-180, 228`); FASTQ without quality → `CoreError.unsupported` → exit 70 (`:221-223`) |
| `--scheme` (export) | `clustalx`, `zappo`, `seaview`, `default`, `titv`, `okabeito`, `minimal`; absent ⇒ `minimal` | **any other value silently becomes `minimal`, with no warning** (`:269-279`) — a known deviation from the strictness of `--format`, and note it differs from the GUI/`ExportOptions` default of `.defaultNucleotide` |
| `--fontsize` (export) | accepted only if parseable as `Double` **and** `6 ≤ N ≤ 40` | out of range → stderr `Warning: invalid --fontsize, using default 13`, non-fatal (`:157-161`) |
| `--dark` | presence-only flag (`params.contains("--dark")`) | — |
| `--start` / `--end` | **1-based closed interval**; defaults `1` and `alignment.length`; slicing runs only when the window is narrower than the whole alignment (`:186`) | non-numeric values fail `Int()` and are **silently ignored** (`:183-184`); out-of-range bounds are **clamped** (`:238-240`); `start > end` → `CoreError.invalidArg` → exit 70 (`:241-243`) |
| `-o` / `--output` / `--out` | `-o` and `--output` for `export`/`convert`; `--out` for `stats` | mismatched spellings are treated as absent, so `convert … --out x.nexus` silently writes a default-named file into the working directory; `--output` appears in code but in **no** usage string |
| option parser | only `--key value` / `-o value`, positional; a value starting with `-` is rejected; for repeated options the first occurrence wins | an option whose value looks like a flag is treated as absent → default used |
| name column | read from `UserDefaults["SeqAlignMac.nameColWidth"]`, else 150 | a headless run therefore inherits GUI preferences — it is **not** fully hermetic (`:163-164`) |

Slicing semantics of `subAlignment` (`:238-267`): `s = max(1,start) − 1`, `e = min(length,end)`;
rows shorter than the window are right-padded with `'-'` to the uniform width, matching the
writer's `paddedSlice`; NEXUS `CHARSET` partitions are re-projected with
`CharsetRemapper.crop(charsets, startCol: s, endCol: e-1)`; `provenance` is copied onto the sliced
alignment and `metadata`/`datatype` pass through. Output naming: `convert` defaults to
`<input-basename>.<canonical ext>` and prints `Converted to <fmt> → <path>`; `export` defaults to
`<input-basename>_alignment.<fmt>` and prints `已导出 <path>`; compressed **input** is selected by
the file extension (`:284-294`), and the CLI never compresses its output (`:109, 170, 233`).

### 13.3 `stats` CSV field table (`:82-105`)

Fields are `metric,value` rows, RFC-4180 quoted only when a value contains `,`, `"`, or a newline
(`:75-81`).

| Field | Meaning | Notes |
|---|---|---|
| `file` | last path component only | |
| `sequences` | row count | |
| `columns` | `Alignment.length`, i.e. the **maximum** row width | §5.1 |
| `datatype` | `nucleotide` \| `aminoacid` | |
| `pooled_identity_site_weighted` | `%.4f`, the site-weighted pooled identity of §8.2 | field name is deliberate; naming rationale at `:87-88` |
| `declared_aligned` | `aligned` \| `unknown` \| `not-aligned` | provenance, §5.5 |
| `mean_column_identity` | `%.4f`, unweighted arithmetic mean of `columnIdentities` | computed at `:116-120` |
| `min_column_identity`, `max_column_identity` | extrema over informative columns | §8.3 |
| `gap_columns` | columns with **no assignable residue** | §8.3 |
| `total_columns` | `UInt64(nCol)` | |
| `variable_sites`, `parsimony_informative_sites`, `singleton_sites` | §8.4 | **these three appear only here and in the stats panel, never in the quality sheet** |
| `gc_content` | `%.4f`, 0 for protein | ACGT-weighted aggregation of `SequenceUtils.gcContent` over sequences (`:122-139`) |
| `fastq_mean_phred`, `fastq_q20_ratio`, `fastq_q30_ratio` | `%.2f`, `%.4f`, `%.4f` | emitted **only when quality data exists** |

### 13.4 Exit codes

| Code | Symbol | Raised at | Meaning |
|---|---|---|---|
| `0` | success | `:51` | the subcommand completed |
| `64` | `EX_USAGE` | `:24` (fewer than 2 tokens), `:49` (unknown subcommand), `:152` (bad `export --format`), `:179` (missing `convert --format`), `:228` (bad `convert --format`) | usage error; the usage block goes to **stdout** |
| `65` | `EX_DATAERR` | `:195` | codon+amino-acid mixed track refused — **in practice unreachable**, since the flag lives in in-process translation metadata (`TranslationTables.swift:376-378`) and the CLI never translates (§15.1) |
| `66` | `EX_NOINPUT` | `:30-32` | file unreadable or gzip decompression failed; stderr `无法读取文件: <path>` |
| `70` | `EX_SOFTWARE` | `:52-55` | any thrown error — parse failure, invalid region, FASTQ without quality, output write failure; stderr `错误: <localizedDescription>` |

CLI output is **not localised** even though the GUI is bilingual: file and parse errors plus
`已写入`/`已导出` progress lines are Chinese, while format/scheme/mixed-track errors, the
`--fontsize` warning, and `Converted to … → …` are English.

---

## 14. Extension guide

Each recipe lists the files a complete change must touch. The recurring rule: **a new pure-logic
file must be added to the `Package.swift` `sources` allow-list, or it is not compiled by the
package and not covered by a single test** (`CONTRIBUTING.md:30`).

### 14.1 Adding a file format

| Step | File(s) | Detail |
|---|---|---|
| 1 | `Sources/AlignmentParsers.swift:9-11` | add the case to `AlignmentFormat` (keep `.unknown` last) |
| 2 | `Sources/AlignmentParsers.swift:14-42` | add a detection rule in `FormatDetector.detect`, ordered so it cannot steal a prefix from an existing format; test that the new marker survives the 65,536-byte sampling window |
| 3 | `Sources/AlignmentParsers.swift` | new `XxxParser.parse(_:progress:)`: reuse `decodeText`, the `ProgressCallback` throttle idiom (2,000 lines), `BlockAwareResidueCollector` for block layouts, and terminate in `ParsedAlignment.finalize` so normalisation, name uniquification, provenance, and the all-gap rejection all apply automatically |
| 4 | `Sources/AlignmentWriters.swift` | new `writeXxx` plus a name handler if the format limits name width; normalise gaps via the shared helper (`:13-18`) and write ragged rows through `paddedSlice` |
| 5 | `Sources/AlignmentParsers.swift:1425-1441` | register in `AlignmentParser.parse` dispatch |
| 6 | `Sources/CLIRunner.swift:58-66, 199-229` | extend the usage text **and** the alias table, including the canonical extension |
| 7 | `Sources/SeqAlignMacApp.swift` | open-panel extension allow-list (`:623-700`), save/save-as format menu (`:822-874`), `LeftSidebarView.swift:347-358` export group |
| 8 | `Info.plist:39-137, 140-270` | `CFBundleDocumentTypes` entry and the `UTImportedTypeDeclarations` extension list |
| 9 | `Sources/Localization.swift` | `AlignmentFormat` display strings via `formatName(_:zh:)` (`:1902-1924`) **and** the Chinese mirror |
| 10 | `Sources/ColorLogic.swift`, `Sources/ColumnStats.swift` | only if the format carries new semantics (per-column scores, annotations) |
| 11 | `Tests/SeqAlignCoreTests/FormatRoundTripTests.swift` | a byte-exact round-trip test plus malformed-input cases asserting an *error*, not a partial model |
| 12 | docs | §7 table, §15.9 lossiness row, `README.md`/`README_ZH.md` format count, `.zenodo.json:9` and `aboutFeatures` if the count changes |

### 14.2 Adding a colour scheme

1. `Sources/AlignmentCore.swift:14-22` — new `ColorScheme` case with the next `Int32` raw value
   (raw values bridge to menu tags and `UserDefaults`; **never renumber existing cases**).
2. `Sources/ColorLogic.swift` — add to `colorIndex(for:scheme:datatype:)` (`:40-50`), a category
   index table in the style of `:160-215`, and to `isProteinOnlyScheme` (`:19-24`) if applicable;
   extend `computeViewport` (`:83-157`) only if the scheme needs column context.
3. `Sources/ColorSchemes.swift` — the palette (index → `NSColor`) **for both light and dark**, or
   declare it appearance-invariant like `clustalX`/`zappo`/`seaView` with a comment saying why,
   and add legend entries in `ColorSchemeLegend` (`:212-269`) using `L.s`, not literals.
4. `Sources/SeqAlignMacApp.swift:502-538` — a View-menu button (decide deliberately whether it
   gets a shortcut; ⇧⌘1…5 are taken) and, for discoverability, `CommandPaletteView.swift:54-61`.
5. `Sources/LeftSidebarView.swift:245-296` and `Sources/SettingsView.swift` — the pickers.
6. `Sources/Localization.swift` — `scheme*` names and tooltips in **both** tables.
7. `Tests/SeqAlignCoreTests/SeqAlignCoreTests.swift` — index-table assertions in the style of
   `:466-488, 625-631`, including the nucleotide-with-protein-scheme fallback.
8. `Sources/ExportManager.swift` / `ColorResolver` consumers pick the scheme up automatically
   because both go through `ColorComputer`; verify, do not assume.

### 14.3 Adding a genetic-code table

1. `Sources/AlignmentCore.swift:24-42` — a new `GeneticCodeTable` case whose raw value is the
   **NCBI table number**.
2. `Sources/TranslationTables.swift` — a delta block on top of `standardTable` in the style of
   `:76-212` (state only the differences, never re-derive the 64 codons), and the new case in the
   exhaustive `table(for:)` switch (`:214-234`). Adding the case there is **mandatory**: the
   switch has no default, so an unhandled case is a compile error, which is the mechanism that
   prevents silent fallback for unsupported table IDs.
3. `Sources/TranslationOptionsView.swift` — the picker entry (currently literal English with the
   NCBI number in parentheses; moving it into `L.s` would be an improvement, see §10.4).
4. `Tests/SeqAlignCoreTests/SeqAlignCoreTests.swift:634-686` — spot-check the changed codons
   against the official `gc.prt` semantics for that table.
5. Update the count wherever it is repeated: `README.md:8`, `MANUAL_EN.md:181`,
   `MANUAL_ZH.md:183`, and §8.11 here. As §8.11 rules, the count is a statement about **this
   codebase** — EN "17 NCBI genetic code tables" (hyphenation follows the host document), ZH 「17 张 NCBI
   遗传密码表」 — and carries no claim about how many tables NCBI itself defines, so there is no external
   denominator to re-check.

### 14.4 Adding a localised string

1. `Sources/Localization.swift` — declare the field in `AppStrings` (`:75-1925`), then **supply
   both** `zh` (`:1455-1676`) and `en` (`:1678-1900`) values, and add the argument to the explicit
   memberwise `init` (`:78-512`) or the build fails. Strings with parameters should follow the
   computed-property pattern in the extension at `:1931-2002` rather than growing the initialiser.
2. Consume it as `L.s.key` at body-evaluation time. Never place a literal, in either language, in
   a view — that is what the (non-blocking) CI grep counts (§12.7).
3. If a new menu item or palette entry appears, keep `CommandPaletteView.swift` in sync; its 32
   entries are cached per language (`:34, 73`).
4. Key symmetry cannot be tested in `SeqAlignCoreTests` (`Localization.swift` is outside the
   target); an app-target test would be needed, and `CONTRIBUTING.md:43` requires discussing that
   justification first.
5. Do **not** reuse a key from §10.4's dead list as if it were live; retire or wire it up
   explicitly.

### 14.5 Adding a test

1. Choose the file by area: parser/writer round-trips → `FormatRoundTripTests.swift`; model,
   stats, search, colour, undo scenarios and enhancements → `SeqAlignCoreTests.swift`
   (`CoreEnhancementTests` from `:522`); malformed/boundary input → `EdgeCaseTests.swift`.
2. Keep fixtures inline (`SeqAlignCoreTests.swift:21` explains why); use
   `Alignment(sequences:…)` plus `assertRoundtrip` (`:147-160`) where appropriate.
3. Concurrency-sensitive tests must go through `snapshot()` / `lockedSequences`, matching the
   contract in §5.1.
4. Prefer asserting an error is thrown over asserting a specific recovered model, consistent with
   §7.11; and do not name a test something it does not check (§12.6, last bullet).
5. Add the file to `Package.swift:30-41` **only** if you added a core source file; then run
   `swift test` and `bash build.sh` locally, and expect CI to run `swift test`,
   `swift build -c release`, and `./build.sh --skip-tests`.
6. Update §12.6's counts and `README.md:8` / `.zenodo.json:9` if the total changes.

### 14.6 Cross-cutting rules

Domain stays UI-free (no AppKit/SwiftUI import in the ten core files; the only permitted imports
are `Foundation` and `Compression`, §4.2). New heavy work runs on a background queue against a
`snapshot()` and hops back to the main actor before touching `@State`/`@Published`
(`CONTRIBUTING.md:36`). Any new background job must capture a `GenerationToken` and discard stale
results (§4.6). Design tokens come from `MinimalTheme.swift` `Minimal.*`; views must not hard-code
colours, and dark-mode detection is only `NSAppearance.isDarkNow`. Metric names in new UI strings
must match the **code identifier**, never a stale tooltip (§8.2).

---

## 15. Known limitations and engineering discrepancies

This section is a ledger, not an apology: each item is verified against the code and each is a
thing a reader could otherwise learn wrongly from an existing document.

### 15.1 Dead code and unreachable capabilities

| Item | Status | Evidence |
|---|---|---|
| `TitleBarTabStrip.swift` | 10-line comment-only placeholder; the live implementation is `FloatingTabBar` | `Sources/TitleBarTabStrip.swift`, `TabbedWindow.swift:294-356` |
| `FaiIndexer` / `.fai` read+write | defined, **zero call sites** in `Sources/` or `Tests/` — an internal utility, not a user feature | `AlignmentParsers.swift:1005-1072` |
| PHYLIP `sequential`, `strict10Char`, `fullnamePadded` output | selectable in the writer, **not reachable** from the app or CLI (both pass the default variant); only tests exercise them | `AlignmentWriters.swift:161-220`; `SeqAlignMacApp.swift:987`; `CLIRunner.swift:204` |
| `writeFasta(wrapWidth > 0)` and `writeClustal(withConsensus: true)` | supported, never requested outside tests | `:37-56, 266-290`; `FormatRoundTripTests.swift:344` |
| `ResidueAlphabet.gapCount`, `.isNucleotideCharacter`, `.missingDataSymbols`; `IUPACCode.DegeneracyScope`; `AlignmentTranslator.translateNoGaps` / `translateBoth` | unused **internal** definitions — nothing in `Sources/` is declared `public`, and `translateNoGaps` / `translateBoth` are `private`; do not present as features | `ResidueAlphabet.swift:35, 94, 100`; `PrimerCalculator.swift:69-72`; `TranslationTables.swift:462, 467` |
| `Gzip.trailerMatches` / `countGzipHeaders` | implemented but never called — CRC32+ISIZE trailer verification is described in a code comment and not wired; the live rejection heuristic is `hasBelievableSecondMemberBoundary`, which also ignores its `firstUncompressedLength` parameter | `AlignmentParsers.swift:1214-1288` |
| CLI `exit 65` mixed-track refusal | defensive only: the flag lives in in-process translation metadata that the CLI never produces | `CLIRunner.swift:193-196`; `TranslationTables.swift:376-378` |
| `meanPairwiseIdentityExact` | correct implementation, **no caller outside tests** (`Tests/SeqAlignCoreTests/FormatRoundTripTests.swift:258`) | `ColumnStats.swift:342-372` |
| 20 dead localisation keys, incl. the whole "Select Codon Position" submenu and the six-frame-overview leftovers | see §10.4 | `Localization.swift` |

### 15.2 Documentation statements that the code contradicts

Rows are deleted as soon as the offending sentence is corrected in the document that carried it —
so nothing below may be quoted as a definition. What remains are UI strings that contradict the
code and cannot be fixed from the documentation, plus claims no document can settle.

| Wrong statement (where it appears) | What the code does |
|---|---|
| `statsMethodNote`, the stats-panel footer (`Localization.swift:1639, 1863`): "column identity = fraction of the most frequent residue (gaps excluded); mean pairwise identity via column-frequency method (gap sites excluded); variable/parsimony/singleton sites on non-gap residues" | column identity divides by **informative sites**, which exclude gaps *and* undetermined symbols, and an all-ambiguous column scores 0, §8.1; the headline figure is **site-weighted pooled identity**, §8.2; the three site counts filter `unassignableStates`, the larger set, §8.4 |
| `treeHint`, the NJ dialog hint (`Localization.swift:1641, 1865`): "first 200 sequences if >200" | **equal-interval** sampling, `step = count / maxSeqs`, §8.8; the sibling string `samplingNote` ("… (even sampling)", `ColumnStats.swift:506`) is the correct one |
| `statsGapCols` ("Gap columns" / 「含空位列数」, `Localization.swift:1516, 1739`) | the predicate is **no assignable residue**, which also covers an all-`N`/`X`/`?` column — and an all-`B` or all-`Z` column for protein, §8.3 |
| "handles alignments up to ~10,000 sequences"; ".dmg and Homebrew cask forthcoming"; third-party feature-comparison rows | unverifiable from this repository — no benchmark, no artefact, no external check, §9.9 |
| "CI checks the view layer for hardcoded Chinese" (`CONTRIBUTING.md:34`) | the grep job exists but is `continue-on-error: true`, so it can never fail a build, §12.7 |

### 15.3 Claims about the build that are not implemented

`Package.swift:29` states that CI can diff-check the `sources` allow-list; **no such CI step
exists** — the only lint jobs are the artefact guard and the non-blocking CJK grep. Consequence:
a newly added core file can still be silently untested, and §14's checklist is the actual control.
Relatedly, `README.md:171` describes `./build.sh` as "swift test → compile → ad-hoc sign → zip",
but the local test gate is best-effort (§12.3, stage 3.5); `CONTRIBUTING.md:48`'s "local
`swift test && ./build.sh` must pass" is the accurate phrasing.

### 15.4 Interaction defects

* **⇧⌘G is registered twice** — View ▸ Toggle Consensus (`SeqAlignMacApp.swift:526-527`) and
  Tools ▸ Find Previous (`:551-552`). The View menu is emitted before the Tools menu inside
  `SeqAlignCommands.body`, and AppKit's `performKeyEquivalent` hands the event to the first
  enabled match, so Find Previous is effectively unreachable by keyboard; the command palette
  advertises ⇧⌘G for consensus only, so the collision is hard for a user to discover. (The exact
  runtime precedence should be re-checked empirically before being stated as settled behaviour.)
* **Zoom in** is bound to ⌘+ **and** to a second, blank-titled menu button carrying `"="`
  (`:516-520`) — an invisible menu row that exists only to expose ⌘= on a US layout, where ⌘+
  never fires. Any shortcut table must list ⌘= alongside ⌘+ (`CommandPaletteView.swift:60-61`).
* **⌘X is semantically overloaded**: with an active canvas selection it copies *and* inserts a gap
  (`CopyPasteRouter.cut()`, `:1187-1233`); without one it is the standard responder cut. Delete
  sequence is ⇧⌘X precisely to avoid the collision.
* Okabe-Ito has a menu shortcut (⇧⌘5) but **no command-palette entry**; Default and Ti/Tv schemes,
  Move Sequence, Primer, Quality, and all image-export actions have **no shortcuts**
  (`:497, 511-512, 545-546`).
* Escape/Return coverage is uneven: Translation and Settings sheets have no Escape binding while
  Primer, Logo, Tree, Window, Annotation, Quality, Guide, Export preview, and the palette do.
* `.observingAppearanceChanges()` is applied twice (`ContentView.swift:98, 103`).

### 15.5 Export asymmetries

`ExportOptions.dpi` accepts any value but has **no UI control anywhere**: PNG is always 300 DPI
while the size label hard-codes the string "(300 DPI)" (`ExportManager.swift:24-47`).
`showConsensus` is hard-coded `true` on both export paths, so hiding the consensus row on screen
does **not** hide it in the exported image. The preview thumbnail is always a PNG render clamped to
1,600 px regardless of the selected PNG/PDF/SVG segment, and changing the segment does not
re-render. Sequence-export surfaces are asymmetric: the sidebar offers six formats (no FASTQ), the
generic Save-As panel offers five extensions, while the writer supports seven (§7.12).

### 15.6 Multi-window correctness

`performExport` raises its toast against `WindowRegistry.shared.activeForAction` rather than the
owning workspace (`ExportPreviewSheet.swift:~250`), so in a multi-window session the message can
land in the wrong window. `PendingWindowData` is a **single global static tuple**
(`SharedUIComponents.swift:568-580`) — neither thread-safe nor per-window — so two rapid
"open in a new window" actions (translate plus external aligner) can cross-deliver.

### 15.7 Measurement and metric limitations

The status bar's per-column identity cache filters **only `0x2D`** for gaps
(`SeqAlignMacApp.swift:225-240`), whereas the canvas and the scan use
`ResidueAlphabet.isGap` (`'-'`, `'.'`, `'~'`) — so a hover readout can disagree with the canvas
for non-canonical gap spellings. `SearchEngine` reads `alignment.sequences` **without the lock**
and is safe only because the app always hands it a snapshot (§6.1.8).
`SequenceUtils.mutationType` takes no datatype parameter despite its comment discussing
per-datatype branching, so any transition/transversion claim is valid for nucleotide input only
(protein-only schemes are separately guarded by `ColorComputer.effectiveScheme`).
`FormatRoundTripTests.swift:56-60` asserts the opposite of its name (§12.6).

### 15.8 Platform and distribution limitations

arm64-only (`build.sh:70`), so the shipped zip does not run on Intel Macs without recompiling, and
neither `README` nor `CONTRIBUTING` says so. Sandbox is **opt-in** (`SEQALIGN_SANDBOX`) and builds
are **not** universally Developer-ID-signed: the default path is ad-hoc signing, and notarisation
runs only with both `DEVELOPER_ID` and `NOTARY_PROFILE` and is non-fatal on failure. CI uploads an
ad-hoc-signed zip with 14-day retention and publishes nothing to a Release. There is no
`.fileImporter`/`DocumentGroup` session restore, no autosave, and no `CFBundleLocalizations`.
`Info.plist` declares `.fna`, `.faa`, `.mpfa` in the FASTA UTI, but the open panel does not accept
them; conversely `.gz` is both an open-panel extension and a *Viewer* document type with no save
story. Conversely the writers accept seven formats, the sidebar exports six, and the Save-As panel
lists five extensions (§7.12).

### 15.9 Format-behaviour limitations

`'.'` is rejected by the NEXUS matrix parser while PHYLIP, CLUSTAL, MSF, and Stockholm all accept
and normalise it, so `GAP=.` in NEXUS fails to load. MSF `Weight:` values are dropped on read and
fixed at `1.00` on write; the per-sequence `Len:` in the name block and the matrix width can
disagree for a ragged model. Stockholm `#=GC RF` is read and discarded and never written, so the
reference line does not round-trip. NEXUS `metadata` is always `[:]` and
`writeNexus(includeMetadata:)` in fact gates only `BEGIN SETS`. PHYLIP names are truncated to the
fixed field width, and the writer's 9+1 and 12-space layouts are deliberately not byte-exact
classical PHYLIP. The FASTA residue-whitelist comment says digits "1-7" where the code accepts
`0-9`. `translate(frame: 3)` offsets by 3 while the UI's "+3" is tag 2 (§8.10).
`AlignmentTranslator.translate` scans before it throws for protein input (§8.10, cost only).

### 15.10 CLI fallbacks that are silent

`--scheme` typos become `minimal` without a warning; non-numeric `--start`/`--end` are ignored;
out-of-range region bounds are clamped; `--fontsize` outside 6…40 warns but continues; `--out` is
recognised by `stats` only, so `convert … --out x` writes a default-named file into the working
directory. `MANUAL_EN.md:337`'s "no silent fallback" spirit therefore does **not** hold for
`export --scheme` (§13.2).

### 15.11 Accessibility and localisation debt

The legend popover shows Chinese under an English UI (§10.4 item 4); canvas toasts, the cursor
announcement, the consensus label, and the column-peek tooltip are Chinese-only; the status-bar
charset label is English-only; the 17 genetic-code picker entries are English-only. Keyboard-only
workflows are largely complete but the ⇧⌘G collision (§15.4) and the missing palette entry for
Okabe-Ito — the colour-vision-deficiency scheme — are accessibility defects in their own right.

### 15.12 Unverified numbers

No performance or capacity figure is stated in this document. Related absences: no coverage
measurement, no fuzzing, no benchmarks, no CHANGELOG or release-notes process, no `date-released`
corroboration inside the repository, and no `.dmg` or Homebrew formula.

### 15.13 Metadata and governance gaps

The repository contains **no** email address, PGP key fingerprint, or form URL, yet
`SECURITY.md:15` and `CODE_OF_CONDUCT.md:31` refer to "the channels published by the maintainer";
GitHub private vulnerability reporting is the only actionable path today. Release metadata cannot
be cross-checked from inside the repository either: `.zenodo.json` carries **no version, no
publication date, and no DOI field**, so the `0.2.0` of `CITATION.cff:10` and the concept DOI at
`CITATION.cff:12-13` (also in the badge at `README.md:4`) rest entirely on the deposited record.
`CITATION.cff` itself is valid CFF 1.2.0 and its author entry uses the canonical
`family-names`/`given-names` keys (`:6-7`). `CODE_OF_CONDUCT.md` is no longer the
failed-translation specimen this section once described — the headings are localised
(`## 可接受的行为示例`, `:9`) and 「坦然接受建设性批评」 (`:13`) replaces the untranslated
"gracefully" — but it is a *condensed* Chinese rendering of Contributor Covenant 2.0 rather than
the canonical text: the "unacceptable behaviour" enumeration collapses into one sentence
(`:17-18`), only its H1 is bilingual (`:2`), and its enforcement section delegates reports to
`SECURITY.md` and to maintainer contact details that the repository does not publish (`:31`).

---

## 16. Governance, release metadata, and references

### 16.1 Document map and single-source-of-truth policy

| File | Role |
|---|---|
| [`README.md`](../README.md) / `README_ZH.md` | project front page; feature and method summary |
| [`docs/USAGE.md`](USAGE.md) | task-oriented user guide |
| **`docs/DOCUMENTATION.md`** (this file) | normative architecture, formats, metrics, build, deviations |
| [`MANUAL_EN.md`](../MANUAL_EN.md) / `MANUAL_ZH.md` | 20-section end-user reference manual, 1:1 bilingual |
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) | environment, commands, architecture rules, test policy, submission flow |
| [`SECURITY.md`](../SECURITY.md) | supported versions, reporting route, declared attack surface, distribution integrity |
| [`PRIVACY.md`](../PRIVACY.md) | data-processing table, App Store nutrition label, MAS versus direct distribution |
| [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) | Contributor Covenant 2.0 |
| [`LICENSE`](../LICENSE), [`CITATION.cff`](../CITATION.cff), [`.zenodo.json`](../.zenodo.json) | MIT licence, citation, deposit metadata |

Counts (format count, test count, table count) currently exist in several places at once —
`README.md:8`, `README_ZH.md:8`, `.zenodo.json:9`, and `aboutFeatures` in
`Localization.swift:1544`. New prose should cite this document rather than restate the numbers,
so the next change has one place to fix.

### 16.2 Versioning and release metadata

`0.2.0` is recorded in `Info.plist:15-18` (`CFBundleShortVersionString` and `CFBundleVersion`,
the packaging source of truth), `CITATION.cff:10` (`"0.2.0"`), the git tag `v0.2.0`, `README.md:35`,
and in **hard-coded strings** `Localization.swift:1542` (`aboutVersion`, Chinese) and `:1768`
(English). There is no `CFBundleShortVersionString` lookup anywhere in `Sources/`, so the About box
displays a fourth, manually maintained copy, and `build.sh` embeds no version (it copies
`Info.plist` verbatim). Git history starts at the squashed initial import (`8ac0015`, 2026-09-24);
the `v0.1.0` tag points at that import, and the `v0.2.0` tag at `5d73c26` (2026-11-14), so only
the interface-refinement commit `694caf5` lies outside the tagged tree. The `docs/` directory
entered the repository after `v0.1.0` was cut — it is absent from that tag's tree — and is included
in `v0.2.0`.

Two Zenodo DOIs are in circulation *by design* and should be labelled explicitly wherever quoted:
the **concept DOI** `10.5281/zenodo.23053513` (badge at `README.md:4`; resolves to the newest
release) and the **version DOI** `10.5281/zenodo.23053514` (cited only by the deposited records —
no file in this repository references it). The BibTeX entry at `README.md:108-120` carries
`note = {v0.2.0}` (`:115`) and the concept DOI (`:117`). Neither DOI can be verified from inside
this repository, because `.zenodo.json` has no DOI field. Licence: MIT. Only two files declare it
*as data* — `CITATION.cff:14` (`license: MIT`, which is the SPDX id) and `.zenodo.json:10-12`
(`license.name`); `LICENSE:3`, `README.md:187` and the `NSHumanReadableCopyright` string at
`Info.plist:26` state it in prose only.

### 16.3 References

Method literature as recorded in the source, plus the software and format references the
implementation depends on:

1. Saitou, N. & Nei, M. (1987) *The neighbor-joining method: a new method for reconstructing
   phylogenetic trees*, Mol. Biol. Evol. 4:406–425 — cited `ColumnStats.swift:558`.
2. SantaLucia, J. Jr. (1998) *A unified system for nucleic acid thermodynamic parameters*,
   Biochemistry 37:1–5 — ΔH/ΔS set and terminal corrections, cited
   `PrimerCalculator.swift:4, 138-167`.
3. von Ahsen, K. et al. (1999) *Tm predictions with salt correction including divalent cations and
   dNTP chelation* — `PrimerCalculator.swift:4, 254-270`.
4. Schneider, T. D. & Stephens, R. M. (1990) *Sequence logos: a new way to display consensus
   frequencies*, Nucleic Acids Res. 18:6097–6100, with the small-sample correction
   `e(n) = (K−1)/(2 ln 2 n)` — `ColumnStats.swift:421, 441-445`.
5. Wong, B. (2011) *Colour picks: points to make on the palette designed for colour-vision
   deficiency*, Nature Methods 8:123 — Okabe-Ito palette attribution,
   `ColorSchemes.swift:138-149`.
6. NCBI *The Genetic Code Translation Tables* (`gc.prt`) — the 17 implemented tables and their
   codon deltas, `TranslationTables.swift:3, 16-234`; the public-data attribution is recorded there.
7. Wallace, R. B. et al. (1979) *the 2·(A+T) + 4·(G+C) rule*, `PrimerCalculator.swift:185`.
8. GC content by the EMBOSS denominator convention (defined residues only),
   `AlignmentCore.swift:285-301`.
9. IUPAC nucleotide and amino-acid ambiguity codes — the degenerate sets, the pairing table used
   by reverse complement (`AlignmentCore.swift:220-253`), and the regex classes
   (`SearchEngine.swift:345-360`).
10. Format specifications: GCG MSF (`AlignmentWriters.swift:293-309`, checksum
    `Σ ((i mod 57)+1)·ASCII` mod 10000), ClustalX colouring and conservation notation
    (`ColorLogic.swift:178-189`, `AlignmentWriters.swift:233-264`), Pfam Stockholm 1.0
    (`AlignmentWriters.swift:349-371`), NEXUS/PAUP `SETS`/`CHARSET` step notation
    (`AlignmentParsers.swift:531-578`), FASTQ Phred+33/+64 (SAM/BAM specification,
    `AlignmentParsers.swift:249-260`), gzip RFC 1952 and BGZF (samtools)
    (`AlignmentParsers.swift:1186-1423`), GFF3 (Sequence Ontology).
11. BibTeX `@software` entry and full reference block: `README.md:105-166`; CITATION.cff and
    `.zenodo.json` as above.

The comparison table in `README.md:90-99` (against Jalview, AliView, and UGENE) is a claim about
third-party software and cannot be verified from this repository; it is therefore not reproduced
here.

---

*End of `docs/DOCUMENTATION.md`. For task-oriented instructions see [USAGE.md](USAGE.md); for the
Chinese version of this document see [DOCUMENTATION_ZH.md](DOCUMENTATION_ZH.md); for the document
index see [README.md](README.md).*
