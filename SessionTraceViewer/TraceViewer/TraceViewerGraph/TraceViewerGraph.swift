//
//  TraceViewerGraph.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import Foundation
import ReducerArchitecture

enum TraceViewerGraph: StoreNamespace {
    struct PublishedValue: Equatable {
        let timelineID: String
        let shouldFocusTimelineList: Bool
    }

    struct Input: Equatable {
        var visibleTimelineIDs: [String]
        var selectableTimelineIDs: [String]
        var selectedTimelineID: String?
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
        let colorKind: TraceViewer.EventColorKind
        let column: Int
        let lane: Int
        let predecessorIDs: [String]
        let edgeLineKindByPredecessorID: [String: TraceViewer.EdgeLineKind]
        let timelineID: String?
        let selectionTimelineID: String?
    }

    typealias StoreEnvironment = Never
    typealias EffectAction = Never

    enum MutatingAction {
        case replaceTraceCollection(SessionTraceCollection)
        case updateInput(Input)
        case selectNode(id: String, shouldFocusTimelineList: Bool)
        case selectAdjacentNode(offset: Int, shouldFocusTimelineList: Bool)
    }

    struct Presentation: Equatable {
        var nodes: [OverviewGraphNode]
        var selectableNodeIDs: [String]
        var tooltipTextByNodeID: [String: String]
        var selectedNodeID: String?
        var maxLane: Int
        var timelineSelectionIDByNodeID: [String: String]
    }

    struct StoreState {
        let timelineData: TraceViewer.TimelineData
        let overviewGraphNodes: [OverviewGraphNode]
        let overviewGraphNodeByID: [String: OverviewGraphNode]
        let overviewGraphIDByTimelineID: [String: String]
        let overviewGraphMaxLane: Int

        var input: Input
    }
}

extension TraceViewerGraph {
    @MainActor
    static func store(
        traceCollection: SessionTraceCollection,
        input: Input
    ) -> Store {
        Store(.init(traceCollection: traceCollection, input: input), env: nil)
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .replaceTraceCollection(let traceCollection):
            state.replaceTraceCollection(traceCollection)
            return .none

        case .updateInput(let input):
            state.updateInput(input)
            return .none

        case .selectNode(let id, let shouldFocusTimelineList):
            guard let selection = state.selectNode(id: id, shouldFocusTimelineList: shouldFocusTimelineList) else {
                return .none
            }
            return .action(.publish(selection))

        case .selectAdjacentNode(let offset, let shouldFocusTimelineList):
            guard let selection = state.selectAdjacentNode(
                offset: offset,
                shouldFocusTimelineList: shouldFocusTimelineList
            ) else {
                return .none
            }
            return .action(.publish(selection))
        }
    }
}
