//
//  TraceViewerGraphState.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import Foundation
import ReducerArchitecture

extension TraceViewerGraph.StoreState {
    struct CommitGraphLayout {
        let laneByID: [String: Int]
        let predecessorIDsByID: [String: [String]]
        let edgeLineKindByPredecessorID: [String: [String: TraceViewer.EdgeLineKind]]
        let sharedColumnAnchorByID: [String: String]
        let maxLane: Int
    }

    struct OverviewGraphPresentation {
        let nodes: [TraceViewerGraph.OverviewGraphNode]
        let nodeByID: [String: TraceViewerGraph.OverviewGraphNode]
        let graphIDByTimelineID: [String: String]
        let maxLane: Int
    }

    init(traceCollection: SessionTraceCollection, input: TraceViewerGraph.Input) {
        let timelineData = TraceViewer.TimelineData(traceCollection: traceCollection)
        let commitGraphLayout = TraceViewerGraph.buildCommitGraphLayout(
            graph: traceCollection.sessionGraph,
            orderedIDs: timelineData.orderedIDs,
            itemsByID: timelineData.itemsByID,
            parentByChildID: TraceViewerGraph.makeParentByChildID(from: traceCollection.sessionGraph.edges)
        )
        let overviewGraphPresentation = TraceViewerGraph.buildOverviewGraphPresentation(
            orderedTimelineIDs: timelineData.orderedIDs,
            itemsByID: timelineData.itemsByID,
            laneByTimelineID: commitGraphLayout.laneByID,
            predecessorIDsByTimelineID: commitGraphLayout.predecessorIDsByID,
            edgeLineKindByPredecessorID: commitGraphLayout.edgeLineKindByPredecessorID,
            sharedColumnAnchorByID: commitGraphLayout.sharedColumnAnchorByID,
            maxTimelineLane: commitGraphLayout.maxLane
        )

        self.init(
            timelineData: timelineData,
            overviewGraphNodes: overviewGraphPresentation.nodes,
            overviewGraphNodeByID: overviewGraphPresentation.nodeByID,
            overviewGraphIDByTimelineID: overviewGraphPresentation.graphIDByTimelineID,
            overviewGraphMaxLane: overviewGraphPresentation.maxLane,
            input: input
        )
    }

    var visibleOverviewGraphNodes: [TraceViewerGraph.OverviewGraphNode] {
        let visibleTimelineIDSet = Set(input.visibleTimelineIDs)
        return overviewGraphNodes.filter { node in
            guard let timelineID = node.timelineID else {
                return true
            }
            return visibleTimelineIDSet.contains(timelineID)
        }
    }

    var selectableVisibleOverviewGraphNodes: [TraceViewerGraph.OverviewGraphNode] {
        let selectableVisibleIDSet = Set(input.selectableTimelineIDs)
        return visibleOverviewGraphNodes.filter { node in
            guard let selectionTimelineID = node.selectionTimelineID else { return false }
            return selectableVisibleIDSet.contains(selectionTimelineID)
        }
    }

    var selectableVisibleOverviewGraphNodeIDs: [String] {
        selectableVisibleOverviewGraphNodes.map(\.id)
    }

    var selectedOverviewGraphNodeID: String? {
        guard let selectedTimelineID = input.selectedTimelineID else { return nil }
        return overviewGraphIDByTimelineID[selectedTimelineID]
    }

    var presentation: TraceViewerGraph.Presentation {
        .init(
            nodes: visibleOverviewGraphNodes,
            selectableNodeIDs: selectableVisibleOverviewGraphNodeIDs,
            tooltipTextByNodeID: timelineData.itemsByID.mapValues(\.title),
            selectedNodeID: selectedOverviewGraphNodeID,
            maxLane: overviewGraphMaxLane,
            timelineSelectionIDByNodeID: Dictionary(
                uniqueKeysWithValues: visibleOverviewGraphNodes.compactMap { node in
                    guard let selectionTimelineID = node.selectionTimelineID else { return nil }
                    return (node.id, selectionTimelineID)
                }
            )
        )
    }

    mutating func updateInput(_ input: TraceViewerGraph.Input) {
        self.input = input
    }

    mutating func replaceTraceCollection(_ traceCollection: SessionTraceCollection) {
        let previousInput = input
        self = .init(traceCollection: traceCollection, input: previousInput)
    }

    mutating func selectNode(
        id: String,
        shouldFocusTimelineList: Bool
    ) -> TraceViewerGraph.PublishedValue? {
        guard selectableVisibleOverviewGraphNodeIDs.contains(id),
              let timelineID = overviewGraphNodeByID[id]?.selectionTimelineID,
              input.selectedTimelineID != timelineID else {
            return nil
        }

        input.selectedTimelineID = timelineID
        return .init(
            timelineID: timelineID,
            shouldFocusTimelineList: shouldFocusTimelineList
        )
    }

    mutating func selectAdjacentNode(
        offset: Int,
        shouldFocusTimelineList: Bool
    ) -> TraceViewerGraph.PublishedValue? {
        let selectableNodeIDs = selectableVisibleOverviewGraphNodeIDs
        guard !selectableNodeIDs.isEmpty else { return nil }

        let step = offset > 0 ? 1 : -1
        let startIndex: Int = {
            guard let selectedNodeID = selectedOverviewGraphNodeID,
                  let currentIndex = selectableNodeIDs.firstIndex(of: selectedNodeID) else {
                return step > 0 ? -1 : selectableNodeIDs.count
            }
            return currentIndex
        }()

        let nextIndex = startIndex + step
        guard selectableNodeIDs.indices.contains(nextIndex) else { return nil }
        let nextNodeID = selectableNodeIDs[nextIndex]
        return selectNode(
            id: nextNodeID,
            shouldFocusTimelineList: shouldFocusTimelineList
        )
    }
}

extension TraceViewerGraph {
    static func makeParentByChildID(
        from edges: [SessionGraph.Edge]
    ) -> [String: String] {
        var parentByChildID: [String: String] = [:]
        for edge in edges {
            switch edge {
            case .nested(let nested):
                parentByChildID[nested.childNodeID] = nested.parentNodeID
            case .contains(let contains):
                if parentByChildID[contains.nodeID] == nil {
                    parentByChildID[contains.nodeID] = contains.batchID.rawValue
                }
            default:
                break
            }
        }
        return parentByChildID
    }

    static func buildCommitGraphLayout(
        graph: SessionGraph,
        orderedIDs: [String],
        itemsByID: [String: TraceViewer.TimelineItem],
        parentByChildID: [String: String]
    ) -> TraceViewerGraph.StoreState.CommitGraphLayout {
        var actionProducerByNodeID: [String: String] = [:]
        var effectEmitterByNodeID: [String: String] = [:]
        var startedEffectsByActionID: [String: [SessionGraph.StartedEffectEdge]] = [:]
        var startedActionByEffectID: [String: String] = [:]
        var emittedEdgesByEffectID: [String: [SessionGraph.EmittedActionEdge]] = [:]
        var childNodeIDsByBatchID: [String: [String]] = [:]
        var inputStateByMutatingActionID: [String: String] = [:]
        var resultActionByStateID: [String: String] = [:]
        var mutatingActionIDs: Set<String> = []
        for edge in graph.edges {
            switch edge {
            case .applied(let applied):
                mutatingActionIDs.insert(applied.actionID.rawValue)
            case .startedEffect(let startedEffect):
                startedEffectsByActionID[startedEffect.actionID.rawValue, default: []].append(startedEffect)
                startedActionByEffectID[startedEffect.effectID.rawValue] = startedEffect.actionID.rawValue
            case .producedAction(let produced):
                actionProducerByNodeID[produced.nodeID] = produced.actionID.rawValue
            case .emittedAction(let emitted):
                effectEmitterByNodeID[emitted.nodeID] = emitted.effectID.rawValue
                emittedEdgesByEffectID[emitted.effectID.rawValue, default: []].append(emitted)
            case .contains(let contains):
                childNodeIDsByBatchID[contains.batchID.rawValue, default: []].append(contains.nodeID)
            case .stateInput(let stateInput):
                inputStateByMutatingActionID[stateInput.actionID.rawValue] = stateInput.stateID.rawValue
            case .stateResult(let stateResult):
                resultActionByStateID[stateResult.stateID.rawValue] = stateResult.actionID.rawValue
            default:
                break
            }
        }

        let firstStartedEffectByActionID: [String: String] = startedEffectsByActionID.mapValues { startedEffects in
            startedEffects
                .sorted { lhs, rhs in
                    if lhs.order == rhs.order {
                        return lhs.effectID < rhs.effectID
                    }
                    return lhs.order < rhs.order
                }
                .first?
                .effectID.rawValue ?? ""
        }
        .filter { !$0.value.isEmpty }

        for item in itemsByID.values {
            switch item.node {
            case .state:
                break
            case .action(let action):
                if action.kind == .mutating {
                    mutatingActionIDs.insert(action.id.rawValue)
                }
            case .mutation(let mutation):
                mutatingActionIDs.insert(mutation.actionID.rawValue)
            case .effect, .batch:
                break
            }
        }

        var effectNodeByID: [String: SessionGraph.EffectNode] = [:]
        for node in graph.nodes {
            guard case .effect(let effect) = node else { continue }
            effectNodeByID[effect.id.rawValue] = effect
        }

        func directSourceEffectID(for actionID: String) -> String? {
            guard let item = itemsByID[actionID],
                  case .action(let action) = item.node else {
                return nil
            }
            guard case .effect(let effectID) = action.source else {
                return nil
            }
            return effectID.rawValue
        }

        var branchEffectByNodeID: [String: String] = [:]
        var mainBranchNodeIDs: Set<String> = []
        var branchResolutionStack: Set<String> = []
        func resolveBranchEffectID(for nodeID: String) -> String? {
            if let cached = branchEffectByNodeID[nodeID] {
                return cached
            }
            if mainBranchNodeIDs.contains(nodeID) {
                return nil
            }
            guard branchResolutionStack.insert(nodeID).inserted else {
                return nil
            }
            defer { branchResolutionStack.remove(nodeID) }

            guard let item = itemsByID[nodeID] else {
                mainBranchNodeIDs.insert(nodeID)
                return nil
            }

            let effectID: String?
            switch item.node {
            case .state:
                effectID = nil

            case .effect(let effect):
                effectID = effect.id.rawValue

            case .action(let action):
                if let directEffectID = directSourceEffectID(for: action.id.rawValue) {
                    effectID = directEffectID
                }
                else if let startedEffectID = firstStartedEffectByActionID[action.id.rawValue] {
                    effectID = startedEffectID
                }
                else if action.kind == .effect {
                    // Standalone effect actions are still effect threads even
                    // when runEffect yields .none or no explicit effect node.
                    effectID = "action-thread:\(action.id.rawValue)"
                }
                else if mutatingActionIDs.contains(action.id.rawValue) || action.kind == .mutating {
                    effectID = nil
                }
                else {
                    effectID = nil
                }

            case .mutation:
                effectID = nil

            case .batch:
                if let emittedByEffectID = effectEmitterByNodeID[nodeID] {
                    effectID = emittedByEffectID
                }
                else if let parentID = parentByChildID[nodeID] {
                    effectID = resolveBranchEffectID(for: parentID)
                }
                else {
                    effectID = nil
                }
            }

            if let effectID {
                branchEffectByNodeID[nodeID] = effectID
            }
            else {
                mainBranchNodeIDs.insert(nodeID)
            }
            return effectID
        }

        var parentEffectByEffectID: [String: String] = [:]
        for effect in effectNodeByID.values {
            if let startedByActionID = effect.startedByActionID,
               let parentEffectID = directSourceEffectID(for: startedByActionID.rawValue) {
                parentEffectByEffectID[effect.id.rawValue] = parentEffectID
            }
        }

        var firstIndexByEffectID: [String: Int] = [:]
        var lastIndexByEffectID: [String: Int] = [:]
        for (index, id) in orderedIDs.enumerated() {
            guard let effectID = resolveBranchEffectID(for: id) else { continue }
            if firstIndexByEffectID[effectID] == nil {
                firstIndexByEffectID[effectID] = index
            }
            lastIndexByEffectID[effectID] = index
        }
        let indexByNodeID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) })

        for (effectID, _) in effectNodeByID {
            guard let startIndex = orderedIDs.firstIndex(of: effectID) else { continue }
            if let existingFirst = firstIndexByEffectID[effectID] {
                firstIndexByEffectID[effectID] = min(existingFirst, startIndex)
            }
            else {
                firstIndexByEffectID[effectID] = startIndex
            }
            let existingLast = lastIndexByEffectID[effectID] ?? startIndex
            lastIndexByEffectID[effectID] = max(existingLast, startIndex)
        }

        let syncScheduledEffectActionIDsByBatchID: [String: [String]] = itemsByID.reduce(
            into: [:]
        ) { partialResult, pair in
            guard case .batch(let batch) = pair.value.node,
                  batch.kind == .syncFanOut else {
                return
            }

            let effectActionIDs = (childNodeIDsByBatchID[pair.key] ?? []).filter { childID in
                guard let childItem = itemsByID[childID],
                      case .action(let action) = childItem.node else {
                    return false
                }
                return action.kind == .effect
            }
            guard effectActionIDs.count > 1 else { return }
            partialResult[pair.key] = effectActionIDs
        }

        var groupedStartIndexByEffectID: [String: Int] = [:]
        var groupedStartRankByEffectID: [String: Int] = [:]
        var sharedColumnAnchorByID: [String: String] = [:]
        for (batchID, actionIDs) in syncScheduledEffectActionIDsByBatchID {
            guard let batchIndex = orderedIDs.firstIndex(of: batchID) else { continue }
            for (rank, actionID) in actionIDs.enumerated() {
                sharedColumnAnchorByID[actionID] = batchID
                guard let effectID = resolveBranchEffectID(for: actionID) else { continue }
                groupedStartIndexByEffectID[effectID] = batchIndex
                groupedStartRankByEffectID[effectID] = rank
            }
        }

        let effectIDsByStartOrder = firstIndexByEffectID.keys.sorted { lhs, rhs in
            let leftIndex = groupedStartIndexByEffectID[lhs] ?? firstIndexByEffectID[lhs] ?? .max
            let rightIndex = groupedStartIndexByEffectID[rhs] ?? firstIndexByEffectID[rhs] ?? .max
            if leftIndex == rightIndex {
                let leftRank = groupedStartRankByEffectID[lhs] ?? .max
                let rightRank = groupedStartRankByEffectID[rhs] ?? .max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs < rhs
            }
            return leftIndex < rightIndex
        }

        var laneByEffectID: [String: Int] = [:]
        var activeLaneByEffectID: [String: Int] = [:]
        var occupiedEffectLanes: Set<Int> = []
        var maxLane = 0

        for effectID in effectIDsByStartOrder {
            let startIndex = groupedStartIndexByEffectID[effectID] ?? firstIndexByEffectID[effectID] ?? .max

            let expiredEffects = activeLaneByEffectID.keys.filter { activeEffectID in
                (lastIndexByEffectID[activeEffectID] ?? .max) < startIndex
            }
            for activeEffectID in expiredEffects {
                if let releasedLane = activeLaneByEffectID.removeValue(forKey: activeEffectID) {
                    occupiedEffectLanes.remove(releasedLane)
                }
            }

            let parentLane = parentEffectByEffectID[effectID]
                .flatMap { laneByEffectID[$0] } ?? 0
            let highestActiveLane = activeLaneByEffectID.values.max() ?? 0
            var laneCandidate = max(
                parentLane + 1,
                highestActiveLane > 0 ? highestActiveLane + 1 : 1
            )
            while occupiedEffectLanes.contains(laneCandidate) {
                laneCandidate += 1
            }

            laneByEffectID[effectID] = laneCandidate
            activeLaneByEffectID[effectID] = laneCandidate
            occupiedEffectLanes.insert(laneCandidate)
            maxLane = max(maxLane, laneCandidate)
        }

        var laneByID: [String: Int] = [:]
        for id in orderedIDs {
            if case .state = itemsByID[id]?.node {
                laneByID[id] = 0
                continue
            }

            if let effectID = resolveBranchEffectID(for: id) {
                let lane = laneByEffectID[effectID] ?? 1
                laneByID[id] = lane
                maxLane = max(maxLane, lane)
            }
            else {
                let nodeIndex = indexByNodeID[id] ?? 0
                var occupiedLanes: Set<Int> = []
                for (effectID, lane) in laneByEffectID {
                    guard let firstIndex = groupedStartIndexByEffectID[effectID] ?? firstIndexByEffectID[effectID],
                          let lastIndex = lastIndexByEffectID[effectID] else { continue }
                    guard firstIndex <= nodeIndex && nodeIndex <= lastIndex else { continue }
                    occupiedLanes.insert(lane)
                }

                var laneCandidate = 1
                while occupiedLanes.contains(laneCandidate) {
                    laneCandidate += 1
                }
                laneByID[id] = laneCandidate
                maxLane = max(maxLane, laneCandidate)
            }
        }

        func causalPredecessors(for id: String) -> [String] {
            guard let item = itemsByID[id] else { return [] }

            var predecessorIDs: [String] = []
            switch item.node {
            case .state(let state):
                if let resultActionID = resultActionByStateID[state.id.rawValue] {
                    predecessorIDs.append(resultActionID)
                }

            case .action(let action):
                var hasExplicitCausalSource = false
                switch action.source {
                case .action(let actionID):
                    predecessorIDs.append(actionID.rawValue)
                    hasExplicitCausalSource = true
                case .effect(let effectID):
                    predecessorIDs.append(effectID.rawValue)
                    hasExplicitCausalSource = true
                case .user, .system:
                    break
                }
                if (mutatingActionIDs.contains(action.id.rawValue) || action.kind == .mutating),
                   !hasExplicitCausalSource,
                   let inputStateID = inputStateByMutatingActionID[action.id.rawValue] {
                    predecessorIDs.append(inputStateID)
                }

            case .mutation(let mutation):
                predecessorIDs.append(mutation.actionID.rawValue)

            case .effect(let effect):
                if let actionID = effect.startedByActionID {
                    predecessorIDs.append(actionID.rawValue)
                }

            case .batch:
                if let actionID = actionProducerByNodeID[id] {
                    predecessorIDs.append(actionID)
                }
                if let effectID = effectEmitterByNodeID[id] {
                    predecessorIDs.append(effectID)
                }
                if predecessorIDs.isEmpty, let parentID = parentByChildID[id] {
                    predecessorIDs.append(parentID)
                }
            }

            return predecessorIDs.uniqued()
        }

        let visibleNodeIDs = Set(itemsByID.keys)
        var predecessorAliasByHiddenNodeID: [String: String] = [:]
        for edge in graph.edges {
            switch edge {
            case .applied(let applied):
                guard !visibleNodeIDs.contains(applied.mutationID.rawValue) else { break }
                guard visibleNodeIDs.contains(applied.actionID.rawValue) else { break }
                predecessorAliasByHiddenNodeID[applied.mutationID.rawValue] = applied.actionID.rawValue

            default:
                break
            }
        }

        func resolveVisibleNodeID(_ id: String) -> String? {
            var currentID = id
            var visited: Set<String> = []
            while !visibleNodeIDs.contains(currentID) {
                guard visited.insert(currentID).inserted else { return nil }
                guard let aliasID = predecessorAliasByHiddenNodeID[currentID] else { return nil }
                currentID = aliasID
            }
            return currentID
        }

        func isAsyncEffectKind(_ kind: SessionGraph.EffectNode.Kind) -> Bool {
            kind.rawValue.hasPrefix("async") || kind == .publisher
        }

        var asyncContextByActionID: [String: Bool] = [:]
        var asyncContextActionResolutionStack: Set<String> = []
        var asyncContextByEffectID: [String: Bool] = [:]
        var asyncContextEffectResolutionStack: Set<String> = []

        func isActionInAsyncContext(_ actionID: String) -> Bool {
            if let cached = asyncContextByActionID[actionID] {
                return cached
            }
            guard asyncContextActionResolutionStack.insert(actionID).inserted else {
                return false
            }
            defer { asyncContextActionResolutionStack.remove(actionID) }

            guard let item = itemsByID[actionID],
                  case .action(let action) = item.node else {
                asyncContextByActionID[actionID] = false
                return false
            }

            let isAsyncContext: Bool
            switch action.source {
            case .effect(let effectID):
                isAsyncContext = isEffectInAsyncContext(effectID.rawValue)
            case .action(let sourceActionID):
                isAsyncContext = isActionInAsyncContext(sourceActionID.rawValue)
            case .user, .system:
                isAsyncContext = false
            }

            asyncContextByActionID[actionID] = isAsyncContext
            return isAsyncContext
        }

        func isEffectInAsyncContext(_ effectID: String) -> Bool {
            if let cached = asyncContextByEffectID[effectID] {
                return cached
            }
            guard asyncContextEffectResolutionStack.insert(effectID).inserted else {
                return false
            }
            defer { asyncContextEffectResolutionStack.remove(effectID) }

            guard let effectNode = effectNodeByID[effectID] else {
                asyncContextByEffectID[effectID] = false
                return false
            }

            if isAsyncEffectKind(effectNode.kind) {
                asyncContextByEffectID[effectID] = true
                return true
            }

            let inheritedAsyncContext: Bool = {
                guard let startedByActionID = effectNode.startedByActionID else { return false }
                return isActionInAsyncContext(startedByActionID.rawValue)
            }()

            asyncContextByEffectID[effectID] = inheritedAsyncContext
            return inheritedAsyncContext
        }

        var effectThreadPredecessorByNodeID: [String: String] = [:]
        for (effectID, emittedEdges) in emittedEdgesByEffectID {
            let sortedEmittedEdges = emittedEdges.sorted { lhs, rhs in
                if lhs.emissionIndex == rhs.emissionIndex {
                    if lhs.order == rhs.order {
                        return lhs.nodeID < rhs.nodeID
                    }
                    return lhs.order < rhs.order
                }
                return lhs.emissionIndex < rhs.emissionIndex
            }

            let anchorID: String? = {
                if let visibleEffectID = resolveVisibleNodeID(effectID) {
                    return visibleEffectID
                }
                if let startedActionID = startedActionByEffectID[effectID],
                   let visibleStartedActionID = resolveVisibleNodeID(startedActionID) {
                    return visibleStartedActionID
                }
                return nil
            }()

            var previousVisibleNodeID = anchorID
            for emittedEdge in sortedEmittedEdges {
                guard let emittedVisibleNodeID = resolveVisibleNodeID(emittedEdge.nodeID) else { continue }
                if let previousVisibleNodeID, previousVisibleNodeID != emittedVisibleNodeID {
                    if effectThreadPredecessorByNodeID[emittedVisibleNodeID] == nil {
                        effectThreadPredecessorByNodeID[emittedVisibleNodeID] = previousVisibleNodeID
                    }
                }
                previousVisibleNodeID = emittedVisibleNodeID
            }
        }

        var predecessorIDsByID: [String: [String]] = [:]
        var edgeLineKindByPredecessorID: [String: [String: TraceViewer.EdgeLineKind]] = [:]

        func edgeLineKind(to nodeID: String) -> TraceViewer.EdgeLineKind {
            guard let nodeItem = itemsByID[nodeID] else { return .solid }
            switch nodeItem.node {
            case .action(let action):
                return isActionInAsyncContext(action.id.rawValue) ? .dotted : .solid

            case .effect(let effect):
                return isEffectInAsyncContext(effect.id.rawValue) ? .dotted : .solid

            case .state, .mutation, .batch:
                return .solid
            }
        }

        for id in orderedIDs {
            var predecessorIDs = causalPredecessors(for: id).compactMap { predecessorID in
                resolveVisibleNodeID(predecessorID)
            }
            let threadPredecessorID = effectThreadPredecessorByNodeID[id]
            let prefersSingleThreadPredecessor: Bool = {
                guard let item = itemsByID[id] else { return false }
                guard case .action(let action) = item.node else { return false }
                if case .effect = action.source {
                    return true
                }
                return false
            }()
            if prefersSingleThreadPredecessor, let threadPredecessorID {
                // For effect-sourced actions, prefer one continuation edge to avoid
                // synthetic + causal double incoming edges.
                predecessorIDs = [threadPredecessorID]
            }
            predecessorIDs = predecessorIDs.uniqued()
            predecessorIDsByID[id] = predecessorIDs

            let lineKindByPredecessor: [String: TraceViewer.EdgeLineKind] = Dictionary(
                uniqueKeysWithValues: predecessorIDs.map { predecessorID in
                    (predecessorID, edgeLineKind(to: id))
                }
            )
            edgeLineKindByPredecessorID[id] = lineKindByPredecessor
        }

        return .init(
            laneByID: laneByID,
            predecessorIDsByID: predecessorIDsByID,
            edgeLineKindByPredecessorID: edgeLineKindByPredecessorID,
            sharedColumnAnchorByID: sharedColumnAnchorByID,
            maxLane: max(maxLane, 0)
        )
    }

    static func buildOverviewGraphPresentation(
        orderedTimelineIDs: [String],
        itemsByID: [String: TraceViewer.TimelineItem],
        laneByTimelineID: [String: Int],
        predecessorIDsByTimelineID: [String: [String]],
        edgeLineKindByPredecessorID: [String: [String: TraceViewer.EdgeLineKind]],
        sharedColumnAnchorByID: [String: String],
        maxTimelineLane: Int
    ) -> TraceViewerGraph.StoreState.OverviewGraphPresentation {
        var graphLaneByTimelineID = laneByTimelineID.mapValues { max($0, 1) }
        for timelineID in orderedTimelineIDs {
            guard let item = itemsByID[timelineID] else { continue }
            if case .state = item.node {
                graphLaneByTimelineID[timelineID] = 0
            }
            else if graphLaneByTimelineID[timelineID] == nil {
                graphLaneByTimelineID[timelineID] = 1
            }
        }

        let knownGraphNodeIDs = Set(orderedTimelineIDs)
        var nodes: [TraceViewerGraph.OverviewGraphNode] = []
        nodes.reserveCapacity(orderedTimelineIDs.count)
        var nodeByID: [String: TraceViewerGraph.OverviewGraphNode] = [:]
        var graphIDByTimelineID: [String: String] = [:]
        var columnByTimelineID: [String: Int] = [:]
        var maxLane = max(maxTimelineLane, 0)
        var nextColumn = 0

        for timelineID in orderedTimelineIDs {
            guard let item = itemsByID[timelineID] else { continue }
            let kind: TraceViewerGraph.OverviewGraphNode.Kind = {
                switch item.kind {
                case .state:
                    return .state
                case .flow:
                    return .flow
                case .mutation:
                    return .mutation
                case .effect:
                    return .effect
                case .batch:
                    return .batch
                }
            }()

            let column: Int = {
                if let anchorID = sharedColumnAnchorByID[timelineID],
                   let anchorColumn = columnByTimelineID[anchorID] {
                    return anchorColumn + 1
                }
                return nextColumn
            }()
            columnByTimelineID[timelineID] = column
            nextColumn = max(nextColumn, column + 1)

            let lane: Int = {
                if case .state = item.node { return 0 }
                return max(graphLaneByTimelineID[timelineID] ?? 1, 1)
            }()
            maxLane = max(maxLane, lane)

            let node = TraceViewerGraph.OverviewGraphNode(
                id: timelineID,
                kind: kind,
                colorKind: item.colorKind,
                column: column,
                lane: lane,
                predecessorIDs: (predecessorIDsByTimelineID[timelineID] ?? [])
                    .filter { knownGraphNodeIDs.contains($0) }
                    .uniqued(),
                edgeLineKindByPredecessorID: edgeLineKindByPredecessorID[timelineID] ?? [:],
                timelineID: timelineID,
                selectionTimelineID: timelineID
            )
            nodes.append(node)
            nodeByID[node.id] = node
            graphIDByTimelineID[timelineID] = timelineID
        }

        return .init(
            nodes: nodes,
            nodeByID: nodeByID,
            graphIDByTimelineID: graphIDByTimelineID,
            maxLane: max(maxLane, 0)
        )
    }
}
