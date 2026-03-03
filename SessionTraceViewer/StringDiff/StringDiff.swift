//
//  StringDiff.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/2/26.
//

import Foundation
import SwiftUI

import ReducerArchitecture

enum StringDiff: StoreNamespace {
    static let windowID = "string-diff-window"

    typealias PublishedValue = Void

    typealias StoreEnvironment = Never
    typealias EffectAction = Never
    typealias MutatingAction = Void

    enum PresentationStyle {
        case standard
        case inlineEmbedded
    }

    struct WindowRequest: Hashable, Codable {
        let title: String
        let string1Caption: String
        let string1: String
        let string2Caption: String
        let string2: String
    }

    enum DiffSide {
        case old
        case new

        var highlightBackground: Color {
            switch self {
            case .old:
                ViewerTheme.diffOldHighlightBackground
            case .new:
                ViewerTheme.diffNewHighlightBackground
            }
        }

        var highlightText: Color {
            switch self {
            case .old:
                ViewerTheme.diffOldHighlightText
            case .new:
                ViewerTheme.diffNewHighlightText
            }
        }

        var rowTint: Color {
            highlightBackground.opacity(0.42)
        }
    }

    enum DiffLineKind {
        case unchanged
        case old
        case new

        var rowTint: Color {
            switch self {
            case .unchanged:
                .clear
            case .old:
                DiffSide.old.rowTint
            case .new:
                DiffSide.new.rowTint
            }
        }
    }

    struct StoreState {
        struct DiffLine: Identifiable {
            let id: String
            let lineNumber: Int?
            let text: AttributedString
            let kind: DiffLineKind
        }

        struct DiffRow: Identifiable {
            let id: String
            let oldLine: DiffLine?
            let newLine: DiffLine?
        }

        struct DiffSection: Identifiable {
            enum Kind {
                case context
                case diff(index: Int)
            }

            let id: String
            let kind: Kind
            let oldRangeLabel: String
            let newRangeLabel: String
            let rows: [DiffRow]

            var isDiff: Bool {
                diffIndex != nil
            }

            var diffIndex: Int? {
                guard case .diff(let index) = kind else { return nil }
                return index
            }
        }

        private enum DiffOperation {
            case equal(oldLineNumber: Int, newLineNumber: Int, text: String)
            case delete(oldLineNumber: Int, text: String)
            case insert(newLineNumber: Int, text: String)
        }

        let title: String
        let presentationStyle: PresentationStyle
        let string1Caption: String
        let string2Caption: String
        let sections: [DiffSection]

        var diffHunks: [DiffSection] {
            sections.filter(\.isDiff)
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
            side: DiffSide
        ) -> AttributedString {
            var attributedString = plainAttributedString(for: string)

            let diffFromOther = otherString.difference(from: string)
            for removal in diffFromOther.removals {
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
                    for newIndex in stride(from: newLines.count - 1, through: 0, by: -1) {
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
        ) -> DiffSection {
            let equalLines = operations.compactMap { operation -> (Int, Int, String)? in
                guard case .equal(let oldLineNumber, let newLineNumber, let text) = operation else {
                    return nil
                }
                return (oldLineNumber, newLineNumber, text)
            }

            let rows = equalLines.map { oldLineNumber, newLineNumber, text in
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
        ) -> DiffSection {
            let oldLines = operations.compactMap { operation -> (Int, String)? in
                guard case .delete(let lineNumber, let text) = operation else { return nil }
                return (lineNumber, text)
            }
            let newLines = operations.compactMap { operation -> (Int, String)? in
                guard case .insert(let lineNumber, let text) = operation else { return nil }
                return (lineNumber, text)
            }

            let rowCount = max(oldLines.count, newLines.count)
            let rows = (0..<rowCount).map { rowIndex in
                let oldLine = oldLines.indices.contains(rowIndex) ? oldLines[rowIndex] : nil
                let newLine = newLines.indices.contains(rowIndex) ? newLines[rowIndex] : nil

                return DiffRow(
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
            }

            return DiffSection(
                id: "diff-\(index)",
                kind: .diff(index: index),
                oldRangeLabel: lineRangeLabel(oldLines.map(\.0)),
                newRangeLabel: lineRangeLabel(newLines.map(\.0)),
                rows: rows
            )
        }

        private static func sections(string1: String, string2: String) -> [DiffSection] {
            let operations = diffOperations(
                oldLines: splitLines(string1),
                newLines: splitLines(string2)
            )

            var sections: [DiffSection] = []
            var pendingContextOperations: [DiffOperation] = []
            var pendingDiffOperations: [DiffOperation] = []
            var contextIndex = 0
            var diffIndex = 0

            for operation in operations {
                switch operation {
                case .equal:
                    if !pendingDiffOperations.isEmpty {
                        diffIndex += 1
                        sections.append(
                            makeDiffSection(
                                from: pendingDiffOperations,
                                index: diffIndex
                            )
                        )
                        pendingDiffOperations.removeAll(keepingCapacity: true)
                    }
                    pendingContextOperations.append(operation)
                case .delete, .insert:
                    if !pendingContextOperations.isEmpty {
                        contextIndex += 1
                        sections.append(
                            makeContextSection(
                                from: pendingContextOperations,
                                index: contextIndex
                            )
                        )
                        pendingContextOperations.removeAll(keepingCapacity: true)
                    }
                    pendingDiffOperations.append(operation)
                }
            }

            if !pendingDiffOperations.isEmpty {
                diffIndex += 1
                sections.append(
                    makeDiffSection(
                        from: pendingDiffOperations,
                        index: diffIndex
                    )
                )
            }
            else if !pendingContextOperations.isEmpty {
                contextIndex += 1
                sections.append(
                    makeContextSection(
                        from: pendingContextOperations,
                        index: contextIndex
                    )
                )
            }

            return sections
        }

        init(
            title: String,
            presentationStyle: PresentationStyle,
            string1Caption: String,
            string1: String,
            string2Caption: String,
            string2: String
        ) {
            self.title = title
            self.presentationStyle = presentationStyle
            self.string1Caption = string1Caption
            self.string2Caption = string2Caption

            self.sections = Self.sections(string1: string1, string2: string2)
        }
    }
}

extension StringDiff {
    @MainActor
    static func store(
        title: String,
        presentationStyle: PresentationStyle = .standard,
        string1Caption: String,
        string1: String,
        string2Caption: String,
        string2: String
    ) -> Store {
        Store(
            .init(
                title: title,
                presentationStyle: presentationStyle,
                string1Caption: string1Caption,
                string1: string1,
                string2Caption: string2Caption,
                string2: string2
            ),
            env: nil
        )
    }

    @MainActor
    static func store(windowRequest: WindowRequest) -> Store {
        store(
            title: windowRequest.title,
            presentationStyle: .standard,
            string1Caption: windowRequest.string1Caption,
            string1: windowRequest.string1,
            string2Caption: windowRequest.string2Caption,
            string2: windowRequest.string2
        )
    }
}
