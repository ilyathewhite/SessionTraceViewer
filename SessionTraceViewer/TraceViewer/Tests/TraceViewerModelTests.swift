import XCTest
import ReducerArchitecture
import Testing
@testable import SessionTraceViewer

extension ModelTests {
    @MainActor
    @Suite struct TraceViewerModelTests {}
}

extension ModelTests.TraceViewerModelTests {
    @Test
    func testOverviewGraphKeepsStateNodesOnMainLane() throws {
        let state = try makeStateFromGeneratedTrace()

        let stateNodes = state.overviewGraphNodes.filter { $0.kind == .state }
        XCTAssertFalse(stateNodes.isEmpty)
        for node in stateNodes {
            XCTAssertEqual(node.lane, 0, "State node \(node.id) must stay on main lane")
        }
    }

    @Test
    func testStateNodeTitlesUseInitialThenStateChange() throws {
        let state = try makeStateFromGeneratedTrace()
        let stateItems = state.itemsByID.values
            .filter { $0.kind == .state }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order { return lhs.id < rhs.id }
                return lhs.order < rhs.order
            }

        guard let firstState = stateItems.first else {
            XCTFail("No state nodes found in generated trace.")
            return
        }
        XCTAssertEqual(firstState.title, "Initial State")

        for item in stateItems.dropFirst() {
            XCTAssertEqual(item.title, "State Change")
        }
    }

    @Test
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

    @Test
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

    @Test
    func testPublishAndCancelActionsUseFlowKind() throws {
        let state = try makeStateFromRecordMeetingTrace()
        let flowItems = state.itemsByID.values.compactMap { item -> TraceViewer.TimelineItem? in
            guard case .action(let action) = item.node else { return nil }
            guard action.kind == .publish || action.kind == .cancel else { return nil }
            return item
        }

        guard !flowItems.isEmpty else {
            XCTFail("No publish/cancel actions found in record meeting trace.")
            return
        }

        for item in flowItems {
            XCTAssertEqual(item.kind, .flow, "Publish/cancel actions should be labeled FLOW.")
        }
    }

    @Test
    func testStateValueRowsCarryComparisonValuesForChangedProperties() throws {
        let state = try makeStateFromGeneratedTrace()
        let stateItems = state.orderedIDs.compactMap { state.itemsByID[$0] }.filter { item in
            item.kind == .state
        }
        guard stateItems.count > 1 else {
            XCTFail("Need at least two state items to compare values.")
            return
        }

        let previousItem = stateItems[0]
        let currentItem = stateItems[1]
        guard let valueRows = EventInspectorFormatter.valueRows(
            for: currentItem,
            previousStateItem: previousItem
        ) else {
            XCTFail("Expected state item rows.")
            return
        }
        guard let countRow = valueRows.first(where: { $0.property == "count" }) else {
            XCTFail("count property missing from state rows.")
            return
        }

        XCTAssertTrue(countRow.isChanged)
        XCTAssertEqual(countRow.change?.oldValue, formattedStateValue(property: "count", in: previousItem))
        XCTAssertEqual(countRow.change?.newValue, formattedStateValue(property: "count", in: currentItem))
    }

    @Test
    func testSelectEventKeepsTimelineAndGraphSelectionInSync() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let targetID = state.visibleIDs.dropFirst().first else {
            XCTFail("Trace did not contain enough visible nodes for selection test.")
            return
        }

        _ = TraceViewerList.reduce(&state, .selectEvent(id: targetID, shouldFocus: false))
        XCTAssertEqual(state.selectedID, targetID)
        XCTAssertEqual(state.selectedOverviewGraphNodeID, targetID)
    }

    @Test
    func testSelectEventEmitsFocusResetAndScrollEffectWhenSelectionChanges() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let targetID = state.visibleIDs.dropFirst().first else {
            XCTFail("Trace did not contain enough visible nodes for selection effect test.")
            return
        }

        let effect = TraceViewerList.reduce(&state, .selectEvent(id: targetID, shouldFocus: true))

        XCTAssertTrue(containsResetTimelineListFocusAction(in: effect))
        XCTAssertEqual(scrolledTimelineID(in: effect), targetID)
    }

    @Test
    func testSelectEventDoesNotEmitScrollEffectWhenSelectionIsUnchanged() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let selectedID = state.selectedID else {
            XCTFail("Trace did not contain an initial selection.")
            return
        }

        let effect = TraceViewerList.reduce(&state, .selectEvent(id: selectedID, shouldFocus: true))

        XCTAssertTrue(containsResetTimelineListFocusAction(in: effect))
        XCTAssertNil(scrolledTimelineID(in: effect))
    }

    @Test
    func testSelectEventWithoutFocusRequestDoesNotEmitFocusReset() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let targetID = state.visibleIDs.dropFirst().first else {
            XCTFail("Trace did not contain enough visible nodes for selection effect test.")
            return
        }

        let effect = TraceViewerList.reduce(&state, .selectEvent(id: targetID, shouldFocus: false))

        XCTAssertFalse(containsResetTimelineListFocusAction(in: effect))
        XCTAssertEqual(scrolledTimelineID(in: effect), targetID)
    }

    @Test
    func testSelectNextGraphNodeAdvancesToNextVisibleGraphNode() throws {
        let state = try makeStateFromGeneratedTrace()
        let visibleGraphNodes = state.visibleOverviewGraphNodes.compactMap(\.selectionTimelineID)
        guard visibleGraphNodes.count > 1 else {
            XCTFail("Trace did not contain enough visible graph nodes for graph navigation test.")
            return
        }

        var graphState = state.graphState
        let effect = TraceViewerGraph.reduce(
            &graphState,
            .selectAdjacentNode(offset: 1, shouldFocusTimelineList: false)
        )

        XCTAssertEqual(
            publishedGraphSelection(in: effect),
            .init(timelineID: visibleGraphNodes[1], shouldFocusTimelineList: false)
        )
        XCTAssertEqual(
            graphState.presentation.selectedNodeID,
            state.selectableVisibleOverviewGraphNodeIDs[1]
        )
    }

    @Test
    func testSelectPreviousGraphNodeMovesBackToPreviousVisibleGraphNode() throws {
        var state = try makeStateFromGeneratedTrace()
        let visibleGraphNodes = state.visibleOverviewGraphNodes.compactMap(\.selectionTimelineID)
        guard visibleGraphNodes.count > 2 else {
            XCTFail("Trace did not contain enough visible graph nodes for graph navigation test.")
            return
        }

        _ = TraceViewerList.reduce(&state, .selectEvent(id: visibleGraphNodes[2], shouldFocus: false))
        var graphState = state.graphState
        let effect = TraceViewerGraph.reduce(
            &graphState,
            .selectAdjacentNode(offset: -1, shouldFocusTimelineList: false)
        )

        XCTAssertEqual(
            publishedGraphSelection(in: effect),
            .init(timelineID: visibleGraphNodes[1], shouldFocusTimelineList: false)
        )
        XCTAssertEqual(
            graphState.presentation.selectedNodeID,
            state.selectableVisibleOverviewGraphNodeIDs[1]
        )
    }

    @Test
    func testToggleEventKindFilterKeepsTimelineAndOverviewVisible() throws {
        var state = try makeStateFromGeneratedTrace()
        let visibleIDs = state.visibleIDs
        let visibleGraphNodeIDs = state.visibleOverviewGraphNodes.map(\.id)
        guard state.visibleItems.contains(where: { $0.kind == .mutation }) else {
            XCTFail("Trace did not contain mutation rows for filter coverage.")
            return
        }

        _ = TraceViewerList.reduce(&state, .toggleEventKindFilter(.state))

        XCTAssertFalse(state.isAllEventKindsSelected)
        XCTAssertTrue(state.isEventKindSelected(.state))
        XCTAssertEqual(state.visibleIDs, visibleIDs)
        XCTAssertEqual(state.visibleOverviewGraphNodes.map(\.id), visibleGraphNodeIDs)
        XCTAssertTrue(state.selectableVisibleIDs.allSatisfy { id in
            state.itemsByID[id]?.kind == .state
        })
    }

    @Test
    func testToggleUserEventFilterKeepsOnlyUserSourcedItemsSelectable() throws {
        var state = try makeStateFromGeneratedTrace()
        let visibleIDs = state.visibleIDs
        let visibleGraphNodeIDs = state.visibleOverviewGraphNodes.map(\.id)
        guard state.visibleItems.contains(where: { $0.isUserSourceEvent }),
              state.visibleItems.contains(where: { $0.subtitleSourceLabel == "CODE" }) else {
            XCTFail("Trace did not contain both USER and CODE sourced rows.")
            return
        }

        _ = TraceViewerList.reduce(&state, .toggleUserEventFilter)

        XCTAssertFalse(state.isAllEventKindsSelected)
        XCTAssertTrue(state.isUserEventFilterSelected)
        XCTAssertEqual(state.visibleIDs, visibleIDs)
        XCTAssertEqual(state.visibleOverviewGraphNodes.map(\.id), visibleGraphNodeIDs)
        XCTAssertTrue(state.selectableVisibleIDs.allSatisfy { id in
            state.itemsByID[id]?.isUserSourceEvent == true
        })
    }

    @Test
    func testFilterChangeSelectsFirstSelectableRowWhenCurrentSelectionIsFilteredOut() throws {
        var state = try makeStateFromGeneratedTrace()
        let stateIDs = state.visibleItems
            .filter { $0.kind == .state }
            .map(\.id)
        guard stateIDs.count > 1,
              let lastMutationID = state.visibleItems.last(where: { $0.kind == .mutation })?.id else {
            XCTFail("Trace did not contain enough state rows and mutation rows for selection fallback coverage.")
            return
        }

        _ = TraceViewerList.reduce(&state, .selectEvent(id: lastMutationID, shouldFocus: false))
        _ = TraceViewerList.reduce(&state, .toggleEventKindFilter(.state))

        XCTAssertEqual(state.selectedID, stateIDs.first)
    }

    @Test
    func testSelectEventOnFilteredItemRestoresAllAndSelectsIt() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let stateID = state.visibleItems.first(where: { $0.kind == .state })?.id,
              let mutationID = state.visibleItems.first(where: { $0.kind == .mutation })?.id else {
            XCTFail("Trace did not contain both state and mutation rows.")
            return
        }

        _ = TraceViewerList.reduce(&state, .toggleEventKindFilter(.state))
        _ = TraceViewerList.reduce(&state, .selectEvent(id: stateID, shouldFocus: false))
        _ = TraceViewerList.reduce(&state, .selectEvent(id: mutationID, shouldFocus: false))

        XCTAssertEqual(state.selectedID, mutationID)
        XCTAssertTrue(state.isAllEventKindsSelected)
    }

    @Test
    func testSelectAllEventKindsRestoresExclusiveAllSelection() throws {
        var state = try makeStateFromGeneratedTrace()

        _ = TraceViewerList.reduce(&state, .toggleEventKindFilter(.state))
        _ = TraceViewerList.reduce(&state, .selectAllEventKinds)

        XCTAssertTrue(state.isAllEventKindsSelected)
        XCTAssertEqual(state.selectableVisibleIDs, state.visibleIDs)
    }

    @Test
    func testSelectNextVisibleSkipsFilteredItems() throws {
        var state = try makeStateFromGeneratedTrace()
        let stateIDs = state.visibleItems
            .filter { $0.kind == .state }
            .map(\.id)
        guard stateIDs.count > 1 else {
            XCTFail("Trace did not contain enough state rows for filtered navigation.")
            return
        }

        _ = TraceViewerList.reduce(&state, .toggleEventKindFilter(.state))
        _ = TraceViewerList.reduce(&state, .selectEvent(id: stateIDs[0], shouldFocus: false))
        _ = TraceViewerList.reduce(&state, .selectNextVisible)

        XCTAssertEqual(state.selectedID, stateIDs[1])
    }

    @Test
    func testSelectNextGraphNodeSkipsFilteredItems() throws {
        var state = try makeStateFromGeneratedTrace()
        let stateGraphNodeIDs = state.visibleOverviewGraphNodes
            .compactMap(\.selectionTimelineID)
            .filter { id in
                state.itemsByID[id]?.kind == .state
            }
        guard stateGraphNodeIDs.count > 1 else {
            XCTFail("Trace did not contain enough state graph nodes for filtered graph navigation.")
            return
        }

        _ = TraceViewerList.reduce(&state, .toggleEventKindFilter(.state))
        var graphState = state.graphState
        let effect = TraceViewerGraph.reduce(
            &graphState,
            .selectAdjacentNode(offset: 1, shouldFocusTimelineList: true)
        )

        XCTAssertEqual(
            publishedGraphSelection(in: effect),
            .init(timelineID: stateGraphNodeIDs[1], shouldFocusTimelineList: true)
        )
        XCTAssertEqual(
            graphState.presentation.selectedNodeID,
            state.selectableVisibleOverviewGraphNodeIDs[1]
        )
    }

    @Test
    func testCollapseHidesDescendantsInTimelineAndOverview() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let collapsibleID = state.visibleIDs.first(where: { state.hasChildren($0) }) else {
            XCTFail("Trace did not contain a collapsible node.")
            return
        }

        let descendants = state.descendants(of: collapsibleID)
        guard !descendants.isEmpty else {
            XCTFail("Collapsible node had no descendants.")
            return
        }

        _ = TraceViewerList.reduce(&state, .selectEvent(id: collapsibleID, shouldFocus: false))
        _ = TraceViewerList.reduce(&state, .collapseSelected)

        XCTAssertTrue(state.isCollapsed(collapsibleID))
        for descendantID in descendants {
            XCTAssertFalse(state.visibleIDs.contains(descendantID))
            XCTAssertFalse(state.visibleOverviewGraphNodes.contains(where: { $0.id == descendantID }))
        }
    }

    @Test
    func testReplaceTraceCollectionPreservesSelectionAndCollapsedState() throws {
        var state = try makeStateFromGeneratedTrace()
        guard let collapsibleID = state.visibleIDs.first(where: { state.hasChildren($0) }) else {
            XCTFail("Trace did not contain a collapsible node.")
            return
        }

        _ = TraceViewerList.reduce(&state, .selectEvent(id: collapsibleID, shouldFocus: false))
        _ = TraceViewerList.reduce(&state, .collapseSelected)

        let traceCollection = state.traceCollection
        _ = TraceViewerList.reduce(&state, .replaceTraceCollection(traceCollection))

        XCTAssertEqual(state.selectedID, collapsibleID)
        XCTAssertTrue(state.collapsedIDs.contains(collapsibleID))
    }

    @Test
    func testReplaceTraceCollectionEmitsScrollEffectWhenSelectionChanges() throws {
        var state = try makeStateFromGeneratedTrace()
        let replacementCollection = try makeStateFromRecordMeetingTrace().traceCollection
        let previousSelectedID = state.selectedID

        let effect = TraceViewerList.reduce(&state, .replaceTraceCollection(replacementCollection))

        guard let selectedID = state.selectedID else {
            XCTFail("Replacement trace did not contain a selectable item.")
            return
        }
        guard previousSelectedID != selectedID else {
            XCTFail("Replacement trace unexpectedly preserved the same selection ID.")
            return
        }

        XCTAssertFalse(containsResetTimelineListFocusAction(in: effect))
        XCTAssertEqual(scrolledTimelineID(in: effect), selectedID)
    }

    @Test
    func testSyncScheduledEffectActionsShareOverviewColumn() async throws {
        let state = try await makeStateFromSyncScheduledEffectsTrace()

        guard let alphaAction = overviewEffectActionNode(
            named: "startAlpha",
            in: state
        ), let betaAction = overviewEffectActionNode(
            named: "startBeta",
            in: state
        ) else {
            XCTFail("Expected sync scheduled effect actions were not present in the overview graph.")
            return
        }

        XCTAssertEqual(
            alphaAction.column,
            betaAction.column,
            "Sync-scheduled sibling effect actions should align vertically in the same overview column."
        )
    }

    @Test
    func testSyncScheduledEffectActionsUseDistinctLanesBottomToTop() async throws {
        let state = try await makeStateFromSyncScheduledEffectsTrace()

        guard let alphaAction = overviewEffectActionNode(
            named: "startAlpha",
            in: state
        ), let betaAction = overviewEffectActionNode(
            named: "startBeta",
            in: state
        ) else {
            XCTFail("Expected sync scheduled effect actions were not present in the overview graph.")
            return
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

    @Test
    func testRecordMeetingTimerEffectKeepsOneLaneForItsMutatingActions() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let startAction = state.itemsByID.values.first { item in
            guard case .action(let action) = item.node else { return false }
            return action.actionCase == "startOneSecondTimer" && action.kind == .effect
        }
        guard let startAction else {
            XCTFail("startOneSecondTimer action not found in RecordMeeting trace.")
            return
        }

        let startedEffectID = state.graph.edges.compactMap { edge -> String? in
            guard case .startedEffect(let started) = edge else { return nil }
            guard started.actionID.rawValue == startAction.id else { return nil }
            return started.effectID.rawValue
        }.first
        guard let startedEffectID else {
            XCTFail("No started effect for startOneSecondTimer in RecordMeeting trace.")
            return
        }

        guard let startLane = state.overviewGraphNodeByID[startAction.id]?.lane else {
            XCTFail("No lane for startOneSecondTimer action.")
            return
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

    @Test
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
            XCTFail("startOneSecondTimer action not found in RecordMeeting trace.")
            return
        }

        let startedEffectID = state.graph.edges.compactMap { edge -> String? in
            guard case .startedEffect(let started) = edge else { return nil }
            guard started.actionID.rawValue == startAction.id.rawValue else { return nil }
            return started.effectID.rawValue
        }.first
        guard let startedEffectID else {
            XCTFail("No started effect for startOneSecondTimer in RecordMeeting trace.")
            return
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
            XCTFail("Not enough timer actions to assert thread continuity.")
            return
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

    @Test
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
            XCTFail("startOneSecondTimer action not found in RecordMeeting trace.")
            return
        }
        guard let transcriptStartAction = actionByID.values.first(where: {
            ($0.actionCase == "startTranscriptRecording" || $0.actionCase == "startTrasscriptRecording")
            && $0.kind == .effect
        }) else {
            XCTFail("startTranscriptRecording action not found in RecordMeeting trace.")
            return
        }

        guard let timerEffectID = startedEffectByActionID[timerStartAction.id.rawValue],
              let transcriptEffectID = startedEffectByActionID[transcriptStartAction.id.rawValue],
              let timerEffect = effectByID[timerEffectID],
              let transcriptEffect = effectByID[transcriptEffectID] else {
            XCTFail("Required effect nodes not found in RecordMeeting trace.")
            return
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

    @Test
    func testRecordMeetingAdjacentEffectStartReusesLaneWhenFirstHasNoContinuations() throws {
        let state = try makeStateFromRecordMeetingTrace()
        let actions = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            return action
        }
        guard let prepareSoundPlayer = actions.first(where: {
            $0.actionCase == "prepareSoundPlayer" && $0.kind == .effect
        }) else {
            XCTFail("prepareSoundPlayer action not found in RecordMeeting trace.")
            return
        }
        guard let startOneSecondTimer = actions.first(where: {
            $0.actionCase == "startOneSecondTimer" && $0.kind == .effect
        }) else {
            XCTFail("startOneSecondTimer action not found in RecordMeeting trace.")
            return
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

    @Test
    func testRecordMeetingFirstMutationDoesNotUsePrepareSoundPlayerAsPredecessor() throws {
        let state = try makeStateFromRecordMeetingTrace()

        let actions = state.itemsByID.values.compactMap { item -> SessionGraph.ActionNode? in
            guard case .action(let action) = item.node else { return nil }
            return action
        }
        guard let prepareSoundPlayer = actions.first(where: {
            $0.actionCase == "prepareSoundPlayer" && $0.kind == .effect
        }) else {
            XCTFail("prepareSoundPlayer action not found in RecordMeeting trace.")
            return
        }

        guard let firstMutationAfterPrepare = actions
            .filter({ $0.kind == .mutating && $0.order > prepareSoundPlayer.order })
            .sorted(by: { $0.order < $1.order })
            .first else {
            XCTFail("No mutation action found after prepareSoundPlayer.")
            return
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

    @Test
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
            XCTFail("No mutating action found in generated trace.")
            return
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

    @Test
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

    @Test
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
            XCTFail("showEndMeetingAlert action not found in RecordMeeting trace.")
            return
        }
        guard let effectID = startedEffectByActionID[showEndMeetingAlert.id.rawValue] else {
            XCTFail("showEndMeetingAlert effect not found in RecordMeeting trace.")
            return
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

    @Test
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

    @Test
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

    @Test
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
            XCTFail("No user-origin mutation actions found in RecordMeeting trace.")
            return
        }

        guard let mutationNode = state.overviewGraphNodeByID[firstUserMutation.id.rawValue] else {
            XCTFail("Overview node for user-origin mutation not found.")
            return
        }
        XCTAssertEqual(
            mutationNode.predecessorIDs.count,
            1,
            "User-origin mutation should not receive extra synthetic thread predecessors."
        )
        guard let onlyPredecessorID = mutationNode.predecessorIDs.first,
              let onlyPredecessor = state.itemsByID[onlyPredecessorID] else {
            XCTFail("Expected single predecessor for user-origin mutation.")
            return
        }
        XCTAssertEqual(
            onlyPredecessor.kind,
            .state,
            "User-origin mutation predecessor should be the input store state."
        )
    }

    @Test
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

}
