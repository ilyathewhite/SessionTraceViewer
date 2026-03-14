//
//  TraceViewerState.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/13/26.
//

import Foundation
import ReducerArchitecture

extension TraceViewer.StoreState {
    init(traceSession: TraceSession) {
        self.traceSession = traceSession
        self.storeVisibilityByID = Dictionary(
            uniqueKeysWithValues: traceSession.storeTraces.map { ($0.id, true) }
        )
        self.viewerData = TraceViewer.makeViewerData(
            traceSession: traceSession,
            storeVisibilityByID: storeVisibilityByID
        )
    }

    var storeLayers: [TraceViewer.StoreLayer] {
        traceSession.storeTraces
            .enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.startedAt, rhs.element.startedAt) {
                case let (.some(lhsStartedAt), .some(rhsStartedAt)):
                    if lhsStartedAt != rhsStartedAt {
                        return lhsStartedAt < rhsStartedAt
                    }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
            .map { storeTrace in
            return .init(
                id: storeTrace.id,
                displayName: storeTrace.displayName,
                isVisible: storeVisibilityByID[storeTrace.id] ?? true
            )
        }
    }

    mutating func replaceTraceSession(_ traceSession: TraceSession) {
        self.traceSession = traceSession
        var nextVisibilityByID: [String: Bool] = [:]
        for storeTrace in traceSession.storeTraces {
            nextVisibilityByID[storeTrace.id] = storeVisibilityByID[storeTrace.id] ?? true
        }
        storeVisibilityByID = nextVisibilityByID
        rebuildViewerData()
    }

    mutating func setStoreVisibility(id: String, isVisible: Bool) {
        guard let currentVisibility = storeVisibilityByID[id] else { return }
        guard currentVisibility != isVisible else { return }
        storeVisibilityByID[id] = isVisible
        rebuildViewerData()
    }

    mutating func toggleStoreVisibility(id: String) {
        guard let currentVisibility = storeVisibilityByID[id] else { return }
        setStoreVisibility(id: id, isVisible: !currentVisibility)
    }

    private mutating func rebuildViewerData() {
        viewerData = TraceViewer.makeViewerData(
            traceSession: traceSession,
            storeVisibilityByID: storeVisibilityByID
        )
        contentVersion += 1
    }
}

extension TraceViewer {
    static func traceSession(from traceCollection: SessionTraceCollection) -> TraceSession {
        let storeInstanceID = traceCollection.sessionGraph.storeInstanceID.rawValue
        return .init(
            sessionID: "viewer.single-session.\(storeInstanceID)",
            title: traceCollection.title,
            hostName: nil,
            processName: nil,
            startedAt: nil,
            storeTraces: [
                .init(
                    storeInstanceID: storeInstanceID,
                    storeName: traceCollection.title,
                    hostName: nil,
                    processName: nil,
                    startedAt: nil,
                    traceCollection: traceCollection
                )
            ]
        )
    }
}
