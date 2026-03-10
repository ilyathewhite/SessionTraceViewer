//
//  TraceViewerListUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import ReducerArchitecture
import SwiftUI

extension TraceViewerList: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = TraceViewerList
        @ObservedObject var store: Store
        @Namespace private var timelineFocusScope
        @State private var timelineListScrollCoordinator = TimelineListScrollCoordinator()
        @FocusState private var timelineListHasFocus: Bool
        @Environment(\.controlActiveState) private var controlActiveState
        @Environment(\.resetFocus) private var resetFocus

        private let moveGraphSelection: ((Int) -> Void)?

        init(_ store: Store) {
            self.init(store, moveGraphSelection: nil)
        }

        init(_ store: Store, moveGraphSelection: ((Int) -> Void)?) {
            self.store = store
            self.moveGraphSelection = moveGraphSelection
        }

        var body: some View {
            timelineListPanel
                .background(ViewerTheme.timelinePanelBackground)
                .connectOnAppear {
                    let timelineListScrollCoordinator = timelineListScrollCoordinator
                    store.environment = .init(
                        resetTimelineListFocus: {
                            resetFocus(in: timelineFocusScope)
                        },
                        scrollTimelineListToID: { id in
                            timelineListScrollCoordinator.scroll(to: id)
                        }
                    )
                }
        }

        private var selectionIsFocused: Bool {
            timelineListHasFocus && controlActiveState == .key
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
                                store.send(.mutating(.selectEvent(id: item.id, shouldFocus: true)))
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
        }

        private func handleMove(_ direction: MoveCommandDirection) {
            guard timelineListHasFocus else { return }
            switch direction {
            case .up:
                store.send(.mutating(.selectPreviousVisible))
            case .down:
                store.send(.mutating(.selectNextVisible))
            case .left:
                moveGraphSelection?(-1)
            case .right:
                moveGraphSelection?(1)
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
