//
//  SessionTraceDocument.swift
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

struct SessionTraceDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.sessionTraceLZMA, .data]
    }

    var traceCollection: SessionTraceCollection

    init(traceCollection: SessionTraceCollection = .placeholder) {
        self.traceCollection = traceCollection
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        traceCollection = try SessionTraceCollection(fileData: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(traceCollection)
        return .init(regularFileWithContents: data)
    }
}

private extension SessionTraceCollection {
    static var placeholder: SessionTraceCollection {
        .init(
            title: "Session Trace",
            sessionGraph: .init(
                storeInstanceID: "placeholder.s0",
                nodes: [],
                edges: []
            )
        )
    }
}
