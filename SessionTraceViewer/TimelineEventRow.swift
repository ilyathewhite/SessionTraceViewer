//
//  TimelineEventRow.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI

struct TimelineEventRow: View {
    let item: TraceViewer.TimelineItem
    let isSelectable: Bool
    let isSelected: Bool
    let selectionIsFocused: Bool

    var body: some View {
        TimelineEventRowCard(
            item: item,
            isSelectable: isSelectable,
            isSelected: isSelected,
            selectionIsFocused: selectionIsFocused
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}
