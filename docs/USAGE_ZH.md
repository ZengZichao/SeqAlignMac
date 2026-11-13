# SeqAlignMac 使用指南

**版本：** 0.1.0 · **读者：** 最终用户（图形界面与命令行） · **文档类型：** 任务导向使用文档

> **语言说明：** 本系列的权威版本是英文 [USAGE.md](USAGE.md)。本中文版本与英文版逐节对应；如有任何出入，以英文版为准。文档索引见 [README.md](README.md)，技术说明文档中文版见 [DOCUMENTATION_ZH.md](DOCUMENTATION_ZH.md)。

本指南告诉你*如何把事情做完*：该打开哪个菜单、该选哪个选项，以及屏幕上的那些数字到底意味着什么。
架构、格式规范、指标推导和已知限制清单都写在 [`DOCUMENTATION_ZH.md`](DOCUMENTATION_ZH.md) 里；本指南只链接它，
不重复它。

---

## 目录

1. [如何使用本指南](#1-如何使用本指南)
2. [开始之前](#2-开始之前)
3. [快速上手（五分钟）](#3-快速上手五分钟)
4. [打开文件](#4-打开文件)
5. [界面总览](#5-界面总览)
6. [阅读比对](#6-阅读比对)
7. [编辑比对](#7-编辑比对)
8. [搜索](#8-搜索)
9. [分析工作流](#9-分析工作流)
10. [外部比对器](#10-外部比对器)
11. [导出](#11-导出)
12. [偏好设置](#12-偏好设置)
13. [键盘快捷键](#13-键盘快捷键)
14. [命令行用法](#14-命令行用法)
15. [实战配方](#15-实战配方)
16. [故障排查与常见问题](#16-故障排查与常见问题)
17. [获取帮助与已知限制](#17-获取帮助与已知限制)

---

## 1. 如何使用本指南

- 第 2–5 节是环境准备与界面认知，读一遍即可。
- 第 6–12 节是各项功能任务，每节开头都给出菜单路径，方便你直接切入。
- 第 13–14 节是参考表格（快捷键、CLI 选项）。
- 第 15–16 节是端到端的完整工作流演练，以及对报错信息的解答。

菜单标签按界面显示原样引用，采用 `文件（File）▸ 打开文件…（Open File…）` 的写法。键盘符号：
⌘（Command）、⇧（Shift）、⌥（Option）、⌃（Control）。

有少数界面字符串即使在使用英文界面时也仅有中文（画布工具提示、图像导出错误、CLI 进度行）。
凡是这一点会影响你的工作流的地方，本指南都会明确说明。

---

## 2. 开始之前

### 2.1 系统要求

| 要求 | 数值 |
|---|---|
| 操作系统 | macOS 14.0 或更高版本（以 `LSMinimumSystemVersion` 声明，同时也是 SwiftPM 的平台下限） |
| 处理器架构 | **仅支持 Apple Silicon（`arm64`）。** 发布构建不含 `x86_64` slice，因此不是通用二进制；预构建压缩包不支持 Intel Mac |
| 显示器 | 无特殊要求；默认窗口为 1500 × 880 pt，最小尺寸 1100 × 520 pt |
| 磁盘 | 数十 MB 量级，用于程序包与发行 zip |

### 2.2 获取应用

从本仓库的检出目录构建：

```bash
chmod +x build.sh          # some checkouts lose the executable bit
bash build.sh              # or: ./build.sh
```

如果 `./build.sh` 报 "permission denied"，说明检出时文件的可执行权限位没有被恢复；请执行一次
`chmod +x build.sh`，或者像上面那样通过 `bash` 调用它。

常用参数（任何其他参数都会被静默忽略）：

```bash
./build.sh --open          # launch the app when the build finishes
./build.sh --skip-tests    # skip the unit-test gate
```

构建会按顺序执行若干阶段：先把之前的程序包移到一边，组装 `.app` 骨架，拷贝 `Info.plist`，
**在** `swift` 工具链和 XCTest 模块可用时运行 `swift test`（在只安装了 Command Line Tools
的机器上会打印一条警告并继续），用 `swiftc -O -target arm64-apple-macosx14.0` 编译 `Sources/`
下的每一个文件，生成应用图标，拷贝 `logo.svg` 和隐私清单，对程序包做代码签名，打包成 zip，
并可选地进行公证。

构建产物生成在脚本旁边，也就是仓库根目录：

| 产物 | 内容 |
|---|---|
| `SeqAlignMac.app` | 应用程序包（`Contents/MacOS/SeqAlignMac` 是可执行文件，它同时也是 CLI） |
| `SeqAlignMac.app.zip` | 可分发压缩包，由 `ditto -c -k --keepParent` 生成 |

两者都是被 git 忽略的构建产物。CI 会把同一个 zip 作为名为 `SeqAlignMac-app` 的 artifact 上传
（保留 14 天）；没有 `.dmg` 镜像，也没有 Homebrew cask，因此从源码构建或使用 CI artifact 就是你
获得本应用的方式。

### 2.3 签名、Gatekeeper 与首次启动

除非你在构建前导出了 `DEVELOPER_ID`，否则脚本会退回到 **ad-hoc 签名**
（`codesign --force --deep --sign -`），而公证只有在 `DEVELOPER_ID` 和
`NOTARY_PROFILE` *两者*都设置时才会执行。所以你在本地构建出的应用是 ad-hoc 签名、未经 Apple
签名的——这是预期情况，不是缺陷。

实际意味着：

- **本地从源码构建：** Gatekeeper 不会提出警告，因为该程序包从未带上隔离属性。双击
  `SeqAlignMac.app` 即可启动。
- **以 `SeqAlignMac.app.zip` 下载**（来自 CI artifact 或文件共享）：macOS 会为其打上
  `com.apple.quarantine`，因此首次启动可能被拦截，提示 "cannot be opened because the developer
  cannot be verified" 或 "damaged"。用下列任一方式解决：
  1. 在 Finder 中右键（或 Control-点击）应用 ▸ **打开（Open）** ▸ 在确认对话框中再点 **打开（Open）**。
  2. 系统设置（System Settings）▸ 隐私与安全性（Privacy & Security）▸ **仍要打开（Open Anyway）**，需在拦截提示出现之后。
  3. 从终端清除隔离属性：`xattr -dr com.apple.quarantine SeqAlignMac.app`。
- 启动前先核验你收到的内容：

  ```bash
  codesign --verify --verbose SeqAlignMac.app
  spctl -a -vv SeqAlignMac.app     # an ad-hoc build is intentionally rejected by spctl
  ```

hardened runtime 与 app-sandbox 权限默认*不*启用；沙箱需要在签名时显式开启
（`SEQALIGN_SANDBOX=1`），而一旦开启就会禁止启动外部比对器的可执行文件。

在第一次启动时，SeqAlignMac 会显示一个一次性提示浮层，告诉你文件可以拖放到窗口上，并且工具按钮
位于侧边栏。窗口以 1500 × 880 pt 打开；你可以把它缩小到最小 1100 × 520 pt。

---

## 3. 快速上手（五分钟）

把这七个步骤完整走一遍；每一步只涉及一个界面。

1. **打开文件。** 选择 文件（File）▸ 打开文件…（Open File…）（⌘O），选中 `alignment.fasta`，
   点击 **打开（Open）**。大文件会显示 "Parsing file… N %" 覆盖层并带一个取消按钮；它消失后画布
   就绪。也可以把文件拖到窗口上，或运行
   `open -a SeqAlignMac alignment.fasta`。
2. **查看画布。** 冻结的名称列在左侧，顶部是一条细窄的保守度轨道，其下是列标尺，然后是残基网格，
   共识序列行位于标尺下方。右侧面板已经显示实时统计；底部状态栏显示序列数、列数、光标位置、
   光标下的残基、列一致度和数据类型。
3. **滚动。** 使用始终可见的横向与纵向滚动条，或者使用滚轮。向右滚动时，序列名称保持在左侧固定。
4. **选择区域。** 在单元格上拖动可建立矩形选区，或按住 ⌥ 拖动可整列选择。按 Esc 清除选区。
   ⌘A 选择整个比对。
5. **切换配色方案。** 选择 视图（View）▸ Okabe-Ito（色觉无障碍）（Okabe-Ito (CVD-safe)），或按
   ⇧⌘5。`⇧⌘1` 会让你回到 极简（Minimal），即内置的默认方案。
6. **导出 PNG。** 按 ⇧⌘E 打开 导出预览（Export Preview），检查预估尺寸，点击 **导出…（Export…）**，
   然后选择目标位置。（或者用 文件（File）▸ 导出为 PNG（Export as PNG）跳过预览。）
7. **在命令行转换文件。**

   ```bash
   SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus -o alignment.nexus
   ```

从这里开始，第 4 节及以后会详细讲解每一项任务。如果你只是想要拿一份用于流水线的比对统计，运行
`SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli stats alignment.fasta --out stats.csv`。

---

## 4. 打开文件

### 4.1 支持的格式与扩展名

SeqAlignMac 可以读写七种比对格式。压缩是透明处理的，因此下列任何扩展名也可能以 `…fasta.gz`、
`…nex.gz` 等形式出现。

| 格式 | 打开面板显示的扩展名 | Bundle 中声明的常见附加扩展名 | 说明 |
|---|---|---|---|
| FASTA | `.fasta`, `.fa`, `.fas` | `.fna`, `.faa`, `.mpfa` | 这三个附加扩展名是为 Finder 声明的，并**不**在打开面板的列表里；请把这类文件拖放到窗口上 |
| FASTQ | `.fastq`, `.fq` | — | Phred 质量会被解析并保留 |
| NEXUS | `.nexus`, `.nex` | — | `DATA`/`CHARACTERS` 矩阵加上 `SETS`/`CHARSET` |
| PHYLIP | `.phy`, `.phylip` | — | sequential、interleaved、strict-10 与补空名称四种排版会被自动区分 |
| CLUSTAL | `.aln` | — | 也接受 MAFFT 那种无表头的输出 |
| MSF | `.msf` | — | GCG 多序列比对格式 |
| Stockholm | `.sto`, `.stockholm` | — | Pfam/Rfam 风格 |
| Gzip 归档 | `.gz` | — | 以查看器方式打开，解包为其中所含的比对格式 |

格式是由**内容的前 64 KB**判定的，而不是文件名，因此名为 `data.txt` 的 FASTA 文件仍能正确打开，
扩展名标错通常也无害。如果嗅探出的格式无法识别，SeqAlignMac 会退回到 FASTA 解析。

### 4.2 打开方式

1. 文件（File）▸ 打开文件…（Open File…）（⌘O）。
2. 把文件拖到窗口上：第一个拖入的文件替换当前标签页，之后每一个文件各自新建一个标签页。
3. 在终端运行 `open -a SeqAlignMac alignment.fasta`。
4. 当应用已注册该文档类型后，在 Finder 中双击文件。
5. 文件（File）▸ 打开最近（Open Recent）——最近十个路径，已不存在的会灰显。
6. 内置演示数据：帮助（Help）▸ 加载示例数据（Load Example Data），或侧边栏 文件（File）分组中的
   **示例（Example）** 按钮，会载入一个只有四条序列的小型比对，方便你在打开真实数据之前先探索。

### 4.3 压缩输入

- 解压缩是**以 `.gz` 扩展名为准**的：名为 `alignment.fasta` 的 gzip 数据不会被解压缩。若需要它被
  解压缩，请把它改名为 `alignment.fasta.gz`。
- 单成员 gzip 与多成员 **BGZF** 流（`bgzip` 产生的分块格式）都被接受，因此 bgzip 压缩的 FASTA
  可以一次打开。
- 对于 `cat a.gz b.gz > both.gz` 这类简单拼接，程序会**明确报错拒绝**，而不是读一半。请正确解压后
  重新 gzip，或分别打开其中的各个成员。
- 用 ⌘S 保存会保持原有的压缩方式（`.gz` 源文件会重新 gzip）。**另存为（Save As）** 则写出未压缩的
  副本。

### 4.4 坏输入是错误，绝不静默截断

SeqAlignMac 会报告格式错误的文件，而不是打开一个不完整的比对。你会看到诸如
"illegal character 'x' at line N"、"PHYLIP data lines fewer than declared `ntax`"、"sequence X has no
residues"、"MSF: sequence X length disagrees with the `Len:` header"、"FASTQ quality line length does not
match the residue line" 以及 "no records parsed" 这类信息。因此一个能打开但看起来不对的文件，更可能的
原因是真正的格式不匹配，而不是解析器的缺陷。（其中一些字符串目前只有中文；见第 16 节。）

### 4.5 长度不齐与未比对的输入

如果文件中的序列长度不一致，SeqAlignMac 会用 `-` 在右端补齐，好让画布能渲染出一个矩形，同时记录
该文件的来源信息：

| 来源信息 | 含义 |
|---|---|
| `aligned` | 等长的行且至少含一个内部空位——各行确实逐列同源 |
| `unknown` | 等长但没有内部空位（与无空位的比对无法区分），或输入为空 |
| `not-aligned` | 行的长度各不相同——跨列的同源关系**不**成立 |

当来源信息为 `not-aligned` 时，右侧统计面板会显示橙色提示条，警告列统计和系统发育树不可靠，你应当
先做比对。**分析功能并不会被禁用**——你仍然可以打开序列 Logo、NJ 树、滑动窗口图和比对质量报告；
应用只是告诉你这些数字不可信。同一个值也会由 CLI 以 CSV 字段 `declared_aligned` 导出。
要修正数据，请运行外部比对器（第 10 节）。

### 4.6 大文件

- 画布是虚拟化的：只绘制可见矩形内的行与列，重绘也只限于新露出的那一条区域，因此滚动开销与比对的
  总大小无关。
- 解析在后台执行，带百分比覆盖层和一个取消按钮。
- 画布所需的列统计在非主线程计算；如果尚未就绪，画布会退化为无着色单元格，而不是卡住不动。统计面板
  会在其计算完成时刷新。
- 由于从未实测过，因此没有公布任何序列数量的容量指标。对于无人值守的超大任务，优先使用 CLI
  （第 14 节），它完全没有渲染开销。

### 4.7 每种格式在往返转换中会失去什么

请在你了解代价的前提下进行转换或重新保存。以下信息无法保留：

| 格式 | 写出时丢失或被改动的内容 |
|---|---|
| FASTA | 质量值（请改用 FASTQ）；除第一个空格之后的自由文本描述之外的结构化表头字段。写出时每序列一行：库支持行折叠（`wrapWidth`），但**没有任何 GUI 或 CLI 选项把它暴露出来** |
| FASTQ | 空位补齐的列其质量为 `!`（Q0）；写出时高于 Phred 93 的质量会被**钳制**；`+` 行从不重复表头；读段组/`B` 标签不会被解析 |
| NEXUS | `DATA`/`CHARACTERS` 与 `SETS` 之外的一切：`[...]` 注释、`FEATURES`、`TREES`、`ASSUMPTIONS`、`LABELS`、`STATES`、`SYMBOLS`、`PARTITIONS`、`&` 注解，以及逐字符的状态频率。比对元数据**从不**保留（写入器的 `includeMetadata` 开关只控制 `SETS` 块）。名称是被补齐而非被截断。注意：与其余格式不同，`.` 在 NEXUS 矩阵中不是可接受的空位字节 |
| PHYLIP | **序列名称被截断为 10 个字符**（在 strict/sequential 排版中为 9 个），重名会就地用 `.1`、`.2`、… 消歧；描述被丢弃；空位写法统一为 `-`；sequential 与 interleaved 只能靠启发式恢复。库中存在四种写入变体，但应用和 CLI 始终写出 interleaved 形式 |
| CLUSTAL | 应用不写保守度行（该选项只存在于库中）；块结构按 60 列重写 |
| MSF | `Weight:` 恒为 `1.00`；真实 GCG 输出中的 reference/rank 行会被忽略；写入器在 `MSF:` 与 `Check:` 两处都输出 GCG 校验和（按位点加权，mod 10000） |
| Stockholm | `#=GC RF` 会被解析**然后丢弃**——参考共识无法往返；不读取逐序列的 `#=GS` 注解；只有 `#=GF ID`、`AC` 与 `SQ` 会被涉及；`#=GF SQ` 会被写出但从不读回；名称中的空格会被替换为 `_` |

除 NEXUS 矩阵解析器外，所有格式在解析时都会把空位写法 `.`、`~` 和 `-` 归一化为 `-`，因此
`GAP=.` 的 NEXUS 文件会以 "illegal character `.`" 报错失败。

---

## 5. 界面总览

### 5.1 三个面板

每个窗口都有三个始终可见的区域；没有浮动工具栏，按钮都放在侧边栏里。

- **左侧侧边栏**（默认宽度 180 pt，限定在 150–320 pt），分为 `文件（File）`、`序列分析（Analysis）`、
  `视图（View）`、`导出（Export）`、`系统（System）` 五组：打开（Open）、保存（Save）、示例（Example）；
  对齐（Align）、翻译（Translate）、引物（Primer）、质量（Quality）、Logo、NJ 树（NJ Tree）、
  窗口（Window）、注释（Annot）；配色方案（Color Scheme）选择器、差异（Diff）开关、搜索（Search）、
  撤销（Undo）、重做（Redo）、缩放控件；导出（Export）▸ 序列（Sequence）/图像（Image）；
  底部是设置（Settings）、命令（Command）、外观（Appearance）与语言（Language）按钮。对于蛋白数据，
  **翻译（Translate）** 与 **引物（Primer）** 会被禁用，工具提示为 "Only applicable to nucleotide
  sequences"。
- **中央画布**：冻结的名称列、保守度轨道、列标尺、残基网格，以及共识序列行。
- **右侧统计面板**（默认 264 pt，限定在 220–460 pt）：实时的质量、系统发育和保守度指标，共识序列，
  光标信息，以及指标定义脚注。

拖动面板之间的竖直分隔条即可调整宽度；两个宽度都会在启动之间保留。画布内部的名称列分隔条同样可以
拖动（80–2000 pt，默认 150 pt），那个宽度也会被记住。

### 5.2 标签页与窗口

每个窗口的标题栏都带一条标签页栏。**每个标签页各自持有一个比对，并各自拥有自己的撤销栈。**
有未保存改动的标签页以 `• ` 前缀标示，并在鼠标悬停或处于活动状态时显示 ✕。只有最近使用的三个标签页
保留其活动状态；其余在你切回去时会重建，因此一个非近期标签页会丢失临时选区，但不会丢失已保存的数据。

这是最容易混淆的一点，所以直说：

| 按键 | 关闭的对象 |
|---|---|
| ⌘W | **标签页**（文件（File）▸ 关闭标签页（Close Tab））；关闭某窗口中的最后一个标签页会关闭该窗口 |
| ⇧⌘W | **窗口**（文件（File）▸ 关闭窗口（Close Window）），连同其中每一个标签页 |

⌘T 新建标签页，⌘N 新建窗口。关闭有改动的标签页或窗口会弹出一个表单，提示 "… has unsaved edits.
Save?"，并提供 **保存（Save）**、**不保存（Don't Save）**、**取消（Cancel）**。只要任何地方存在有改动的
文档，退出程序时就会弹出系统对话框，提供 **保存并退出（Save and Quit）**、**不保存（Don't Save）**、
**取消（Cancel）**；如果其中任何一次保存失败，退出就会被中止，以免丢失内容。

### 5.3 状态栏

从左到右依次为：序列数（`Seqs`）、列数（`Cols`）、以 `row, column` 形式表示的光标位置、
光标下的残基（`Residue`）、光标处的列一致度（`Identity`，取整数百分比）、数据类型
（`Type`：核酸或氨基酸）、一个 **`Charset`** 字段——当文件含有 NEXUS `CHARSET` 分区时显示其数量
（该字段的标签按实现就是英文的），最右侧是文件名加一个 `●` 未保存标记，或者 `未打开文件（No file open）`。
有任务正在执行时，状态栏会显示带转圈动画的保存/导出指示器。把鼠标停在文件名上，工具提示会显示完整路径。

### 5.4 命令面板

按 ⇧⌘P（工具（Tools）▸ 命令面板（Command Palette））打开它。它列出 32 条命令——打开/保存、
运行外部比对器、翻译、引物、质量、搜索、复制、全选、反向互补、插入空位、删除/重命名/移动序列，
七种配色方案中的六种，放大/缩小/重置缩放，显示/隐藏共识序列，浅色/深色/跟随系统，设置，向导，
示例与关于。

在依赖它之前，先了解这两个限制：

- 过滤是对命令标题的**子串**匹配，不是模糊匹配。搜 "gap" 能找到 插入空位（Insert Gap）；搜 "insgap"
  则什么都找不到。
- 它**没有** Okabe-Ito 配色方案的条目，也没有任何导出操作、查找下一个/上一个、撤销/重做，以及序列
  Logo、NJ 树、滑动窗口图和注释表单的条目。这些请用侧边栏或菜单（或第 13 节里的快捷键）。

用 ↑/↓ 导航，Return 执行，Esc 关闭。

---

## 6. 阅读比对

### 6.1 七种配色方案

入口：侧栏「视图（View）」分组里的**配色方案（Color Scheme）**选择器、`视图（View）`菜单、画布右键菜单的
`配色方案（Color Scheme）▸`子菜单、偏好设置（Preferences），或下列快捷键。首次启动时默认是极简（Minimal）。

| 方案 | 快捷键 | 按什么着色 | 什么时候选它 |
|---|---|---|---|
| 极简（Minimal） | ⇧⌘1 | 只按保守度着色——依据列一致度的五级灰阶；空位留白 | 你想要一份中性、适合打印的概览，只看哪些列是保守的，而不涉及残基化学性质 |
| 默认（Default） | 无 | 标准核酸类别：A、C、G、T/U、N、空位，以及把所有简并码归为一类 | 日常的核酸阅读；这是其他多数工具所展示的那套调色板 |
| ClustalX | ⇧⌘2 | 理化基团（`AVLIMFW`、`KRH`、`DE`、`NQST`、`CGP`、`Y`），并带**阈值门控** | 与 ClustalX 的截图做对照时 |
| Zappo | ⇧⌘3 | 功能/化学分组（`AVLIMC`、`FWY`、`KRH`、`DE`、`STNQ`、`GP`） | 辨认同一功能类内部的保守替换 |
| SeaView | ⇧⌘4 | 更粗略的四分组简化（`AILMVFWC`、`KR`、`STNDEQGP`、`HY`） | 对蛋白比对做快速的「大致相同/不同」判读 |
| 过渡/颠换（Ti/Tv） | 无 | 嘌呤↔嘌呤与嘧啶↔嘧啶的过渡，对比颠换 | 在核酸数据上做群体与单型分析 |
| Okabe-Ito（色觉无障碍）（Okabe-Ito (CVD-safe)） | ⇧⌘5 | Okabe–Ito 色觉缺陷调色板（Wong 2011） | 投稿与审稿用的图；任何存在红绿色盲的读者 |

值得了解的细节：

- **ClustalX 阈值。** 列一致度低于阈值的列不着色。偏好设置里的滑块范围是 0.1–0.9，步长 0.05，默认值
  **0.3**。这是唯一*不会*持久化的偏好项；每次启动都会回到 0.3。
- **方案与数据类型的兼容性。** ClustalX、Zappo 和 SeaView 是面向蛋白的调色板；把它们用于核酸数据时，
  SeqAlignMac 会静默地按默认（Default）核酸配色渲染；把 Ti/Tv 用于蛋白数据时则按极简（Minimal）渲染。
  这三种方案也是外观不变的（appearance-invariant），所以你的截图与参考工具之间保持可比；极简（Minimal）、
  默认（Default）、过渡/颠换（Ti/Tv）和 Okabe-Ito 则有针对深色模式调校过的变体。
- **配色图例（Color Legend）**弹出面板（侧栏，「视图（View）」分组）会解释当前调色板以及画布手势。

### 6.2 共识行

用 `视图（View）▸ 显示/隐藏共识序列（Show/Hide Consensus）`切换（⇧⌘G——冲突说明见 8.5 节）。共识字符
遵循**共识模式（Consensus Mode）**偏好项：

| 模式 | 输出 |
|---|---|
| 多数规则（Majority Rule） | 该列中出现次数最多的残基（并列时取字母序靠前的那个残基） |
| IUPAC 简并（IUPAC Degenerate） | 覆盖该列观测到的字符集的单个 IUPAC 码（仅核酸；蛋白列退回多数规则） |
| 严格共识（Strict） | 仅当该列完全不变时给出该残基，否则为 `N`（核酸）或 `X`（蛋白） |

该模式**只改变共识字符**。一致度百分比、保守度轨道、着色、池化一致度（位点加权）这个数字以及邻接法系统
发育树始终使用多数规则，所以切换模式不会改变你在多次会话之间比较的任何数值。

### 6.3 保守度轨道

网格上方那条细轨道按列绘制一致度：在极简（Minimal）方案中它是一条五级灰阶；在科研类方案中它取共识残基
的颜色，alpha 透明度与一致度成正比，并在完全保守的列上再加一个亮色顶帽。**在轨道上点击或拖动**即可扫动
定位：画布会把那一列滚动到视口正中，这是沿长比对快速跳转的最快办法。

### 6.4 差异模式

在侧栏「视图（View）」分组里打开**差异（Diff）**。在你启用它的那一刻，与光标所在行相同的残基会以不带
背景填充的方式绘制，于是相对那条参考行的变异就凸显出来。参考行就是当时光标所在的那一行；移动光标并重新
开关一次即可更换参考行。差异模式和参考行都**不会持久化**——两者在下次启动时重置。

### 6.5 缩放，以及字母为什么会消失

| 操作 | 方式 |
|---|---|
| 放大 | ⌘=（也提供 ⌘+ 入口）、「视图（View）」分组里的 **+** 按钮、⌘ 滚轮向上，或捏合手势 |
| 缩小 | ⌘-、**−** 按钮、⌘ 滚轮向下，或张合手势 |
| 重置 | ⇧⌘0，它把字体恢复到 13 pt（显示为 100 %） |
| 范围 | 8–28 pt；该设置会持久化 |

列宽由等宽字体中字符的实测前进宽度（advance width）推导而来，因此它随字号线性增长。**当每列宽度低于大约
6 px 时，画布就完全不绘制字母，只绘制色块。**这是有意为之：在那个密度下字形会相互重叠而无法辨认，而色块
仍然承载完整的一致度与调色板信息。这是我们经常收到的一个求助问题，解决办法很简单，就是放大（按几次 ⌘=，
或 ⇧⌘0）。行高不受这个开关影响，所以字母消失时你截图的纵向节奏并不会改变。标尺每十列显示一个数字，并会
按需缩小自己的字体，以保证四位和五位数字位置清晰可读。

### 6.6 选取

| 选区 | 手势 |
|---|---|
| 单个单元格（光标） | 点击某个单元格，或用方向键移动 |
| 矩形块 | 在单元格上拖动 |
| 整列 | ⌥ 拖动 |
| 整个比对 | ⌘A |
| 清除 | Esc |

复制（⌘C）会把选中的块以 FASTA 输出。「仅导出选中区域（Export selection only）」会忽略单个的光标单元格——
单击之后并不存在活动选区，所以只有在真正拖动过之后才勾选该选项。

---

## 7. 编辑比对

所有编辑都记录在各自标签页的撤销栈上。

### 7.1 序列级操作

| 任务 | 入口 | 效果 |
|---|---|---|
| 重命名序列 | ⇧⌘R、双击它的名称、`编辑（Edit）▸ 重命名序列（Rename Sequence）`，或画布右键 | 一张只有一个输入框的表单（sheet）；该改动是一个撤销步 |
| 重新排序序列 | 在名称列中上下拖动它的名称（会出现插入位置指示线），或 `编辑（Edit）▸ 移动序列…（Move Sequence…）`，或右键 ▸ `移动到顶部（Move to Top）` / `移动到底部（Move to Bottom）` | **移动序列（Move Sequence）没有键盘快捷键** |
| 删除序列 | 光标在该行上时按 ⇧⌘X（`编辑（Edit）▸ 删除选中序列（Delete Selected Sequence）`） | 被删除的行可以由撤销恢复 |
| 添加序列 | 画布右键 ▸ `添加序列…（Add Sequence…）` | 需要时补齐到当前宽度 |
| 反向互补 | ⌘I，或右键 | 仅适用于核酸数据；在蛋白数据上该命令什么都不做 |
| 排序 | 右键 ▸ `排序方式（Sort By）`：按名称排序（Sort by Name）、按与共识相似度排序（Similarity to Consensus）、按 GC 含量排序（GC Content）、按序列长度排序（含空位）（Length (with gaps)）、按序列长度排序（不含空位）（Length (no gaps)） | 排序在后台执行；如果你在排序过程中编辑，过时的结果会被丢弃并重新计算 |
| 粘贴 | ⌘V | 若剪贴板内容中含有 `>`，就按 FASTA 解析；否则每个非空行成为一条名为 `Pasted_N` 的序列。无法识别的剪贴板内容会抛出「Cannot parse clipboard: please paste FASTA or raw sequences」（无法识别剪贴板内容：请粘贴 FASTA 或纯序列） |

### 7.2 列操作

| 任务 | 入口 | 细节 |
|---|---|---|
| 插入空位列 | ⌘D | 在光标位置插入一个空位列 |
| 剪切 | ⌘X | 画布存在选区时，「剪切（Cut）」会复制该块**并**在其中填入空位；否则它就是常规的 responder cut。不要指望它删除内容 |
| 去除全空位列 | 右键 ▸ `空位精简（Gap Trimming）▸ 去除全空位列（Remove All-Gap Columns）` | 不含任何可归属残基的列 |
| 去除空位富集列 | 右键 ▸ `空位精简（Gap Trimming）▸ 去除空位富集列 (>50%)（Remove High-Gap Columns (>50%)）` | 空位超过一半行的列 |

删除列的同时会重新映射 NEXUS 的 `CHARSET` 分区，而撤销会恢复原来的分区。

### 7.3 残基级编辑与 IUPAC 输入

**画布里没有文本编辑器**：画布只消费方向键和 Esc，所以你无法往单元格里键入一个新残基，也无法用键盘给
某行加上/去掉包裹。因此残基改动只能通过上面那些整列与整行操作、粘贴一条更正后的序列，或者在你选定的文本
编辑器里修改后重新载入来完成。IUPAC 简并码（`R`、`Y`、`S`、`W`、`K`、`M`、`B`、`D`、`H`、`V`、`N`）在
FASTA、NEXUS、PHYLIP、CLUSTAL、MSF 和 Stockholm 输入中被接受并保留，并且它们参与搜索与统计的方式正如
第 8 和第 9 节所记载的那样。

核心库里确实存在一个批量残基替换命令（并且作为一个步骤整体撤销），但**目前没有任何 GUI 菜单项或 CLI
参数调用它**，所以它不算面向用户的功能。

### 7.4 撤销与重做

| 按键 | 动作 |
|---|---|
| ⌘Z | 撤销 |
| ⇧⌘Z | 重做 |

- 栈受**两项预算**限制：50 个条目**以及** 256 MiB。任一项被超出时，*最旧*的步骤会被丢弃，并且始终至少
  保留一个步骤，以保证最后一次编辑仍可撤销。
- 分组操作（空位精简、排序、由多个部分组成的脚本化编辑）会作为一个**事务（transaction）**记录，并作为
  一个步骤撤销；撤销提示（toast）会报出该事务的名称及其步骤数。
- 执行一次新的编辑会清空重做栈。
- **没有击键合并（coalescing）机制。** SeqAlignMac 不会合并重复的相同编辑，所以 ⌘Z 绝不会把一连串打字
  作为一个整体撤销——唯一的聚合就是那个显式的事务 API。如果你期待的是「撤销最后五个字符」，那个行为并不存在。
- 每个标签页都有自己的栈；切换标签页不会共享也不会清除历史。

---

## 8. 搜索

用 ⌘F（`工具（Tools）▸ 搜索（Search）`）、侧栏的**搜索（Search）**按钮，或命令面板打开搜索栏。

### 8.1 范围与模式

- **范围药丸按钮**：`内容（Content）`搜索残基，`名称（Name）`搜索序列名称（物种或标识符）。
- **正则开关**：在 IUPAC 模式匹配与正则表达式之间切换。
- 输入会防抖 **300 ms** 之后才计算搜索；改动药丸或开关则立即搜索。查询计算期间栏内显示一个加载指示，
  什么都没找到时显示 `0 / 0` 与「无匹配结果（No matches）」。
- ✕ 按钮关闭搜索栏并取消任何待处理的计算。快速输入同样会取消已被取代的搜索，所以过时的结果绝不会覆盖
  较新的结果。

### 8.2 IUPAC 简并模式

在非正则的 `内容（Content）`模式下，简并字母在匹配之前先展开：

| 码 | 匹配 | 码 | 匹配 |
|---|---|---|---|
| `R` | A, G | `B` | C, G, T |
| `Y` | C, T | `D` | A, G, T |
| `S` | G, C | `H` | A, C, T |
| `W` | A, T | `V` | A, C, G |
| `K` | G, T | `N` | A, C, G, T **以及**字面量 `N` |
| `M` | A, C | | |

搜索真实文件时还有两条额外规则要紧：每个码同时也匹配它自身的字面字符（所以查询 `NNN` 既能命中数据里的
`NNN`，而不只是 `ACG`），并且 `T` 与 `U` 被视为等价。不含简并码的普通字母走的是精确匹配器，而且重叠的出现位置也会被报告——在一串五个 `A` 中搜索 `AA` 会给你全部四个位置。

### 8.3 正则模式

启用正则开关后，输入框的占位文字变为 `序列正则（如 A[TC]G{2,}）`（内容范围，原文
`Sequence regex (e.g. A[TC]G{2,})`）或 `名称正则（如 Homo.*BRCA1）`（名称范围，原文
`Name regex (e.g. Homo.*BRCA1)`）。说明：

- 你模式中的字面量会被转成大写以做大小写不敏感匹配，但转义序列与字符类（`\d`、`\w`、`\s`、`\b`、`[...]`）
  保持原样，所以 `\d+` 不会悄悄变成 `\D+`。
- IUPAC 到字符类的展开只应用于**内容（Content）**范围；名称范围的正则看到的就是你原样书写的模式。
- 正则匹配是不重叠的（扫描会越过每个命中继续），这与 IUPAC 路径不同。
- 非法模式会在搜索运行之前被拒绝，提示 `Invalid regex: `（正则表达式无效：）后接你输入的模式，
  并且不报告任何命中。

### 8.4 匹配项跳转

计数器读作 `current / total`。⌘G 跳到下一个匹配项；搜索栏里的**上一个（Prev）**按钮向后退。当前命中以蓝色勾勒、描边更粗，其他命中用细线勾勒，并且每个命中还会在列标尺上以一个刻度标记出来，让你一眼看清
分布。`名称（Name）`范围内的命中会高亮整行。

### 8.5 关于 ⇧⌘G 的注意事项，以及如何触达「查找上一个」

⇧⌘G 在菜单树里被注册了**两次**：一次用于 `视图（View）▸ 显示/隐藏共识序列（Show/Hide Consensus）`，
一次用于 `工具（Tools）▸ 查找上一个（Find Previous）`。视图（View）菜单先于工具（Tools）菜单构建，所以
共识序列开关胜出，而**查找上一个实际上无法通过键盘触达**。不要把从别的编辑器继承来的「shift-Cmd-G 就是向后一个」
的肌肉记忆当作依据。要向后退：

1. 点击搜索栏里的**上一个（Prev）**（可靠路径），或
2. 用鼠标在菜单中选择 `工具（Tools）▸ 查找上一个（Find Previous）`。

命令面板只把 ⇧⌘G 列在「显示/隐藏共识序列（Show/Hide Consensus）」之下，并且完全没有任何 Find 条目，
所以它也不是通往「查找上一个」的路径。

---

## 9. 分析工作流

下面每一小节都是一个任务：先说点哪里，再说这些数字是什么意思。

### 9.1 值得信赖的质量统计

一共有三块不同的统计界面，它们显示的行并不相同。

**A. 实时统计面板（右侧，始终可见）。** 卡片自上而下：

1. `比对概览（Overview）` — 文件名、格式、序列数、列数、数据类型。
2. `质量指标（Quality）` — 需要时先显示未比对横幅，然后是**池化一致度（位点加权）**（Pooled identity
   (site-weighted)）、平均 / 最差 / 最佳列一致度、含空位列数、总列数。
3. `系统发育信息量（Phylogenetic Information）` — 变异位点数（Variable Sites）、简约信息位点数
   （Parsimony-Informative Sites）、单态位点数（Singleton Sites）。
4. `保守度分布（Conservation）` — 列一致度的五档直方图（颜色更深的柱 = 更保守）以及高保守列（≥80%）
   （High conserved (≥80%)）计数。
5. `共识长度（Consensus length）` — 共识序列、它的长度**以列数表示**，以及一个复制（Copy）按钮。
6. `测序质量（Read Quality）` — 仅对 FASTQ 来源显示：平均 Phred（Mean Phred）、最低 Phred（Min Phred）、
   ≥Q20 碱基占比（≥Q20 bases）、≥Q30 碱基占比（≥Q30 bases）。
7. `光标位置（Cursor）` — 光标处的位置、残基与一致度。
8. 一个页脚，定义每一项指标。

**B. 质量报告表单（Quality report sheet）** — `工具（Tools）▸ 比对质量评估（Alignment Quality）`（侧栏
**质量（Quality）**按钮）。它显示池化一致度（位点加权）、最差/最佳列一致度、含空位列数、总列数、共识长度、存在质量
数据时的 FASTQ 各行，以及 NEXUS `CHARSET` 名称列表。它**不**显示 GC 含量，也**不**显示变异/简约信息/
单态位点的计数——那些只存在于实时面板里以及 CLI 的 CSV 里。

**C. CLI 的 CSV**（`cli stats`）— 覆盖面最广的一组，包含 `gc_content` 与 `declared_aligned`。

以下是那些主要数字的计算方式，好让你在论文的方法部分能正确描述它们：

- **列一致度（column identity）** `I = (count of the most frequent residue) / (number of assignable residues in the
  column)`。分母排除空位**以及**未判定状态（`N`、`X`、`?` 及其蛋白等价符号）。整列为空位或整列未判定的列
  得分是 **0**，不是 1。
- **含空位列（Gap columns）**的含义是「完全没有可归属残基的列」：全空位列**以及**全为 `N`/全为 `X`/全为 `?`
  的列。面板上的标签「Gap columns」（以及较早的中文标签「含空位列数」，即 "columns containing gaps"）对它的描述并不
  充分；不要把它读作「含有任何空位的列」。
- **池化一致度（位点加权）**（Pooled identity (site-weighted)）并*不是*所有成对序列一致度的平均值。
  形式上 `Σ_columns Σ_residues f·(f−1) / Σ_columns n·(n−1)`：对每一列，它累加「从该列取出两个残基恰好匹配」
  的概率，并按该列实际拥有的可比残基数加权。后果是：它的表现像一个按位点加权的平均，所以某个同名指标如果
  出自一个对每对一致度取平均的工具，会给出略微不同的数字。精确的按对（per-pair）实现在库里是存在的，但在
  UI 或 CLI 的任何地方都没有暴露出来。
- **位点（Sites）**只按已定义残基计数：*变异位点（variable site）*有两种或更多种不同的已定义状态；
  *简约信息位点（parsimony-informative site）*还额外要求至少两种状态各出现两次或更多次；*单态位点
  （singleton site）*是指最常见状态的出现次数恰好比总次数少一（即一个自衍征，autapomorphy）、且该位点不是
  简约信息位点。
- **FASTQ 质量**在所有带质量信息的读段的全部碱基上合并计算：`Mean Phred = Σq / total bases`、
  `Min Phred`（没有质量数据时报告为 0）、`Q20 ratio = #{q ≥ 20} / total bases`、
  `Q30 ratio = #{q ≥ 30} / total bases`。这些比值是按**碱基**计算的，不是按读段；读段数是携带质量信息的
  行的数目。

位点计数在**所有**行上计算；9.3 节描述的 200 条序列抽样只适用于邻接法系统发育树。每次编辑后统计会在后台
重新计算，所以一个繁忙的文件可能短时间显示略微滞后的数字。

### 9.2 序列 Logo

1. 点击侧栏「序列分析（Analysis）」分组中的 **Logo**。
2. 用 ‹ / › 在比对中翻页；每页绘制 120 列，并且每十列标注一次列位置。
3. 读取高度刻度：纵轴上限对核酸为 2.0 比特，对氨基酸为 4.3 比特。

解读：每个字栈的总高度就是信息含量 `R = log2(K) − (H + e(n))`（Schneider–Stephens 1990），其中 `K` 对
核酸为 4、对氨基酸为 20，`H` 是该列的香农熵，`e(n) = (K − 1) / (2·ln2·n)` 是对 `n` 个观测残基的小样本
校正。单个字母按其在该列中所占的比例缩放。空位被排除在外，而模糊残基**不会**被按比例重新分配——只有可归属
状态参与计数，所以一个 `N` 很多的列看起来比它的原始变异度所暗示的信息量更低。

长比对有上限：计算器在 **4,000 列**之后停止，表单会打印一条省略列数的提示（「序列 Logo 仅计算前 4000 列，
省略列数：」）。如果你的 Logo 说它被截断了，那就只翻到你真正关心的那一小段（第 14 节的
`convert --start/--end` 正是为此产出一个很小的文件）。

### 9.3 邻接法系统发育树

1. 点击「序列分析（Analysis）」分组中的 **NJ 树（NJ Tree）**。
2. 等待窗格里出现 Newick 字符串；标题会报告是否发生了抽样。
3. 点击**复制 Newick（Copy Newick）**，把它粘贴进你的树查看器（它是纯文本；SeqAlignMac 自己没有绘制树
   的画布）。

方法与注意事项（以代码的实际实现为准）：

- 距离是**未校正的 p 距离（p-distance）**：`d = 1 − matches / comparable`，其中某个位置可比（comparable）
  仅当两个字节都不是空位**且**都不是 `N` 或 `X`。没有任何可比位点的一对序列被赋予 `d = 1.0`。不施加
  Jukes–Cantor 或 Kimura 校正，因此这棵树只适合**近缘、低分化**的序列。表单里写明了这条免责声明；请把它
  当作约束条件看待。
- 超过 200 条序列时，输入会**按等间隔步长抽样为 200 条序列**，而不是按文件顺序取前 200 条。（应用内一段
  较早的文字暗示「前 200 条」；抽样器取每 `n/200` 条序列，那才是那句披露的含义。）
- Newick 在根部带一条 NHX 风格的来源（provenance）注释，形如
  `[&sampled=<used>_of_<total>;model=p-distance;clamped=<n>]`。归档这棵树时请保留它，并留意某些下游工具会
  拒绝或剥掉注释。
- 负分支长度会被**钳为 0**，被钳零的分支数目会在屏幕上以及在那条注释中报告——数量很大说明 p 距离对你的
  数据而言过于粗糙。
- 两条序列的输入会被精确处理（两个末端各分得成对距离的一半）；一条或零条序列则给出一棵平凡的树。末端
  名称在写出之前会做唯一化处理。
- 分支长度以五位小数打印。

编辑比对会把这棵树标记为脏，因此重新打开表单时它会重新计算。

### 9.4 滑动窗口一致度

1. 点击「序列分析（Analysis）」分组中的 **窗口（Window）**。
2. 拖动**窗口宽度（Window size）**滑块（5–500 列，步长 5；默认 50）。

图表对窗口内的每列一致度取平均，并把它对真实的窗口中心点绘制；网格线标出 0/25/50/75/100 %。步长是半个
窗口，因此相邻点是重叠的，并且总会输出最后一个短窗口以覆盖到最后一列。用它来一眼定位保守区块（候选引物
或探针区域）与可变片段（候选基因分型区域）。每列一致度向量是有缓存的，所以拖动滑块开销很小，不会重新扫描
整个比对。

### 9.5 六阅读框翻译

1. 点击「序列分析（Analysis）」分组中的 **翻译（Translate）**，或按 ⇧⌘T
   （`工具（Tools）▸ 翻译为氨基酸（Translate to Amino Acid）`）。
2. 选择一张遗传密码表、一个阅读框、一种显示模式、名称处理方式以及结果是否在新窗口打开；然后按 Return
   或点击**翻译（Translate）**。
3. 读取控件下方出现的那行警告；多条警告以「 · 」连接起来。

**遗传密码表（已实现 17 张）。** 选择器按 NCBI 编号列出各张表，并附一个简短的英文标签（例如
`Standard (1)` … `Peritrich Nuclear (30)`）；这些标签是源码里的字面量，未做本地化。下面列出的编号与惯用的
NCBI 名称就是选择器所覆盖的那些表：

| NCBI 编号 | 密码子表 | NCBI 编号 | 密码子表 |
|---|---|---|---|
| 1 | The Standard Code | 11 | The Bacterial and Some Plastid Codes |
| 2 | The Vertebrate Mitochondrial Code | 12 | The Alternative Fungal Yeast Code |
| 3 | The Yeast Mitochondrial Code | 13 | The Ascidian Mitochondrial Code |
| 4 | The Mold Mitochondrial and Some Protozoan Codes | 14 | The Alternative Flatworm Mitochondrial Code |
| 5 | The Invertebrate Mitochondrial Code | 15 | Blepharisma Nuclear Code |
| 6 | The Ciliate and Some Dinophyte Codes | 16 | The Chlorophycean Mitochondrial Code |
| 9 | The Echinoderm and Flatworm Mitochondrial Code | 24 | The Rhabdopleurida Mitochondrial Code |
| 10 | The Euplotid Nuclear Code | 25 | The Candidate Division SR1 and Gracilibacteria Codes |
| 30 | The Peritrich Nuclear Code | | |

其他任何 NCBI 编号都不在提供之列；不会静默回退到标准遗传密码表。

**阅读框。** 选择器显示 −3、−2、−1、+1、+2、+3。负阅读框先对序列做反向互补，然后从偏移量
（`|frame| − 1`）开始；正阅读框在内部对 +1、+2、+3 分别从偏移 0、1、2 开始。以比对的列作为参照坐标系，
所以 +1 从第一列开始。

**显示模式。**

| 模式 | 输出 | 结果的数据类型 |
|---|---|---|
| 单密码子（Codon only） | 经过阅读框调整的核苷酸序列 | 核酸 |
| 氨基酸码（Amino acid） | 每个密码子一个残基 | 氨基酸 |
| 两者（Both） | 密码子与氨基酸交错，三个碱基后接一个残基 | 核酸，但被标记为混排轨道 |
| 忽略空位（Ignore gaps） | 翻译之前先去除空位 | 氨基酸，来源（provenance）重置为 `unknown` |

**名称处理。** 保留原名称，或追加 `_AA` 后缀。**在新窗口打开结果（保留当前比对）**默认开启，这样会保留
当前的比对；关掉它则就地替换掉比对，而这次替换可以用 ⌘Z 撤销（提示语会这么说明）。

**警告，以及它们对下游工作的含义：**

| 警告 | 含义 |
|---|---|
| 移码（Frameshift） | 一段内部空位、其长度不是 3 的倍数，会使下游阅读框相位错位；从那个密码子起输出为 `X`，消息会点名序列和列 |
| 长度不是 3 的倍数（Length not a multiple of three） | 翻译前已在右侧用空位补齐比对，以免最后一个密码子被悄悄丢弃 |
| 混排密码子轨道（Mixed codon track） | 「两者」显示模式把核酸与氨基酸字符混在同一条轨道里：仅供显示——不能用于统计或建树，图像导出会拒绝它 |
| 输出行长参差（Ragged output） | 忽略空位模式产生长度不等的行，与源比对列脱钩——不能用于系统发育分析 |
| 输入不是核酸（Not nucleotide input） | 蛋白数据无法翻译；输入原样回显返回 |

混排轨道 / 参差输出 / 移码 / 非核酸输入中的任何一项，都会让结果被明确判定为*不适合系统发育分析*——这个
结论由翻译器计算得出并在表单中呈现。只要密码子里含有空位、密码子不在表内，或者发生在移码之后，氨基酸就是
`X`；SeqAlignMac 从不虚构它无法推导出的残基。

**注意事项：** 应用的字符串表里仍留存着一段较早的「选择密码子位 / 第 1·2·3 位（Select Codon Position /
Position 1·2·3）」条目，但出厂的 UI 里**没有密码子位选择器**。不要去找它；可以用 +1/+2/+3 三个阅读框分别
翻译再相互比较来模拟该功能。

### 9.6 引物计算器

1. 在画布上选择一个行范围并点击**从选区填入（Fill from selection）**（空位会被去除），或者在
   `序列 A：（Sequence A:）`里输入一条序列。要做异源二聚体检查，就填写
   `序列 B（异源二聚体用）：（Sequence B (for heterodimer):）`。
2. 设置盐条件：`Na+`（默认 50 mM）、`Mg2+`（默认 0 mM）、`Oligo`（寡链，默认 0.25 µM）。这三项都会在
   两次启动之间持久化。负数或非数字输入会被拒绝；只敲了一半的数字会被忽略而不是被应用。
3. 按**计算 Tm（Calc Tm）**、**计算 GC%（Calc GC%）**、**自身二聚体（Self-dimer）**或
   **异源二聚体（Hetero-dimer）**。这张表单没有键盘快捷键；可从侧栏**引物（Primer）**按钮、
   `工具（Tools）▸ 引物计算…（Primer Calculator…）`、命令面板或画布右键进入。

这些数字是什么：

- **Tm（熔解温度）**用的是最近邻热力学，配 SantaLucia 1998 的统一参数集，并包含针对 G·C 与 A·T 末端的
  5′/3′ 末端（helix-initiation）校正。结果以区间打印，`Tm ≈ min °C ~ max °C`，因为计算会对一条简并引物的
  **每一个 IUPAC 变体**重复执行；简并展开的上限是 **4,096 种组合**，简并度超过该上限的引物会以计算错误
  失败，而不是返回一个不完整的区间。
- 盐浓度校正走 von Ahsen 1999 路线：有效一价盐浓度取以 mM 计的 `[Na+]`，当存在二价镁时再加上
  `120·√(free Mg)`，其中 `free Mg = [Mg2+] − [dNTP]`（单位 mM）。随后
  `ΔS += 0.368·(n−1)·ln([salt] M)`，且 `Tm = ΔH·1000 / (ΔS_salt + R·ln(C_T/x)) − 273.15`，其中
  `R = 1.987`，自互补（回文）寡链取 `x = 1`，否则 `x = 4`。**面板里没有 dNTP 输入框**，所以在 GUI 中
  `[dNTP]` 恒为零：如果你用 2 mM dNTP 和 1.5 mM Mg²⁺ 跑真实的 PCR，螯合校正不会替你算进去。请通过相应地
  调低你输入的 Mg²⁺ 来把这一项计入，或者在库里自行计算。
- **Wallace 回退。** Wallace 规则 `2·(A+T+U) + 4·(G+C)` 作为一种方法可用；把它当作对短的普通寡链的快速
  合理性检查，而不要当作简并引物所报告的 Tm（面板标注并致谢的是最近邻法）。
- **GC 含量**是 `(G+C) / (A+C+G+T+U)`，以两位小数打印，并且使用与 CLI 的 `gc_content` 相同的分母规则计算，
  所以二者永远不会不一致。
- **二聚体（Dimers）**的打分是在最佳互补的 3′ 后缀/偏移配对上、以 37 °C 下的 ΔG（kcal/mol）给出（最短
  4 个碱基对，链长至少 4 个核苷酸）。任何低于 **ΔG −5 kcal/mol** 的值会被标记「有显著二聚体倾向
  （Significant dimer tendency）」；否则标记「无显著二聚体（No significant dimer）」。输入会被**截断到前
  200 个字符**，所以请粘贴一条寡链，而不是整条扩增产物。

### 9.7 GFF3 注释浏览器

1. 点击「序列分析（Analysis）」分组中的 **注释（Annot）**，然后点**导入 GFF3…（Import GFF3…）**并选择一个
   `.gff`、`.gff3` 或纯文本文件。
2. 读取表格：列依次是 `序列（Sequence）`、`类型（Type）`、`列范围（Columns）`、`名称（Name）`，并且每行
   都有一个**跳转（Jump）**按钮。页脚显示文件名以及解析出的特征数目。
3. 点击**跳转（Jump）**把画布滚动到该特征并高亮它；表单随即关闭。

GFF3 文件中的坐标是 1 起始、并针对**序列残基**取闭区间；浏览器把它们以空位感知（gap-aware）的方式映射到
比对的**列**上，这正是表头写作 `列范围（Columns）`而不是「位置」的原因。目标行的解析顺序是：先按序列名精确
匹配，然后按带冒号后缀的名称，最后按前缀/后缀，因此 GFF 中 `BRCA1` 这样的 `seqid` 可以匹配名为 `BRCA1`、
`BRCA1|transcript_a` 的比对行，或名称以 `BRCA1` 开头或以 `BRCA1` 结尾的行。你可能看到的失败提示：
「Could not read annotation file」（无法读取注释文件）、
「Annotation file parsed 0 features (wrong format or empty)」（注释文件解析结果为空（格式错误或无特征））、
「Sequence not found in alignment: <seqid>」（比对内未找到序列：<seqid>），以及
「The annotated range lies outside this sequence; cannot jump」（注释区间落在该序列残基范围之外，无法跳转）。

**没有任何筛选器。** 没有类型筛选、没有名称搜索、没有坐标范围输入框：你得到的是按文件顺序排列的完整已
解析特征列表，然后自己滚动。如果文件很大，请计划一次只导入一条染色体/一个区域。

---

## 10. 外部比对器

SeqAlignMac 自身不执行序列比对。它调用本地的命令行比对器，然后载入其结果。

1. 按 ⇧⌘B（`工具（Tools）▸ 运行比对（Run Alignment）`），或点击侧栏中的 **对齐（Align）**。
2. 在比对器下拉菜单中选择一个**预设**；命令模板会自动填入输入框，你可以接着编辑它。
3. 点击 **运行（Run）**（或按 Return）。结果会**在新窗口中**打开；你当前的比对保持不变。

### 10.1 四个预设

| 预设 | 命令模板 |
|---|---|
| mafft（推荐） | `mafft --quiet {input}` |
| muscle | `muscle -align {input} -output {output}` |
| clustalw | `clustalw2 -infile={input} -outfile={output} -quiet` |
| 自定义…（Custom…） | 空——请自行输入命令与完整路径 |

### 10.2 `{output}` 规则，以及输出是如何被捕获的

捕获方式由你实际输入的命令推导得出，**不是**由预设名称决定：

- 命令中**包含 `{output}`** → 期望该工具写出这个文件，SeqAlignMac 事后把文件读回来
  （`muscle`、`clustalw`）。
- 命令中**不包含 `{output}`** → 捕获标准输出并解析它（`mafft`）。如果你把 `{output}` 从 muscle
  模板中删掉，得到的会是空结果或无法解析的结果；如果你在一行 mafft 命令里加上 `{output}`，mafft
  根本看不到这个选项，于是运行失败。

占位符 `{input}` 与 `{output}` 会被替换成系统临时目录中的临时 FASTA 路径
（`seqalign_input_<UUID>.fasta`、`seqalign_output_<UUID>.fasta`）；无论运行结果如何，两者都会在
运行结束时删除。如果你的自定义命令**完全没有**使用占位符，比对数据将改为送入该工具的**标准输入**。
命令行在切分时具备引号感知能力，因此 `--anystop "--foo bar"` 这类参数能被完整保留，可执行文件路径
中的 `~` 也会被展开。

临时输入始终以不换行的 FASTA 形式写出，所以需要特定输入格式的工具无法从这个面板直接驱动——
请先转换格式（见 14.4 节）。

### 10.3 查找可执行文件

命令中第一个给出的可执行文件名按以下方式解析：若给的是绝对路径或 `~` 路径就直接用；否则在
`/opt/homebrew/bin`、`/opt/homebrew/sbin`、`/usr/local/bin`、`/usr/local/sbin`、`/usr/bin`、`/bin`
中做 PATH 搜索；再不行就交给 `/usr/bin/which`。若全部失败，你会看到 `未找到比对器：<name>`（`Aligner not found: <name>`）——
请安装该工具，或在输入框里填写完整路径。Apple Silicon 上的 Homebrew（`/opt/homebrew`）已被覆盖，
无需任何 PATH 设置。

### 10.4 超时、取消与超大输出

- 截止时限**可配置**，并非固定值。`偏好设置（Preferences）▸ 比对器超时（Aligner timeout）` 提供
  30–3600 秒、步进 30 秒的取值，默认 **300 s**；实际生效的时限是 `max(10 s, preference)`，因此存储值
  为 0 时会回落到 300 s。面板上的状态文字仍然写着「比对中…（超时 5 分钟自动终止）」（英文界面为 "Aligning… (auto-cancel after 5 min)"），这只在使用默认值时
  成立——如果你改动了该项偏好设置，这句文字不会跟着变。
- 到达时限后先向子进程发送 **SIGTERM**；若 **5 秒后**它仍然存活，再发送 **SIGKILL**。此时你会看到
  `比对超时（5 分钟），已终止。请减小比对规模后重试。`（`Alignment timed out (5 min). Try reducing alignment size.`）
- 点击 **终止（Terminate）** 可以主动取消；本次运行会报告 `已取消比对。（Alignment cancelled.）`
- 标准输出与标准错误在等待进程结束的**同时**被并发排空。正是这一点让大规模比对变得安全：即便某个
  工具写出数 MB 的输出，也不可能把管道缓冲区堵成死锁。即便如此，这个备选做法仍值得保留——应用自身
  占用的内存会随结果规模增长，对非常大的任务，在终端里批量运行更友好。
- 非零退出码会报告为 `比对失败（退出码 N）：<stderr 末尾 ≤200 字符>`（`Alignment failed (exit code N): <last ≤200 characters of stderr>`），这通常是
  调试自定义命令行最快的办法。
- 结果格式依据输出内容自动检测（见 4.1 节），因此即使工具在标准输出上打印 CLUSTAL 或 NEXUS，
  也仍然能被正确读取。

### 10.5 结果一致性校验会拒绝不匹配的输出

在载入结果之前，SeqAlignMac 会把结果与当初喂给它的输入做比较，一旦两者不一致就**拒绝载入**：

| 校验项 | 报告为 |
|---|---|
| 序列条数发生变化 | `sequence count changed (a → b)` |
| 输入中存在而结果中缺失的名称 | `missing sequences`（最多列出三个名称） |
| 结果中多出的名称 | `unexpected sequences`（最多列出三个名称） |
| 结果各行长度不一致 | `result rows have differing lengths` |

提示信息写作 `Alignment result is inconsistent with the input; refused: <detail>`。这层校验能保护你，
避免载入被工具截短的读段、被改名的记录，或只生成了部分的比对。应当修正命令（常见的就是标准输出与
文件写回这两种捕获方式用混了，见 10.2 节），而不是绕过它；该拒绝行为不可配置。不过你始终可以在终端
里运行该工具，再把它的输出当作普通文件打开，那样只受常规的解析期检查约束。

成功时，新窗口的标题为 `<your file name> (aligned)`；若结果来自标准输出、没有涉及任何文件名，
标题则为 `alignment_result.fasta`；这些后缀在设计上只有英文形式。

### 10.6 关于沙盒构建的说明

没有任何运行时开关会隐藏这个功能。只有签名期选项 `SEQALIGN_SANDBOX=1` 才会附加应用沙盒权限，
而沙盒化的构建无法执行用户提供的可执行文件——这正是 Mac App Store 风格的构建会失去外部比对能力的
原因。你自己构建出的发行版默认不带沙盒，所以该功能是可用的。

---

## 11. 导出

### 11.1 图像导出（PNG、PDF、SVG）

入口：`文件（File）▸ 导出为 PNG（Export as PNG）` / `导出为 PDF（Export as PDF）` /
`导出为 SVG（Export as SVG）`（都没有快捷键），侧栏的 `导出（Export）▸ 图像（Image）`，
或者先用 ⇧⌘E 打开预览面板。

1. 打开 `文件（File）▸ 导出预览（Export Preview）`（⇧⌘E）。
2. 选择**格式（Format）**分段控件：PNG、PDF 或 SVG。
3. 如果你只想要被选中的那块区域，勾选 **仅导出选中区域（Export selection only）**（没有选区时该选项
   会置灰）；如果你想要深色调色板，勾选 **深色模式导出（Dark Mode Export）**。
4. 查看 **预估尺寸（Estimated Size）**，然后点击 **导出…（Export…）** 并选择目标位置。

导出的图像包含什么，以及你能与不能控制什么：

| 属性 | 取值 | 能否从 GUI 控制？ |
|---|---|---|
| PNG 分辨率 | **始终 300 DPI**（按 300/72 的比例渲染） | 否——导出选项里的 DPI 字段没有对应界面，可尺寸标签却写着 "(300 DPI)" |
| 共识行 | **始终包含** | 否——在面板与预览两条路径中 `showConsensus` 都被硬编码为开启。在屏幕上隐藏共识行**并不会**让它在图像中消失；请在图注里把它考虑进去 |
| 名称列 | 默认 150 pt；实际采用你在画布上拖动到的宽度 | 间接可以：拖动分隔线（会持久化） |
| 字号 | 默认 13 pt；命令行可以覆盖它 | 在 GUI 中，导出前通过缩放（见 6.5 节）调整 |
| 配色方案 | 当前生效的那一个 | 可以，通过视图（View）／偏好设置（Preferences） |
| 范围 | 整段比对，或当前选区 | 可以，通过「仅导出选中区域（Export selection only）」 |
| 尺寸标签 | PNG 为 `W × H px (300 DPI)`；PDF/SVG 为 `W × H pt` | — |

PDF 与 SVG 都是矢量输出（SVG 以转义后的分块文本写出，空位矩形的不透明度为 16 %）。密码子与氨基酸
混排的轨道会被拒绝，并报一个 "unsupported" 错误，因为这样的轨道在一行里混用了两套字母表（见 9.5 节）。
对于离谱的尺寸，PNG 会拒绝导出并给出一条关于位图内存预算的提示，该提示只有中文。

**预览的局限。** 缩略图永远是一次 **PNG** 渲染结果，宽度被限制在最大 1600 px，而且当你在格式分段
控件里把 PNG 切换成 PDF 或 SVG 时它**不会**重新渲染：你看到的是布局的栅格化印象，按相应宽高比/格式实际
输出的结果可能与它不同。如果预览显示 "Preview unavailable (alignment too large or render failed)"，
请直接导出——完整渲染用的是另一套预算。在多窗口的使用场景下，成功提示可能出现在错误的窗口里；
请以磁盘上的文件为准。

### 11.2 保存与序列导出

| 任务 | 入口 | 产物 |
|---|---|---|
| 就地保存 | ⌘S | 相同格式、相同路径，源文件是 `.gz` 时会重新 gzip |
| 另存为 | ⇧⌘S | 一个保存面板；不论源文件是什么，输出都不压缩 |
| 导出为另一种格式 | 侧栏 `导出（Export）▸ 序列（Sequence）▸ FASTA / NEXUS / PHYLIP / CLUSTAL / MSF / Stockholm` | 一条带有新文件名的 "Saved <file>" 提示 |

下面这些不对称之处常令人意外，因此在此说明：

- 侧栏只提供**六**种序列格式，**没有 FASTQ**；而库和命令行都能写出 FASTQ（带真实的 Phred 质量值）。
  请使用 `cli convert --format fastq`。
- 另存为面板把文件名限制在 `fasta`、`nexus`、`phy`、`aln`、`msf` 之内；Stockholm 以及各种 PHYLIP
  变体只能通过侧栏上明确列出的格式按钮到达，而且无论如何应用写出的都是交替式（interleaved）PHYLIP。
- FASTQ 在保存或导出时**不会**被降级成 FASTA：质量值以 Phred+33 字符写出，补齐的位置变成 `!`（Q0），
  大于 93 的值会被截断到上限（见 4.7 节）。

保存或导出成功时会显示 `Saved <file>` 或 `Exported <file>`；失败时显示 `Save failed:` 或
`Export failed:`，并在其后附上底层错误。带着未保存的工作退出，会重新走一遍保存对话框（见 5.2 节）。

---

## 12. 偏好设置

用 ⌘, 打开（`偏好设置…（Preferences…）`，侧栏的 **设置（Settings）** 按钮也可以）。它是一个面板
（sheet），不是独立窗口：点击 **完成（Done）** 关闭（这里没有 Escape 绑定）。

| 设置项 | 取值范围／选项 | 默认值 | 作用 |
|---|---|---|---|
| 外观（Appearance） | 浅色 / 深色 / 跟随系统 | 跟随系统 | 应用级外观；数据色板在有意义的场合备有深色变体 |
| 默认配色（Color scheme） | 全部 7 种方案 | **极简（Minimal）** | 画布与导出的色板 |
| 默认字号（Font size） | 步进器，8–28 pt | 13 pt | 字形大小、缩放百分比，以及导出版面的尺寸 |
| 显示共识序列（Show consensus sequence） | 开 / 关 | 开 | 只影响屏幕上的共识行——导出始终包含它 |
| 高对比模式（High contrast mode） | 开 / 关 | 关 | 为无障碍用途增加额外的空位斜线并提高对比度 |
| 聚焦变暗（Focus dim） | 开 / 关 | 关 | 选区生效期间，非选中区域被淡化 |
| ClustalX 保守度阈值（Conservation Threshold） | 0.1–0.9，步进 0.05 | 0.3 | 在 ClustalX 方案中低于该阈值的列不着色 |
| 共识模式（Consensus Mode） | 多数规则 / IUPAC 简并 / 严格共识 | 多数规则 | 只影响共识字符；绝不改变一致度数值 |
| 比对器超时（Aligner timeout） | 步进器，30–3600 s，步进 30 | 300 s | 外部比对器运行的截止时限（见 10.4 节） |

引物的盐条件（`Na+` 50 mM、`Mg2+` 0 mM、`Oligo` 0.25 µM）不在这个面板里，但会从引物面板持久化保存。

**哪些会被记住、哪些不会。** 会持久化：语言、外观、配色方案、字号、名称列宽度、高对比模式、
聚焦变暗、共识模式、比对器超时、面板宽度（侧栏、统计）、最近十个文件路径、引物盐条件输入框，
以及一次性的首次运行标记。**不持久化**：ClustalX 阈值（每次启动都回到 0.3）、共识序列的可见性、
差异模式及其参照行、打开的标签页及它们的内容、以及搜索查询。退出会丢失你的窗口布局；请从
`文件（File）▸ 打开最近（Open Recent）` 重新打开文件。

**运行时切换语言。** 选择 `视图（View）▸ 语言（Language）▸ English / 中文`，或使用侧栏底部的
**语言（Language）** 按钮。该选择存储在设备上；首次启动时，它会从你的系统首选语言推断得到
（系统语言以 `zh` 开头则选用中文）。菜单、窗口标题、面板和命令面板都会立即重新渲染；无需重启。
有些字符串不在对照表里，因而始终保持只有中文（画布的提示气泡与 toast、图像导出错误、命令行、
遗传密码表选择器，以及 `Charset` 标签）。

---

## 13. 键盘快捷键

这张表就是应用注册的全部绑定的完整集合。这里一处都没出现的快捷键并不存在：**没有**任何快捷键
对应移动序列（Move Sequence）、引物计算（Primer）、比对质量评估（Alignment Quality）、默认（Default）
配色方案、过渡/颠换（Ti/Tv）方案，或 `文件（File）▸ 导出为 PNG/PDF/SVG（Export as PNG/PDF/SVG）`
中的任何一项。

### 13.1 全局、文件与剪贴板

| 按键 | 操作 | 菜单路径 |
|---|---|---|
| ⌘T | 在当前窗口新建标签页 | 文件（File）▸ 新建标签页（New Tab） |
| ⌘N | 新建窗口 | 文件（File）▸ 新建窗口（New Window） |
| ⌘O | 打开文件 | 文件（File）▸ 打开文件…（Open File…） |
| ⌘W | 关闭**标签页** | 文件（File）▸ 关闭标签页（Close Tab） |
| ⇧⌘W | 关闭**窗口** | 文件（File）▸ 关闭窗口（Close Window） |
| ⌘S | 就地保存 | 文件（File）▸ 保存（Save） |
| ⇧⌘S | 另存为… | 文件（File）▸ 另存为…（Save As…） |
| ⇧⌘E | 导出预览面板 | 文件（File）▸ 导出预览（Export Preview） |
| — | 导出为 PNG / PDF / SVG | 文件（File）▸ 导出为 PNG/PDF/SVG（Export as PNG/PDF/SVG） |
| ⌘A | 全选 | 编辑（Edit）▸ 全选（Select All） |
| ⌘C | 以 FASTA 复制选区 | 编辑（Edit）▸ 复制（Copy） |
| ⌘V | 粘贴序列 | 编辑（Edit）▸ 粘贴（Paste） |
| ⌘X | 剪切（有画布选区时：复制该区块**并**在其中插入空位） | 编辑（Edit）▸ 剪切（Cut） |
| ⌘, | 偏好设置面板 | 偏好设置…（Preferences…） |
| ⇧⌘P | 命令面板 | 工具（Tools）▸ 命令面板（Command Palette） |

### 13.2 编辑

| 按键 | 操作 | 菜单路径 |
|---|---|---|
| ⌘Z | 撤销（撤销栈为空时置灰） | 编辑（Edit）▸ 撤销（Undo） |
| ⇧⌘Z | 重做 | 编辑（Edit）▸ 重做（Redo） |
| ⇧⌘R | 重命名光标所在的序列 | 编辑（Edit）▸ 重命名序列（Rename Sequence） |
| ⇧⌘X | 删除光标所在的序列 | 编辑（Edit）▸ 删除选中序列（Delete Selected Sequence） |
| ⌘D | 在光标处插入一列空位 | 编辑（Edit）▸ 插入空位（Insert Gap） |
| ⌘I | 反向互补（仅核酸数据） | 编辑（Edit）▸ 反向互补（Reverse Complement） |
| — | 移动序列…（Move Sequence…） | 编辑（Edit）▸ 移动序列…（Move Sequence…） |

### 13.3 视图、配色方案与缩放

| 按键 | 操作 | 菜单路径 |
|---|---|---|
| ⇧⌘1 | 极简（Minimal）方案 | 视图（View） |
| ⇧⌘2 | ClustalX 方案 | 视图（View） |
| ⇧⌘3 | Zappo 方案 | 视图（View） |
| ⇧⌘4 | SeaView 方案 | 视图（View） |
| ⇧⌘5 | Okabe-Ito（色觉无障碍）方案 | 视图（View） |
| — | 默认（Default）方案、过渡/颠换（Ti/Tv）方案 | 视图（View） |
| ⌘= **或** ⌘+ | 放大（两者都已注册；美式键盘布局请用 ⌘=） | 视图（View） |
| ⌘- | 缩小 | 视图（View） |
| ⇧⌘0 | 将缩放重置为 13 pt（100 %） | 视图（View） |
| ⇧⌘G | 显示/隐藏共识序列——**与"查找上一个"冲突**，见 8.5 节 | 视图（View）▸ 显示/隐藏共识序列（Show/Hide Consensus） |
| — | 外观（浅色 / 深色 / 跟随系统） | 视图（View）▸ 外观（Appearance） |
| — | 语言（中文 / English） | 视图（View）▸ 语言（Language） |

### 13.4 搜索与工具

| 按键 | 操作 | 菜单路径 |
|---|---|---|
| ⌘F | 显示搜索栏 | 工具（Tools）▸ 搜索（Search） |
| ⌘G | 查找下一个 | 工具（Tools）▸ 查找下一个（Find Next） |
| ⇧⌘G | 查找上一个（已注册，但实际上这个组合键被共识序列开关抢走了） | 工具（Tools）▸ 查找上一个（Find Previous） |
| ⇧⌘B | 外部比对器面板 | 工具（Tools）▸ 运行比对（Run Alignment） |
| ⇧⌘T | 翻译选项面板 | 工具（Tools）▸ 翻译为氨基酸（Translate to Amino Acid） |
| — | 引物计算…（Primer Calculator…） | 工具（Tools）▸ 引物计算…（Primer Calculator…） |
| — | 比对质量评估（Alignment Quality） | 工具（Tools）▸ 比对质量评估（Alignment Quality） |

### 13.5 帮助

| 按键 | 操作 | 菜单路径 |
|---|---|---|
| — | 新手向导（Quick Guide） | 帮助（Help）▸ 新手向导（Quick Guide） |
| — | 加载示例数据（Load Example Data） | 帮助（Help）▸ 加载示例数据（Load Example Data） |
| — | 关于序列对齐（About SeqAlign） | 帮助（Help）▸ 关于序列对齐（About SeqAlign） |

### 13.6 画布按键与手势

| 输入 | 操作 |
|---|---|
| ← ↑ → ↓ | 移动光标（视图会滚动以保持光标可见） |
| ⌥ + 方向键 | 从锚点出发扩展矩形选区 |
| Esc | 清除选区 |
| 在网格中拖动 | 矩形选区 |
| ⌥ 拖动 | 整列区块选择 |
| 双击名称 | 重命名面板 |
| 上下拖动名称 | 重新排列序列顺序 |
| 拖动名称列分隔线 | 调整名称列宽度 |
| 在保守度轨道上拖动 | 连续浏览／跳转到某一列 |
| ⌘ + 滚轮 | 缩放 |
| 捏合（`magnify`） | 缩放 |

### 13.7 面板按键

| 输入 | 涉及的面板 |
|---|---|
| Esc | 序列 Logo、NJ 树、滑动窗口图、注释浏览器、质量评估报告、引物计算、导出预览、命令面板、新手向导；在未保存更改面板上，按 Escape 会触发它的**取消（Cancel）**按钮 |
| Return | 新手向导的开始、重命名确认、移动确认、外部比对器的运行／终止、翻译、导出预览的导出 |
| ↑ / ↓ | 命令面板导航 |
| 无 Escape 绑定 | **偏好设置…（Preferences…）**（点击 **完成（Done）**）与**翻译选项（Translation options）**面板——这两个请用鼠标关闭 |

---

## 14. 命令行用法

运行 GUI 的同一个可执行文件也能以无头方式运行。它就是 app 包内的二进制文件：

```bash
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli <subcommand> <file> [options]
```

`cli` 必须是**第一个**参数；没有它，启动的就是 GUI。为简洁起见，下面的示例用 `$SA` 代指那条路径：

```bash
SA=SeqAlignMac.app/Contents/MacOS/SeqAlignMac
```

共有三个子命令：`stats`、`export`、`convert`。你至少要给出一个子命令和一个输入路径，
否则会打印用法提示块并以退出码 64 结束。没有 `--help`、`--version`、`-v` 或 `--verbose`；
运行 `cli --help` 会打印用法提示块并退出 64。选项按 `--key value` 或 `-o value`
这样的位置配对来匹配；以 `-` 开头的值被视为"该选项缺失"，于是采用默认值；
如果同一个选项重复出现，**第一次**出现的那次生效。

输入文件是在子命令被分派**之前**读取并解析的，所以文件有问题时，即使子命令拼错也
会先报告解析错误；而拼错的子命令照样要付出完整解析的代价。`.gz` 输入按扩展名解压
（4.3 节）。

### 14.1 `cli stats` — 以 CSV 输出列统计

```
SeqAlignMac cli stats <alignment-file> [--out results.csv]
```

| 选项 | 默认值 | 行为 |
|---|---|---|
| `--out <path>` | 未给出 | 给出该选项时，CSV 写入文件，stdout 只打印 `已写入 <path>`（`Wrote <path>`）。不给时，CSV 输出到 stdout |
| `-o` | — | **`stats` 不识别 `-o`** —— 这里请用 `--out` |
| `--start` / `--end` | — | **`stats` 会忽略它们**：统计不做区域切片 |

CSV 字段，按顺序（`metric,value`；只有当值含有逗号、引号或换行时才加引号）：

| 字段 | 含义 |
|---|---|
| `file` | 只取路径的最后一个组件 |
| `sequences`、`columns` | 行数与列数（补齐之后的列数，即比对宽度） |
| `datatype` | `nucleotide` 或 `aminoacid` |
| `pooled_identity_site_weighted` | 池化一致度（位点加权），0–1，四位小数——见 9.1；这不是成对均值 |
| `declared_aligned` | 来源信息：`aligned`、`unknown` 或 `not-aligned` |
| `mean_column_identity` | 各列一致度值的算术平均，0–1 |
| `min_column_identity`、`max_column_identity` | 最佳／最差列，在信息列上统计（不存在信息列时为 0） |
| `gap_columns` | 没有任何可判定残基的列（全空位**或**全未判定） |
| `total_columns` | 列数 |
| `variable_sites`、`parsimony_informative_sites`、`singleton_sites` | 9.1 中定义的各类位点计数 |
| `gc_content` | GC 占比，0–1；蛋白质为 `0` |
| `fastq_mean_phred`、`fastq_q20_ratio`、`fastq_q30_ratio` | **仅当**来源带有质量数据时才出现 |

```bash
$SA cli stats aln.fasta --out stats.csv
$SA cli stats aln.fasta.gz | cut -d, -f1-2
```

### 14.2 `cli export` — 图像导出

```
SeqAlignMac cli export <alignment-file> --format png|pdf|svg [-o output]
                       [--fontsize N] [--dark]
                       [--scheme minimal|clustalx|zappo|seaview|default|titv|okabeito]
```

| 选项 | 默认值 | 取值非法时的行为 |
|---|---|---|
| `--format` | `png` | 除 `png`/`pdf`/`svg` 之外的任何值 → stderr 输出 `Error: unknown --format '<x>' (expected png\|pdf\|svg)` 并**退出 64** |
| `--scheme` | `minimal` | 名字无法识别时**静默回退到 `minimal`** —— 一个拼写错误会让你失去配色而不报任何错。库自身的 `ExportOptions` 默认是默认（Default）核酸配色；CLI 的默认是极简（Minimal） |
| `--fontsize N` | 13 | 只接受 6–40 之间的数字；否则在 stderr 上给出 `Warning: invalid --fontsize, using default 13` 一行，并使用 13（非致命） |
| `--dark` | 关闭 | 只看是否出现的开关 |
| `-o` / `--output` | `<input-basename>_alignment.<format>` | — |
| `--start` / `--end` | — | `export` 不支持；CLI 没有选区导出 |

名称列宽度取自持久化的偏好设置 `SeqAlignMac.nameColWidth`（否则为 150 pt），因此一次
无头运行会继承你的 GUI 布局——这是可复现性上的一个坑；要么有意识地设定该偏好设置，
要么使用一个全新的 user defaults 域。PNG 输出始终按 300 DPI 光栅化，并且共识行总是
会被绘制，与 GUI 中完全一致（11.1 节）。成功时 stdout 打印 `已导出 <path>`（`Exported <path>`）。

```bash
$SA cli export aln.fasta --format svg -o figure.svg --scheme okabeito --dark
$SA cli export aln.phy --format png --fontsize 10 > /dev/null   # 写出 aln_alignment.png
```

### 14.3 `cli convert` — 格式转换与区域提取

```
SeqAlignMac cli convert <alignment-file>
                       --format nexus|phylip|clustal|msf|stockholm|fasta|fastq
                       [-o output-file] [--start N] [--end M]
```

| 选项 | 默认值 | 取值非法时的行为 |
|---|---|---|
| `--format` | **必需** | 缺失 → `Error: --format is required for convert`，**退出 64**。未知 → `Error: unknown --format '<x>' (expected nexus\|phylip\|clustal\|msf\|stockholm\|fasta\|fastq)`，**退出 64** |
| `--start N` | `1` | 非数字值会被**静默忽略**（使用默认值）。超出范围的值会被**静默钳制**回比对之内 |
| `--end M` | 列数 | 同上 |
| `-o` / `--output` | `<input-basename>.<canonical extension>` | 这里**不**识别 `--out` —— 写 `convert … --out x.nexus` 会在当前目录静默生成一个默认命名的文件 |
| `--scheme`、`--fontsize`、`--dark` | — | `convert` 会忽略它们 |

可接受的格式别名（不区分大小写），以及默认输出名所使用的扩展名：
`nexus|nex`（`.nexus`）、`phylip|phy`（`.phy`）、`clustal|aln`（`.aln`）、`msf`（`.msf`）、
`stockholm|sto`（`.sto`）、`fasta|fa|fas`（`.fasta`）、`fastq|fq`（`.fastq`）。

区域语义：`--start`/`--end` 描述的是**比对列的 1 基闭区间**——
`--start 201 --end 400` 保留第 201 到 400 列（含两端，共 200 列）。超出比对范围的边界
会被静默钳制而不告警；`start > end`（或起点越过比对的最后一列）是错误：
`错误: 无效参数: Invalid region: <start>-<end>`，**退出 70**。短于所请求窗口的序列会用
`-` 向右补齐到统一宽度。NEXUS 的 `CHARSET` 分区会**重新投影到裁剪后的坐标**上，
因此区间对 MrBayes/RAxML/IQ-TREE 仍然正确，来源信息会被带过去，元数据与数据类型
也照常传递。当所请求的窗口就是整个比对时，切片整个步骤会被跳过。

`--format fastq` 要求至少有一条序列带质量值；否则本次运行会以
`不支持的操作: convert fastq 需要带质量值的 FASTQ 来源…` 失败并退出 70
（非 FASTQ 数据请改用 `--format fasta`）。如果指定的输出名以 `.gz` 结尾，转换后的文本
会在写出时用 gzip 压缩。密码子 + 氨基酸混排轨道会被拒绝，**退出 65**；该防护是防御性
的，实践中经由 CLI 走不到，因为混排轨道只作为进程内翻译结果存在，而 CLI 从不产生
这样的结果。

成功时 stdout 打印 `Converted to <format you typed> → <output path>`。

```bash
$SA cli convert aln.fasta --format nexus -o aln.nexus
$SA cli convert big.fasta --format fasta --start 1 --end 5000 -o region.fasta
$SA cli convert reads.fastq --format fastq -o fixed.fastq     # 质量值保留，补齐处为 Q0
```

### 14.4 退出码

| 码 | 名称 | 触发时机 |
|---|---|---|
| 0 | 成功 | 命令完成了它的工作 |
| 64 | 用法错误 | 参数太少；未知子命令；`export --format` 不是 png/pdf/svg 之一；`convert` 缺少 `--format`；`convert --format` 未知。会打印用法提示块，**打印到标准输出** |
| 65 | 数据错误 | 密码子 + 氨基酸混排轨道被拒绝（防御性；见 14.3） |
| 66 | 输入不可用 | 文件无法读取，或 `.gz` 文件无法解压：`无法读取文件: <path>` |
| 70 | 内部／软件错误 | 任何抛出的错误：解析失败、区域非法、FASTQ 无质量值、输出写入失败。以 stderr 上的 `错误: <description>` 报告 |

CLI 的错误与进度文本**未本地化**：文件与解析消息，以及 `已写入` / `已导出` 进度行是
中文，而格式／配色／`--fontsize` 相关消息和 `Converted to …` 行是英文。如果你围绕它写
脚本，请以前缀 `Error:`/`错误:` 来抓取，并把非零退出码当作权威信号。

### 14.5 一条批量流水线

把每个 PHYLIP 文件转换为 NEXUS，把失败响亮地跳过，并留下一份清单：

```bash
SA=SeqAlignMac.app/Contents/MacOS/SeqAlignMac
mkdir -p out
for f in in/*.phy; do
  base=$(basename "${f%.phy}")
  if "$SA" cli convert "$f" --format nexus -o "out/${base}.nexus" >>pipeline.log 2>&1; then
    printf '%s\tOK\n' "$base" >>manifest.tsv
  else
    rc=$?; printf '%s\tFAILED(exit %d)\n' "$base" "$rc" >>manifest.tsv
  fi
done
```

### 14.6 一份可复现分析的实战配方

```bash
SA=SeqAlignMac.app/Contents/MacOS/SeqAlignMac
set -euo pipefail
"$SA" cli stats aln.fasta.gz --out stats.csv
"$SA" cli convert aln.fasta.gz --format fasta -o aln.unaligned_check.fasta
"$SA" cli export aln.fasta.gz --format pdf -o fig.pdf --scheme okabeito
sha256sum stats.csv fig.pdf aln.unaligned_check.fasta > checksums.txt
```

在输出旁边记录三件事，因为正是它们让数字可以被重复：`stats.csv` 的 `declared_aligned`
列（输入是否真的已比对）、PNG/PDF 导出会从偏好设置继承你保存的名称列宽度这一事实，
以及 `--scheme` 拼错时会静默回退到 `minimal` 而不报错。在你的实验记录里写清所用
可执行文件（`SeqAlignMac.app/Contents/MacOS/SeqAlignMac`，来自 v0.1.0 的构建）。

---

## 15. 实战配方

把多个功能组合起来的端到端任务。命令使用 14 节中的 `$SA` 简写。

### 15.1 提取一个 NEXUS 区域用于引物设计

目标：在一个大型比对上扩增一个 300 bp 的窗口，并针对它设计引物。

1. 找到窗口：点击侧栏「序列分析（Analysis）」组中的 **窗口（Window）**，阅读一致度图；
   记下两侧保守区域的列号。
2. 一步完成裁剪与转换：
   `"$SA" cli convert whole.fasta --format nexus --start 4001 --end 4300 -o amplicon.nexus`
   NEXUS 的 `CHARSET` 区间会自动重新编号，因此下游系统发育分析保持一致。
3. 在 SeqAlignMac 中打开 `amplicon.nexus`（⌘O）。
4. 选中你想设计引物的行区间，打开引物面板（侧栏 **引物（Primer）**），点击
   **从选区填入（Fill from selection）**。
5. 按下 **计算 Tm（Calc Tm）**、**计算 GC%（Calc GC%）**、**自身二聚体（Self-dimer）**，
   然后在 `序列 B（Sequence B）`中填入反向引物后点击 **异源二聚体（Hetero-dimer）**。
   ΔG 低于 −5 kcal/mol 应视为危险信号，并且要记住该面板不模拟 dNTP 的螯合作用（9.6 节）。
6. 也用 Wallace 数值对这一对引物做一次校验；如果对一个短的常规寡链两者相差超过
   几度，就要怀疑序列带有简并碱基。

### 15.2 用 Q20 与 Q30 做 FASTQ 质控筛查

目标：在投入算力之前先判断一批读段是否可用。

1. 打开 `reads.fastq`。统计面板会显示一张 **测序质量（Read Quality）** 卡片，其中有
   平均 Phred（Mean Phred）、最低 Phred（Min Phred）、≥Q20 碱基占比（≥Q20 bases）、
   ≥Q30 碱基占比（≥Q30 bases）。
2. 把这些比率按**每碱基**的占比来读：Q20 = 预期错误率 1 %，Q30 = 0.1 %。例如某个数据集
   达到 92 % ≥Q20 但只有 68 % ≥Q30，那么它用于共识调用没有问题，而在同聚物里做变异
   调用就属于勉强。最低 Phred 接近 2 通常意味着读段末端质量衰减，而不是文件损坏。
3. 切换到 ⇧⌘5（Okabe-Ito）并稍微缩小一点，看低质量的尾部落在读段的哪些位置；
   保守度轨道会给你逐列的整体图景。
4. 需要为每个文件留一份数值记录时：`"$SA" cli stats reads.fastq.gz --out qc.csv`，
   并把 `fastq_mean_phred`、`fastq_q20_ratio`、`fastq_q30_ratio` 保留在你的质控表里。
5. 如果你要把读段交给另一个工具，并且要让比对空位得到规整处理：
   `"$SA" cli convert reads.fastq.gz --format fastq -o normalized.fastq` —— 补齐的列变成 Q0（`!`）。

### 15.3 构建一棵邻接法系统发育树并发表

1. 确认输入真的是已比对的：统计面板**不得**显示橙色的未比对横幅，或者 CLI 输出中的
   `declared_aligned` 必须是 `aligned`。如果尚未比对，先运行一个比对器（10 节）。
2. 让分歧程度保持很低——p-distance 是未校正的，所以这棵树只适用于近缘类群。
3. 点击 **NJ 树（NJ Tree）**。若序列超过 200 条，请注意采样说明那一行：按等间隔步长
   抽取 200 条。
4. 点击 **复制 Newick（Copy Newick）**，粘贴到你的树查看器，并**保留根的 NHX 注释**
   （`[&sampled=200_of_1240;model=p-distance;clamped=3]`）——它准确记录了到底算了什么。
   如实报告被钳制的分支数；数目偏高说明距离模型对你的数据已经饱和。
5. 要做一次可复现的运行：用 `cli convert --start/--end` 裁剪出该分类单元子集，重新生成
   树，并把 Newick 与旁边的 `stats.csv` 一起存档。

### 15.4 一张用于论文的色觉无障碍图

1. `视图（View）▸ Okabe-Ito（色觉无障碍）`，即英文界面的 `Okabe-Ito (CVD-safe)`（⇧⌘5）。
   这套配色就是为红绿色觉缺陷设计的（Wong 2011）。
2. 如果图要以灰度印刷，请打开 `偏好设置…（Preferences…）▸ 高对比模式（High contrast mode）`，
   并把字号设到字母仍会被绘制的程度——在最小几档字号下只剩下色块（6.5 节）。
3. 选中你希望出现在图里的区域。记住：无论你在屏幕上能否看到共识行，它**总是**会被导出，
   所以请让共识保持显示，并把它当作图注的一部分来对待。
4. ⇧⌘E → **格式（Format）：PDF** 得到矢量图，勾选 **仅导出选中区域（Export selection only）**，
   并查看预估尺寸。需要光栅图时用 **PNG** —— 它按 300 DPI 写出，而且没有 DPI 控制项。
5. 如果预览缩略图与你预期的不一致，那是已知的预览限制（它始终是宽度 ≤1600 px 的 PNG
   渲染）；照常导出，然后检查真实文件。
6. 在图注中写明所用的配色方案以及是否包含共识序列，例如 "Okabe-Ito palette; consensus row
   shown; 300 DPI"。

### 15.5 批量转换两百个文件

```bash
SA=SeqAlignMac.app/Contents/MacOS/SeqAlignMac
mkdir -p nexus
ls clustal/*.aln | sed 's/\.aln$//' | while read -r base; do
  "$SA" cli convert "${base}.aln" --format nexus -o "nexus/${base}.nexus" \
    || echo "FAILED ${base}.aln" >> failures.log
done
wc -l nexus/*.nexus | tail -1
```

然后检查 `failures.log`。常见原因是退出码 66（名字带 `.gz` 而里面并不是 gzip，或者
文件确实无法读取）以及解析错误带来的退出码 70，两者都会在标准错误上带上具体原因。

### 15.6 整理一个未比对的 FASTA 而不丢失原件

1. 打开文件；接受那条未比对横幅——它是在告诉你列同源关系并不成立。
2. ⇧⌘B → 预设 **mafft（推荐）**（英文界面 `mafft (recommended)`），点击 **运行（Run）**。
   结果会在一个名为 `<file> (aligned)` 的**新窗口**中打开；原来的标签页不受影响。
3. 如果运行被拒绝并提示"与输入不一致"（inconsistent with the input），检查你是否把
   `{output}` 从模板里删掉了（mafft 写到标准输出，不应带 `{output}` 占位符），然后重试。
4. 验证：新窗口的横幅应当消失，**含空位列数（Gap columns）** 应当下降，
   **池化一致度（位点加权）（Pooled identity (site-weighted)）** 应当上升。
   用 `cli stats` 对两个文件做前后对比。
5. ⌘S 就地保存（进来的时候是 gzip，保存后仍然是 gzipped），或用 ⇧⌘S / 侧栏导出
   写出另一种格式。

---

## 16. 故障排查与常见问题

**文件打不开。**
按顺序检查格式与压缩这两件事。打开面板只列出
`fasta, fa, fas, fastq, fq, nexus, nex, phy, phylip, aln, msf, sto, stockholm, gz`，
所以 `.fna`、`.faa`、`.mpfa` 或 `.clustal` 文件在那里根本看不见，尽管 app 其实读得了
里面的内容——把文件直接拖到窗口上即可。gzip 流必须确实*是* gzip **并且**命名为 `.gz`；
一个实际是 `cat a.gz b.gz` 拼出来的文件会被有意拒绝，以免静默丢掉数据。如果被拒绝的是
某一条具体记录，请读错误信息："illegal character at line N"、"fewer data lines than
declared"、"quality line length mismatch"、"sequence has no residues" 都很精确，
并且它们都意味着要修的是文件——不是 app。

**字母显示为色块；我读不出残基。**
你低于密度阈值：每列约 6 px 以下时，字形绘制会被有意关闭。按几下 ⌘=，或按 ⇧⌘0
回到 13 pt。行高不变，所以这个开关只关乎宽度。

**我切换共识模式（Consensus Mode）之后，共识行跟我的统计结果不一致。**
这是预期行为。发生变化的只有共识*字形*；一致度百分比、保守度轨道、着色、池化一致度（位点加权）
和 NJ 树始终使用多数规则（majority rule）。另外请记住统计面板里的
"共识长度（Consensus length）"其实是一个**列数**。

**`Aligner not found: mafft`。**
该工具不在任何被探测的目录里（`/opt/homebrew/bin`、`/opt/homebrew/sbin`、`/usr/local/bin`、
`/usr/local/sbin`、`/usr/bin`、`/bin`，然后是 `which`）。装上它，或者在命令栏里键入完整路径
（`/opt/homebrew/bin/mafft --quiet {input}`）。`Alignment timed out` 表示你撞上了由偏好设置
决定的时限（默认 300 s，可在 30–3600 s 之间调节）：把它调大，或者裁剪输入。

**"Alignment result is inconsistent with the input; refused"。**
结果与输入在序列数、名称或参差性上不匹配（10.5 节）。最常见的原因是命令行与捕获模式
互相矛盾：存在 `{output}` 时 app 读文件，不存在时 app 读标准输出。把模板改对；如果你
非要用这个输出不可，就在终端里自己运行该工具，然后正常打开它生成的文件。

**撤销不合并我的按键。**
这是设计使然。不存在按键合并（keystroke coalescing）——只有显式的事务才会归组——
而且撤销栈最多保留 50 步和 256 MiB，先丢弃最早的那一步。如果你想一步撤销一个大的
改动，就把它做成一条命令（例如空位精简），而不是连续的一串小编辑。

**Gatekeeper 拦住了 app。**
见 2.3 节：临时签名（ad-hoc）是默认的构建路径。用右键 ▸ **打开（Open）**，或
系统设置（System Settings）▸ 隐私与安全性（Privacy & Security）▸ **仍要打开（Open Anyway）**，
或者移除隔离属性。`spctl -a -vv` 拒绝一个临时签名的构建是预期结果，不是被篡改的证据。

**导出失败，报的是关于位图尺寸或宽高的消息。**
PNG 路径会拒绝荒谬的输出尺寸；该消息目前只有中文
（"导出位图过大…"、"无法创建 W×H 位图上下文…"）。缩小范围（只导出选区）、缩小名称列
宽度，或者改导出 PDF/SVG。密码子 + 氨基酸混排轨道根本无法导出：请重新翻译，
只选 单密码子（Codon only）或 氨基酸码（Amino acid）。

**⇧⌘G 这个键没有跳到上一个匹配。**
已知冲突；它切换的是共识行。请改用搜索栏里的 **上一个（Prev）** 按钮，或
`工具（Tools）▸ 查找上一个（Find Previous）`。

**有些标签即使在英文界面下也是中文。**
若干画布 toast、列窥视（column-peek）工具提示、状态栏的 `Charset` 标签、遗传密码选择器、
图像导出错误字符串，以及全部 CLI 输出，都还没有进入本地化表。它们的行为完全一致；
只是措辞不同。英文／中文切换（12 节）不会改变它们。

**两个窗口显示相同的"关于"／版本。**
`帮助（Help）▸ 关于序列对齐（About SeqAlign）` 会显示版本，而那个字符串是硬编码在 app
里的，不是从 bundle 读取的，所以即使是本地重新构建的二进制，它也总是说
**Version 0.1.0**。就打包而言，权威版本是 `Info.plist` 里的 `CFBundleShortVersionString`，
你可以用下面的命令查看：

```bash
defaults read "$PWD/SeqAlignMac.app/Contents/Info" CFBundleShortVersionString
```

**我在哪里能找到日志？**
没有日志文件。错误都是就地显示——错误横幅、toast、比对器面板的消息区——而 CLI 把
诊断信息写到标准输出／标准错误，所以把它们重定向到文件（见 14.5）。偏好设置存放在
`UserDefaults` 里，键名带 `SeqAlignMac.` 前缀：

```bash
defaults read com.seqalign.mac      # 列出每一项已持久化的偏好设置
defaults delete com.seqalign.mac    # 把它们全部重置
```

卸载会移除所有本地保存的状态，任何数据都不会被上传到任何地方（见 `PRIVACY.md`）。

**关于性能的问题。**
渲染是虚拟化的，统计在后台运行，而有文档依据的说法到此为止：没有测量过任何序列数量
上限或速度指标，所以不要围绕一个被承诺的容量去做规划。对于非常大的或无人值守的工作，
请使用命令行。

---

## 17. 获取帮助与已知限制

**去哪里找具体答案**

| 问题 | 文档 |
|---|---|
| 我该如何……（某项任务） | 本指南 `docs/USAGE_ZH.md`（以及[英文版](USAGE.md)） |
| 它是怎么构建的、某个数字为什么是这个值、各格式的确切规则是什么、CLI 契约是什么 | [`docs/DOCUMENTATION_ZH.md`](DOCUMENTATION_ZH.md) |
| 哪些限制是已知并被跟踪的 | [`DOCUMENTATION_ZH.md`](DOCUMENTATION_ZH.md)，"已知限制与工程偏差"一节 |
| 文档／功能总览与快速链接 | [文档索引](README.md)，以及仓库的 `README.md` |
| 参与贡献、代码风格、核心文件白名单、测试策略 | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |
| 报告安全问题、攻击面、签名与完整性 | [`SECURITY.md`](../SECURITY.md) |
| 收集了哪些数据（没有）以及偏好设置存在哪里 | [`PRIVACY.md`](../PRIVACY.md) |
| 如何引用本软件 | [`CITATION.cff`](../CITATION.cff) |
| 应用内 | `帮助（Help）▸ 新手向导（Quick Guide）`（八步走查）、`帮助（Help）▸ 关于序列对齐（About SeqAlign）` |

**使用本 app 时要记住的限制**

- 没有内置比对器：比对本身总是来自外部工具（10 节）。
- 没有系统发育树渲染画布：NJ 的结果是一段 Newick 文本，要绘图得去别处（9.3 节）。
- 不能在画布上键入残基；编辑以整行／整列加上粘贴为主（7.3 节）。
- 除了 `cli stats` 产生的那份 CSV，没有按序列或按位点的表格导出。
- 导出控制比较粗：PNG 固定 300 DPI，共识行总是开启，CLI 导出路径没有区域参数
  （11.1 节）。
- 注释浏览器没有任何筛选功能（9.7 节）。
- 只写不读、没有用户界面的库功能：FASTA 换行（`wrapWidth`）、PHYLIP 的
  sequential／strict-10／padded-name 各变体、CLUSTAL 共识行、NEXUS 元数据写入
  （实际上它只控制 `SETS` 块），以及 `.fai` 索引处理。只能通过库来触达它们。
- 命令行界面**完全没有自动化测试**：参数解析、退出码、CSV 字段集合以及
  `--start/--end` 切片都是靠阅读源码验证的，而不是靠测试套件，CI 也从不执行 `cli` 模式。
  请把 CLI 的边界行为当作"如本文所述、如代码所读"，并在脚本里检查退出码。
- 110 个核心单元测试覆盖解析器、写出器、统计、搜索、翻译与撤销各层；AppKit/SwiftUI 的
  渲染、导出和文件保存路径不在该套件的覆盖范围内。
- 仅支持 macOS，仅 `arm64`，并且不存在任何 Linux 或 Intel 上的验证。

如果某个行为与本指南不符，请针对仓库提一个 issue，附上该文件（或一个最小片段）、
你使用的确切菜单路径，以及你看到的那条消息；`cli stats` 给出的 `declared_aligned` 值
和 `codesign --verify` 的输出是最有用的两项内容。
