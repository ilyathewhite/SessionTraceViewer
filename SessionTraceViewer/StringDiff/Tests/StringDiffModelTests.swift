import XCTest
import ReducerArchitecture
import Testing
@testable import SessionTraceViewer

extension ModelTests {
    @MainActor
    @Suite struct StringDiffModelTests {}
}

extension ModelTests.StringDiffModelTests {
    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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

    @Test
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
            makeDiffSections: StringDiff.makeDiffSections
        )

        if case .notStarted = store.state.diffSections {
        }
        else {
            XCTFail("Expected diff task to start in .notStarted state.")
        }
        XCTAssertNil(store.state.diffSections.value)

        let task = store.send(.effect(.loadDiffIfNeeded))

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

    @Test
    func testStringDiffFileMergeArgumentsUseExplicitSideFlags() {
        let oldFileURL = URL(fileURLWithPath: "/tmp/old.txt")
        let newFileURL = URL(fileURLWithPath: "/tmp/new.txt")

        XCTAssertEqual(
            StringDiff.fileMergeArguments(
                oldFileURL: oldFileURL,
                newFileURL: newFileURL
            ),
            [
                "-left",
                oldFileURL.path,
                "-right",
                newFileURL.path
            ]
        )
    }

    @Test
    func testStringDiffLaunchResolvedFileMergeLaunchesExecutable() {
        let oldFileURL = URL(fileURLWithPath: "/tmp/old.txt")
        let newFileURL = URL(fileURLWithPath: "/tmp/new.txt")
        let executableURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Applications/FileMerge.app/Contents/MacOS/FileMerge")

        var launchedExecutableURL: URL?
        var launchedArguments: [String]?

        let didLaunch = StringDiff.launchResolvedFileMerge(
            oldFileURL: oldFileURL,
            newFileURL: newFileURL,
            executableURL: executableURL,
            launchFileMergeExecutable: { executableURL, arguments in
                launchedExecutableURL = executableURL
                launchedArguments = arguments
            }
        )

        XCTAssertTrue(didLaunch)
        XCTAssertEqual(launchedExecutableURL, executableURL)
        XCTAssertEqual(
            launchedArguments,
            StringDiff.fileMergeArguments(
                oldFileURL: oldFileURL,
                newFileURL: newFileURL
            )
        )
    }

    @Test
    func testStringDiffLaunchResolvedFileMergeReturnsFalseWhenLaunchFails() {
        struct FileMergeLaunchFailed: Error {}

        let oldFileURL = URL(fileURLWithPath: "/tmp/old.txt")
        let newFileURL = URL(fileURLWithPath: "/tmp/new.txt")
        let executableURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Applications/FileMerge.app/Contents/MacOS/FileMerge")

        let didLaunch = StringDiff.launchResolvedFileMerge(
            oldFileURL: oldFileURL,
            newFileURL: newFileURL,
            executableURL: executableURL,
            launchFileMergeExecutable: { _, _ in
                throw FileMergeLaunchFailed()
            }
        )

        XCTAssertFalse(didLaunch)
    }
}
