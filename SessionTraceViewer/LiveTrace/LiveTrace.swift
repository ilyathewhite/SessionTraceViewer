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
        case updateServerStatus(LiveTraceServer.Status)
        case receiveEnvelope(SessionTraceLiveEnvelope)
    }

    enum EffectAction {
        case startListeningIfNeeded
        case startListening
        case syncSelectedTraceViewer
    }

    enum LiveUpdate: Sendable {
        case status(LiveTraceServer.Status)
        case envelope(SessionTraceLiveEnvelope)
    }

    struct StoreState {
        struct Session: Identifiable {
            let id: String
            var title: String
            var subtitleLines: [String]
            var lastUpdatedAt: Date
            var isEnded = false
            var startedAt: Date?
            fileprivate var accumulator: SessionGraphAccumulator

            init(sessionID: String) {
                self.id = sessionID
                self.title = "Live Trace"
                self.subtitleLines = [sessionID]
                self.lastUpdatedAt = .now
                self.accumulator = .init(
                    title: "Live Trace",
                    sessionID: sessionID
                )
            }

            var traceCollection: SessionTraceCollection {
                accumulator.traceCollection
            }

            var statusText: String {
                if isEnded {
                    return "Ended \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
                }
                return "Updated \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
            }

            var startedAtText: String? {
                startedAt.map {
                    "Started \($0.formatted(date: .abbreviated, time: .standard))"
                }
            }

            mutating func apply(metadata: SessionTraceLiveSessionMetadata) {
                title = metadata.title
                subtitleLines = LiveTrace.sessionSubtitleLines(
                    metadata: metadata,
                    fallback: id
                )
                startedAt = metadata.startedAt
                isEnded = false
                lastUpdatedAt = .now
                accumulator.title = metadata.title
            }

            mutating func apply(snapshot: SessionTraceCollection) {
                accumulator.replace(with: snapshot)
                title = snapshot.title
                isEnded = false
                lastUpdatedAt = .now
            }

            mutating func apply(patch: SessionTraceLivePatch) {
                accumulator.apply(patch)
                isEnded = false
                lastUpdatedAt = .now
            }

            mutating func markEnded() {
                isEnded = true
                lastUpdatedAt = .now
            }
        }

        let port: UInt16
        var isListening = false
        var selectedSessionID: String?
        var serverStatus: LiveTraceServer.Status
        private(set) var sessionsByID: [String: Session]

        init(port: UInt16 = SessionTraceLiveDefaults.defaultPort) {
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

        mutating func updateServerStatus(_ status: LiveTraceServer.Status) {
            serverStatus = status
        }

        mutating func receiveEnvelope(_ envelope: SessionTraceLiveEnvelope) {
            var session = sessionsByID[envelope.sessionID] ?? .init(sessionID: envelope.sessionID)
            switch envelope.kind {
            case .hello:
                if let metadata = envelope.metadata {
                    session.apply(metadata: metadata)
                }

            case .snapshot:
                if let traceCollection = envelope.traceCollection {
                    session.apply(snapshot: traceCollection)
                }

            case .patch:
                if let patch = envelope.patch {
                    session.apply(patch: patch)
                }

            case .end:
                session.markEnded()
            }

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
    static func store(port: UInt16 = SessionTraceLiveDefaults.defaultPort) -> Store {
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

        case .updateServerStatus(let status):
            state.updateServerStatus(status)
            return .none

        case .receiveEnvelope(let envelope):
            state.receiveEnvelope(envelope)
            guard state.selectedSessionID == envelope.sessionID else { return .none }
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
                if state.selectedSessionID != nil {
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
            guard let traceCollection = state.selectedSession?.traceCollection else { return .none }
            env.syncTraceViewer(traceCollection)
            return .none
        }
    }
}

extension LiveTrace {
    fileprivate static func sessionSubtitleLines(
        metadata: SessionTraceLiveSessionMetadata,
        fallback: String
    ) -> [String] {
        let lines = [
            metadata.storeName,
            metadata.processName,
            metadata.hostName
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return lines.isEmpty ? [fallback] : lines
    }
}

private struct SessionGraphAccumulator {
    var title: String

    private let sessionID: String
    private var schemaVersion: Int
    private var storeInstanceID: SessionGraph.StoreInstanceID
    private var nodesByID: [String: SessionGraph.Node]
    private var edges: [SessionGraph.Edge]

    init(
        title: String,
        sessionID: String
    ) {
        self.title = title
        self.sessionID = sessionID
        self.schemaVersion = SessionGraph.currentSchemaVersion
        self.storeInstanceID = .init(rawValue: sessionID)
        self.nodesByID = [:]
        self.edges = []
    }

    mutating func replace(with traceCollection: SessionTraceCollection) {
        title = traceCollection.title
        schemaVersion = traceCollection.sessionGraph.schemaVersion
        storeInstanceID = traceCollection.sessionGraph.storeInstanceID
        nodesByID = Dictionary(
            uniqueKeysWithValues: traceCollection.sessionGraph.nodes.map { ($0.id, $0) }
        )
        edges = traceCollection.sessionGraph.edges.sorted(by: Self.edgeSort)
    }

    mutating func apply(_ patch: SessionTraceLivePatch) {
        switch patch {
        case .upsertNode(let node):
            nodesByID[node.id] = node

        case .appendEdge(let edge):
            edges.append(edge)
        }
    }

    var traceCollection: SessionTraceCollection {
        .init(
            title: title,
            sessionGraph: .init(
                schemaVersion: schemaVersion,
                storeInstanceID: storeInstanceID,
                nodes: nodesByID.values.sorted(by: Self.nodeSort),
                edges: edges.sorted(by: Self.edgeSort)
            )
        )
    }

    private static func nodeSort(lhs: SessionGraph.Node, rhs: SessionGraph.Node) -> Bool {
        if lhs.order == rhs.order {
            return lhs.id < rhs.id
        }
        return lhs.order < rhs.order
    }

    private static func edgeSort(lhs: SessionGraph.Edge, rhs: SessionGraph.Edge) -> Bool {
        lhs.order < rhs.order
    }
}
