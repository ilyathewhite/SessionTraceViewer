//
//  TraceViewerUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import ReducerArchitecture
import SwiftUI

extension TraceViewer: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = TraceViewer
        @ObservedObject var store: Store
        @Namespace private var timelineFocusScope
        @FocusState private var timelineListHasFocus: Bool
        @Environment(\.controlActiveState) private var controlActiveState
        @Environment(\.resetFocus) private var resetFocus
        private let timelineListIdealWidth: CGFloat = 420
        private let timelineListMinimumWidth: CGFloat = 220

        init(_ store: Store) {
            self.store = store
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    ViewerTheme.background
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        overviewSection

                        Divider()

                        HStack(spacing: 0) {
                            timelineListPanel
                                .frame(width: timelineListWidth(for: geometry.size.width))
                                .frame(maxHeight: .infinity)

                            Divider()

                            inspectorPanel
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.borderless)
            .preferredColorScheme(.light)
        }

        private func timelineListWidth(for availableWidth: CGFloat) -> CGFloat {
            let preferredWidth = min(
                timelineListIdealWidth,
                max(timelineListMinimumWidth, availableWidth * 0.42)
            )
            return min(max(availableWidth - 1, 0), preferredWidth)
        }

        private var selectionIsFocused: Bool {
            timelineListHasFocus && controlActiveState == .key
        }

        private var overviewPanel: some View {
            TimelineOverviewView(
                nodes: store.state.visibleOverviewGraphNodes,
                tooltipTextByNodeID: store.state.itemsByID.mapValues(\.title),
                selectedNodeID: store.state.selectedOverviewGraphNodeID,
                maxLane: store.state.overviewGraphMaxLane,
                onSelectNode: { graphNodeID in
                    guard let timelineID = store.state.timelineSelectionID(forOverviewGraphNodeID: graphNodeID) else {
                        return
                    }
                    send(.selectEvent(id: timelineID))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)
            .viewerPanelCardStyle()
        }

        private var overviewSection: some View {
            overviewPanel
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(ViewerTheme.overviewAreaBackground)
        }

        private var timelineListPanel: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(store.state.visibleItems) { item in
                            TimelineEventRow(
                                item: item,
                                isSelected: item.id == store.state.selectedID,
                                selectionIsFocused: selectionIsFocused
                            )
                            .id(item.id)
                            .onTapGesture {
                                send(.selectEvent(id: item.id))
                            }
                        }
                    }
                    .padding(10)
                }
                .contentShape(Rectangle())
                .focusable(true, interactions: .edit)
                .focusEffectDisabled()
                .focused($timelineListHasFocus)
                .focusScope(timelineFocusScope)
                .prefersDefaultFocus(true, in: timelineFocusScope)
                .onMoveCommand(perform: handleMove)
                .onChange(of: store.state.selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                    if !timelineListHasFocus {
                        resetFocus(in: timelineFocusScope)
                    }
                }
            }
            .background(ViewerTheme.timelinePanelBackground)
        }

        private var inspectorPanel: some View {
            EventInspectorView(
                item: store.state.selectedItem,
                previousStateItem: store.state.selectedPreviousStateItem
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ViewerTheme.inspectorPanelBackground)
        }

        private func send(_ action: MutatingAction) {
            store.send(.mutating(action))
        }

        private func handleMove(_ direction: MoveCommandDirection) {
            guard timelineListHasFocus else { return }
            switch direction {
            case .up:
                send(.selectPreviousVisible)
            case .down:
                send(.selectNextVisible)
            case .left:
                send(.selectPreviousGraphNode)
            case .right:
                send(.selectNextGraphNode)
            default:
                break
            }
        }
    }
}

private struct TimelineOverviewView: View {
    let nodes: [TraceViewer.StoreState.OverviewGraphNode]
    let tooltipTextByNodeID: [String: String]
    let selectedNodeID: String?
    let maxLane: Int
    let onSelectNode: (String) -> Void

    private let nodeSpacing: CGFloat = 48
    private let laneSpacing: CGFloat = 34
    private let graphInset: CGFloat = 24
    private let nodeHitArea: CGFloat = 30
    private let tooltipMaxWidth: CGFloat = 240
    @State private var hoveredNodeID: String?

    private var maxColumn: Int {
        nodes.map(\.column).max() ?? 0
    }

    private var laneCount: Int {
        let visibleMaxLane = nodes.map { $0.lane }.max() ?? maxLane
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
        return ZStack {
            ViewerTheme.timelineGraphBackground

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    graphContent
                }
                .onAppear {
                    scrollToSelected(proxy)
                }
                .onChange(of: selectedNodeID) { _, _ in
                    scrollToSelected(proxy)
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
                    .id(node.id)
                    .onTapGesture {
                        onSelectNode(node.id)
                    }
            }

            if let hoveredTooltip {
                GraphNodeTooltip(text: hoveredTooltip.text)
                    .frame(maxWidth: tooltipMaxWidth)
                    .position(hoveredTooltip.position)
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

    private var hoveredTooltip: (text: String, position: CGPoint)? {
        guard let hoveredNodeID,
              let node = nodes.first(where: { $0.id == hoveredNodeID }),
              let text = tooltipTextByNodeID[hoveredNodeID],
              !text.isEmpty else {
            return nil
        }

        let nodePoint = point(for: node)
        let xPadding = tooltipMaxWidth / 2 + 10
        let clampedX = min(max(nodePoint.x, xPadding), max(graphWidth - xPadding, xPadding))
        let y = max(16, nodePoint.y - 22)
        return (text, CGPoint(x: clampedX, y: y))
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy) {
        guard let selectedNodeID else { return }
        proxy.scrollTo(selectedNodeID)
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

    private func color(for kind: TraceViewer.EventColorKind) -> Color {
        ViewerTheme.graphColor(for: kind)
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
                            with: .color(edgeColor),
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
                                    with: .color(edgeColor),
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
                                with: .color(edgeColor),
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
                        with: .color(edgeColor),
                        style: strokeStyle
                    )
                }
            }
        }

        for node in nodes {
            let center = point(for: node)
            let selected = node.id == selectedNodeID
            let radius = nodeRadius(selected: selected)
            let fillColor = color(for: node.colorKind)

            let nodeRect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            context.fill(Path(ellipseIn: nodeRect), with: .color(fillColor))

            if selected {
                let ringRadius = radius + 2.6
                let ringRect = CGRect(
                    x: center.x - ringRadius,
                    y: center.y - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                )
                context.stroke(
                    Path(ellipseIn: ringRect),
                    with: .color(ViewerTheme.overviewSelectionRing),
                    lineWidth: 1
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
            } else {
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

private struct GraphNodeTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.82))
            )
            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
    }
}
