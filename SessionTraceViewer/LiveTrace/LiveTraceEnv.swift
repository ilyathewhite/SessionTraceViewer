//
//  LiveTraceEnv.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import Foundation
import ReducerArchitecture

extension LiveTrace {
    @MainActor
    static func liveUpdates(port: UInt16) -> AsyncStream<LiveUpdate> {
        AsyncStream { continuation in
            let server = LiveTraceServer(port: port)
            server.onEnvelope = { envelope in
                continuation.yield(.envelope(envelope))
            }
            server.onStatusChange = { status in
                continuation.yield(.status(status))
            }
            continuation.onTermination = { _ in
                server.stop()
            }
            server.start()
        }
    }
}
