import SwiftUI

extension TraceViewer {
    struct GraphNodeTooltip: View {
        let text: String
        let width: CGFloat

        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: width, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.82))
                )
                .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
        }
    }
}
