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
        let metadata = SessionTraceLiveSessionMetadata(
            sessionID: "session-z",
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
        XCTAssertEqual(state.selectedSession?.subtitleLines, ["CounterStore", "Trace Host", "MacBook Pro"])
        XCTAssertEqual(state.selectedSession?.startedAt, startedAt)
        XCTAssertEqual(syncedLiveTraceSessionID(in: effect), metadata.sessionID)
    }

    @Test
    func testLiveTraceKeepsCurrentSelectionWhenNewerSessionArrives() {
        var state = LiveTrace.StoreState()

        _ = LiveTrace.reduce(
            &state,
            .receiveEnvelope(
                .hello(
                    .init(
                        sessionID: "session-z",
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
                    .init(
                        sessionID: "session-a",
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
                    .init(
                        sessionID: "session-z",
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
                    .init(
                        sessionID: "session-a",
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
}
