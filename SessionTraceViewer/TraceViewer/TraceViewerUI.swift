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

            let traceViewerListStore = TraceViewerList.store(traceCollection: store.state.traceCollection)
            store.addChildIfNeeded(traceViewerListStore)
            store.addChildIfNeeded(
                TraceViewerGraph.store(
                    traceCollection: store.state.traceCollection,
                    input: traceViewerListStore.state.graphInput
                )
            )
            store.addChildIfNeeded(
                TraceViewerDetails.store(
                    selection: traceViewerListStore.state.eventInspectorSelection
                )
            )
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    ViewerTheme.background
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        traceViewerGraphStore.contentView

                        Divider()

                        scopeBarSection

                        Divider()

                        HStack(spacing: 0) {
                            TraceViewerList.ContentView(
                                traceViewerListStore,
                                moveGraphSelection: moveGraphSelection
                            )
                            .frame(width: timelineListWidth(for: geometry.size.width))
                            .frame(maxHeight: .infinity)

                            Divider()

                            traceViewerDetailsStore.contentView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.borderless)
            .preferredColorScheme(.light)
            .connectOnAppear {
                let parentStore = store
                let traceViewerListStore = traceViewerListStore
                let traceViewerGraphStore = traceViewerGraphStore
                let traceViewerDetailsStore = traceViewerDetailsStore

                traceViewerListStore.bind(to: parentStore, on: \.traceCollectionVersion) { _ in
                    .mutating(.replaceTraceCollection(parentStore.state.traceCollection))
                }

                traceViewerGraphStore.bind(to: parentStore, on: \.traceCollectionVersion) { _ in
                    .mutating(.replaceTraceCollection(parentStore.state.traceCollection))
                }

                traceViewerGraphStore.bind(to: traceViewerListStore, on: \.graphInput) {
                    .mutating(.updateInput($0))
                }

                traceViewerDetailsStore.bind(to: traceViewerListStore, on: \.eventInspectorSelection) {
                    .mutating(.updateSelection($0))
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

        private var traceViewerDetailsStore: TraceViewerDetails.Store {
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

        private var scopeBarSection: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    Nsp.ScopeBarButton(
                        title: "All",
                        isSelected: traceViewerListStore.state.isAllEventKindsSelected,
                        textColor: ViewerTheme.scopeBarAllText,
                        backgroundColor: ViewerTheme.scopeBarAllBackground,
                        strokeColor: ViewerTheme.scopeBarAllStroke
                    ) {
                        traceViewerListStore.send(.mutating(.selectAllEventKinds))
                    }

                    Nsp.ScopeBarButton(
                        title: "User",
                        isSelected: traceViewerListStore.state.isUserEventFilterSelected,
                        textColor: ViewerTheme.scopeBarUserText,
                        backgroundColor: ViewerTheme.scopeBarUserBackground,
                        strokeColor: ViewerTheme.scopeBarUserStroke
                    ) {
                        traceViewerListStore.send(.mutating(.toggleUserEventFilter))
                    }

                    HStack(spacing: 4) {
                        ForEach(traceViewerListStore.state.scopeBarKinds, id: \.self) { kind in
                            Nsp.ScopeBarButton(
                                title: kind.rawValue,
                                isSelected: traceViewerListStore.state.isEventKindSelected(kind),
                                textColor: ViewerTheme.chipText(for: kind),
                                backgroundColor: ViewerTheme.chipBackground(for: kind),
                                strokeColor: ViewerTheme.chipStroke(for: kind)
                            ) {
                                traceViewerListStore.send(.mutating(.toggleEventKindFilter(kind)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ViewerTheme.background)
        }
    }
}
