//
//  LiveTraceStore.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 3/3/26.
//

import Foundation
import ReducerArchitecture
import SwiftUI

@MainActor
final class LiveTraceStore: ObservableObject {
    @Published var selectedSessionID: String?
    @Published private(set) var sessions: [LiveTraceSessionViewModel] = []
    @Published private(set) var serverStatus = LiveTraceServer.Status.starting(SessionTraceLiveDefaults.defaultPort)

    private let server: LiveTraceServer
    private var sessionsByID: [String: LiveTraceSessionViewModel] = [:]

    init(port: UInt16 = SessionTraceLiveDefaults.defaultPort) {
        server = LiveTraceServer(port: port)
        server.onEnvelope = { [weak self] envelope in
            self?.handle(envelope)
        }
        server.onStatusChange = { [weak self] status in
            self?.serverStatus = status
        }
        server.start()
    }

    deinit {
        server.stop()
    }

    var selectedSession: LiveTraceSessionViewModel? {
        guard let selectedSessionID else { return sessions.first }
        return sessionsByID[selectedSessionID] ?? sessions.first
    }

    private func handle(_ envelope: SessionTraceLiveEnvelope) {
        let session = sessionModel(for: envelope.sessionID)
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

        refreshSessions()
    }

    private func sessionModel(for sessionID: String) -> LiveTraceSessionViewModel {
        if let existing = sessionsByID[sessionID] {
            return existing
        }

        let session = LiveTraceSessionViewModel(sessionID: sessionID)
        sessionsByID[sessionID] = session
        return session
    }

    private func refreshSessions() {
        sessions = sessionsByID.values.sorted { lhs, rhs in
            if lhs.lastUpdatedAt == rhs.lastUpdatedAt {
                return lhs.id < rhs.id
            }
            return lhs.lastUpdatedAt > rhs.lastUpdatedAt
        }

        if selectedSessionID == nil || sessionsByID[selectedSessionID ?? ""] == nil {
            selectedSessionID = sessions.first?.id
        }
    }
}

@MainActor
final class LiveTraceSessionViewModel: ObservableObject, Identifiable {
    let id: String
    let traceViewerStore: TraceViewer.Store

    @Published private(set) var title: String
    @Published private(set) var subtitleLines: [String]
    @Published private(set) var lastUpdatedAt: Date
    @Published private(set) var isEnded = false
    @Published private(set) var startedAt: Date?

    private var accumulator: SessionGraphAccumulator

    init(sessionID: String) {
        self.id = sessionID
        self.title = "Live Trace"
        self.subtitleLines = [sessionID]
        self.lastUpdatedAt = .now
        self.accumulator = .init(
            title: "Live Trace",
            sessionID: sessionID
        )
        self.traceViewerStore = TraceViewer.store(traceCollection: accumulator.traceCollection)
    }

    func apply(metadata: SessionTraceLiveSessionMetadata) {
        title = metadata.title
        subtitleLines = Self.sessionSubtitleLines(
            metadata: metadata,
            fallback: id
        )
        startedAt = metadata.startedAt
        isEnded = false
        accumulator.title = metadata.title
        pushCurrentTrace()
    }

    func apply(snapshot: SessionTraceCollection) {
        accumulator.replace(with: snapshot)
        title = snapshot.title
        isEnded = false
        pushCurrentTrace()
    }

    func apply(patch: SessionTraceLivePatch) {
        accumulator.apply(patch)
        isEnded = false
        pushCurrentTrace()
    }

    func markEnded() {
        isEnded = true
        lastUpdatedAt = .now
    }

    private func pushCurrentTrace() {
        let traceCollection = accumulator.traceCollection
        lastUpdatedAt = .now
        traceViewerStore.send(.mutating(.replaceTraceCollection(traceCollection)))
    }

    private static func sessionSubtitleLines(
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
