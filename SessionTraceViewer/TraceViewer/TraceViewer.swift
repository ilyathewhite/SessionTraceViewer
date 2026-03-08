//
//  TraceViewer.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import Foundation
import ReducerArchitecture

enum TraceViewer: StoreNamespace {
    typealias PublishedValue = Void

    struct StoreEnvironment {
        let resetTimelineListFocus: @MainActor () -> Void
        let scrollTimelineListToID: @MainActor (String) -> Void
        let syncEventInspectorSelection: @MainActor (EventInspector.Selection) -> Void
    }

    enum MutatingAction {
        case replaceTraceCollection(SessionTraceCollection)
        case selectEvent(id: String, shouldFocus: Bool)
        case selectAllEventKinds
        case toggleEventKindFilter(EventKind)
        case toggleUserEventFilter
        case selectNextVisible
        case selectPreviousVisible
        case selectNextGraphNode
        case selectPreviousGraphNode
        case selectFirstVisible
        case selectLastVisible
        case toggleCollapseSelected
        case collapseSelected
        case expandSelected
        case collapseAll
        case expandAll
        case focusSelection
    }

    enum EffectAction {
        case none
        case resetTimelineListFocus
        case scrollTimelineListToID(String)
        case syncEventInspectorSelection(EventInspector.Selection)
    }

    enum EventKind: String, Equatable, Hashable {
        case state
        case flow
        case mutation
        case effect
        case batch
    }

    enum EventColorKind: Equatable, Hashable {
        case state
        case mutation
        case effect
        case batch
        case publish
        case cancel
    }

    enum EdgeLineKind: Equatable, Hashable {
        case solid
        case dotted
    }

    struct TimelineItem: Identifiable, Equatable {
        private static let subtitleSeparator = " • "

        let id: String
        let order: Int
        let kind: EventKind
        let colorKind: EventColorKind
        let title: String
        let subtitle: String
        let date: Date?
        let childIDs: [String]
        let node: SessionGraph.Node

        var timeLabel: String {
            EventInspectorFormatter.timestamp(date)
        }

        var subtitleSourceLabel: String? {
            guard let range = subtitle.range(of: Self.subtitleSeparator) else { return nil }
            let prefix = String(subtitle[..<range.lowerBound])
            switch prefix.uppercased() {
            case "USER", "CODE":
                return prefix.uppercased()
            default:
                return nil
            }
        }

        var subtitleDetailLabel: String? {
            guard subtitleSourceLabel != nil,
                  let range = subtitle.range(of: Self.subtitleSeparator) else { return nil }
            return String(subtitle[range.upperBound...])
        }

        var isUserSourceEvent: Bool {
            subtitleSourceLabel == "USER"
        }
    }

    struct StoreState {
        struct CustomScopeSelection: Equatable {
            var eventKinds: Set<EventKind> = []
            var includesUserEvents = false
        }

        enum ScopeFilter: Equatable {
            case all
            case custom(CustomScopeSelection)
        }

        struct OverviewGraphNode: Identifiable, Equatable {
            enum Kind: Equatable {
                case state
                case flow
                case mutation
                case effect
                case batch
            }

            let id: String
            let kind: Kind
            let colorKind: EventColorKind
            let column: Int
            let lane: Int
            let predecessorIDs: [String]
            let edgeLineKindByPredecessorID: [String: EdgeLineKind]
            let timelineID: String?
            let selectionTimelineID: String?
        }

        let traceCollection: SessionTraceCollection
        let graph: SessionGraph
        let orderedIDs: [String]
        let itemsByID: [String: TimelineItem]
        let childrenByParentID: [String: [String]]
        let descendantCountByID: [String: Int]
        let overviewGraphNodes: [OverviewGraphNode]
        let overviewGraphNodeByID: [String: OverviewGraphNode]
        let overviewGraphIDByTimelineID: [String: String]
        let overviewGraphMaxLane: Int

        var scopeFilter: ScopeFilter
        var collapsedIDs: Set<String>
        var selectedID: String?
    }
}

extension TraceViewer {
    private static func followUpEffect(
        shouldResetTimelineListFocus: Bool,
        previousSelectedID: String?,
        selectedID: String?,
        previousEventInspectorSelection: EventInspector.Selection,
        eventInspectorSelection: EventInspector.Selection
    ) -> Store.SyncEffect {
        var actions: [Store.Action] = []

        if shouldResetTimelineListFocus {
            actions.append(.effect(.resetTimelineListFocus))
        }
        if previousEventInspectorSelection != eventInspectorSelection {
            actions.append(.effect(.syncEventInspectorSelection(eventInspectorSelection)))
        }
        if previousSelectedID != selectedID,
           let selectedID {
            actions.append(.effect(.scrollTimelineListToID(selectedID)))
        }

        switch actions.count {
        case 0:
            return .none
        case 1:
            return .action(actions[0])
        default:
            return .actions(actions)
        }
    }

    @MainActor
    static func store(traceCollection: SessionTraceCollection) -> Store {
        Store(.init(traceCollection: traceCollection), env: nil)
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        let previousSelectedID = state.selectedID
        let previousEventInspectorSelection = state.eventInspectorSelection
        var shouldResetTimelineListFocus = false

        switch action {
        case .replaceTraceCollection(let traceCollection):
            state.replaceTraceCollection(traceCollection)

        case .selectEvent(let id, let shouldFocus):
            state.selectEvent(id: id)
            shouldResetTimelineListFocus = shouldFocus

        case .selectAllEventKinds:
            state.selectAllEventKinds()
            shouldResetTimelineListFocus = true

        case .toggleEventKindFilter(let kind):
            state.toggleEventKindFilter(kind)
            shouldResetTimelineListFocus = true

        case .toggleUserEventFilter:
            state.toggleUserEventFilter()
            shouldResetTimelineListFocus = true

        case .selectNextVisible:
            state.selectVisible(offset: 1)
            shouldResetTimelineListFocus = true

        case .selectPreviousVisible:
            state.selectVisible(offset: -1)
            shouldResetTimelineListFocus = true

        case .selectNextGraphNode:
            state.selectGraphNode(offset: 1)
            shouldResetTimelineListFocus = true

        case .selectPreviousGraphNode:
            state.selectGraphNode(offset: -1)
            shouldResetTimelineListFocus = true

        case .selectFirstVisible:
            state.selectFirstVisible()
            shouldResetTimelineListFocus = true

        case .selectLastVisible:
            state.selectLastVisible()
            shouldResetTimelineListFocus = true

        case .toggleCollapseSelected:
            guard let selectedID = state.selectedID else { break }
            guard state.hasChildren(selectedID) else { break }
            if state.collapsedIDs.contains(selectedID) {
                state.collapsedIDs.remove(selectedID)
            }
            else {
                state.collapsedIDs.insert(selectedID)
            }
            state.clampSelection()
            shouldResetTimelineListFocus = true

        case .collapseSelected:
            guard let selectedID = state.selectedID else { break }
            guard state.hasChildren(selectedID) else { break }
            state.collapsedIDs.insert(selectedID)
            state.clampSelection()
            shouldResetTimelineListFocus = true

        case .expandSelected:
            guard let selectedID = state.selectedID else { break }
            state.collapsedIDs.remove(selectedID)
            state.clampSelection()
            shouldResetTimelineListFocus = true

        case .collapseAll:
            for id in state.orderedIDs where state.hasChildren(id) {
                state.collapsedIDs.insert(id)
            }
            state.clampSelection()
            shouldResetTimelineListFocus = true

        case .expandAll:
            state.collapsedIDs.removeAll()
            state.clampSelection()
            shouldResetTimelineListFocus = true

        case .focusSelection:
            state.focusOnSelection()
            shouldResetTimelineListFocus = true
        }
        return followUpEffect(
            shouldResetTimelineListFocus: shouldResetTimelineListFocus,
            previousSelectedID: previousSelectedID,
            selectedID: state.selectedID,
            previousEventInspectorSelection: previousEventInspectorSelection,
            eventInspectorSelection: state.eventInspectorSelection
        )
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        switch action {
        case .none:
            return .none

        case .resetTimelineListFocus:
            env.resetTimelineListFocus()
            return .none

        case .scrollTimelineListToID(let id):
            env.scrollTimelineListToID(id)
            return .none

        case .syncEventInspectorSelection(let selection):
            env.syncEventInspectorSelection(selection)
            return .none
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
