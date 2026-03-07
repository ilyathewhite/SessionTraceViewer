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

        init(_ store: Store) {
            self.store = store
        }

        var body: some View {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
            .frame(minWidth: 1320, minHeight: 900)
            .connectOnAppear {
                store.environment = .init(
                    liveUpdates: Nsp.liveUpdates,
                    syncTraceViewer: Nsp.syncTraceViewer(store: store)
                )
                store.send(.effect(.startListeningIfNeeded))
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
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        }

        @ViewBuilder
        private var detail: some View {
            if let session = store.state.selectedSession {
                Nsp.SessionDetailView(
                    session: session,
                    traceViewerStore: selectedTraceViewerStore
                )
            }
            else {
                ContentUnavailableView(
                    "Waiting For Live Trace",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Enable `store.logConfig.liveTrace` in the traced app and keep SessionTraceViewer open.")
                )
            }
        }

        private var selectedTraceViewerStore: TraceViewer.Store? {
            guard let selectedSessionID = store.state.selectedSessionID else { return nil }
            return store.child(key: selectedSessionID)
        }

        private var sidebarSessions: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.state.sessions) { session in
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

    init(port: UInt16 = SessionTraceLiveDefaults.defaultPort) {
        _store = StateObject(wrappedValue: LiveTrace.store(port: port))
    }

    var body: some View {
        LiveTrace.ContentView(store)
    }
}
