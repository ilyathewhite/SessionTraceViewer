//
//  StringDiffLoadingView.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension StringDiff {
    struct LoadingView: View {
        var body: some View {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                Text("Preparing diff preview...")
                    .font(.headline)
                    .foregroundStyle(ViewerTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ViewerTheme.sectionBackground)
        }
    }
}
