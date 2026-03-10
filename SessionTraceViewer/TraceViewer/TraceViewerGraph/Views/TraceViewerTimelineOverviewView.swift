import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension TraceViewerGraph {
    struct TimelineOverviewView: View {
        fileprivate struct Layout: Equatable {
            let laneCount: Int
            let columnWidth: CGFloat = 48
            let laneSpacing: CGFloat = 34
            let verticalInset: CGFloat = 24
            let nodeRadius: CGFloat = 5
            let nodeHitArea: CGFloat = 30
            let tooltipHeight: CGFloat = TraceViewerGraph.TimelineOverviewTooltip.height
            let tooltipVerticalOffset: CGFloat = 22
            let tooltipMaxWidth: CGFloat = 240
            let selectionRingGap: CGFloat = 2
            let selectionRingThickness: CGFloat = 2
            let mutedOpacity: Double = 0.26

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

            var blockerClearance: CGFloat {
                nodeRadius + 3.2
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

        fileprivate struct EdgePiece: Identifiable {
            enum Segment {
                case horizontal(lane: Int, startX: CGFloat, endX: CGFloat)
                case sourceCurve(startLane: Int, endLane: Int)
                case targetCurve(startLane: Int, endLane: Int)
                case localCurve(startLane: Int, endLane: Int)
            }

            let id: String
            let color: Color
            let lineKind: TraceViewer.EdgeLineKind
            let segment: Segment
        }

        fileprivate struct Column: Identifiable {
            let id: Int
            let nodes: [TraceViewerGraph.OverviewGraphNode]
            let edgePieces: [EdgePiece]
        }

        fileprivate struct HoveredTooltip {
            let text: String
            let nodePoint: CGPoint
            let width: CGFloat
        }

        let nodes: [TraceViewerGraph.OverviewGraphNode]
        let selectableNodeIDs: [String]
        let tooltipTextByNodeID: [String: String]
        let selectedNodeID: String?
        let maxLane: Int
        let onSelectNode: (String) -> Void
        @State private var hoveredNodeID: String?

        private var layout: Layout {
            let visibleMaxLane = nodes.map(\.lane).max() ?? maxLane
            return .init(laneCount: max(visibleMaxLane + 1, 1))
        }

        private var maxColumn: Int {
            nodes.map(\.column).max() ?? 0
        }

        private var graphWidth: CGFloat {
            CGFloat(maxColumn + 1) * layout.columnWidth
        }

        private var nodeByID: [String: TraceViewerGraph.OverviewGraphNode] {
            Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        }

        private var nodeIndexByID: [String: Int] {
            Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        }

        private var selectableNodeIDSet: Set<String> {
            Set(selectableNodeIDs)
        }

        private var columns: [Column] {
            let nodesByColumn = Dictionary(grouping: nodes, by: \.column)
            let edgePiecesByColumn = buildEdgePieces(nodesByColumn: nodesByColumn)
            return (0...maxColumn).map { column in
                Column(
                    id: column,
                    nodes: (nodesByColumn[column] ?? [])
                        .sorted { lhs, rhs in
                            if lhs.lane == rhs.lane {
                                return lhs.id < rhs.id
                            }
                            return lhs.lane > rhs.lane
                        },
                    edgePieces: edgePiecesByColumn[column] ?? []
                )
            }
        }

        private var selectedColumnID: Int? {
            guard let selectedNodeID else { return nil }
            return nodeByID[selectedNodeID]?.column
        }

        private var hoveredTooltip: HoveredTooltip? {
            guard let hoveredNodeID,
                  let node = nodeByID[hoveredNodeID],
                  let text = tooltipTextByNodeID[hoveredNodeID],
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
                            ForEach(columns) { column in
                                TimelineOverviewColumnView(
                                    column: column,
                                    layout: layout,
                                    selectedNodeID: selectedNodeID,
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

        private func buildEdgePieces(
            nodesByColumn: [Int: [TraceViewerGraph.OverviewGraphNode]]
        ) -> [Int: [EdgePiece]] {
            var edgePiecesByColumn: [Int: [EdgePiece]] = [:]

            for node in nodes {
                guard let nodeIndex = nodeIndexByID[node.id] else { continue }

                for predecessorID in node.predecessorIDs {
                    guard let predecessor = nodeByID[predecessorID],
                          let predecessorIndex = nodeIndexByID[predecessorID],
                          predecessorIndex < nodeIndex else {
                        continue
                    }

                    let lineKind = node.edgeLineKindByPredecessorID[predecessorID] ?? .solid
                    let color = edgeColor(
                        for: lineKind,
                        predecessorID: predecessorID,
                        nodeID: node.id
                    )

                    appendPieces(
                        from: predecessor,
                        to: node,
                        lineKind: lineKind,
                        color: color,
                        nodesByColumn: nodesByColumn,
                        edgePiecesByColumn: &edgePiecesByColumn
                    )
                }
            }

            return edgePiecesByColumn
        }

        private func appendPieces(
            from predecessor: TraceViewerGraph.OverviewGraphNode,
            to node: TraceViewerGraph.OverviewGraphNode,
            lineKind: TraceViewer.EdgeLineKind,
            color: Color,
            nodesByColumn: [Int: [TraceViewerGraph.OverviewGraphNode]],
            edgePiecesByColumn: inout [Int: [EdgePiece]]
        ) {
            let edgeID = "\(predecessor.id)->\(node.id)"

            if predecessor.column == node.column {
                edgePiecesByColumn[node.column, default: []].append(
                    .init(
                        id: "\(edgeID):local",
                        color: color,
                        lineKind: lineKind,
                        segment: .localCurve(
                            startLane: predecessor.lane,
                            endLane: node.lane
                        )
                    )
                )
                return
            }

            if predecessor.lane == node.lane {
                appendHorizontalSegments(
                    edgeID: edgeID,
                    column: predecessor.column,
                    lane: predecessor.lane,
                    baseRange: layout.columnCenterX...layout.columnWidth,
                    excludingNodeIDs: [predecessor.id],
                    lineKind: lineKind,
                    color: color,
                    nodesByColumn: nodesByColumn,
                    edgePiecesByColumn: &edgePiecesByColumn
                )

                if predecessor.column + 1 < node.column {
                    for column in (predecessor.column + 1)..<node.column {
                        appendHorizontalSegments(
                            edgeID: edgeID,
                            column: column,
                            lane: node.lane,
                            baseRange: 0...layout.columnWidth,
                            excludingNodeIDs: [],
                            lineKind: lineKind,
                            color: color,
                            nodesByColumn: nodesByColumn,
                            edgePiecesByColumn: &edgePiecesByColumn
                        )
                    }
                }

                appendHorizontalSegments(
                    edgeID: edgeID,
                    column: node.column,
                    lane: node.lane,
                    baseRange: 0...layout.columnCenterX,
                    excludingNodeIDs: [node.id],
                    lineKind: lineKind,
                    color: color,
                    nodesByColumn: nodesByColumn,
                    edgePiecesByColumn: &edgePiecesByColumn
                )
                return
            }

            if predecessor.lane < node.lane {
                edgePiecesByColumn[predecessor.column, default: []].append(
                    .init(
                        id: "\(edgeID):source-curve",
                        color: color,
                        lineKind: lineKind,
                        segment: .sourceCurve(
                            startLane: predecessor.lane,
                            endLane: node.lane
                        )
                    )
                )

                if predecessor.column + 1 < node.column {
                    for column in (predecessor.column + 1)..<node.column {
                        appendHorizontalSegments(
                            edgeID: edgeID,
                            column: column,
                            lane: node.lane,
                            baseRange: 0...layout.columnWidth,
                            excludingNodeIDs: [],
                            lineKind: lineKind,
                            color: color,
                            nodesByColumn: nodesByColumn,
                            edgePiecesByColumn: &edgePiecesByColumn
                        )
                    }
                }

                appendHorizontalSegments(
                    edgeID: edgeID,
                    column: node.column,
                    lane: node.lane,
                    baseRange: 0...layout.columnCenterX,
                    excludingNodeIDs: [node.id],
                    lineKind: lineKind,
                    color: color,
                    nodesByColumn: nodesByColumn,
                    edgePiecesByColumn: &edgePiecesByColumn
                )
                return
            }

            appendHorizontalSegments(
                edgeID: edgeID,
                column: predecessor.column,
                lane: predecessor.lane,
                baseRange: layout.columnCenterX...layout.columnWidth,
                excludingNodeIDs: [predecessor.id],
                lineKind: lineKind,
                color: color,
                nodesByColumn: nodesByColumn,
                edgePiecesByColumn: &edgePiecesByColumn
            )

            if predecessor.column + 1 < node.column {
                for column in (predecessor.column + 1)..<node.column {
                    appendHorizontalSegments(
                        edgeID: edgeID,
                        column: column,
                        lane: predecessor.lane,
                        baseRange: 0...layout.columnWidth,
                        excludingNodeIDs: [],
                        lineKind: lineKind,
                        color: color,
                        nodesByColumn: nodesByColumn,
                        edgePiecesByColumn: &edgePiecesByColumn
                    )
                }
            }

            edgePiecesByColumn[node.column, default: []].append(
                .init(
                    id: "\(edgeID):target-curve",
                    color: color,
                    lineKind: lineKind,
                    segment: .targetCurve(
                        startLane: predecessor.lane,
                        endLane: node.lane
                    )
                )
            )
        }

        private func appendHorizontalSegments(
            edgeID: String,
            column: Int,
            lane: Int,
            baseRange: ClosedRange<CGFloat>,
            excludingNodeIDs: Set<String>,
            lineKind: TraceViewer.EdgeLineKind,
            color: Color,
            nodesByColumn: [Int: [TraceViewerGraph.OverviewGraphNode]],
            edgePiecesByColumn: inout [Int: [EdgePiece]]
        ) {
            let blockers = (nodesByColumn[column] ?? [])
                .filter { node in
                    node.lane == lane && !excludingNodeIDs.contains(node.id)
                }
                .sorted { $0.id < $1.id }

            let segments = horizontalSegments(
                in: baseRange,
                blockers: blockers
            )

            for (index, segment) in segments.enumerated() {
                edgePiecesByColumn[column, default: []].append(
                    .init(
                        id: "\(edgeID):horizontal:\(column):\(index)",
                        color: color,
                        lineKind: lineKind,
                        segment: .horizontal(
                            lane: lane,
                            startX: segment.lowerBound,
                            endX: segment.upperBound
                        )
                    )
                )
            }
        }

        private func horizontalSegments(
            in baseRange: ClosedRange<CGFloat>,
            blockers: [TraceViewerGraph.OverviewGraphNode]
        ) -> [ClosedRange<CGFloat>] {
            var segments = [baseRange]

            for _ in blockers {
                let blockerLower = max(layout.columnCenterX - layout.blockerClearance, 0)
                let blockerUpper = min(layout.columnCenterX + layout.blockerClearance, layout.columnWidth)
                let blockerRange = blockerLower...blockerUpper

                segments = segments.flatMap { segment in
                    split(segment: segment, removing: blockerRange)
                }
            }

            return segments.filter { $0.upperBound - $0.lowerBound > 0.5 }
        }

        private func split(
            segment: ClosedRange<CGFloat>,
            removing blockerRange: ClosedRange<CGFloat>
        ) -> [ClosedRange<CGFloat>] {
            if blockerRange.upperBound <= segment.lowerBound || blockerRange.lowerBound >= segment.upperBound {
                return [segment]
            }

            var result: [ClosedRange<CGFloat>] = []
            if blockerRange.lowerBound > segment.lowerBound {
                result.append(segment.lowerBound...min(blockerRange.lowerBound, segment.upperBound))
            }
            if blockerRange.upperBound < segment.upperBound {
                result.append(max(blockerRange.upperBound, segment.lowerBound)...segment.upperBound)
            }
            return result
        }

        private func edgeColor(
            for lineKind: TraceViewer.EdgeLineKind,
            predecessorID: String,
            nodeID: String
        ) -> Color {
            let baseColor: Color = {
                switch lineKind {
                case .solid:
                    return ViewerTheme.solidBranchLine
                case .dotted:
                    return ViewerTheme.dottedBranchLine
                }
            }()

            return baseColor.opacity(
                min(graphOpacity(for: predecessorID), graphOpacity(for: nodeID))
            )
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

        private func graphOpacity(for nodeID: String) -> Double {
            selectableNodeIDSet.contains(nodeID) ? 1 : layout.mutedOpacity
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
        let column: TimelineOverviewView.Column
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
                        layout: layout
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
        let piece: TimelineOverviewView.EdgePiece
        let layout: TimelineOverviewView.Layout

        var body: some View {
            path
                .stroke(
                    piece.color,
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
