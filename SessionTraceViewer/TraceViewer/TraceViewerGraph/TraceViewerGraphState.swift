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

    init() {
        self.init(viewerData: TraceViewer.emptyViewerData(), input: .empty)
    }

    init(traceCollection: SessionTraceCollection, input: TraceViewerGraph.Input) {
        self.init(
            viewerData: TraceViewer.makeViewerData(
                traceSession: TraceViewer.traceSession(from: traceCollection),
                storeVisibilityByID: [
                    traceCollection.sessionGraph.storeInstanceID.rawValue: true
                ]
            ),
            input: input
        )
    }

    init(viewerData: TraceViewer.ViewerData, input: TraceViewerGraph.Input) {
        let timelineData = TraceViewer.TimelineData(
            traceCollection: viewerData.primaryTraceCollection,
            orderedIDs: viewerData.orderedIDs,
            itemsByID: viewerData.itemsByID,
            childrenByParentID: viewerData.childrenByParentID,
            descendantCountByID: viewerData.descendantCountByID
        )
        let presentation = TraceViewerGraph.buildPresentation(
            overviewGraphNodes: viewerData.overviewGraphNodes,
            overviewGraphIDByTimelineID: viewerData.overviewGraphIDByTimelineID,
            overviewGraphMaxLane: viewerData.overviewGraphMaxLane,
            tooltipTextByNodeID: viewerData.overviewGraphTooltipTextByID,
            trackRows: viewerData.graphTrackRows,
            input: input
        )

        self.timelineData = timelineData
        self.overviewGraphNodes = viewerData.overviewGraphNodes
        self.overviewGraphNodeByID = viewerData.overviewGraphNodeByID
        self.overviewGraphIDByTimelineID = viewerData.overviewGraphIDByTimelineID
        self.overviewGraphMaxLane = viewerData.overviewGraphMaxLane
        self.overviewGraphTooltipTextByID = viewerData.overviewGraphTooltipTextByID
        self.input = input
        self.presentation = presentation
        self.visibleOverviewGraphNodes = []
        self.selectableVisibleOverviewGraphNodeIDs = []
        self.selectedOverviewGraphNodeID = nil
        refreshDerivedState()
    }

    private mutating func refreshDerivedState() {
        visibleOverviewGraphNodes = presentation.visibleNodes
        selectableVisibleOverviewGraphNodeIDs = presentation.selectableNodeIDs
        selectedOverviewGraphNodeID = presentation.selectedNodeID
    }

    mutating func updateInput(_ input: TraceViewerGraph.Input) {
        let previousInput = self.input
        self.input = input

        if previousInput.visibleTimelineIDs != input.visibleTimelineIDs {
            presentation = makePresentation(for: input)
            refreshDerivedState()
            return
        }

        if previousInput.selectableTimelineIDs != input.selectableTimelineIDs {
            let selectableNodeIDs = selectableVisibleOverviewGraphNodeIDs(
                from: presentation.visibleNodes,
                selectableTimelineIDs: input.selectableTimelineIDs
            )
            selectableVisibleOverviewGraphNodeIDs = selectableNodeIDs
            presentation.selectableNodeIDs = selectableNodeIDs
            presentation.selectableNodeIDSet = Set(selectableNodeIDs)
        }

        if previousInput.selectedTimelineID != input.selectedTimelineID {
            selectedOverviewGraphNodeID = selectedOverviewGraphNodeID(for: input.selectedTimelineID)
            presentation.selectedNodeID = selectedOverviewGraphNodeID
            presentation.selectedColumnID = selectedOverviewGraphNodeID.flatMap {
                presentation.nodeByID[$0]?.column
            }
            presentation.selectedStoreInstanceID = selectedOverviewGraphNodeID.flatMap {
                presentation.nodeByID[$0]?.storeInstanceID
            }
        }
    }

    mutating func replaceViewerData(_ viewerData: TraceViewer.ViewerData) {
        let previousInput = input
        self = .init(viewerData: viewerData, input: previousInput)
    }

    mutating func replaceTraceCollection(_ traceCollection: SessionTraceCollection) {
        replaceViewerData(
            TraceViewer.makeViewerData(
                traceSession: TraceViewer.traceSession(from: traceCollection),
                storeVisibilityByID: [
                    traceCollection.sessionGraph.storeInstanceID.rawValue: true
                ]
            )
        )
    }

    mutating func selectNode(
        id: String,
        shouldFocusTimelineList: Bool
    ) -> TraceViewerGraph.PublishedValue? {
        guard presentation.selectableNodeIDs.contains(id),
              let timelineID = presentation.timelineSelectionIDByNodeID[id],
              input.selectedTimelineID != timelineID else {
            return nil
        }

        input.selectedTimelineID = timelineID
        selectedOverviewGraphNodeID = selectedOverviewGraphNodeID(for: timelineID)
        presentation.selectedNodeID = selectedOverviewGraphNodeID
        presentation.selectedColumnID = selectedOverviewGraphNodeID.flatMap {
            presentation.nodeByID[$0]?.column
        }
        presentation.selectedStoreInstanceID = selectedOverviewGraphNodeID.flatMap {
            presentation.nodeByID[$0]?.storeInstanceID
        }
        return .init(
            timelineID: timelineID,
            shouldFocusTimelineList: shouldFocusTimelineList
        )
    }

    mutating func selectAdjacentNode(
        offset: Int,
        shouldFocusTimelineList: Bool
    ) -> TraceViewerGraph.PublishedValue? {
        let selectableNodeIDs = presentation.selectableNodeIDs
        guard !selectableNodeIDs.isEmpty else { return nil }

        let step = offset > 0 ? 1 : -1
        let startIndex: Int = {
            guard let selectedNodeID = presentation.selectedNodeID,
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

    private func makePresentation(for input: TraceViewerGraph.Input) -> TraceViewerGraph.Presentation {
        TraceViewerGraph.buildPresentation(
            overviewGraphNodes: overviewGraphNodes,
            overviewGraphIDByTimelineID: overviewGraphIDByTimelineID,
            overviewGraphMaxLane: overviewGraphMaxLane,
            tooltipTextByNodeID: overviewGraphTooltipTextByID,
            trackRows: presentation.trackRows,
            input: input
        )
    }

    private func selectableVisibleOverviewGraphNodeIDs(
        from visibleNodes: [TraceViewerGraph.OverviewGraphNode],
        selectableTimelineIDs: [String]
    ) -> [String] {
        let selectableVisibleIDSet = Set(selectableTimelineIDs)
        return visibleNodes.compactMap { node in
            guard let selectionTimelineID = node.selectionTimelineID,
                  selectableVisibleIDSet.contains(selectionTimelineID) else {
                return nil
            }
            return node.id
        }
    }

    private func selectedOverviewGraphNodeID(for selectedTimelineID: String?) -> String? {
        guard let selectedTimelineID else { return nil }
        return overviewGraphIDByTimelineID[selectedTimelineID]
    }
}

extension TraceViewerGraph {
    private static let trackLaneGap = 1

    static func isHiddenOverviewNode(
        _ item: TraceViewer.TimelineItem
    ) -> Bool {
        guard case .batch(let batch) = item.node else {
            return false
        }
        return batch.kind == .syncFanOut
    }

    static func visibleOverviewOrderedIDs(
        from orderedIDs: [String],
        itemsByID: [String: TraceViewer.TimelineItem]
    ) -> [String] {
        orderedIDs.filter { id in
            guard let item = itemsByID[id] else { return false }
            return !isHiddenOverviewNode(item)
        }
    }

    static func buildSource(
        traceSession: TraceSession,
        visibleStoreTraces: [TraceSession.StoreTrace],
        localDataByStoreID: [String: TraceViewer.TimelineData],
        orderedIDs: [String],
        itemsByID: [String: TraceViewer.TimelineItem]
    ) -> TraceViewerGraph.GraphSource {
        guard let firstStoreTrace = visibleStoreTraces.first else {
            return .init(
                nodes: [],
                nodeByID: [:],
                graphIDByTimelineID: [:],
                maxLane: 0,
                tooltipTextByNodeID: [:],
                trackRows: []
            )
        }

        if visibleStoreTraces.count == 1,
           let timelineData = localDataByStoreID[firstStoreTrace.id] {
            let commitGraphLayout = buildCommitGraphLayout(
                graph: firstStoreTrace.traceCollection.sessionGraph,
                orderedIDs: timelineData.orderedIDs,
                itemsByID: timelineData.itemsByID,
                parentByChildID: makeParentByChildID(from: firstStoreTrace.traceCollection.sessionGraph.edges)
            )
            let overviewGraphPresentation = buildOverviewGraphPresentation(
                orderedTimelineIDs: timelineData.orderedIDs,
                itemsByID: timelineData.itemsByID,
                laneByTimelineID: commitGraphLayout.laneByID,
                predecessorIDsByTimelineID: commitGraphLayout.predecessorIDsByID,
                edgeLineKindByPredecessorID: commitGraphLayout.edgeLineKindByPredecessorID,
                sharedColumnAnchorByID: commitGraphLayout.sharedColumnAnchorByID,
                maxTimelineLane: commitGraphLayout.maxLane,
                storeInstanceID: firstStoreTrace.id
            )
            let tooltipTextByNodeID = timelineData.itemsByID.mapValues(\.title)
            let maxColumn = max(
                overviewGraphPresentation.nodes.map(\.column).max() ?? -1,
                firstStoreTrace.endedAt == nil ? 1 : 0
            )
            return .init(
                nodes: overviewGraphPresentation.nodes,
                nodeByID: overviewGraphPresentation.nodeByID,
                graphIDByTimelineID: overviewGraphPresentation.graphIDByTimelineID,
                maxLane: overviewGraphPresentation.maxLane,
                tooltipTextByNodeID: tooltipTextByNodeID,
                trackRows: [
                    .init(
                        id: 0,
                        baseLane: 0,
                        maxLane: overviewGraphPresentation.maxLane,
                        segments: [
                            .init(
                                id: firstStoreTrace.id,
                                storeInstanceID: firstStoreTrace.id,
                                storeName: firstStoreTrace.displayName,
                                startColumn: 0,
                                endColumn: maxColumn,
                                extendsToTrailingEdge: firstStoreTrace.endedAt == nil,
                                baseLane: 0,
                                maxLane: overviewGraphPresentation.maxLane,
                                trackMaxLane: overviewGraphPresentation.maxLane,
                                showsDivider: false,
                                requiredColumnWidth: TraceViewerGraph.requiredColumnWidth(
                                    forStoreName: firstStoreTrace.displayName,
                                    columnsSpanned: maxColumn + 1
                                )
                            )
                        ]
                    )
                ]
            )
        }

        struct StoreLayout {
            let storeTrace: TraceSession.StoreTrace
            let timelineData: TraceViewer.TimelineData
            let commitGraphLayout: TraceViewerGraph.StoreState.CommitGraphLayout
            let firstDate: Date?
            let lastDate: Date?
        }

        let storeOrderByID = Dictionary(
            uniqueKeysWithValues: visibleStoreTraces.enumerated().map { ($1.id, $0) }
        )
        let overviewOrderedIDs = visibleOverviewOrderedIDs(
            from: orderedIDs,
            itemsByID: itemsByID
        )
        let globalColumnByTimelineID = Dictionary(
            uniqueKeysWithValues: overviewOrderedIDs.enumerated().map { ($1, $0) }
        )
        let hasVisibleActiveStore = visibleStoreTraces.contains { $0.endedAt == nil }
        let sessionEndColumn = max(overviewOrderedIDs.count - 1, 0) + (hasVisibleActiveStore ? 1 : 0)

        let allStoreTraces = traceSession.storeTraces.filter { localDataByStoreID[$0.id] != nil }
        let storeLayouts: [StoreLayout] = allStoreTraces.compactMap { storeTrace in
            guard let timelineData = localDataByStoreID[storeTrace.id] else { return nil }
            let commitGraphLayout = buildCommitGraphLayout(
                graph: storeTrace.traceCollection.sessionGraph,
                orderedIDs: timelineData.orderedIDs,
                itemsByID: timelineData.itemsByID,
                parentByChildID: makeParentByChildID(from: storeTrace.traceCollection.sessionGraph.edges)
            )
            return .init(
                storeTrace: storeTrace,
                timelineData: timelineData,
                commitGraphLayout: commitGraphLayout,
                firstDate: timelineData.firstDatedEventAt,
                lastDate: timelineData.lastDatedEventAt
            )
        }

        let sortedLayouts = storeLayouts.sorted { lhs, rhs in
            let lhsStart = lhs.storeTrace.startedAt ?? lhs.firstDate ?? .distantPast
            let rhsStart = rhs.storeTrace.startedAt ?? rhs.firstDate ?? .distantPast
            if lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
            return (storeOrderByID[lhs.storeTrace.id] ?? .max)
                < (storeOrderByID[rhs.storeTrace.id] ?? .max)
        }

        var nextTrackID = 0
        var availableUntilByTrackID: [Int: Date] = [:]
        var trackIDByStoreID: [String: Int] = [:]

        for layout in sortedLayouts {
            let start = layout.storeTrace.startedAt ?? layout.firstDate ?? .distantPast
            let availableTrackIDs = availableUntilByTrackID
                .filter { $0.value <= start }
                .map(\.key)
                .sorted()
            let trackID = availableTrackIDs.first ?? {
                defer { nextTrackID += 1 }
                return nextTrackID
            }()
            trackIDByStoreID[layout.storeTrace.id] = trackID
            availableUntilByTrackID[trackID] = layout.storeTrace.endedAt ?? .distantFuture
        }

        let visibleStoreIDSet = Set(visibleStoreTraces.map(\.id))
        let visibleLayoutsByTrackID = Dictionary(
            grouping: sortedLayouts.filter { visibleStoreIDSet.contains($0.storeTrace.id) }
        ) { layout in
            trackIDByStoreID[layout.storeTrace.id] ?? 0
        }

        let trackIDs = visibleLayoutsByTrackID.keys.sorted()
        var baseLaneByTrackID: [Int: Int] = [:]
        var runningBaseLane = 0
        for trackID in trackIDs {
            baseLaneByTrackID[trackID] = runningBaseLane
            let maxTrackLane = visibleLayoutsByTrackID[trackID]?
                .map(\.commitGraphLayout.maxLane)
                .max() ?? 0
            runningBaseLane += maxTrackLane + 1 + trackLaneGap
        }

        var nodes: [TraceViewerGraph.OverviewGraphNode] = []
        var nodeByID: [String: TraceViewerGraph.OverviewGraphNode] = [:]
        var graphIDByTimelineID: [String: String] = [:]
        var tooltipTextByNodeID: [String: String] = [:]
        var trackRows: [TraceViewerGraph.TrackRow] = []
        var maxLane = 0

        for trackID in trackIDs {
            let trackLayouts = (visibleLayoutsByTrackID[trackID] ?? []).sorted { lhs, rhs in
                let lhsStart = lhs.storeTrace.startedAt ?? lhs.firstDate ?? .distantPast
                let rhsStart = rhs.storeTrace.startedAt ?? rhs.firstDate ?? .distantPast
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                return lhs.storeTrace.id < rhs.storeTrace.id
            }
            let baseLane = baseLaneByTrackID[trackID] ?? 0
            let trackMaxLane = trackLayouts
                .map { baseLane + $0.commitGraphLayout.maxLane }
                .max() ?? baseLane
            maxLane = max(maxLane, trackMaxLane)

            let segments: [TraceViewerGraph.TrackSegment] = trackLayouts.enumerated().compactMap { index, layout in
                let timelineIDs = layout.timelineData.orderedIDs.map {
                    TraceViewer.scopedTimelineID(
                        storeInstanceID: layout.storeTrace.id,
                        localNodeID: $0
                    )
                }
                let columns = timelineIDs.compactMap { globalColumnByTimelineID[$0] }
                let startColumn = columns.min()
                    ?? inferredStartColumn(
                        for: layout.storeTrace.startedAt ?? layout.firstDate,
                        orderedIDs: overviewOrderedIDs,
                        itemsByID: itemsByID,
                        sessionEndColumn: sessionEndColumn
                    )
                let eventEndColumn = columns.max()
                let endColumn: Int
                if layout.storeTrace.endedAt == nil {
                    endColumn = sessionEndColumn
                }
                else {
                    endColumn = eventEndColumn
                        ?? inferredEndColumn(
                            for: layout.storeTrace.endedAt ?? layout.lastDate,
                            orderedIDs: overviewOrderedIDs,
                            itemsByID: itemsByID,
                            fallbackColumn: startColumn
                        )
                }
                return .init(
                    id: layout.storeTrace.id,
                    storeInstanceID: layout.storeTrace.id,
                    storeName: layout.storeTrace.displayName,
                    startColumn: startColumn,
                    endColumn: endColumn,
                    extendsToTrailingEdge: layout.storeTrace.endedAt == nil,
                    baseLane: baseLane,
                    maxLane: baseLane + layout.commitGraphLayout.maxLane,
                    trackMaxLane: trackMaxLane,
                    showsDivider: index > 0,
                    requiredColumnWidth: TraceViewerGraph.requiredColumnWidth(
                        forStoreName: layout.storeTrace.displayName,
                        columnsSpanned: max(endColumn - startColumn + 1, 1)
                    )
                )
            }

            for layout in trackLayouts {
                let predecessorIDsByLocalID = layout.commitGraphLayout.predecessorIDsByID
                let lineKindByPredecessorID = layout.commitGraphLayout.edgeLineKindByPredecessorID
                for localID in layout.timelineData.orderedIDs {
                    guard let item = layout.timelineData.itemsByID[localID] else { continue }
                    guard !isHiddenOverviewNode(item) else { continue }
                    let globalID = TraceViewer.scopedTimelineID(
                        storeInstanceID: layout.storeTrace.id,
                        localNodeID: localID
                    )
                    guard let column = globalColumnByTimelineID[globalID] else { continue }
                    let predecessorIDs = (predecessorIDsByLocalID[localID] ?? []).map {
                        TraceViewer.scopedTimelineID(
                            storeInstanceID: layout.storeTrace.id,
                            localNodeID: $0
                        )
                    }
                    let edgeLineKindByGlobalPredecessorID = Dictionary(
                        uniqueKeysWithValues: (lineKindByPredecessorID[localID] ?? [:]).map { pair in
                            (
                                TraceViewer.scopedTimelineID(
                                    storeInstanceID: layout.storeTrace.id,
                                    localNodeID: pair.key
                                ),
                                pair.value
                            )
                        }
                    )
                    let localLane = layout.commitGraphLayout.laneByID[localID]
                        ?? (item.kind == .state ? 0 : 1)
                    let node = TraceViewerGraph.OverviewGraphNode(
                        id: globalID,
                        storeInstanceID: layout.storeTrace.id,
                        kind: overviewKind(for: item.kind),
                        colorKind: item.colorKind,
                        column: column,
                        lane: baseLane + localLane,
                        predecessorIDs: predecessorIDs,
                        edgeLineKindByPredecessorID: edgeLineKindByGlobalPredecessorID,
                        timelineID: globalID,
                        selectionTimelineID: globalID
                    )
                    nodes.append(node)
                    nodeByID[node.id] = node
                    graphIDByTimelineID[globalID] = globalID
                    tooltipTextByNodeID[globalID] = item.title
                }
            }

            trackRows.append(
                .init(
                    id: trackID,
                    baseLane: baseLane,
                    maxLane: trackMaxLane,
                    segments: segments
                )
            )
        }

        return .init(
            nodes: nodes,
            nodeByID: nodeByID,
            graphIDByTimelineID: graphIDByTimelineID,
            maxLane: maxLane,
            tooltipTextByNodeID: tooltipTextByNodeID,
            trackRows: trackRows
        )
    }

    private static func overviewKind(
        for eventKind: TraceViewer.EventKind
    ) -> TraceViewerGraph.OverviewGraphNode.Kind {
        switch eventKind {
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
    }

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

        let hiddenOverviewNodeIDs = Set(
            itemsByID.compactMap { pair in
                isHiddenOverviewNode(pair.value) ? pair.key : nil
            }
        )

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

        let visibleNodeIDs = Set(itemsByID.keys).subtracting(hiddenOverviewNodeIDs)
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

        for hiddenNodeID in hiddenOverviewNodeIDs {
            guard predecessorAliasByHiddenNodeID[hiddenNodeID] == nil else { continue }
            guard let aliasID = causalPredecessors(for: hiddenNodeID).first else { continue }
            predecessorAliasByHiddenNodeID[hiddenNodeID] = aliasID
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
        maxTimelineLane: Int,
        storeInstanceID: String
    ) -> TraceViewerGraph.StoreState.OverviewGraphPresentation {
        let knownGraphNodeIDs = Set(
            visibleOverviewOrderedIDs(from: orderedTimelineIDs, itemsByID: itemsByID)
        )
        var nodes: [TraceViewerGraph.OverviewGraphNode] = []
        nodes.reserveCapacity(knownGraphNodeIDs.count)
        var nodeByID: [String: TraceViewerGraph.OverviewGraphNode] = [:]
        var graphIDByTimelineID: [String: String] = [:]
        var columnByTimelineID: [String: Int] = [:]
        var maxLane = max(maxTimelineLane, 0)
        var nextColumn = 0

        for timelineID in orderedTimelineIDs {
            guard let item = itemsByID[timelineID] else { continue }
            if isHiddenOverviewNode(item) {
                let hiddenColumn: Int = {
                    if let anchorID = sharedColumnAnchorByID[timelineID],
                       let anchorColumn = columnByTimelineID[anchorID] {
                        return anchorColumn + 1
                    }
                    let predecessorColumns = (predecessorIDsByTimelineID[timelineID] ?? [])
                        .compactMap { columnByTimelineID[$0] }
                    if let predecessorColumn = predecessorColumns.max() {
                        return predecessorColumn
                    }
                    return max(nextColumn - 1, 0)
                }()
                columnByTimelineID[timelineID] = hiddenColumn
                continue
            }

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
                return max(laneByTimelineID[timelineID] ?? 1, 1)
            }()
            maxLane = max(maxLane, lane)

            let node = TraceViewerGraph.OverviewGraphNode(
                id: timelineID,
                storeInstanceID: storeInstanceID,
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

    static func buildPresentation(
        overviewGraphNodes: [TraceViewerGraph.OverviewGraphNode],
        overviewGraphIDByTimelineID: [String: String],
        overviewGraphMaxLane: Int,
        tooltipTextByNodeID: [String: String],
        trackRows: [TraceViewerGraph.TrackRow],
        input: TraceViewerGraph.Input
    ) -> TraceViewerGraph.Presentation {
        let visibleTimelineIDSet = Set(input.visibleTimelineIDs)
        let visibleNodes = overviewGraphNodes.filter { node in
            guard let timelineID = node.timelineID else {
                return true
            }
            return visibleTimelineIDSet.contains(timelineID)
        }
        let selectableTimelineIDSet = Set(input.selectableTimelineIDs)
        let nodeByID = Dictionary(uniqueKeysWithValues: visibleNodes.map { ($0.id, $0) })
        let selectableNodeIDs: [String] = visibleNodes.compactMap { node -> String? in
            guard let selectionTimelineID = node.selectionTimelineID,
                  selectableTimelineIDSet.contains(selectionTimelineID) else {
                return nil
            }
            return node.id
        }
        let selectedNodeID = input.selectedTimelineID.flatMap { overviewGraphIDByTimelineID[$0] }
        let selectedNode = selectedNodeID.flatMap { nodeByID[$0] }
        let visibleNodeMaxLane = visibleNodes.map(\.lane).max() ?? -1
        let visibleTrackMaxLane = trackRows.map(\.maxLane).max() ?? -1
        let visibleMaxLane = max(
            visibleNodeMaxLane,
            max(visibleTrackMaxLane, overviewGraphMaxLane)
        )

        return .init(
            visibleNodes: visibleNodes,
            columns: buildOverviewColumns(
                nodes: visibleNodes,
                minimumColumnCount: maxTrackEndColumn(trackRows: trackRows) + 1
            ),
            nodeByID: nodeByID,
            selectableNodeIDs: selectableNodeIDs,
            selectableNodeIDSet: Set(selectableNodeIDs),
            tooltipTextByNodeID: tooltipTextByNodeID,
            tooltipWidthByNodeID: tooltipTextByNodeID.mapValues { text in
                TraceViewerGraph.tooltipWidth(for: text)
            },
            selectedNodeID: selectedNodeID,
            selectedColumnID: selectedNode?.column,
            selectedStoreInstanceID: selectedNode?.storeInstanceID,
            visibleMaxLane: visibleMaxLane,
            maxLane: overviewGraphMaxLane,
            trackRows: trackRows,
            displayLaneByLane: displayLaneByLane(trackRows: trackRows),
            columnWidth: max(
                TraceViewerGraph.OverviewMetrics.columnWidth,
                trackRows.flatMap(\.segments).map(\.requiredColumnWidth).max()
                    ?? TraceViewerGraph.OverviewMetrics.columnWidth
            ),
            timelineSelectionIDByNodeID: Dictionary(
                uniqueKeysWithValues: visibleNodes.compactMap { node in
                    guard let selectionTimelineID = node.selectionTimelineID else { return nil }
                    return (node.id, selectionTimelineID)
                }
            )
        )
    }

    static func buildOverviewColumns(
        nodes: [TraceViewerGraph.OverviewGraphNode],
        minimumColumnCount: Int = 0
    ) -> [TraceViewerGraph.OverviewColumn] {
        let maxColumn = max(
            nodes.map(\.column).max() ?? -1,
            max(minimumColumnCount - 1, -1)
        )
        guard maxColumn >= 0 else {
            return []
        }
        let nodesByColumn = Dictionary(grouping: nodes, by: \.column)
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let nodeIndexByID = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        let edgePiecesByColumn = buildOverviewEdgePieces(
            nodes: nodes,
            nodesByColumn: nodesByColumn,
            nodeByID: nodeByID,
            nodeIndexByID: nodeIndexByID
        )

        return (0...maxColumn).map { column in
            .init(
                id: column,
                nodes: (nodesByColumn[column] ?? [])
                    .sorted { lhs, rhs in
                        if lhs.lane == rhs.lane {
                            return lhs.id < rhs.id
                        }
                        return lhs.lane > rhs.lane
                    },
                edgePieces: edgePiecesByColumn[column] ?? []
            )
        }
    }

    private static func maxTrackEndColumn(
        trackRows: [TraceViewerGraph.TrackRow]
    ) -> Int {
        trackRows
            .flatMap(\.segments)
            .map(\.endColumn)
            .max() ?? -1
    }

    private static func inferredStartColumn(
        for startDate: Date?,
        orderedIDs: [String],
        itemsByID: [String: TraceViewer.TimelineItem],
        sessionEndColumn: Int
    ) -> Int {
        guard !orderedIDs.isEmpty else { return 0 }
        guard let startDate else { return 0 }
        for (index, id) in orderedIDs.enumerated() {
            guard let date = itemsByID[id]?.date else { continue }
            if date >= startDate {
                return index
            }
        }
        return sessionEndColumn
    }

    private static func inferredEndColumn(
        for endDate: Date?,
        orderedIDs: [String],
        itemsByID: [String: TraceViewer.TimelineItem],
        fallbackColumn: Int
    ) -> Int {
        guard !orderedIDs.isEmpty else { return fallbackColumn }
        guard let endDate else { return fallbackColumn }
        for (index, id) in orderedIDs.enumerated().reversed() {
            guard let date = itemsByID[id]?.date else { continue }
            if date <= endDate {
                return max(index, fallbackColumn)
            }
        }
        return fallbackColumn
    }

    private static func buildOverviewEdgePieces(
        nodes: [TraceViewerGraph.OverviewGraphNode],
        nodesByColumn: [Int: [TraceViewerGraph.OverviewGraphNode]],
        nodeByID: [String: TraceViewerGraph.OverviewGraphNode],
        nodeIndexByID: [String: Int]
    ) -> [Int: [TraceViewerGraph.OverviewEdgePiece]] {
        var edgePiecesByColumn: [Int: [TraceViewerGraph.OverviewEdgePiece]] = [:]

        for node in nodes {
            guard let nodeIndex = nodeIndexByID[node.id] else { continue }

            for predecessorID in node.predecessorIDs {
                guard let predecessor = nodeByID[predecessorID],
                      let predecessorIndex = nodeIndexByID[predecessorID],
                      predecessorIndex < nodeIndex else {
                    continue
                }

                appendOverviewEdgePieces(
                    from: predecessor,
                    to: node,
                    lineKind: node.edgeLineKindByPredecessorID[predecessorID] ?? .solid,
                    nodesByColumn: nodesByColumn,
                    edgePiecesByColumn: &edgePiecesByColumn
                )
            }
        }

        return edgePiecesByColumn
    }

    private static func appendOverviewEdgePieces(
        from predecessor: TraceViewerGraph.OverviewGraphNode,
        to node: TraceViewerGraph.OverviewGraphNode,
        lineKind: TraceViewer.EdgeLineKind,
        nodesByColumn: [Int: [TraceViewerGraph.OverviewGraphNode]],
        edgePiecesByColumn: inout [Int: [TraceViewerGraph.OverviewEdgePiece]]
    ) {
        let edgeID = "\(predecessor.id)->\(node.id)"
        let columnCenterX = TraceViewerGraph.OverviewMetrics.columnWidth / 2

        if predecessor.column == node.column {
            edgePiecesByColumn[node.column, default: []].append(
                .init(
                    id: "\(edgeID):local",
                    predecessorID: predecessor.id,
                    nodeID: node.id,
                    lineKind: lineKind,
                    segment: .localCurve(startLane: predecessor.lane, endLane: node.lane)
                )
            )
            return
        }

        if predecessor.lane == node.lane {
            appendOverviewHorizontalSegments(
                edgeID: edgeID,
                predecessorID: predecessor.id,
                nodeID: node.id,
                column: predecessor.column,
                lane: predecessor.lane,
                baseRange: columnCenterX...TraceViewerGraph.OverviewMetrics.columnWidth,
                excludingNodeIDs: [predecessor.id],
                lineKind: lineKind,
                nodesByColumn: nodesByColumn,
                edgePiecesByColumn: &edgePiecesByColumn
            )

            if predecessor.column + 1 < node.column {
                for column in (predecessor.column + 1)..<node.column {
                    appendOverviewHorizontalSegments(
                        edgeID: edgeID,
                        predecessorID: predecessor.id,
                        nodeID: node.id,
                        column: column,
                        lane: node.lane,
                        baseRange: 0...TraceViewerGraph.OverviewMetrics.columnWidth,
                        excludingNodeIDs: [],
                        lineKind: lineKind,
                        nodesByColumn: nodesByColumn,
                        edgePiecesByColumn: &edgePiecesByColumn
                    )
                }
            }

            appendOverviewHorizontalSegments(
                edgeID: edgeID,
                predecessorID: predecessor.id,
                nodeID: node.id,
                column: node.column,
                lane: node.lane,
                baseRange: 0...columnCenterX,
                excludingNodeIDs: [node.id],
                lineKind: lineKind,
                nodesByColumn: nodesByColumn,
                edgePiecesByColumn: &edgePiecesByColumn
            )
            return
        }

        if predecessor.lane < node.lane {
            edgePiecesByColumn[predecessor.column, default: []].append(
                .init(
                    id: "\(edgeID):source-curve",
                    predecessorID: predecessor.id,
                    nodeID: node.id,
                    lineKind: lineKind,
                    segment: .sourceCurve(startLane: predecessor.lane, endLane: node.lane)
                )
            )

            if predecessor.column + 1 < node.column {
                for column in (predecessor.column + 1)..<node.column {
                    appendOverviewHorizontalSegments(
                        edgeID: edgeID,
                        predecessorID: predecessor.id,
                        nodeID: node.id,
                        column: column,
                        lane: node.lane,
                        baseRange: 0...TraceViewerGraph.OverviewMetrics.columnWidth,
                        excludingNodeIDs: [],
                        lineKind: lineKind,
                        nodesByColumn: nodesByColumn,
                        edgePiecesByColumn: &edgePiecesByColumn
                    )
                }
            }

            appendOverviewHorizontalSegments(
                edgeID: edgeID,
                predecessorID: predecessor.id,
                nodeID: node.id,
                column: node.column,
                lane: node.lane,
                baseRange: 0...columnCenterX,
                excludingNodeIDs: [node.id],
                lineKind: lineKind,
                nodesByColumn: nodesByColumn,
                edgePiecesByColumn: &edgePiecesByColumn
            )
            return
        }

        appendOverviewHorizontalSegments(
            edgeID: edgeID,
            predecessorID: predecessor.id,
            nodeID: node.id,
            column: predecessor.column,
            lane: predecessor.lane,
            baseRange: columnCenterX...TraceViewerGraph.OverviewMetrics.columnWidth,
            excludingNodeIDs: [predecessor.id],
            lineKind: lineKind,
            nodesByColumn: nodesByColumn,
            edgePiecesByColumn: &edgePiecesByColumn
        )

        if predecessor.column + 1 < node.column {
            for column in (predecessor.column + 1)..<node.column {
                appendOverviewHorizontalSegments(
                    edgeID: edgeID,
                    predecessorID: predecessor.id,
                    nodeID: node.id,
                    column: column,
                    lane: predecessor.lane,
                    baseRange: 0...TraceViewerGraph.OverviewMetrics.columnWidth,
                    excludingNodeIDs: [],
                    lineKind: lineKind,
                    nodesByColumn: nodesByColumn,
                    edgePiecesByColumn: &edgePiecesByColumn
                )
            }
        }

        edgePiecesByColumn[node.column, default: []].append(
            .init(
                id: "\(edgeID):target-curve",
                predecessorID: predecessor.id,
                nodeID: node.id,
                lineKind: lineKind,
                segment: .targetCurve(startLane: predecessor.lane, endLane: node.lane)
            )
        )
    }

    private static func appendOverviewHorizontalSegments(
        edgeID: String,
        predecessorID: String,
        nodeID: String,
        column: Int,
        lane: Int,
        baseRange: ClosedRange<CGFloat>,
        excludingNodeIDs: Set<String>,
        lineKind: TraceViewer.EdgeLineKind,
        nodesByColumn: [Int: [TraceViewerGraph.OverviewGraphNode]],
        edgePiecesByColumn: inout [Int: [TraceViewerGraph.OverviewEdgePiece]]
    ) {
        let hasBlocker = (nodesByColumn[column] ?? []).contains { overviewNode in
            overviewNode.lane == lane && !excludingNodeIDs.contains(overviewNode.id)
        }

        let segments = overviewHorizontalSegments(in: baseRange, hasBlocker: hasBlocker)
        for (index, segment) in segments.enumerated() {
            edgePiecesByColumn[column, default: []].append(
                .init(
                    id: "\(edgeID):horizontal:\(column):\(index)",
                    predecessorID: predecessorID,
                    nodeID: nodeID,
                    lineKind: lineKind,
                    segment: .horizontal(
                        lane: lane,
                        startX: segment.lowerBound,
                        endX: segment.upperBound
                    )
                )
            )
        }
    }

    private static func overviewHorizontalSegments(
        in baseRange: ClosedRange<CGFloat>,
        hasBlocker: Bool
    ) -> [ClosedRange<CGFloat>] {
        guard hasBlocker else {
            return [baseRange]
        }

        let columnCenterX = TraceViewerGraph.OverviewMetrics.columnWidth / 2
        let blockerLower = max(columnCenterX - TraceViewerGraph.OverviewMetrics.blockerClearance, 0)
        let blockerUpper = min(
            columnCenterX + TraceViewerGraph.OverviewMetrics.blockerClearance,
            TraceViewerGraph.OverviewMetrics.columnWidth
        )
        let blockerRange = blockerLower...blockerUpper
        return splitOverviewSegment(segment: baseRange, removing: blockerRange)
            .filter { $0.upperBound - $0.lowerBound > 0.5 }
    }

    private static func splitOverviewSegment(
        segment: ClosedRange<CGFloat>,
        removing blockerRange: ClosedRange<CGFloat>
    ) -> [ClosedRange<CGFloat>] {
        if blockerRange.upperBound <= segment.lowerBound || blockerRange.lowerBound >= segment.upperBound {
            return [segment]
        }

        var result: [ClosedRange<CGFloat>] = []
        if blockerRange.lowerBound > segment.lowerBound {
            result.append(segment.lowerBound...min(blockerRange.lowerBound, segment.upperBound))
        }
        if blockerRange.upperBound < segment.upperBound {
            result.append(max(blockerRange.upperBound, segment.lowerBound)...segment.upperBound)
        }
        return result
    }
}
