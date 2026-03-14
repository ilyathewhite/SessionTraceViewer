//
//  TimelineEventRowCard.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI

struct TimelineEventRowCard: View {
    private enum Layout {
        static let kindChipMinWidth: CGFloat = 60
        static let leadingColumnWidth: CGFloat = 60
        static let gridHorizontalSpacing: CGFloat = 8
        static let gridVerticalSpacing: CGFloat = 6
    }

    let item: TraceViewer.TimelineItem
    let isSelectable: Bool
    let isSelected: Bool
    let selectionIsFocused: Bool

    private var kindColor: Color {
        ViewerTheme.chipText(for: item.colorKind)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Layout.gridHorizontalSpacing) {
            VStack(alignment: .center, spacing: Layout.gridVerticalSpacing) {
                kindTag
                sourceLabelView
            }
            .frame(width: Layout.leadingColumnWidth, alignment: .center)

            VStack(alignment: .leading, spacing: Layout.gridVerticalSpacing) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ViewerTheme.primaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.displayStoreName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ViewerTheme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.timeLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ViewerTheme.timestampText)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .viewerListCardStyle(selected: isSelected, isFocused: selectionIsFocused)
        .saturation(isSelectable ? 1 : 0.2)
        .opacity(isSelectable ? 1 : 0.45)
    }

    private var kindTag: some View {
        Text(item.kind.rawValue)
            .font(.system(size: 9, weight: .semibold, design: .monospaced).smallCaps())
            .foregroundStyle(kindColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: Layout.kindChipMinWidth)
            .background(ViewerTheme.chipBackground(for: item.colorKind), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(ViewerTheme.chipStroke(for: item.colorKind), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var sourceLabelView: some View {
        if let sourceLabel = item.subtitleSourceLabel ?? defaultSourceLabel {
            Text(sourceLabel)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(ViewerTheme.secondaryText)
        } else {
            Text(" ")
                .font(.system(size: 10.5, weight: .bold))
                .hidden()
        }
    }

    private var defaultSourceLabel: String? {
        item.kind == .state ? "CODE" : nil
    }
}
