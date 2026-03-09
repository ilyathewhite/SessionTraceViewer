import SwiftUI

extension TraceViewer {
    struct ScopeBarButton: View {
        private enum Layout {
            static let minWidth: CGFloat = 60
        }

        let title: String
        let isSelected: Bool
        let textColor: Color
        let backgroundColor: Color
        let strokeColor: Color
        let action: () -> Void

        private var resolvedFillColor: Color {
            guard isSelected else { return ViewerTheme.sectionBackground }
            return backgroundColor
        }

        private var resolvedStrokeColor: Color {
            guard isSelected else { return ViewerTheme.rowStroke }
            return strokeColor
        }

        private var resolvedTextColor: Color {
            guard isSelected else { return ViewerTheme.secondaryText }
            return textColor
        }

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced).smallCaps())
                    .foregroundStyle(resolvedTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minWidth: Layout.minWidth)
                    .background(
                        Capsule(style: .continuous)
                            .fill(resolvedFillColor)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(resolvedStrokeColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
