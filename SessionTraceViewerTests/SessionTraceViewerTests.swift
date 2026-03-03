import Foundation
import XCTest
import ReducerArchitecture
@testable import SessionTraceViewer

private enum TestTraceFeature: StoreNamespace {
    typealias PublishedValue = Void

    struct StoreEnvironment {}

    enum MutatingAction {
        case increment
    }

    enum EffectAction {
        case none
    }

    struct StoreState {
        var count = 0
    }
}

private enum SyncScheduledEffectsFeature: StoreNamespace {
    typealias PublishedValue = Void

    struct StoreEnvironment {}

    enum MutatingAction {
        case scheduleEffects
    }

    enum EffectAction {
        case startAlpha
        case startBeta
    }

    struct StoreState {
        var startedEffects: [String] = []
    }
}

private extension TestTraceFeature {
    @MainActor
    static func store() -> Store {
        Store(.init(), env: .init())
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .increment:
            state.count += 1
            if state.count == 1 {
                return .action(.mutating(.increment))
            }
            return .none
        }
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        .none
    }
}

private extension SyncScheduledEffectsFeature {
    @MainActor
    static func store() -> Store {
        Store(.init(), env: .init())
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .scheduleEffects:
            return .actions([
                .effect(.startAlpha),
                .effect(.startBeta)
            ])
        }
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        switch action {
        case .startAlpha, .startBeta:
            return .asyncAction {
                try? await Task.sleep(for: .milliseconds(20))
                return .none
            }
        }
    }
}

@MainActor
final class SessionTraceViewerTests: XCTestCase {
    func testOverviewGraphKeepsStateNodesOnMainLane() throws {
        let state = try makeStateFromGeneratedTrace()

        let stateNodes = state.overviewGraphNodes.filter { $0.kind == .state }
        XCTAssertFalse(stateNodes.isEmpty)
        for node in stateNodes {
            XCTAssertEqual(node.lane, 0, "State node \(node.id) must stay on main lane")
        }
    }

    func testStateNodeTitlesUseInitialThenStateChange() throws {
        let state = try makeStateFromGeneratedTrace()
        let stateItems = state.itemsByID.values
            .filter { $0.kind == .state }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order { return lhs.id < rhs.id }
                return lhs.order < rhs.order
            }

        guard let firstState = stateItems.first else {
            throw XCTSkip("No state nodes found in generated trace.")
        }
        XCTAssertEqual(firstState.title, "Initial State")

        for item in stateItems.dropFirst() {
            XCTAssertEqual(item.title, "State Change")
        }
    }

    func testActionSubtitlesStartWithUserOrCode() throws {
        let state = try makeStateFromGeneratedTrace()
        let actionItems = state.itemsByID.values.compactMap { item -> (TraceViewer.TimelineItem, SessionGraph.ActionNode)? in
            guard case .action(let action) = item.node else { return nil }
            return (item, action)
        }

        var sawUser = false
        var sawCode = false
        for (item, action) in actionItems {
            switch action.source {
            case .user:
                sawUser = true
                XCTAssertTrue(item.subtitle.hasPrefix("USER •"), "Expected USER subtitle prefix for \(item.id).")
            case .action, .effect, .system:
                sawCode = true
                XCTAssertTrue(item.subtitle.hasPrefix("CODE •"), "Expected CODE subtitle prefix for \(item.id).")
            }
        }

        XCTAssertTrue(sawUser)
        XCTAssertTrue(sawCode)
    }

    func testActionSubtitlesUseExactStoredCase() throws {
        let state = try makeStateFromGeneratedTrace()
        let actionItems = state.itemsByID.values.compactMap { item -> (TraceViewer.TimelineItem, SessionGraph.ActionNode)? in
            guard case .action(let action) = item.node else { return nil }
            return (item, action)
        }

        for (item, action) in actionItems {
            let expectedDetail = exactCaseLabel(from: action.action)
            guard let expectedDetail else { continue }
            XCTAssertEqual(
                item.subtitleDetailLabel,
                expectedDetail,
                "Expected exact case label for \(item.id)."
            )
        }
    }

    func testStateValueRowsCarryComparisonValuesForChangedProperties() throws {
        let state = try makeStateFromGeneratedTrace()
        let stateItems = state.orderedIDs.compactMap { state.itemsByID[$0] }.filter { item in
            item.kind == .state
        }
        guard stateItems.count > 1 else {
            throw XCTSkip("Need at least two state items to compare values.")
        }

        let previousItem = stateItems[0]
        let currentItem = stateItems[1]
        guard let valueRows = InspectorFormatter.valueRows(
            for: currentItem,
            previousStateItem: previousItem
        ) else {
            XCTFail("Expected state item rows.")
            return
        }
        guard let countRow = valueRows.first(where: { $0.property == "count" }) else {
            throw XCTSkip("count property missing from state rows.")
        }

        XCTAssertTrue(countRow.isChanged)
        XCTAssertEqual(countRow.change?.oldValue, formattedStateValue(property: "count", in: previousItem))
        XCTAssertEqual(countRow.change?.newValue, formattedStateValue(property: "count", in: currentItem))
    }

    func testSelectEventKeepsTimelineAndGraphSelectionInSync() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let targetID = state.visibleIDs.dropFirst().first else {
            throw XCTSkip("Trace did not contain enough visible nodes for selection test.")
        }

        _ = TraceViewer.reduce(&state, .selectEvent(id: targetID))
        XCTAssertEqual(state.selectedID, targetID)
        XCTAssertEqual(state.selectedOverviewGraphNodeID, targetID)
    }

    func testSelectNextGraphNodeAdvancesToNextVisibleGraphNode() throws {
        var state = try makeStateFromGeneratedTrace()
        let visibleGraphNodes = state.visibleOverviewGraphNodes.compactMap(\.selectionTimelineID)
        guard visibleGraphNodes.count > 1 else {
            throw XCTSkip("Trace did not contain enough visible graph nodes for graph navigation test.")
        }

        _ = TraceViewer.reduce(&state, .selectNextGraphNode)

        XCTAssertEqual(state.selectedID, visibleGraphNodes[1])
        XCTAssertEqual(state.selectedOverviewGraphNodeID, visibleGraphNodes[1])
    }

    func testSelectPreviousGraphNodeMovesBackToPreviousVisibleGraphNode() throws {
        var state = try makeStateFromGeneratedTrace()
        let visibleGraphNodes = state.visibleOverviewGraphNodes.compactMap(\.selectionTimelineID)
        guard visibleGraphNodes.count > 2 else {
            throw XCTSkip("Trace did not contain enough visible graph nodes for graph navigation test.")
        }

        _ = TraceViewer.reduce(&state, .selectEvent(id: visibleGraphNodes[2]))
        _ = TraceViewer.reduce(&state, .selectPreviousGraphNode)

        XCTAssertEqual(state.selectedID, visibleGraphNodes[1])
        XCTAssertEqual(state.selectedOverviewGraphNodeID, visibleGraphNodes[1])
    }

    func testCollapseHidesDescendantsInTimelineAndOverview() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let collapsibleID = state.visibleIDs.first(where: { state.hasChildren($0) }) else {
            throw XCTSkip("Trace did not contain a collapsible node.")
        }

        let descendants = state.descendants(of: collapsibleID)
        guard !descendants.isEmpty else {
            throw XCTSkip("Collapsible node had no descendants.")
        }

        _ = TraceViewer.reduce(&state, .selectEvent(id: collapsibleID))
        _ = TraceViewer.reduce(&state, .collapseSelected)

        XCTAssertTrue(state.isCollapsed(collapsibleID))
        for descendantID in descendants {
            XCTAssertFalse(state.visibleIDs.contains(descendantID))
            XCTAssertFalse(state.visibleOverviewGraphNodes.contains(where: { $0.id == descendantID }))
        }
    }

    func testReplaceTraceCollectionPreservesSelectionAndCollapsedState() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let collapsibleID = state.visibleIDs.first(where: { state.hasChildren($0) }) else {
            throw XCTSkip("Trace did not contain a collapsible node.")
        }

        _ = TraceViewer.reduce(&state, .selectEvent(id: collapsibleID))
        _ = TraceViewer.reduce(&state, .collapseSelected)

        let traceCollection = state.traceCollection
        _ = TraceViewer.reduce(&state, .replaceTraceCollection(traceCollection))

        XCTAssertEqual(state.selectedID, collapsibleID)
        XCTAssertTrue(state.collapsedIDs.contains(collapsibleID))
    }

    func testSyncScheduledEffectActionsShareOverviewColumn() async throws {
        let state = try await makeStateFromSyncScheduledEffectsTrace()

        guard let alphaAction = overviewEffectActionNode(
            named: "startAlpha",
            in: state
        ), let betaAction = overviewEffectActionNode(
            named: "startBeta",
            in: state
        ) else {
            throw XCTSkip("Expected sync scheduled effect actions were not present in the overview graph.")
        }

        XCTAssertEqual(
            alphaAction.column,
            betaAction.column,
            "Sync-scheduled sibling effect actions should align vertically in the same overview column."
        )
    }

    func testSyncScheduledEffectActionsUseDistinctLanesBottomToTop() async throws {
        let state = try await makeStateFromSyncScheduledEffectsTrace()

        guard let alphaAction = overviewEffectActionNode(
            named: "startAlpha",
            in: state
        ), let betaAction = overviewEffectActionNode(
            named: "startBeta",
            in: state
        ) else {
            throw XCTSkip("Expected sync scheduled effect actions were not present in the overview graph.")
        }

        XCTAssertNotEqual(
            alphaAction.lane,
            betaAction.lane,
            "Sync-scheduled sibling effect actions should not share an overview lane."
        )
        XCTAssertLessThan(
            alphaAction.lane,
            betaAction.lane,
            "Sibling sync effect actions should stack bottom-to-top in batch order."
        )
    }

    func testRecordMeetingTimerEffectKeepsOneLaneForItsMutatingActions() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let startAction = state.itemsByID.values.first { item in
            guard case .action(let action) = item.node else { return false }
            return action.actionCase == "startOneSecondTimer" && action.kind == .effect
        }
        guard let startAction else {
            throw XCTSkip("startOneSecondTimer action not found in RecordMeeting trace.")
        }

        let startedEffectID = state.graph.edges.compactMap { edge -> String? in
            guard case .startedEffect(let started) = edge else { return nil }
            guard started.actionID.rawValue == startAction.id else { return nil }
            return started.effectID.rawValue
        }.first
        guard let startedEffectID else {
            throw XCTSkip("No started effect for startOneSecondTimer in RecordMeeting trace.")
        }

        guard let startLane = state.overviewGraphNodeByID[startAction.id]?.lane else {
            throw XCTSkip("No lane for startOneSecondTimer action.")
        }

        let timerMutatingActionIDs = state.itemsByID.values.compactMap { item -> String? in
            guard case .action(let action) = item.node else { return nil }
            guard action.actionCase == "incSecondsElapsed", action.kind == .mutating else { return nil }
            guard case .effect(let effectID) = action.source, effectID.rawValue == startedEffectID else { return nil }
            return action.id.rawValue
        }

        XCTAssertFalse(timerMutatingActionIDs.isEmpty)
        for actionID in timerMutatingActionIDs {
            XCTAssertEqual(
                state.overviewGraphNodeByID[actionID]?.lane,
                startLane,
                "Action \(actionID) should stay on lane \(startLane) for effect \(startedEffectID)"
            )
        }
    }

    func testRecordMeetingTimerEffectActionsStayConnectedWhenAppliedNodesAreCollapsed() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let actionByID: [String: SessionGraph.ActionNode] = Dictionary(
            uniqueKeysWithValues: state.itemsByID.values.compactMap { item in
                guard case .action(let action) = item.node else { return nil }
                return (action.id.rawValue, action)
            }
        )

        guard let startAction = actionByID.values.first(where: {
            $0.actionCase == "startOneSecondTimer" && $0.kind == .effect
        }) else {
            throw XCTSkip("startOneSecondTimer action not found in RecordMeeting trace.")
        }

        let startedEffectID = state.graph.edges.compactMap { edge -> String? in
            guard case .startedEffect(let started) = edge else { return nil }
            guard started.actionID.rawValue == startAction.id.rawValue else { return nil }
            return started.effectID.rawValue
        }.first
        guard let startedEffectID else {
            throw XCTSkip("No started effect for startOneSecondTimer in RecordMeeting trace.")
        }

        let timerActionIDs = actionByID.values
            .filter { action in
                if action.id.rawValue == startAction.id.rawValue { return true }
                guard case .effect(let effectID) = action.source else { return false }
                return effectID.rawValue == startedEffectID
            }
            .sorted { lhs, rhs in lhs.order < rhs.order }
            .map { $0.id.rawValue }

        guard timerActionIDs.count > 1 else {
            throw XCTSkip("Not enough timer actions to assert thread continuity.")
        }

        for (index, actionID) in timerActionIDs.enumerated() where index > 0 {
            let expectedPredecessorID = timerActionIDs[index - 1]
            let predecessors = state.overviewGraphNodeByID[actionID]?.predecessorIDs ?? []
            XCTAssertTrue(
                predecessors.contains(expectedPredecessorID),
                "Action \(actionID) should stay connected to previous timer action \(expectedPredecessorID)."
            )
        }
    }

    func testRecordMeetingOverlappingEffectsUseDifferentLanes() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let actionByID: [String: SessionGraph.ActionNode] = Dictionary(
            uniqueKeysWithValues: state.itemsByID.values.compactMap { item in
                guard case .action(let action) = item.node else { return nil }
                return (action.id.rawValue, action)
            }
        )
        let effectByID: [String: SessionGraph.EffectNode] = Dictionary(
            uniqueKeysWithValues: state.graph.nodes.compactMap { node in
                guard case .effect(let effect) = node else { return nil }
                return (effect.id.rawValue, effect)
            }
        )
        let actionByOrder: [String: Int] = Dictionary(
            uniqueKeysWithValues: actionByID.map { ($0.key, $0.value.order) }
        )
        let startedEffectByActionID: [String: String] = Dictionary(
            uniqueKeysWithValues: state.graph.edges.compactMap { edge in
                guard case .startedEffect(let started) = edge else { return nil }
                return (started.actionID.rawValue, started.effectID.rawValue)
            }
        )
        let emittedActionOrdersByEffectID: [String: [Int]] = Dictionary(
            grouping: state.graph.edges.compactMap { edge -> (String, Int)? in
                guard case .emittedAction(let emitted) = edge,
                      let order = actionByOrder[emitted.nodeID] else {
                    return nil
                }
                return (emitted.effectID.rawValue, order)
            },
            by: { $0.0 }
        )
        .mapValues { pairs in
            pairs.map(\.1)
        }

        guard let timerStartAction = actionByID.values.first(where: {
            $0.actionCase == "startOneSecondTimer" && $0.kind == .effect
        }) else {
            throw XCTSkip("startOneSecondTimer action not found in RecordMeeting trace.")
        }
        guard let transcriptStartAction = actionByID.values.first(where: {
            ($0.actionCase == "startTranscriptRecording" || $0.actionCase == "startTrasscriptRecording")
            && $0.kind == .effect
        }) else {
            throw XCTSkip("startTranscriptRecording action not found in RecordMeeting trace.")
        }

        guard let timerEffectID = startedEffectByActionID[timerStartAction.id.rawValue],
              let transcriptEffectID = startedEffectByActionID[transcriptStartAction.id.rawValue],
              let timerEffect = effectByID[timerEffectID],
              let transcriptEffect = effectByID[transcriptEffectID] else {
            throw XCTSkip("Required effect nodes not found in RecordMeeting trace.")
        }

        let timerStartOrder = timerEffect.order
        let timerEndOrder = max(emittedActionOrdersByEffectID[timerEffectID]?.max() ?? timerStartOrder, timerStartOrder)
        let transcriptStartOrder = transcriptEffect.order
        let transcriptEndOrder = max(emittedActionOrdersByEffectID[transcriptEffectID]?.max() ?? transcriptStartOrder, transcriptStartOrder)
        let overlap = timerStartOrder <= transcriptEndOrder && transcriptStartOrder <= timerEndOrder
        XCTAssertTrue(overlap, "Expected effects to overlap in time for lane separation check.")

        let timerLane = state.overviewGraphNodeByID[timerStartAction.id.rawValue]?.lane
            ?? state.overviewGraphNodeByID[timerEffectID]?.lane
        let transcriptLane = state.overviewGraphNodeByID[transcriptStartAction.id.rawValue]?.lane
            ?? state.overviewGraphNodeByID[transcriptEffectID]?.lane
        XCTAssertNotNil(timerLane)
        XCTAssertNotNil(transcriptLane)
        XCTAssertNotEqual(
            timerLane,
            transcriptLane,
            """
            Overlapping effects should not share a lane.
            timer action/effect: \(timerStartAction.id) / \(timerEffectID) order \(timerStartOrder)...\(timerEndOrder)
            transcript action/effect: \(transcriptStartAction.id) / \(transcriptEffectID) order \(transcriptStartOrder)...\(transcriptEndOrder)
            """
        )
    }

    func testRecordMeetingAdjacentEffectStartReusesLaneWhenFirstHasNoContinuations() throws {
        let state = try makeStateFromRecordMeetingTrace()
        let actions = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            return action
        }
        guard let prepareSoundPlayer = actions.first(where: {
            $0.actionCase == "prepareSoundPlayer" && $0.kind == .effect
        }) else {
            throw XCTSkip("prepareSoundPlayer action not found in RecordMeeting trace.")
        }
        guard let startOneSecondTimer = actions.first(where: {
            $0.actionCase == "startOneSecondTimer" && $0.kind == .effect
        }) else {
            throw XCTSkip("startOneSecondTimer action not found in RecordMeeting trace.")
        }

        let prepareLane = state.overviewGraphNodeByID[prepareSoundPlayer.id.rawValue]?.lane
        let timerLane = state.overviewGraphNodeByID[startOneSecondTimer.id.rawValue]?.lane
        XCTAssertNotNil(prepareLane)
        XCTAssertNotNil(timerLane)
        XCTAssertEqual(
            prepareLane,
            timerLane,
            "An adjacent effect with no continuation should not keep the lane occupied."
        )
    }

    func testRecordMeetingFirstMutationDoesNotUsePrepareSoundPlayerAsPredecessor() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let actions = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            return action
        }
        guard let prepareSoundPlayer = actions.first(where: {
            $0.actionCase == "prepareSoundPlayer" && $0.kind == .effect
        }) else {
            throw XCTSkip("prepareSoundPlayer action not found in RecordMeeting trace.")
        }

        guard let firstMutationAfterPrepare = actions
            .filter({ $0.kind == .mutating && $0.order > prepareSoundPlayer.order })
            .sorted(by: { $0.order < $1.order })
            .first else {
            throw XCTSkip("No mutation action found after prepareSoundPlayer.")
        }

        let predecessors = state.overviewGraphNodeByID[firstMutationAfterPrepare.id.rawValue]?.predecessorIDs ?? []
        XCTAssertFalse(
            predecessors.contains(prepareSoundPlayer.id.rawValue),
            """
            Mutation \(firstMutationAfterPrepare.id) should not be connected to prepareSoundPlayer \
            when causal source is elsewhere.
            """
        )
    }

    func testGeneratedTraceUserMutationHasStateInputAndStateResultEdges() throws {
        let state = try makeStateFromGeneratedTrace()

        let actions = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            return action
        }
        guard let firstMutationAction = actions
            .filter({ $0.kind == .mutating })
            .sorted(by: { $0.order < $1.order })
            .first else {
            throw XCTSkip("No mutating action found in generated trace.")
        }

        let mutationPredecessors = state.overviewGraphNodeByID[firstMutationAction.id.rawValue]?.predecessorIDs ?? []
        let stateNodeIDs = Set(
            state.overviewGraphNodes
                .filter { $0.kind == .state }
                .map(\.id)
        )

        XCTAssertTrue(
            mutationPredecessors.contains(where: { stateNodeIDs.contains($0) }),
            "Mutating action \(firstMutationAction.id) should have incoming edge from previous state."
        )

        let resultingStateNode = state.overviewGraphNodes.first { node in
            guard node.kind == .state else { return false }
            return node.predecessorIDs.contains(firstMutationAction.id.rawValue)
        }
        XCTAssertNotNil(
            resultingStateNode,
            "Mutating action \(firstMutationAction.id) should connect to a resulting state node."
        )
    }

    func testRecordMeetingShowEndMeetingAlertHasSingleThreadContinuationEdge() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let showAlertActions = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            guard action.actionCase == "showEndMeetingAlert" else { return nil }
            return action
        }
        .sorted { lhs, rhs in lhs.order < rhs.order }

        XCTAssertFalse(showAlertActions.isEmpty)
        for action in showAlertActions {
            let outgoingCount = state.overviewGraphNodes
                .filter { $0.predecessorIDs.contains(action.id.rawValue) }
                .count
            XCTAssertEqual(
                outgoingCount,
                1,
                "showEndMeetingAlert action \(action.id) should have one continuation edge in effect thread."
            )
        }
    }

    func testRecordMeetingShowAlertEffectActionsStayOnShowAlertLane() throws {
        let state = try makeStateFromRecordMeetingTrace()
        let actions = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            return action
        }
        .sorted { lhs, rhs in lhs.order < rhs.order }
        let startedEffectByActionID: [String: String] = Dictionary(
            uniqueKeysWithValues: state.graph.edges.compactMap { edge in
                guard case .startedEffect(let started) = edge else { return nil }
                return (started.actionID.rawValue, started.effectID.rawValue)
            }
        )

        guard let showEndMeetingAlert = actions
            .filter({ $0.actionCase == "showEndMeetingAlert" })
            .last else {
            throw XCTSkip("showEndMeetingAlert action not found in RecordMeeting trace.")
        }
        guard let effectID = startedEffectByActionID[showEndMeetingAlert.id.rawValue] else {
            throw XCTSkip("showEndMeetingAlert effect not found in RecordMeeting trace.")
        }
        let effectActions = actions.filter { action in
            guard case .effect(let sourceEffectID) = action.source else { return false }
            return sourceEffectID.rawValue == effectID
        }

        let showLane = state.overviewGraphNodeByID[showEndMeetingAlert.id.rawValue]?.lane
        XCTAssertNotNil(showLane)
        XCTAssertFalse(effectActions.isEmpty, "Expected showEndMeetingAlert effect to emit actions.")

        for effectAction in effectActions {
            let effectActionLane = state.overviewGraphNodeByID[effectAction.id.rawValue]?.lane
            XCTAssertNotNil(effectActionLane)
            XCTAssertEqual(
                effectActionLane,
                showLane,
                "\(effectAction.actionCase) should remain on the same lane as its showEndMeetingAlert sequence."
            )
        }
    }

    func testRecordMeetingHasAsyncDottedAndSyncSolidEdges() throws {
        let state = try makeStateFromRecordMeetingTrace()
        var solidCount = 0
        var dottedCount = 0

        for node in state.overviewGraphNodes {
            for predecessorID in node.predecessorIDs {
                let lineKind = node.edgeLineKindByPredecessorID[predecessorID] ?? .solid
                switch lineKind {
                case .solid:
                    solidCount += 1
                case .dotted:
                    dottedCount += 1
                }
            }
        }

        XCTAssertGreaterThan(
            solidCount,
            0,
            "Expected at least one solid edge for mutating/sync action flow."
        )
        XCTAssertGreaterThan(
            dottedCount,
            0,
            "Expected at least one dotted edge for async action flow."
        )
    }

    func testRecordMeetingShowAlertAsyncSequenceContinuationThroughPublishIsDotted() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let actionsByID: [String: SessionGraph.ActionNode] = Dictionary(
            uniqueKeysWithValues: state.itemsByID.values.compactMap { item in
                guard case .action(let action) = item.node else { return nil }
                return (action.id.rawValue, action)
            }
        )
        let startedEffectByActionID: [String: String] = Dictionary(
            uniqueKeysWithValues: state.graph.edges.compactMap { edge in
                guard case .startedEffect(let started) = edge else { return nil }
                return (started.actionID.rawValue, started.effectID.rawValue)
            }
        )

        guard let showAlertAction = actionsByID.values
            .filter({ $0.actionCase == "showEndMeetingAlert" })
            .sorted(by: { $0.order < $1.order })
            .first else {
            throw XCTSkip("showEndMeetingAlert action not found in RecordMeeting trace.")
        }
        guard let effectID = startedEffectByActionID[showAlertAction.id.rawValue] else {
            throw XCTSkip("No started effect for showEndMeetingAlert.")
        }

        let effectActions = actionsByID.values
            .filter { action in
                guard case .effect(let sourceEffectID) = action.source else { return false }
                return sourceEffectID.rawValue == effectID
            }
            .sorted(by: { $0.order < $1.order })

        let updates = effectActions
            .filter { action in
                action.actionCase == "updateIgnoreTimer"
            }

        guard updates.count >= 2 else {
            throw XCTSkip("Not enough updateIgnoreTimer actions for async continuation test.")
        }
        guard let publish = effectActions.first(where: { $0.actionCase == "publish" }) else {
            throw XCTSkip("Publish action not found in showEndMeetingAlert effect.")
        }

        let firstUpdate = updates[0]
        let secondUpdate = updates[1]
        guard let secondNode = state.overviewGraphNodeByID[secondUpdate.id.rawValue] else {
            throw XCTSkip("Second update node not found in overview graph.")
        }
        XCTAssertTrue(
            publish.order > firstUpdate.order && publish.order < secondUpdate.order,
            "Publish should occur between the two updateIgnoreTimer actions in the async sequence."
        )
        XCTAssertEqual(
            secondNode.predecessorIDs,
            [publish.id.rawValue],
            "Expected second updateIgnoreTimer to continue from publish, the previous emitted node in the async sequence."
        )
        XCTAssertEqual(
            secondNode.edgeLineKindByPredecessorID[publish.id.rawValue],
            .dotted,
            "Continuation edge inside async sequence should be dotted."
        )
    }

    func testRecordMeetingEffectSourcedMutationsDoNotUseInputStateAsDirectPredecessor() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let inputStateByMutatingActionID = state.graph.edges.reduce(into: [String: String]()) {
            partialResult,
            edge in
            guard case .stateInput(let stateInput) = edge else { return }
            partialResult[stateInput.actionID.rawValue] = stateInput.stateID.rawValue
        }

        let effectSourcedMutations = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            guard action.kind == .mutating else { return nil }
            guard case .effect = action.source else { return nil }
            return action
        }
        .sorted(by: { $0.order < $1.order })

        XCTAssertFalse(effectSourcedMutations.isEmpty)

        for action in effectSourcedMutations {
            guard let inputStateID = inputStateByMutatingActionID[action.id.rawValue] else {
                XCTFail("Missing input state edge for effect-sourced mutation \(action.id).")
                continue
            }
            guard let overviewNode = state.overviewGraphNodeByID[action.id.rawValue] else {
                XCTFail("Overview graph node for \(action.id) not found.")
                continue
            }

            XCTAssertFalse(
                overviewNode.predecessorIDs.contains(inputStateID),
                """
                Effect-sourced mutation \(action.id) should not include its input state as a direct predecessor \
                when the overview graph already has a causal continuation source.
                """
            )
        }
    }

    func testRecordMeetingUserMutationHasOnlyStatePredecessor() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let userMutations = state.itemsByID.values
            .compactMap { item -> SessionGraph.ActionNode? in
                guard case .action(let action) = item.node else { return nil }
                guard action.kind == .mutating else { return nil }
                guard case .user = action.source else { return nil }
                return action
            }
            .sorted(by: { $0.order < $1.order })
        guard let firstUserMutation = userMutations.first else {
            throw XCTSkip("No user-origin mutation actions found in RecordMeeting trace.")
        }

        guard let mutationNode = state.overviewGraphNodeByID[firstUserMutation.id.rawValue] else {
            throw XCTSkip("Overview node for user-origin mutation not found.")
        }
        XCTAssertEqual(
            mutationNode.predecessorIDs.count,
            1,
            "User-origin mutation should not receive extra synthetic thread predecessors."
        )
        guard let onlyPredecessorID = mutationNode.predecessorIDs.first,
              let onlyPredecessor = state.itemsByID[onlyPredecessorID] else {
            throw XCTSkip("Expected single predecessor for user-origin mutation.")
        }
        XCTAssertEqual(
            onlyPredecessor.kind,
            .state,
            "User-origin mutation predecessor should be the input store state."
        )
    }

    func testRecordMeetingEffectSourcedActionsHaveAtMostOneIncomingEdge() throws {
        let state = try makeStateFromRecordMeetingTrace()
        let effectSourcedActions = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            guard case .effect = action.source else { return nil }
            return action
        }
        XCTAssertFalse(effectSourcedActions.isEmpty)
        for action in effectSourcedActions {
            let predecessorCount = state.overviewGraphNodeByID[action.id.rawValue]?.predecessorIDs.count ?? 0
            XCTAssertLessThanOrEqual(
                predecessorCount,
                1,
                "Effect-sourced action \(action.id) should not receive duplicate incoming edges."
            )
        }
    }

    func testRecordMeetingUserMutationDoesNotShareActiveEffectLane() throws {
        let state = try makeStateFromRecordMeetingTrace()

        guard let order23 = state.itemsByID.values.first(where: { $0.order == 23 }),
              let order30 = state.itemsByID.values.first(where: { $0.order == 30 }) else {
            throw XCTSkip("Expected #23 and #30 nodes not found in RecordMeeting trace.")
        }
        guard let lane23 = state.overviewGraphNodeByID[order23.id]?.lane,
              let lane30 = state.overviewGraphNodeByID[order30.id]?.lane else {
            throw XCTSkip("Overview lanes for #23/#30 not found.")
        }

        XCTAssertNotEqual(
            lane30,
            lane23,
            "A user-origin action (#30) should not occupy an active async effect lane (#23)."
        )
    }

    func testStringDiffGroupsSeparatedLineChangesIntoSeparateHunks() throws {
        let state = StringDiff.StoreState(
            title: "Diff",
            presentationStyle: .standard,
            string1Caption: "Old Value",
            string1: "alpha\nbeta\ngamma\ndelta",
            string2Caption: "New Value",
            string2: "alpha\nBETA\ngamma\nDELTA"
        )
        let sections = try XCTUnwrap(state.diffSections.value)

        XCTAssertEqual(state.diffHunks.count, 2)
        XCTAssertEqual(state.diffHunks.map(\.oldRangeLabel), ["L2", "L4"])
        XCTAssertEqual(state.diffHunks.map(\.newRangeLabel), ["L2", "L4"])
        XCTAssertEqual(sections.count, 4)
    }

    func testStringDiffKeepsUnchangedLinesAsContextSections() throws {
        let state = StringDiff.StoreState(
            title: "Diff",
            presentationStyle: .standard,
            string1Caption: "Old Value",
            string1: "alpha\nbeta\ngamma\ndelta",
            string2Caption: "New Value",
            string2: "alpha\nBETA\ngamma\nDELTA"
        )
        let sections = try XCTUnwrap(state.diffSections.value)

        XCTAssertEqual(sections.count, 4)
        XCTAssertFalse(sections[0].isDiff)
        XCTAssertTrue(sections[1].isDiff)
        XCTAssertFalse(sections[2].isDiff)
        XCTAssertTrue(sections[3].isDiff)
        XCTAssertEqual(sections[0].rows[0].oldLine?.lineNumber, 1)
        XCTAssertEqual(sections[0].rows[0].newLine?.lineNumber, 1)
        XCTAssertEqual(sections[2].rows[0].oldLine?.lineNumber, 3)
        XCTAssertEqual(sections[2].rows[0].newLine?.lineNumber, 3)
    }

    func testStringDiffUsesEmptyOldRangeForPureInsertionHunk() {
        let state = StringDiff.StoreState(
            title: "Diff",
            presentationStyle: .standard,
            string1Caption: "Old Value",
            string1: "one\nthree",
            string2Caption: "New Value",
            string2: "one\ntwo\nthree"
        )

        XCTAssertEqual(state.diffHunks.count, 1)
        XCTAssertEqual(state.diffHunks[0].oldRangeLabel, "No lines")
        XCTAssertEqual(state.diffHunks[0].newRangeLabel, "L2")
        XCTAssertNil(state.diffHunks[0].rows[0].oldLine)
        XCTAssertEqual(state.diffHunks[0].rows[0].newLine?.lineNumber, 2)
    }

    func testStringDiffKeepsWholeDocumentAsContextWhenThereAreNoChanges() throws {
        let state = StringDiff.StoreState(
            title: "Diff",
            presentationStyle: .standard,
            string1Caption: "Old Value",
            string1: "one\ntwo",
            string2Caption: "New Value",
            string2: "one\ntwo"
        )
        let sections = try XCTUnwrap(state.diffSections.value)

        XCTAssertTrue(state.diffHunks.isEmpty)
        XCTAssertEqual(sections.count, 1)
        XCTAssertFalse(sections[0].isDiff)
        XCTAssertEqual(sections[0].rows.map(\.id).count, 2)
    }

    func testStringDiffSelectsFirstDiffByDefault() {
        let state = StringDiff.StoreState(
            title: "Diff",
            presentationStyle: .standard,
            string1Caption: "Old Value",
            string1: "alpha\nbeta\ngamma\ndelta",
            string2Caption: "New Value",
            string2: "alpha\nBETA\ngamma\nDELTA"
        )

        XCTAssertEqual(state.selectedDiffIndex, 0)
        XCTAssertEqual(state.selectedDiffID, state.diffHunks[0].id)
        XCTAssertTrue(state.previousDiffDisabled)
        XCTAssertFalse(state.nextDiffDisabled)
    }

    func testStringDiffSelectionActionsUpdateStoreState() {
        var state = StringDiff.StoreState(
            title: "Diff",
            presentationStyle: .standard,
            string1Caption: "Old Value",
            string1: "alpha\nbeta\ngamma\ndelta",
            string2Caption: "New Value",
            string2: "alpha\nBETA\ngamma\nDELTA"
        )

        _ = StringDiff.reduce(&state, .selectNextDiff)
        XCTAssertEqual(state.selectedDiffIndex, 1)
        XCTAssertEqual(state.selectedDiffID, state.diffHunks[1].id)
        XCTAssertFalse(state.previousDiffDisabled)
        XCTAssertTrue(state.nextDiffDisabled)

        _ = StringDiff.reduce(&state, .selectPreviousDiff)
        XCTAssertEqual(state.selectedDiffIndex, 0)
        XCTAssertEqual(state.selectedDiffID, state.diffHunks[0].id)

        _ = StringDiff.reduce(&state, .selectDiff(id: state.diffHunks[1].id))
        XCTAssertEqual(state.selectedDiffIndex, 1)
        XCTAssertEqual(state.selectedDiffID, state.diffHunks[1].id)
    }

    func testStringDiffStoreLoadsSectionsAsynchronouslyFromInput() async {
        let store = StringDiff.windowStore(
            input: .init(
                title: "Diff",
                string1Caption: "Old Value",
                string1: "one\ntwo\nthree",
                string2Caption: "New Value",
                string2: "one\nTWO\nthree"
            )
        )
        store.environment = .init(
            makeDiffSections: { string1, string2 in
                return StringDiff.StoreState.makeSections(string1: string1, string2: string2)
            }
        )

        if case .notStarted = store.state.diffSections {
        }
        else {
            XCTFail("Expected diff task to start in .notStarted state.")
        }
        XCTAssertNil(store.state.diffSections.value)

        let task = store.send(.mutating(.startLoadingIfNeeded))

        if case .inProgress = store.state.diffSections {
        }
        else {
            XCTFail("Expected diff task to move to .inProgress state.")
        }
        XCTAssertNil(store.state.diffSections.value)

        await task?.value

        if case .success(let sections) = store.state.diffSections {
            XCTAssertEqual(sections.count, 3)
        }
        else {
            XCTFail("Expected diff task to finish in .success state.")
        }
        XCTAssertEqual(store.state.diffSections.value?.count, 3)
        XCTAssertEqual(store.state.diffHunks.count, 1)
        XCTAssertEqual(store.state.diffHunks[0].oldRangeLabel, "L2")
        XCTAssertEqual(store.state.diffHunks[0].newRangeLabel, "L2")
        XCTAssertEqual(store.state.selectedDiffIndex, 0)
        XCTAssertEqual(store.state.selectedDiffID, store.state.diffHunks[0].id)
    }

    private func makeStateFromGeneratedTrace() throws -> TraceViewer.StoreState {
        let name = "SessionTraceViewerTests-\(UUID().uuidString)"
        let store = TestTraceFeature.store()
        store.logConfig.sessionTraceFilename = name

        store.send(.mutating(.increment))
        store.saveSessionTraceIfNeeded()

        let traceURL = try savedTraceURL(named: name)
        defer { try? FileManager.default.removeItem(at: traceURL) }

        let data = try Data(contentsOf: traceURL)
        let collection = try SessionTraceCollection(fileData: data)
        return TraceViewer.StoreState(traceCollection: collection)
    }

    private func makeStateFromSyncScheduledEffectsTrace() async throws -> TraceViewer.StoreState {
        let name = "SessionTraceViewerSyncEffects-\(UUID().uuidString)"
        let store = SyncScheduledEffectsFeature.store()
        store.logConfig.sessionTraceFilename = name

        let task = store.send(.mutating(.scheduleEffects))
        await task?.value
        store.saveSessionTraceIfNeeded()

        let traceURL = try savedTraceURL(named: name)
        defer { try? FileManager.default.removeItem(at: traceURL) }

        let data = try Data(contentsOf: traceURL)
        let collection = try SessionTraceCollection(fileData: data)
        return TraceViewer.StoreState(traceCollection: collection)
    }

    private func makeStateFromRecordMeetingTrace() throws -> TraceViewer.StoreState {
        let traceURL = URL(fileURLWithPath: "/Users/ilya/Development/RecordMeeting.lzma")
        let data = try Data(contentsOf: traceURL)
        let collection = try SessionTraceCollection(fileData: data)
        return TraceViewer.StoreState(traceCollection: collection)
    }

    private func savedTraceURL(named name: String) throws -> URL {
        let fileManager = FileManager.default
        let cachesURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let logsURL = cachesURL.appendingPathComponent("ReducerLogs")
        let files = try fileManager.contentsOfDirectory(
            at: logsURL,
            includingPropertiesForKeys: nil
        )
        guard let url = files.first(where: { file in
            let stem = file.deletingPathExtension().lastPathComponent
            return stem == name
        }) else {
            throw NSError(
                domain: "SessionTraceViewerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Saved trace '\(name)' not found in \(logsURL.path)"]
            )
        }
        return url
    }

    private func exactCaseLabel(from code: String?) -> String? {
        guard let code, !code.isEmpty, code != "nil" else { return nil }
        guard code.first == "." else { return code }

        var label = "."
        for character in code.dropFirst() {
            guard character.isLetter || character.isNumber || character == "_" else {
                break
            }
            label.append(character)
        }
        return label.count > 1 ? label : nil
    }

    private func overviewEffectActionNode(
        named actionCase: String,
        in state: TraceViewer.StoreState
    ) -> TraceViewer.StoreState.OverviewGraphNode? {
        state.overviewGraphNodes.first { node in
            guard let item = state.itemsByID[node.id],
                  case .action(let action) = item.node else {
                return false
            }
            return action.actionCase == actionCase && action.kind == .effect
        }
    }

    private func formattedStateValue(property: String, in item: TraceViewer.TimelineItem) -> String? {
        guard case .state(let stateNode) = item.node else { return nil }
        return stateNode.state
            .first(where: { $0.property == property })?
            .value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }
}
