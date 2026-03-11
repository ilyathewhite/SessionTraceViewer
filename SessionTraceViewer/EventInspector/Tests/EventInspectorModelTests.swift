import XCTest
import ReducerArchitecture
import Testing
@testable import SessionTraceViewer

extension ModelTests {
    @MainActor
    @Suite struct EventInspectorModelTests {}
}

extension ModelTests.EventInspectorModelTests {
    @Test
    func testEventInspectorUpdateSelectionClearsTransientStateAndDismissesInlineDiff() async throws {
        let state = try await makeStateFromGeneratedTrace()
        let stateItems = state.orderedIDs.compactMap { state.itemsByID[$0] }.filter { item in
            item.kind == .state
        }
        guard stateItems.count > 1 else {
            XCTFail("Need at least two state items to exercise inspector selection updates.")
            return
        }

        let initialSelection = EventInspector.Selection(
            item: stateItems[0],
            previousStateItem: nil
        )
        let nextSelection = EventInspector.Selection(
            item: stateItems[1],
            previousStateItem: stateItems[0]
        )
        var inspectorState = EventInspector.StoreState(
            selection: initialSelection,
            detailRowExpansionByID: ["details-0-captured": false],
            valueRowExpansionByID: ["count": false],
            inlineDiffRowID: "count"
        )

        let effect = EventInspector.reduce(&inspectorState, .updateSelection(nextSelection))

        XCTAssertEqual(inspectorState.selection, nextSelection)
        XCTAssertTrue(inspectorState.detailRowExpansionByID.isEmpty)
        XCTAssertTrue(inspectorState.valueRowExpansionByID.isEmpty)
        XCTAssertNil(inspectorState.inlineDiffRowID)
        let actions = eventInspectorSyncActions(in: effect)
        XCTAssertEqual(actions.count, 1)
        guard case .effect(.syncInlineDiff(nil)) = actions[0] else {
            return XCTFail("Expected selection update to dismiss inline diff, got \(actions).")
        }
    }

    @Test
    func testEventInspectorInspectDiffUsesInlinePresentationForShortChanges() async throws {
        let state = try await makeStateFromGeneratedTrace()
        let stateItems = state.orderedIDs.compactMap { state.itemsByID[$0] }.filter { item in
            item.kind == .state
        }
        guard stateItems.count > 1 else {
            XCTFail("Need at least two state items to exercise inspector diff presentation.")
            return
        }
        let previousItem = stateItems[0]
        let currentItem = stateItems[1]
        let expectedInput = StringDiff.input(
            title: "count",
            oldValue: try XCTUnwrap(formattedStateValue(property: "count", in: previousItem)),
            newValue: try XCTUnwrap(formattedStateValue(property: "count", in: currentItem))
        )
        let inspectorState = EventInspector.StoreState(
            selection: .init(
                item: currentItem,
                previousStateItem: previousItem
            )
        )

        let effect = EventInspector.runEffect(
            makeEventInspectorEnv(),
            inspectorState,
            .inspectDiff(rowID: "count")
        )

        switch effect {
        case .action(.mutating(let action, _, _), _):
            guard case .setInlineDiff(let rowID, let input) = action else {
                return XCTFail("Expected inline diff selection action, got \(action).")
            }
            XCTAssertEqual(rowID, "count")
            XCTAssertEqual(input, expectedInput)

        default:
            XCTFail("Expected short diff to stay inline, got \(effect).")
        }
    }

    @Test
    func testEventInspectorTreatsLargeDiffsAsWindowContent() {
        let largeChange = EventInspectorFormatter.ValueChange(
            oldValue: "a\nb\nc\nd\ne",
            newValue: "A\nB\nC\nD\nE"
        )

        XCTAssertFalse(EventInspector.shouldPresentDiffInline(change: largeChange))
    }
}
