//
//  EventInspectorUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import AppKit
import SwiftUI
import ReducerArchitecture

extension EventInspector: StoreUINamespace {
    struct ContentView: StoreContentView {
        private enum Layout {
            static let columnSpacing: CGFloat = 9
            static let separatorWidth: CGFloat = 1
            static let valueColumnPadding: CGFloat = 8
            static let rowTopPadding: CGFloat = 5
            static let rowBottomPadding: CGFloat = 5
            static let rowHorizontalPadding: CGFloat = 12
            static let diffIndicatorColumnWidth: CGFloat = 16
            static let diffIndicatorTrailingPadding: CGFloat = 2
            static let truncatedValueIconSize: CGFloat = 12
            static let truncatedValueIconTrailingPadding: CGFloat = 8
            static let truncatedValueIconTopPadding: CGFloat = 8
            static let truncatedValuePreviewTrailingPadding: CGFloat = 26
        }

        typealias Nsp = EventInspector
        @ObservedObject var store: Store
        @Environment(\.openWindow) private var openWindow

        init(_ store: Store) {
            self.store = store
        }

        private var inlineStringDiffStore: StringDiff.Store? {
            store.child()
        }

        var body: some View {
            Group {
                if store.state.item != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if store.state.showsDetailsCard {
                                detailsCard(rows: store.state.detailRows)
                            }
                            if let valueRows = store.state.valueRows {
                                valueCard(rows: valueRows)
                            }
                        }
                    }
                }
                else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "cursorarrow.click",
                        description: Text("Pick an event from the timeline to inspect node data.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 10)
            .padding(.leading, 0)
            .padding(.trailing, 10)
            .connectOnAppear {
                store.environment = .init(
                    syncInlineDiff: Nsp.syncInlineDiff(store: store),
                    openDiffWindow: { input in
                        openWindow(
                            id: StringDiff.windowID,
                            value: input
                        )
                    },
                    openExternalDiff: StringDiff.openExternalDiff,
                    openValueWindow: { input in
                        openWindow(
                            id: EventInspector.valueWindowID,
                            value: input
                        )
                    }
                )
            }
        }

        private func propertyView(key: String) -> some View {
            Text(key)
                .font(.system(size: 12, weight: .light, design: .monospaced))
                .foregroundStyle(ViewerTheme.inspectorPropertyText)
        }

        private func valueView(value: String) -> some View {
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(ViewerTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.leading, Layout.valueColumnPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        private func detailsCard(rows: [EventInspectorFormatter.ValueRow]) -> some View {
            inspectorGridCard(
                title: "Details",
                rows: rows,
                onRowTap: nil
            )
        }

        @ViewBuilder
        private func valueCard(rows: [EventInspectorFormatter.ValueRow]) -> some View {
            inspectorGridCard(
                title: "Value",
                rows: rows,
                onRowTap: { row in
                    store.send(.effect(.inspectDiff(rowID: row.id)))
                }
            )
        }

        @ViewBuilder
        private func inspectorGridCard(
            title: String,
            rows: [EventInspectorFormatter.ValueRow],
            onRowTap: ((EventInspectorFormatter.ValueRow) -> Void)?
        ) -> some View {
            let currentInlineStringDiffStore = inlineStringDiffStore
            let showsDiffColumn = rows.contains { $0.change != nil }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ViewerTheme.secondaryText)

                Grid(alignment: .topLeading, horizontalSpacing: Layout.columnSpacing, verticalSpacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        let showsInlineDiff = store.state.inlineDiffRowID == row.id
                            && currentInlineStringDiffStore != nil

                        GridRow(alignment: .top) {
                            propertyColumn(row: row)

                            if showsDiffColumn {
                                diffIndicatorColumn(row: row)
                            }

                            valueColumn(row: row)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard row.change != nil else { return }
                            onRowTap?(row)
                        }

                        if showsInlineDiff {
                            gridSeparator(columnCount: showsDiffColumn ? 3 : 2)
                        }

                        if store.state.inlineDiffRowID == row.id,
                           let currentInlineStringDiffStore {
                            GridRow(alignment: .top) {
                                Color.clear
                                    .frame(width: 1, height: 1)

                                if showsDiffColumn {
                                    Color.clear
                                        .frame(width: Layout.diffIndicatorColumnWidth)
                                }

                                inlineDiffValueColumn(currentInlineStringDiffStore)
                            }
                        }

                        if index < rows.count - 1 {
                            gridSeparator(columnCount: showsDiffColumn ? 3 : 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    Rectangle()
                        .stroke(ViewerTheme.sectionStroke, lineWidth: 1)
                }
            }
            .padding(10)
            .background(cardBackground)
            .overlay(cardBorder)
            .shadow(color: ViewerTheme.detailCardShadow, radius: 1.4, x: 0, y: 1)
        }

        private var cardBackground: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ViewerTheme.sectionBackground)
        }

        private var cardBorder: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ViewerTheme.rowStroke, lineWidth: 1)
        }

        private func propertyColumn(
            row: EventInspectorFormatter.ValueRow
        ) -> some View {
            propertyView(key: row.property)
                .foregroundStyle(ViewerTheme.inspectorPropertyText)
            .padding(.leading, Layout.rowHorizontalPadding)
            .padding(.trailing, Layout.rowHorizontalPadding)
            .padding(.top, Layout.rowTopPadding)
            .padding(.bottom, Layout.rowBottomPadding)
        }

        private func diffIndicatorColumn(row: EventInspectorFormatter.ValueRow) -> some View {
            return Group {
                if row.change != nil {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ViewerTheme.valueChangedAccent)
                }
                else {
                    Color.clear
                }
            }
            .frame(width: Layout.diffIndicatorColumnWidth)
            .padding(.trailing, Layout.diffIndicatorTrailingPadding)
            .padding(.top, Layout.rowTopPadding)
            .padding(.bottom, Layout.rowBottomPadding)
        }

        @ViewBuilder
        private func valueColumn(row: EventInspectorFormatter.ValueRow) -> some View {
            if row.showsTruncationInPreview {
                Button {
                    store.send(.effect(.inspectValue(rowID: row.id)))
                } label: {
                    tappableValuePreview(row: row)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .help("Open Full Value")
            }
            else {
                valuePreview(row: row)
            }
        }

        private func tappableValuePreview(row: EventInspectorFormatter.ValueRow) -> some View {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(.clear)

                valuePreview(row: row)

                Image(systemName: "arrow.down.left.and.arrow.up.right")
                    .font(.system(size: Layout.truncatedValueIconSize, weight: .bold))
                    .foregroundStyle(ViewerTheme.secondaryText)
                    .padding(.top, Layout.truncatedValueIconTopPadding)
                    .padding(.trailing, Layout.truncatedValueIconTrailingPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }

        private func valuePreview(row: EventInspectorFormatter.ValueRow) -> some View {
            valueView(value: row.value)
                .lineLimit(row.inlinePreviewLineLimit)
                .truncationMode(.tail)
                .padding(
                    .trailing,
                    row.showsTruncationInPreview
                        ? Layout.truncatedValuePreviewTrailingPadding
                        : 8
                )
                .padding(.top, Layout.rowTopPadding)
                .padding(.bottom, Layout.rowBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) {
                    if row.isChanged {
                        Rectangle()
                            .fill(ViewerTheme.valueChangedBackground)
                            .padding(.leading, -(Layout.columnSpacing / 2))
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(ViewerTheme.sectionStroke)
                        .frame(width: Layout.separatorWidth)
                        .offset(x: -(Layout.columnSpacing / 2))
                }
        }

        private func inlineDiffValueColumn(_ stringDiffStore: StringDiff.Store) -> some View {
            stringDiffStore.contentView
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(ViewerTheme.sectionStroke)
                        .frame(width: Layout.separatorWidth)
                        .offset(x: -(Layout.columnSpacing / 2))
                }
        }

        private func gridSeparator(columnCount: Int) -> some View {
            Rectangle()
                .fill(ViewerTheme.sectionStroke)
                .frame(height: 1)
                .gridCellColumns(columnCount)
        }

    }
}

extension EventInspector {
    struct ValueWindowView: View {
        private enum Layout {
            static let minWidth: CGFloat = 420
            static let idealWidth: CGFloat = 760
            static let minHeight: CGFloat = 120
            static let idealHeight: CGFloat = 720
            static let horizontalPadding: CGFloat = 14
            static let verticalPadding: CGFloat = 12
            static let fontSize: CGFloat = 12
            static let font = NSFont.monospacedSystemFont(
                ofSize: fontSize,
                weight: .regular
            )
        }

        let input: ValueWindowInput

        var body: some View {
            ScrollView {
                Text(input.value)
                    .font(.system(size: Layout.fontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(ViewerTheme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Layout.horizontalPadding)
                    .padding(.vertical, Layout.verticalPadding)
            }
            .frame(
                minWidth: Layout.minWidth,
                idealWidth: Layout.idealWidth,
                maxWidth: .infinity,
                minHeight: Layout.minHeight,
                idealHeight: displayedHeight,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .background(ViewerTheme.sectionBackground)
            .navigationTitle(input.title)
        }

        private var displayedHeight: CGFloat {
            min(
                max(Self.measuredTextHeight(for: input.value), Layout.minHeight),
                Layout.idealHeight
            )
        }

        private static func measuredTextHeight(for value: String) -> CGFloat {
            let attributedString = NSAttributedString(
                string: value.isEmpty ? " " : value,
                attributes: [
                    .font: Layout.font
                ]
            )
            let textWidth = Layout.idealWidth - (Layout.horizontalPadding * 2)
            let measuredRect = attributedString.boundingRect(
                with: .init(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return ceil(measuredRect.height) + (Layout.verticalPadding * 2)
        }
    }
}
