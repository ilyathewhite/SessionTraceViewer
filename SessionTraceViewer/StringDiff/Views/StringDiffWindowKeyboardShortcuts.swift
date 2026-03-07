//
//  StringDiffWindowKeyboardShortcuts.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import SwiftUI

extension StringDiff {
    struct WindowKeyboardShortcuts: View {
        let previousDiffDisabled: Bool
        let nextDiffDisabled: Bool
        let selectPreviousDiff: () -> Void
        let selectNextDiff: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                Button("Previous Diff", action: selectPreviousDiff)
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                    .disabled(previousDiffDisabled)

                Button("Next Diff", action: selectNextDiff)
                    .keyboardShortcut(.downArrow, modifiers: [.command])
                    .disabled(nextDiffDisabled)
            }
            .buttonStyle(.plain)
            .labelsHidden()
            .accessibilityHidden(true)
            .frame(width: 0, height: 0)
            .opacity(0.001)
        }
    }
}
