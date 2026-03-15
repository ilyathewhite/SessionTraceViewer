//
//  TraceViewerList.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import Foundation
import ReducerArchitecture

enum TraceViewerList: StoreNamespace {
    typealias PublishedValue = Void

    struct StoreEnvironment {
        let resetTimelineListFocus: @MainActor () -> Void
        let scrollTimelineListToID: @MainActor (String) -> Void
    }

    enum MutatingAction {
        case replaceViewerData(TraceViewer.ViewerData)
        case replaceTraceCollection(SessionTraceCollection)
        case selectEvent(id: String, shouldFocus: Bool)
        case selectAllEventKinds
        case toggleEventKindFilter(TraceViewer.EventKind)
        case toggleUserEventFilter
        case selectNextVisible
        case selectPreviousVisible
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
        case resetTimelineListFocus
        case scrollTimelineListToID(String)
    }

    struct StoreState {
        struct ItemIdentity: Hashable {
            let storeInstanceID: String
            let localNodeID: String
        }

        struct CustomScopeSelection: Equatable {
            var eventKinds: Set<TraceViewer.EventKind> = []
            var includesUserEvents = false
        }

        enum ScopeFilter: Equatable {
            case all
            case custom(CustomScopeSelection)
        }

        let traceCollection: SessionTraceCollection
        let visibleStoreCount: Int
        let orderedIDs: [String]
        let orderedIDSet: Set<String>
        let indexByID: [String: Int]
        let itemsByID: [String: TraceViewer.TimelineItem]
        let itemIDByIdentity: [ItemIdentity: String]
        let childrenByParentID: [String: [String]]
        let descendantIDsByID: [String: Set<String>]
        let ancestorIDsByID: [String: Set<String>]
        let descendantCountByID: [String: Int]

        var scopeFilter: ScopeFilter
        var collapsedIDs: Set<String>
        var selectedID: String?
        var visibleIDs: [String]
        var visibleIndexByID: [String: Int]
        var visibleItems: [TraceViewer.TimelineItem]
        var selectableVisibleIDs: [String]
        var selectableVisibleIndexByID: [String: Int]
        var selectableVisibleIDSet: Set<String>
        var graphInput: TraceViewerGraph.Input
        var selectedItem: TraceViewer.TimelineItem?
        var selectedPreviousStateItem: TraceViewer.TimelineItem?
        var eventInspectorSelection: EventInspector.Selection
    }
}

extension TraceViewerList {
    private static func followUpEffect(
        shouldResetTimelineListFocus: Bool,
        previousSelectedID: String?,
        selectedID: String?
    ) -> Store.SyncEffect {
        var actions: [Store.Action] = []

        if shouldResetTimelineListFocus {
            actions.append(.effect(.resetTimelineListFocus))
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
    static func store(viewerData: TraceViewer.ViewerData) -> Store {
        Store(.init(viewerData: viewerData), env: nil)
    }

    @MainActor
    static func store(traceCollection: SessionTraceCollection) -> Store {
        store(
            viewerData: TraceViewer.makeViewerData(
                traceSession: TraceViewer.traceSession(from: traceCollection),
                storeVisibilityByID: [
                    traceCollection.sessionGraph.storeInstanceID.rawValue: true
                ]
            )
        )
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        let previousSelectedID = state.selectedID
        var shouldResetTimelineListFocus = false

        switch action {
        case .replaceViewerData(let viewerData):
            state.replaceViewerData(viewerData)

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
            state.clampSelection(refreshVisibility: true)
            shouldResetTimelineListFocus = true

        case .collapseSelected:
            guard let selectedID = state.selectedID else { break }
            guard state.hasChildren(selectedID) else { break }
            state.collapsedIDs.insert(selectedID)
            state.clampSelection(refreshVisibility: true)
            shouldResetTimelineListFocus = true

        case .expandSelected:
            guard let selectedID = state.selectedID else { break }
            state.collapsedIDs.remove(selectedID)
            state.clampSelection(refreshVisibility: true)
            shouldResetTimelineListFocus = true

        case .collapseAll:
            for id in state.orderedIDs where state.hasChildren(id) {
                state.collapsedIDs.insert(id)
            }
            state.clampSelection(refreshVisibility: true)
            shouldResetTimelineListFocus = true

        case .expandAll:
            state.collapsedIDs.removeAll()
            state.clampSelection(refreshVisibility: true)
            shouldResetTimelineListFocus = true

        case .focusSelection:
            state.focusOnSelection()
            shouldResetTimelineListFocus = true
        }

        return followUpEffect(
            shouldResetTimelineListFocus: shouldResetTimelineListFocus,
            previousSelectedID: previousSelectedID,
            selectedID: state.selectedID
        )
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        switch action {
        case .resetTimelineListFocus:
            env.resetTimelineListFocus()
            return .none

        case .scrollTimelineListToID(let id):
            env.scrollTimelineListToID(id)
            return .none
        }
    }
}
