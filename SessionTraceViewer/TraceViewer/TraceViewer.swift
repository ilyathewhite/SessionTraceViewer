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
        case replaceTraceCollection(SessionTraceCollection)
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

    struct StoreState {
        var traceCollection: SessionTraceCollection
        var traceCollectionVersion = 0
    }
}

extension TraceViewer {
    @MainActor
    static func store(traceCollection: SessionTraceCollection) -> Store {
        Store(.init(traceCollection: traceCollection), env: nil)
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .replaceTraceCollection(let traceCollection):
            state.traceCollection = traceCollection
            state.traceCollectionVersion += 1
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
