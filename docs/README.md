# SeqAlignMac — Documentation Index

**Version:** 0.1.0 · **Repository:** [../README.md](../README.md)

> **Language policy.** English is the primary language of this documentation set. The English files
> are the authoritative text; the Chinese files are section-by-section mirrors of them. Where a
> statement in the two languages differs, or where a document and the code differ, **the English
> document (and the code it cites) wins**. The Chinese mirrors under `docs/`
> (`DOCUMENTATION_ZH.md`, `USAGE_ZH.md`) and the root-level `MANUAL_ZH.md` each restate this at their
> top; `README_ZH.md` does not carry the statement. The root-level governance files
> (`PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`) sit outside this
> English-primary scheme altogether: each is a single Chinese-primary file with bilingual headings and
> no English counterpart — see
> [Relationship to the root-level documents](#relationship-to-the-root-level-documents).

This index covers the documentation maintained under `docs/`. The repository root additionally
carries the release README and the original user manuals; they are listed in
[Relationship to the root-level documents](#relationship-to-the-root-level-documents) so nothing
appears to be missing.

---

## Table of contents

1. [The two documents](#the-two-documents)
2. [Which document to read](#which-document-to-read)
3. [Document map](#document-map)
4. [How the documents are structured](#how-the-documents-are-structured)
5. [Relationship to the root-level documents](#relationship-to-the-root-level-documents)
6. [Conventions used in these documents](#conventions-used-in-these-documents)
7. [Accuracy and currency](#accuracy-and-currency)

---

## The two documents

| # | English (primary) | 中文（镜像版本） | What it answers |
| --- | --- | --- | --- |
| 1 | [`DOCUMENTATION.md`](DOCUMENTATION.md) — Project Documentation (说明文档) | [`DOCUMENTATION_ZH.md`](DOCUMENTATION_ZH.md) — 项目说明文档 | *How is it built, and how does it work?* Architecture, modules, data model, format specification, algorithms and their exact definitions, rendering, localisation, persistence, build and test gates, extension guide, known limitations. |
| 2 | [`USAGE.md`](USAGE.md) — Usage Guide (使用文档) | [`USAGE_ZH.md`](USAGE_ZH.md) — 使用指南 | *How do I get something done?* Installation and first launch, opening files, reading the interface, colour schemes, editing, search, every analysis workflow and how to interpret its numbers, external aligners, export, preferences, the complete shortcut tables, the command-line reference, worked recipes, troubleshooting. |

The two are deliberately complementary: the usage guide links to the documentation for normative
definitions instead of restating them, and the documentation links to the usage guide instead of
describing workflows.

---

## Which document to read

Read [`USAGE.md`](USAGE.md) if you are **using** SeqAlignMac — you have alignment files, and you
want to view, edit, analyse, export, or batch-convert them. Start at
[Before you start](USAGE.md#2-before-you-start), then
[Quick start](USAGE.md#3-quick-start-five-minutes).

Read [`DOCUMENTATION.md`](DOCUMENTATION.md) if you are **reading or changing** SeqAlignMac — you
want to know why a number on screen is what it is, which code path produces it, how to add a format
or a colour scheme, or what the build and test gates actually enforce. Start at
[Architecture](DOCUMENTATION.md#4-architecture), then
[Algorithms and methods](DOCUMENTATION.md#8-algorithms-and-methods).

If you read Chinese, use [`USAGE_ZH.md`](USAGE_ZH.md) and
[`DOCUMENTATION_ZH.md`](DOCUMENTATION_ZH.md). They mirror the English section numbering exactly, so
`§8.12` exists in both, and the same citation points to the same line of code.

---

## Document map

`USAGE.md` — 17 sections:
How to use this guide · Before you start · Quick start · Opening files · Interface tour · Reading the
alignment · Editing the alignment · Searching · Analysis workflows · External aligners · Export ·
Preferences · Keyboard shortcuts · Command-line usage · Recipes · Troubleshooting and FAQ · Getting
help and limitations.

`DOCUMENTATION.md` — 16 sections:
Purpose, audience, and document map · Project overview · Repository layout · Architecture · Data
model reference · Module reference · Format I/O specification · Algorithms and methods · Rendering
and performance · Localisation architecture · Persistence · Build system and quality gates ·
Command-line interface as a documented contract · Extension guide · Known limitations and
engineering discrepancies · Governance, release metadata, and references.

Both documents carry a numbered table of contents with in-page anchors, and both cite code as
`Sources/File.swift:LINE` (relative to the repository root) so any claim can be checked in one click.

---

## How the documents are structured

- **Numbered sections, stable across languages.** Section `n` in one language is section `n` in the
  other, which makes translation drift easy to spot.
- **Citations over assertions.** Behavioural claims point at the code that implements them; the
  documents describe the code as committed at tag `v0.1.0`.
- **Tables for option lists, defaults, and mappings.** Shortcut tables, preference keys, format
  capabilities, genetic-code tables, exit codes and CLI flags are all tabulated rather than
  paraphrased.
- **An explicit limitations ledger.** `DOCUMENTATION.md` §15 records known deviations between the
  code, the interface, and older prose in the repository — dead bindings, write-only features,
  unlocalised surfaces, silent CLI fallbacks — so the documents do not propagate them.
- **No duplicated normative text.** Metric definitions live in `DOCUMENTATION.md` §8 only; the usage
  guide links to them.

---

## Relationship to the root-level documents

The files in the repository root are release and governance documents, and are **not** rewritten
here. This index links to them rather than restating them. Note that the four governance files below
are authored **in Chinese**, with bilingual headings only; each is a single file with no English
counterpart and no Chinese mirror, so the mirroring scheme described in the language policy does not
apply to them:

| File | Role |
| --- | --- |
| [`README.md`](../README.md) | English project front page: feature list, quick start, methodological summary table, citation, licence. |
| [`README_ZH.md`](../README_ZH.md) | Chinese project front page. |
| [`MANUAL_EN.md`](../MANUAL_EN.md) / [`MANUAL_ZH.md`](../MANUAL_ZH.md) | The original release manuals, written for v0.1.0 and kept as standalone documents in the repository root. `docs/USAGE.md` supersedes them for day-to-day reference. They are **not** shipped inside the `.app`: `build.sh` copies only `Info.plist`, `AppIcon.icns`, `logo.svg` and `PrivacyInfo.xcprivacy` into `Contents/Resources`, and nothing under `Sources/` refers to them — Help ▸ Quick Guide opens a hard-coded in-app view (`Sources/ContentView.swift:226`, `GuideView`), not these files. |
| [`CONTRIBUTING.md`](../CONTRIBUTING.md) | How to contribute, branch and commit expectations, test policy. **Chinese-language file** (bilingual headings only); no separate English version. |
| [`SECURITY.md`](../SECURITY.md) | Vulnerability reporting policy. **Chinese-language file** (bilingual headings only); no separate English version. |
| [`PRIVACY.md`](../PRIVACY.md) | Privacy statement, mirrored by [`Resources/PrivacyInfo.xcprivacy`](../Resources/PrivacyInfo.xcprivacy). **Chinese-language file** with a one-paragraph English summary; no separate English version. |
| [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md) | Community conduct (Contributor Covenant 2.0). **Chinese-language file**; no separate English version. |
| [`LICENSE`](../LICENSE) · [`CITATION.cff`](../CITATION.cff) · [`.zenodo.json`](../.zenodo.json) | MIT licence, citation metadata, archival metadata. |

---

## Conventions used in these documents

- `File ▸ Menu Item` names a macOS menu path: top-level menu first, then submenu, then item, joined
  by `▸`. English documents quote every label exactly as the English interface shows it. Chinese
  documents must render **every** label in the path as `本地化标签（English Label）` — localised label
  first, the English label in full-width parentheses — e.g. `视图（View）▸ 语言（Language）`. The `▸`
  separator itself is never translated or replaced. Because the interface language is switchable at
  runtime (`View ▸ Language`), a reader may be looking at either rendering; a path that localises the
  menu but leaves the item in bare English, or vice versa, is a defect in the Chinese documents.
- The app's own catalogue (`Sources/Localization.swift`) supplies the Chinese titles for the
  `视图（View）` and `工具（Tools）` menus and for every menu item, so those follow the in-app language
  toggle. The `File`, `Edit`, `Window`, and `Help` titles come from SwiftUI's standard command groups
  and follow the system language instead, which is why the Chinese documents gloss those titles too
  rather than assuming they switch with the app.
- Symbols ⌘ ⌥ ⇧ ⌃ ⌫ are written as macOS modifiers and are **not** translated, in either language.
- 1-based vs 0-based coordinates are called out wherever a position is discussed: the model is
  0-based internally, every user-facing coordinate is 1-based.
- Format names (FASTA, FASTQ, NEXUS, PHYLIP, CLUSTAL, MSF, Stockholm), tool names, identifiers,
  environment variables, file names, formulae and numeric constants are reproduced verbatim in both
  languages.
- "Primary language" and "authoritative" refer to the English documents; "mirror" refers to the
  Chinese documents.

---

## Accuracy and currency

Both documents describe the source tree as committed at tag `v0.1.0` (Swift 6.0 toolchain, macOS
14.0 deployment target, `arm64-apple-macosx14.0` build). Where the code, the older root manuals, and
these documents disagree, these documents follow the code and record the disagreement in
`DOCUMENTATION.md` §15 rather than silently repeating the older claim.

If you find a statement that no longer matches the code, the citation printed next to it is the
fastest way to confirm it — and the issue is worth reporting per
[`SECURITY.md`](../SECURITY.md) if it has a security dimension, or
[`CONTRIBUTING.md`](../CONTRIBUTING.md) otherwise.

---

*Index of `docs/`. English is the primary language of this documentation set; each of the two
documents indexed here has a mirrored Chinese version at the links above. This index itself is
English-only, and the root-level governance files are Chinese-only; neither is mirrored.*
