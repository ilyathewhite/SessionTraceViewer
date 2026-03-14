//
//  TraceViewerDetailsUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import ReducerArchitecture
import SwiftUI

extension TraceViewerDetails: StoreUINamespace {
    struct SelectionContentView: View {
        let selection: EventInspector.Selection
        @StateObject private var eventInspectorStore: EventInspector.Store

        init(selection: EventInspector.Selection) {
            self.selection = selection
            _eventInspectorStore = StateObject(
                wrappedValue: EventInspector.store(selection: selection)
            )
        }

        var body: some View {
            eventInspectorStore.contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: selection) { _, newSelection in
                    eventInspectorStore.send(.mutating(.updateSelection(newSelection)))
                }
        }
    }

    struct ContentView: StoreContentView {
        typealias Nsp = TraceViewerDetails
        @ObservedObject var store: Store

        init(_ store: Store) {
            self.store = store
            store.addChildIfNeeded(
                EventInspector.store(selection: store.state.selection)
            )
        }

        var body: some View {
            eventInspectorStore.contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .connectOnAppear {
                    let eventInspectorStore = eventInspectorStore
                    eventInspectorStore.bind(to: store, on: \.selection) {
                        .mutating(.updateSelection($0))
                    }
                }
        }

        private var eventInspectorStore: EventInspector.Store {
            store.child()!
        }
    }
}
