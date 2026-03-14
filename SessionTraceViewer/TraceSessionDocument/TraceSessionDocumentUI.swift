//
//  TraceSessionDocumentUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import AppKit
import ReducerArchitecture
import SwiftUI

struct TraceSessionDocumentSaveActions {
    let saveTitle: String
    let saveAsTitle: String
    let save: () -> Void
    let saveAs: () -> Void
}

struct TraceSessionDocumentSaveActionsKey: FocusedValueKey {
    typealias Value = TraceSessionDocumentSaveActions
}

extension FocusedValues {
    var traceSessionDocumentSaveActions: TraceSessionDocumentSaveActions? {
        get { self[TraceSessionDocumentSaveActionsKey.self] }
        set { self[TraceSessionDocumentSaveActionsKey.self] = newValue }
    }
}

struct TraceSessionDocumentView: View {
    @Binding private var document: TraceSessionDocument
    private let fileURL: URL?

    @StateObject private var traceViewerStore: TraceViewer.Store
    @StateObject private var recordingController: TraceSessionDocumentRecordingController

    init(
        document: Binding<TraceSessionDocument>,
        fileURL: URL?
    ) {
        _document = document
        self.fileURL = fileURL
        _traceViewerStore = StateObject(
            wrappedValue: TraceViewer.store(traceSession: document.wrappedValue.session)
        )
        _recordingController = StateObject(
            wrappedValue: .init(document: document.wrappedValue)
        )
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(
                    minWidth: 240,
                    idealWidth: 280,
                    maxWidth: 360,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1240, minHeight: 860)
        .focusedSceneValue(
            \.traceSessionDocumentSaveActions,
            saveActions
        )
        .connectOnAppear {
            recordingController.startIfNeeded()
            syncTraceViewer()
        }
        .onChange(of: displaySession) { _, _ in
            syncTraceViewer()
        }
    }

    private var displaySession: TraceSession {
        document.isRecording ? recordingController.session : document.session
    }

    private var hasRecordedStores: Bool {
        !displaySession.storeTraces.isEmpty
    }

    @ViewBuilder
    private var detail: some View {
        if hasRecordedStores {
            TraceViewer.ContentView(traceViewerStore)
        }
        else if document.isRecording {
            ContentUnavailableView(
                "Waiting For Live Trace",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text(waitingDescription)
            )
        }
        else {
            ContentUnavailableView(
                "No Recorded Trace",
                systemImage: "doc.text.magnifyingglass",
                description: Text("This document does not contain any recorded store traces.")
            )
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(traceViewerStore.state.storeLayers) { storeLayer in
                        TraceSessionStoreRow(
                            storeLayer: storeLayer,
                            setVisibility: { isVisible in
                                traceViewerStore.send(
                                    .mutating(
                                        .setStoreVisibility(
                                            id: storeLayer.id,
                                            isVisible: isVisible
                                        )
                                    )
                                )
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .background(ViewerTheme.timelinePanelBackground)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headerTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ViewerTheme.primaryText)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(headerLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(ViewerTheme.secondaryText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            if document.isRecording {
                Button("Stop Recording", action: stopRecording)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ViewerTheme.sectionBackground)
    }

    private var headerTitle: String {
        if hasRecordedStores {
            return displaySession.title
        }
        if document.isRecording {
            return "Recording Trace"
        }
        if let fileURL {
            return fileURL.deletingPathExtension().lastPathComponent
        }
        return "Session Trace"
    }

    private var headerLines: [String] {
        var lines: [String] = []

        if document.isRecording || document.recordingMode == .stopped {
            lines.append(recordingController.statusText)
        }

        if hasRecordedStores {
            lines.append(
                displaySession.storeTraces.count == 1
                    ? "1 store"
                    : "\(displaySession.storeTraces.count) stores"
            )

            if let processName = normalized(displaySession.processName),
               processName != displaySession.title {
                lines.append(processName)
            }

            if let hostName = normalized(displaySession.hostName) {
                lines.append(hostName)
            }
        }

        return lines
    }

    private var waitingDescription: String {
        let configLine: String
        if let port = recordingController.port {
            configLine = "Configure `LiveTraceConfig.shared.port = \(port)`"
        }
        else {
            configLine = "Configure `LiveTraceConfig.shared`"
        }

        return "\(configLine), enable `store.logConfig.liveTraceEnabled = true` in the traced app, and keep this document open."
    }

    private var saveActions: TraceSessionDocumentSaveActions {
        .init(
            saveTitle: document.isRecording ? "Stop Recording and Save" : "Save",
            saveAsTitle: document.isRecording ? "Stop Recording and Save As…" : "Save As…",
            save: {
                performSave(selector: #selector(NSDocument.save(_:)))
            },
            saveAs: {
                performSave(selector: #selector(NSDocument.saveAs(_:)))
            }
        )
    }

    private func performSave(selector: Selector) {
        if document.isRecording {
            stopRecording()
        }
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    private func stopRecording() {
        guard document.isRecording else { return }
        let finalSession = recordingController.stopRecording()
        document.markRecordingStopped(with: finalSession)
        syncTraceViewer()
    }

    private func syncTraceViewer() {
        traceViewerStore.send(
            .mutating(
                .replaceTraceSession(displaySession)
            )
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct TraceSessionStoreRow: View {
    let storeLayer: TraceViewer.StoreLayer
    let setVisibility: (Bool) -> Void

    private var visibilitySymbolName: String {
        storeLayer.isVisible ? "eye" : "eye.slash"
    }

    var body: some View {
        Button(action: {
            setVisibility(!storeLayer.isVisible)
        }) {
            HStack(spacing: 8) {
                Text(storeLayer.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ViewerTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: visibilitySymbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(storeLayer.isVisible ? ViewerTheme.primaryText : ViewerTheme.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(storeLayer.isVisible ? "Hide Store" : "Show Store")
    }
}
