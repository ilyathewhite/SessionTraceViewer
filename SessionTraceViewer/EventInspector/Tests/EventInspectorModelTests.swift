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
            inlineDiffRowID: "count"
        )

        let effect = EventInspector.reduce(&inspectorState, .updateSelection(nextSelection))

        XCTAssertEqual(inspectorState.selection, nextSelection)
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

    @Test
    func testInlinePreviewShowsFullValueWhenTenLinesOrLess() {
        let value = (1...10).map { "line \($0)" }.joined(separator: "\n")

        XCTAssertEqual(
            EventInspectorFormatter.inlinePreviewLineLimit(for: value),
            10
        )
        XCTAssertFalse(
            EventInspectorFormatter.inlinePreviewShowsTruncation(for: value)
        )
    }

    @Test
    func testInlinePreviewTruncatesWhenValueExceedsTenLines() {
        let value = (1...11).map { "line \($0)" }.joined(separator: "\n")

        XCTAssertEqual(
            EventInspectorFormatter.inlinePreviewLineLimit(for: value),
            3
        )
        XCTAssertTrue(
            EventInspectorFormatter.inlinePreviewShowsTruncation(for: value)
        )
    }

    @Test
    func testEventInspectorInspectValueOpensWindowForTruncatedPreview() {
        var inspectorState = EventInspector.StoreState(
            selection: .init(
                item: nil,
                previousStateItem: nil
            )
        )
        inspectorState.detailRows = [
            .init(
                id: "details-0-notes",
                property: "notes",
                value: (1...11).map { "line \($0)" }.joined(separator: "\n"),
                isChanged: false,
                change: nil,
                inlinePreviewLineLimit: 3,
                showsTruncationInPreview: true
            )
        ]

        let effect = EventInspector.runEffect(
            makeEventInspectorEnv(),
            inspectorState,
            .inspectValue(rowID: "details-0-notes")
        )

        switch effect {
        case .action(let action, _):
            guard case .effect(.openValueWindow(let input)) = action else {
                return XCTFail("Expected truncated value inspection to open a value window, got \(action).")
            }
            XCTAssertEqual(input.title, "notes")
            XCTAssertTrue(input.value.contains("line 11"))

        default:
            XCTFail("Expected truncated value inspection to open a value window, got \(effect).")
        }
    }
}
