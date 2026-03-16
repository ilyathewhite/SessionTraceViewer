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

    enum DefaultStoreVisibility: Equatable {
        case allVisible
        case firstCreatedOnly
    }

    enum MutatingAction {
        case replaceTraceSession(TraceSession)
        case replaceTraceCollection(SessionTraceCollection)
        case setStoreVisibility(id: String, isVisible: Bool)
        case showStore(id: String, additively: Bool)
        case showOnlyStore(id: String)
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
        let timeLabel: String
        let displayStoreName: String
        let subtitleSourceLabel: String?
        let subtitleDetailLabel: String?
        let isUserSourceEvent: Bool

        init(
            id: String,
            localNodeID: String,
            storeInstanceID: String,
            storeName: String,
            order: Int,
            kind: EventKind,
            colorKind: EventColorKind,
            title: String,
            subtitle: String,
            date: Date?,
            childIDs: [String],
            node: SessionGraph.Node
        ) {
            self.id = id
            self.localNodeID = localNodeID
            self.storeInstanceID = storeInstanceID
            self.storeName = storeName
            self.order = order
            self.kind = kind
            self.colorKind = colorKind
            self.title = title
            self.subtitle = subtitle
            self.date = date
            self.childIDs = childIDs
            self.node = node
            self.timeLabel = EventInspectorFormatter.timestamp(date)
            self.displayStoreName = storeName

            let subtitleComponents = Self.subtitleComponents(from: subtitle)
            self.subtitleSourceLabel = subtitleComponents.sourceLabel
            self.subtitleDetailLabel = subtitleComponents.detailLabel
            self.isUserSourceEvent = subtitleComponents.isUserSource
        }

        private static func subtitleComponents(
            from subtitle: String
        ) -> (sourceLabel: String?, detailLabel: String?, isUserSource: Bool) {
            guard let range = subtitle.range(of: subtitleSeparator) else {
                return (nil, nil, false)
            }

            let prefix = String(subtitle[..<range.lowerBound]).uppercased()
            guard prefix == "USER" || prefix == "CODE" else {
                return (nil, nil, false)
            }

            return (
                prefix,
                String(subtitle[range.upperBound...]),
                prefix == "USER"
            )
        }
    }

    struct StoreLayer: Identifiable, Equatable {
        let id: String
        let displayName: String
        let isVisible: Bool
        let childKeyLineText: String?
        let statusText: String?
        let eventCount: Int
        let children: [StoreLayer]
        let eventCountText: String
        let metadataText: String

        init(
            id: String,
            displayName: String,
            isVisible: Bool,
            childKeyLineText: String?,
            statusText: String?,
            eventCount: Int,
            children: [StoreLayer]
        ) {
            self.id = id
            self.displayName = displayName
            self.isVisible = isVisible
            self.childKeyLineText = childKeyLineText
            self.statusText = statusText
            self.eventCount = eventCount
            self.children = children

            let eventCountText = Self.eventCountText(for: eventCount)
            self.eventCountText = eventCountText
            self.metadataText = Self.metadataText(
                statusText: statusText,
                eventCountText: eventCountText
            )
        }

        var outlineChildren: [StoreLayer]? {
            children.isEmpty ? nil : children
        }

        private static func eventCountText(for eventCount: Int) -> String {
            switch eventCount {
            case 0:
                return "no events"
            case 1:
                return "1 event"
            default:
                return "\(eventCount) events"
            }
        }

        private static func metadataText(
            statusText: String?,
            eventCountText: String
        ) -> String {
            [statusText, eventCountText]
                .compactMap { text in
                    guard let text, !text.isEmpty else { return nil }
                    return text
                }
                .joined(separator: " • ")
        }
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
        let defaultStoreVisibility: DefaultStoreVisibility
        var traceSession: TraceSession
        var storeVisibilityByID: [String: Bool]
        var sessionData: SessionData
        var viewerData: ViewerData
        var storeLayerRootCache: [StoreLayer]
        var storeLayerCache: [StoreLayer]
        var contentVersion = 0
    }
}

extension TraceViewer {
    @MainActor
    static func store(
        traceSession: TraceSession,
        defaultStoreVisibility: DefaultStoreVisibility = .allVisible
    ) -> Store {
        Store(
            .init(
                traceSession: traceSession,
                defaultStoreVisibility: defaultStoreVisibility
            ),
            env: nil
        )
    }

    @MainActor
    static func store(
        traceCollection: SessionTraceCollection,
        defaultStoreVisibility: DefaultStoreVisibility = .allVisible
    ) -> Store {
        store(
            traceSession: traceSession(from: traceCollection),
            defaultStoreVisibility: defaultStoreVisibility
        )
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

        case .showStore(let id, let additively):
            state.showStore(id: id, additively: additively)
            return .none

        case .showOnlyStore(let id):
            state.showOnlyStore(id: id)
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
