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

        WindowGroup("Value Diff", id: StringDiff.windowID, for: StringDiff.Input.self) { input in
            if let input = input.wrappedValue {
                NavigationStack {
                    StringDiffWindowView(input: input)
                }
            }
            else {
                Color.clear
            }
        }
        .defaultSize(width: 960, height: 620)
    }
}
