//
//  StringDiffInlineValueCard.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension StringDiff {
    struct InlineValueCard: View {
        let title: String
        let text: AttributedString

        private var displayText: AttributedString {
            text.characters.isEmpty ? AttributedString(" ") : text
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption.smallCaps().weight(.semibold))
                    .foregroundStyle(ViewerTheme.secondaryText)

                Text(displayText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
        }
    }
}
