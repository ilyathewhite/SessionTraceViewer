//
//  StringDiffEnv.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/2/26.
//

import Foundation

extension StringDiff {
    static func input(
        title: String,
        oldValue: String,
        newValue: String
    ) -> Input {
        .init(
            title: title,
            string1Caption: "Old Value",
            string1: oldValue,
            string2Caption: "New Value",
            string2: newValue
        )
    }

    @MainActor
    static func inlineStore(input: Input) -> Store {
        store(input: input, presentationStyle: .inlineEmbedded)
    }

    @MainActor
    static func windowStore(input: Input) -> Store {
        store(input: input, diffSections: .notStarted)
    }
    
    typealias DiffLine = StoreState.DiffLine
    typealias DiffRow = StoreState.DiffRow
    typealias DiffSection = StoreState.DiffSection

    private enum DiffOperation: Sendable {
        case equal(oldLineNumber: Int, newLineNumber: Int, text: String)
        case delete(oldLineNumber: Int, text: String)
        case insert(newLineNumber: Int, text: String)
    }

    static func makeDiffSections(string1: String, string2: String) -> [DiffSection] {
        guard !Task.isCancelled else { return [] }
        let operations = diffOperations(
            oldLines: splitLines(string1),
            newLines: splitLines(string2)
        )
        guard !Task.isCancelled else { return [] }

        var sections: [DiffSection] = []
        var pendingContextOperations: [DiffOperation] = []
        var pendingDiffOperations: [DiffOperation] = []
        var contextIndex = 0
        var diffIndex = 0

        for operation in operations {
            if Task.isCancelled { return [] }
            switch operation {
            case .equal:
                if !pendingDiffOperations.isEmpty {
                    if Task.isCancelled { return [] }
                    diffIndex += 1
                    guard let section = makeDiffSection(
                        from: pendingDiffOperations,
                        index: diffIndex
                    )
                    else { return [] }
                    sections.append(section)
                    pendingDiffOperations.removeAll(keepingCapacity: true)
                }
                pendingContextOperations.append(operation)

            case .delete, .insert:
                if !pendingContextOperations.isEmpty {
                    if Task.isCancelled { return [] }
                    contextIndex += 1
                    guard let section = makeContextSection(
                        from: pendingContextOperations,
                        index: contextIndex
                    )
                    else { return [] }
                    sections.append(section)
                    pendingContextOperations.removeAll(keepingCapacity: true)
                }
                pendingDiffOperations.append(operation)
            }
        }

        if !pendingDiffOperations.isEmpty {
            if Task.isCancelled { return [] }
            diffIndex += 1
            guard let section = makeDiffSection(
                from: pendingDiffOperations,
                index: diffIndex
            )
            else { return [] }
            sections.append(section)
        }
        else if !pendingContextOperations.isEmpty {
            if Task.isCancelled { return [] }
            contextIndex += 1
            guard let section = makeContextSection(
                from: pendingContextOperations,
                index: contextIndex
            )
            else { return [] }
            sections.append(section)
        }

        guard !Task.isCancelled else { return [] }
        return sections
    }

    private static func plainAttributedString(for string: String) -> AttributedString {
        var attributedString = AttributedString(string)
        if attributedString.startIndex != attributedString.endIndex {
            let fullRange = attributedString.startIndex..<attributedString.endIndex
            attributedString[fullRange].foregroundColor = ViewerTheme.primaryText
        }
        return attributedString
    }

    private static func diffAttributedString(
        for string: String,
        comparedTo otherString: String,
        side: StringDiff.DiffSide
    ) -> AttributedString {
        guard !Task.isCancelled else { return plainAttributedString(for: string) }
        var attributedString = plainAttributedString(for: string)

        let diffFromOther = otherString.difference(from: string)
        for removal in diffFromOther.removals {
            guard !Task.isCancelled else { return plainAttributedString(for: string) }
            guard case .remove(offset: let offset, element: _, associatedWith: _) = removal else {
                assertionFailure()
                continue
            }

            let index = attributedString.index(
                attributedString.startIndex,
                offsetByCharacters: offset
            )
            attributedString[index...index].backgroundColor = side.highlightBackground
            attributedString[index...index].foregroundColor = side.highlightText
        }
        return attributedString
    }

    private static func splitLines(_ string: String) -> [String] {
        guard !string.isEmpty else { return [] }
        return string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func diffOperations(
        oldLines: [String],
        newLines: [String]
    ) -> [DiffOperation] {
        let rowStride = newLines.count + 1
        func tableIndex(_ row: Int, _ column: Int) -> Int {
            row * rowStride + column
        }

        var lcs = Array(
            repeating: 0,
            count: (oldLines.count + 1) * (newLines.count + 1)
        )

        if !oldLines.isEmpty, !newLines.isEmpty {
            for oldIndex in stride(from: oldLines.count - 1, through: 0, by: -1) {
                if Task.isCancelled { return [] }
                for newIndex in stride(from: newLines.count - 1, through: 0, by: -1) {
                    if Task.isCancelled { return [] }
                    let currentIndex = tableIndex(oldIndex, newIndex)
                    if oldLines[oldIndex] == newLines[newIndex] {
                        lcs[currentIndex] = lcs[tableIndex(oldIndex + 1, newIndex + 1)] + 1
                    }
                    else {
                        lcs[currentIndex] = max(
                            lcs[tableIndex(oldIndex + 1, newIndex)],
                            lcs[tableIndex(oldIndex, newIndex + 1)]
                        )
                    }
                }
            }
        }

        var operations: [DiffOperation] = []
        var oldIndex = 0
        var newIndex = 0
        var oldLineNumber = 1
        var newLineNumber = 1

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if Task.isCancelled { return [] }
            if oldIndex < oldLines.count,
                newIndex < newLines.count,
                oldLines[oldIndex] == newLines[newIndex]
            {
                operations.append(
                    .equal(
                        oldLineNumber: oldLineNumber,
                        newLineNumber: newLineNumber,
                        text: oldLines[oldIndex]
                    )
                )
                oldIndex += 1
                newIndex += 1
                oldLineNumber += 1
                newLineNumber += 1
            }
            else if newIndex == newLines.count
                || (
                    oldIndex < oldLines.count
                        && lcs[tableIndex(oldIndex + 1, newIndex)]
                            >= lcs[tableIndex(oldIndex, newIndex + 1)]
                )
            {
                operations.append(
                    .delete(oldLineNumber: oldLineNumber, text: oldLines[oldIndex])
                )
                oldIndex += 1
                oldLineNumber += 1
            }
            else {
                operations.append(
                    .insert(newLineNumber: newLineNumber, text: newLines[newIndex])
                )
                newIndex += 1
                newLineNumber += 1
            }
        }

        return operations
    }

    private static func lineRangeLabel(_ lineNumbers: [Int]) -> String {
        guard let first = lineNumbers.first, let last = lineNumbers.last else {
            return "No lines"
        }
        if first == last {
            return "L\(first)"
        }
        return "L\(first)-\(last)"
    }

    private static func makeContextSection(
        from operations: [DiffOperation],
        index: Int
    ) -> DiffSection? {
        guard !Task.isCancelled else { return nil }

        var equalLines: [(Int, Int, String)] = []
        equalLines.reserveCapacity(operations.count)
        for operation in operations {
            if Task.isCancelled { return nil }
            guard case .equal(let oldLineNumber, let newLineNumber, let text) = operation else {
                continue
            }
            equalLines.append((oldLineNumber, newLineNumber, text))
        }

        var rows: [DiffRow] = []
        rows.reserveCapacity(equalLines.count)
        for (oldLineNumber, newLineNumber, text) in equalLines {
            if Task.isCancelled { return nil }
            rows.append(
                DiffRow(
                    id: "context-\(index)-\(oldLineNumber)-\(newLineNumber)",
                    oldLine: DiffLine(
                        id: "context-old-\(index)-\(oldLineNumber)",
                        lineNumber: oldLineNumber,
                        text: plainAttributedString(for: text),
                        kind: .unchanged
                    ),
                    newLine: DiffLine(
                        id: "context-new-\(index)-\(newLineNumber)",
                        lineNumber: newLineNumber,
                        text: plainAttributedString(for: text),
                        kind: .unchanged
                    )
                )
            )
        }

        return DiffSection(
            id: "context-\(index)",
            kind: .context,
            oldRangeLabel: lineRangeLabel(equalLines.map(\.0)),
            newRangeLabel: lineRangeLabel(equalLines.map(\.1)),
            rows: rows
        )
    }

    private static func makeDiffSection(
        from operations: [DiffOperation],
        index: Int
    ) -> DiffSection? {
        guard !Task.isCancelled else { return nil }

        var oldLines: [(Int, String)] = []
        var newLines: [(Int, String)] = []
        oldLines.reserveCapacity(operations.count)
        newLines.reserveCapacity(operations.count)
        for operation in operations {
            if Task.isCancelled { return nil }
            switch operation {
            case .delete(let lineNumber, let text):
                oldLines.append((lineNumber, text))

            case .insert(let lineNumber, let text):
                newLines.append((lineNumber, text))

            case .equal:
                break
            }
        }

        let rowCount = max(oldLines.count, newLines.count)
        var rows: [DiffRow] = []
        rows.reserveCapacity(rowCount)
        for rowIndex in 0..<rowCount {
            if Task.isCancelled { return nil }
            let oldLine = oldLines.indices.contains(rowIndex) ? oldLines[rowIndex] : nil
            let newLine = newLines.indices.contains(rowIndex) ? newLines[rowIndex] : nil

            rows.append(
                DiffRow(
                    id: "\(index)-\(rowIndex)",
                    oldLine: oldLine.map { lineNumber, text in
                        DiffLine(
                            id: "old-\(index)-\(lineNumber)",
                            lineNumber: lineNumber,
                            text: diffAttributedString(
                                for: text,
                                comparedTo: newLine?.1 ?? "",
                                side: .old
                            ),
                            kind: .old
                        )
                    },
                    newLine: newLine.map { lineNumber, text in
                        DiffLine(
                            id: "new-\(index)-\(lineNumber)",
                            lineNumber: lineNumber,
                            text: diffAttributedString(
                                for: text,
                                comparedTo: oldLine?.1 ?? "",
                                side: .new
                            ),
                            kind: .new
                        )
                    }
                )
            )
        }

        return DiffSection(
            id: "diff-\(index)",
            kind: .diff(index: index),
            oldRangeLabel: lineRangeLabel(oldLines.map(\.0)),
            newRangeLabel: lineRangeLabel(newLines.map(\.0)),
            rows: rows
        )
    }
}
