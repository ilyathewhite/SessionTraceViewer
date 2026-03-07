//
//  EventInspector.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import Foundation
import ReducerArchitecture

enum EventInspector: StoreNamespace {
    typealias PublishedValue = Void

    struct StoreEnvironment {
        let syncInlineDiff: @MainActor (_ input: StringDiff.Input?) -> Void
        let openDiffWindow: @MainActor (_ input: StringDiff.Input) -> Void
    }

    struct Selection: Equatable {
        var item: TraceViewer.TimelineItem?
        var previousStateItem: TraceViewer.TimelineItem?
    }

    enum MutatingAction {
        case updateSelection(Selection)
        case toggleDetailRowExpansion(id: String)
        case toggleValueRowExpansion(id: String)
        case setInlineDiff(rowID: String?, input: StringDiff.Input?)
    }

    enum EffectAction {
        case inspectDiff(rowID: String)
        case syncInlineDiff(StringDiff.Input?)
        case openDiffWindow(StringDiff.Input)
    }

    struct StoreState {
        var selection: Selection
        var detailRowExpansionByID: [String: Bool] = [:]
        var valueRowExpansionByID: [String: Bool] = [:]
        var inlineDiffRowID: String?

        var item: TraceViewer.TimelineItem? {
            selection.item
        }

        var previousStateItem: TraceViewer.TimelineItem? {
            selection.previousStateItem
        }

        var showsDetailsCard: Bool {
            guard let item else { return false }
            return !EventInspector.isStateItem(item)
        }

        var detailRows: [EventInspectorFormatter.ValueRow] {
            guard let item else { return [] }

            return EventInspectorFormatter.keyValues(for: item).enumerated().map { index, pair in
                EventInspectorFormatter.ValueRow(
                    id: "details-\(index)-\(pair.0)",
                    property: pair.0,
                    value: pair.1,
                    isChanged: false,
                    change: nil,
                    isExpandable: EventInspectorFormatter.valueNeedsExpansion(pair.1),
                    isExpandedByDefault: EventInspectorFormatter.valueExpandsByDefault(pair.1)
                )
            }
        }

        var valueRows: [EventInspectorFormatter.ValueRow]? {
            guard let item else { return nil }
            return EventInspectorFormatter.valueRows(
                for: item,
                previousStateItem: previousStateItem
            )
        }

        func detailRow(forID id: String) -> EventInspectorFormatter.ValueRow? {
            detailRows.first { $0.id == id }
        }

        func valueRow(forID id: String) -> EventInspectorFormatter.ValueRow? {
            valueRows?.first { $0.id == id }
        }

        func isDetailRowExpanded(_ row: EventInspectorFormatter.ValueRow) -> Bool {
            detailRowExpansionByID[row.id] ?? row.isExpandedByDefault
        }

        func isValueRowExpanded(_ row: EventInspectorFormatter.ValueRow) -> Bool {
            valueRowExpansionByID[row.id] ?? row.isExpandedByDefault
        }

        mutating func updateSelection(_ selection: Selection) -> Bool {
            guard self.selection != selection else { return false }
            self.selection = selection
            detailRowExpansionByID = [:]
            valueRowExpansionByID = [:]
            inlineDiffRowID = nil
            return true
        }

        mutating func toggleDetailRowExpansion(id: String) {
            guard let row = detailRow(forID: id) else {
                assertionFailure("Missing detail row \(id)")
                return
            }
            let currentValue = detailRowExpansionByID[id] ?? row.isExpandedByDefault
            detailRowExpansionByID[id] = !currentValue
        }

        mutating func toggleValueRowExpansion(id: String) {
            guard let row = valueRow(forID: id) else {
                assertionFailure("Missing value row \(id)")
                return
            }
            let currentValue = valueRowExpansionByID[id] ?? row.isExpandedByDefault
            valueRowExpansionByID[id] = !currentValue
        }
    }
}

extension EventInspector {
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

        case .toggleDetailRowExpansion(let id):
            state.toggleDetailRowExpansion(id: id)
            return .none

        case .toggleValueRowExpansion(let id):
            state.toggleValueRowExpansion(id: id)
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

            if shouldPresentDiffInline(change: change) {
                let nextRowID = state.inlineDiffRowID == rowID ? nil : rowID
                let nextInput = state.inlineDiffRowID == rowID ? nil : input
                return .action(.mutating(.setInlineDiff(rowID: nextRowID, input: nextInput)))
            }

            return .actions([
                .mutating(.setInlineDiff(rowID: nil, input: nil)),
                .effect(.openDiffWindow(input))
            ])

        case .syncInlineDiff(let input):
            env.syncInlineDiff(input)
            return .none

        case .openDiffWindow(let input):
            env.openDiffWindow(input)
            return .none
        }
    }

    static func shouldPresentDiffInline(change: EventInspectorFormatter.ValueChange) -> Bool {
        let maxLineCount = 4
        let maxCombinedCharacterCount = 280

        return lineCount(of: change.oldValue) <= maxLineCount
            && lineCount(of: change.newValue) <= maxLineCount
            && (change.oldValue.count + change.newValue.count) <= maxCombinedCharacterCount
    }

    @MainActor
    static func syncInlineDiff(store: Store) -> @MainActor (StringDiff.Input?) -> Void {
        { [weak store] input in
            guard let store else { return }
            syncInlineDiff(store: store, input: input)
        }
    }

    @MainActor
    static func syncInlineDiff(store: Store, input: StringDiff.Input?) {
        let existingStore: StringDiff.Store? = store.child()
        store.removeChild(existingStore, delay: false)

        guard let input else { return }
        store.addChild(StringDiff.inlineStore(input: input))
    }

    private static func lineCount(of value: String) -> Int {
        max(value.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
    }

    private static func isStateItem(_ item: TraceViewer.TimelineItem) -> Bool {
        if case .state = item.node {
            return true
        }
        return false
    }
}
