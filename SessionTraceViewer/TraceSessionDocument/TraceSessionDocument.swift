//
//  TraceSessionDocument.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI
import UniformTypeIdentifiers
import ReducerArchitecture

extension UTType {
    static var sessionTraceLZMA: UTType {
        UTType(filenameExtension: "lzma") ?? .data
    }
}

struct TraceSessionDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.sessionTraceLZMA, .data]
    }

    var session: TraceSession

    init(session: TraceSession = .placeholder()) {
        self.session = session
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        session = try TraceSession(fileData: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(session)
        return .init(regularFileWithContents: data)
    }
}

extension TraceSession {
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
