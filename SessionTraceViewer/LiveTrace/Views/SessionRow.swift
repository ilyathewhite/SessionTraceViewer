//
//  SessionRow.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension LiveTrace {
    struct SessionRow: View {
        let session: StoreState.Session
        let isSelected: Bool
        let selectionIsFocused: Bool

        private var selectionBackgroundColor: Color {
            guard isSelected else { return .clear }
            return selectionIsFocused ? ViewerTheme.rowSelectedFill : ViewerTheme.rowInactiveSelectedFill
        }

        private var selectionStrokeColor: Color {
            guard isSelected else { return .clear }
            return selectionIsFocused ? ViewerTheme.rowSelectedStroke : ViewerTheme.rowInactiveSelectedStroke
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ViewerTheme.publish)
                        .frame(width: 8, height: 8)
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(ViewerTheme.primaryText)
                        .lineLimit(1)
                }

                SessionDescriptionView(lines: session.subtitleLines)
                    .font(.system(size: 12))
                    .foregroundStyle(ViewerTheme.secondaryText)

                Text(session.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ViewerTheme.secondaryText)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackgroundColor)
            .overlay {
                if isSelected {
                    Rectangle()
                        .stroke(selectionStrokeColor, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
