//
//  LiveTraceServer.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 3/3/26.
//

import Foundation
import Network
import ReducerArchitecture

final class LiveTraceServer {
    enum Status: Equatable, Sendable {
        case starting(UInt16)
        case listening(UInt16)
        case failed(String)

        var description: String {
            switch self {
            case .starting(let port):
                return "Starting listener on \(SessionTraceLiveDefaults.defaultHost):\(port)"
            case .listening(let port):
                return "Listening on \(SessionTraceLiveDefaults.defaultHost):\(port)"
            case .failed(let message):
                return message
            }
        }
    }

    var onEnvelope: ((SessionTraceLiveEnvelope) -> Void)?
    var onStatusChange: ((Status) -> Void)?

    private let port: UInt16
    private let queue = DispatchQueue(label: "SessionTraceViewer.LiveTraceServer")
    private var listener: NWListener?
    private var connections: [UUID: ConnectionHandler] = [:]

    init(port: UInt16 = SessionTraceLiveDefaults.defaultPort) {
        self.port = port
    }

    func start() {
        guard listener == nil else { return }
        updateStatus(.starting(port))
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            updateStatus(.failed("Invalid live trace port \(port)"))
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.stateUpdateHandler = { [weak self] state in
                self?.handle(state: state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        }
        catch {
            updateStatus(.failed("Failed to start live trace listener: \(error.localizedDescription)"))
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
        }
    }

    private func handle(state: NWListener.State) {
        switch state {
        case .ready:
            updateStatus(.listening(port))
        case .failed(let error):
            updateStatus(.failed("Live trace listener failed: \(error.localizedDescription)"))
        case .cancelled:
            break
        case .setup, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let handler = ConnectionHandler(
            connection: connection,
            onEnvelope: { [weak self] envelope in
                self?.publish(envelope)
            },
            onClose: { [weak self] id in
                self?.queue.async {
                    self?.connections.removeValue(forKey: id)
                }
            }
        )
        connections[handler.id] = handler
        handler.start(on: queue)
    }

    private func publish(_ envelope: SessionTraceLiveEnvelope) {
        Task { @MainActor [weak self] in
            self?.onEnvelope?(envelope)
        }
    }

    private func updateStatus(_ status: Status) {
        Task { @MainActor [weak self] in
            self?.onStatusChange?(status)
        }
    }
}

private final class ConnectionHandler {
    let id = UUID()

    private let connection: NWConnection
    private let onEnvelope: (SessionTraceLiveEnvelope) -> Void
    private let onClose: (UUID) -> Void
    private var buffer = Data()

    init(
        connection: NWConnection,
        onEnvelope: @escaping (SessionTraceLiveEnvelope) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.connection = connection
        self.onEnvelope = onEnvelope
        self.onClose = onClose
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state: state)
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    private func handle(state: NWConnection.State) {
        switch state {
        case .ready:
            receiveNextChunk()
        case .failed, .cancelled:
            onClose(id)
        case .setup, .preparing, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func receiveNextChunk() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.consumeBuffer()
            }

            if isComplete || error != nil {
                self.onClose(self.id)
                return
            }

            self.receiveNextChunk()
        }
    }

    private func consumeBuffer() {
        while let line = buffer.consumeLine() {
            guard !line.isEmpty else { continue }
            do {
                let envelope = try JSONDecoder().decode(SessionTraceLiveEnvelope.self, from: line)
                onEnvelope(envelope)
            }
            catch {
                continue
            }
        }
    }
}

private extension Data {
    mutating func consumeLine() -> Data? {
        guard let lineBreakIndex = firstIndex(of: 0x0A) else { return nil }
        let line = Data(prefix(upTo: lineBreakIndex))
        removeSubrange(startIndex...lineBreakIndex)
        return line
    }
}
