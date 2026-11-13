# SeqAlignMac

![CI](https://img.shields.io/github/actions/workflow/status/ZengZichao/SeqAlignMac/ci.yml?branch=main&label=CI&style=flat-square)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23053513.svg)](https://doi.org/10.5281/zenodo.23053513)

SeqAlignMac 是一款 macOS 原生多序列比对（MSA）查看、编辑与分析应用，使用 Swift 编写，在 SwiftUI 外壳中承载 AppKit Core Text 画布，提供极简、无干扰的黑白配色界面与完整的键盘导航。与 Jalview、AliView 等基于 Java 的桌面工具不同，SeqAlignMac 面向 macOS 14+ 从零开始设计，带来原生 Apple 体验，内置色觉无障碍支持（Okabe-Ito 色板）、中英双语界面切换，以及用于在可复现流程中批量处理的无界面命令行接口。

应用支持七种比对格式的读写（FASTA、FASTQ、NEXUS、PHYLIP、CLUSTAL、MSF、Stockholm），可直接打开 .gz 压缩文件。提供六阅读框翻译（NCBI 现行 27 张遗传密码表中的 17 张）、近邻法引物 Tm 计算（SantaLucia 1998）、邻接法系统发育树（Saitou & Nei 1987）、序列 Logo（Schneider & Stephens 1990）、列级质量统计、IUPAC 简并引物分析，以及 PNG/PDF/SVG 矢量导出。纯逻辑核心库 `SeqAlignCore` 与渲染层解耦，包含 110 个单元测试：七种解析器往返、引物热力学、翻译、撤销/重做、搜索、统计，以及覆盖格式边界情形（FASTQ 保留质量值的写出、gzip 压缩/解压往返、IUPAC/严格共识模式，以及 PHYLIP 顺序/交错变体）的回归套件。

## 目录

- [功能](#功能)
- [快速开始](#快速开始)
- [安装](#安装)
- [方法学定义](#方法学定义)
- [功能对比](#功能对比)
- [引用方式](#引用方式)
- [构建与测试](#构建与测试)
- [许可证](#许可证)
- [分发](#分发)
- [文档](#文档)

## 功能

- **格式读写**：FASTA / FASTQ / NEXUS / PHYLIP / CLUSTAL / MSF / Stockholm（Pfam/Rfam 标准）导入与导出；.gz 压缩文件（含 bgzip 多成员）直接打开；支持换行续行的 PHYLIP 顺序格式与按 taxon 聚合的 NEXUS 交错格式；畸形输入显式报错而非静默截断。
- **可视化**：七种配色方案（极简单色 / 默认核苷酸 / ClustalX / Zappo / SeaView / 过渡/颠换 / Okabe-Ito 色觉无障碍）、共识序列轨道、保守度轨道、参考序列差异模式。
- **大数据渲染**：仅绘制可视区域的虚拟化画布；横向滚动时序列名称列固定显示；细滚动条常驻可见可拖拽；字形按密度自适应（列宽可读时绘制字母，过窄时仅显示色块）；列统计在后台线程计算，超大比对打开不阻塞界面。
- **分析**：比对质量统计、序列 Logo（信息含量）、邻接法系统发育树（Newick 导出）、滑动窗口一致度、六阅读框翻译（17 张 NCBI 遗传密码表）、引物 Tm/GC/二聚体（盐浓度可配置）、GFF3 注释浏览器与坐标跳转。
- **工具**：IUPAC 简并搜索（支持正则）、撤销/重做、命令面板、多标签页、PNG/PDF/SVG 矢量导出、无界面命令行。
- **FASTQ 质量**：Phred 质量值参与统计（平均 Phred、Q20/Q30 占比）。
- **双语**：英文与简体中文界面，运行时可切换。
- **外部比对器**：MAFFT（stdout 直读）、MUSCLE v5、ClustalW2 预设；大输出并发排空管道防死锁，结果格式自动检测。

## v0.1.0 变更（2026-09）

首次公开发布。SeqAlignMac 是一款 macOS 原生多序列比对（MSA）查看、编辑与分析应用，使用 Swift 编写，在 SwiftUI 外壳中承载 AppKit 画布。

## 快速开始

```bash
# 1. GUI 打开 FASTA 文件
open -a SeqAlignMac alignment.fasta   # 或直接把文件拖到应用图标上

# 2. 命令行批量转换 FASTA → NEXUS
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus -o alignment.nexus

# 3. 导出某段区域用于引物设计
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus --start 100 --end 300 -o region.nexus
```

## 安装

### 从源码构建（SwiftPM）

要求：macOS 14.0+，Xcode 16 或 Swift 6.0 工具链。

```bash
git clone https://github.com/ZengZichao/SeqAlignMac.git
cd SeqAlignMac
./build.sh        # swift test（领域层单元测试）→ swiftc 编译 .app → ad-hoc 签名 → 打包 zip
./build.sh --skip-tests   # 跳过 swift test（CI 中已单独执行）
./build.sh --open         # 构建后直接启动应用
```

构建后的应用程序位于仓库根目录下的 `SeqAlignMac.app`，同时生成可分发的 `SeqAlignMac.app.zip`。

### 仅运行测试

```bash
swift test        # 仅运行 SeqAlignCore 单元测试
```

## 方法学定义

| 指标 | 定义 |
| --- | --- |
| 列一致度 | 该列主频残基占非空位残基的比例（空位不计） |
| 平均成对一致度 | 列频次法：&Sigma;<sub>col</sub> &Sigma;<sub>k</sub> f<sub>k</sub>(f<sub>k</sub>&minus;1) / &Sigma;<sub>col</sub> n<sub>c</sub>(n<sub>c</sub>&minus;1)，空位位点不计，无需采样 |
| 变异/简约/单态位点 | 按非空位残基统计：&ge;2 种残基 / &ge;2 种且每种 &ge;2 条 / 仅 1 条不同 |
| NJ 树 | Saitou & Nei 1987；距离为未校正 p-distance（成对比较仅计双方均非空位位点）；>200 条取前 200 条 |
| 序列 Logo | Schneider & Stephens 1990：R(l) = log<sub>2</sub>K &minus; (H(l) + e(n))，e(n) = (K&minus;1)/(2&middot;ln2&middot;n) 小样本校正；空位不计 |
| 引物 Tm | SantaLucia 1998 统一近邻参数 + 末端校正；盐校正沿用 von Ahsen 等人（1999）；Na<sup>+</sup>/Mg<sup>2+</sup>/寡链浓度均可在界面配置 |
| Okabe-Ito 色板 | Wong 2011, *Nature Methods*，对红绿色盲友好 |

## 功能对比

表 1：SeqAlignMac 与主流比对编辑器的功能对比。

| 功能 | SeqAlignMac | Jalview 2.11 | AliView 1.32 | UGENE 50 |
| --- | --- | --- | --- | --- |
| macOS 原生应用 | 是 | 否（Java） | 否（Java/Swing） | 否（Qt） |
| 色觉无障碍 | 是（Okabe-Ito） | 否 | 否 | 否 |
| 命令行批处理 | 是 | 有限 | 否 | 是 |
| 翻译（17 张 NCBI 表） | 是 | 是（标准子集） | 否 | 是（标准子集） |
| 引物计算 | 是（Tm, GC, 二聚体） | 否 | 否 | 是（Tm, GC） |
| 序列 Logo | 是 | 是（插件） | 否 | 是 |
| 邻接法树 | 是 | 是 | 是 | 是 |
| 维护状态 | 活跃（2026） | 活跃 | 活跃 | 活跃 |

## 引用方式

如果您在研究中使用了 SeqAlignMac，请引用本软件：

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

如需引用不绑定具体版本的全部已发布版本，请使用概念 DOI [10.5281/zenodo.23053513](https://doi.org/10.5281/zenodo.23053513)，它始终解析到最新版本。

### 参考文献

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

## 构建与测试

```bash
./build.sh        # swift test（领域层单元测试）→ swiftc 编译 → ad-hoc 签名 → 打包 zip
./build.sh --skip-tests   # 跳过 swift test（CI 中已单独执行）
swift test        # 仅运行 SeqAlignCore 单元测试
```

设置 `DEVELOPER_ID` 环境变量可用开发者 ID 证书签名（启用强化运行时）；未设置时使用 ad-hoc 签名兜底。可选的分发开关：

- `SEQALIGN_SANDBOX=1` — 打入 Mac App Store 的 App 沙盒 entitlements（`SeqAlignMac.entitlements`）。
- `NOTARY_PROFILE=<profile>` — 在完成 Developer ID 签名之后，用 `notarytool` 提交已构建的 zip 并用 `stapler` 装订（需先运行一次 `xcrun notarytool store-credentials …` 存好凭据）。

## 许可证

MIT 许可证，详见 [LICENSE](LICENSE) 文件。

## 分发

macOS 14+。两个发布渠道，仅有一项功能差异：

- **GitHub Releases / Developer ID（直接下载）：** 非沙盒构建——**保留**外部比对器（MAFFT / MUSCLE / ClustalW2）功能；随附 Developer ID 签名 + 公证一并分发，以便 Gatekeeper 放行。
- **Mac App Store：** 必须运行在 App 沙盒（App Sandbox）内，而沙盒**禁止启动用户自行安装的外部可执行文件**——因此 App Store 版本不含外部比对器功能。其余功能（查看、编辑、分析、翻译、统计、导出、撤销/重做，均不依赖 CLI）完全一致。

预编译的 `.dmg` 与 Homebrew cask 即将推出。另见 [`PRIVACY.md`](PRIVACY.md)、[`SECURITY.md`](SECURITY.md) 与 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 文档

- [文档索引](docs/README.md) — `docs/` 目录下持续维护的文档总览
- [使用指南](docs/USAGE_ZH.md) / [Usage Guide](docs/USAGE.md) — 任务导向的使用说明
- [项目说明文档](docs/DOCUMENTATION_ZH.md) / [Project Documentation](docs/DOCUMENTATION.md) — 架构、格式、指标与构建门禁
- [英文用户手册](MANUAL_EN.md) — 详细使用指南与工作流示例
- [中文用户手册](MANUAL_ZH.md) — 详细用户手册
- [English README](README.md) — 英文快速开始指南
