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
        let syncTraceViewer: @MainActor (_ traceSession: TraceSession) -> Void
    }

    enum MutatingAction {
        case markListeningStarted
        case selectSession(id: String)
        case selectPreviousSession
        case selectNextSession
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
            fileprivate var accumulator: LiveTraceSessionAccumulator
            private(set) var traceSession: TraceSession
            private(set) var title: String
            private(set) var subtitleLines: [String]
            private(set) var startedAt: Date?
            private(set) var storeTraces: [TraceSession.StoreTrace]
            private(set) var completedAt: Date?
            private(set) var statusText: String
            private(set) var exportFilename: String
            private(set) var startedAtText: String?

            init(sessionID: String) {
                let accumulator = LiveTraceSessionAccumulator(
                    title: "Live Trace",
                    sessionID: sessionID
                )
                self.id = sessionID
                self.lastUpdatedAt = .now
                self.accumulator = accumulator
                self.traceSession = accumulator.session
                self.title = accumulator.session.title
                self.subtitleLines = LiveTrace.sessionSubtitleLines(
                    session: accumulator.session,
                    fallback: sessionID
                )
                self.startedAt = accumulator.session.startedAt
                self.storeTraces = accumulator.session.storeTraces
                self.completedAt = nil
                self.statusText = ""
                self.exportFilename = ""
                self.startedAtText = nil
                refreshDerivedDisplayValues()
            }

            mutating func apply(_ envelope: LiveTraceEnvelope) {
                accumulator.apply(envelope)
                lastUpdatedAt = accumulator.lastUpdatedAt
                refreshDerivedDisplayValues()
            }

            private mutating func refreshDerivedDisplayValues() {
                traceSession = accumulator.session
                title = traceSession.title
                subtitleLines = LiveTrace.sessionSubtitleLines(
                    session: traceSession,
                    fallback: id
                )
                startedAt = traceSession.startedAt
                storeTraces = traceSession.storeTraces
                completedAt = Self.completedAt(for: storeTraces)
                statusText = Self.statusText(
                    completedAt: completedAt,
                    lastUpdatedAt: lastUpdatedAt
                )
                exportFilename = Self.exportFilename(
                    title: title,
                    startedAt: startedAt,
                    sessionID: id
                )
                startedAtText = startedAt.map {
                    "Started \($0.formatted(date: .abbreviated, time: .standard))"
                }
            }

            private static func completedAt(
                for storeTraces: [TraceSession.StoreTrace]
            ) -> Date? {
                let endedAtValues = storeTraces.compactMap(\.endedAt)
                guard !storeTraces.isEmpty, endedAtValues.count == storeTraces.count else {
                    return nil
                }
                return endedAtValues.max()
            }

            private static func statusText(
                completedAt: Date?,
                lastUpdatedAt: Date
            ) -> String {
                if let completedAt {
                    return "Completed \(completedAt.formatted(date: .omitted, time: .standard))"
                }
                return "Updated \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
            }

            private static func exportFilename(
                title: String,
                startedAt: Date?,
                sessionID: String
            ) -> String {
                let baseTitle = LiveTrace.sanitizedExportFilenameComponent(
                    title,
                    fallback: "TraceSession"
                )
                let suffix = if let startedAt {
                    LiveTrace.exportFilenameTimestamp(startedAt)
                } else {
                    LiveTrace.sanitizedExportFilenameComponent(
                        sessionID,
                        fallback: "session"
                    )
                }
                return "\(baseTitle)-\(suffix)"
            }
        }

        let port: UInt16
        var isListening = false
        var selectedSessionID: String?
        var serverStatus: LiveTraceServer.Status
        private(set) var sessionsByID: [String: Session]
        private(set) var sessions: [Session]
        private(set) var selectedSession: Session?

        init(port: UInt16 = LiveTraceDefaults.defaultPort) {
            self.port = port
            self.serverStatus = .starting(port)
            self.sessionsByID = [:]
            self.sessions = []
            self.selectedSession = nil
        }

        mutating func selectSession(id: String) {
            guard sessionsByID[id] != nil else { return }
            selectedSessionID = id
            refreshSelectedSession()
        }

        mutating func selectRelativeSession(offset: Int) {
            let sessions = sessions
            guard !sessions.isEmpty else {
                selectedSessionID = nil
                refreshSelectedSession()
                return
            }

            guard let selectedSessionID,
                  let currentIndex = sessions.firstIndex(where: { $0.id == selectedSessionID }) else {
                self.selectedSessionID = sessions.first?.id
                refreshSelectedSession()
                return
            }

            let nextIndex = min(
                max(currentIndex + offset, 0),
                sessions.count - 1
            )
            self.selectedSessionID = sessions[nextIndex].id
            refreshSelectedSession()
        }

        mutating func updateServerStatus(_ status: LiveTraceServer.Status) {
            serverStatus = status
        }

        mutating func receiveEnvelope(_ envelope: LiveTraceEnvelope) {
            var session = sessionsByID[envelope.sessionID] ?? .init(sessionID: envelope.sessionID)
            session.apply(envelope)
            sessionsByID[session.id] = session
            refreshSessions()
            normalizeSelectedSession()
        }

        private mutating func normalizeSelectedSession() {
            if selectedSessionID == nil || sessionsByID[selectedSessionID ?? ""] == nil {
                selectedSessionID = sessions.first?.id
            }
            refreshSelectedSession()
        }

        private mutating func refreshSessions() {
            sessions = sessionsByID.values.sorted { lhs, rhs in
                if lhs.lastUpdatedAt == rhs.lastUpdatedAt {
                    return lhs.id < rhs.id
                }
                return lhs.lastUpdatedAt > rhs.lastUpdatedAt
            }
        }

        private mutating func refreshSelectedSession() {
            guard let selectedSessionID else {
                selectedSession = nil
                return
            }
            selectedSession = sessionsByID[selectedSessionID]
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
                if state.selectedSession != nil {
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
            guard let traceSession = state.selectedSession?.traceSession else { return .none }
            env.syncTraceViewer(traceSession)
            return .none
        }
    }
}

extension LiveTrace {
    fileprivate static func exportFilenameTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }

    fileprivate static func sanitizedExportFilenameComponent(
        _ value: String?,
        fallback: String
    ) -> String {
        guard let value = normalized(value) else { return fallback }
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = value.components(separatedBy: invalidCharacters).joined(separator: "-")
        let collapsedWhitespace = sanitized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return collapsedWhitespace.isEmpty ? fallback : collapsedWhitespace
    }

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
