//
//  SessionTraceDocumentUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI

struct SessionTraceDocumentView: View {
    let document: SessionTraceDocument
    @StateObject private var store: TraceViewer.Store

    init(document: SessionTraceDocument) {
        self.document = document
        self._store = StateObject(
            wrappedValue: TraceViewer.store(traceCollection: document.traceCollection)
        )
    }

    var body: some View {
        TraceViewer.ContentView(store)
    }
}
