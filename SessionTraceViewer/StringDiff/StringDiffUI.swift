//
//  StringDiffUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/2/26.
//

import SwiftUI
import ReducerArchitecture
import SwiftUIEx

extension StringDiff: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = StringDiff
        @ObservedObject var store: Store

        init(_ store: Store) {
            self.store = store
        }

        var body: some View {
            Group {
                switch store.state.diffSections {
                case .notStarted, .inProgress:
                    Nsp.LoadingView()

                case .success(let sections):
                    switch store.state.presentationStyle {
                    case .standard:
                        Nsp.WindowLoadedView(store: store)

                    case .inlineEmbedded:
                        Nsp.InlineLoadedView(
                            oldTitle: store.state.string1Caption,
                            newTitle: store.state.string2Caption,
                            sections: sections
                        )
                    }

                case .failure:
                    Nsp.LoadingView()
                }
            }
            .frame(
                minWidth: store.state.presentationStyle.isInlineEmbedded ? nil : 860,
                minHeight: store.state.presentationStyle.isInlineEmbedded ? nil : 540
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                store.state.presentationStyle.isInlineEmbedded
                    ? Color.clear
                    : ViewerTheme.sectionBackground
            )
            .connectOnAppear {
                store.environment = .init(
                    makeDiffSections: Nsp.makeDiffSections
                )
                store.send(.effect(.loadDiffIfNeeded))
            }
        }
    }
}

struct StringDiffWindowView: View {
    @StateObject private var store: StringDiff.Store

    init(input: StringDiff.Input) {
        self._store = StateObject(wrappedValue: StringDiff.windowStore(input: input))
    }

    var body: some View {
        StringDiff.ContentView(store)
            .navigationTitle(store.state.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ViewerTheme.sectionBackground)
    }
}
