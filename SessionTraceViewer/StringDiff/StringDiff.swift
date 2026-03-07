//
//  StringDiff.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/2/26.
//

import Foundation
import SwiftUI

import FoundationEx
import ReducerArchitecture

enum StringDiff: StoreNamespace {
    static let windowID = "string-diff-window"

    typealias PublishedValue = Void

    struct StoreEnvironment {
        let makeDiffSections: (_ string1: String, _ string2: String) -> [StoreState.DiffSection]
    }

    enum MutatingAction {
        case loadDiff
        case didLoadDiff([StoreState.DiffSection])
        case selectDiff(id: String)
        case selectPreviousDiff
        case selectNextDiff
    }

    enum EffectAction {
        case loadDiffIfNeeded
        case loadDiff(string1: String, string2: String)
    }

    enum PresentationStyle: Sendable {
        case standard
        case inlineEmbedded
    }

    struct Input: Hashable, Codable, Sendable {
        let title: String
        let string1Caption: String
        let string1: String
        let string2Caption: String
        let string2: String
    }

    enum DiffSide: Sendable {
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

    enum DiffLineKind: Sendable {
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
        struct DiffLine: Identifiable, Sendable {
            let id: String
            let lineNumber: Int?
            let text: AttributedString
            let kind: DiffLineKind
        }

        struct DiffRow: Identifiable, Sendable {
            let id: String
            let oldLine: DiffLine?
            let newLine: DiffLine?
        }

        struct DiffSection: Identifiable, Sendable {
            enum Kind: Sendable {
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

        let title: String
        let presentationStyle: PresentationStyle
        let string1Caption: String
        let string1: String
        let string2Caption: String
        let string2: String
        var diffSections: AsyncTaskValue<[DiffSection], Never>
        var selectedDiffIndex: Int?

        var diffHunks: [DiffSection] {
            diffSections.value?.filter(\.isDiff) ?? []
        }

        var selectedDiffID: String? {
            guard let selectedDiffIndex, diffHunks.indices.contains(selectedDiffIndex) else { return nil }
            return diffHunks[selectedDiffIndex].id
        }

        var previousDiffDisabled: Bool {
            guard let selectedDiffIndex else { return diffHunks.isEmpty }
            return selectedDiffIndex <= 0
        }

        var nextDiffDisabled: Bool {
            guard let selectedDiffIndex else { return diffHunks.isEmpty }
            return selectedDiffIndex >= diffHunks.count - 1
        }

        init(
            title: String,
            presentationStyle: PresentationStyle,
            string1Caption: String,
            string1: String,
            string2Caption: String,
            string2: String,
            diffSections: AsyncTaskValue<[DiffSection], Never>? = nil,
            selectedDiffIndex: Int? = nil
        ) {
            self.title = title
            self.presentationStyle = presentationStyle
            self.string1Caption = string1Caption
            self.string1 = string1
            self.string2Caption = string2Caption
            self.string2 = string2
            self.diffSections = diffSections
                ?? .success(StringDiff.makeDiffSections(string1: string1, string2: string2))
            self.selectedDiffIndex = selectedDiffIndex
            normalizeSelectedDiffIndex()
        }

        mutating func normalizeSelectedDiffIndex() {
            selectedDiffIndex = normalizedSelectedDiffIndex
        }

        mutating func selectDiff(id: String) {
            guard let index = diffHunks.firstIndex(where: { $0.id == id }) else { return }
            selectedDiffIndex = index
        }

        mutating func selectPreviousDiff() {
            selectedDiffIndex = previousSelectedDiffIndex
        }

        mutating func selectNextDiff() {
            selectedDiffIndex = nextSelectedDiffIndex
        }

        private var normalizedSelectedDiffIndex: Int? {
            guard !diffHunks.isEmpty else { return nil }
            guard let selectedDiffIndex else { return 0 }
            guard diffHunks.indices.contains(selectedDiffIndex) else { return 0 }
            return selectedDiffIndex
        }

        private var previousSelectedDiffIndex: Int? {
            guard !diffHunks.isEmpty else { return nil }
            guard let selectedDiffIndex else { return 0 }
            return max(selectedDiffIndex - 1, 0)
        }

        private var nextSelectedDiffIndex: Int? {
            guard !diffHunks.isEmpty else { return nil }
            guard let selectedDiffIndex else { return 0 }
            return min(selectedDiffIndex + 1, diffHunks.count - 1)
        }
    }
}

extension StringDiff.PresentationStyle {
    var isInlineEmbedded: Bool {
        self == .inlineEmbedded
    }
}

extension StringDiff {
    @MainActor
    static func store(
        input: Input,
        presentationStyle: PresentationStyle = .standard,
        diffSections: AsyncTaskValue<[StoreState.DiffSection], Never>? = nil
    ) -> Store {
        Store(
            .init(
                title: input.title,
                presentationStyle: presentationStyle,
                string1Caption: input.string1Caption,
                string1: input.string1,
                string2Caption: input.string2Caption,
                string2: input.string2,
                diffSections: diffSections
            ),
            env: nil
        )
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .loadDiff:
            guard case .notStarted = state.diffSections else { return .none }
            state.diffSections = .inProgress
            return .action(.effect(.loadDiff(string1: state.string1, string2: state.string2)))

        case .didLoadDiff(let sections):
            state.diffSections = .success(sections)
            state.normalizeSelectedDiffIndex()
            return .none

        case .selectDiff(let id):
            state.selectDiff(id: id)
            return .none

        case .selectPreviousDiff:
            state.selectPreviousDiff()
            return .none

        case .selectNextDiff:
            state.selectNextDiff()
            return .none
        }
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        switch action {
        case .loadDiffIfNeeded:
            guard case .notStarted = state.diffSections else { return .none }
            return .action(.mutating(.loadDiff))

        case .loadDiff(let string1, let string2):
            return .asyncAction {
                async let sections = env.makeDiffSections(string1, string2)
                return .mutating(.didLoadDiff(await sections))
            }
        }
    }
}
