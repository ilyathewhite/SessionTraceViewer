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
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .viewerInsetPanelStyle()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            ViewerTheme.traceViewerInsetPanelInnerShadow,
                            .clear
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 3)
                    .allowsHitTesting(false)
                }
                .background(ViewerTheme.traceViewerContentBackground)
        }

        private var overviewPanel: some View {
            let presentation = store.state.presentation

            return Nsp.TimelineOverviewView(
                presentation: presentation,
                onSelectNode: { graphNodeID in
                    store.send(.mutating(.selectNode(id: graphNodeID, shouldFocusTimelineList: false)))
                }
            )
        }
    }
}
