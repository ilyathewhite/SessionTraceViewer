//
//  StringDiffUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/2/26.
//

import SwiftUI
import SwiftUIEx
import ReducerArchitecture

private extension StringDiff.PresentationStyle {
    var isInlineEmbedded: Bool {
        self == .inlineEmbedded
    }
}

private struct StringDiffWindowKeyboardShortcuts: View {
    let previousDiffDisabled: Bool
    let nextDiffDisabled: Bool
    let selectPreviousDiff: () -> Void
    let selectNextDiff: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button("Previous Diff", action: selectPreviousDiff)
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(previousDiffDisabled)

            Button("Next Diff", action: selectNextDiff)
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(nextDiffDisabled)
        }
        .buttonStyle(.plain)
        .labelsHidden()
        .accessibilityHidden(true)
        .frame(width: 0, height: 0)
        .opacity(0.001)
    }
}

private struct StringDiffLineCell: View {
    let line: StringDiff.StoreState.DiffLine?
    let presentationStyle: StringDiff.PresentationStyle

    private var displayText: AttributedString {
        guard let line else { return AttributedString(" ") }
        return line.text.characters.isEmpty ? AttributedString(" ") : line.text
    }

    var body: some View {
        Text(displayText)
            .font(
                .system(
                    size: presentationStyle.isInlineEmbedded ? 11 : 12,
                    weight: .regular,
                    design: .monospaced
                )
            )
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, presentationStyle.isInlineEmbedded ? 8 : 12)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(lineBackground)
    }

    private var lineBackground: some View {
        Group {
            if let line {
                line.kind.rowTint
            }
            else {
                ViewerTheme.metricRowBackground
            }
        }
    }
}

private struct StringDiffSectionRows: View {
    let section: StringDiff.StoreState.DiffSection
    let presentationStyle: StringDiff.PresentationStyle

    var body: some View {
        VStack(spacing: 0) {
            ForEach(section.rows) { row in
                HStack(spacing: 0) {
                    StringDiffLineCell(
                        line: row.oldLine,
                        presentationStyle: presentationStyle
                    )
                    Divider()
                    StringDiffLineCell(
                        line: row.newLine,
                        presentationStyle: presentationStyle
                    )
                }
            }
        }
    }
}

private struct StringDiffColumnHeader: View {
    let presentationStyle: StringDiff.PresentationStyle
    let oldTitle: String
    let newTitle: String

    var body: some View {
        HStack(spacing: 0) {
            headerCell(title: oldTitle)
            Divider()
            headerCell(title: newTitle)
        }
        .background(ViewerTheme.metricRowBackground)
    }

    private func headerCell(title: String) -> some View {
        Text(title)
            .font(
                presentationStyle.isInlineEmbedded
                    ? .subheadline.smallCaps().weight(.semibold)
                    : .headline.smallCaps().weight(.semibold)
            )
            .foregroundStyle(ViewerTheme.secondaryText)
            .padding(.horizontal, presentationStyle.isInlineEmbedded ? 8 : 12)
            .padding(.vertical, presentationStyle.isInlineEmbedded ? 5 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StringDiffInlineValueCard: View {
    let title: String
    let text: AttributedString

    private var displayText: AttributedString {
        text.characters.isEmpty ? AttributedString(" ") : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.smallCaps().weight(.semibold))
                .foregroundStyle(ViewerTheme.secondaryText)

            Text(displayText)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
    }
}

private struct StringDiffDocumentSection: View {
    let section: StringDiff.StoreState.DiffSection
    let isSelected: Bool
    let onSelect: () -> Void

    private var borderStroke: Color {
        isSelected ? ViewerTheme.rowSelectedStroke : ViewerTheme.sectionStroke
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    var body: some View {
        StringDiffSectionRows(
            section: section,
            presentationStyle: .standard
        )
        .padding(section.isDiff ? 4 : 0)
        .overlay {
            if section.isDiff {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(borderStroke, lineWidth: borderWidth)
                    .padding(2)
            }
        }
        .padding(.vertical, section.isDiff ? 2 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard section.isDiff else { return }
            onSelect()
        }
    }
}

private struct StringDiffLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("Preparing diff preview...")
                .font(.headline)
                .foregroundStyle(ViewerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ViewerTheme.sectionBackground)
    }
}

private struct StringDiffInlineLoadedView: View {
    let oldTitle: String
    let newTitle: String
    let sections: [StringDiff.StoreState.DiffSection]

    private var oldText: AttributedString {
        combinedText(for: .old)
    }

    private var newText: AttributedString {
        combinedText(for: .new)
    }

    private func combinedText(for side: StringDiff.DiffSide) -> AttributedString {
        let lines = sections
            .flatMap(\.rows)
            .compactMap { row in
                switch side {
                case .old:
                    row.oldLine
                case .new:
                    row.newLine
                }
            }

        var combined = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                combined.append(AttributedString("\n"))
            }
            combined.append(line.text)
        }
        return combined
    }

    var body: some View {
        let verticalPadding: CGFloat = 6
        Group {
            if sections.isEmpty {
                Text("No Differences")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ViewerTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, verticalPadding)
            }
            else {
                HStack(alignment: .top, spacing: 0) {
                    StringDiffInlineValueCard(
                        title: oldTitle,
                        text: oldText
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, verticalPadding)

                    Rectangle()
                        .fill(ViewerTheme.sectionStroke)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)

                    StringDiffInlineValueCard(
                        title: newTitle,
                        text: newText
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, verticalPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct StringDiffWindowLoadedView: View {
    @ObservedObject var store: StringDiff.Store

    @FocusState private var hasKeyboardFocus: Bool

    private var sections: [StringDiff.StoreState.DiffSection] {
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

                            StringDiffColumnHeader(
                                presentationStyle: .standard,
                                oldTitle: store.state.string1Caption,
                                newTitle: store.state.string2Caption
                            )

                            Divider()

                            LazyVStack(spacing: 0) {
                                ForEach(sections) { section in
                                    StringDiffDocumentSection(
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
                        DispatchQueue.main.async {
                            hasKeyboardFocus = true
                            scrollToSelectedDiff(using: proxy, animated: false)
                        }
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
        .onAppear {
            DispatchQueue.main.async {
                hasKeyboardFocus = true
            }
        }
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    hasKeyboardFocus = true
                }
        )
        .overlay(alignment: .topLeading) {
            StringDiffWindowKeyboardShortcuts(
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
                    StringDiffLoadingView()

                case .success(let sections):
                    switch store.state.presentationStyle {
                    case .standard:
                        StringDiffWindowLoadedView(store: store)

                    case .inlineEmbedded:
                        StringDiffInlineLoadedView(
                            oldTitle: store.state.string1Caption,
                            newTitle: store.state.string2Caption,
                            sections: sections
                        )
                    }

                case .failure:
                    StringDiffLoadingView()
                }
            }
            .frame(
                minWidth: store.state.presentationStyle == .inlineEmbedded ? nil : 860,
                minHeight: store.state.presentationStyle == .inlineEmbedded ? nil : 540
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                store.state.presentationStyle == .inlineEmbedded
                    ? Color.clear
                    : ViewerTheme.sectionBackground
            )
            .connectOnAppear {
                store.environment = .init(
                    makeDiffSections: { string1, string2 in
                        Nsp.StoreState.makeSections(string1: string1, string2: string2)
                    }
                )
                store.send(.mutating(.startLoadingIfNeeded))
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
