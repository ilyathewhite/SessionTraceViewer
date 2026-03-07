//
//  StringDiffInlineLoadedView.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension StringDiff {
    struct InlineLoadedView: View {
        let oldTitle: String
        let newTitle: String
        let sections: [StoreState.DiffSection]

        private var oldText: AttributedString {
            combinedText(for: .old)
        }

        private var newText: AttributedString {
            combinedText(for: .new)
        }

        private func combinedText(for side: DiffSide) -> AttributedString {
            let lines = sections
                .flatMap(\.rows)
                .compactMap { row in
                    switch side {
                    case .old:
                        row.oldLine
                    case .new:
                        row.newLine
                    }
                }

            var combined = AttributedString()
            for (index, line) in lines.enumerated() {
                if index > 0 {
                    combined.append(AttributedString("\n"))
                }
                combined.append(line.text)
            }
            return combined
        }

        var body: some View {
            let verticalPadding: CGFloat = 6
            Group {
                if sections.isEmpty {
                    Text("No Differences")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ViewerTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, verticalPadding)
                }
                else {
                    HStack(alignment: .top, spacing: 0) {
                        InlineValueCard(
                            title: oldTitle,
                            text: oldText
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.vertical, verticalPadding)

                        Rectangle()
                            .fill(ViewerTheme.sectionStroke)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)

                        InlineValueCard(
                            title: newTitle,
                            text: newText
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.vertical, verticalPadding)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
