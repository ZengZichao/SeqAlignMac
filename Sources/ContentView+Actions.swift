//  ContentView+Actions.swift
//  SeqAlignMac — 通知处理与上下文菜单动作（从 ContentView.swift 拆分）
//
//  包含：通知注册、上下文菜单动作处理、辅助函数（相似度/空位列/粘贴/拖放）。

import AppKit
import SwiftUI

// MARK: - 通知处理

extension ContentView {
    func setupNotifications() {
        // #10：命令路由收敛为统一守卫方法，基于 keyWindow 的实际活动标签，
        // 而非全局 activeWorkspace 单例（避免窗口/标签切换竞态时命令发错 workspace）
        let center = NotificationCenter.default
        // 统一收集 token，onDisappear 中反注册（修复 observer 泄漏与重复注册）
        func observe(_ name: Notification.Name, _ handler: @escaping (Notification) -> Void) {
            notificationObservers.append(center.addObserver(forName: name, object: nil, queue: .main, using: handler))
        }
        observe(.showPrimer) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.primerPrefill = self.sequenceForPrimer()
            self.showingPrimerSheet = true
        }
        observe(.showSettings) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.showingSettings = true
        }
        observe(.renameSeq) { [self] _ in
            guard isActiveWorkspace() else { return }
            // 使用当前光标行而非硬编码 0，与右键菜单路径行为一致
            let row = max(0, min(self.cursorRow, (self.workspace.currentAlignment?.seqCount ?? 1) - 1))
            self.renameRow = row
            if let align = self.workspace.currentAlignment, row < align.seqCount {
                self.renameText = align.sequences[row].name
            }
            self.renameSheet = true
        }
        observe(.moveSeq) { [self] _ in
            guard isActiveWorkspace() else { return }
            if let align = self.workspace.currentAlignment {
                self.moveFrom = 0
                self.moveTo = align.seqCount - 1
            }
            self.moveSheet = true
        }
        observe(.runAlignment) { [self] _ in
            guard isActiveWorkspace() else { return }
            // 不再无条件清空命令。ExternalAlignerView 的 onAppear 会在 path 为空时
            // 填充当前预设模板，避免首次点「运行」因 path 为空而报错。
            // 用户上次输入的自定义命令得以保留。
            self.externalAlignerSheet = true
        }
        observe(.showTranslate) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.showingTranslateSheet = true
        }
        observe(.pasteFromClipboard) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.handleContextAction(.paste)
        }
        observe(.removeSelectedSeq) { [self] _ in
            guard isActiveWorkspace() else { return }
            let row = max(0, min(self.cursorRow, (self.workspace.currentAlignment?.seqCount ?? 1) - 1))
            if let align = self.workspace.currentAlignment, row < align.seqCount {
                let cmd = RemoveSeqCommand(indices: [row], removedSequences: [align.sequences[row]])
                UndoRedoCoordinator.shared.execute(cmd)
            }
        }
        observe(.reverseComplement) { [self] _ in
            guard isActiveWorkspace() else { return }
            let row = max(0, min(self.cursorRow, (self.workspace.currentAlignment?.seqCount ?? 1) - 1))
            if let align = self.workspace.currentAlignment, row < align.seqCount {
                // 核酸守卫（与右键菜单路径一致）：蛋白序列做 A→T 等碱基置换属数据破坏
                guard align.datatype == .nucleicAcid else { return }
                let cmd = ReverseComplementCommand(index: row, originalResidues: align.sequences[row].residues)
                UndoRedoCoordinator.shared.execute(cmd)
            }
        }
        observe(.insertGap) { [self] _ in
            guard isActiveWorkspace() else { return }
            let row = max(0, min(self.cursorRow, (self.workspace.currentAlignment?.seqCount ?? 1) - 1))
            let col = max(0, self.cursorCol)
            if let align = self.workspace.currentAlignment, row < align.seqCount {
                let cmd = InsertGapCommand(index: row, pos: col, gapLen: 1)
                UndoRedoCoordinator.shared.execute(cmd)
            }
        }
        observe(.showAbout) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.showAboutSheet = true
        }
        observe(.showGuide) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.showGuideSheet = true
        }
        observe(.showQualityReport) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.showQualityReportSheet = true
        }
        observe(.showCommandPalette) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.showCommandPalette = true
        }
        observe(.showExportPreview) { [self] _ in
            guard isActiveWorkspace() else { return }
            self.showExportPreview = true
        }
    }

    /// #10：统一的活动 workspace 守卫——基于 keyWindow 的实际活动标签，
    /// 而非全局 activeWorkspace 单例（后者在多窗口切换时可能有竞态）
    private func isActiveWorkspace() -> Bool {
        WindowRegistry.shared.activeForAction === self.workspace
    }

    private func sequenceForPrimer() -> String {
        guard let align = workspace.currentAlignment, align.seqCount > 0 else { return "" }
        let row = min(max(0, cursorRow), align.seqCount - 1)
        let seq = align.sequences[row]
        return seq.residues.filter { $0 != 0x2D }.map { String(UnicodeScalar($0)) }.joined()
    }

    // MARK: - 上下文菜单动作处理

    /// 重计算型排序统一范式——后台快照 → 预计算 key（Schwartzian transform，
    /// 每序列算一次 O(cols) key）→ 排序 → 回主线程入撤销栈。
    /// 若在排序闭包里每次比较重算两条序列的 GC 含量（最坏 O(rows·cols·log rows)），
    /// 且全部在主线程执行，大比对会秒级冻结。
    private func performSort(_ keySelector: @escaping ([UInt8]) -> Double,
                             description: @escaping () -> String,
                             toast: @escaping () -> String,
                             attempts: Int = 2) {
        guard let align = workspace.currentAlignment else { return }
        let startRevision = align.revision          // 发起时的修订号
        let oldSeqs = align.sequences
        let snapshot = align.snapshot()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            // 每序列只算一次 key
            let keyed = snapshot.sequences.map { seq -> (Sequence, Double) in
                (seq, keySelector(seq.residues))
            }
            let sortedSeqs = keyed.sorted { $0.1 > $1.1 }.map { $0.0 }
            DispatchQueue.main.async {
                // 后台计算期间若发生编辑（修订号变化），旧结果与 oldSeqs 均已过期，
                // 直接应用会静默覆盖用户编辑。改为基于最新数据重跑（至多 2 次），仍冲突则放弃。
                guard align.revision == startRevision else {
                    if attempts > 1 {
                        performSort(keySelector, description: description, toast: toast, attempts: attempts - 1)
                    }
                    return
                }
                if !sequencesUnchanged(oldSeqs, sortedSeqs) {
                    let cmd = SortSequencesCommand(oldSequences: oldSeqs, newSequences: sortedSeqs,
                                                   description: description())
                    UndoRedoCoordinator.shared.execute(cmd)
                    workspace.showToast(toast())
                }
            }
        }
    }

    func handleContextAction(_ action: ContextAction) {
        switch action {
        case .sortByName:
            if let align = workspace.currentAlignment {
                let oldSeqs = align.sequences
                let snapshot = align.snapshot()
                // 排序整体后台化（String 字典序比较已原生优化，无需预计算 key）
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let sortedSeqs = snapshot.sequences.sorted { $0.name < $1.name }
                    DispatchQueue.main.async {
                        if !sequencesUnchanged(oldSeqs, sortedSeqs) {
                            let cmd = SortSequencesCommand(oldSequences: oldSeqs, newSequences: sortedSeqs, description: L.s.toastSortByName)
                            UndoRedoCoordinator.shared.execute(cmd)
                            workspace.showToast(L.s.toastSortByName)
                        }
                    }
                }
            }
        case .sortBySimilarity:
            if let align = workspace.currentAlignment {
                let oldSeqs = align.sequences
                // O(rows×cols) 的列统计 + 相似度排序移到后台，完成后回主线程入撤销栈
                let snapshot = align.snapshot()
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    // 列统计已融合为单遍扫描
                    let consensus = AlignmentStatsCalculator.computeColumnStats(snapshot).consensus
                    let sortedSeqs = snapshot.sequences.enumerated().sorted { (a, b) in
                        let simA = similarity(seq: a.element.residues, consensus: consensus)
                        let simB = similarity(seq: b.element.residues, consensus: consensus)
                        return simA > simB
                    }.map { $0.element }
                    DispatchQueue.main.async {
                        if !sequencesUnchanged(oldSeqs, sortedSeqs) {
                            let cmd = SortSequencesCommand(oldSequences: oldSeqs, newSequences: sortedSeqs, description: L.s.toastSortBySimilarity)
                            UndoRedoCoordinator.shared.execute(cmd)
                            workspace.showToast(L.s.toastSortBySimilarity)
                        }
                    }
                }
            }
        case .sortByGC:
            performSort({ SequenceUtils.gcContent($0) },
                        description: { L.s.toastSortByGC },
                        toast: { L.s.toastSortByGC })
        case .sortByLength:
            performSort({ Double($0.count) },
                        description: { L.s.toastSortByLength },
                        toast: { L.s.toastSortByLength })
        case .sortByLengthNoGaps:
            performSort({ Double(SequenceUtils.effectiveLength($0)) },
                        description: { L.s.toastSortByLengthNoGaps },
                        toast: { L.s.toastSortByLengthNoGaps })
        case .reverseComplement:
            if let align = workspace.currentAlignment, align.datatype == .nucleicAcid {
                let row = max(0, min(cursorRow, align.seqCount - 1))
                let cmd = ReverseComplementCommand(index: row, originalResidues: align.sequences[row].residues)
                UndoRedoCoordinator.shared.execute(cmd)
                workspace.showToast(L.s.toastReverseComplement)
            }
        case .removeAllGapCols:
            removeGapColumns(threshold: 1.0, toast: L.s.toastGapColsRemoved,
                             commandDescription: L.s.toastGapColsRemoved)
        case .removeHighGapCols:
            removeGapColumns(threshold: 0.5, toast: L.s.toastHighGapColsRemoved,
                             commandDescription: L.s.toastHighGapColsRemoved)
        case .copySelection(let range):
            if let align = workspace.currentAlignment {
                let pasteboard = NSPasteboard.general
                let rEnd = min(range.rowEnd, align.seqCount - 1)
                let cEnd = min(range.colEnd, align.length - 1)
                guard rEnd >= range.rowStart, cEnd >= range.colStart else { return }
                // 字节缓冲聚合构造
                var bytes: [UInt8] = []
                bytes.reserveCapacity((rEnd - range.rowStart + 1) * (cEnd - range.colStart + 1 + 16))
                for row in range.rowStart...rEnd {
                    let seq = align.sequences[row]
                    bytes.append(contentsOf: ">\(seq.name)\n".utf8)
                    for col in range.colStart...cEnd {
                        bytes.append(col < seq.residues.count ? seq.residues[col] : 0x2D)
                    }
                    bytes.append(0x0A)
                }
                pasteboard.clearContents()
                pasteboard.setString(String(decoding: bytes, as: UTF8.self), forType: .string)
                let zh = LanguageManager.shared.language == .zh
                workspace.showToast("\(L.s.toastCopied) \(rEnd - range.rowStart + 1) \(zh ? "行 ×" : "rows ×") \(cEnd - range.colStart + 1) \(zh ? "列" : "cols")")
            }
        case .translateRegion:
            showingTranslateSheet = true
        case .insertGap:
            NotificationCenter.default.post(name: .insertGap, object: nil)
        case .paste:
            pasteFromClipboard()
        case .addSequence:
            if let align = workspace.currentAlignment {
                let zh = LanguageManager.shared.language == .zh
                let defaultName = zh ? "序列_\(align.seqCount + 1)" : "Seq_\(align.seqCount + 1)"
                let newSeq = Sequence(name: defaultName,
                                      residues: [UInt8](repeating: 0x2D, count: align.length))
                let cmd = AddSeqCommand(sequence: newSeq)
                UndoRedoCoordinator.shared.execute(cmd)
            }
        }
    }

    /// 去空位列统一入口——后台快照 → 单次锁内遍历统计 gap → 回主线程入撤销栈。
    /// 避免在主线程逐列调用 columnResidues（每列一次锁 + 一次数组分配）。
    private func removeGapColumns(threshold: Double, toast: String, commandDescription: String, attempts: Int = 2) {
        guard let align = workspace.currentAlignment else { return }
        let startRevision = align.revision
        let snapshot = align.snapshot()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let gapCols = findGapColumns(snapshot, threshold: threshold)
            DispatchQueue.main.async {
                // 后台期间发生编辑则按最新数据重跑（至多 2 次），避免用过期列索引删列
                guard align.revision == startRevision else {
                    if attempts > 1 { removeGapColumns(threshold: threshold, toast: toast, commandDescription: commandDescription, attempts: attempts - 1) }
                    return
                }
                guard !gapCols.isEmpty else { return }
                let cmd = RemoveColumnsCommand(columnsToRemove: gapCols, alignment: align,
                                               description: commandDescription)
                UndoRedoCoordinator.shared.execute(cmd)
                workspace.showToast(toast)
            }
        }
    }

    // MARK: - 辅助函数

    /// 排序前后是否无变化：逐元素比较
    private func sequencesUnchanged(_ a: [Sequence], _ b: [Sequence]) -> Bool {
        guard a.count == b.count else { return true }
        for (x, y) in zip(a, b) where x.name != y.name || x.residues != y.residues {
            return false
        }
        return true
    }

    /// 计算序列与共识的相似度（匹配比例）
    private func similarity(seq: [UInt8], consensus: [UInt8]) -> Double {
        let len = min(seq.count, consensus.count)
        guard len > 0 else { return 0 }
        var matches = 0
        var total = 0
        for i in 0..<len {
            if seq[i] != 0x2D && consensus[i] != 0x2D {
                total += 1
                if seq[i] == consensus[i] { matches += 1 }
            }
        }
        return total > 0 ? Double(matches) / Double(total) : 0
    }

    /// 单次锁内遍历按列累加 gap 计数
    private func findGapColumns(_ align: Alignment, threshold: Double) -> [Int] {
        let nSeq = align.seqCount
        guard nSeq > 0 else { return [] }
        let nCol = align.length
        var gapCounts = [Int](repeating: 0, count: nCol)
        align.lockedSequences { seqs in
            for seq in seqs {
                let residues = seq.residues
                let upper = min(residues.count, nCol)
                for col in 0..<upper where residues[col] == 0x2D {
                    gapCounts[col] += 1
                }
            }
        }
        var result: [Int] = []
        result.reserveCapacity(nCol)
        for col in 0..<nCol where Double(gapCounts[col]) / Double(nSeq) >= threshold {
            result.append(col)
        }
        return result
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            workspace.showToast(L.s.toastClipboardEmpty)
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = text.data(using: .utf8) ?? Data()

        if trimmed.contains(">") {
            if let align = try? AlignmentParser.parse(data, format: .fasta) {
                let cmds = align.sequences.map { AddSeqCommand(sequence: $0) }
                UndoRedoCoordinator.shared.executeTransaction(cmds, description: "\(L.s.toastPasted) \(cmds.count)")
            } else {
                workspace.errorMessage = L.s.errorClipboardUnrecognized
            }
        } else {
            var parsed: [Sequence] = []
            let lines = trimmed.split(separator: "\n").map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            for line in lines {
                let cleaned = line.uppercased().filter { c -> Bool in
                    guard let s = c.asciiValue else { return false }
                    return (s >= 0x41 && s <= 0x5A) || s == 0x2D || s == 0x2A
                }
                guard !cleaned.isEmpty else { continue }
                let residues = cleaned.utf8.map { $0 }
                let zh = LanguageManager.shared.language == .zh
                let prefix = zh ? "粘贴序列" : "Pasted"
                parsed.append(Sequence(name: "\(prefix)_\(parsed.count + 1)", residues: residues))
            }
            if parsed.isEmpty {
                workspace.errorMessage = L.s.errorClipboardUnrecognized
            } else {
                let cmds = parsed.map { AddSeqCommand(sequence: $0) }
                UndoRedoCoordinator.shared.executeTransaction(cmds, description: "\(L.s.toastPasted) \(cmds.count)")
            }
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        // 多文件拖放时，第一个文件在当前标签打开，后续文件各在新标签打开。
        // 逐个调用 openFile 到同一 target 会被代次机制丢弃，只留最后一个。
        var isFirst = true
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier("public.file-url") else { continue }
            accepted = true
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                // 不同 provider 回调给 Data / URL / String 三种载荷
                let url: URL?
                if let urlData = item as? Data {
                    url = URL(dataRepresentation: urlData, relativeTo: nil)
                } else if let nsurl = item as? URL {
                    url = nsurl
                } else if let path = item as? String {
                    url = URL(fileURLWithPath: path)
                } else {
                    url = nil
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    if isFirst {
                        // 第一个文件在当前标签打开
                        isFirst = false
                        OpenFileManager.shared.openFile(at: url)
                    } else {
                        // 后续文件各在新标签打开
                        if let ts = WindowRegistry.shared.tabState(for: NSApp.keyWindow) {
                            ts.addTab()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            OpenFileManager.shared.openFile(at: url)
                        }
                    }
                }
            }
        }
        return accepted
    }
}
