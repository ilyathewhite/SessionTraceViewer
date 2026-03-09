import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension TraceViewer {
    struct GraphNodeTooltip: View {
        static let fontSize: CGFloat = 11
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 4

        static var height: CGFloat {
            textLineHeight + verticalPadding * 2
        }

        private static var textLineHeight: CGFloat {
            #if canImport(AppKit)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            return ceil(NSLayoutManager().defaultLineHeight(for: font))
            #else
            return fontSize
            #endif
        }

        let text: String
        let width: CGFloat

        var body: some View {
            Text(text)
                .font(.system(size: Self.fontSize, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, Self.verticalPadding)
                .frame(width: width, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                )
                .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
        }
    }
}
