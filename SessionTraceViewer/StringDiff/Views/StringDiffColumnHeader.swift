//
//  StringDiffColumnHeader.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension StringDiff {
    struct ColumnHeader: View {
        let presentationStyle: PresentationStyle
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
}
