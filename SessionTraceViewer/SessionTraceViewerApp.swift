//
//  SessionTraceViewerApp.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import AppKit
import SwiftUI

@main
struct SessionTraceViewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TraceSessionDocument()) { file in
            TraceSessionDocumentView(
                document: file.$document,
                fileURL: file.fileURL
            )
        }
        .defaultSize(width: 1460, height: 900)
        .commands {
            TraceSessionDocumentCommands()
        }

        WindowGroup("Value", id: EventInspector.valueWindowID, for: EventInspector.ValueWindowInput.self) { input in
            if let input = input.wrappedValue {
                NavigationStack {
                    EventInspector.ValueWindowView(input: input)
                }
            }
            else {
                Color.clear
            }
        }
        .windowResizability(.contentSize)

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

private struct TraceSessionDocumentCommands: Commands {
    @FocusedValue(\.traceSessionDocumentSaveActions) private var saveActions

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button(saveActions?.saveTitle ?? "Save") {
                if let saveActions {
                    saveActions.save()
                }
                else {
                    NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button(saveActions?.saveAsTitle ?? "Save As…") {
                if let saveActions {
                    saveActions.saveAs()
                }
                else {
                    NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("S", modifiers: [.command, .shift])
        }
    }
}
