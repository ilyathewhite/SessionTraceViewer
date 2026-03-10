//
//  TraceViewerGraphUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import ReducerArchitecture
import SwiftUI

extension TraceViewerGraph: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = TraceViewerGraph
        @ObservedObject var store: Store

        init(_ store: Store) {
            self.store = store
        }

        var body: some View {
            overviewPanel
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(ViewerTheme.overviewAreaBackground)
        }

        private var overviewPanel: some View {
            let presentation = store.state.presentation

            return Nsp.TimelineOverviewView(
                presentation: presentation,
                onSelectNode: { graphNodeID in
                    store.send(.mutating(.selectNode(id: graphNodeID, shouldFocusTimelineList: false)))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)
            .viewerPanelCardStyle()
        }
    }
}
