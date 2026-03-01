//
//  TimelineEventRow.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI

struct TimelineEventRow: View {
    let item: TraceViewer.TimelineItem
    let isSelected: Bool

    var body: some View {
        TimelineEventRowCard(item: item, isSelected: isSelected)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}
