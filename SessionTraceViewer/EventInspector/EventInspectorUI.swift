//
//  EventInspectorUI.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI
import ReducerArchitecture

extension EventInspector: StoreUINamespace {
    struct ContentView: StoreContentView {
        private enum Layout {
            static let columnSpacing: CGFloat = 9
            static let disclosureSpacing: CGFloat = 4
            static let disclosureWidth: CGFloat = 20
            static let disclosureHeight: CGFloat = 20
            static let separatorWidth: CGFloat = 1
            static let valueColumnPadding: CGFloat = 8
            static let rowTopPadding: CGFloat = 5
            static let rowBottomPadding: CGFloat = 5
            static let expandableRowExtraTopPadding: CGFloat = 6
            static let rowHorizontalPadding: CGFloat = 12
            static let diffIndicatorColumnWidth: CGFloat = 16
            static let diffIndicatorTrailingPadding: CGFloat = 2
        }

        private enum InspectorCardKind {
            case details
            case value
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
                cardKind: .details,
                onRowTap: nil
            )
        }

        @ViewBuilder
        private func valueCard(rows: [EventInspectorFormatter.ValueRow]) -> some View {
            inspectorGridCard(
                title: "Value",
                rows: rows,
                cardKind: .value,
                onRowTap: { row in
                    store.send(.effect(.inspectDiff(rowID: row.id)))
                }
            )
        }

        @ViewBuilder
        private func inspectorGridCard(
            title: String,
            rows: [EventInspectorFormatter.ValueRow],
            cardKind: InspectorCardKind,
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
                        let isExpanded = isExpanded(row, in: cardKind)
                        let showsInlineDiff = store.state.inlineDiffRowID == row.id
                            && currentInlineStringDiffStore != nil

                        GridRow(alignment: .top) {
                            propertyColumn(row: row, isExpanded: isExpanded) {
                                toggleRowExpansion(for: row, in: cardKind)
                            }

                            if showsDiffColumn {
                                diffIndicatorColumn(row: row)
                            }

                            valueColumn(row: row, isExpanded: isExpanded)
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
            row: EventInspectorFormatter.ValueRow,
            isExpanded: Bool,
            action: @escaping () -> Void
        ) -> some View {
            let topPadding = Layout.rowTopPadding + (row.isExpandable ? Layout.expandableRowExtraTopPadding : 0)

            return HStack(alignment: .top, spacing: Layout.disclosureSpacing) {
                if row.isExpandable {
                    Button(action: action) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ViewerTheme.secondaryText)
                            .frame(width: Layout.disclosureWidth, height: Layout.disclosureHeight)
                    }
                    .buttonStyle(.plain)
                }

                propertyView(key: row.property)
                    .foregroundStyle(ViewerTheme.inspectorPropertyText)
            }
            .padding(.leading, Layout.rowHorizontalPadding)
            .padding(.trailing, Layout.rowHorizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, Layout.rowBottomPadding)
        }

        private func diffIndicatorColumn(row: EventInspectorFormatter.ValueRow) -> some View {
            let topPadding = Layout.rowTopPadding + (row.isExpandable ? Layout.expandableRowExtraTopPadding : 0)

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
            .padding(.top, topPadding)
            .padding(.bottom, Layout.rowBottomPadding)
        }

        private func valueColumn(
            row: EventInspectorFormatter.ValueRow,
            isExpanded: Bool
        ) -> some View {
            let topPadding = Layout.rowTopPadding + (row.isExpandable ? Layout.expandableRowExtraTopPadding : 0)

            return valueView(value: row.value)
                .lineLimit(isExpanded ? nil : 1)
                .truncationMode(.tail)
                .padding(.trailing, 8)
                .padding(.top, topPadding)
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

        private func isExpanded(
            _ row: EventInspectorFormatter.ValueRow,
            in cardKind: InspectorCardKind
        ) -> Bool {
            switch cardKind {
            case .details:
                return store.state.isDetailRowExpanded(row)
            case .value:
                return store.state.isValueRowExpanded(row)
            }
        }

        private func toggleRowExpansion(
            for row: EventInspectorFormatter.ValueRow,
            in cardKind: InspectorCardKind
        ) {
            switch cardKind {
            case .details:
                store.send(.mutating(.toggleDetailRowExpansion(id: row.id)))
            case .value:
                store.send(.mutating(.toggleValueRowExpansion(id: row.id)))
            }
        }
    }
}
