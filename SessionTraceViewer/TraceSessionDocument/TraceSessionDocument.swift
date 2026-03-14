//
//  TraceSessionDocument.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import Darwin
import SwiftUI
import UniformTypeIdentifiers
import ReducerArchitecture

extension UTType {
    static var sessionTraceLZMA: UTType {
        UTType(filenameExtension: "lzma") ?? .data
    }
}

struct TraceSessionDocument: FileDocument {
    enum RecordingMode: Equatable {
        case recording(preferredPort: UInt16)
        case stopped
        case staticTrace
    }

    static var readableContentTypes: [UTType] {
        [.sessionTraceLZMA, .data]
    }

    var session: TraceSession
    var recordingMode: RecordingMode

    init(
        session: TraceSession = .empty(),
        recordingMode: RecordingMode = .recording(preferredPort: LiveTraceDefaults.defaultPort)
    ) {
        self.session = session
        self.recordingMode = recordingMode
    }

    init(loadedSession session: TraceSession) {
        self.init(
            session: session,
            recordingMode: .staticTrace
        )
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.init(loadedSession: try TraceSession(fileData: data))
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(session)
        return .init(regularFileWithContents: data)
    }

    var isRecording: Bool {
        guard case .recording = recordingMode else { return false }
        return true
    }

    mutating func markRecordingStopped(with session: TraceSession) {
        self.session = session
        recordingMode = .stopped
    }
}

extension TraceSession {
    static func empty(
        title: String = "Recording Trace",
        sessionID: String = "recording.pending.session"
    ) -> TraceSession {
        .init(
            sessionID: sessionID,
            title: title,
            hostName: nil,
            processName: nil,
            startedAt: nil,
            storeTraces: []
        )
    }

    static func placeholder(
        title: String = "Session Trace",
        sessionID: String = "placeholder.session"
    ) -> TraceSession {
        let storeInstanceID = "\(sessionID).store"
        return .init(
            sessionID: sessionID,
            title: title,
            hostName: nil,
            processName: nil,
            startedAt: nil,
            storeTraces: [
                .init(
                    storeInstanceID: storeInstanceID,
                    storeName: "Store Trace",
                    hostName: nil,
                    processName: nil,
                    startedAt: nil,
                    traceCollection: .placeholder(
                        title: "Store Trace",
                        storeInstanceID: storeInstanceID
                    )
                )
            ]
        )
    }
}

@MainActor
final class TraceSessionDocumentRecordingController: ObservableObject {
    enum Lifecycle: Equatable {
        case inactive
        case starting(UInt16)
        case listening(UInt16)
        case stopped(UInt16?)
        case failed(String)
    }

    @Published private(set) var session: TraceSession
    @Published private(set) var lifecycle: Lifecycle

    private let preferredPort: UInt16?
    private var hasStarted = false
    private var server: LiveTraceServer?
    private var activeSessionID: String?
    private var accumulator: LiveTraceSessionAccumulator?

    init(document: TraceSessionDocument) {
        session = document.session
        switch document.recordingMode {
        case .recording(let preferredPort):
            self.preferredPort = preferredPort
            lifecycle = .inactive
        case .stopped, .staticTrace:
            self.preferredPort = nil
            lifecycle = .stopped(nil)
        }
    }

    deinit {
        server?.stop()
    }

    var statusText: String {
        switch lifecycle {
        case .inactive:
            return "Preparing live trace listener"
        case .starting(let port):
            return "Starting listener on \(LiveTraceDefaults.defaultHost):\(port)"
        case .listening(let port):
            return "Listening on \(LiveTraceDefaults.defaultHost):\(port)"
        case .stopped(let port):
            if let port {
                return "Recording stopped. Port \(port) is now available."
            }
            return "Recording stopped"
        case .failed(let message):
            return message
        }
    }

    var port: UInt16? {
        switch lifecycle {
        case .starting(let port), .listening(let port), .stopped(let port?):
            return port
        case .inactive, .stopped(nil), .failed:
            return nil
        }
    }

    func startIfNeeded() {
        guard !hasStarted,
              let preferredPort else {
            return
        }
        hasStarted = true

        do {
            let port = try Self.firstAvailablePort(startingAt: preferredPort)
            let server = LiveTraceServer(port: port)
            server.onStatusChange = { [weak self] status in
                self?.handle(status: status)
            }
            server.onEnvelope = { [weak self] envelope in
                self?.receive(envelope)
            }
            self.server = server
            lifecycle = .starting(port)
            server.start()
        }
        catch {
            lifecycle = .failed(error.localizedDescription)
        }
    }

    func stopRecording() -> TraceSession {
        if case .listening(let port) = lifecycle {
            server?.stop()
            server = nil
            lifecycle = .stopped(port)
        }
        else if case .starting(let port) = lifecycle {
            server?.stop()
            server = nil
            lifecycle = .stopped(port)
        }
        else if case .failed = lifecycle {
            lifecycle = .stopped(nil)
        }
        return session
    }

    private func handle(status: LiveTraceServer.Status) {
        switch status {
        case .starting(let port):
            lifecycle = .starting(port)
        case .listening(let port):
            lifecycle = .listening(port)
        case .failed(let message):
            lifecycle = .failed(message)
            server = nil
        }
    }

    private func receive(_ envelope: LiveTraceEnvelope) {
        if let activeSessionID, envelope.sessionID != activeSessionID {
            return
        }

        if activeSessionID == nil {
            activeSessionID = envelope.sessionID
            accumulator = .init(
                title: session.title,
                sessionID: envelope.sessionID
            )
        }

        accumulator?.apply(envelope)
        if let session = accumulator?.session {
            self.session = session
        }
    }

    private static func firstAvailablePort(startingAt port: UInt16) throws -> UInt16 {
        for candidate in Int(port)...Int(UInt16.max) {
            let candidatePort = UInt16(candidate)
            if canBind(to: candidatePort) {
                return candidatePort
            }
        }

        throw NSError(
            domain: "SessionTraceViewer.TraceSessionDocument",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No available live trace ports were found starting at \(port)."]
        )
    }

    private static func canBind(to port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(
                    descriptor,
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }

        return result == 0
    }
}

extension SessionTraceCollection {
    static func placeholder(
        title: String = "Session Trace",
        storeInstanceID: String = "placeholder.store"
    ) -> SessionTraceCollection {
        .init(
            title: title,
            sessionGraph: .init(
                storeInstanceID: .init(rawValue: storeInstanceID),
                nodes: [],
                edges: []
            )
        )
    }
}
