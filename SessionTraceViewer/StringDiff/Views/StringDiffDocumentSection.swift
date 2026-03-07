//
//  StringDiffDocumentSection.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension StringDiff {
    struct DocumentSection: View {
        let section: StoreState.DiffSection
        let isSelected: Bool
        let onSelect: () -> Void

        private var borderStroke: Color {
            isSelected ? ViewerTheme.rowSelectedStroke : ViewerTheme.sectionStroke
        }

        private var borderWidth: CGFloat {
            isSelected ? 2 : 1
        }

        var body: some View {
            SectionRows(
                section: section,
                presentationStyle: .standard
            )
            .padding(section.isDiff ? 4 : 0)
            .overlay {
                if section.isDiff {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(borderStroke, lineWidth: borderWidth)
                        .padding(2)
                }
            }
            .padding(.vertical, section.isDiff ? 2 : 0)
            .contentShape(Rectangle())
            .onTapGesture {
                guard section.isDiff else { return }
                onSelect()
            }
        }
    }
}
