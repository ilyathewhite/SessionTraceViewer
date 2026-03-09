import SwiftUI

extension TraceViewer {
    struct TimelineOverviewView: View {
        typealias Nsp = TraceViewer

        private struct ScrollVisibilityInputs: Equatable {
            let selectedNodeID: String?
            let selectedNodeVisibleXRange: ClosedRange<CGFloat>?
        }

        let nodes: [TraceViewer.StoreState.OverviewGraphNode]
        let selectableNodeIDs: [String]
        let tooltipTextByNodeID: [String: String]
        let selectedNodeID: String?
        let maxLane: Int
        let onSelectNode: (String) -> Void

        private let nodeSpacing: CGFloat = 48
        private let laneSpacing: CGFloat = 34
        private let graphInset: CGFloat = 24
        private let nodeHitArea: CGFloat = 30
        private let tooltipMaxWidth: CGFloat = 240
        private let mutedOpacity: Double = 0.26
        private let scrollVisibilityPadding: CGFloat = 8
        private let selectionRingGap: CGFloat = 2
        private let selectionRingThickness: CGFloat = 2
        private let contentScrollTargetID = "overview-content"
        @State private var hoveredNodeID: String?
        @State private var visibleRect: CGRect = .zero
        @State private var pendingScrollAnimation: Bool?

        private var maxColumn: Int {
            nodes.map(\.column).max() ?? 0
        }

        private var laneCount: Int {
            let visibleMaxLane = nodes.map(\.lane).max() ?? maxLane
            return max(visibleMaxLane + 1, 1)
        }

        private var graphWidth: CGFloat {
            guard maxColumn > 0 else { return graphInset * 2 + 1 }
            return graphInset * 2 + CGFloat(maxColumn) * nodeSpacing
        }

        private var graphHeight: CGFloat {
            graphInset * 2 + CGFloat(max(laneCount - 1, 0)) * laneSpacing
        }

        var body: some View {
            graphSurface
        }

        private var graphSurface: some View {
            ZStack {
                ViewerTheme.timelineGraphBackground

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .frame(width: graphWidth, height: graphHeight)
                                .id(contentScrollTargetID)
                            graphContent
                        }
                    }
                    .onAppear {
                        scheduleScrollToSelected(using: proxy, animated: false)
                    }
                    .onChange(of: scrollVisibilityInputs) { oldValue, newValue in
                        scheduleScrollToSelected(
                            using: proxy,
                            animated: oldValue.selectedNodeID != newValue.selectedNodeID
                        )
                    }
                    .onScrollGeometryChange(for: CGRect.self) { geometry in
                        geometry.visibleRect
                    } action: { _, newValue in
                        visibleRect = newValue
                        flushPendingScroll(using: proxy)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: graphHeight, maxHeight: graphHeight)
        }

        private var graphContent: some View {
            ZStack {
                Canvas { context, size in
                    drawGraph(context: &context, size: size)
                }

                ForEach(nodes, id: \.id) { node in
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: nodeHitArea, height: nodeHitArea)
                        .position(point(for: node))
                        .onTapGesture {
                            onSelectNode(node.id)
                        }
                }

                if let hoveredTooltip {
                    Nsp.GraphNodeTooltip(
                        text: hoveredTooltip.text,
                        width: hoveredTooltip.width
                    )
                    .position(tooltipPosition(for: hoveredTooltip.nodePoint, tooltipWidth: hoveredTooltip.width))
                    .allowsHitTesting(false)
                    .zIndex(10)
                }
            }
            .frame(width: graphWidth, height: graphHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard let id = nodeID(at: gesture.location) else { return }
                        if id != selectedNodeID {
                            onSelectNode(id)
                        }
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredNodeID = hoveredNodeID(at: location)
                case .ended:
                    hoveredNodeID = nil
                }
            }
        }

        private var hoveredTooltip: (text: String, nodePoint: CGPoint, width: CGFloat)? {
            guard let hoveredNodeID,
                  let node = nodes.first(where: { $0.id == hoveredNodeID }),
                  let text = tooltipTextByNodeID[hoveredNodeID],
                  !text.isEmpty else {
                return nil
            }

            let nodePoint = point(for: node)
            let width = tooltipWidth(for: text)
            return (text, nodePoint, width)
        }

        private func tooltipPosition(for nodePoint: CGPoint, tooltipWidth: CGFloat) -> CGPoint {
            let xPadding = tooltipWidth / 2 + 10
            let clampedX = min(max(nodePoint.x, xPadding), max(graphWidth - xPadding, xPadding))
            let y = max(16, nodePoint.y - 22)
            return CGPoint(x: clampedX, y: y)
        }

        private func tooltipWidth(for text: String) -> CGFloat {
            let minWidth: CGFloat = 56
            let horizontalPadding: CGFloat = 16
            let averageCharacterWidth: CGFloat = 6.2
            let estimatedTextWidth = CGFloat(text.count) * averageCharacterWidth
            return min(max(estimatedTextWidth + horizontalPadding, minWidth), tooltipMaxWidth)
        }

        private var selectedNode: TraceViewer.StoreState.OverviewGraphNode? {
            guard let selectedNodeID,
                  let node = nodes.first(where: { $0.id == selectedNodeID }) else {
                return nil
            }
            return node
        }

        private var selectedNodeVisibleXRange: ClosedRange<CGFloat>? {
            guard let node = selectedNode else { return nil }
            let selectionRadius = selectionRingOuterRadius(for: nodeRadius(selected: true)) + scrollVisibilityPadding
            let centerX = point(for: node).x
            return max(centerX - selectionRadius, 0)...min(centerX + selectionRadius, graphWidth)
        }

        private var scrollVisibilityInputs: ScrollVisibilityInputs {
            .init(
                selectedNodeID: selectedNodeID,
                selectedNodeVisibleXRange: selectedNodeVisibleXRange
            )
        }

        private var desiredScrollOffset: CGFloat? {
            guard let selectedNodeVisibleXRange,
                  visibleRect.width > 0 else {
                return nil
            }

            let maxScrollableX = max(graphWidth - visibleRect.width, 0)
            guard maxScrollableX > 0 else { return 0 }

            let currentOffset = min(max(visibleRect.minX, 0), maxScrollableX)
            let visibleMinX = currentOffset
            let visibleMaxX = currentOffset + visibleRect.width

            if selectedNodeVisibleXRange.lowerBound >= visibleMinX,
               selectedNodeVisibleXRange.upperBound <= visibleMaxX {
                return currentOffset
            }
            if selectedNodeVisibleXRange.lowerBound < visibleMinX {
                return max(selectedNodeVisibleXRange.lowerBound, 0)
            }
            return min(selectedNodeVisibleXRange.upperBound - visibleRect.width, maxScrollableX)
        }

        private func scheduleScrollToSelected(using proxy: ScrollViewProxy, animated: Bool) {
            guard visibleRect.width > 0 else {
                pendingScrollAnimation = animated
                return
            }
            pendingScrollAnimation = nil
            scrollToSelectedIfNeeded(proxy, animated: animated)
        }

        private func flushPendingScroll(using proxy: ScrollViewProxy) {
            guard let animated = pendingScrollAnimation,
                  visibleRect.width > 0 else {
                return
            }
            pendingScrollAnimation = nil
            scrollToSelectedIfNeeded(proxy, animated: animated)
        }

        private func scrollToSelectedIfNeeded(_ proxy: ScrollViewProxy, animated: Bool) {
            guard let desiredScrollOffset else { return }
            let maxScrollableX = max(graphWidth - visibleRect.width, 0)
            guard maxScrollableX > 0 else { return }

            let currentOffset = min(max(visibleRect.minX, 0), maxScrollableX)
            guard abs(desiredScrollOffset - currentOffset) > 0.5 else { return }

            let anchorX = min(max(desiredScrollOffset / maxScrollableX, 0), 1)
            let anchor = UnitPoint(x: anchorX, y: 0.5)
            if animated {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(contentScrollTargetID, anchor: anchor)
                }
            }
            else {
                proxy.scrollTo(contentScrollTargetID, anchor: anchor)
            }
        }

        private func point(for node: TraceViewer.StoreState.OverviewGraphNode) -> CGPoint {
            CGPoint(
                x: graphInset + CGFloat(node.column) * nodeSpacing,
                y: graphHeight - graphInset - CGFloat(max(node.lane, 0)) * laneSpacing
            )
        }

        private func nodeRadius(selected: Bool) -> CGFloat {
            5
        }

        private func selectionRingInnerRadius(for nodeRadius: CGFloat) -> CGFloat {
            nodeRadius + selectionRingGap
        }

        private func selectionRingOuterRadius(for nodeRadius: CGFloat) -> CGFloat {
            selectionRingInnerRadius(for: nodeRadius) + selectionRingThickness
        }

        private func color(for kind: TraceViewer.EventColorKind) -> Color {
            ViewerTheme.graphColor(for: kind)
        }

        private func isSelectableNode(_ id: String) -> Bool {
            selectableNodeIDs.contains(id)
        }

        private func graphOpacity(for nodeID: String) -> Double {
            isSelectableNode(nodeID) ? 1 : mutedOpacity
        }

        private func drawGraph(context: inout GraphicsContext, size: CGSize) {
            guard !nodes.isEmpty, size.width > 0, size.height > 0 else { return }

            let indexByID = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
            let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            let guideStartX = graphInset
            let guideEndX = graphWidth - graphInset

            // Draw only the baseline (main/state lane). Effect lanes are represented
            // by actual graph edges so unrelated effects do not look like one thread.
            let mainLaneY = graphHeight - graphInset
            let mainLanePath = Path { path in
                path.move(to: CGPoint(x: guideStartX, y: mainLaneY))
                path.addLine(to: CGPoint(x: guideEndX, y: mainLaneY))
            }
            context.stroke(
                mainLanePath,
                with: .color(ViewerTheme.overviewGuide),
                lineWidth: 1.15
            )

            for (index, node) in nodes.enumerated() {
                let toPoint = point(for: node)
                for predecessorID in node.predecessorIDs {
                    guard let fromIndex = indexByID[predecessorID], fromIndex < index else { continue }
                    guard let fromNode = nodeByID[predecessorID] else { continue }
                    let fromLane = fromNode.lane
                    let toLane = node.lane
                    let fromPoint = point(for: fromNode)
                    let lineKind = node.edgeLineKindByPredecessorID[predecessorID] ?? .solid
                    let strokeStyle: StrokeStyle = {
                        switch lineKind {
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
                    }()
                    let edgeColor: Color = {
                        switch lineKind {
                        case .solid:
                            return ViewerTheme.solidBranchLine
                        case .dotted:
                            return ViewerTheme.dottedBranchLine
                        }
                    }()
                    let resolvedEdgeColor = edgeColor.opacity(
                        min(graphOpacity(for: predecessorID), graphOpacity(for: node.id))
                    )
                    if fromLane == toLane, toPoint.x - fromPoint.x > nodeSpacing {
                        // Avoid drawing long same-lane lines through unrelated nodes.
                        // We cut tiny gaps around intermediate nodes on the same lane.
                        let intermediateIndices = (fromIndex + 1)..<index
                        let blockerXs = intermediateIndices.compactMap { midIndex -> CGFloat? in
                            let blockerNode = nodes[midIndex]
                            guard blockerNode.lane == fromLane else { return nil }
                            let blockerPoint = point(for: blockerNode)
                            guard blockerPoint.x > fromPoint.x, blockerPoint.x < toPoint.x else { return nil }
                            return blockerPoint.x
                        }
                        if blockerXs.isEmpty {
                            let directPath = Path { path in
                                path.move(to: fromPoint)
                                path.addLine(to: toPoint)
                            }
                            context.stroke(
                                directPath,
                                with: .color(resolvedEdgeColor),
                                style: strokeStyle
                            )
                        }
                        else {
                            let clearance = nodeRadius(selected: false) + 3.2
                            var segmentStartX = fromPoint.x
                            for blockerX in blockerXs {
                                let segmentEndX = blockerX - clearance
                                if segmentEndX > segmentStartX {
                                    let segmentPath = Path { path in
                                        path.move(to: CGPoint(x: segmentStartX, y: fromPoint.y))
                                        path.addLine(to: CGPoint(x: segmentEndX, y: fromPoint.y))
                                    }
                                    context.stroke(
                                        segmentPath,
                                        with: .color(resolvedEdgeColor),
                                        style: strokeStyle
                                    )
                                }
                                segmentStartX = max(segmentStartX, blockerX + clearance)
                            }
                            if toPoint.x > segmentStartX {
                                let tailPath = Path { path in
                                    path.move(to: CGPoint(x: segmentStartX, y: toPoint.y))
                                    path.addLine(to: toPoint)
                                }
                                context.stroke(
                                    tailPath,
                                    with: .color(resolvedEdgeColor),
                                    style: strokeStyle
                                )
                            }
                        }
                    }
                    else {
                        let connection = connectionPath(
                            from: fromPoint,
                            fromLane: fromLane,
                            to: toPoint,
                            toLane: toLane
                        )
                        context.stroke(
                            connection,
                            with: .color(resolvedEdgeColor),
                            style: strokeStyle
                        )
                    }
                }
            }

            for node in nodes {
                let center = point(for: node)
                let selected = node.id == selectedNodeID
                let radius = nodeRadius(selected: selected)
                let fillColor = color(for: node.colorKind).opacity(graphOpacity(for: node.id))

                let nodeRect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                context.fill(Path(ellipseIn: nodeRect), with: .color(fillColor))

                if selected {
                    let outerRadius = selectionRingOuterRadius(for: radius)
                    let innerRadius = selectionRingInnerRadius(for: radius)
                    let outerRect = CGRect(
                        x: center.x - outerRadius,
                        y: center.y - outerRadius,
                        width: outerRadius * 2,
                        height: outerRadius * 2
                    )
                    let innerRect = CGRect(
                        x: center.x - innerRadius,
                        y: center.y - innerRadius,
                        width: innerRadius * 2,
                        height: innerRadius * 2
                    )
                    var selectionRing = Path()
                    selectionRing.addEllipse(in: outerRect)
                    selectionRing.addEllipse(in: innerRect)
                    context.fill(
                        selectionRing,
                        with: .color(fillColor),
                        style: FillStyle(eoFill: true)
                    )
                }
            }
        }

        private func nodeID(at location: CGPoint) -> String? {
            guard !nodes.isEmpty else { return nil }
            let localX = min(
                max(location.x - graphInset, 0),
                CGFloat(maxColumn) * nodeSpacing
            )
            let rawColumn = Int((localX / nodeSpacing).rounded())
            let targetColumn = nodes.min { lhs, rhs in
                abs(lhs.column - rawColumn) < abs(rhs.column - rawColumn)
            }?.column
            guard let targetColumn else { return nil }

            return nodes
                .filter { $0.column == targetColumn }
                .min { lhs, rhs in
                    let leftDistance = abs(point(for: lhs).y - location.y)
                    let rightDistance = abs(point(for: rhs).y - location.y)
                    if leftDistance == rightDistance {
                        return lhs.lane < rhs.lane
                    }
                    return leftDistance < rightDistance
                }?
                .id
        }

        private func hoveredNodeID(at location: CGPoint) -> String? {
            guard !nodes.isEmpty else { return nil }

            let hoverRadius = nodeHitArea / 2
            var bestMatch: (id: String, distanceSquared: CGFloat)?

            for node in nodes {
                let center = point(for: node)
                let dx = center.x - location.x
                let dy = center.y - location.y
                let distanceSquared = dx * dx + dy * dy
                guard distanceSquared <= hoverRadius * hoverRadius else { continue }

                if let currentBestMatch = bestMatch {
                    if distanceSquared < currentBestMatch.distanceSquared {
                        bestMatch = (node.id, distanceSquared)
                    }
                }
                else {
                    bestMatch = (node.id, distanceSquared)
                }
            }

            return bestMatch?.id
        }

        private func connectionPath(from: CGPoint, fromLane: Int, to: CGPoint, toLane: Int) -> Path {
            let horizontalDistance = max(to.x - from.x, nodeSpacing)
            let laneDelta = fromLane - toLane

            return Path { path in
                path.move(to: from)

                if abs(from.y - to.y) < 0.5 {
                    path.addLine(to: to)
                    return
                }

                // Use geometrically similar bend rectangles:
                // same height:width ratio for every non-flat connection.
                let verticalDistance = abs(to.y - from.y)
                let rectangleHeightToWidth: CGFloat = 1.12
                let desiredCurveRun = verticalDistance / rectangleHeightToWidth
                let curveRun = min(max(desiredCurveRun, nodeSpacing * 0.42), horizontalDistance * 0.90)
                // Smaller control fractions make the bend rounder and less line-like.
                let controlIn: CGFloat = 0.22
                let controlOut: CGFloat = 0.22

                if laneDelta > 0 {
                    // Merging from an effect lane down into main (or lower lane):
                    // stay parallel for most of the distance, then curve late.
                    let turnX = max(from.x + nodeSpacing * 0.24, to.x - curveRun)
                    if turnX > from.x {
                        path.addLine(to: CGPoint(x: turnX, y: from.y))
                    }
                    let run = max(to.x - turnX, 1)
                    path.addCurve(
                        to: to,
                        control1: CGPoint(x: turnX + run * controlIn, y: from.y),
                        control2: CGPoint(x: to.x - run * controlOut, y: to.y)
                    )
                    return
                }

                // Spawning upward from main/effect to a higher lane: peel off earlier.
                let turnX = min(to.x - nodeSpacing * 0.24, from.x + curveRun)
                if turnX > from.x {
                    path.addLine(to: CGPoint(x: turnX, y: from.y))
                }
                let run = max(to.x - turnX, 1)
                path.addCurve(
                    to: to,
                    control1: CGPoint(x: turnX + run * controlIn, y: from.y),
                    control2: CGPoint(x: to.x - run * controlOut, y: to.y)
                )
            }
        }
    }
}
