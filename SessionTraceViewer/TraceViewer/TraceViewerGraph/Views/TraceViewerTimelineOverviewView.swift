import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension TraceViewerGraph {
    struct TimelineOverviewView: View {
        fileprivate struct Layout: Equatable {
            let laneCount: Int
            let columnWidth = TraceViewerGraph.OverviewMetrics.columnWidth
            let laneSpacing = TraceViewerGraph.OverviewMetrics.laneSpacing
            let verticalInset = TraceViewerGraph.OverviewMetrics.verticalInset
            let nodeRadius = TraceViewerGraph.OverviewMetrics.nodeRadius
            let nodeHitArea = TraceViewerGraph.OverviewMetrics.nodeHitArea
            let tooltipHeight: CGFloat = TraceViewerGraph.TimelineOverviewTooltip.height
            let tooltipVerticalOffset = TraceViewerGraph.OverviewMetrics.tooltipVerticalOffset
            let tooltipMaxWidth = TraceViewerGraph.OverviewMetrics.tooltipMaxWidth
            let selectionRingGap = TraceViewerGraph.OverviewMetrics.selectionRingGap
            let selectionRingThickness = TraceViewerGraph.OverviewMetrics.selectionRingThickness
            let mutedOpacity = TraceViewerGraph.OverviewMetrics.mutedOpacity

            var columnCenterX: CGFloat {
                columnWidth / 2
            }

            var graphTopInset: CGFloat {
                max(verticalInset, tooltipHeight / 2 + tooltipVerticalOffset)
            }

            var graphBottomInset: CGFloat {
                verticalInset
            }

            var graphHeight: CGFloat {
                graphTopInset + graphBottomInset + CGFloat(max(laneCount - 1, 0)) * laneSpacing
            }

            var selectionRingInnerRadius: CGFloat {
                nodeRadius + selectionRingGap
            }

            var selectionRingOuterRadius: CGFloat {
                selectionRingInnerRadius + selectionRingThickness
            }

            func laneY(_ lane: Int) -> CGFloat {
                graphHeight - graphBottomInset - CGFloat(max(lane, 0)) * laneSpacing
            }
        }

        fileprivate struct HoveredTooltip {
            let text: String
            let nodePoint: CGPoint
            let width: CGFloat
        }

        let presentation: TraceViewerGraph.Presentation
        let onSelectNode: (String) -> Void
        @State private var hoveredNodeID: String?

        private var layout: Layout {
            .init(laneCount: max(presentation.visibleMaxLane + 1, 1))
        }

        private var graphWidth: CGFloat {
            CGFloat(max(presentation.columns.count, 1)) * layout.columnWidth
        }

        private var selectableNodeIDSet: Set<String> {
            Set(presentation.selectableNodeIDs)
        }

        private var selectedColumnID: Int? {
            guard let selectedNodeID = presentation.selectedNodeID else { return nil }
            return presentation.nodeByID[selectedNodeID]?.column
        }

        private var hoveredTooltip: HoveredTooltip? {
            guard let hoveredNodeID,
                  let node = presentation.nodeByID[hoveredNodeID],
                  let text = presentation.tooltipTextByNodeID[hoveredNodeID],
                  !text.isEmpty else {
                return nil
            }

            return .init(
                text: text,
                nodePoint: point(for: node),
                width: tooltipWidth(for: text)
            )
        }

        var body: some View {
            ZStack {
                ViewerTheme.timelineGraphBackground

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        LazyHStack(spacing: 0) {
                            ForEach(presentation.columns) { column in
                                TimelineOverviewColumnView(
                                    column: column,
                                    layout: layout,
                                    selectedNodeID: presentation.selectedNodeID,
                                    selectableNodeIDSet: selectableNodeIDSet,
                                    onSelectNode: onSelectNode,
                                    onHoverNode: updateHoveredNode
                                )
                                .id(column.id)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let hoveredTooltip {
                                TimelineOverviewTooltip(
                                    text: hoveredTooltip.text,
                                    width: hoveredTooltip.width
                                )
                                .position(
                                    tooltipPosition(
                                        for: hoveredTooltip.nodePoint,
                                        tooltipWidth: hoveredTooltip.width
                                    )
                                )
                                .allowsHitTesting(false)
                                .zIndex(10)
                            }
                        }
                    }
                    .onHover { isHovering in
                        if !isHovering {
                            hoveredNodeID = nil
                        }
                    }
                    .onAppear {
                        scrollToSelected(using: proxy, animated: false)
                    }
                    .onChange(of: selectedColumnID) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        scrollToSelected(using: proxy, animated: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: layout.graphHeight, maxHeight: layout.graphHeight)
        }

        private func point(for node: TraceViewerGraph.OverviewGraphNode) -> CGPoint {
            CGPoint(
                x: CGFloat(node.column) * layout.columnWidth + layout.columnCenterX,
                y: layout.laneY(node.lane)
            )
        }

        private func tooltipWidth(for text: String) -> CGFloat {
            let minWidth: CGFloat = 56
            let horizontalPadding: CGFloat = 16
            let averageCharacterWidth: CGFloat = 6.2
            let estimatedTextWidth = CGFloat(text.count) * averageCharacterWidth
            return min(max(estimatedTextWidth + horizontalPadding, minWidth), layout.tooltipMaxWidth)
        }

        private func tooltipPosition(
            for nodePoint: CGPoint,
            tooltipWidth: CGFloat
        ) -> CGPoint {
            let xPadding = tooltipWidth / 2 + 10
            let clampedX = min(max(nodePoint.x, xPadding), max(graphWidth - xPadding, xPadding))
            let y = max(layout.tooltipHeight / 2, nodePoint.y - layout.tooltipVerticalOffset)
            return CGPoint(x: clampedX, y: y)
        }

        private func updateHoveredNode(_ nodeID: String?, isHovering: Bool) {
            if isHovering {
                hoveredNodeID = nodeID
            }
            else if hoveredNodeID == nodeID {
                hoveredNodeID = nil
            }
        }

        private func scrollToSelected(using proxy: ScrollViewProxy, animated: Bool) {
            guard let selectedColumnID else { return }
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(selectedColumnID, anchor: .center)
                }
            }
            else {
                proxy.scrollTo(selectedColumnID, anchor: .center)
            }
        }
    }
}

extension TraceViewerGraph {
    fileprivate struct TimelineOverviewColumnView: View {
        let column: TraceViewerGraph.OverviewColumn
        let layout: TimelineOverviewView.Layout
        let selectedNodeID: String?
        let selectableNodeIDSet: Set<String>
        let onSelectNode: (String) -> Void
        let onHoverNode: (String?, Bool) -> Void

        var body: some View {
            ZStack(alignment: .topLeading) {
                baseline

                ForEach(column.edgePieces) { piece in
                    TimelineOverviewEdgePieceView(
                        piece: piece,
                        layout: layout,
                        color: edgeColor(for: piece)
                    )
                }

                ForEach(column.nodes, id: \.id) { node in
                    TimelineOverviewNodeView(
                        node: node,
                        layout: layout,
                        isSelected: node.id == selectedNodeID,
                        isSelectable: selectableNodeIDSet.contains(node.id),
                        onSelect: onSelectNode,
                        onHoverChanged: onHoverNode
                    )
                }
            }
            .frame(width: layout.columnWidth, height: layout.graphHeight)
        }

        private func edgeColor(for piece: TraceViewerGraph.OverviewEdgePiece) -> Color {
            let baseColor: Color = {
                switch piece.lineKind {
                case .solid:
                    return ViewerTheme.solidBranchLine
                case .dotted:
                    return ViewerTheme.dottedBranchLine
                }
            }()

            let opacity = min(
                selectableNodeIDSet.contains(piece.predecessorID) ? 1 : layout.mutedOpacity,
                selectableNodeIDSet.contains(piece.nodeID) ? 1 : layout.mutedOpacity
            )
            return baseColor.opacity(opacity)
        }

        private var baseline: some View {
            Path { path in
                let y = layout.laneY(0)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: layout.columnWidth, y: y))
            }
            .stroke(
                ViewerTheme.overviewGuide,
                lineWidth: 1.15
            )
            .allowsHitTesting(false)
        }
    }
}

extension TraceViewerGraph {
    fileprivate struct TimelineOverviewEdgePieceView: View {
        let piece: TraceViewerGraph.OverviewEdgePiece
        let layout: TimelineOverviewView.Layout
        let color: Color

        var body: some View {
            path
                .stroke(
                    color,
                    style: strokeStyle
                )
                .frame(width: layout.columnWidth, height: layout.graphHeight)
                .allowsHitTesting(false)
        }

        private var path: Path {
            Path { path in
                switch piece.segment {
                case .horizontal(let lane, let startX, let endX):
                    guard endX > startX else { return }
                    let y = layout.laneY(lane)
                    path.move(to: CGPoint(x: startX, y: y))
                    path.addLine(to: CGPoint(x: endX, y: y))

                case .sourceCurve(let startLane, let endLane):
                    let start = CGPoint(x: layout.columnCenterX, y: layout.laneY(startLane))
                    let end = CGPoint(x: layout.columnWidth, y: layout.laneY(endLane))
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(
                            x: layout.columnCenterX + (layout.columnWidth - layout.columnCenterX) * 0.28,
                            y: start.y
                        ),
                        control2: CGPoint(
                            x: layout.columnWidth - 8,
                            y: end.y
                        )
                    )

                case .targetCurve(let startLane, let endLane):
                    let start = CGPoint(x: 0, y: layout.laneY(startLane))
                    let end = CGPoint(x: layout.columnCenterX, y: layout.laneY(endLane))
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: 8, y: start.y),
                        control2: CGPoint(
                            x: layout.columnCenterX - layout.columnWidth * 0.22,
                            y: end.y
                        )
                    )

                case .localCurve(let startLane, let endLane):
                    let start = CGPoint(x: layout.columnCenterX, y: layout.laneY(startLane))
                    let end = CGPoint(x: layout.columnCenterX, y: layout.laneY(endLane))
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: layout.columnWidth * 0.84, y: start.y),
                        control2: CGPoint(x: layout.columnWidth * 0.84, y: end.y)
                    )
                }
            }
        }

        private var strokeStyle: StrokeStyle {
            switch piece.lineKind {
            case .solid:
                return StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
            case .dotted:
                return StrokeStyle(
                    lineWidth: 1.45,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [1.5, 6.6]
                )
            }
        }
    }
}

extension TraceViewerGraph {
    fileprivate struct TimelineOverviewNodeView: View {
        let node: TraceViewerGraph.OverviewGraphNode
        let layout: TimelineOverviewView.Layout
        let isSelected: Bool
        let isSelectable: Bool
        let onSelect: (String) -> Void
        let onHoverChanged: (String?, Bool) -> Void

        private var fillColor: Color {
            ViewerTheme.graphColor(for: node.colorKind)
                .opacity(isSelectable ? 1 : layout.mutedOpacity)
        }

        var body: some View {
            button
                .frame(width: layout.nodeHitArea, height: layout.nodeHitArea)
                .position(
                    x: layout.columnCenterX,
                    y: layout.laneY(node.lane)
                )
        }

        private var button: some View {
            Button {
                onSelect(node.id)
            } label: {
                ZStack {
                    if isSelected {
                        Circle()
                            .stroke(fillColor, lineWidth: layout.selectionRingThickness)
                            .frame(
                                width: layout.selectionRingOuterRadius * 2,
                                height: layout.selectionRingOuterRadius * 2
                            )
                    }

                    Circle()
                        .fill(fillColor)
                        .frame(
                            width: layout.nodeRadius * 2,
                            height: layout.nodeRadius * 2
                        )
                }
                .frame(width: layout.nodeHitArea, height: layout.nodeHitArea)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                onHoverChanged(node.id, isHovering)
            }
        }
    }
}

extension TraceViewerGraph {
    fileprivate struct TimelineOverviewTooltip: View {
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
