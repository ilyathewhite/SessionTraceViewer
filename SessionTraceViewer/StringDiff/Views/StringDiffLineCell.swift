//
//  StringDiffLineCell.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension StringDiff {
    struct LineCell: View {
        let line: StoreState.DiffLine?
        let presentationStyle: PresentationStyle

        private var displayText: AttributedString {
            guard let line else { return AttributedString(" ") }
            return line.text.characters.isEmpty ? AttributedString(" ") : line.text
        }

        var body: some View {
            Text(displayText)
                .font(
                    .system(
                        size: presentationStyle.isInlineEmbedded ? 11 : 12,
                        weight: .regular,
                        design: .monospaced
                    )
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, presentationStyle.isInlineEmbedded ? 8 : 12)
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
}
