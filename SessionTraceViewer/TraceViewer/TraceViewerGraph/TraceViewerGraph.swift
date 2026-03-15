//
//  TraceViewerGraph.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import Foundation
import ReducerArchitecture
#if canImport(AppKit)
import AppKit
#endif

enum TraceViewerGraph: StoreNamespace {
    enum OverviewMetrics {
        static let columnWidth: CGFloat = 48
        static let laneSpacing: CGFloat = 34
        static let verticalInset: CGFloat = 24
        static let nodeRadius: CGFloat = 5
        static let nodeHitArea: CGFloat = 30
        static let selectionRingGap: CGFloat = 2
        static let selectionRingThickness: CGFloat = 2
        static let blockerClearance: CGFloat = nodeRadius + 3.2
        static let tooltipVerticalOffset: CGFloat = 22
        static let tooltipMaxWidth: CGFloat = 240
        static let mutedOpacity: Double = 0.26
    }

    struct PublishedValue: Equatable {
        let timelineID: String
        let shouldFocusTimelineList: Bool
    }

    struct Input: Equatable {
        var visibleTimelineIDs: [String]
        var selectableTimelineIDs: [String]
        var selectedTimelineID: String?
    }

    struct OverviewGraphNode: Identifiable, Equatable {
        enum Kind: Equatable {
            case state
            case flow
            case mutation
            case effect
            case batch
        }

        let id: String
        let storeInstanceID: String
        let kind: Kind
        let colorKind: TraceViewer.EventColorKind
        let column: Int
        let lane: Int
        let predecessorIDs: [String]
        let edgeLineKindByPredecessorID: [String: TraceViewer.EdgeLineKind]
        let timelineID: String?
        let selectionTimelineID: String?
    }

    struct OverviewEdgePiece: Identifiable, Equatable {
        enum Segment: Equatable {
            case horizontal(lane: Int, startX: CGFloat, endX: CGFloat)
            case sourceCurve(startLane: Int, endLane: Int)
            case targetCurve(startLane: Int, endLane: Int)
            case localCurve(startLane: Int, endLane: Int)
        }

        let id: String
        let predecessorID: String
        let nodeID: String
        let lineKind: TraceViewer.EdgeLineKind
        let segment: Segment
    }

    struct OverviewColumn: Identifiable, Equatable {
        let id: Int
        let nodes: [OverviewGraphNode]
        let edgePieces: [OverviewEdgePiece]
    }

    struct TrackSegment: Identifiable, Equatable {
        let id: String
        let storeInstanceID: String
        let storeName: String
        let startColumn: Int
        let endColumn: Int
        let extendsToTrailingEdge: Bool
        let baseLane: Int
        let maxLane: Int
        let trackMaxLane: Int
        let showsDivider: Bool
        let requiredColumnWidth: CGFloat
    }

    struct TrackRow: Identifiable, Equatable {
        let id: Int
        let baseLane: Int
        let maxLane: Int
        let segments: [TrackSegment]
    }

    struct GraphSource {
        let nodes: [OverviewGraphNode]
        let nodeByID: [String: OverviewGraphNode]
        let graphIDByTimelineID: [String: String]
        let maxLane: Int
        let tooltipTextByNodeID: [String: String]
        let trackRows: [TrackRow]
    }

    typealias StoreEnvironment = Never
    typealias EffectAction = Never

    enum MutatingAction {
        case replaceViewerData(TraceViewer.ViewerData)
        case replaceTraceCollection(SessionTraceCollection)
        case updateInput(Input)
        case selectNode(id: String, shouldFocusTimelineList: Bool)
        case selectAdjacentNode(offset: Int, shouldFocusTimelineList: Bool)
    }

    struct Presentation: Equatable {
        var visibleNodes: [OverviewGraphNode]
        var columns: [OverviewColumn]
        var nodeByID: [String: OverviewGraphNode]
        var selectableNodeIDs: [String]
        var selectableNodeIDSet: Set<String>
        var tooltipTextByNodeID: [String: String]
        var tooltipWidthByNodeID: [String: CGFloat]
        var selectedNodeID: String?
        var selectedColumnID: Int?
        var selectedStoreInstanceID: String?
        var visibleMaxLane: Int
        var maxLane: Int
        var trackRows: [TrackRow]
        var displayLaneByLane: [Int: Int]
        var columnWidth: CGFloat
        var timelineSelectionIDByNodeID: [String: String]
    }

    struct StoreState {
        let timelineData: TraceViewer.TimelineData
        let overviewGraphNodes: [OverviewGraphNode]
        let overviewGraphNodeByID: [String: OverviewGraphNode]
        let overviewGraphIDByTimelineID: [String: String]
        let overviewGraphMaxLane: Int
        let overviewGraphTooltipTextByID: [String: String]

        var input: Input
        var presentation: Presentation
        var visibleOverviewGraphNodes: [OverviewGraphNode]
        var selectableVisibleOverviewGraphNodeIDs: [String]
        var selectedOverviewGraphNodeID: String?
    }
}

extension TraceViewerGraph {
    fileprivate static let segmentLabelFontSize: CGFloat = 12
    fileprivate static let segmentLabelWidthPadding: CGFloat = 2
    fileprivate static let segmentLabelHorizontalInset: CGFloat = 6

    static func tooltipWidth(for text: String) -> CGFloat {
        let minWidth: CGFloat = 56
        let horizontalPadding: CGFloat = 16
        let averageCharacterWidth: CGFloat = 6.2
        let estimatedTextWidth = CGFloat(text.count) * averageCharacterWidth
        return min(
            max(estimatedTextWidth + horizontalPadding, minWidth),
            OverviewMetrics.tooltipMaxWidth
        )
    }

    static func segmentLabelWidth(for title: String) -> CGFloat {
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: segmentLabelFontSize, weight: .semibold)
        let textWidth = NSString(string: title).size(withAttributes: [.font: font]).width
        return ceil(textWidth + segmentLabelWidthPadding)
        #else
        let averageCharacterWidth: CGFloat = 6.6
        return ceil(CGFloat(title.count) * averageCharacterWidth + segmentLabelWidthPadding)
        #endif
    }

    static func requiredColumnWidth(
        forStoreName storeName: String,
        columnsSpanned: Int
    ) -> CGFloat {
        let requiredSegmentWidth = segmentLabelWidth(for: storeName)
            + segmentLabelHorizontalInset * 2
        return ceil(requiredSegmentWidth / CGFloat(max(columnsSpanned, 1)))
    }

    static func displayLaneByLane(
        trackRows: [TrackRow]
    ) -> [Int: Int] {
        trackRows.reduce(into: [:]) { partialResult, trackRow in
            for lane in trackRow.baseLane...trackRow.maxLane {
                partialResult[lane] = trackRow.baseLane + trackRow.maxLane - lane
            }
        }
    }
}

extension TraceViewerGraph {
    @MainActor
    static func store(
        viewerData: TraceViewer.ViewerData,
        input: Input
    ) -> Store {
        Store(.init(viewerData: viewerData, input: input), env: nil)
    }

    @MainActor
    static func store(
        traceCollection: SessionTraceCollection,
        input: Input
    ) -> Store {
        store(
            viewerData: TraceViewer.makeViewerData(
                traceSession: TraceViewer.traceSession(from: traceCollection),
                storeVisibilityByID: [
                    traceCollection.sessionGraph.storeInstanceID.rawValue: true
                ]
            ),
            input: input
        )
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .replaceViewerData(let viewerData):
            state.replaceViewerData(viewerData)
            return .none

        case .replaceTraceCollection(let traceCollection):
            state.replaceTraceCollection(traceCollection)
            return .none

        case .updateInput(let input):
            state.updateInput(input)
            return .none

        case .selectNode(let id, let shouldFocusTimelineList):
            guard let selection = state.selectNode(id: id, shouldFocusTimelineList: shouldFocusTimelineList) else {
                return .none
            }
            return .action(.publish(selection))

        case .selectAdjacentNode(let offset, let shouldFocusTimelineList):
            guard let selection = state.selectAdjacentNode(
                offset: offset,
                shouldFocusTimelineList: shouldFocusTimelineList
            ) else {
                return .none
            }
            return .action(.publish(selection))
        }
    }
}
