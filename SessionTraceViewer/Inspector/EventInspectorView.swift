//
//  EventInspectorView.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI

struct EventInspectorView: View {
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
    }

    let item: TraceViewer.TimelineItem?
    let previousStateItem: TraceViewer.TimelineItem?

    @State private var detailRowExpansionByID: [String: Bool] = [:]
    @State private var valueRowExpansionByID: [String: Bool] = [:]

    func propertyView(key: String) -> some View {
        Text(key)
            .font(.system(size: 12, weight: .light, design: .monospaced))
            .foregroundStyle(ViewerTheme.inspectorPropertyText)
    }

    func valueView(value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(ViewerTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .padding(.leading, Layout.valueColumnPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !isStateItem(item) {
                            detailsCard(item)
                        }
                        if let valueRows = InspectorFormatter.valueRows(
                            for: item,
                            previousStateItem: previousStateItem
                        ) {
                            valueCard(rows: valueRows)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
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
        .onChange(of: item?.id) { _ in
            detailRowExpansionByID = [:]
            valueRowExpansionByID = [:]
        }
    }

    @ViewBuilder
    private func detailsCard(_ item: TraceViewer.TimelineItem) -> some View {
        let rows = InspectorFormatter.keyValues(for: item).enumerated().map { index, pair in
            InspectorFormatter.ValueRow(
                id: "details-\(index)-\(pair.0)",
                property: pair.0,
                value: pair.1,
                isChanged: false,
                isExpandable: InspectorFormatter.valueNeedsExpansion(pair.1),
                isExpandedByDefault: InspectorFormatter.valueExpandsByDefault(pair.1)
            )
        }

        inspectorGridCard(
            title: "Details",
            rows: rows,
            rowExpansionByID: $detailRowExpansionByID
        )
    }

    @ViewBuilder
    private func valueCard(rows: [InspectorFormatter.ValueRow]) -> some View {
        inspectorGridCard(
            title: "Value",
            rows: rows,
            rowExpansionByID: $valueRowExpansionByID
        )
    }

    @ViewBuilder
    private func inspectorGridCard(
        title: String,
        rows: [InspectorFormatter.ValueRow],
        rowExpansionByID: Binding<[String: Bool]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(ViewerTheme.secondaryText)

            Grid(alignment: .topLeading, horizontalSpacing: Layout.columnSpacing, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let isExpanded = rowExpansionByID.wrappedValue[row.id] ?? row.isExpandedByDefault

                    GridRow(alignment: .firstTextBaseline) {
                        propertyColumn(row: row, isExpanded: isExpanded) {
                            toggleRowExpansion(
                                id: row.id,
                                currentValue: isExpanded,
                                rowExpansionByID: rowExpansionByID
                            )
                        }

                        valueColumn(row: row, isExpanded: isExpanded)
                    }

                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(ViewerTheme.sectionStroke)
                            .frame(height: 1)
                            .gridCellColumns(2)
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
        .shadow(color: ViewerTheme.rowLiftShadow, radius: 1.4, x: 0, y: 1)
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
        row: InspectorFormatter.ValueRow,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let topPadding = Layout.rowTopPadding + (row.isExpandable ? Layout.expandableRowExtraTopPadding : 0)

        return HStack(alignment: .firstTextBaseline, spacing: Layout.disclosureSpacing) {
            if row.isExpandable {
                Button(action: action) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ViewerTheme.secondaryText)
                        .frame(width: Layout.disclosureWidth, height: Layout.disclosureHeight)
                }
                .buttonStyle(.plain)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.bottom] - 6
                }
            }

            propertyView(key: row.property)
                .foregroundStyle(ViewerTheme.inspectorPropertyText)
        }
        .padding(.leading, 8)
        .padding(.top, topPadding)
        .padding(.bottom, Layout.rowBottomPadding)
    }

    private func valueColumn(
        row: InspectorFormatter.ValueRow,
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
            .frame(maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ViewerTheme.sectionStroke)
                .frame(width: Layout.separatorWidth)
                .offset(x: -(Layout.columnSpacing / 2))
        }
    }

    private func toggleRowExpansion(
        id: String,
        currentValue: Bool,
        rowExpansionByID: Binding<[String: Bool]>
    ) {
        rowExpansionByID.wrappedValue[id] = !currentValue
    }

    private func isStateItem(_ item: TraceViewer.TimelineItem) -> Bool {
        if case .state = item.node {
            return true
        }
        return false
    }
}
