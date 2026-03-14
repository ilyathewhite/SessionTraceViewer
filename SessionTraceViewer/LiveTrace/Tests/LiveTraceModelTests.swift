import Foundation
import XCTest
import ReducerArchitecture
import Testing
@testable import SessionTraceViewer

extension ModelTests {
    @MainActor
    @Suite struct LiveTraceModelTests {}
}

extension ModelTests.LiveTraceModelTests {
    @Test
    func testLiveTraceReceiveHelloCreatesSessionAndSelectsIt() {
        var state = LiveTrace.StoreState(port: 41234)
        let startedAt = Date(timeIntervalSince1970: 100)
        let metadata = makeMetadata(
            sessionID: "session-z",
            storeInstanceID: "counter.s1",
            title: "Counter Trace",
            storeName: "CounterStore",
            hostName: "MacBook Pro",
            processName: "Trace Host",
            startedAt: startedAt
        )

        let effect = LiveTrace.reduce(&state, .receiveEnvelope(.hello(metadata)))

        XCTAssertEqual(state.selectedSessionID, metadata.sessionID)
        XCTAssertEqual(state.sessions.map(\.id), [metadata.sessionID])
        XCTAssertEqual(state.selectedSession?.title, metadata.title)
        XCTAssertEqual(state.selectedSession?.subtitleLines, ["1 store", "Trace Host", "MacBook Pro"])
        XCTAssertEqual(state.selectedSession?.startedAt, startedAt)
        XCTAssertEqual(state.selectedSession?.storeTraces.map(\.id), [metadata.storeInstanceID])
        XCTAssertEqual(state.selectedSession?.storeTraces.first?.id, metadata.storeInstanceID)
        XCTAssertEqual(state.selectedSession?.storeTraces.first?.displayName, metadata.storeName)
        XCTAssertTrue(syncsSelectedLiveTraceViewer(in: effect))
    }

    @Test
    func testLiveTraceMergesMultipleStoresIntoOneSelectedSession() {
        var state = LiveTrace.StoreState()

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "counter.s1",
                        title: "Example App",
                        storeName: "CounterStore",
                        startedAt: .init(timeIntervalSince1970: 100)
                    )
                )
            )
        )

        let effect = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "timer.s2",
                        title: "Example App",
                        storeName: "TimerStore",
                        startedAt: .init(timeIntervalSince1970: 110)
                    )
                )
            )
        )

        XCTAssertEqual(state.sessions.map(\.id), ["session-z"])
        XCTAssertEqual(state.selectedSession?.storeTraces.map(\.id), ["counter.s1", "timer.s2"])
        XCTAssertTrue(syncsSelectedLiveTraceViewer(in: effect))
    }

    @Test
    func testLiveTraceKeepsCurrentSelectionWhenNewerSessionArrives() {
        var state = LiveTrace.StoreState()

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "store-z.s1",
                        title: "First Trace",
                        storeName: "Store Z",
                        hostName: "Host Z",
                        processName: "Process Z",
                        startedAt: .init(timeIntervalSince1970: 100)
                    )
                )
            )
        )
        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-a",
                        storeInstanceID: "store-a.s1",
                        title: "Second Trace",
                        storeName: "Store A",
                        hostName: "Host A",
                        processName: "Process A",
                        startedAt: .init(timeIntervalSince1970: 200)
                    )
                )
            )
        )

        XCTAssertEqual(state.selectedSessionID, "session-z")
        XCTAssertEqual(state.sessions.first?.id, "session-a")
    }

    @Test
    func testLiveTraceSessionNavigationFollowsSortedSidebarOrder() {
        var state = LiveTrace.StoreState()

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "store-z.s1",
                        title: "First Trace",
                        storeName: "Store Z",
                        hostName: "Host Z",
                        processName: "Process Z",
                        startedAt: .init(timeIntervalSince1970: 100)
                    )
                )
            )
        )
        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-a",
                        storeInstanceID: "store-a.s1",
                        title: "Second Trace",
                        storeName: "Store A",
                        hostName: "Host A",
                        processName: "Process A",
                        startedAt: .init(timeIntervalSince1970: 200)
                    )
                )
            )
        )

        _ = LiveTrace.reduce(&state, .selectPreviousSession)
        XCTAssertEqual(state.selectedSessionID, "session-a")

        _ = LiveTrace.reduce(&state, .selectNextSession)
        XCTAssertEqual(state.selectedSessionID, "session-z")
    }

    @Test
    func testSelectingSessionSyncsSelectedTraceViewer() {
        var state = LiveTrace.StoreState()

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "store-z.s1",
                        title: "First Trace",
                        storeName: "Store Z",
                        hostName: "Host Z",
                        processName: "Process Z",
                        startedAt: .init(timeIntervalSince1970: 100)
                    )
                )
            )
        )
        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-a",
                        storeInstanceID: "store-a.s1",
                        title: "Second Trace",
                        storeName: "Store A",
                        hostName: "Host A",
                        processName: "Process A",
                        startedAt: .init(timeIntervalSince1970: 200)
                    )
                )
            )
        )

        let effect = LiveTrace.reduce(&state, .selectPreviousSession)

        XCTAssertEqual(state.selectedSessionID, "session-a")
        XCTAssertTrue(syncsSelectedLiveTraceViewer(in: effect))
    }

    @Test
    func testLiveTraceDoesNotSyncTraceViewerForUnselectedSessionUpdate() {
        var state = LiveTrace.StoreState()

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "store-z.s1",
                        title: "First Trace",
                        storeName: "Store Z",
                        hostName: "Host Z",
                        processName: "Process Z",
                        startedAt: .init(timeIntervalSince1970: 100)
                    )
                )
            )
        )
        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-a",
                        storeInstanceID: "store-a.s1",
                        title: "Second Trace",
                        storeName: "Store A",
                        hostName: "Host A",
                        processName: "Process A",
                        startedAt: .init(timeIntervalSince1970: 200)
                    )
                )
            )
        )

        let effect = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-a",
                        storeInstanceID: "store-a.s1",
                        title: "Updated Trace",
                        storeName: "Store A",
                        hostName: "Host A",
                        processName: "Process A",
                        startedAt: .init(timeIntervalSince1970: 200)
                    )
                )
            )
        )

        XCTAssertEqual(state.selectedSessionID, "session-z")
        XCTAssertFalse(syncsSelectedLiveTraceViewer(in: effect))
    }

    @Test
    func testLiveTraceSyncsTraceViewerForSelectedSessionStoreUpdate() {
        var state = LiveTrace.StoreState()

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "counter.s1",
                        title: "Example App",
                        storeName: "CounterStore"
                    )
                )
            )
        )
        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "timer.s2",
                        title: "Example App",
                        storeName: "TimerStore"
                    )
                )
            )
        )

        let effect = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "timer.s2",
                        title: "Example App",
                        storeName: "TimerStore"
                    )
                )
            )
        )

        XCTAssertEqual(
            state.selectedSession?.storeTraces.first(where: { $0.id == "timer.s2" })?.displayName,
            "TimerStore"
        )
        XCTAssertTrue(syncsSelectedLiveTraceViewer(in: effect))
    }

    @Test
    func testLiveTraceMarksStoreAsEndedWhenMetadataUpdates() {
        var state = LiveTrace.StoreState()
        let startedAt = Date(timeIntervalSince1970: 100)
        let endedAt = Date(timeIntervalSince1970: 140)

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "counter.s1",
                        title: "Example App",
                        storeName: "CounterStore",
                        startedAt: startedAt
                    )
                )
            )
        )

        let effect = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "counter.s1",
                        title: "Example App",
                        storeName: "CounterStore",
                        startedAt: startedAt,
                        endedAt: endedAt
                    )
                )
            )
        )

        XCTAssertEqual(
            state.selectedSession?.storeTraces.first(where: { $0.id == "counter.s1" })?.endedAt,
            endedAt
        )
        XCTAssertTrue(
            state.selectedSession?.storeTraces.first(where: { $0.id == "counter.s1" })?.isEnded == true
        )
        XCTAssertEqual(state.selectedSession?.completedAt, endedAt)
        XCTAssertTrue(state.selectedSession?.statusText.hasPrefix("Completed") ?? false)
        XCTAssertTrue(syncsSelectedLiveTraceViewer(in: effect))
    }

    @Test
    func testLiveTraceSessionExportFilenameUsesSessionMetadata() {
        var state = LiveTrace.StoreState()
        let startedAt = Date(timeIntervalSince1970: 100)

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    makeMetadata(
                        sessionID: "session-z",
                        storeInstanceID: "counter.s1",
                        title: "Example / App",
                        storeName: "CounterStore",
                        startedAt: startedAt
                    )
                )
            )
        )

        XCTAssertEqual(
            state.selectedSession?.exportFilename,
            "Example - App-1970-01-01_000140"
        )
    }

    private func makeMetadata(
        sessionID: String,
        storeInstanceID: String,
        title: String,
        storeName: String,
        hostName: String = "Host",
        processName: String = "Process",
        startedAt: Date = .init(timeIntervalSince1970: 100),
        endedAt: Date? = nil
    ) -> LiveTraceStoreMetadata {
        .init(
            sessionID: sessionID,
            storeInstanceID: storeInstanceID,
            title: title,
            storeName: storeName,
            hostName: hostName,
            processName: processName,
            startedAt: startedAt,
            endedAt: endedAt
        )
    }
}
