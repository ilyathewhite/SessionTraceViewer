//
//  StringDiffWindowLoadedView.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import ReducerArchitecture
import SwiftUI

extension StringDiff {
    struct WindowLoadedView: View {
        @ObservedObject var store: Store

        @FocusState private var hasKeyboardFocus: Bool

        private var sections: [StoreState.DiffSection] {
            store.state.diffSections.value ?? []
        }

        private func scrollToSelectedDiff(using proxy: ScrollViewProxy, animated: Bool = true) {
            guard let selectedDiffID = store.state.selectedDiffID else { return }
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(selectedDiffID, anchor: .center)
                }
            }
            else {
                proxy.scrollTo(selectedDiffID, anchor: .top)
            }
        }

        var body: some View {
            Group {
                if sections.isEmpty {
                    ContentUnavailableView(
                        "No Differences",
                        systemImage: "checkmark.seal",
                        description: Text("These values are identical.")
                    )
                }
                else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            VStack(spacing: 0) {
                                Divider()

                                ColumnHeader(
                                    presentationStyle: .standard,
                                    oldTitle: store.state.string1Caption,
                                    newTitle: store.state.string2Caption
                                )

                                Divider()

                                LazyVStack(spacing: 0) {
                                    ForEach(sections) { section in
                                        DocumentSection(
                                            section: section,
                                            isSelected: store.state.selectedDiffID == section.id,
                                            onSelect: {
                                                store.send(.mutating(.selectDiff(id: section.id)))
                                                hasKeyboardFocus = true
                                            }
                                        )
                                        .id(section.id)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .padding(.vertical, 12)
                        }
                        .onAppear {
                            hasKeyboardFocus = true
                            scrollToSelectedDiff(using: proxy, animated: false)
                        }
                        .onChange(of: store.state.selectedDiffID) { _, _ in
                            scrollToSelectedDiff(using: proxy)
                        }
                    }
                }
            }
            .background(ViewerTheme.sectionBackground)
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($hasKeyboardFocus)
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        hasKeyboardFocus = true
                    }
            )
            .overlay(alignment: .topLeading) {
                WindowKeyboardShortcuts(
                    previousDiffDisabled: store.state.previousDiffDisabled,
                    nextDiffDisabled: store.state.nextDiffDisabled,
                    selectPreviousDiff: {
                        store.send(.mutating(.selectPreviousDiff))
                    },
                    selectNextDiff: {
                        store.send(.mutating(.selectNextDiff))
                    }
                )
            }
        }
    }
}
