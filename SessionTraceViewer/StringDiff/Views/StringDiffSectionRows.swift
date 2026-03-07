//
//  StringDiffSectionRows.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension StringDiff {
    struct SectionRows: View {
        let section: StoreState.DiffSection
        let presentationStyle: PresentationStyle

        var body: some View {
            VStack(spacing: 0) {
                ForEach(section.rows) { row in
                    HStack(spacing: 0) {
                        LineCell(
                            line: row.oldLine,
                            presentationStyle: presentationStyle
                        )
                        Divider()
                        LineCell(
                            line: row.newLine,
                            presentationStyle: presentationStyle
                        )
                    }
                }
            }
        }
    }
}
