//
//  StringDiffUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/2/26.
//

import SwiftUI

import ReducerArchitecture

private struct StringDiffLineCell: View {
    let line: StringDiff.StoreState.DiffLine?
    let presentationStyle: StringDiff.PresentationStyle

    private var isInlineEmbedded: Bool {
        presentationStyle == .inlineEmbedded
    }

    private var displayText: AttributedString {
        guard let line else { return AttributedString(" ") }
        return line.text.characters.isEmpty ? AttributedString(" ") : line.text
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: isInlineEmbedded ? 11 : 12, weight: .regular, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isInlineEmbedded ? 8 : 12)
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

    private var isInlineEmbedded: Bool {
        presentationStyle == .inlineEmbedded
    }

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
                isInlineEmbedded
                    ? .subheadline.smallCaps().weight(.semibold)
                    : .headline.smallCaps().weight(.semibold)
            )
            .foregroundStyle(ViewerTheme.secondaryText)
            .padding(.horizontal, isInlineEmbedded ? 8 : 12)
            .padding(.vertical, isInlineEmbedded ? 5 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StringDiffInlineSectionCard: View {
    let section: StringDiff.StoreState.DiffSection

    private var isDiffSection: Bool {
        section.isDiff
    }

    var body: some View {
        StringDiffSectionRows(
            section: section,
            presentationStyle: .inlineEmbedded
        )
        .padding(isDiffSection ? 4 : 0)
        .overlay {
            if isDiffSection {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(ViewerTheme.sectionStroke, lineWidth: 1)
                    .padding(1)
            }
        }
        .padding(.vertical, isDiffSection ? 2 : 0)
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

extension StringDiff: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = StringDiff
        @ObservedObject var store: Store
        @FocusState private var hasKeyboardFocus: Bool
        @State private var selectedDiffIndex: Int?

        init(_ store: Store) {
            self.store = store
        }

        private var isInlineEmbedded: Bool {
            store.state.presentationStyle == .inlineEmbedded
        }

        private var diffHunks: [StoreState.DiffSection] {
            store.state.diffHunks
        }

        private var sections: [StoreState.DiffSection] {
            store.state.sections
        }

        private var selectedDiffID: String? {
            guard let selectedDiffIndex, diffHunks.indices.contains(selectedDiffIndex) else { return nil }
            return diffHunks[selectedDiffIndex].id
        }

        var body: some View {
            Group {
                if isInlineEmbedded {
                    inlineDiffContent
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

        private var inlineDiffContent: some View {
            Group {
                if sections.isEmpty {
                    Text("No Differences")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ViewerTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                else {
                    VStack(alignment: .leading, spacing: 0) {
                        StringDiffColumnHeader(
                            presentationStyle: .inlineEmbedded,
                            oldTitle: store.state.string1Caption,
                            newTitle: store.state.string2Caption
                        )

                        Divider()

                        ForEach(sections) { section in
                            StringDiffInlineSectionCard(
                                section: section
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        private var windowDiffContent: some View {
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
                                            isSelected: selectedDiffID == section.id,
                                            onSelect: {
                                                guard let index = diffHunks.firstIndex(where: { $0.id == section.id }) else {
                                                    return
                                                }
                                                selectDiff(at: index)
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
                            selectInitialDiffIfNeeded()
                            DispatchQueue.main.async {
                                hasKeyboardFocus = true
                                scrollToSelectedDiff(using: proxy, animated: false)
                            }
                        }
                        .onChange(of: selectedDiffIndex) { _, _ in
                            scrollToSelectedDiff(using: proxy)
                        }
                        .onChange(of: diffHunks.map(\.id)) { _, _ in
                            validateSelection(using: proxy)
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
                keyboardShortcuts
            }
        }

        private var keyboardShortcuts: some View {
            VStack(spacing: 0) {
                Button("Previous Diff") {
                    selectPreviousDiff()
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(previousDiffDisabled)

                Button("Next Diff") {
                    selectNextDiff()
                }
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(nextDiffDisabled)
            }
            .buttonStyle(.plain)
            .labelsHidden()
            .accessibilityHidden(true)
            .frame(width: 0, height: 0)
            .opacity(0.001)
        }

        private var previousDiffDisabled: Bool {
            guard let selectedDiffIndex else { return diffHunks.isEmpty }
            return selectedDiffIndex <= 0
        }

        private var nextDiffDisabled: Bool {
            guard let selectedDiffIndex else { return diffHunks.isEmpty }
            return selectedDiffIndex >= diffHunks.count - 1
        }

        private func selectInitialDiffIfNeeded() {
            guard selectedDiffIndex == nil, !diffHunks.isEmpty else { return }
            selectedDiffIndex = 0
        }

        private func selectDiff(at index: Int) {
            guard diffHunks.indices.contains(index) else { return }
            selectedDiffIndex = index
            hasKeyboardFocus = true
        }

        private func selectPreviousDiff() {
            guard !diffHunks.isEmpty else { return }
            guard let selectedDiffIndex else {
                self.selectedDiffIndex = 0
                return
            }
            self.selectedDiffIndex = max(selectedDiffIndex - 1, 0)
        }

        private func selectNextDiff() {
            guard !diffHunks.isEmpty else { return }
            guard let selectedDiffIndex else {
                self.selectedDiffIndex = 0
                return
            }
            self.selectedDiffIndex = min(selectedDiffIndex + 1, diffHunks.count - 1)
        }

        private func validateSelection(using proxy: ScrollViewProxy) {
            guard !diffHunks.isEmpty else {
                selectedDiffIndex = nil
                return
            }
            if let selectedDiffIndex, diffHunks.indices.contains(selectedDiffIndex) {
                scrollToSelectedDiff(using: proxy, animated: false)
            }
            else {
                self.selectedDiffIndex = 0
            }
        }

        private func scrollToSelectedDiff(
            using proxy: ScrollViewProxy,
            animated: Bool = true
        ) {
            guard let selectedDiffIndex, diffHunks.indices.contains(selectedDiffIndex) else { return }
            let selectedHunkID = diffHunks[selectedDiffIndex].id
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(selectedHunkID, anchor: .center)
                }
            }
            else {
                proxy.scrollTo(selectedHunkID, anchor: .top)
            }
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
