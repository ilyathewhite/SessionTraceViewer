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
    }

    let item: TraceViewer.TimelineItem
    let isSelectable: Bool
    let isSelected: Bool
    let selectionIsFocused: Bool

    private var kindColor: Color {
        ViewerTheme.chipText(for: item.colorKind)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
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

                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ViewerTheme.primaryText)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 0)
                }

                subtitleText
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.timeLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ViewerTheme.timestampText)
                .fixedSize()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .viewerListCardStyle(selected: isSelected, isFocused: selectionIsFocused)
        .saturation(isSelectable ? 1 : 0.2)
        .opacity(isSelectable ? 1 : 0.45)
    }

    private var subtitleText: Text {
        guard let sourceLabel = item.subtitleSourceLabel,
              let detailLabel = item.subtitleDetailLabel else {
            return Text(item.subtitle)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(ViewerTheme.secondaryText)
        }

        return Text(sourceLabel)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundColor(ViewerTheme.secondaryText)
        + Text("   ")
        + Text(detailLabel)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(ViewerTheme.primaryText)
    }
}
