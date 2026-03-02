//
//  StringDiffUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/2/26.
//

import SwiftUI

import ReducerArchitecture

private struct StringDiffColumnView: View {
    let presentationStyle: StringDiff.PresentationStyle
    let title: String
    let string: AttributedString

    private var isInlineEmbedded: Bool {
        presentationStyle == .inlineEmbedded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isInlineEmbedded ? 4 : 10) {
            header
            codeText
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, isInlineEmbedded ? 8 : 16)
        .padding(.vertical, isInlineEmbedded ? 6 : 14)
    }

    private var header: some View {
        Text(title)
            .font(
                isInlineEmbedded
                    ? .footnote.smallCaps().weight(.semibold)
                    : .title3.smallCaps().weight(.bold)
            )
            .foregroundStyle(isInlineEmbedded ? ViewerTheme.secondaryText : ViewerTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var codeText: some View {
        Text(string)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension StringDiff: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = StringDiff
        @ObservedObject var store: Store

        init(_ store: Store) {
            self.store = store
        }

        private var isInlineEmbedded: Bool {
            store.state.presentationStyle == .inlineEmbedded
        }

        var body: some View {
            Group {
                if isInlineEmbedded {
                    diffContent
                }
                else {
                    windowDiffContent
                }
            }
            .frame(
                minWidth: isInlineEmbedded ? nil : 860,
                minHeight: isInlineEmbedded ? nil : 540
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isInlineEmbedded ? Color.clear : ViewerTheme.sectionBackground)
        }

        private var diffContent: some View {
            HStack(spacing: 0) {
                StringDiffColumnView(
                    presentationStyle: store.state.presentationStyle,
                    title: store.state.string1Caption,
                    string: store.state.string1
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                StringDiffColumnView(
                    presentationStyle: store.state.presentationStyle,
                    title: store.state.string2Caption,
                    string: store.state.string2
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        private var windowDiffContent: some View {
            ScrollView(.vertical) {
                diffContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(ViewerTheme.sectionBackground)
        }
    }
}

struct StringDiffWindowView: View {
    let request: StringDiff.WindowRequest

    var body: some View {
        StringDiff.ContentView(StringDiff.store(windowRequest: request))
            .navigationTitle(request.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ViewerTheme.sectionBackground)
    }
}
