# SeqAlignMac User Manual (English)

**Version 0.1.0**

SeqAlignMac is a native macOS application for viewing, editing, and analysing multiple sequence alignments (MSA). This manual provides a comprehensive guide to all features and workflows, and is kept in sync with the source code in this repository.

> **v0.1.0**: Initial public release.

---

## Table of Contents

1. [Installation](#1-installation)
2. [Opening Alignment Files](#2-opening-alignment-files)
3. [Interface Overview](#3-interface-overview)
4. [Colour Schemes](#4-colour-schemes)
5. [Editing Alignments](#5-editing-alignments)
6. [Search](#6-search)
7. [Translation](#7-translation)
8. [Primer Calculator](#8-primer-calculator)
9. [Quality Statistics](#9-quality-statistics)
10. [Sequence Logo](#10-sequence-logo)
11. [Neighbour-Joining Tree](#11-neighbour-joining-tree)
12. [Sliding-Window Identity](#12-sliding-window-identity)
13. [External Alignment Tools](#13-external-alignment-tools)
14. [Annotation Browser (GFF3)](#14-annotation-browser-gff3)
15. [Export](#15-export)
16. [Command-Line Interface](#16-command-line-interface)
17. [Keyboard Shortcuts](#17-keyboard-shortcuts)
18. [Preferences](#18-preferences)
19. [Help Menu](#19-help-menu)
20. [Troubleshooting](#20-troubleshooting)

---

## 1. Installation

### From Source

Requirements: macOS 14.0 or later, Xcode 16 or the Swift 6.0 toolchain. `build.sh` compiles for Apple Silicon (`arm64-apple-macosx14.0`).

```bash
git clone https://github.com/zengzichao/SeqAlignMac.git
cd SeqAlignMac
./build.sh
```

The script runs the unit tests (degraded gracefully with a warning when only the Command Line Tools are installed, because the XCTest module is unavailable locally; CI on a full Xcode runner executes them), compiles every Swift source file, generates the application icon, optionally codesigns when the `DEVELOPER_ID` environment variable is set, and packages the result.

The built application appears at `SeqAlignMac.app`, and a distributable archive is created at `SeqAlignMac.app.zip`.

### Run Tests Only

```bash
swift test    # runs the 110 SeqAlignCore unit tests (requires full Xcode)
```

---

## 2. Opening Alignment Files

### Supported Formats

| Format | Extension(s) | Notes |
|---|---|---|
| FASTA | .fasta, .fa, .fas | Auto-detected by the `>` header; further content-based detection |
| FASTQ | .fastq, .fq | Phred+33 quality values parsed into the statistics |
| NEXUS | .nexus, .nex | TAXA/DATA/CHARACTERS/SETS blocks |
| PHYLIP | .phy, .phylip | Auto-detects sequential / interleaved / strict-10 / padded-name variants |
| CLUSTAL | .aln, .clustal | Conservation lines parsed |
| MSF | .msf | AA/NA header type |
| Stockholm | .sto, .stockholm | Pfam/Rfam standard |

Gzip-compressed files (`.gz`, e.g. `alignment.fasta.gz`) are transparently decompressed on opening, in the GUI and in the CLI. Format detection is content-based, so files with unusual extensions also open correctly.

### Methods

1. **Menu**: File ▸ Open (Cmd+O)
2. **Drag and Drop**: Drag a file onto the application icon or onto the window
3. **Command line**: `open -a SeqAlignMac alignment.fasta`
4. **Recent Files**: File ▸ Open Recent
5. **Example data**: Help ▸ Load Example (or the sidebar Example button) loads a built-in demo alignment

---

## 3. Interface Overview

The main window is organised into three always-visible panels:

- **Left Sidebar**: File operations (Open, Save, Example), analysis tools (Run MSA, Translate, Primer, Quality, Logo, NJ Tree, Window, Annotation), colour-scheme selector, and view controls (Search, Difference mode, Legend, Undo, Redo).
- **Center Panel**: The alignment canvas with sequence names (left), residues (centre), the consensus track (top), and the conservation track above the residues. Click or drag on the conservation track to jump to a column.
- **Right Statistics Panel**: Real-time quality metrics, the consensus sequence, and cursor information.

Panel widths are adjusted by **dragging the vertical dividers** between panels (sidebar 150–320 pt, statistics panel 220–460 pt). The widths are remembered between sessions.

The title bar supports multiple tabs (Cmd+T for a new tab). Each tab holds an independent alignment with its own undo stack; tabs are closed with the ✕ button on the tab label, and Cmd+W closes the window.

### Canvas Interactions

- **Click** a cell to place the cursor; **arrow keys** move it.
- **Drag** in the residue area to make a rectangular selection; **Option+drag** selects a column block.
- **Double-click** a sequence name to rename it.
- **Drag** a sequence name up or down to reorder the sequence (an insertion indicator is shown).
- **Esc** clears the selection.
- **Cmd+scroll** or **pinch** zooms the canvas continuously.
- The name column separator is itself draggable to change the name column width.
- The **sequence-name column stays frozen** when you scroll horizontally, so sequence labels remain visible at any position; clicking the names in the frozen column still renames, reorders, or opens the context menu.
- Thin **scroll bars are always visible** at the right and bottom edges of the canvas and can be dragged directly.
- **Density-adaptive glyphs**: when zoomed out below a readable column width, residues are drawn as colour blocks only; letters reappear as you zoom in.

### Status Bar

At the bottom: sequence count, column count, cursor position (row, column), residue under the cursor, column identity (%), data type (nucleotide/amino acid), and the number of NEXUS CHARSET blocks when present. The right end shows the file name with a ● marker when unsaved changes exist.

---

## 4. Colour Schemes

Switch via the sidebar selector, the View menu, or the keyboard shortcuts Cmd+Shift+1 through Cmd+Shift+4:

| Scheme | Shortcut | Description |
|---|---|---|
| Minimal | Cmd+Shift+1 | Monochrome grey-scale by column conservation (default) |
| ClustalX | Cmd+Shift+2 | Physicochemical grouping with a configurable conservation threshold |
| Zappo | Cmd+Shift+3 | Functional grouping |
| SeaView | Cmd+Shift+4 | Simplified grouping |
| Default | — | Standard nucleotide colours (A/C/G/T/N/gap) |
| Transition/Transversion | — | Purine↔purine (transition) vs. purine↔pyrimidine (transversion) |
| Okabe-Ito | — | Colour-vision-deficiency-friendly palette (Wong, 2011) |

The ClustalX conservation threshold is adjustable in Preferences (0.1–0.9, default 0.3). Columns below the threshold remain uncoloured. A colour legend is available via the sidebar Legend button.

---

## 5. Editing Alignments

All edits go through the undo/redo stack (up to 50 steps; older steps are discarded). Batch operations recorded as a single transaction are undone as one step.

### Context Menus

Right-click menus are context-sensitive:

- **Name area**: Rename Sequence, Delete Sequence, Move to Top, Move to Bottom, Sort By (Name, Similarity, GC Content, Length, Length without Gaps), Gap Trimming (Remove all-gap Columns / Remove high-gap Columns, >50% gap).
- **Residue area**: Copy Selection, Colour Scheme submenu (all seven schemes), Reverse Complement (nucleotides only), Translate Region, Gap Trimming submenu.
- **Empty area** (below the alignment): Insert Gap, Paste, Add Sequence.

### Common Operations

- **Rename sequence**: double-click the name, or right-click ▸ Rename Sequence (Cmd+Shift+R)
- **Delete sequence**: right-click ▸ Delete Sequence (Cmd+Shift+X)
- **Move sequence**: right-click ▸ Move to Top / Move to Bottom, or drag the name up/down
- **Reverse complement**: right-click ▸ Reverse Complement, or Cmd+I (nucleotides only)
- **Insert gap**: right-click ▸ Insert Gap in the empty area, or Cmd+D
- **Add sequence**: right-click ▸ Add Sequence in the empty area, or paste from the clipboard
- **Sort**: right-click ▸ Sort By (name, similarity, GC content, length, length without gaps)
- **Remove gap columns**: right-click ▸ Gap Trimming ▸ Remove all-gap columns, or Remove high-gap columns (>50% gaps)

### Undo/Redo

- Undo: Cmd+Z
- Redo: Cmd+Shift+Z

---

## 6. Search

Open the search bar with Cmd+F (or the sidebar Search button).

- **Scope**: Content (residues) or Name (sequence identifiers)
- **IUPAC mode** (default): Degenerate codes match equivalent residues (e.g., R matches A or G)
- **Regex mode**: toggled with the regex button; IUPAC codes outside character classes are auto-expanded (e.g., R → [AG]); escape sequences (e.g., `\d`, `\b`) and character-class contents are preserved verbatim and are not affected by IUPAC upper-casing
- **Live search**: matches update as you type (300 ms debounce)
- **Navigation**: Enter jumps to the next match (or performs the first search); the ‹ › buttons step between matches; Cmd+G finds the next and the Tools-menu Find Previous repeats the previous match

---

## 7. Translation

Access via Tools ▸ Translate (Cmd+Shift+T). Nucleotide alignments only.

- **Genetic code table**: 17 of the 27 genetic code tables currently defined by NCBI (values verified against the NCBI official `gc.prt` release via Biopython); unsupported table IDs are not offered in the UI and there is no silent fallback
- **Reading frame**: −3 to +3 (six-frame)
- **Display mode**: Codon-only, amino-acid, both (interleaved), or ignore gaps (gaps removed before translation)
- **Sequence names**: keep original names or add an `_AA` suffix
- **Output**: replace the current alignment or open the result in a new window
- **Options**: highlight start codons, highlight stop codons

Negative frames are computed on the reverse complement. Frame −1 starts at the first base of the reverse complement, −2 at the second, −3 at the third (standard six-frame semantics).

---

## 8. Primer Calculator

Access via Tools ▸ Primer Calculator. Nucleotide sequences only.

- **Input**: type or paste a primer sequence, or fill from the current canvas selection
- **Tm**: nearest-neighbour method (SantaLucia, 1998) with terminal correction; salt correction after von Ahsen et al. (1999)
- **Wallace rule**: quick Tm estimate (2×AT + 4×GC)
- **GC content**: fraction of G+C
- **Self-dimer ΔG**: 3′-end complementary window thermodynamics at 37 °C; palindromic (self-complementary) primers handled explicitly
- **Hetero-dimer ΔG**: enter a second sequence for cross-dimer analysis
- **Degenerate primers**: IUPAC codes (R, Y, S, W, K, M, B, D, H, V, N) are expanded up to an internal limit of 4096 combinations; Tm is reported as a (min, max) range
- **Configurable parameters**: Na⁺, Mg²⁺, and oligonucleotide concentrations (invalid input is clamped to non-negative values)
- **Error reporting**: sequences containing characters the NN table cannot handle (e.g., U or gaps), invalid salt concentrations, sequences too short, or degenerate expansion beyond the 4096 limit produce explicit error messages instead of distorted numbers

---

## 9. Quality Statistics

Access via Tools ▸ Alignment Quality.

| Metric | Definition |
|---|---|
| Mean pairwise identity | Column-frequency method, gaps excluded |
| Min/Max column identity | Extreme column conservation values |
| Gap columns | Columns containing only gap characters |
| Variable sites | ≥2 residue types (non-gap) |
| Parsimony-informative sites | ≥2 types, each present in ≥2 sequences |
| Singleton sites | Exactly 1 sequence differs |
| GC content | Fraction of G+C (nucleotides only) |
| FASTQ quality | Mean Phred and Q20/Q30 ratios (FASTQ input only) |

The same statistics are written by the CLI `stats` command (Section 16).

---

## 10. Sequence Logo

Access via the sidebar ▸ Logo button. Displays the information content per column after Schneider and Stephens (1990):

R(l) = log₂K − (H(l) + e(n))

where K is the alphabet size, H the Shannon entropy, and e(n) = (K−1)/(2·ln2·n) the small-sample correction. Gaps are excluded. Letter height = residue fraction × column information. Page through long alignments with the ‹ › controls.

---

## 11. Neighbour-Joining Tree

Access via the sidebar ▸ NJ Tree button.

- Method: Saitou and Nei (1987)
- Distance: uncorrected p-distance, computed over mutually non-gap sites only
- Subsampling: if the alignment has more than 200 sequences, the first 200 are used
- Output: Newick string with a copy-to-clipboard button

---

## 12. Sliding-Window Identity

Access via the sidebar ▸ Window button.

- Window size adjustable from 5 to 500 columns (default 50)
- Step = window/2 (at least 1)
- Output: average column identity per window plotted against the window centre position

---

## 13. External Alignment Tools

Access via the sidebar ▸ Run MSA button, or Tools ▸ Run Alignment (Cmd+Shift+B). Runs an external multiple-alignment program on a FASTA file you choose and opens the result in a new tab/window.

Built-in presets (command templates; `{input}`/`{output}` are placeholders):

| Preset | Command | Result source |
|---|---|---|
| MAFFT | `mafft --quiet {input}` | standard output |
| MUSCLE v5 | `muscle -align {input} -output {output}` | output file |
| ClustalW2 | `clustalw2 -infile={input} -outfile={output} -quiet` | output file |
| Custom | user-defined template | standard output (configurable) |

The external program must be installed and reachable through your `PATH` (e.g., `brew install mafft muscle clustal-w`); the application searches `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and `/bin` in turn.

Behaviour notes:

- MAFFT and custom presets read the alignment result from the process **standard output** (MAFFT does not write an output file).
- Large outputs are drained concurrently on a background queue, preventing the 64 KB pipe-buffer deadlock; on timeout (5 min) the process receives SIGTERM, escalating to SIGKILL after a 5-second grace period.
- Result formats are **auto-detected** (ClustalW2 writes CLUSTAL format rather than FASTA, and is now parsed correctly).
- If a custom command contains no `{input}` placeholder, the sequence data is passed via **stdin**.

---

## 14. Annotation Browser (GFF3)

Access via the sidebar ▸ Annotation button.

- Import a GFF3 annotation file
- Browse features filtered by type, name, and coordinate range
- Click Jump to navigate the canvas to the annotation region

---

## 15. Export

### Image Export

Open with File ▸ Export Preview (Cmd+Shift+E), or File ▸ Export PNG/PDF/SVG for direct export.

- Formats: PNG, PDF, SVG
- Options: dark mode, colour scheme, font size, export selection only (available when a selection exists)
- A live preview is shown before export

### Sequence Export

- Formats: FASTA, NEXUS, PHYLIP, CLUSTAL, MSF, Stockholm
- The output format follows the file extension chosen in the save dialog (e.g., `.nexus`/`.nex` → NEXUS, `.phy` → PHYLIP, `.aln` → CLUSTAL, `.msf` → MSF, `.sto`/`.stockholm` → Stockholm, any other → FASTA)
- FASTQ data is exported as FASTA (quality values are dropped)

---

## 16. Command-Line Interface

The same binary doubles as a headless CLI. Run it through the executable inside the app bundle:

```bash
# Column statistics → CSV (stdout or --out file)
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli stats alignment.fasta --out stats.csv

# Format conversion, optionally restricted to a 1-based closed region
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus -o alignment.nexus
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus --start 100 --end 300 -o region.nexus

# Image export with scheme and size options
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli export alignment.fasta --format pdf --scheme okabeito -o alignment.pdf
```

Complete usage:

```text
SeqAlignMac cli stats    <alignment-file> [--out results.csv]
SeqAlignMac cli export   <alignment-file> --format png|pdf|svg [-o output]
                        [--fontsize N] [--dark]
                        [--scheme minimal|clustalx|zappo|seaview|default|titv|okabeito]
SeqAlignMac cli convert  <alignment-file> --format nexus|phylip|clustal|msf|stockholm|fasta
                        [-o output-file] [--start N] [--end M]
```

All CLI commands accept `.gz` input and auto-detect the input format. `convert` requires `--format`; an unsupported `--format` value for `export` or `convert` now exits with code 64 instead of silently falling back to the default format; region bounds are 1-based and inclusive.

---

## 17. Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+O | Open file |
| Cmd+N | New window |
| Cmd+T | New tab |
| Cmd+W | Close window |
| Cmd+S | Save |
| Cmd+Shift+S | Save As |
| Cmd+Shift+E | Export preview |
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+X | Cut |
| Cmd+C | Copy selection |
| Cmd+V | Paste |
| Cmd+A | Select all |
| Cmd+I | Reverse complement (nucleotides only) |
| Cmd+D | Insert gap |
| Cmd+Shift+X | Delete selected sequence |
| Cmd+Shift+R | Rename sequence |
| Cmd+F | Search |
| Cmd+G | Find next |
| Cmd+Shift+G | Toggle consensus track (View menu; the same combination is also registered as Find Previous in the Tools menu) |
| Cmd+Shift+1 | Colour scheme: Minimal |
| Cmd+Shift+2 | Colour scheme: ClustalX |
| Cmd+Shift+3 | Colour scheme: Zappo |
| Cmd+Shift+4 | Colour scheme: SeaView |
| Cmd++ / Cmd+- | Zoom in / out |
| Cmd+Shift+0 | Reset zoom (13 pt) |
| Cmd+scroll / pinch | Continuous zoom |
| Cmd+Shift+B | Run external alignment |
| Cmd+Shift+T | Translate |
| Cmd+Shift+P | Command palette |
| Cmd+, | Preferences |
| Arrow keys | Move cursor |
| Enter (search field) | Next match |
| Esc | Clear selection |
| Option+drag | Column-block selection |

---

## 18. Preferences

Access via SeqAlignMac ▸ Settings… (Cmd+,).

- **Appearance**: Light / Dark / System
- **Default colour scheme**: Minimal, ClustalX, Zappo, SeaView, Default, Transition/Transversion
- **Font size**: stepper from 8 to 28 pt (default 13)
- **Show consensus**: toggle the consensus track
- **High contrast**: enhanced readability mode
- **Focus dim**: dim regions outside the selection
- **ClustalX threshold**: conservation cut-off, slider 0.1–0.9 in steps of 0.05 (default 0.3)
- **Consensus mode**: majority rule / identity thresholds
- **Codon triplet display**: group nucleotide columns in triplets
- **Language**: English / 简体中文 (applied immediately, no restart required)

---

## 19. Help Menu

- **Guide**: in-app quick-start guide
- **Load Example**: opens a built-in example alignment for trying the features
- **About**: version and project information

The command palette (Cmd+Shift+P) offers fuzzy-searchable access to most commands, including the guide and example loader.

---

## 20. Troubleshooting

**File not opening**: Ensure the file is in a supported format; detection is content-based, so a mislabelled extension is usually still fine. Try saving as FASTA first. For `.gz` files, ensure they are valid gzip streams.

**Slow with large alignments**: SeqAlignMac handles alignments up to ~10,000 sequences. For very large datasets, use the CLI `stats` command for statistics without launching the GUI.

**Primer Tm differs from other tools**: SeqAlignMac uses SantaLucia (1998) unified nearest-neighbour parameters with terminal correction and von Ahsen (1999) salt correction. Ensure the salt concentrations match. The Wallace rule gives a rough estimate only.

**Translation frame confusion**: Negative frames are on the reverse complement. Frame −1 starts from the first base of the reverse-complement sequence, −2 from the second, and so on.

**External aligner (Run MSA) fails to start**: The preset commands require `mafft`, `muscle`, or `clustalw2` to be installed and on your `PATH`. Verify with `which mafft` in a terminal, or use the Custom preset with a full path.

**Unit tests cannot run locally**: `swift test` requires the XCTest module shipped with full Xcode. With only the Command Line Tools installed, `build.sh` skips the tests with a warning; CI performs the full run.