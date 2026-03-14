//
//  TraceViewerUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import ReducerArchitecture
import SwiftUI

extension TraceViewer: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = TraceViewer
        @ObservedObject var store: Store
        private let timelineListIdealWidth: CGFloat = 420
        private let timelineListMinimumWidth: CGFloat = 220

        init(_ store: Store) {
            self.store = store

            let traceViewerListStore = TraceViewerList.store(viewerData: store.state.viewerData)
            store.addChildIfNeeded(traceViewerListStore)
            store.addChildIfNeeded(
                TraceViewerGraph.store(
                    viewerData: store.state.viewerData,
                    input: traceViewerListStore.state.graphInput
                )
            )
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    ViewerTheme.background
                        .ignoresSafeArea()

                    VisibleStoreContentView(
                        listStore: traceViewerListStore,
                        graphStore: traceViewerGraphStore,
                        timelineListWidth: timelineListWidth(for: geometry.size.width),
                        moveGraphSelection: moveGraphSelection
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.borderless)
            .preferredColorScheme(.light)
            .connectOnAppear {
                let parentStore = store
                let traceViewerListStore = traceViewerListStore
                let traceViewerGraphStore = traceViewerGraphStore
                traceViewerListStore.bind(to: parentStore, on: \.viewerData) {
                    .mutating(.replaceViewerData($0))
                }

                traceViewerGraphStore.bind(to: parentStore, on: \.viewerData) {
                    .mutating(.replaceViewerData($0))
                }

                traceViewerGraphStore.bind(to: traceViewerListStore, on: \.graphInput) {
                    .mutating(.updateInput($0))
                }

                traceViewerListStore.bindPublishedValue(of: traceViewerGraphStore) {
                    .mutating(
                        .selectEvent(
                            id: $0.timelineID,
                            shouldFocus: $0.shouldFocusTimelineList
                        )
                    )
                }
            }
        }

        private func timelineListWidth(for availableWidth: CGFloat) -> CGFloat {
            let preferredWidth = min(
                timelineListIdealWidth,
                max(timelineListMinimumWidth, availableWidth * 0.42)
            )
            return min(max(availableWidth - 1, 0), preferredWidth)
        }

        private var traceViewerListStore: TraceViewerList.Store {
            store.child()!
        }

        private var traceViewerGraphStore: TraceViewerGraph.Store {
            store.child()!
        }

        private var moveGraphSelection: (Int) -> Void {
            { offset in
                traceViewerGraphStore.send(
                    .mutating(
                        .selectAdjacentNode(
                            offset: offset,
                            shouldFocusTimelineList: true
                        )
                    )
                )
            }
        }
    }

    struct VisibleStoreContentView: View {
        @ObservedObject var listStore: TraceViewerList.Store
        @ObservedObject var graphStore: TraceViewerGraph.Store
        let timelineListWidth: CGFloat
        let moveGraphSelection: (Int) -> Void

        var body: some View {
            VStack(spacing: 0) {
                if listStore.state.hasVisibleStores {
                    graphStore.contentView

                    Divider()

                    ScopeBarSectionView(store: listStore)

                    Divider()

                    HStack(spacing: 8) {
                        TraceViewerList.ContentView(
                            listStore,
                            moveGraphSelection: moveGraphSelection
                        )
                        .frame(width: timelineListWidth)
                        .frame(maxHeight: .infinity)

                        TraceViewerDetails.SelectionContentView(
                            selection: listStore.state.eventInspectorSelection
                        )
                        .id(detailsSelectionIdentity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .viewerInsetPanelStyle()
                    .background(ViewerTheme.traceViewerContentBackground)
                }
                else {
                    noVisibleStoresPlaceholder
                }
            }
        }

        private var detailsSelectionIdentity: String {
            let selectedItemID = listStore.state.eventInspectorSelection.item?.id ?? "none"
            let previousStateItemID = listStore.state.eventInspectorSelection.previousStateItem?.id ?? "none"
            return "\(selectedItemID)::\(previousStateItemID)"
        }

        private var noVisibleStoresPlaceholder: some View {
            ContentUnavailableView(
                "No Store Selected",
                systemImage: "eye.slash",
                description: Text("Show a store in the sidebar to inspect its timeline and details.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .viewerInsetPanelStyle()
            .background(ViewerTheme.traceViewerContentBackground)
        }
    }

    struct ScopeBarSectionView: View {
        @ObservedObject var store: TraceViewerList.Store

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    TraceViewer.ScopeBarButton(
                        title: "All",
                        isSelected: store.state.isAllEventKindsSelected,
                        textColor: ViewerTheme.scopeBarAllText,
                        backgroundColor: ViewerTheme.scopeBarAllBackground,
                        strokeColor: ViewerTheme.scopeBarAllStroke
                    ) {
                        store.send(.mutating(.selectAllEventKinds))
                    }

                    TraceViewer.ScopeBarButton(
                        title: "User",
                        isSelected: store.state.isUserEventFilterSelected,
                        textColor: ViewerTheme.scopeBarUserText,
                        backgroundColor: ViewerTheme.scopeBarUserBackground,
                        strokeColor: ViewerTheme.scopeBarUserStroke
                    ) {
                        store.send(.mutating(.toggleUserEventFilter))
                    }

                    HStack(spacing: 4) {
                        ForEach(store.state.scopeBarKinds, id: \.self) { kind in
                            TraceViewer.ScopeBarButton(
                                title: kind.rawValue,
                                isSelected: store.state.isEventKindSelected(kind),
                                textColor: ViewerTheme.chipText(for: kind),
                                backgroundColor: ViewerTheme.chipBackground(for: kind),
                                strokeColor: ViewerTheme.chipStroke(for: kind)
                            ) {
                                store.send(.mutating(.toggleEventKindFilter(kind)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ViewerTheme.traceViewerScopeBarBackground)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(ViewerTheme.sectionStroke)
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}
