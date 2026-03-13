//
//  LiveTrace.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 3/3/26.
//

import Foundation
import ReducerArchitecture

enum LiveTrace: StoreNamespace {
    typealias PublishedValue = Void

    struct StoreEnvironment {
        let liveUpdates: @MainActor (_ port: UInt16) -> AsyncStream<LiveUpdate>
        let syncTraceViewer: @MainActor (_ traceCollection: SessionTraceCollection) -> Void
    }

    enum MutatingAction {
        case markListeningStarted
        case selectSession(id: String)
        case selectPreviousSession
        case selectNextSession
        case selectStore(id: String)
        case updateServerStatus(LiveTraceServer.Status)
        case receiveEnvelope(LiveTraceEnvelope)
    }

    enum EffectAction {
        case startListeningIfNeeded
        case startListening
        case syncSelectedTraceViewer
    }

    enum LiveUpdate: Sendable {
        case status(LiveTraceServer.Status)
        case envelope(LiveTraceEnvelope)
    }

    struct StoreState {
        struct Session: Identifiable {
            let id: String
            var lastUpdatedAt: Date
            var selectedStoreID: String?
            fileprivate var accumulator: LiveTraceSessionAccumulator

            init(sessionID: String) {
                self.id = sessionID
                self.lastUpdatedAt = .now
                self.selectedStoreID = nil
                self.accumulator = .init(
                    title: "Live Trace",
                    sessionID: sessionID
                )
            }

            var traceSession: TraceSession {
                accumulator.session
            }

            var title: String {
                traceSession.title
            }

            var subtitleLines: [String] {
                LiveTrace.sessionSubtitleLines(
                    session: traceSession,
                    fallback: id
                )
            }

            var startedAt: Date? {
                traceSession.startedAt
            }

            var storeTraces: [TraceSession.StoreTrace] {
                traceSession.storeTraces
            }

            var selectedStore: TraceSession.StoreTrace? {
                traceSession.storeTrace(id: selectedStoreID)
            }

            var selectedTraceCollection: SessionTraceCollection? {
                selectedStore?.traceCollection
            }

            var completedAt: Date? {
                let endedAtValues = storeTraces.compactMap(\.endedAt)
                guard !storeTraces.isEmpty, endedAtValues.count == storeTraces.count else {
                    return nil
                }
                return endedAtValues.max()
            }

            var statusText: String {
                if let completedAt {
                    return "Completed \(completedAt.formatted(date: .omitted, time: .standard))"
                }
                return "Updated \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
            }

            var selectedStoreStatusText: String {
                if let endedAt = selectedStore?.endedAt {
                    return "Store ended \(endedAt.formatted(date: .omitted, time: .standard))"
                }
                return statusText
            }

            var startedAtText: String? {
                startedAt.map {
                    "Started \($0.formatted(date: .abbreviated, time: .standard))"
                }
            }

            func storeSummaryText(for storeTrace: TraceSession.StoreTrace) -> String {
                var parts = [
                    "\(storeTrace.traceCollection.sessionGraph.nodes.count) nodes",
                    "\(storeTrace.traceCollection.sessionGraph.edges.count) edges"
                ]
                if let endedAt = storeTrace.endedAt {
                    parts.append("Ended \(endedAt.formatted(date: .omitted, time: .standard))")
                }
                return parts.joined(separator: " • ")
            }

            mutating func apply(_ envelope: LiveTraceEnvelope) {
                accumulator.apply(envelope)
                lastUpdatedAt = accumulator.lastUpdatedAt
                normalizeSelectedStore()
            }

            mutating func selectStore(id: String) {
                guard storeTraces.contains(where: { $0.id == id }) else { return }
                selectedStoreID = id
            }

            private mutating func normalizeSelectedStore() {
                if selectedStoreID == nil ||
                    !storeTraces.contains(where: { $0.id == selectedStoreID }) {
                    selectedStoreID = storeTraces.first?.id
                }
            }
        }

        let port: UInt16
        var isListening = false
        var selectedSessionID: String?
        var serverStatus: LiveTraceServer.Status
        private(set) var sessionsByID: [String: Session]

        init(port: UInt16 = LiveTraceDefaults.defaultPort) {
            self.port = port
            self.serverStatus = .starting(port)
            self.sessionsByID = [:]
        }

        var sessions: [Session] {
            sessionsByID.values.sorted { lhs, rhs in
                if lhs.lastUpdatedAt == rhs.lastUpdatedAt {
                    return lhs.id < rhs.id
                }
                return lhs.lastUpdatedAt > rhs.lastUpdatedAt
            }
        }

        var selectedSession: Session? {
            guard let selectedSessionID else { return nil }
            return sessionsByID[selectedSessionID]
        }

        var selectedTraceCollection: SessionTraceCollection? {
            selectedSession?.selectedTraceCollection
        }

        mutating func selectSession(id: String) {
            guard sessionsByID[id] != nil else { return }
            selectedSessionID = id
        }

        mutating func selectRelativeSession(offset: Int) {
            let sessions = sessions
            guard !sessions.isEmpty else {
                selectedSessionID = nil
                return
            }

            guard let selectedSessionID,
                  let currentIndex = sessions.firstIndex(where: { $0.id == selectedSessionID }) else {
                self.selectedSessionID = sessions.first?.id
                return
            }

            let nextIndex = min(
                max(currentIndex + offset, 0),
                sessions.count - 1
            )
            self.selectedSessionID = sessions[nextIndex].id
        }

        mutating func selectStore(id: String) {
            guard let selectedSessionID,
                  var session = sessionsByID[selectedSessionID] else {
                return
            }
            session.selectStore(id: id)
            sessionsByID[selectedSessionID] = session
        }

        mutating func updateServerStatus(_ status: LiveTraceServer.Status) {
            serverStatus = status
        }

        mutating func receiveEnvelope(_ envelope: LiveTraceEnvelope) {
            var session = sessionsByID[envelope.sessionID] ?? .init(sessionID: envelope.sessionID)
            session.apply(envelope)
            sessionsByID[session.id] = session
            normalizeSelectedSession()
        }

        private mutating func normalizeSelectedSession() {
            if selectedSessionID == nil || sessionsByID[selectedSessionID ?? ""] == nil {
                selectedSessionID = sessions.first?.id
            }
        }
    }
}

extension LiveTrace {
    private static let listenEffectKey = "live-trace-listener"

    @MainActor
    static func store(port: UInt16 = LiveTraceDefaults.defaultPort) -> Store {
        Store(.init(port: port), env: nil)
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .markListeningStarted:
            guard !state.isListening else { return .none }
            state.isListening = true
            return .action(.effect(.startListening))

        case .selectSession(let id):
            let previousSelectedSessionID = state.selectedSessionID
            state.selectSession(id: id)
            guard state.selectedSessionID != previousSelectedSessionID else { return .none }
            return .action(.effect(.syncSelectedTraceViewer))

        case .selectPreviousSession:
            let previousSelectedSessionID = state.selectedSessionID
            state.selectRelativeSession(offset: -1)
            guard state.selectedSessionID != previousSelectedSessionID else { return .none }
            return .action(.effect(.syncSelectedTraceViewer))

        case .selectNextSession:
            let previousSelectedSessionID = state.selectedSessionID
            state.selectRelativeSession(offset: 1)
            guard state.selectedSessionID != previousSelectedSessionID else { return .none }
            return .action(.effect(.syncSelectedTraceViewer))

        case .selectStore(let id):
            let previousSelectedStoreID = state.selectedSession?.selectedStore?.id
            state.selectStore(id: id)
            guard state.selectedSession?.selectedStore?.id != previousSelectedStoreID else {
                return .none
            }
            return .action(.effect(.syncSelectedTraceViewer))

        case .updateServerStatus(let status):
            state.updateServerStatus(status)
            return .none

        case .receiveEnvelope(let envelope):
            state.receiveEnvelope(envelope)
            guard state.selectedSessionID == envelope.sessionID else { return .none }
            guard state.selectedSession?.selectedStore?.id == envelope.storeInstanceID else {
                return .none
            }
            return .action(.effect(.syncSelectedTraceViewer))
        }
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        switch action {
        case .startListeningIfNeeded:
            guard !state.isListening else { return .none }
            return .action(.mutating(.markListeningStarted))

        case .startListening:
            let port = state.port
            return .asyncActionSequenceLatest(key: listenEffectKey) { send in
                if state.selectedTraceCollection != nil {
                    send(.effect(.syncSelectedTraceViewer))
                }

                for await update in env.liveUpdates(port) {
                    switch update {
                    case .status(let status):
                        send(.mutating(.updateServerStatus(status)))
                    case .envelope(let envelope):
                        send(.mutating(.receiveEnvelope(envelope)))
                    }
                }
            }

        case .syncSelectedTraceViewer:
            guard let traceCollection = state.selectedTraceCollection else { return .none }
            env.syncTraceViewer(traceCollection)
            return .none
        }
    }
}

extension LiveTrace {
    fileprivate static func sessionSubtitleLines(
        session: TraceSession,
        fallback: String
    ) -> [String] {
        var lines: [String] = []
        lines.append(
            session.storeTraces.count == 1
                ? "1 store"
                : "\(session.storeTraces.count) stores"
        )

        if let processName = normalized(session.processName),
           processName != session.title {
            lines.append(processName)
        }

        if let hostName = normalized(session.hostName) {
            lines.append(hostName)
        }

        return lines.isEmpty ? [fallback] : lines
    }

    fileprivate static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
