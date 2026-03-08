import SwiftUI

extension TraceViewer {
    struct ScopeBarButton: View {
        private enum Layout {
            static let minWidth: CGFloat = 60
        }

        let title: String
        let isSelected: Bool
        let tint: Color
        let isNeutral: Bool
        let action: () -> Void

        private var fillColor: Color {
            guard isSelected else { return ViewerTheme.sectionBackground }
            if isNeutral {
                return ViewerTheme.rowSelectedFill
            }
            return tint.opacity(0.14)
        }

        private var strokeColor: Color {
            guard isSelected else { return ViewerTheme.rowStroke }
            if isNeutral {
                return ViewerTheme.rowSelectedStroke
            }
            return tint.opacity(0.4)
        }

        private var textColor: Color {
            guard isSelected else { return ViewerTheme.secondaryText }
            if isNeutral {
                return ViewerTheme.primaryText
            }
            return tint
        }

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced).smallCaps())
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minWidth: Layout.minWidth)
                    .background(
                        Capsule(style: .continuous)
                            .fill(fillColor)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
