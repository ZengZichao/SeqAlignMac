# SeqAlignMac

![CI](https://img.shields.io/github/actions/workflow/status/zengzichao/SeqAlignMac/ci.yml?branch=main&label=CI&style=flat-square)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23053513.svg)](https://doi.org/10.5281/zenodo.23053513)

A native macOS application for viewing, editing, and analysing multiple sequence alignments. SeqAlignMac is built entirely in Swift and SwiftUI, providing a minimalist, distraction-free interface with a monochrome aesthetic and full keyboard navigation. Unlike Jalview or AliView, which are Java-based desktop tools, SeqAlignMac is designed from the ground up for macOS 14+, offering a native Apple experience with built-in colour-vision-deficiency accessibility (Okabe-Ito palette), bilingual (English and Chinese) localisation, and a headless command-line interface for batch processing in reproducible pipelines.

The application supports reading and writing seven alignment formats (FASTA, FASTQ, NEXUS, PHYLIP, CLUSTAL, MSF, and Stockholm) with automatic gzip decompression. It provides six-frame translation across 17 of the 27 genetic code tables currently defined by NCBI, nearest-neighbour primer Tm calculation (SantaLucia, 1998), neighbour-joining phylogenetic tree inference (Saitou and Nei, 1987), sequence logo generation (Schneider and Stephens, 1990), column-level quality statistics, IUPAC-aware degenerate primer analysis, and vector export to PNG, PDF, and SVG. A pure-logic core library (`SeqAlignCore`) is isolated from the rendering layer and covered by 110 unit tests: all seven parser round-trips, primer thermodynamics, translation, undo/redo, search, statistics, and a regression suite covering format edge cases (FASTQ quality-preserving writes, gzip compress/decompress round-trips, IUPAC/strict consensus modes, and PHYLIP sequential/interleaved variants).

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Methodological Definitions](#methodological-definitions)
- [Feature Comparison](#feature-comparison)
- [How to Cite](#how-to-cite)
- [Build and Test](#build-and-test)
- [License](#license)
- [Distribution](#distribution)
- [中文说明](#中文说明)

## Features

- **Format I/O**: FASTA, FASTQ, NEXUS, PHYLIP, CLUSTAL, MSF, and Stockholm (Pfam/Rfam standard) import and export; `.gz` files (including multi-member bgzip) opened directly; wrapped sequential PHYLIP and taxon-aggregated interleaved NEXUS supported; malformed inputs raise explicit errors instead of being silently truncated.
- **Visualisation**: Seven colour schemes (minimal monochrome, default nucleotide, ClustalX, Zappo, SeaView, transition/transversion, and Okabe-Ito colour-vision-deficiency-friendly), consensus sequence track, conservation track, and reference-sequence difference mode.
- **Large-alignment rendering**: Virtualised canvas that paints only the visible region; the sequence-name column stays frozen while scrolling horizontally; thin scroll bars are always visible and draggable; glyph rendering is density-adaptive (letters are drawn once columns are wide enough to be readable, colour blocks below that); column statistics are computed off the main thread so very large alignments open without blocking the interface.
- **Analysis**: Alignment quality statistics, sequence logo (information content), neighbour-joining phylogenetic tree (Newick export), sliding-window identity, six-frame translation (17 NCBI genetic code tables), primer Tm/GC/dimer (configurable salt concentrations), and GFF3 annotation browsing with coordinate navigation.
- **Tools**: IUPAC-aware degenerate search with regular expressions, full undo/redo, command palette, multi-tab interface, PNG/PDF/SVG vector export, and a headless command-line interface.
- **FASTQ Quality**: Phred quality values integrated into statistics (mean Phred, Q20/Q30 ratios).
- **Localisation**: English and Simplified Chinese interface, switchable at runtime.
- **External aligners**: MAFFT (stdout capture), MUSCLE v5, and ClustalW2 presets; large outputs are drained concurrently to prevent pipe deadlocks, and result formats are auto-detected.

## What's new in v0.1.0 (2026-09)

Initial public release. SeqAlignMac is a native macOS application for viewing, editing, and analysing multiple sequence alignments, built entirely in Swift and SwiftUI.

## Quick Start

```bash
# 1. Open a FASTA file in the GUI application
open -a SeqAlignMac alignment.fasta   # or drag the file onto the app icon

# 2. Batch-convert FASTA to NEXUS via the command line
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus -o alignment.nexus

# 3. Export a sub-region as a NEXUS file for downstream primer design
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus --start 100 --end 300 -o region.nexus
```

## Installation

### From Source (SwiftPM)

Requirements: macOS 14.0 or later, Xcode 16 or Swift 6.0 toolchain.

```bash
git clone https://github.com/zengzichao/SeqAlignMac.git
cd SeqAlignMac
./build.sh        # runs swift test, compiles, ad-hoc signs, and packages the .app bundle
./build.sh --skip-tests   # skip swift test (CI runs tests separately)
```

The built application is placed at `SeqAlignMac.app` in the repository root, with a distributable zip at `SeqAlignMac.app.zip`.

### Run Tests Only

```bash
swift test        # runs SeqAlignCore unit tests only
```

## Methodological Definitions

| Metric | Definition |
| --- | --- |
| Column identity | Proportion of the most frequent non-gap residue in a column (gaps excluded) |
| Mean pairwise identity | Column-frequency method: &Sigma;<sub>col</sub> &Sigma;<sub>k</sub> f<sub>k</sub>(f<sub>k</sub>&minus;1) / &Sigma;<sub>col</sub> n<sub>c</sub>(n<sub>c</sub>&minus;1); gap sites excluded, no sampling required |
| Variable / parsimony / singleton sites | Counted over non-gap residues: &ge;2 residue types / &ge;2 types each &ge;2 sequences / only one sequence differs |
| NJ tree | Saitou and Nei (1987); distance = uncorrected p-distance (pairwise comparison over mutually non-gap sites only); >200 sequences subsampled to first 200 |
| Sequence logo | Schneider and Stephens (1990): R(l) = log<sub>2</sub>K &minus; (H(l) + e(n)), e(n) = (K&minus;1)/(2&middot;ln2&middot;n) small-sample correction; gaps excluded |
| Primer Tm | SantaLucia (1998) unified nearest-neighbour parameters with terminal correction; salt correction after von Ahsen et al. (1999); Na<sup>+</sup>/Mg<sup>2+</sup>/oligo concentration configurable in the UI |
| Okabe-Ito palette | Wong (2011), *Nature Methods*; red-green colour-blindness-friendly |

## Feature Comparison

Table 1: Feature comparison of SeqAlignMac with established alignment editors.

| Feature | SeqAlignMac | Jalview 2.11 | AliView 1.32 | UGENE 50 |
| --- | --- | --- | --- | --- |
| Native macOS application | Yes | No (Java) | No (Java/Swing) | No (Qt) |
| Colour-vision-deficiency accessibility | Yes (Okabe-Ito) | No | No | No |
| CLI batch processing | Yes | Limited | No | Yes |
| Translation (17 NCBI tables) | Yes | Yes (standard subset) | No | Yes (standard subset) |
| Primer calculation | Yes (Tm, GC, dimer) | No | No | Yes (Tm, GC) |
| Sequence logo | Yes | Yes (via plugin) | No | Yes |
| Neighbour-joining tree | Yes | Yes | Yes | Yes |
| Maintenance status | Active (2026) | Active | Active | Active |

## How to Cite

If you use SeqAlignMac in your research, please cite the software:

```bibtex
@software{zeng2026seqalignmac,
  author    = {Zeng, Zichao},
  title     = {SeqAlignMac: A native macOS application for viewing, editing, and analysing multiple sequence alignments},
  year      = {2026},
  month     = sep,
  note      = {v0.1.0},
  publisher = {Zenodo},
  doi       = {10.5281/zenodo.23053514},
  url       = {https://doi.org/10.5281/zenodo.23053514}
}
```

To cite the software independently of its version, use the concept DOI [10.5281/zenodo.23053513](https://doi.org/10.5281/zenodo.23053513), which always resolves to the most recent release.

### References

```bibtex
@article{santalucia1998,
  author  = {SantaLucia, Jr., John},
  title   = {A unified view of polymer, dumbbell, and oligonucleotide {DNA} nearest-neighbor thermodynamics},
  journal = {Proceedings of the National Academy of Sciences},
  volume  = {95},
  number  = {4},
  pages   = {1460--1465},
  year    = {1998},
  doi     = {10.1073/pnas.95.4.1460}
}

@article{saitou1987,
  author  = {Saitou, Naruya and Nei, Masatoshi},
  title   = {The neighbor-joining method: a new method for reconstructing phylogenetic trees},
  journal = {Molecular Biology and Evolution},
  volume  = {4},
  number  = {4},
  pages   = {406--425},
  year    = {1987},
  doi     = {10.1093/oxfordjournals.molbev.a040454}
}

@article{schneider1990,
  author  = {Schneider, Thomas D. and Stephens, R. Michael},
  title   = {Sequence logos: a new way to display consensus sequences},
  journal = {Nucleic Acids Research},
  volume  = {18},
  number  = {20},
  pages   = {6097--6100},
  year    = {1990},
  doi     = {10.1093/nar/18.20.6097}
}

@article{wong2011,
  author  = {Wong, Bang},
  title   = {Points of view: Color blindness},
  journal = {Nature Methods},
  volume  = {8},
  number  = {6},
  pages   = {441},
  year    = {2011},
  doi     = {10.1038/nmeth.1618}
}
```

## Build and Test

```bash
./build.sh        # swift test (domain-layer unit tests) → swiftc compile → ad-hoc sign → package zip
./build.sh --skip-tests   # skip swift test (CI runs tests separately)
swift test        # run SeqAlignCore unit tests only
```

Set `DEVELOPER_ID` to sign with a Developer ID certificate (hardened runtime); without it an ad-hoc signature is applied as a fallback. Optional distribution knobs:

- `SEQALIGN_SANDBOX=1` — embed the Mac App Store App Sandbox entitlements (`SeqAlignMac.entitlements`).
- `NOTARY_PROFILE=<profile>` — after a Developer ID signature, submit the built zip with `notarytool` and `stapler` (run `xcrun notarytool store-credentials …` once first).

## License

MIT License. See the [LICENSE](LICENSE) file for details.

## Distribution

macOS 14+. Two release channels with one functional difference:

- **GitHub Releases / Developer ID (direct download):** unsandboxed build — **keeps** the External Aligners
  (MAFFT / MUSCLE / ClustalW2) feature; ship with Developer ID signature + notarization so Gatekeeper accepts it.
- **Mac App Store:** must run inside the App Sandbox, which **forbids launching user-installed external
  binaries** — so the External Aligners feature is not available in the App Store build. Everything else
  (viewing, editing, analysis, translation, statistics, export, undo/redo, CLI-free) is identical.

Pre-built `.dmg` and a Homebrew cask are forthcoming. See [`PRIVACY.md`](PRIVACY.md),
[`SECURITY.md`](SECURITY.md), and [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Documentation

- [Manual (English)](MANUAL_EN.md) — detailed user guide and workflow examples
- [Manual (中文)](MANUAL_ZH.md) — 详细用户手册
- [README (中文)](README_ZH.md) — Chinese quick-start guide

---

## 中文说明

SeqAlignMac 是一款 macOS 原生多序列比对（MSA）查看与编辑器，使用 Swift 和 SwiftUI 构建。与 Jalview、AliView 等基于 Java 的桌面工具不同，SeqAlignMac 面向 macOS 14+ 原生设计，提供极简的黑白配色界面、色觉无障碍（Okabe-Ito 色板）、中英双语界面切换，以及用于批量处理的无界面命令行接口。

应用支持七种比对格式的读写（FASTA、FASTQ、NEXUS、PHYLIP、CLUSTAL、MSF、Stockholm），可直接打开 .gz 压缩文件（含 bgzip 多成员）。提供六阅读框翻译（17 张 NCBI 遗传密码表）、近邻法引物 Tm 计算（SantaLucia 1998）、邻接法系统发育树（Saitou & Nei 1987）、序列 Logo（Schneider & Stephens 1990）、列级质量统计、IUPAC 简并引物分析，以及 PNG/PDF/SVG 矢量导出。纯逻辑核心库 `SeqAlignCore` 与渲染层解耦，包含 110 个单元测试：七种解析器往返、引物热力学、翻译、撤销/重做、搜索、统计，以及覆盖格式边界情形的回归套件。

### 功能

- **格式读写**：FASTA / FASTQ / NEXUS / PHYLIP / CLUSTAL / MSF / Stockholm（Pfam/Rfam 标准）导入与导出；.gz 压缩文件（含 bgzip 多成员）直接打开；支持换行续行的 PHYLIP 顺序格式与按 taxon 聚合的 NEXUS 交错格式；畸形输入显式报错而非静默截断。
- **可视化**：七种配色方案（极简 / 默认 / ClustalX / Zappo / SeaView / 过渡颠换 / Okabe-Ito 色觉无障碍）、共识序列轨道、保守度轨道、参考序列差异模式。
- **大数据渲染**：仅绘制可视区域的虚拟化画布；横向滚动时序列名称列固定显示；细滚动条常驻可见可拖拽；字形按密度自适应（列宽可读时绘制字母，过窄时仅显示色块）；列统计在后台线程计算，超大比对打开不阻塞界面。
- **分析**：比对质量统计、序列 Logo（信息含量）、邻接法系统发育树（Newick 导出）、滑动窗口一致度、六阅读框翻译（17 张 NCBI 遗传密码表）、引物 Tm/GC/二聚体（盐浓度可配置）、GFF3 注释浏览与坐标跳转。
- **工具**：IUPAC 简并搜索（支持正则）、撤销/重做、命令面板、多标签页、PNG/PDF/SVG 矢量导出、无界面命令行。
- **FASTQ 质量**：Phred 质量值参与统计（平均 Phred、Q20/Q30 占比）。
- **双语**：英文与简体中文界面，运行时可切换。
- **外部比对**：MAFFT（stdout 直读）、MUSCLE v5、ClustalW2 预设；大输出并发排空管道防死锁，结果格式自动检测。

### 快速开始

```bash
# 1. GUI 打开 FASTA 文件
open -a SeqAlignMac alignment.fasta   # 或直接把文件拖到应用图标上

# 2. 命令行批量转换 FASTA → NEXUS
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus -o alignment.nexus

# 3. 导出某段区域用于引物设计
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus --start 100 --end 300 -o region.nexus
```

### 方法学定义

| 指标 | 定义 |
| --- | --- |
| 列一致度 | 该列主频残基占非空位残基的比例（空位不计） |
| 平均成对一致度 | 列频次法：&Sigma;<sub>col</sub> &Sigma;<sub>k</sub> f<sub>k</sub>(f<sub>k</sub>&minus;1) / &Sigma;<sub>col</sub> n<sub>c</sub>(n<sub>c</sub>&minus;1)，空位位点不计，无需采样 |
| 变异/简约/单态位点 | 按非空位残基统计：&ge;2 种残基 / &ge;2 种且每种 &ge;2 条 / 仅 1 条不同 |
| NJ 树 | Saitou & Nei 1987；距离为未校正 p-distance（成对比较仅计双方均非空位位点）；>200 条取前 200 条 |
| 序列 Logo | Schneider & Stephens 1990：R(l) = log<sub>2</sub>K &minus; (H(l) + e(n))，e(n) = (K&minus;1)/(2&middot;ln2&middot;n) 小样本校正；空位不计 |
| 引物 Tm | SantaLucia 1998 统一近邻参数 + 末端校正；盐校正 von Ahsen 1999；Na<sup>+</sup>/Mg<sup>2+</sup>/寡链浓度均可在界面配置 |
| Okabe-Ito 色板 | Wong 2011, *Nature Methods*，对红绿色盲友好 |

### 构建与测试

```bash
./build.sh        # swift test（领域层单元测试）→ swiftc 编译 → ad-hoc 签名 → 打包 zip
./build.sh --skip-tests   # 跳过 swift test（CI 中已单独执行）
swift test        # 仅运行 SeqAlignCore 单元测试
```

设置 `DEVELOPER_ID` 环境变量可用开发者证书签名（启用强化运行时，便于公证）；未设置时使用 ad-hoc 签名兜底。

### 许可证

MIT 许可证，详见 [LICENSE](LICENSE) 文件。

### 分发

macOS 14+，源码构建（SwiftPM）。预编译 .dmg 与 Homebrew cask 即将推出。

### 文档

- [英文用户手册](MANUAL_EN.md) — 详细使用指南与工作流示例
- [中文用户手册](MANUAL_ZH.md) — 详细使用说明
