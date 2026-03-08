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
        @Namespace private var timelineFocusScope
        @State private var timelineListScrollCoordinator = TimelineListScrollCoordinator()
        @FocusState private var timelineListHasFocus: Bool
        @Environment(\.controlActiveState) private var controlActiveState
        @Environment(\.resetFocus) private var resetFocus
        private let timelineListIdealWidth: CGFloat = 420
        private let timelineListMinimumWidth: CGFloat = 220

        init(_ store: Store) {
            self.store = store

            store.addChildIfNeeded(
                EventInspector.store(
                    selection: store.state.eventInspectorSelection
                )
            )
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    ViewerTheme.background
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        overviewSection

                        Divider()

                        scopeBarSection

                        Divider()

                        HStack(spacing: 0) {
                            timelineListPanel
                                .frame(width: timelineListWidth(for: geometry.size.width))
                                .frame(maxHeight: .infinity)

                            Divider()

                            inspectorPanel
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
                let timelineListScrollCoordinator = timelineListScrollCoordinator
                let eventInspectorStore = eventInspectorStore
                store.environment = .init(
                    resetTimelineListFocus: {
                        resetFocus(in: timelineFocusScope)
                    },
                    scrollTimelineListToID: { id in
                        timelineListScrollCoordinator.scroll(to: id)
                    },
                    syncEventInspectorSelection: { selection in
                        eventInspectorStore.send(.mutating(.updateSelection(selection)))
                    }
                )
            }
        }

        private func timelineListWidth(for availableWidth: CGFloat) -> CGFloat {
            let preferredWidth = min(
                timelineListIdealWidth,
                max(timelineListMinimumWidth, availableWidth * 0.42)
            )
            return min(max(availableWidth - 1, 0), preferredWidth)
        }

        private var selectionIsFocused: Bool {
            timelineListHasFocus && controlActiveState == .key
        }

        private var eventInspectorStore: EventInspector.Store {
            store.child()!
        }

        private var overviewPanel: some View {
            Nsp.TimelineOverviewView(
                nodes: store.state.visibleOverviewGraphNodes,
                selectableNodeIDs: store.state.selectableVisibleOverviewGraphNodeIDs,
                tooltipTextByNodeID: store.state.itemsByID.mapValues(\.title),
                selectedNodeID: store.state.selectedOverviewGraphNodeID,
                maxLane: store.state.overviewGraphMaxLane,
                onSelectNode: { graphNodeID in
                    guard let timelineID = store.state.timelineSelectionID(forOverviewGraphNodeID: graphNodeID) else {
                        return
                    }
                    store.send(.mutating(.selectEvent(id: timelineID)))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)
            .viewerPanelCardStyle()
        }

        private var overviewSection: some View {
            overviewPanel
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(ViewerTheme.overviewAreaBackground)
        }

        private var scopeBarSection: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    Nsp.ScopeBarButton(
                        title: "All",
                        isSelected: store.state.isAllEventKindsSelected,
                        tint: ViewerTheme.secondaryText,
                        isNeutral: true
                    ) {
                        store.send(.mutating(.selectAllEventKinds))
                    }

                    Nsp.ScopeBarButton(
                        title: "User",
                        isSelected: store.state.isUserEventFilterSelected,
                        tint: ViewerTheme.secondaryText,
                        isNeutral: false
                    ) {
                        store.send(.mutating(.toggleUserEventFilter))
                    }

                    HStack(spacing: 4) {
                        ForEach(store.state.scopeBarKinds, id: \.self) { kind in
                            Nsp.ScopeBarButton(
                                title: kind.rawValue,
                                isSelected: store.state.isEventKindSelected(kind),
                                tint: ViewerTheme.color(for: kind),
                                isNeutral: false
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
            .background(ViewerTheme.background)
        }

        private var timelineListPanel: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(store.state.visibleItems) { item in
                            TimelineEventRow(
                                item: item,
                                isSelectable: store.state.isSelectableTimelineID(item.id),
                                isSelected: item.id == store.state.selectedID,
                                selectionIsFocused: selectionIsFocused
                            )
                            .id(item.id)
                            .onTapGesture {
                                store.send(.mutating(.selectEvent(id: item.id)))
                            }
                        }
                    }
                    .padding(10)
                }
                .contentShape(Rectangle())
                .focusable(true, interactions: .edit)
                .focusEffectDisabled()
                .focused($timelineListHasFocus)
                .focusScope(timelineFocusScope)
                .prefersDefaultFocus(true, in: timelineFocusScope)
                .onMoveCommand(perform: handleMove)
                .onAppear {
                    timelineListScrollCoordinator.install(proxy: proxy)
                }
                .onDisappear {
                    timelineListScrollCoordinator.clear()
                }
            }
            .background(ViewerTheme.timelinePanelBackground)
        }

        private var inspectorPanel: some View {
            eventInspectorStore.contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ViewerTheme.inspectorPanelBackground)
        }

        private func handleMove(_ direction: MoveCommandDirection) {
            guard timelineListHasFocus else { return }
            switch direction {
            case .up:
                store.send(.mutating(.selectPreviousVisible))
            case .down:
                store.send(.mutating(.selectNextVisible))
            case .left:
                store.send(.mutating(.selectPreviousGraphNode))
            case .right:
                store.send(.mutating(.selectNextGraphNode))
            default:
                break
            }
        }
    }
}

@MainActor
private final class TimelineListScrollCoordinator {
    private var scrollToID: ((String) -> Void)?

    func install(proxy: ScrollViewProxy) {
        scrollToID = { id in
            withAnimation {
                proxy.scrollTo(id)
            }
        }
    }

    func clear() {
        scrollToID = nil
    }

    func scroll(to id: String) {
        scrollToID?(id)
    }
}
