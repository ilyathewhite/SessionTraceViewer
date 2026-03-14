//
//  TraceViewer.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import Foundation
import ReducerArchitecture

enum TraceViewer: StoreNamespace {
    typealias PublishedValue = Void
    typealias StoreEnvironment = Never
    typealias EffectAction = Never

    enum MutatingAction {
        case replaceTraceSession(TraceSession)
        case replaceTraceCollection(SessionTraceCollection)
        case setStoreVisibility(id: String, isVisible: Bool)
        case toggleStoreVisibility(id: String)
    }

    enum EventKind: String, Equatable, Hashable {
        case state
        case flow
        case mutation
        case effect
        case batch
    }

    enum EventColorKind: Equatable, Hashable {
        case state
        case mutation
        case effect
        case batch
        case publish
        case cancel
    }

    enum EdgeLineKind: Equatable, Hashable {
        case solid
        case dotted
    }

    struct TimelineItem: Identifiable, Equatable {
        private static let subtitleSeparator = " • "

        let id: String
        let localNodeID: String
        let storeInstanceID: String
        let storeName: String
        let order: Int
        let kind: EventKind
        let colorKind: EventColorKind
        let title: String
        let subtitle: String
        let date: Date?
        let childIDs: [String]
        let node: SessionGraph.Node

        var timeLabel: String {
            EventInspectorFormatter.timestamp(date)
        }

        var displayStoreName: String {
            storeName
        }

        var subtitleSourceLabel: String? {
            guard let range = subtitle.range(of: Self.subtitleSeparator) else { return nil }
            let prefix = String(subtitle[..<range.lowerBound])
            switch prefix.uppercased() {
            case "USER", "CODE":
                return prefix.uppercased()
            default:
                return nil
            }
        }

        var subtitleDetailLabel: String? {
            guard subtitleSourceLabel != nil,
                  let range = subtitle.range(of: Self.subtitleSeparator) else { return nil }
            return String(subtitle[range.upperBound...])
        }

        var isUserSourceEvent: Bool {
            subtitleSourceLabel == "USER"
        }
    }

    struct StoreLayer: Identifiable, Equatable {
        let id: String
        let displayName: String
        let isVisible: Bool
    }

    struct ViewerData: Equatable {
        let traceSession: TraceSession
        let visibleStoreTraces: [TraceSession.StoreTrace]
        let primaryTraceCollection: SessionTraceCollection
        let orderedIDs: [String]
        let itemsByID: [String: TimelineItem]
        let childrenByParentID: [String: [String]]
        let descendantCountByID: [String: Int]
        let overviewGraphNodes: [TraceViewerGraph.OverviewGraphNode]
        let overviewGraphNodeByID: [String: TraceViewerGraph.OverviewGraphNode]
        let overviewGraphIDByTimelineID: [String: String]
        let overviewGraphMaxLane: Int
        let overviewGraphTooltipTextByID: [String: String]
        let graphTrackRows: [TraceViewerGraph.TrackRow]
    }

    struct StoreState {
        var traceSession: TraceSession
        var storeVisibilityByID: [String: Bool]
        var viewerData: ViewerData
        var contentVersion = 0
    }
}

extension TraceViewer {
    @MainActor
    static func store(traceSession: TraceSession) -> Store {
        Store(.init(traceSession: traceSession), env: nil)
    }

    @MainActor
    static func store(traceCollection: SessionTraceCollection) -> Store {
        store(traceSession: traceSession(from: traceCollection))
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .replaceTraceSession(let traceSession):
            state.replaceTraceSession(traceSession)
            return .none

        case .replaceTraceCollection(let traceCollection):
            state.replaceTraceSession(traceSession(from: traceCollection))
            return .none

        case .setStoreVisibility(let id, let isVisible):
            state.setStoreVisibility(id: id, isVisible: isVisible)
            return .none

        case .toggleStoreVisibility(let id):
            state.toggleStoreVisibility(id: id)
            return .none
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
