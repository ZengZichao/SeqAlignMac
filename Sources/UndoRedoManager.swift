//  UndoRedoManager.swift
//  SeqAlignMac — 撤销/重做命令栈

import Foundation

// MARK: - 命令协议

protocol EditCommand {
    func execute(on alignment: Alignment)
    func undo(on alignment: Alignment)
    var description: String { get }
    /// 估算命令保留状态占用的内存字节数（快照型命令返回序列数据规模），供撤销栈总量限制使用
    var estimatedMemoryBytes: Int { get }
    /// 本命令影响的列集合（增量列统计用）。
    /// - nil：范围未知，画布应全量重算列统计；
    /// - 空集：编辑不影响任何列统计（重命名 / 排序 / 移动等行序或元数据操作），
    ///   画布可直接复用旧统计；
    /// - 非空集：只重算这些列（单字符编辑可将 O(n×m) 降为 O(n)）。
    var dirtyColumns: Set<Int>? { get }
}

extension EditCommand {
    var estimatedMemoryBytes: Int { 0 }
    var dirtyColumns: Set<Int>? { nil }
}

/// 序列数组近似内存占用（residues 每残基 1 字节，名称/描述忽略不计）
func sequenceBytes(_ seqs: [Sequence]) -> Int {
    seqs.reduce(0) { $0 + $1.residues.count }
}

// MARK: - 具体命令

struct RenameCommand: EditCommand {
    let index: Int
    let oldName: String
    let newName: String
    var description: String { "重命名序列" }
    /// 改名不影响列统计，画布可直接复用旧统计
    var dirtyColumns: Set<Int>? { Set() }

    func execute(on alignment: Alignment) {
        guard index < alignment.sequences.count else { return }
        alignment.sequences[index].name = newName
    }
    func undo(on alignment: Alignment) {
        guard index < alignment.sequences.count else { return }
        alignment.sequences[index].name = oldName
    }
}

struct RemoveSeqCommand: EditCommand {
    let indices: [Int]
    let removedSequences: [Sequence]
    var description: String { "删除序列" }

    func execute(on alignment: Alignment) {
        let sortedDesc = indices.sorted(by: >)
        for idx in sortedDesc {
            if idx < alignment.sequences.count {
                alignment.sequences.remove(at: idx)
            }
        }
    }
    func undo(on alignment: Alignment) {
        // execute 之后行数可能已变少（例如撤销栈里前一条命令删了别的序列），
        // 直接 `insert(_:at:)` 会在 at 超界时 trap，因此钳制到合法插入位；
        // 同时不依赖"调用方按升序传 removedSequences"的隐含契约：
        // removedSequences 与 indices 的配对关系在本命令 init 时就固定，
        // 越界时按"插到末尾"处理而不是崩溃，并保留原有相对顺序。
        let sortedAsc = indices.sorted()
        for (i, idx) in sortedAsc.enumerated() where i < removedSequences.count {
            let at = min(max(0, idx), alignment.sequences.count)
            alignment.sequences.insert(removedSequences[i], at: at)
        }
    }
}

struct ReverseComplementCommand: EditCommand {
    let index: Int
    let originalResidues: [UInt8]
    var description: String { "反向互补" }

    func execute(on alignment: Alignment) {
        guard index < alignment.sequences.count else { return }
        let seq = alignment.sequences[index]
        alignment.sequences[index].residues = SequenceUtils.reverseComplement(seq.residues)
    }
    func undo(on alignment: Alignment) {
        guard index < alignment.sequences.count else { return }
        alignment.sequences[index].residues = originalResidues
    }
}

/// 引用类型（class）：execute 记录实际插入位置（可能被钳制到行尾），
/// undo 按记录值删除。若 undo 依赖按原始 pos 反推，行短于 pos 时会撤销静默失效、
/// gap 残留导致撤销前后状态不一致。
final class InsertGapCommand: EditCommand {
    let index: Int
    let pos: Int
    let gapLen: Int
    private var actualInsertPos: Int = -1
    var description: String { "插入空位" }
    /// 在某行 pos 处插入 gapLen 个空位会把该行 pos 之后的全部残基
    /// 右移 gapLen 列，受影响列应为 [start, alignment.length)。本计算属性取不到 alignment
    /// 长度，故返回 nil 走全量重算（契约规定 nil == 全量）。当前因长度变化本会被
    /// ensureStats 的 `columnCount == length` 守卫降级为全量，返回 nil 只是让契约诚实、
    /// 避免未来出现「等长编辑」路径时静默漏算脏列。
    var dirtyColumns: Set<Int>? { nil }

    init(index: Int, pos: Int, gapLen: Int) {
        self.index = index
        self.pos = pos
        self.gapLen = gapLen
    }

    func execute(on alignment: Alignment) {
        guard index < alignment.sequences.count else { return }
        actualInsertPos = min(pos, alignment.sequences[index].residues.count)
        alignment.sequences[index].residues.insert(contentsOf: [UInt8](repeating: 0x2D, count: gapLen), at: actualInsertPos)
    }
    func undo(on alignment: Alignment) {
        guard index < alignment.sequences.count, actualInsertPos >= 0 else { return }
        let residues = alignment.sequences[index].residues
        let removeEnd = min(actualInsertPos + gapLen, residues.count)
        guard actualInsertPos < removeEnd else { return }
        alignment.sequences[index].residues.removeSubrange(actualInsertPos..<removeEnd)
    }
}

struct BatchReplaceCommand: EditCommand {
    let index: Int
    let pos: Int
    let len: Int
    let oldResidues: [UInt8]
    let newResidues: [UInt8]
    var description: String { "批量替换" }
    /// 替换区间 = 写入起点起 max(旧长度, 新长度) 列
    /// 改变长度的替换（newResidues.count != len）会让编辑点**之后**的所有列
    /// 全部位移，有界脏列会跳过它们而复用旧统计。与 InsertGapCommand 同一原则：
    /// 长度变化时返回 nil（契约含义 = 范围未知 = 全量重算）。
    var dirtyColumns: Set<Int>? {
        newResidues.count != len ? nil : Set(pos..<(pos + len))
    }

    func execute(on alignment: Alignment) {
        guard index < alignment.sequences.count else { return }
        var residues = alignment.sequences[index].residues
        let start = min(pos, residues.count)
        let end = min(pos + len, residues.count)
        // 用新残基替换 [start, end) 区间（长度可增可减）
        residues.replaceSubrange(start..<end, with: newResidues)
        alignment.sequences[index].residues = residues
    }
    func undo(on alignment: Alignment) {
        guard index < alignment.sequences.count else { return }
        var residues = alignment.sequences[index].residues
        let start = min(pos, residues.count)
        // 还原：把 execute 写入的 newResidues 区间换回 oldResidues
        let replacedLen = min(newResidues.count, max(0, residues.count - start))
        residues.replaceSubrange(start..<start + replacedLen, with: oldResidues)
        alignment.sequences[index].residues = residues
    }
}

/// 引用类型（class）：在 execute 中记录实际插入索引，undo 时按索引删除，
/// 而不是用名称匹配定位序列（存在同名序列时会定位错）。引用类型保证 execute 写入的
/// insertedIndex 在 undo 时可见（struct 经协议存在容器传递后状态不保留）。
final class AddSeqCommand: EditCommand {
    let sequence: Sequence
    private var insertedIndex: Int = -1
    /// 既有行在 padToMaxLength 补齐前的残基长度（仅记录被补齐改动的行），撤销时还原
    private var originalResidueCounts: [Int: Int] = [:]
    var description: String { "添加序列" }

    init(sequence: Sequence) {
        self.sequence = sequence
    }

    func execute(on alignment: Alignment) {
        alignment.sequences.append(sequence)
        insertedIndex = alignment.sequences.count - 1
        var counts: [Int: Int] = [:]
        for (i, seq) in alignment.sequences.dropLast().enumerated() {
            counts[i] = seq.residues.count
        }
        alignment.padToMaxLength()
        originalResidueCounts = counts.filter { i, original in
            i < alignment.sequences.count && alignment.sequences[i].residues.count != original
        }
    }
    func undo(on alignment: Alignment) {
        guard insertedIndex >= 0, insertedIndex < alignment.sequences.count else { return }
        alignment.sequences.remove(at: insertedIndex)
        for (i, original) in originalResidueCounts {
            guard i < alignment.sequences.count else { continue }
            let current = alignment.sequences[i].residues.count
            if current > original {
                alignment.sequences[i].residues.removeLast(current - original)
            }
        }
        originalResidueCounts.removeAll()
        alignment.revision += 1
    }
}

/// 引用类型（class）：在 execute 中记录实际插入位置，undo 直接使用记录的值，
/// 不依赖反推计算（如按 `actualTo = toIndex > fromIndex ? toIndex - 1 : toIndex`
/// 反推会假设 execute 后数组状态没变，缺乏防御性）。
final class MoveSeqCommand: EditCommand {
    let fromIndex: Int
    let toIndex: Int
    private var actualInsertIndex: Int = -1
    var description: String { "移动序列" }
    /// 行重排不改变每列残基多重集，列统计不变
    var dirtyColumns: Set<Int>? { Set() }

    init(fromIndex: Int, toIndex: Int) {
        self.fromIndex = fromIndex
        self.toIndex = toIndex
    }

    func execute(on alignment: Alignment) {
        // from == to 是空操作：remove 后按 toIndex-1 回插会把序列左移一位
        guard fromIndex != toIndex else { return }
        guard fromIndex < alignment.sequences.count, toIndex <= alignment.sequences.count else { return }
        let seq = alignment.sequences.remove(at: fromIndex)
        let insertIdx = toIndex > fromIndex ? toIndex - 1 : toIndex
        actualInsertIndex = min(insertIdx, alignment.sequences.count)
        alignment.sequences.insert(seq, at: actualInsertIndex)
        alignment.revision += 1
    }
    func undo(on alignment: Alignment) {
        guard actualInsertIndex >= 0, actualInsertIndex < alignment.sequences.count else { return }
        let seq = alignment.sequences.remove(at: actualInsertIndex)
        // fromIndex 同样需要钳制，否则超界 insert 会 trap
        alignment.sequences.insert(seq, at: min(max(0, fromIndex), alignment.sequences.count))
        alignment.revision += 1
    }
}

/// 排序命令：右键「按名称排序」走撤销栈。保存排序前后完整序列数组，
/// execute/undo 直接整体赋值（[Sequence] 值类型写时复制，代价可控）。
struct SortSequencesCommand: EditCommand {
    let oldSequences: [Sequence]
    let newSequences: [Sequence]
    let actionDescription: String
    var description: String { actionDescription }

    init(oldSequences: [Sequence], newSequences: [Sequence], description: String = "排序") {
        self.oldSequences = oldSequences
        self.newSequences = newSequences
        self.actionDescription = description
    }

    var estimatedMemoryBytes: Int { sequenceBytes(oldSequences) + sequenceBytes(newSequences) }
    /// 排序只改行序，每列残基多重集不变，列统计不变
    var dirtyColumns: Set<Int>? { Set() }

    func execute(on alignment: Alignment) {
        alignment.sequences = newSequences
    }
    func undo(on alignment: Alignment) {
        alignment.sequences = oldSequences
    }
}

/// 去除空位列命令：从所有序列中删除指定列集合（全空位列或高空位富集列）。
/// 保存原始序列以便撤销。列索引按降序删除避免偏移。
struct RemoveColumnsCommand: EditCommand {
    let columnsToRemove: [Int]
    let oldSequences: [Sequence]
    let actionDescription: String
    /// NEXUS charsets 是 1-based 列区间，删列后必须同步平移；若原样保留，
    /// "去除空位列"后再导出 NEXUS，得到的是坐标已整体偏移、但字面仍然合法的
    /// CHARSET 定义 —— MrBayes / RAxML / IQ-TREE 会照单全收并按错误分区跑模型，
    /// 这是系统发育基因组学里最难事后发现的一类错误（结果看起来完全正常）。
    var oldCharsets: [CharsetInfo] = []
    var description: String { actionDescription }

    init(columnsToRemove: [Int], alignment: Alignment, description: String) {
        self.columnsToRemove = columnsToRemove.sorted(by: >)
        self.oldSequences = alignment.sequences
        self.actionDescription = description
        self.oldCharsets = alignment.charsets
    }

    var estimatedMemoryBytes: Int { sequenceBytes(oldSequences) }

    /// 单 pass 双指针原地去列，避免每序列生成 2 个临时数组 + Set 哈希二次查找
    func execute(on alignment: Alignment) {
        let removeSet = Set(columnsToRemove)
        // 先按删除后的新坐标重映射分区，再改序列
        alignment.charsets = CharsetRemapper.shift(alignment.charsets, removedColumns: removeSet)
        for i in alignment.sequences.indices {
            var residues = alignment.sequences[i].residues
            var w = 0
            for r in 0..<residues.count where !removeSet.contains(r) {
                residues[w] = residues[r]
                w += 1
            }
            if w < residues.count {
                residues.removeLast(residues.count - w)
                alignment.sequences[i].residues = residues
            }
        }
        alignment.revision += 1
    }
    func undo(on alignment: Alignment) {
        alignment.sequences = oldSequences
        alignment.charsets = oldCharsets      // 分区随序列一并还原
        alignment.revision += 1
    }
}
/// 保存替换前后的 datatype / sequences / charsets / metadata，撤销即完整还原。
struct ReplaceAlignmentCommand: EditCommand {
    let oldDatatype: Datatype
    let oldSequences: [Sequence]
    let oldCharsets: [CharsetInfo]
    let oldMetadata: [String: String]
    let newDatatype: Datatype
    let newSequences: [Sequence]
    let newCharsets: [CharsetInfo]
    let newMetadata: [String: String]
    var description: String { "替换比对" }

    init(old: Alignment, new: Alignment) {
        self.oldDatatype = old.datatype
        self.oldSequences = old.sequences
        self.oldCharsets = old.charsets
        self.oldMetadata = old.metadata
        self.newDatatype = new.datatype
        self.newSequences = new.sequences
        self.newCharsets = new.charsets
        self.newMetadata = new.metadata
    }

    var estimatedMemoryBytes: Int { sequenceBytes(oldSequences) + sequenceBytes(newSequences) }

    func execute(on alignment: Alignment) {
        alignment.datatype = newDatatype
        alignment.sequences = newSequences
        alignment.charsets = newCharsets
        alignment.metadata = newMetadata
    }
    func undo(on alignment: Alignment) {
        alignment.datatype = oldDatatype
        alignment.sequences = oldSequences
        alignment.charsets = oldCharsets
        alignment.metadata = oldMetadata
    }
}

// MARK: - 命令栈管理器

/// 栈深度限制（默认 50），超出时丢弃最旧命令。
/// 对于大比对操作（如 10000 条序列 × 5000 位点 ≈ 50MB/份），
/// 栈深度 20 步即 ~1GB，需要设上限避免内存膨胀。
final class UndoRedoManager {
    /// 最大撤销栈深度
    static let maxStackDepth = 50
    /// 撤销栈内存总量上限（256MB）：快照型命令（排序/去空位列/替换比对）按保留的
    /// 序列字节计入，超出时优先丢弃最旧命令。若只限条数（50），大比对上
    /// 几十次快照操作即可占数 GB。
    static let maxStackBytes = 256 * 1024 * 1024

    private var undoStack: [EditCommand] = []
    private var redoStack: [EditCommand] = []
    private var transactionStack: [[EditCommand]] = []
    private var stackBytes = 0

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var undoStackDepth: Int { undoStack.count }
    var redoStackDepth: Int { redoStack.count }

    /// 开始事务（支持嵌套：内层事务的命令在外层 commit 时合并为一步）
    func beginTransaction() {
        transactionStack.append([])
    }

    /// 提交事务：空事务不做任何事（若 begin 后未执行命令就无条件清空 redoStack，
    /// 会白白丢失重做历史）
    func commitTransaction() {
        guard !transactionStack.isEmpty else { return }
        let cmds = transactionStack.removeLast()
        guard !cmds.isEmpty else { return }
        if let parent = transactionStack.popLast() {
            transactionStack.append(parent + cmds)
            return
        }
        if cmds.count == 1 {
            pushUndo(cmds[0])
        } else {
            pushUndo(CompositeCommand(commands: cmds))
        }
        redoStack.removeAll()
    }

    /// 执行命令
    func execute(_ command: EditCommand, on alignment: Alignment) {
        command.execute(on: alignment)
        if !transactionStack.isEmpty {
            transactionStack[transactionStack.count - 1].append(command)
        } else {
            pushUndo(command)
            redoStack.removeAll()
        }
    }

    /// 压入撤销栈，超出深度或内存上限时丢弃最旧命令（始终保留最近一条）
    private func pushUndo(_ command: EditCommand) {
        undoStack.append(command)
        stackBytes += command.estimatedMemoryBytes
        while (undoStack.count > Self.maxStackDepth || stackBytes > Self.maxStackBytes), undoStack.count > 1 {
            stackBytes -= undoStack.removeFirst().estimatedMemoryBytes
        }
    }

    /// 撤销（返回被撤销的命令，用于 Toast 提示）
    func undoCommand(on alignment: Alignment) -> EditCommand? {
        guard let command = undoStack.popLast() else { return nil }
        command.undo(on: alignment)
        redoStack.append(command)
        return command
    }

    /// 重做（返回被重做的命令，用于 Toast 提示）
    func redoCommand(on alignment: Alignment) -> EditCommand? {
        guard let command = redoStack.popLast() else { return nil }
        command.execute(on: alignment)
        undoStack.append(command)
        return command
    }

    /// 清空（必须同时重置 stackBytes，否则后续 push 会以虚高计数
    /// 提前逐出撤销历史，撤销深度静默缩水）
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        transactionStack.removeAll()
        stackBytes = 0
    }
}

// MARK: - 复合命令（事务）

struct CompositeCommand: EditCommand {
    let commands: [EditCommand]
    var description: String { "事务（\(commands.count) 步操作）" }
    var estimatedMemoryBytes: Int { commands.reduce(0) { $0 + $1.estimatedMemoryBytes } }
    /// 任一子命令范围未知 → 整体未知；否则为各子命令脏列的并集
    var dirtyColumns: Set<Int>? {
        var result = Set<Int>()
        for cmd in commands {
            guard let cols = cmd.dirtyColumns else { return nil }
            result.formUnion(cols)
        }
        return result
    }

    func execute(on alignment: Alignment) {
        for cmd in commands { cmd.execute(on: alignment) }
    }
    func undo(on alignment: Alignment) {
        for cmd in commands.reversed() { cmd.undo(on: alignment) }
    }
}
