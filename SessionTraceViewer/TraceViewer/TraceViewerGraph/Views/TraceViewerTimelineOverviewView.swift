import SwiftUI

extension TraceViewerGraph {
    struct TimelineOverviewView: View {
        fileprivate struct Layout: Equatable {
            static let contentHorizontalInset: CGFloat = 10
            static let contentVerticalInset: CGFloat = 8

            let laneCount: Int
            let displayLaneByLane: [Int: Int]
            let columnWidth: CGFloat
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
            let regionTopPadding: CGFloat = 39
            let regionBottomPadding: CGFloat = 24
            let regionCornerRadius: CGFloat = 9
            let regionHorizontalInset: CGFloat = 0
            let regionShadowRadius: CGFloat = 3.5
            let regionShadowYOffset: CGFloat = 1
            let regionLabelHorizontalInset: CGFloat = 6
            let regionLabelTopInset: CGFloat = 8
            let dividerVerticalInset: CGFloat = 8

            var columnCenterX: CGFloat {
                columnWidth / 2
            }

            private var regionLaneGapToContentEdge: CGFloat {
                Self.contentHorizontalInset
            }

            var graphTopInset: CGFloat {
                max(
                    regionTopPadding + regionLaneGapToContentEdge - Self.contentVerticalInset,
                    tooltipHeight / 2 + tooltipVerticalOffset
                )
            }

            var graphBottomInset: CGFloat {
                regionBottomPadding + regionLaneGapToContentEdge - Self.contentVerticalInset
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
                let displayLane = displayLaneByLane[lane] ?? max(lane, 0)
                return graphTopInset + CGFloat(displayLane) * laneSpacing
            }
        }

        fileprivate struct HoveredTooltip {
            let text: String
            let nodePoint: CGPoint
            let width: CGFloat
        }

        fileprivate struct SegmentOverlayModel: Identifiable {
            let segment: TraceViewerGraph.TrackSegment
            let rect: CGRect
            let isSelected: Bool

            var id: String { segment.id }
        }

        let presentation: TraceViewerGraph.Presentation
        let onSelectNode: (String) -> Void
        @State private var hoveredNodeID: String?

        private var layout: Layout {
            .init(
                laneCount: max(presentation.visibleMaxLane + 1, 1),
                displayLaneByLane: presentation.displayLaneByLane,
                columnWidth: presentation.columnWidth
            )
        }

        private var graphWidth: CGFloat {
            CGFloat(max(presentation.columns.count, 1)) * layout.columnWidth
        }

        private var hoveredTooltip: HoveredTooltip? {
            guard let hoveredNodeID,
                  let node = presentation.nodeByID[hoveredNodeID],
                  let text = presentation.tooltipTextByNodeID[hoveredNodeID],
                  let width = presentation.tooltipWidthByNodeID[hoveredNodeID],
                  !text.isEmpty else {
                return nil
            }

            return .init(
                text: text,
                nodePoint: point(for: node),
                width: width
            )
        }

        private func segmentOverlayModels(contentWidth: CGFloat) -> [SegmentOverlayModel] {
            presentation.trackRows.flatMap { trackRow in
                trackRow.segments.map { segment in
                    .init(
                        segment: segment,
                        rect: segmentRect(for: segment, contentWidth: contentWidth),
                        isSelected: presentation.selectedStoreInstanceID == segment.storeInstanceID
                    )
                }
            }
        }

        var body: some View {
            GeometryReader { geometry in
                let contentWidth = max(
                    graphWidth,
                    max(geometry.size.width - Layout.contentHorizontalInset * 2, 0)
                )

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        overviewContent(contentWidth: contentWidth)
                    }
                    .onHover { isHovering in
                        if !isHovering {
                            hoveredNodeID = nil
                        }
                    }
                    .onAppear {
                        scrollToSelected(using: proxy, animated: false)
                    }
                    .onChange(of: presentation.selectedColumnID) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        scrollToSelected(using: proxy, animated: true)
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: layout.graphHeight + Layout.contentVerticalInset * 2,
                maxHeight: layout.graphHeight + Layout.contentVerticalInset * 2
            )
        }

        private func overviewContent(contentWidth: CGFloat) -> some View {
            let overlayModels = segmentOverlayModels(contentWidth: contentWidth)

            return LazyHStack(spacing: 0) {
                ForEach(presentation.columns) { column in
                    TimelineOverviewColumnView(
                        column: column,
                        layout: layout,
                        selectedNodeID: presentation.selectedNodeID,
                        selectableNodeIDSet: presentation.selectableNodeIDSet,
                        onSelectNode: onSelectNode,
                        onHoverNode: updateHoveredNode
                    )
                    .id(column.id)
                }
            }
            .frame(minWidth: contentWidth, alignment: .topLeading)
            .background(alignment: .topLeading) {
                segmentRegionOverlay(overlayModels: overlayModels)
            }
            .overlay(alignment: .topLeading) {
                segmentLabelOverlay(overlayModels: overlayModels)
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
            .padding(.horizontal, Layout.contentHorizontalInset)
            .padding(.vertical, Layout.contentVerticalInset)
        }

        private func segmentRegionOverlay(
            overlayModels: [SegmentOverlayModel]
        ) -> some View {
            ZStack(alignment: .topLeading) {
                ForEach(overlayModels) { overlay in
                    TimelineOverviewSegmentRegionView(
                        overlay: overlay,
                        layout: layout
                    )
                }
            }
            .allowsHitTesting(false)
        }

        private func segmentLabelOverlay(
            overlayModels: [SegmentOverlayModel]
        ) -> some View {
            ZStack(alignment: .topLeading) {
                ForEach(overlayModels) { overlay in
                    TimelineOverviewSegmentLabelView(
                        overlay: overlay,
                        layout: layout
                    )
                }
            }
            .allowsHitTesting(false)
        }

        private func point(for node: TraceViewerGraph.OverviewGraphNode) -> CGPoint {
            CGPoint(
                x: CGFloat(node.column) * layout.columnWidth + layout.columnCenterX,
                y: layout.laneY(node.lane)
            )
        }

        private func segmentRect(
            for segment: TraceViewerGraph.TrackSegment,
            contentWidth: CGFloat
        ) -> CGRect {
            let x = CGFloat(segment.startColumn) * layout.columnWidth + layout.regionHorizontalInset
            let nominalMaxX = CGFloat(segment.endColumn + 1) * layout.columnWidth
                - layout.regionHorizontalInset
            let rectMaxX = segment.extendsToTrailingEdge
                ? max(nominalMaxX, contentWidth - layout.regionHorizontalInset)
                : nominalMaxX
            let width = max(rectMaxX - x, 1)
            let laneTopY = min(layout.laneY(segment.baseLane), layout.laneY(segment.trackMaxLane))
            let laneBottomY = max(layout.laneY(segment.baseLane), layout.laneY(segment.trackMaxLane))
            let topY = laneTopY - layout.regionTopPadding
            let bottomY = laneBottomY + layout.regionBottomPadding
            return CGRect(
                x: x,
                y: topY,
                width: width,
                height: max(bottomY - topY, 40)
            )
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
            guard let selectedColumnID = presentation.selectedColumnID else { return }
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(selectedColumnID)
                }
            }
            else {
                proxy.scrollTo(selectedColumnID)
            }
        }
    }
}

extension TraceViewerGraph {
    fileprivate struct TimelineOverviewSegmentRegionView: View {
        let overlay: TimelineOverviewView.SegmentOverlayModel
        let layout: TimelineOverviewView.Layout

        private var fillColor: Color {
            overlay.isSelected
                ? ViewerTheme.sectionBackground
                : ViewerTheme.overviewRegionBackground
        }

        private var strokeColor: Color {
            overlay.isSelected ? ViewerTheme.rowStroke : ViewerTheme.sectionStroke
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(
                    cornerRadius: layout.regionCornerRadius,
                    style: .continuous
                )
                .fill(fillColor)
                .overlay {
                    Path { path in
                        let y = layout.laneY(overlay.segment.baseLane) - overlay.rect.minY
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: overlay.rect.width, y: y))
                    }
                    .stroke(
                        ViewerTheme.overviewGuide,
                        lineWidth: 1.15
                    )
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: layout.regionCornerRadius,
                        style: .continuous
                    )
                    .stroke(
                        strokeColor,
                        lineWidth: overlay.isSelected ? 1.4 : 1
                    )
                }
                .shadow(
                    color: overlay.isSelected
                        ? ViewerTheme.overviewRegionSelectedShadow
                        : ViewerTheme.overviewRegionShadow,
                    radius: layout.regionShadowRadius,
                    y: layout.regionShadowYOffset
                )
                .frame(width: overlay.rect.width, height: overlay.rect.height)
                .position(x: overlay.rect.midX, y: overlay.rect.midY)

                if overlay.segment.showsDivider {
                    Path { path in
                        let x = overlay.rect.minX
                        path.move(
                            to: CGPoint(
                                x: x,
                                y: overlay.rect.minY + layout.dividerVerticalInset
                            )
                        )
                        path.addLine(
                            to: CGPoint(
                                x: x,
                                y: overlay.rect.maxY - layout.dividerVerticalInset
                            )
                        )
                    }
                    .stroke(
                        ViewerTheme.sectionStrokeMuted,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                    )
                }
            }
        }
    }
}

extension TraceViewerGraph {
    fileprivate struct TimelineOverviewSegmentLabelView: View {
        let overlay: TimelineOverviewView.SegmentOverlayModel
        let layout: TimelineOverviewView.Layout

        var body: some View {
            Text(overlay.segment.storeName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ViewerTheme.primaryTextMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(
                    width: max(overlay.rect.width - layout.regionLabelHorizontalInset * 2, 0),
                    height: overlay.rect.height,
                    alignment: .topLeading
                )
                .position(x: overlay.rect.midX, y: overlay.rect.midY)
                .offset(
                    x: layout.regionLabelHorizontalInset,
                    y: layout.regionLabelTopInset
                )
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
                    let xScale = layout.columnWidth / TraceViewerGraph.OverviewMetrics.columnWidth
                    let y = layout.laneY(lane)
                    path.move(to: CGPoint(x: startX * xScale, y: y))
                    path.addLine(to: CGPoint(x: endX * xScale, y: y))

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
                .foregroundStyle(ViewerTheme.tooltipText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, Self.verticalPadding)
                .frame(width: width, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ViewerTheme.tooltipBackground)
                )
                .shadow(color: ViewerTheme.tooltipShadow, radius: 3, x: 0, y: 1)
        }
    }
}
