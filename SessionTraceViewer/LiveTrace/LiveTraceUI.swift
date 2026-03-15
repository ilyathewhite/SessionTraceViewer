//
//  LiveTraceUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 3/3/26.
//

import ReducerArchitecture
import SwiftUI

extension LiveTrace: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = LiveTrace
        @ObservedObject var store: Store
        @FocusState private var sidebarHasFocus: Bool
        @Environment(\.controlActiveState) private var controlActiveState
        @State private var exportDocument = TraceSessionDocument()
        @State private var exportDefaultFilename = "TraceSession"
        @State private var isExportingSession = false
        @State private var exportErrorMessage: String?

        init(_ store: Store) {
            self.store = store
            store.addChildIfNeeded(
                TraceViewer.store(
                    traceSession: store.state.selectedSession?.traceSession
                        ?? .placeholder(
                            title: "Live Trace",
                            sessionID: "live-trace.placeholder.session"
                        )
                )
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
            .frame(minWidth: 1460, minHeight: 900)
            .connectOnAppear {
                let traceViewerStore = traceViewerStore
                store.environment = .init(
                    liveUpdates: Nsp.liveUpdates,
                    syncTraceViewer: { [weak traceViewerStore] traceSession in
                        traceViewerStore?.send(.mutating(.replaceTraceSession(traceSession)))
                    }
                )
                store.send(.effect(.startListeningIfNeeded))
            }
            .fileExporter(
                isPresented: $isExportingSession,
                document: exportDocument,
                contentType: .sessionTraceLZMA,
                defaultFilename: exportDefaultFilename
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .alert(
                "Unable to Save Session",
                isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            exportErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    exportErrorMessage = nil
                }
            } message: {
                Text(exportErrorMessage ?? "")
            }
        }

        private var sidebar: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Traces")
                        .font(.headline)
                    Text(store.state.serverStatus.description)
                        .font(.caption)
                        .foregroundStyle(ViewerTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ViewerTheme.sectionBackground)

                Divider()

                sidebarSessions
            }
        }

        @ViewBuilder
        private var detail: some View {
            if let session = store.state.selectedSession {
                Nsp.SessionDetailView(
                    session: session,
                    traceViewerStore: traceViewerStore,
                    saveSession: {
                        exportDocument = .init(session: session.traceSession)
                        exportDefaultFilename = session.exportFilename
                        isExportingSession = true
                    }
                )
            }
            else {
                ContentUnavailableView(
                    "Waiting For Live Trace",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Configure `LiveTraceConfig.shared`, set `LiveTraceConfig.shared.traceAllStores = true` or enable `store.logConfig.liveTraceEnabled = .selfAndChildren` in the traced app, and keep SessionTraceViewer open.")
                )
            }
        }

        private var traceViewerStore: TraceViewer.Store {
            store.child()!
        }

        private var sidebarSessions: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.state.sessions) { session in
                            VStack(spacing: 0) {
                                Nsp.SessionRow(
                                    session: session,
                                    isSelected: session.id == store.state.selectedSessionID,
                                    selectionIsFocused: sidebarSelectionIsFocused
                                )
                                .id(session.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.send(.mutating(.selectSession(id: session.id)))
                                    sidebarHasFocus = true
                                }

                                if session.id == store.state.selectedSessionID {
                                    SessionStoreLayersView(traceViewerStore: traceViewerStore)
                                        .padding(.leading, 18)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(ViewerTheme.timelinePanelBackground)
                .focusable()
                .focusEffectDisabled()
                .focused($sidebarHasFocus)
                .onAppear {
                    scrollToSelected(using: proxy, animated: false)
                }
                .onChange(of: store.state.selectedSessionID) { _, _ in
                    scrollToSelected(using: proxy)
                }
                .onMoveCommand(perform: handleSidebarMove)
            }
        }

        private var sidebarSelectionIsFocused: Bool {
            sidebarHasFocus && controlActiveState == .key
        }

        private func scrollToSelected(using proxy: ScrollViewProxy, animated: Bool = true) {
            guard let selectedSessionID = store.state.selectedSessionID else { return }
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(selectedSessionID, anchor: .center)
                }
            }
            else {
                proxy.scrollTo(selectedSessionID, anchor: .center)
            }
        }

        private func handleSidebarMove(_ direction: MoveCommandDirection) {
            guard sidebarHasFocus else { return }
            switch direction {
            case .up:
                store.send(.mutating(.selectPreviousSession))
            case .down:
                store.send(.mutating(.selectNextSession))
            default:
                break
            }
        }
    }
}

struct LiveTraceWindowView: View {
    @StateObject private var store: LiveTrace.Store

    init(port: UInt16 = LiveTraceDefaults.defaultPort) {
        _store = StateObject(wrappedValue: LiveTrace.store(port: port))
    }

    var body: some View {
        LiveTrace.ContentView(store)
    }
}

private struct SessionStoreLayersView: View {
    @ObservedObject var traceViewerStore: TraceViewer.Store

    var body: some View {
        TraceViewer.StoreLayersOutlineView(
            store: traceViewerStore,
            rowVerticalPadding: 3
        )
    }
}
