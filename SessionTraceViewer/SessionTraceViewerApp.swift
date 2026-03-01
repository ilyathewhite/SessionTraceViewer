//
//  SessionTraceViewerApp.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI

@main
struct SessionTraceViewerApp: App {
    var body: some Scene {
        DocumentGroup(viewing: SessionTraceDocument.self) { file in
            SessionTraceDocumentView(document: file.document)
        }
    }
}
