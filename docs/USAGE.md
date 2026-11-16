# SeqAlignMac — Usage Guide

**Version:** 0.1.0 · **Audience:** end users (GUI and CLI) · **Document type:** task-oriented usage guide (使用文档) · **Primary language:** English

**Language:** English (primary) · [中文版](USAGE_ZH.md)
**Also read:** [Documentation index](README.md) · [Technical documentation](DOCUMENTATION.md)

This guide tells you *how to get things done*: which menu to open, which option to pick, and what the
numbers on the screen actually mean. Architecture, format specifications, metric derivations and the
known-limitations ledger live in [`DOCUMENTATION.md`](DOCUMENTATION.md); this guide links to it instead of
duplicating it.

---

## Table of Contents

1. [How to use this guide](#1-how-to-use-this-guide)
2. [Before you start](#2-before-you-start)
3. [Quick start (five minutes)](#3-quick-start-five-minutes)
4. [Opening files](#4-opening-files)
5. [Interface tour](#5-interface-tour)
6. [Reading the alignment](#6-reading-the-alignment)
7. [Editing the alignment](#7-editing-the-alignment)
8. [Searching](#8-searching)
9. [Analysis workflows](#9-analysis-workflows)
10. [External aligners](#10-external-aligners)
11. [Export](#11-export)
12. [Preferences](#12-preferences)
13. [Keyboard shortcuts](#13-keyboard-shortcuts)
14. [Command-line usage](#14-command-line-usage)
15. [Recipes](#15-recipes)
16. [Troubleshooting and FAQ](#16-troubleshooting-and-faq)
17. [Getting help and limitations](#17-getting-help-and-limitations)

---

## 1. How to use this guide

- Sections 2–5 are setup and orientation. Read them once.
- Sections 6–12 are feature tasks. Each one starts with the menu path so you can jump straight in.
- Sections 13–14 are reference tables (shortcuts, CLI flags).
- Sections 15–16 are worked end-to-end workflows and answers to failure messages.

Menu labels are quoted exactly as the English UI shows them, using the convention
`File ▸ Open File…`. Keyboard symbols: ⌘ (Command), ⇧ (Shift), ⌥ (Option), ⌃ (Control).

A few on-screen strings are Chinese-only even in the English interface (canvas tooltips, image-export
errors, CLI progress lines). Where that matters for your workflow, this guide says so explicitly.

---

## 2. Before you start

### 2.1 System requirements

| Requirement | Value |
|---|---|
| Operating system | macOS 14.0 or later (declared as `LSMinimumSystemVersion`, and as the SwiftPM platform floor) |
| Processor architecture | **Apple Silicon (`arm64`) only.** The shipped build has no `x86_64` slice, so it is not a universal binary; Intel Macs are not supported by the pre-built archive |
| Display | Any; the default window is 1500 × 880 pt with a minimum of 1100 × 520 pt |
| Disk | A few tens of megabytes for the bundle and the distribution zip |

### 2.2 Getting the app

Build it from a checkout of this repository:

```bash
chmod +x build.sh          # some checkouts lose the executable bit
bash build.sh              # or: ./build.sh
```

If `./build.sh` fails with "permission denied", the file mode was not restored on checkout; either run
`chmod +x build.sh` once or invoke it through `bash` as shown above.

Useful flags (any other argument is ignored silently):

```bash
./build.sh --open          # launch the app when the build finishes
./build.sh --skip-tests    # skip the unit-test gate
```

The build runs several stages in order: it moves any previous bundle aside, assembles the `.app`
skeleton, copies `Info.plist`, runs `swift test` **if** a `swift` toolchain and the XCTest module are
available (on a Command-Line-Tools-only machine it prints a warning and continues), compiles every file
under `Sources/` with `swiftc -O -target arm64-apple-macosx14.0`, generates the app icon, copies
`logo.svg` and the privacy manifest, code-signs the bundle, zips it, and optionally notarizes it.

Artefacts land next to the script, at the repository root:

| Artefact | Contents |
|---|---|
| `SeqAlignMac.app` | The application bundle (`Contents/MacOS/SeqAlignMac` is the executable, which is also the CLI) |
| `SeqAlignMac.app.zip` | The distributable archive, produced with `ditto -c -k --keepParent` |

Both are git-ignored build output. CI uploads the same zip as the artifact named `SeqAlignMac-app`
(14-day retention); there are no `.dmg` images and no Homebrew cask, so building from source or using a
CI artifact is how you obtain the app.

### 2.3 Signing, Gatekeeper, and first launch

Unless you export a `DEVELOPER_ID` before building, the script falls back to **ad-hoc signing**
(`codesign --force --deep --sign -`), and notarization runs only when *both* `DEVELOPER_ID` and
`NOTARY_PROFILE` are set. So the app you build locally is ad-hoc signed and unsigned-by-Apple — that is
expected, not a defect.

What that means in practice:

- **Built locally from source:** Gatekeeper does not complain, because the bundle never carried the
  quarantine attribute. Double-click `SeqAlignMac.app` to launch it.
- **Downloaded as `SeqAlignMac.app.zip`** (from a CI artifact or a file share): macOS tags it with
  `com.apple.quarantine`, so the first launch may be blocked with "cannot be opened because the developer
  cannot be verified" or "damaged". Resolve it in one of these ways:
  1. Right-click (or Control-click) the app in Finder ▸ **Open** ▸ **Open** in the confirmation dialog.
  2. System Settings ▸ Privacy & Security ▸ **Open Anyway**, after the block notice appears.
  3. Clear quarantine from the terminal: `xattr -dr com.apple.quarantine SeqAlignMac.app`.
- Verify what you received before launching:

  ```bash
  codesign --verify --verbose SeqAlignMac.app
  spctl -a -vv SeqAlignMac.app     # an ad-hoc build is intentionally rejected by spctl
  ```

The hardened runtime and the app-sandbox entitlements are *not* enabled by default; the sandbox is
opt-in at signing time (`SEQALIGN_SANDBOX=1`), and it forbids launching external aligner binaries.

On the very first launch, SeqAlignMac shows a one-time hint toast telling you that files can be dropped
onto the window and that the sidebar holds the tool buttons. The window opens at 1500 × 880 pt; resize it
down to a minimum of 1100 × 520 pt.

---

## 3. Quick start (five minutes)

Work through these seven steps once; each is one screen.

1. **Open a file.** Choose `File ▸ Open File…` (⌘O), select `alignment.fasta`, and click **Open**.
   A large file shows a "Parsing file… N %" overlay with a Cancel button; when it disappears the canvas
   is ready. Alternatively drag the file onto the window, or run
   `open -a SeqAlignMac alignment.fasta`.
2. **Look at the canvas.** The frozen name column is on the left, a thin conservation rail runs along the
   top, then the column ruler, then the residue grid, and the consensus row sits below the ruler. The
   right-hand panel already shows live statistics; the status bar at the bottom shows sequence count,
   column count, cursor position, the residue under the cursor, column identity and data type.
3. **Scroll.** Use the always-visible horizontal and vertical scroll bars, or the scroll wheel. Sequence
   names stay pinned on the left as you scroll right.
4. **Select a region.** Drag across cells to make a rectangular selection, or ⌥-drag to select whole
   columns. Press Esc to clear. ⌘A selects the entire alignment.
5. **Switch colour scheme.** Choose `View ▸ Okabe-Ito (CVD-safe)` or press ⇧⌘5. `⇧⌘1` returns you to
   Minimal, the built-in default.
6. **Export a PNG.** Press ⇧⌘E to open `Export Preview`, check the estimated size, click **Export…**,
   then choose a destination. (Or `File ▸ Export as PNG` to skip the preview.)
7. **Convert a file on the command line.**

   ```bash
   SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli convert alignment.fasta --format nexus -o alignment.nexus
   ```

From here, sections 4 onward cover each task in detail. If you just want the alignment statistics for a
pipeline, run `SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli stats alignment.fasta --out stats.csv`.

---

## 4. Opening files

### 4.1 Supported formats and extensions

SeqAlignMac reads and writes seven alignment formats. Compression is handled transparently, so any of the
following extensions may also appear as `…fasta.gz`, `…nex.gz`, and so on.

| Format | Extensions the Open panel shows | Typical extras declared in the bundle | Notes |
|---|---|---|---|
| FASTA | `.fasta`, `.fa`, `.fas` | `.fna`, `.faa`, `.mpfa` | The three extras are declared for Finder but are **not** in the Open panel's list; drop them on the window instead |
| FASTQ | `.fastq`, `.fq` | — | Phred quality is parsed and kept |
| NEXUS | `.nexus`, `.nex` | — | `DATA`/`CHARACTERS` matrix plus `SETS`/`CHARSET` |
| PHYLIP | `.phy`, `.phylip` | — | Sequential, interleaved, strict-10 and padded-name layouts are distinguished automatically |
| CLUSTAL | `.aln` | — | MAFFT-style headerless output is also accepted |
| MSF | `.msf` | — | GCG multiple-alignment format |
| Stockholm | `.sto`, `.stockholm` | — | Pfam/Rfam style |
| Gzip archive | `.gz` | — | Opened as a viewer, decompressed to whichever alignment format is inside |

The format is decided from the **first 64 KB of content**, not from the file name, so a FASTA file named
`data.txt` still opens correctly and a mislabelled extension is usually harmless. If the sniffed format is
unrecognised, SeqAlignMac falls back to FASTA parsing.

### 4.2 Ways to open

1. `File ▸ Open File…` (⌘O).
2. Drag a file onto the window: the first dropped file replaces the current tab, each later file opens in
   its own new tab.
3. `open -a SeqAlignMac alignment.fasta` from a terminal.
4. Double-click a file in Finder once the app is registered for that document type.
5. `File ▸ Open Recent` — the last ten paths, with missing ones greyed out.
6. A built-in demo: `Help ▸ Load Example Data`, or the **Example** button in the sidebar's File group,
   loads a small four-sequence alignment so you can explore before opening real data.

### 4.3 Compressed input

- Decompression is keyed off the **`.gz` extension**: a gzip payload named `alignment.fasta` is not
  decompressed. Rename it to `alignment.fasta.gz` if you need that.
- Single-member gzip and multi-member **BGZF** streams (the block format produced by `bgzip`) are both
  accepted, so a bgzipped FASTA opens in one pass.
- Naive concatenations such as `cat a.gz b.gz > both.gz` are **refused with an explicit error** rather
  than being half-read. Unzip and re-gzip them properly, or open the members separately.
- Saving with ⌘S keeps the original compression (a `.gz` source is re-gzipped). **Save As** writes an
  uncompressed copy.

### 4.4 Bad input is an error, never a silent truncation

SeqAlignMac reports malformed files instead of opening a partial alignment. You will see messages such as
"illegal character 'x' at line N", "PHYLIP data lines fewer than declared `ntax`", "sequence X has no
residues", "MSF: sequence X length disagrees with the `Len:` header", "FASTQ quality line length does not
match the residue line" and "no records parsed". A file that opens but looks wrong is therefore much more
likely to be a genuine format mismatch than a parser bug. (Some of these strings are currently
Chinese-only; see section 16.)

### 4.5 Ragged and unaligned input

If the sequences in a file are not the same length, SeqAlignMac right-pads them with `-` so the canvas can
render a rectangle, and it records the provenance of the file:

| Provenance | Meaning |
|---|---|
| `aligned` | Equal-length rows with at least one internal gap — the rows really are homologous column-by-column |
| `unknown` | Equal-length rows with no internal gaps (indistinguishable from an un-gapped alignment), or empty input |
| `not-aligned` | Rows of different lengths — homology across columns does **not** hold |

When provenance is `not-aligned`, the right-hand statistics panel shows an orange banner warning that
column statistics and trees are unreliable and that you should align first. **Analysis is not disabled** —
you can still open the logo, the tree, the window chart and the quality report; the app simply tells you
the numbers are not trustworthy. The same value is exported by the CLI as the CSV field `declared_aligned`.
To fix the data, run an external aligner (section 10).

### 4.6 Large files

- The canvas is virtualised: only the rows and columns inside the visible rectangle are drawn, and repaint
  is limited to the newly exposed strip, so scrolling cost does not depend on total alignment size.
- Parsing runs in the background with a percentage overlay and a Cancel button.
- Column statistics for the canvas are computed off the main thread; if they are not ready yet, the canvas
  degrades to uncoloured cells rather than freezing. The statistics panel refreshes when its pass lands.
- No sequence-count capacity figure is published, because none has been measured. For unattended very
  large jobs, prefer the CLI (section 14), which has no rendering cost at all.

### 4.7 What each format loses on a round trip

Convert or re-save with your eyes open. The following information does not survive:

| Format | Lost or altered on write |
|---|---|
| FASTA | Quality values (use FASTQ), structured header fields beyond the free-text description after the first space. Written one line per sequence: the library supports line wrapping (`wrapWidth`) but **no GUI or CLI option exposes it** |
| FASTQ | Gap-padded columns get quality `!` (Q0); quality above Phred 93 is **clamped** when writing; the `+` line never repeats the header; read-group/`B` tags are not parsed |
| NEXUS | Everything outside `DATA`/`CHARACTERS` and `SETS`: `[...]` comments, `FEATURES`, `TREES`, `ASSUMPTIONS`, `LABELS`, `STATES`, `SYMBOLS`, `PARTITIONS`, `&`-annotations, and per-character state frequencies. Alignment metadata is **never** preserved (the writer's `includeMetadata` flag only gates the `SETS` block). Names are padded, not truncated. Note that `.` is not an accepted gap byte in a NEXUS matrix, unlike the other formats |
| PHYLIP | **Sequence names are truncated to 10 characters** (9 in the strict/sequential layout) and collisions are disambiguated in-place with `.1`, `.2`, …; descriptions are dropped; gap spellings are collapsed to `-`; sequential-versus-interleaved is recovered only heuristically. The four writer variants exist in the library but the app and CLI always write the interleaved form |
| CLUSTAL | The conservation line is not written by the app (the option exists in the library only); block structure is rewritten at 60 columns |
| MSF | `Weight:` is always `1.00`; reference/rank lines from real GCG output are ignored; the writer emits the GCG checksum (position-weighted, mod 10000) in both the `MSF:` and `Check:` fields |
| Stockholm | `#=GC RF` is parsed and **then discarded** — the reference consensus does not round-trip; per-sequence `#=GS` annotations are not read; only `#=GF ID`, `AC` and `SQ` are involved; `#=GF SQ` is written but never read back; spaces in names are replaced by `_` |

Gap spellings `.`, `~` and `-` are normalised to `-` at parse time in every format except the NEXUS matrix
parser, so a `GAP=.` NEXUS file fails with "illegal character `.`".

---

## 5. Interface tour

### 5.1 The three panels

Every window has three always-visible areas; there is no floating toolbar, the buttons live in the sidebar.

- **Left sidebar** (default width 180 pt, clamped to 150–320 pt), grouped as `File`, `Analysis`, `View`,
  `Export`, `System`: Open, Save, Example; Align, Translate, Primer, Quality, Logo, NJ Tree, Window,
  Annot; Color Scheme picker, Diff toggle, Search, Undo, Redo, zoom controls; Export ▸ Sequence/Image;
  Settings, Command Palette, Appearance and Language buttons at the bottom. On protein data, **Translate**
  and **Primer** are disabled with the tooltip "Only applicable to nucleotide sequences".
- **Centre canvas**: the frozen name column, the conservation rail, the column ruler, the residue grid, and
  the consensus row.
- **Right statistics panel** (default 264 pt, clamped to 220–460 pt): live quality, phylogenetic and
  conservation metrics, the consensus string, cursor information, and the definitions footer.

Drag the vertical dividers between panels to resize them; both widths are remembered between launches. The
name column divider inside the canvas is also draggable (80–2000 pt, default 150 pt), and that width is
remembered too.

### 5.2 Tabs and windows

Each window carries a tab strip in the title bar. **Every tab holds its own alignment with its own undo
stack.** Dirty tabs are prefixed with `• ` and show a ✕ on hover or when active. Only the three most
recently used tabs keep their live state; the rest are rebuilt when you return to them, so an unrecent tab
loses transient selection but not saved data.

This is the single most common point of confusion, so state it plainly:

| Key | What it closes |
|---|---|
| ⌘W | the **tab** (`File ▸ Close Tab`); closing the last tab in a window closes that window |
| ⇧⌘W | the **window** (`File ▸ Close Window`), and with it every tab inside |

⌘T opens a new tab, ⌘N opens a new window. Closing a dirty tab or window raises a sheet reading "… has
unsaved edits. Save?" with **Save**, **Don't Save**, **Cancel**. Quitting with dirty documents anywhere
raises a system dialog with **Save and Quit**, **Don't Save**, **Cancel**; if any save fails, quitting is
aborted so nothing is lost.

### 5.3 Status bar

From left to right: sequence count (`Seqs`), column count (`Cols`), cursor position as `row, column`,
residue under the cursor (`Residue`), column identity at the cursor (`Identity`, a whole-number percent),
data type (`Type`: Nucleotide or Amino Acid), a **`Charset`** field showing the number of NEXUS `CHARSET`
partitions when the file has any (this field's label is English-only by construction), and at the far right
the file name with a `●` unsaved marker, or `No file open`. The status bar shows a saving/exporting
indicator with a spinner while work is in flight. Hovering the file name shows the full path in a tooltip.

### 5.4 Command palette

Press ⇧⌘P (`Tools ▸ Command Palette`) to open it. It lists 32 commands — open/save, run aligner,
translate, primer, quality, search, copy, select all, reverse complement, insert gap, delete/rename/move
sequence, six of the seven colour schemes, zoom in/out/reset, toggle consensus, light/dark/system,
settings, guide, example and about.

Know the two limitations before relying on it:

- Filtering is **substring** matching on the command title, not fuzzy matching. Search "gap" to find
  Insert Gap; searching "insgap" finds nothing.
- It has **no** entry for the Okabe-Ito scheme, for any export action, for Find Next/Previous, for
  Undo/Redo, or for the Logo, NJ Tree, Window and Annotation sheets. Use the sidebar or the menus (or the
  shortcuts in section 13) for those.

Navigate with ↑/↓, run with Return, dismiss with Esc.

---

## 6. Reading the alignment

### 6.1 The seven colour schemes

Reach: the **Color Scheme** picker in the sidebar's View group, `View` menu, the canvas right-click
`Color Scheme ▸` submenu, Preferences, or the shortcuts below. Minimal is the default on first launch.

| Scheme | Shortcut | What it colours by | Pick it when |
|---|---|---|---|
| Minimal | ⇧⌘1 | Conservation only — a five-step grey ramp from column identity; gaps are blank | You want a neutral, print-safe overview of which columns are conserved, independent of residue chemistry |
| Default | none | Standard nucleotide classes: A, C, G, T/U, N, gap, and everything degenerate lumped together | Everyday nucleotide reading; this is the palette most other tools show |
| ClustalX | ⇧⌘2 | Physicochemical groups (`AVLIMFW`, `KRH`, `DE`, `NQST`, `CGP`, `Y`) with **threshold gating** | Comparing against ClustalX screenshots |
| Zappo | ⇧⌘3 | Functional/chemical grouping (`AVLIMC`, `FWY`, `KRH`, `DE`, `STNQ`, `GP`) | Spotting conservative substitutions within a functional class |
| SeaView | ⇧⌘4 | A coarser four-group simplification (`AILMVFWC`, `KR`, `STNDEQGP`, `HY`) | A quick "same-ish / different" read on protein alignments |
| Ti/Tv | none | Purine↔purine and pyrimidine↔pyrimidine transitions versus transversions | Population and haplotype work on nucleotide data |
| Okabe-Ito (CVD-safe) | ⇧⌘5 | The Okabe–Ito colour-vision-deficiency palette (Wong 2011) | Figures for journals and reviewers; any reader with red-green colour blindness |

Details worth knowing:

- **ClustalX threshold.** Columns whose identity falls below the threshold are left uncoloured. The slider
  in Preferences runs 0.1–0.9 in steps of 0.05 and defaults to **0.3**. This is the one preference that is
  *not* persisted; it returns to 0.3 on every launch.
- **Scheme/datatype compatibility.** ClustalX, Zappo and SeaView are protein-oriented palettes; applied to
  nucleotide data SeqAlignMac silently renders them with the Default nucleotide colours, and Ti/Tv applied
  to protein data renders as Minimal. Those three schemes are also appearance-invariant, so screenshots
  stay comparable with the reference tools; Minimal, Default, Ti/Tv and Okabe-Ito have tuned dark-mode
  variants.
- The **Color Legend** popover (sidebar, View group) explains the current palette and the canvas gestures.

### 6.2 Consensus row

Toggle with `View ▸ Show/Hide Consensus` (⇧⌘G — see the conflict note in section 8.5). The consensus glyph
follows the **Consensus Mode** preference:

| Mode | Output |
|---|---|
| Majority Rule | The most frequent residue in the column (ties resolved toward the alphabetically earlier residue) |
| IUPAC Degenerate | A single IUPAC code covering the observed set (nucleotides only; protein columns fall back to majority) |
| Strict | The residue only if the column is invariant, otherwise `N` (nucleotide) or `X` (protein) |

The mode changes **only the consensus letter**. Identity percentages, the conservation rail, colouring, the
pooled identity figure and the NJ tree always use the majority rule, so switching modes does not change any
number you are comparing across sessions.

### 6.3 Conservation rail

The thin rail above the grid plots per-column identity: in Minimal it is a five-step grey ramp; in the
scientific schemes it is the consensus residue's colour with alpha proportional to identity, plus a bright
cap on fully conserved columns. **Click or drag on the rail** to scrub: the canvas scrolls that column into
the middle of the viewport, which is the fastest way to jump along a long alignment.

### 6.4 Difference mode

Turn on **Diff** in the sidebar's View group. Residues equal to the row under the cursor at the moment you
enable it are rendered without a background fill, so variation against that reference row pops out. The
reference row is whatever row the cursor was on; move the cursor and re-toggle to change it. Difference
mode and the reference row are **not persisted** — both reset at next launch.

### 6.5 Zoom, and why the letters disappear

| Action | How |
|---|---|
| Zoom in | ⌘= (a ⌘+ entry also exists), the **+** button in View, ⌘-scroll-wheel up, or a pinch gesture |
| Zoom out | ⌘-, the **−** button, ⌘-scroll down, or pinch out |
| Reset | ⇧⌘0, which returns the font to 13 pt (displayed as 100 %) |
| Range | 8–28 pt; the setting is persisted |

Column width is derived from the measured advance width of a character in the monospaced font, so it grows
linearly with the font size. **Below roughly 6 px per column, the canvas stops drawing letters entirely and
draws only colour blocks.** This is deliberate: at that density glyphs overlap and are unreadable, while the
coloured blocks still carry the full identity and palette information. It is a support question we get
often, and the fix is simply to zoom in (⌘= a few times, or ⇧⌘0). Row height is unaffected by the switch, so
the vertical rhythm of your screenshot does not change when letters vanish. The ruler shows a number every
ten columns and shrinks its font as needed to keep four- and five-digit positions legible.

### 6.6 Selecting

| Selection | Gesture |
|---|---|
| Single cell (cursor) | Click a cell, or move with the arrow keys |
| Rectangular block | Drag across cells |
| Whole columns | ⌥-drag |
| Whole alignment | ⌘A |
| Clear | Esc |

Copying (⌘C) emits the selected block as FASTA. "Export selection only" ignores a lone cursor cell — after a
single click there is no active selection, so tick the option only after a real drag.

---

## 7. Editing the alignment

All edits are recorded on the per-tab undo stack.

### 7.1 Sequence-level operations

| Task | Reach | Effect |
|---|---|---|
| Rename a sequence | ⇧⌘R, double-click its name, `Edit ▸ Rename Sequence`, or the canvas right-click | A sheet with one field; the change is one undo step |
| Reorder a sequence | Drag its name up or down in the name column (an insertion indicator appears), or `Edit ▸ Move Sequence…`, or right-click ▸ `Move to Top` / `Move to Bottom` | **Move Sequence has no keyboard shortcut** |
| Delete a sequence | ⇧⌘X (`Edit ▸ Delete Selected Sequence`) while the cursor is on the row | Removed rows are restored by undo |
| Add a sequence | Canvas right-click ▸ `Add Sequence…` | Padded to the current width as needed |
| Reverse complement | ⌘I, or right-click | Nucleotide data only; on protein data the command does nothing |
| Sort | Right-click ▸ `Sort By`: Name, Similarity to Consensus, GC Content, Length (with gaps), Length (no gaps) | Sorting runs in the background; if you edit during the sort, the stale result is thrown away and recomputed |
| Paste | ⌘V | If the clipboard contains `>`, it is parsed as FASTA; otherwise each non-empty line becomes a sequence named `Pasted_N`. Unrecognisable clipboard content raises "Cannot parse clipboard: please paste FASTA or raw sequences" |

### 7.2 Column operations

| Task | Reach | Detail |
|---|---|---|
| Insert a gap column | ⌘D | Inserts one gap column at the cursor position |
| Cut | ⌘X | When the canvas has a selection, "Cut" copies the block **and** inserts gaps in it; otherwise it is the normal responder cut. Do not expect a deletion |
| Remove all-gap columns | Right-click ▸ `Gap Trimming ▸ Remove All-Gap Columns` | Columns with no assignable residue |
| Remove high-gap columns | Right-click ▸ `Gap Trimming ▸ Remove High-Gap Columns (>50%)` | Columns where gaps exceed half the rows |

Removing columns also re-maps NEXUS `CHARSET` partitions, and undo restores the original partitions.

### 7.3 Residue-level editing and IUPAC input

There is **no in-canvas text editor**: the canvas consumes only the arrow keys and Esc, so you cannot type
a new residue into a cell or wrap/unwrap a row by keyboard. Residue changes are therefore made by the
whole-column and whole-row operations above, by pasting a corrected sequence, or in your text editor of
choice followed by a reload. IUPAC degenerate codes (`R`, `Y`, `S`, `W`, `K`, `M`, `B`, `D`, `H`, `V`, `N`)
are accepted and preserved in FASTA, NEXUS, PHYLIP, CLUSTAL, MSF and Stockholm input, and they participate
in search and in the statistics exactly as documented in sections 8 and 9.

A batch residue-replace command does exist inside the core library (and undoes as one step), but **no GUI
menu item or CLI flag invokes it today**, so it is not a user-facing feature.

### 7.4 Undo and redo

| Key | Action |
|---|---|
| ⌘Z | Undo |
| ⇧⌘Z | Redo |

- The stack is capped by **two budgets**: 50 entries **and** 256 MiB. When either is exceeded, the *oldest*
  steps are dropped, and at least one step is always kept so the last edit remains undoable.
- Grouped operations (gap trimming, sorting, a multi-part scripted edit) are recorded as a **transaction**
  and undone as one step; the undo toast names the transaction with its step count.
- Performing a new edit clears the redo stack.
- **There is no keystroke coalescing.** SeqAlignMac does not merge repeated identical edits, so ⌘Z never
  rewinds a burst of typing as one unit — the only aggregation is the explicit transaction API. If you
  expected "undo the last five characters", that behaviour does not exist.
- Each tab has its own stack; switching tabs does not share or clear history.

---

## 8. Searching

Open the search bar with ⌘F (`Tools ▸ Search`), the sidebar **Search** button, or the command palette.

### 8.1 Scope and mode

- **Scope pills**: `Content` searches residues, `Name` searches sequence names (species or identifiers).
- **Regex toggle**: switches between IUPAC-pattern matching and regular expressions.
- Typing debounces for **300 ms** before a search is computed; changing a pill or a toggle searches
  immediately. The bar shows a spinner while a query is computing, and `0 / 0` with "No matches" when
  nothing was found.
- The ✕ button closes the bar and cancels any pending computation. Rapid typing also cancels superseded
  searches, so stale results never land on top of newer ones.

### 8.2 IUPAC degenerate patterns

In non-regex `Content` mode, degenerate letters are expanded before matching:

| Code | Matches | Code | Matches |
|---|---|---|---|
| `R` | A, G | `B` | C, G, T |
| `Y` | C, T | `D` | A, G, T |
| `S` | G, C | `H` | A, C, T |
| `W` | A, T | `V` | A, C, G |
| `K` | G, T | `N` | A, C, G, T **and** a literal `N` |
| `M` | A, C | | |

Two extra rules matter when you search real files: every code also matches its own literal character (so a
query of `NNN` can find `NNN` in the data, not only `ACG`), and `T` and `U` are treated as equivalent.
Patternless matches of a plain letter use an exact matcher, and overlapping occurrences are reported —
searching `AA` in a run of five `A`s gives you all four positions.

### 8.3 Regex mode

Enable the regex toggle and the field placeholder changes to `Sequence regex (e.g. A[TC]G{2,})` for content
or `Name regex (e.g. Homo.*BRCA1)` for names. Notes:

- Literals in your pattern are upper-cased for case-insensitive matching, but escape sequences and
  character classes (`\d`, `\w`, `\s`, `\b`, `[...]`) are preserved, so `\d+` does not silently become
  `\D+`.
- IUPAC-to-class expansion is applied to the **content** scope only; a name-scope regex sees your pattern as
  written.
- Regex matches are non-overlapping (the scan advances past each hit), unlike the IUPAC path.
- An invalid pattern is rejected before the search runs, with `Invalid regex: ` followed by your pattern,
  and no hits are reported.

### 8.4 Navigating matches

The counter reads `current / total`. ⌘G jumps to the next match; the **Prev** button in the search bar steps
backwards. The current hit is outlined in blue with a stronger stroke, other hits are outlined thinly, and
every hit is also marked with a tick on the column ruler so you can see the distribution at a glance.
Hits in `Name` scope highlight the entire row.

### 8.5 The ⇧⌘G caveat, and how to reach "Find Previous"

⇧⌘G is registered **twice** in the menu tree: once for `View ▸ Show/Hide Consensus` and once for
`Tools ▸ Find Previous`. The View menu is built before the Tools menu, so the consensus toggle wins and
**Find Previous is effectively not reachable by keyboard**. Do not rely on a "shift-Cmd-G goes backwards"
muscle memory inherited from other editors. To step backwards:

1. Click **Prev** in the search bar (the reliable route), or
2. Choose `Tools ▸ Find Previous` from the menu with the mouse.

The command palette lists ⇧⌘G only against "Show/Hide Consensus" and has no Find entries at all, so it is
not a route to Find Previous either.

---

## 9. Analysis workflows

Each subsection is a task: where to click, then what the numbers mean.

### 9.1 Quality statistics you can trust

There are three different statistics surfaces, and they do not show the same rows.

**A. The live statistics panel (right side, always visible).** Cards, top to bottom:

1. `Overview` — file name, format, sequence count, column count, data type.
2. `Quality` — the unaligned banner when relevant, then **Pooled identity (site-weighted)**, Mean / Min /
   Max column identity, Gap columns, Total columns.
3. `Phylogenetic Information` — Variable Sites, Parsimony-Informative Sites, Singleton Sites.
4. `Conservation` — a five-bucket histogram of column identity (darker bars = more conserved) and the
   High conserved (≥80%) count.
5. `Consensus length` — the consensus string, its length **expressed as a column count**, and a Copy button.
6. `Read Quality` — only for FASTQ sources: Mean Phred, Min Phred, ≥Q20 bases, ≥Q30 bases.
7. `Cursor` — position, residue and identity under the cursor.
8. A footer defining every metric.

**B. The Quality report sheet** — `Tools ▸ Alignment Quality` (sidebar **Quality**). It shows pooled
identity, min/max column identity, gap columns, total columns, consensus length, the FASTQ rows when
quality data exists, and the list of NEXUS `CHARSET` names. It does **not** show GC content and does **not**
show the variable/parsimony/singleton site counts — those live in the live panel and in the CLI CSV.

**C. The CLI CSV** (`cli stats`) — the widest set, including `gc_content` and `declared_aligned`.

How the headline numbers are computed, so you can describe them correctly in a methods section:

- **Column identity** `I = (count of the most frequent residue) / (number of assignable residues in the
  column)`. The denominator excludes gaps **and** undetermined states (`N`, `X`, `?` and their protein
  equivalents). A column that is entirely gap or entirely undetermined scores **0**, not 1.
- **Gap columns** means "columns with no assignable residue at all": all-gap columns **and** all-`N`/all-`X`/
  all-`?` columns. The panel label "Gap columns" (and the older Chinese label "含空位列数", "columns containing
  gaps") under-describes this; do not read it as "columns containing any gap".
- **Pooled identity (site-weighted)** is *not* the mean of all pairwise sequence identities. Formally
  `Σ_columns Σ_residues f·(f−1) / Σ_columns n·(n−1)`: for each column it accumulates the probability that
  two residues drawn from that column match, weighted by how many comparable residues the column actually
  holds. Consequence: it behaves like a site-weighted average, so a metric of the same name from a tool
  that averages per-pair identities will give a slightly different number. An exact per-pair implementation
  exists in the library but is not surfaced anywhere in the UI or CLI.
- **Sites** are counted over defined residues only: a *variable site* has two or more distinct defined
  states; a *parsimony-informative site* additionally has at least two states each occurring two or more
  times; a *singleton site* is one where the most common state occurs exactly one fewer time than the total
  (an autapomorphy) and the site is not parsimony-informative.
- **FASTQ quality** is pooled over all bases of all reads that carry quality: `Mean Phred = Σq / total bases`,
  `Min Phred` (reported as 0 when there is no quality data), `Q20 ratio = #{q ≥ 20} / total bases`,
  `Q30 ratio = #{q ≥ 30} / total bases`. The ratios are per **base**, not per read; the read count is the
  number of rows that carry quality.

Site counts are computed over **all** rows; the 200-sequence subsampling described in section 9.3 applies to
the neighbour-joining tree only. Statistics recompute in the background after each edit, so a busy file may
show slightly lagging numbers for a moment.

### 9.2 Sequence logo

1. Click **Logo** in the sidebar's Analysis group.
2. Page through the alignment with ‹ / ›; 120 columns are drawn per page, and column positions are labelled
   every ten columns.
3. Read the height scale: the axis tops out at 2.0 bits for nucleotides and 4.3 bits for amino acids.

Interpretation: each stack's total height is the information content
`R = log2(K) − (H + e(n))` (Schneider–Stephens 1990), where `K` is 4 for nucleotides and 20 for amino
acids, `H` is the Shannon entropy of the column, and `e(n) = (K − 1) / (2·ln2·n)` is the small-sample
correction for `n` observed residues. Individual letters are scaled by their fraction of the column. Gaps
are excluded, and ambiguous residues are **not** fractionally redistributed — only assignable states count,
so an `N`-heavy column looks less informative than its raw variability suggests.

Long alignments are capped: the calculator stops after **4,000 columns** and the sheet prints an
omitted-columns notice. If your logo says it is truncated, page through the crop you actually care about
(section 14's `convert --start/--end` produces a small file for exactly this).

### 9.3 Neighbour-joining tree

1. Click **NJ Tree** in the sidebar's Analysis group.
2. Wait for the Newick string in the pane; the header reports whether subsampling occurred.
3. Click **Copy Newick** and paste it into your tree viewer (it is plain text; SeqAlignMac has no tree
   drawing canvas of its own).

Method and caveats, as the code implements them:

- Distances are **uncorrected p-distance**: `d = 1 − matches / comparable`, where a position is comparable
  only if neither byte is a gap **and** neither is `N` or `X`. A pair with no comparable site is given
  `d = 1.0`. No Jukes–Cantor or Kimura correction is applied, so the tree is appropriate only for **closely
  related, low-divergence** sequences. The sheet states this disclaimer; treat it as binding.
- Above 200 sequences the input is **subsampled to 200 sequences by equal-interval stride**, not by taking
  the first 200 in file order. (An earlier text in the app hints at "first 200"; the sampler takes every
  `n/200`-th sequence, which is what the disclosure means.)
- The Newick carries an NHX-style provenance comment at the root, of the form
  `[&sampled=<used>_of_<total>;model=p-distance;clamped=<n>]`. Keep it when you archive the tree, and be
  aware that some downstream tools reject or strip comments.
- Negative branch lengths are **clamped to 0** and the number of clamped branches is reported on screen and
  in that comment — a large count is a sign that p-distance is too crude for your data.
- Two-sequence input is handled exactly (both tips get half the pairwise distance); one or zero sequences
  yield a trivial tree. Tip names are made unique before writing.
- Branch lengths are printed with five decimals.

Editing the alignment marks the tree dirty, so reopening the sheet recomputes it.

### 9.4 Sliding-window identity

1. Click **Window** in the Analysis group.
2. Drag the **Window size** slider (5–500 columns, step 5; default 50).

The chart averages per-column identity over the window and plots it against the true window centre; grid
lines mark 0/25/50/75/100 %. Steps are half a window, so consecutive points overlap, and a final short
window is always emitted to reach the last column. Use it to locate conserved blocks (candidate primer or
probe regions) and variable segments (candidate genotyping regions) at a glance. The per-column identity
vector is cached, so dragging the slider is cheap and does not re-scan the alignment.

### 9.5 Six-frame translation

1. Click **Translate** in the Analysis group, or press ⇧⌘T (`Tools ▸ Translate to Amino Acid`).
2. Pick a genetic code table, a reading frame, a display mode, the name handling and whether the result
   opens in a new window; then press Return or click **Translate**.
3. Read the warning line that appears under the controls; multiple warnings are joined with " · ".

**Genetic code tables (17 implemented).** The picker lists the tables by NCBI number with a short English
label (for example `Standard (1)` … `Peritrich Nuclear (30)`); those labels are literals in the source and are
not localised. The numbers and conventional NCBI designations below are what the picker covers:

| NCBI no. | Table | NCBI no. | Table |
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

Any other NCBI number is simply not offered; there is no silent fallback to the standard code.

**Reading frame.** The picker shows −3, −2, −1, +1, +2, +3. Negative frames reverse-complement the sequence
first and then start at offset (`|frame| − 1`); positive frames start at offset 0, 1, 2 for +1, +2, +3
internally. The alignment columns are the reference frame, so +1 starts at the first column.

**Display mode.**

| Mode | Output | Data type of the result |
|---|---|---|
| Codon only | The frame-adjusted nucleotide sequence | Nucleotide |
| Amino acid | One residue per codon | Amino acid |
| Both | Codon and amino acid interleaved, three bases then one residue | Nucleotide, but flagged as a mixed track |
| Ignore gaps | Gaps stripped before translating | Amino acid, provenance reset to `unknown` |

**Name handling.** Keep the original names, or append an `_AA` suffix. **Open result in new window** is on by
default, which preserves the current alignment; turning it off replaces the alignment in place, and that
replacement is undoable with ⌘Z (the toast says so).

**Warnings and what they mean for downstream work:**

| Warning | Meaning |
|---|---|
| Frameshift | A run of internal gaps whose length is not a multiple of 3 puts the downstream frame out of phase; from that codon onward the output is `X`, and the message names the sequence and column |
| Length not a multiple of three | The alignment was right-padded with gaps before translating so the last codon is not silently dropped |
| Mixed codon track | The "Both" display mixes nucleotide and amino-acid characters in one track: display only — it cannot be used for statistics or tree building, and image export refuses it |
| Ragged output | Ignore-gaps mode yields rows of differing length, decoupled from the source columns — not usable for phylogenetics |
| Not nucleotide input | Protein data cannot be translated; the input is echoed back unchanged |

Any of mixed track / ragged output / frameshift / non-nucleotide input makes the result explicitly
*unsafe for phylogenetics* — that verdict is computed by the translator and surfaced in the sheet.
Amino acids are `X` whenever a codon contains a gap, when the codon is not in the table, or after a frameshift;
SeqAlignMac never fabricates a residue it cannot derive.

**Caveat:** an older "Select Codon Position / Position 1·2·3" entry survives in the app's string table, but
the shipped UI has **no codon-position picker**. Do not look for it; emulate it by translating with frames
+1/+2/+3 and comparing.

### 9.6 Primer calculator

1. Select a row range on the canvas and click **Fill from selection** (gaps are stripped), or type a
   sequence into `Sequence A:`. For a heterodimer check, fill `Sequence B (for heterodimer):`.
2. Set the salt conditions: `Na+` (default 50 mM), `Mg2+` (default 0 mM), `Oligo` (default 0.25 µM). All
   three persist between launches. Negative or non-numeric entries are rejected; a half-typed number is
   ignored rather than applied.
3. Press **Calc Tm**, **Calc GC%**, **Self-dimer** or **Hetero-dimer**. There is no keyboard shortcut for
   this sheet; reach it from the sidebar **Primer** button, `Tools ▸ Primer Calculator…`, the palette or the
   canvas right-click.

What the numbers are:

- **Tm** is nearest-neighbour thermodynamics with the SantaLucia 1998 unified parameter set, including
  5′/3′ terminal (helix-initiation) corrections for G·C and A·T ends. The result is printed as a range,
  `Tm ≈ min °C ~ max °C`, because the calculation is repeated for **every IUPAC variant** of a degenerate
  primer; degenerate expansion is capped at **4,096 combinations**, and a primer whose degeneracy exceeds
  the cap fails with a calculation error rather than returning a partial range.
- Salt correction follows the von Ahsen 1999 route: the effective monovalent salt is `[Na+]` in mM, plus
  `120·√(free Mg)` when divalent magnesium is present, where `free Mg = [Mg2+] − [dNTP]` in mM. Then
  `ΔS += 0.368·(n−1)·ln([salt] M)`, and `Tm = ΔH·1000 / (ΔS_salt + R·ln(C_T/x)) − 273.15` with `R = 1.987`
  and `x = 1` for a self-complementary (palindromic) oligo, otherwise `x = 4`.
  **There is no dNTP field in the panel**, so from the GUI `[dNTP]` is always zero: if you run a real PCR
  with 2 mM dNTP and 1.5 mM Mg²⁺, the chelation correction is not applied for you. Account for it by
  lowering your entered Mg²⁺ accordingly, or compute it in the library.
- **Wallace fallback.** The Wallace rule `2·(A+T+U) + 4·(G+C)` is available as a method; use it as a quick
  sanity check for short ordinary oligos, not as the reported Tm for degenerate primers (nearest-neighbour
  is what the panel labels and credits).
- **GC content** is `(G+C) / (A+C+G+T+U)`, printed with two decimals, and is computed with the same
  denominator rule as the CLI's `gc_content` so the two never disagree.
- **Dimers** are scored as ΔG in kcal/mol at 37 °C over the best complementary 3′ suffix/offset pairing
  (minimum run of 4 base pairs, strands of at least 4 nucleotides). Anything below **ΔG −5 kcal/mol** is
  flagged "Significant dimer tendency"; otherwise "No significant dimer". Inputs are **truncated to the
  first 200 characters**, so paste an oligo, not a whole amplicon.

### 9.7 GFF3 annotation browser

1. Click **Annot** in the Analysis group, then **Import GFF3…** and pick a `.gff`, `.gff3` or plain-text
   file.
2. Read the table: columns are `Sequence`, `Type`, `Columns`, `Name`, and each row has a **Jump** button.
   The footer shows the file name and the number of features parsed.
3. Click **Jump** to scroll the canvas to that feature and highlight it; the sheet closes.

Coordinates in the GFF3 file are 1-based and inclusive over **sequence residues**; the browser maps them
gap-aware onto alignment **columns**, which is why the header says `Columns` and not "positions". The target
row is resolved by exact sequence name, then by a colon-suffixed name, then by prefix/suffix, so a GFF
`seqid` of `BRCA1` will match an alignment row named `BRCA1`, `BRCA1|transcript_a` or a name starting or
ending with `BRCA1`. Failures you may see: "Could not read annotation file", "Annotation file parsed 0
features (wrong format or empty)", "Sequence not found in alignment: <seqid>", and "The annotated range
lies outside this sequence; cannot jump".

**There are no filters.** No type filter, no name search, no coordinate-range field: you get the whole
parsed feature list in file order, and you scroll it. Plan to import one chromosome/region at a time if the
file is large.

---

## 10. External aligners

SeqAlignMac does not align sequences itself. It calls a local command-line aligner and loads the result.

1. Press ⇧⌘B (`Tools ▸ Run Alignment`), or click **Align** in the sidebar.
2. Pick a **preset** from the Aligner menu; the command template fills in the field, and you can edit it.
3. Click **Run** (or press Return). Results open **in a new window**; your current alignment is untouched.

### 10.1 The four presets

| Preset | Command template |
|---|---|
| mafft (recommended) | `mafft --quiet {input}` |
| muscle | `muscle -align {input} -output {output}` |
| clustalw | `clustalw2 -infile={input} -outfile={output} -quiet` |
| Custom… | empty — type your own command and full path |

### 10.2 The `{output}` rule, and how output is captured

Capture mode is derived from the command you actually typed, **not** from the preset name:

- The command **contains `{output}`** → the tool is expected to write that file, and SeqAlignMac reads the
  file back afterwards (`muscle`, `clustalw`).
- The command **does not contain `{output}`** → stdout is captured and parsed (`mafft`). If you delete
  `{output}` from the muscle template, you get an empty or unparsable result; if you add `{output}` to a
  mafft line, mafft never sees the option and fails.

Placeholders `{input}` and `{output}` are substituted with temporary FASTA paths
(`seqalign_input_<UUID>.fasta`, `seqalign_output_<UUID>.fasta`) in the system temp directory; both are
deleted when the run finishes whatever the outcome. If your custom command uses **no** placeholder at all,
the alignment is fed to the tool's **stdin** instead. The command line is split with quote awareness, so
`--anystop "--foo bar"` style arguments survive intact, and `~` in an executable path is expanded.

The temporary input is always written as unwrapped FASTA, so tools needing a specific format cannot be
driven from this sheet — convert first (section 14.4).

### 10.3 Finding the binary

The executable named first is resolved by: absolute/`~` path if given; otherwise a PATH probe of
`/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`, `/usr/local/sbin`, `/usr/bin`, `/bin`;
otherwise `/usr/bin/which`. If none succeeds you get `Aligner not found: <name>` — install the tool, or put
the full path in the field. Homebrew on Apple Silicon (`/opt/homebrew`) is covered without any PATH setup.

### 10.4 Timeout, cancellation, and large outputs

- The deadline is **configurable**, not fixed. Preferences ▸ aligner timeout offers 30–3600 seconds in steps
  of 30, default **300 s**; the effective deadline is `max(10 s, preference)`, so a stored value of 0 falls
  back to 300 s. The sheet's status text still reads "auto-cancel after 5 min", which is true only for the
  default — if you change the preference, the words do not change.
- On the deadline the child is sent **SIGTERM**, and if it is still alive **5 seconds later** it is sent
  **SIGKILL**. You then see `Alignment timed out (5 min). Try reducing alignment size.`
- Click **Terminate** to cancel deliberately; the run reports `Alignment cancelled.`
- stdout and stderr are drained **concurrently** with the process being awaited. This is what makes big
  alignments safe: a tool writing megabytes of output cannot deadlock the pipe buffer. Keep the option
  anyway — the app's own memory grows with the result size, and for very large jobs a terminal batch run is
  kinder.
- A non-zero exit is reported as `Alignment failed (exit code N): <last ≤200 characters of stderr>`, which
  is usually the fastest way to debug a custom command line.
- The result format is auto-detected from the output content (section 4.1), so a tool emitting CLUSTAL or
  NEXUS on stdout is still read correctly.

### 10.5 The result-consistency check refuses mismatched output

Before loading a result, SeqAlignMac compares it with the input it was given, and **refuses to load** if
they disagree:

| Check | Reported as |
|---|---|
| Sequence count changed | `sequence count changed (a → b)` |
| Names present in the input but missing from the result | `missing sequences` (up to three names listed) |
| Extra names in the result | `unexpected sequences` (up to three names listed) |
| Result rows of differing lengths | `result rows have differing lengths` |

The message reads `Alignment result is inconsistent with the input; refused: <detail>`. This protects you
from a tool that trimmed reads, renamed records, or produced only part of the alignment. Fix the command
(frequently a stdout-versus-file capture mistake, section 10.2) rather than bypassing it; the refusal is not
configurable, but you can always run the tool in a terminal and open its output as an ordinary file, which
is subject only to the normal parse-time checks.

On success the new window is titled `<your file name> (aligned)`, or `alignment_result.fasta` when the
result came from stdout with no file name involved; those suffixes are English-only by construction.

### 10.6 A note on sandboxed builds

There is no runtime switch that hides this feature. Only the signing-time option `SEQALIGN_SANDBOX=1`
attaches the app-sandbox entitlements, and a sandboxed build cannot execute user-supplied binaries — which
is why a Mac App Store style build would lose external alignment. The distribution you build yourself is
unsandboxed by default, so the feature is available.

---

## 11. Export

### 11.1 Image export (PNG, PDF, SVG)

Reach: `File ▸ Export as PNG` / `as PDF` / `as SVG` (no shortcuts), the sidebar `Export ▸ Image`, or
⇧⌘E for the preview sheet first.

1. Open `File ▸ Export Preview` (⇧⌘E).
2. Choose the **Format** segment: PNG, PDF or SVG.
3. Tick **Export selection only** if you want only the selected block (the option is greyed out when there
   is no selection), and **Dark Mode Export** if you want the dark palette.
4. Check **Estimated Size**, then click **Export…** and choose the destination.

What the exported image contains, and what you can and cannot control:

| Property | Value | Controllable from the GUI? |
|---|---|---|
| PNG resolution | **300 DPI always** (rendered at a 300/72 scale) | No — the DPI field in the export options has no UI, yet the size label says "(300 DPI)" |
| Consensus row | **Always included** | No — `showConsensus` is hard-coded on in both the panel and the preview path. Hiding the consensus row on screen does **not** hide it in the image; plan for it in figure captions |
| Name column | 150 pt by default; the width you dragged to in the canvas is used | Indirectly, by dragging the divider (persisted) |
| Font size | 13 pt by default; the CLI can override it | In the GUI, via zoom (section 6.5) before exporting |
| Colour scheme | The scheme currently active | Yes, via View/Preferences |
| Ranges | Whole alignment, or the current selection | Yes, via "Export selection only" |
| Size labels | PNG `W × H px (300 DPI)`; PDF/SVG `W × H pt` | — |

PDF and SVG are vector output (SVG is written as escaped, chunked text with gap rectangles at 16 % opacity).
Mixed codon-plus-amino-acid tracks are refused with an "unsupported" error, because such a track mixes two
alphabets in one row (section 9.5). PNG refuses absurd sizes with a message about the bitmap budget, in
Chinese only.

**Preview limitations.** The thumbnail is always a **PNG** render clamped to a maximum width of 1600 px, and
it does **not** re-render when you switch the format segment from PNG to PDF or SVG: what you see is a
raster impression of the layout, and the aspect/format-specific output can differ from it. If the preview
says "Preview unavailable (alignment too large or render failed)", export directly — the full render uses a
different budget. In multi-window setups the success toast can appear in the wrong window; verify the file
on disk.

### 11.2 Saving and sequence export

| Task | Reach | Output |
|---|---|---|
| Save in place | ⌘S | Same format, same path, re-gzipped if the source was `.gz` |
| Save As | ⇧⌘S | A save panel; uncompressed output regardless of the source |
| Export as another format | Sidebar `Export ▸ Sequence ▸ FASTA / NEXUS / PHYLIP / CLUSTAL / MSF / Stockholm` | A "Saved <file>" toast with the new name |

The asymmetries below surprise people, so they are stated here:

- The sidebar offers **six** sequence formats and **no FASTQ**; the library and the CLI can write FASTQ
  (with real Phred quality). Use `cli convert --format fastq`.
- The Save-As panel restricts the file name to `fasta`, `nexus`, `phy`, `aln`, `msf`; Stockholm and the
  PHYLIP variants are reachable only through the sidebar's explicit format buttons, and in any case the app
  writes the interleaved PHYLIP variant.
- FASTQ is **not** downgraded to FASTA on save or export: quality is written as Phred+33 characters, padded
  positions become `!` (Q0), and values above 93 are clamped (section 4.7).

A successful save or export shows `Saved <file>` or `Exported <file>`; a failure shows `Save failed:` or
`Export failed:` with the underlying error appended. Quitting with unsaved work routes back through the save
dialog (section 5.2).

---

## 12. Preferences

Open with ⌘, (`Preferences…`, also the sidebar **Settings** button). It is a sheet, not a separate window:
click **Done** to close (there is no Escape binding here).

| Setting | Range / choices | Default | Effect |
|---|---|---|---|
| Appearance | Light / Dark / Follow System | Follow system | Per-app appearance; data palettes have dark variants where meaningful |
| Color scheme | All 7 schemes | **Minimal** | Canvas and export palette |
| Font size | Stepper, 8–28 pt | 13 pt | Glyph size, zoom percentage, and the export layout size |
| Show consensus sequence | On / Off | On | The consensus row on screen only — exports always include it |
| High contrast mode | On / Off | Off | Extra gap diagonals and stronger contrast for accessibility |
| Focus dim | On / Off | Off | Non-selected regions are dimmed while a selection is active |
| ClustalX Conservation Threshold | 0.1–0.9, step 0.05 | 0.3 | Columns below the threshold are left uncoloured in the ClustalX scheme |
| Consensus Mode | Majority Rule / IUPAC Degenerate / Strict | Majority Rule | The consensus glyph only; never changes identity numbers |
| Aligner timeout | Stepper, 30–3600 s, step 30 | 300 s | Deadline for external aligner runs (section 10.4) |

Primer salt conditions (`Na+` 50 mM, `Mg2+` 0 mM, `Oligo` 0.25 µM) are not in this sheet but persist from the
primer panel.

**What is and what is not remembered.** Persisted: language, appearance, colour scheme, font size, name
column width, high contrast, focus dim, consensus mode, aligner timeout, panel widths (sidebar, statistics),
the last ten file paths, the primer salt fields, and the one-time first-run flag.
**Not persisted**: the ClustalX threshold (it returns to 0.3 on every launch), consensus visibility,
difference mode and its reference row, the open tabs and their contents, and the search query. Quitting
loses your window layout; reopen files from `File ▸ Open Recent`.

**Switching language at runtime.** Choose `View ▸ Language ▸ English / 中文`, or use the **Language** button at
the bottom of the sidebar. The choice is stored on the device and, on first launch, is inferred from your
system's preferred language (Chinese is chosen if the system language starts with `zh`). Menus, window
titles, panels and the palette all re-render immediately; no restart is needed. Some strings are not in the
table and stay Chinese-only (canvas tooltips and toasts, image-export errors, the CLI, the genetic-code
picker, the `Charset` label).

---

## 13. Keyboard shortcuts

This table is the complete set of bindings the application registers. Shortcuts listed nowhere here do not
exist: there is **no** shortcut for Move Sequence, Primer, Alignment Quality, the Default colour scheme, the
Ti/Tv scheme, or any of `File ▸ Export as PNG/PDF/SVG`.

### 13.1 Global, file, and clipboard

| Keys | Action | Menu path |
|---|---|---|
| ⌘T | New tab in the current window | File ▸ New Tab |
| ⌘N | New window | File ▸ New Window |
| ⌘O | Open file | File ▸ Open File… |
| ⌘W | Close the **tab** | File ▸ Close Tab |
| ⇧⌘W | Close the **window** | File ▸ Close Window |
| ⌘S | Save in place | File ▸ Save |
| ⇧⌘S | Save As… | File ▸ Save As… |
| ⇧⌘E | Export preview sheet | File ▸ Export Preview |
| — | Export as PNG / PDF / SVG | File ▸ Export as PNG/PDF/SVG |
| ⌘A | Select all | Edit ▸ Select All |
| ⌘C | Copy selection as FASTA | Edit ▸ Copy |
| ⌘V | Paste sequences | Edit ▸ Paste |
| ⌘X | Cut (with a canvas selection: copy the block **and** insert gaps in it) | Edit ▸ Cut |
| ⌘, | Preferences sheet | Preferences… |
| ⇧⌘P | Command palette | Tools ▸ Command Palette |

### 13.2 Editing

| Keys | Action | Menu path |
|---|---|---|
| ⌘Z | Undo (greyed when the stack is empty) | Edit ▸ Undo |
| ⇧⌘Z | Redo | Edit ▸ Redo |
| ⇧⌘R | Rename the sequence under the cursor | Edit ▸ Rename Sequence |
| ⇧⌘X | Delete the sequence under the cursor | Edit ▸ Delete Selected Sequence |
| ⌘D | Insert one gap column at the cursor | Edit ▸ Insert Gap |
| ⌘I | Reverse complement (nucleotide data only) | Edit ▸ Reverse Complement |
| — | Move Sequence… | Edit ▸ Move Sequence… |

### 13.3 View, colour schemes, and zoom

| Keys | Action | Menu path |
|---|---|---|
| ⇧⌘1 | Minimal scheme | View |
| ⇧⌘2 | ClustalX scheme | View |
| ⇧⌘3 | Zappo scheme | View |
| ⇧⌘4 | SeaView scheme | View |
| ⇧⌘5 | Okabe-Ito (CVD-safe) scheme | View |
| — | Default scheme, Ti/Tv scheme | View |
| ⌘= **or** ⌘+ | Zoom in (both are registered; on a US layout use ⌘=) | View |
| ⌘- | Zoom out | View |
| ⇧⌘0 | Reset zoom to 13 pt (100 %) | View |
| ⇧⌘G | Show/Hide consensus — **conflicts with Find Previous**, see 8.5 | View ▸ Show/Hide Consensus |
| — | Appearance (Light / Dark / Follow System) | View ▸ Appearance |
| — | Language (中文 / English) | View ▸ Language |

### 13.4 Search and tools

| Keys | Action | Menu path |
|---|---|---|
| ⌘F | Show the search bar | Tools ▸ Search |
| ⌘G | Find next | Tools ▸ Find Next |
| ⇧⌘G | Find previous (registered, but the consensus toggle claims the key combination in practice) | Tools ▸ Find Previous |
| ⇧⌘B | External aligner sheet | Tools ▸ Run Alignment |
| ⇧⌘T | Translation options sheet | Tools ▸ Translate to Amino Acid |
| — | Primer Calculator… | Tools ▸ Primer Calculator… |
| — | Alignment Quality | Tools ▸ Alignment Quality |

### 13.5 Help

| Keys | Action | Menu path |
|---|---|---|
| — | Quick Guide | Help ▸ Quick Guide |
| — | Load Example Data | Help ▸ Load Example Data |
| — | About SeqAlign | Help ▸ About SeqAlign |

### 13.6 Canvas keys and gestures

| Input | Action |
|---|---|
| ← ↑ → ↓ | Move the cursor (the view scrolls to keep it visible) |
| ⌥ + arrows | Extend the rectangular selection from its anchor |
| Esc | Clear the selection |
| Drag in the grid | Rectangular selection |
| ⌥-drag | Whole-column block selection |
| Double-click a name | Rename sheet |
| Drag a name up/down | Reorder the sequence |
| Drag the name divider | Resize the name column |
| Drag on the conservation rail | Scrub/jump to a column |
| ⌘-scroll wheel | Zoom |
| Pinch (`magnify`) | Zoom |

### 13.7 Sheet keys

| Input | Sheets |
|---|---|
| Esc | Logo, NJ Tree, Window chart, Annotation, Quality report, Primer, Export preview, Command palette, Guide; on the unsaved-changes sheet, Escape triggers its **Cancel** button |
| Return | Guide start, Rename confirm, Move confirm, External aligner Run/Terminate, Translate, Export preview Export |
| ↑ / ↓ | Command palette navigation |
| No Escape binding | **Preferences…** (click **Done**) and the **Translation options** sheet — dismiss those with the mouse |

---

## 14. Command-line usage

The same executable that runs the GUI also runs headless. It is the binary inside the bundle:

```bash
SeqAlignMac.app/Contents/MacOS/SeqAlignMac cli <subcommand> <file> [options]
```

`cli` must be the **first** argument; without it the GUI launches. For brevity the examples below use
`$SA` for that path:

```bash
SA=SeqAlignMac.app/Contents/MacOS/SeqAlignMac
```

Three subcommands exist: `stats`, `export`, `convert`. You need at least a subcommand and an input path, or
you get the usage block and exit 64. There is no `--help`, `--version`, `-v` or `--verbose`; running
`cli --help` prints the usage block and exits 64. Options are matched as `--key value` or `-o value`
positional pairs; a value that begins with `-` is treated as "option absent" and the default applies; if an
option is repeated, the **first** occurrence wins.

The input file is read and parsed **before** the subcommand is dispatched, so a bad file reports a parse
error even if the subcommand is misspelt, and a misspelt subcommand still pays the full parse cost. `.gz`
inputs are decompressed by extension (section 4.3).

### 14.1 `cli stats` — column statistics as CSV

```
SeqAlignMac cli stats <alignment-file> [--out results.csv]
```

| Option | Default | Behaviour |
|---|---|---|
| `--out <path>` | absent | With it, the CSV goes to the file and stdout prints only `已写入 <path>` (`Wrote <path>`). Without it, the CSV goes to stdout |
| `-o` | — | **Not recognised by `stats`** — use `--out` here |
| `--start` / `--end` | — | **Ignored by `stats`**: there is no region slicing for statistics |

CSV fields, in order (`metric,value`; values are quoted only when they contain a comma, quote or newline):

| Field | Meaning |
|---|---|
| `file` | Last path component only |
| `sequences`, `columns` | Row and column counts (columns after padding, i.e. alignment width) |
| `datatype` | `nucleotide` or `aminoacid` |
| `pooled_identity_site_weighted` | Site-weighted pooled identity, 0–1 with four decimals — see 9.1; this is not a per-pair mean |
| `declared_aligned` | Provenance: `aligned`, `unknown` or `not-aligned` |
| `mean_column_identity` | Arithmetic mean of the per-column identity values, 0–1 |
| `min_column_identity`, `max_column_identity` | Worst/best columns, over informative columns (0 when none exist) |
| `gap_columns` | Columns with no assignable residue (all-gap **or** all-undetermined) |
| `total_columns` | Column count |
| `variable_sites`, `parsimony_informative_sites`, `singleton_sites` | Site counts as defined in 9.1 |
| `gc_content` | GC fraction, 0–1; `0` for protein |
| `fastq_mean_phred`, `fastq_q20_ratio`, `fastq_q30_ratio` | Present **only** when the source carries quality data |

```bash
$SA cli stats aln.fasta --out stats.csv
$SA cli stats aln.fasta.gz | cut -d, -f1-2
```

### 14.2 `cli export` — image export

```
SeqAlignMac cli export <alignment-file> --format png|pdf|svg [-o output]
                       [--fontsize N] [--dark]
                       [--scheme minimal|clustalx|zappo|seaview|default|titv|okabeito]
```

| Option | Default | Bad value behaviour |
|---|---|---|
| `--format` | `png` | Anything other than `png`/`pdf`/`svg` → stderr `Error: unknown --format '<x>' (expected png\|pdf\|svg)` and **exit 64** |
| `--scheme` | `minimal` | **Silently falls back to `minimal`** for an unrecognised name — a typo costs you the palette with no error. The library's own `ExportOptions` default is the Default nucleotide scheme; the CLI's default is Minimal |
| `--fontsize N` | 13 | Accepted only as a number in 6–40; otherwise a `Warning: invalid --fontsize, using default 13` line on stderr and 13 is used (non-fatal) |
| `--dark` | off | Presence-only flag |
| `-o` / `--output` | `<input-basename>_alignment.<format>` | — |
| `--start` / `--end` | — | Not supported by `export`; there is no selection export from the CLI |

The name column width is read from the persisted preference `SeqAlignMac.nameColWidth` (else 150 pt), so a
headless run inherits your GUI layout — a caveat for reproducibility; set the preference deliberately, or use
a fresh user defaults domain. PNG output is always rasterised at 300 DPI, and the consensus row is always
drawn, exactly as in the GUI (section 11.1). On success stdout prints `已导出 <path>` (`Exported <path>`).

```bash
$SA cli export aln.fasta --format svg -o figure.svg --scheme okabeito --dark
$SA cli export aln.phy --format png --fontsize 10 > /dev/null   # writes aln_alignment.png
```

### 14.3 `cli convert` — format conversion and region extraction

```
SeqAlignMac cli convert <alignment-file>
                       --format nexus|phylip|clustal|msf|stockholm|fasta|fastq
                       [-o output-file] [--start N] [--end M]
```

| Option | Default | Bad value behaviour |
|---|---|---|
| `--format` | **required** | Missing → `Error: --format is required for convert`, **exit 64**. Unknown → `Error: unknown --format '<x>' (expected nexus\|phylip\|clustal\|msf\|stockholm\|fasta\|fastq)`, **exit 64** |
| `--start N` | `1` | Non-numeric values are **silently ignored** (the default is used). Out-of-range values are **silently clamped** into the alignment |
| `--end M` | number of columns | As above |
| `-o` / `--output` | `<input-basename>.<canonical extension>` | `--out` is **not** recognised here — writing `convert … --out x.nexus` silently produces a default-named file in the current directory |
| `--scheme`, `--fontsize`, `--dark` | — | Ignored by `convert` |

Accepted format aliases, case-insensitive, with the extension the default output name uses:
`nexus|nex` (`.nexus`), `phylip|phy` (`.phy`), `clustal|aln` (`.aln`), `msf` (`.msf`),
`stockholm|sto` (`.sto`), `fasta|fa|fas` (`.fasta`), `fastq|fq` (`.fastq`).

Region semantics: `--start`/`--end` describe a **1-based closed interval of alignment columns** —
`--start 201 --end 400` keeps columns 201 through 400 inclusive (200 columns). Bounds outside the alignment
are clamped without warning; `start > end` (or a start past the end) is an error:
`错误: 无效参数: Invalid region: <start>-<end>` with **exit 70**. Sequences shorter than the requested window
are right-padded with `-` to a uniform width. NEXUS `CHARSET` partitions are **re-projected onto the cropped
coordinates** so ranges stay correct for MrBayes/RAxML/IQ-TREE, provenance is carried over, and metadata and
data type pass through. Slicing is skipped entirely when the requested window is the whole alignment.

`--format fastq` requires that at least one sequence carries quality values; otherwise the run fails with
`不支持的操作: convert fastq 需要带质量值的 FASTQ 来源…` and exit 70 (use `--format fasta` for non-FASTQ
data). If the named output ends in `.gz`, the converted text is gzip-compressed on write. A codon+amino-acid
mixed track is refused with **exit 65**; that guard is defensive and is not reachable through the CLI in
practice, because mixed tracks only exist as in-process translation results that the CLI never produces.

On success stdout prints `Converted to <format you typed> → <output path>`.

```bash
$SA cli convert aln.fasta --format nexus -o aln.nexus
$SA cli convert big.fasta --format fasta --start 1 --end 5000 -o region.fasta
$SA cli convert reads.fastq --format fastq -o fixed.fastq     # quality preserved, padded Q0
```

### 14.4 Exit codes

| Code | Name | When |
|---|---|---|
| 0 | success | The command did its work |
| 64 | usage error | Too few arguments; unknown subcommand; `export --format` not one of png/pdf/svg; `convert` without `--format`; `convert --format` unknown. The usage block is printed, **to stdout** |
| 65 | data error | A codon + amino-acid mixed track was refused (defensive; see 14.3) |
| 66 | input unavailable | The file could not be read, or a `.gz` file could not be decompressed: `无法读取文件: <path>` |
| 70 | internal/software error | Any thrown error: parse failure, invalid region, FASTQ without quality, output write failure. Reported as `错误: <description>` on stderr |

Error and progress text from the CLI is **not localised**: file and parse messages plus the
`已写入` / `已导出` progress lines are Chinese, format/scheme/`--fontsize` messages and the `Converted to …`
line are English. Grep for a leading `Error:`/`错误:` if you are scripting around it, and treat a non-zero
exit as the authoritative signal.

### 14.5 A batch pipeline

Convert every PHYLIP file to NEXUS, skip failures loudly, and keep a manifest:

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

### 14.6 A reproducible-analysis recipe

```bash
SA=SeqAlignMac.app/Contents/MacOS/SeqAlignMac
set -euo pipefail
"$SA" cli stats aln.fasta.gz --out stats.csv
"$SA" cli convert aln.fasta.gz --format fasta -o aln.unaligned_check.fasta
"$SA" cli export aln.fasta.gz --format pdf -o fig.pdf --scheme okabeito
sha256sum stats.csv fig.pdf aln.unaligned_check.fasta > checksums.txt
```

Record three things alongside the outputs, because they are what makes the numbers repeatable: the
`declared_aligned` column of `stats.csv` (whether the input was truly aligned), the fact that PNG/PDF export
inherits your saved name-column width from preferences, and that `--scheme` typos fall back to `minimal`
without an error. Pin the executable you used (`SeqAlignMac.app/Contents/MacOS/SeqAlignMac` from a build of
v0.1.0) in your lab notebook.

---

## 15. Recipes

End-to-end tasks that combine several features. Commands use the `$SA` shorthand from section 14.

### 15.1 Extract one NEXUS region for primer design

Goal: amplify a 300 bp window of a large alignment and design primers against it.

1. Find the window: click **Window** in the sidebar's Analysis group and read the identity chart; note the
   column numbers of the conserved flanks.
2. Crop and convert in one step:
   `"$SA" cli convert whole.fasta --format nexus --start 4001 --end 4300 -o amplicon.nexus`
   NEXUS `CHARSET` ranges are renumbered automatically, so downstream phylogenetics stays consistent.
3. Open `amplicon.nexus` in SeqAlignMac (⌘O).
4. Select the row range you want to prime against, open the primer sheet (sidebar **Primer**), and click
   **Fill from selection**.
5. Press **Calc Tm**, **Calc GC%**, **Self-dimer**, then **Hetero-dimer** with the reverse primer in
   `Sequence B`. Treat ΔG below −5 kcal/mol as a red flag, and remember dNTP chelation is not modelled from
   the panel (section 9.6).
6. Sanity-check the pair with the Wallace number too; if the two disagree by more than a few degrees for a
   short ordinary oligo, suspect a degenerate sequence.

### 15.2 FASTQ QC triage with Q20 and Q30

Goal: decide whether a run of reads is usable before spending compute on it.

1. Open `reads.fastq`. The statistics panel shows a `Read Quality` card with Mean Phred, Min Phred, ≥Q20
   bases and ≥Q30 bases.
2. Read the ratios as **per-base** fractions: Q20 = 1 % expected error, Q30 = 0.1 %. A dataset at, say,
   92 % ≥Q20 but 68 % ≥Q30 is fine for consensus calling and marginal for variant calling in homopolymers.
   Min Phred near 2 usually means trailing-end quality decay, not a broken file.
3. Switch to ⇧⌘5 (Okabe-Ito) and zoom out a little to see where the low-quality tails sit along the read;
   the conservation rail gives you the column-wise picture.
4. For a numeric record per file: `"$SA" cli stats reads.fastq.gz --out qc.csv` and keep
   `fastq_mean_phred`, `fastq_q20_ratio`, `fastq_q30_ratio` in your QC table.
5. If you need to hand the reads to another tool with the alignment gaps resolved:
   `"$SA" cli convert reads.fastq.gz --format fastq -o normalized.fastq` — padded columns become Q0 (`!`).

### 15.3 Build a neighbour-joining tree and publish it

1. Confirm the input really is aligned: the statistics panel must **not** show the orange unaligned banner,
   or `declared_aligned` must be `aligned` in the CLI output. If it is not aligned, run an aligner first
   (section 10).
2. Keep divergence low — p-distance is uncorrected, so this tree is for close relatives only.
3. Click **NJ Tree**. If you have more than 200 sequences, note the sampling line: 200 sequences are taken by
   equal-interval stride.
4. Click **Copy Newick**, paste into your tree viewer, and **keep the root NHX comment**
   (`[&sampled=200_of_1240;model=p-distance;clamped=3]`) — it documents exactly what was computed. Report the
   clamped-branch count honestly; a high count means the distance model is saturated for your data.
5. For a reproducible run: crop to the taxon subset with `cli convert --start/--end`, regenerate the tree,
   and store both the Newick and the `stats.csv` next to it.

### 15.4 A colour-blind-safe figure for a paper

1. `View ▸ Okabe-Ito (CVD-safe)` (⇧⌘5). This scheme is designed for red-green deficiency (Wong 2011).
2. Turn on `Preferences… ▸ High contrast mode` if the figure is printed in greyscale, and set the font size
   so letters are still drawn — at the smallest sizes only colour blocks remain (section 6.5).
3. Select the region you want in the figure. Remember: the consensus row is **always** exported whether or
   not you can see it on screen, so leave consensus displayed and treat it as part of the figure legend.
4. ⇧⌘E → **Format: PDF** for a vector figure, tick **Export selection only**, and check the estimated size.
   Use **PNG** when a raster is required — it is written at 300 DPI, and no DPI control exists.
5. If the preview thumbnail looks different from what you expect, that is the known preview limitation (it is
   always a PNG render at ≤1600 px wide); export anyway and inspect the real file.
6. In the caption state the scheme and the consensus inclusion, e.g. "Okabe-Ito palette; consensus row
   shown; 300 DPI".

### 15.5 Batch-convert two hundred files

```bash
SA=SeqAlignMac.app/Contents/MacOS/SeqAlignMac
mkdir -p nexus
ls clustal/*.aln | sed 's/\.aln$//' | while read -r base; do
  "$SA" cli convert "${base}.aln" --format nexus -o "nexus/${base}.nexus" \
    || echo "FAILED ${base}.aln" >> failures.log
done
wc -l nexus/*.nexus | tail -1
```

Then check `failures.log`. The usual causes are exit 66 (a `.gz` name without gzip inside, or a truly
unreadable file) and exit 70 from a parse error, both of which carry the reason on stderr.

### 15.6 Curate an unaligned FASTA without losing the original

1. Open the file; accept the unaligned banner — it tells you column homology does not hold.
2. ⇧⌘B → preset **mafft (recommended)**, Run. The result opens in a **new window** named
   `<file> (aligned)`; the original tab is untouched.
3. If the run is refused with "inconsistent with the input", check that you have not deleted `{output}` from
   the template (mafft writes to stdout and must not have an `{output}` placeholder), then retry.
4. Verify: the new window's banner should be gone, `Gap columns` should drop, and `Pooled identity
   (site-weighted)` should rise. Compare before/after with `cli stats` on both files.
5. ⌘S to save in place (still gzipped if it came in gzip), or ⇧⌘S / the sidebar export to write another
   format.

---

## 16. Troubleshooting and FAQ

**The file will not open.**
Check the format and the compression story in that order. The Open panel only lists
`fasta, fa, fas, fastq, fq, nexus, nex, phy, phylip, aln, msf, sto, stockholm, gz`, so a `.fna`, `.faa`,
`.mpfa` or `.clustal` file is invisible there even though the app can read the content — drop it onto the
window instead. A gzip stream must actually be gzip *and* be named `.gz`; a file that is really
`cat a.gz b.gz` is deliberately rejected so no data is silently dropped. If a specific record is refused,
read the error: "illegal character at line N", "fewer data lines than declared", "quality line length
mismatch" and "sequence has no residues" are all precise, and they mean the file — not the app — needs
fixing.

**Letters show as coloured blocks; I cannot read the residues.**
You are below the density threshold: under about 6 px per column, glyph drawing is switched off on purpose.
Press ⌘= a few times, or ⇧⌘0 to return to 13 pt. Row height is unchanged, so the switch is only about width.

**The consensus row does not match my statistics after I switch Consensus Mode.**
Expected. Only the consensus *glyph* changes; identity percentages, the conservation rail, colouring, the
pooled identity and the NJ tree always use the majority rule. Also remember the statistics panel's
"Consensus length" is a **column count**.

**`Aligner not found: mafft`.**
The tool is not in any probed directory (`/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`,
`/usr/local/sbin`, `/usr/bin`, `/bin`, then `which`). Install it, or type the full path
(`/opt/homebrew/bin/mafft --quiet {input}`) in the command field. `Alignment timed out` means you hit the
preference-driven deadline (default 300 s, adjustable 30–3600 s): raise it or crop the input.

**"Alignment result is inconsistent with the input; refused".**
The result did not match the input by sequence count, names or raggedness (section 10.5). Most often the
command line and the capture mode disagree: if `{output}` is present the app reads a file, if absent it
reads stdout. Fix the template; if you must use the output anyway, run the tool yourself in a terminal and
open its file normally.

**Undo does not merge my keystrokes.**
By design. There is no keystroke coalescing — only explicit transactions group — and the stack holds at most
50 steps and 256 MiB, dropping the oldest first. If you need to revert a large change in one step, do it as
one command (for example gap trimming) rather than a series of small edits.

**Gatekeeper blocks the app.**
See section 2.3: ad-hoc signing is the default build path. Use right-click ▸ Open, or
System Settings ▸ Privacy & Security ▸ Open Anyway, or remove the quarantine attribute.
`spctl -a -vv` rejecting an ad-hoc build is expected, not evidence of tampering.

**An export failed with a message about bitmap size or dimensions.**
The PNG path refuses absurd output sizes; the message is currently Chinese-only
("导出位图过大…", "无法创建 W×H 位图上下文…"). Reduce the range (export the selection only), reduce the
name column width, or export PDF/SVG instead. A mixed codon + amino-acid track cannot be exported at all:
re-translate choosing Codon only or Amino acid.

**The ⇧⌘G key does not go to the previous match.**
Known conflict; it toggles the consensus row. Use the **Prev** button in the search bar or
`Tools ▸ Find Previous`.

**Some labels are Chinese even in English.**
Certain canvas toasts, the column-peek tooltip, the `Charset` status-bar label, the genetic-code picker,
image-export error strings, and all CLI output are not in the localisation table yet. They behave identically;
only the wording differs. The English/Chinese toggle (section 12) does not change them.

**Two windows show the same About/version.**
`Help ▸ About SeqAlign` shows the version, and that string is hard-coded in the app rather than read from
the bundle, so it always says **Version 0.2.0** even for a locally rebuilt binary. The authoritative version
for packaging is `Info.plist`'s `CFBundleShortVersionString`, which you can check with:

```bash
defaults read "$PWD/SeqAlignMac.app/Contents/Info" CFBundleShortVersionString
```

**Where do I find the log?**
There is no log file. Errors are shown in place — error banners, toasts, the aligner sheet's message area —
and the CLI writes diagnostics to stdout/stderr, so redirect them to a file (see 14.5). Preferences live in
`UserDefaults` under the `SeqAlignMac.` prefix:

```bash
defaults read com.seqalign.mac      # list every persisted preference
defaults delete com.seqalign.mac    # reset them all
```

Uninstalling removes all locally stored state, and nothing is uploaded anywhere (see `PRIVACY.md`).

**Performance questions.**
Rendering is virtualised and statistics run in the background, and that is as far as documented claims go:
no sequence-count ceiling or speed figure has been measured, so do not plan around a promised capacity. For
very large or unattended work, use the CLI.

---

## 17. Getting help and limitations

**Where to look for a specific answer**

| Question | Document |
|---|---|
| How do I… (a task) | This guide, `docs/USAGE.md` (and [中文版](USAGE_ZH.md)) |
| How is it built, why is a number what it is, what are the formats' exact rules, what is the CLI contract | [`docs/DOCUMENTATION.md`](DOCUMENTATION.md) |
| Which limitations are known and tracked | [`DOCUMENTATION.md`](DOCUMENTATION.md), the "Known limitations and engineering discrepancies" section |
| Document/feature overview and quick links | [the documentation index](README.md), and the repository `README.md` |
| Contributing, code style, the core-file allow-list, test policy | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |
| Reporting a security issue, attack surface, signing and integrity | [`SECURITY.md`](../SECURITY.md) |
| What data is collected (nothing) and where preferences are stored | [`PRIVACY.md`](../PRIVACY.md) |
| How to cite the software | [`CITATION.cff`](../CITATION.cff) |
| In-app | `Help ▸ Quick Guide` (an eight-step walkthrough), `Help ▸ About SeqAlign` |

**Limitations to keep in mind while using the app**

- No internal aligner: alignment itself always comes from an external tool (section 10).
- No tree rendering canvas: the NJ result is Newick text for you to draw elsewhere (section 9.3).
- No in-canvas residue typing; editing is whole-row/whole-column plus paste (section 7.3).
- No per-sequence or per-position table export beyond the CSV that `cli stats` produces.
- Export control is coarse: 300 DPI fixed for PNG, consensus always on, no region flags in the CLI export
  path (section 11.1).
- The annotation browser has no filters (section 9.7).
- Write-only library features with no user interface: FASTA line wrapping (`wrapWidth`), the PHYLIP
  sequential/strict-10/padded-name variants, the CLUSTAL consensus line, NEXUS metadata inclusion (which in
  fact only gates the `SETS` block), and `.fai` index handling. Reach them only through the library.
- The command-line interface has **no automated tests at all**: argument parsing, the exit codes, the CSV
  field set and `--start/--end` slicing are verified by reading the source, not by a test suite, and CI never
  exercises `cli` mode. Treat edge-case CLI behaviour as "as documented here, as read from the code", and
  check exit codes in scripts.
- 110 core unit tests cover the parsers, writers, statistics, search, translation and undo layers; the
  AppKit/SwiftUI rendering, export and file-save paths are not covered by that suite.
- macOS only, `arm64` only, and no Linux or Intel validation exists.

If something behaves differently from this guide, open an issue against the repository with the file (or a
minimal excerpt), the exact menu path you used, and the message you saw; the `declared_aligned` value from
`cli stats` and the output of `codesign --verify` are the two most useful things to include.
