//
//  EventInspector.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import Foundation
import ReducerArchitecture

enum EventInspector: StoreNamespace {
    static let valueWindowID = "event-inspector-value-window"

    typealias PublishedValue = Void

    struct StoreEnvironment {
        let syncInlineDiff: @MainActor (_ input: StringDiff.Input?) -> Void
        let openDiffWindow: @MainActor (_ input: StringDiff.Input) -> Void
        let openExternalDiff: @MainActor (_ input: StringDiff.Input) -> Bool
        let openValueWindow: @MainActor (_ input: ValueWindowInput) -> Void
    }

    struct ValueWindowInput: Hashable, Codable, Sendable {
        let title: String
        let value: String
    }

    struct Selection: Equatable {
        var item: TraceViewer.TimelineItem?
        var previousStateItem: TraceViewer.TimelineItem?
    }

    enum MutatingAction {
        case updateSelection(Selection)
        case setInlineDiff(rowID: String?, input: StringDiff.Input?)
    }

    enum EffectAction {
        case inspectDiff(rowID: String)
        case inspectValue(rowID: String)
        case syncInlineDiff(StringDiff.Input?)
        case openDiffWindow(StringDiff.Input)
        case openExternalDiff(StringDiff.Input)
        case openValueWindow(ValueWindowInput)
    }

    struct StoreState {
        var selection: Selection
        var inlineDiffRowID: String?
        var item: TraceViewer.TimelineItem?
        var previousStateItem: TraceViewer.TimelineItem?
        var showsDetailsCard: Bool
        var detailRows: [EventInspectorFormatter.ValueRow]
        var valueRows: [EventInspectorFormatter.ValueRow]?

        init(selection: Selection) {
            self.init(
                selection: selection,
                inlineDiffRowID: nil
            )
        }

        init(
            selection: Selection,
            inlineDiffRowID: String?
        ) {
            self.selection = selection
            self.inlineDiffRowID = inlineDiffRowID
            self.item = nil
            self.previousStateItem = nil
            self.showsDetailsCard = false
            self.detailRows = []
            self.valueRows = nil
            refreshDerivedState()
        }

        func detailRow(forID id: String) -> EventInspectorFormatter.ValueRow? {
            detailRows.first { $0.id == id }
        }

        func valueRow(forID id: String) -> EventInspectorFormatter.ValueRow? {
            valueRows?.first { $0.id == id }
        }

        func row(forID id: String) -> EventInspectorFormatter.ValueRow? {
            detailRow(forID: id) ?? valueRow(forID: id)
        }

        mutating func updateSelection(_ selection: Selection) -> Bool {
            guard self.selection != selection else { return false }
            self.selection = selection
            inlineDiffRowID = nil
            refreshDerivedState()
            return true
        }

        private mutating func refreshDerivedState() {
            item = selection.item
            previousStateItem = selection.previousStateItem
            showsDetailsCard = item.map { !EventInspector.isStateItem($0) } ?? false

            if let item {
                detailRows = EventInspectorFormatter.keyValues(for: item).enumerated().map { index, pair in
                    EventInspectorFormatter.ValueRow(
                        id: "details-\(index)-\(pair.0)",
                        property: pair.0,
                        value: pair.1,
                        isChanged: false,
                        change: nil,
                        inlinePreviewLineLimit: EventInspectorFormatter.inlinePreviewLineLimit(
                            for: pair.1
                        ),
                        showsTruncationInPreview:
                            EventInspectorFormatter.inlinePreviewShowsTruncation(for: pair.1)
                    )
                }
                valueRows = EventInspectorFormatter.valueRows(
                    for: item,
                    previousStateItem: previousStateItem
                )
            }
            else {
                detailRows = []
                valueRows = nil
            }
        }
    }
}

extension EventInspector {
    enum DiffPresentation: Sendable, Equatable {
        case inline
        case window
        case fileMerge
    }

    @MainActor
    static func store(selection: Selection) -> Store {
        Store(.init(selection: selection), env: nil)
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .updateSelection(let selection):
            let hadInlineDiff = state.inlineDiffRowID != nil
            guard state.updateSelection(selection) else { return .none }
            if hadInlineDiff {
                return .action(.effect(.syncInlineDiff(nil)))
            }
            return .none

        case .setInlineDiff(let rowID, let input):
            state.inlineDiffRowID = rowID
            return .action(.effect(.syncInlineDiff(input)))
        }
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        switch action {
        case .inspectDiff(let rowID):
            guard let row = state.valueRow(forID: rowID),
                  let change = row.change else {
                return .none
            }

            let input = StringDiff.input(
                title: row.property,
                oldValue: change.oldValue,
                newValue: change.newValue
            )

            switch diffPresentation(for: change) {
            case .inline:
                let nextRowID = state.inlineDiffRowID == rowID ? nil : rowID
                let nextInput = state.inlineDiffRowID == rowID ? nil : input
                return .action(.mutating(.setInlineDiff(rowID: nextRowID, input: nextInput)))

            case .window:
                return .actions([
                    .mutating(.setInlineDiff(rowID: nil, input: nil)),
                    .effect(.openDiffWindow(input))
                ])

            case .fileMerge:
                return .actions([
                    .mutating(.setInlineDiff(rowID: nil, input: nil)),
                    .effect(.openExternalDiff(input))
                ])
            }

        case .inspectValue(let rowID):
            guard let row = state.row(forID: rowID),
                  row.showsTruncationInPreview else {
                return .none
            }
            return .action(
                .effect(
                    .openValueWindow(
                        .init(
                            title: row.property,
                            value: row.value
                        )
                    )
                )
            )

        case .syncInlineDiff(let input):
            env.syncInlineDiff(input)
            return .none

        case .openDiffWindow(let input):
            env.openDiffWindow(input)
            return .none

        case .openExternalDiff(let input):
            guard !env.openExternalDiff(input) else { return .none }
            return .action(.effect(.openDiffWindow(input)))

        case .openValueWindow(let input):
            env.openValueWindow(input)
            return .none
        }
    }

    static func shouldPresentDiffInline(change: EventInspectorFormatter.ValueChange) -> Bool {
        diffPresentation(for: change) == .inline
    }

    static func diffPresentation(
        for change: EventInspectorFormatter.ValueChange
    ) -> DiffPresentation {
        let maxInlineLineCount = 4
        let maxInlineCombinedCharacterCount = 280
        let maxWindowLineCount = 400
        let maxWindowCombinedCharacterCount = 32_000
        let maxWindowLineComparisonCellCount = 120_000
        let maxWindowLongestLineCharacterCount = 8_000

        let oldLineCount = lineCount(of: change.oldValue)
        let newLineCount = lineCount(of: change.newValue)
        let combinedCharacterCount = change.oldValue.count + change.newValue.count

        if oldLineCount <= maxInlineLineCount,
           newLineCount <= maxInlineLineCount,
           combinedCharacterCount <= maxInlineCombinedCharacterCount {
            return .inline
        }

        let comparisonCellCount = oldLineCount.multipliedReportingOverflow(by: newLineCount)
        if comparisonCellCount.overflow {
            return .fileMerge
        }

        let longestLineCharacterCount = max(
            longestLineCharacterCount(in: change.oldValue),
            longestLineCharacterCount(in: change.newValue)
        )

        if oldLineCount > maxWindowLineCount
            || newLineCount > maxWindowLineCount
            || combinedCharacterCount > maxWindowCombinedCharacterCount
            || comparisonCellCount.partialValue > maxWindowLineComparisonCellCount
            || longestLineCharacterCount > maxWindowLongestLineCharacterCount {
            return .fileMerge
        }

        return .window
    }

    private static func lineCount(of value: String) -> Int {
        max(value.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
    }

    private static func longestLineCharacterCount(in value: String) -> Int {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(\.count)
            .max() ?? value.count
    }

    private static func isStateItem(_ item: TraceViewer.TimelineItem) -> Bool {
        if case .state = item.node {
            return true
        }
        return false
    }
}
