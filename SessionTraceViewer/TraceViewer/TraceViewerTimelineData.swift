//
//  TraceViewerTimelineData.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import Foundation
import ReducerArchitecture

extension TraceViewer {
    struct TimelineData {
        let traceCollection: SessionTraceCollection
        let orderedIDs: [String]
        let itemsByID: [String: TimelineItem]
        let childrenByParentID: [String: [String]]
        let descendantCountByID: [String: Int]
    }
}

extension TraceViewer.TimelineData {
    init(traceCollection: SessionTraceCollection) {
        var childrenByParentID: [String: [String]] = [:]
        for edge in traceCollection.sessionGraph.edges {
            switch edge {
            case .nested(let nested):
                childrenByParentID[nested.parentNodeID, default: []].append(nested.childNodeID)
            case .contains(let contains):
                childrenByParentID[contains.batchID.rawValue, default: []].append(contains.nodeID)
            default:
                break
            }
        }

        let sortedNodes = traceCollection.sessionGraph.nodes
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.id < rhs.id
                }
                return lhs.order < rhs.order
            }
        let initialStateID = sortedNodes.compactMap { node -> String? in
            guard case .state(let state) = node else { return nil }
            return state.id.rawValue
        }.first
        let actionByID = Dictionary(
            uniqueKeysWithValues: sortedNodes.compactMap { node -> (String, SessionGraph.ActionNode)? in
                guard case .action(let action) = node else { return nil }
                return (action.id.rawValue, action)
            }
        )
        let indexByNodeID = Dictionary(
            uniqueKeysWithValues: sortedNodes.enumerated().map { ($1.id, $0) }
        )
        let mutationsByActionID = Dictionary(
            grouping: sortedNodes.compactMap { node -> SessionGraph.MutationNode? in
                guard case .mutation(let mutation) = node else { return nil }
                return mutation
            },
            by: \.actionID
        )
        let effectsByStartedActionID: [String: [SessionGraph.EffectNode]] = sortedNodes.reduce(
            into: [:]
        ) { partialResult, node in
            guard case .effect(let effect) = node else { return }
            guard let actionID = effect.startedByActionID, !actionID.isEmpty else { return }
            partialResult[actionID.rawValue, default: []].append(effect)
        }

        var hiddenAppliedNodeIDs: Set<String> = []
        for action in actionByID.values {
            switch action.kind {
            case .mutating:
                for mutation in mutationsByActionID[action.id] ?? [] {
                    if !TraceViewer.shouldShowAppliedNode(
                        scheduledNodeID: action.id.rawValue,
                        appliedNodeID: mutation.id.rawValue,
                        indexByNodeID: indexByNodeID
                    ) {
                        hiddenAppliedNodeIDs.insert(mutation.id.rawValue)
                    }
                }
            case .effect:
                for effect in effectsByStartedActionID[action.id.rawValue] ?? [] {
                    if !TraceViewer.shouldShowAppliedNode(
                        scheduledNodeID: action.id.rawValue,
                        appliedNodeID: effect.id.rawValue,
                        indexByNodeID: indexByNodeID
                    ) {
                        hiddenAppliedNodeIDs.insert(effect.id.rawValue)
                    }
                }
            default:
                break
            }
        }

        var visibleAppliedMutationActionIDs: Set<String> = []
        for mutation in mutationsByActionID.values.joined()
        where !hiddenAppliedNodeIDs.contains(mutation.id.rawValue) {
            visibleAppliedMutationActionIDs.insert(mutation.actionID.rawValue)
        }

        var visibleAppliedEffectActionIDs: Set<String> = []
        for effect in effectsByStartedActionID.values.joined()
        where !hiddenAppliedNodeIDs.contains(effect.id.rawValue) {
            if let startedByActionID = effect.startedByActionID {
                visibleAppliedEffectActionIDs.insert(startedByActionID.rawValue)
            }
        }

        let hiddenAppliedMutationByActionID = Dictionary(
            uniqueKeysWithValues: mutationsByActionID.compactMap { actionID, mutations -> (String, SessionGraph.MutationNode)? in
                guard !visibleAppliedMutationActionIDs.contains(actionID.rawValue) else { return nil }
                let hiddenMutations = mutations
                    .filter { hiddenAppliedNodeIDs.contains($0.id.rawValue) }
                    .sorted { lhs, rhs in lhs.order < rhs.order }
                guard let mutation = hiddenMutations.first else { return nil }
                return (actionID.rawValue, mutation)
            }
        )
        let hiddenAppliedEffectByActionID = Dictionary(
            uniqueKeysWithValues: effectsByStartedActionID.compactMap { actionID, effects -> (String, SessionGraph.EffectNode)? in
                guard !visibleAppliedEffectActionIDs.contains(actionID) else { return nil }
                let hiddenEffects = effects
                    .filter { hiddenAppliedNodeIDs.contains($0.id.rawValue) }
                    .sorted { lhs, rhs in lhs.order < rhs.order }
                guard let effect = hiddenEffects.first else { return nil }
                return (actionID, effect)
            }
        )

        var itemsByID: [String: TraceViewer.TimelineItem] = [:]
        var orderedIDs: [String] = []
        orderedIDs.reserveCapacity(sortedNodes.count)

        for node in sortedNodes {
            guard !hiddenAppliedNodeIDs.contains(node.id) else { continue }
            guard let item = TraceViewer.makeTimelineItem(
                node: node,
                initialStateID: initialStateID,
                childrenByParentID: childrenByParentID,
                actionByID: actionByID,
                visibleAppliedMutationActionIDs: visibleAppliedMutationActionIDs,
                visibleAppliedEffectActionIDs: visibleAppliedEffectActionIDs,
                hiddenAppliedMutationByActionID: hiddenAppliedMutationByActionID,
                hiddenAppliedEffectByActionID: hiddenAppliedEffectByActionID
            ) else {
                continue
            }
            itemsByID[item.id] = item
            orderedIDs.append(item.id)
        }

        let normalizedChildrenByParentID = childrenByParentID.mapValues { ids in
            ids
                .uniqued()
                .filter { itemsByID[$0] != nil }
                .sorted { lhs, rhs in
                    guard let left = itemsByID[lhs], let right = itemsByID[rhs] else {
                        return lhs < rhs
                    }
                    if left.order == right.order {
                        return left.id < right.id
                    }
                    return left.order < right.order
                }
        }

        var descendantCountByID: [String: Int] = [:]
        func descendantCount(of id: String) -> Int {
            if let cached = descendantCountByID[id] {
                return cached
            }

            let children = normalizedChildrenByParentID[id] ?? []
            let total = children.count + children.reduce(0) { partial, childID in
                partial + descendantCount(of: childID)
            }
            descendantCountByID[id] = total
            return total
        }

        for id in orderedIDs {
            _ = descendantCount(of: id)
        }

        self.init(
            traceCollection: traceCollection,
            orderedIDs: orderedIDs,
            itemsByID: itemsByID,
            childrenByParentID: normalizedChildrenByParentID,
            descendantCountByID: descendantCountByID
        )
    }
}

extension TraceViewer {
    static func makeTimelineItem(
        node: SessionGraph.Node,
        initialStateID: String?,
        childrenByParentID: [String: [String]],
        actionByID: [String: SessionGraph.ActionNode],
        visibleAppliedMutationActionIDs: Set<String>,
        visibleAppliedEffectActionIDs: Set<String>,
        hiddenAppliedMutationByActionID: [String: SessionGraph.MutationNode],
        hiddenAppliedEffectByActionID: [String: SessionGraph.EffectNode]
    ) -> TimelineItem? {
        switch node {
        case .state(let state):
            let isInitialState = (state.id.rawValue == initialStateID)
            return .init(
                id: state.id.rawValue,
                order: state.order,
                kind: .state,
                colorKind: .state,
                title: isInitialState ? "Initial State" : "State Change",
                subtitle: isInitialState ? "initial state snapshot" : "state snapshot",
                date: state.capturedAt,
                childIDs: childrenByParentID[state.id.rawValue] ?? [],
                node: node
            )

        case .action(let action):
            let collapsedAppliedMutation = hiddenAppliedMutationByActionID[action.id.rawValue]
            let title: String = {
                switch action.kind {
                case .effect:
                    return action.actionCase
                case .publish:
                    return "Publish"
                case .cancel:
                    return "Cancel"
                case .mutating:
                    return action.actionCase
                case .none:
                    return action.actionCase
                }
            }()
            let subtitle: String = {
                let source = actionOriginLabel(action.source)
                let exactCase = exactCaseLabel(from: action.action) ?? action.action
                return "\(source) • \(exactCase)"
            }()
            let eventKind: EventKind
            let eventColorKind: EventColorKind
            switch action.kind {
            case .mutating:
                eventKind = .mutation
                eventColorKind = .mutation
            case .effect:
                eventKind = .effect
                eventColorKind = .effect
            case .publish:
                eventKind = .flow
                eventColorKind = .publish
            case .cancel:
                eventKind = .flow
                eventColorKind = .cancel
            case .none:
                assertionFailure("Unexpected traced .none action node: \(action.id.rawValue)")
                return nil
            }

            return .init(
                id: action.id.rawValue,
                order: action.order,
                kind: eventKind,
                colorKind: eventColorKind,
                title: title,
                subtitle: subtitle,
                date: collapsedAppliedMutation?.appliedAt ?? action.receivedAt,
                childIDs: childrenByParentID[action.id.rawValue] ?? [],
                node: node
            )

        case .mutation(let mutation):
            let actionName = actionByID[mutation.actionID.rawValue]?.actionCase
            return .init(
                id: mutation.id.rawValue,
                order: mutation.order,
                kind: .mutation,
                colorKind: .mutation,
                title: actionName.map { "Apply \($0)" } ?? "Apply Mutation",
                subtitle: actionName.map { _ in "applied mutation • action=\(mutation.actionID)" }
                    ?? "applied mutation • action=\(mutation.actionID)",
                date: mutation.appliedAt,
                childIDs: childrenByParentID[mutation.id.rawValue] ?? [],
                node: node
            )

        case .effect(let effect):
            let effectName = effect.startedByActionID.flatMap { actionByID[$0.rawValue]?.actionCase }
            let subtitle: String = {
                let details = EventInspectorFormatter.effectSubtitle(effect)
                if effect.kind == .action {
                    return "applied effect • single action"
                }
                return "applied effect • \(details)"
            }()
            return .init(
                id: effect.id.rawValue,
                order: effect.order,
                kind: .effect,
                colorKind: .effect,
                title: effectName ?? effect.kind.rawValue,
                subtitle: subtitle,
                date: nil,
                childIDs: childrenByParentID[effect.id.rawValue] ?? [],
                node: node
            )

        case .batch(let batch):
            return .init(
                id: batch.id.rawValue,
                order: batch.order,
                kind: .batch,
                colorKind: .batch,
                title: "Batch \(batch.kind.rawValue)",
                subtitle: "actions=\(batch.actionCount)",
                date: nil,
                childIDs: childrenByParentID[batch.id.rawValue] ?? [],
                node: node
            )
        }
    }

    static func shouldShowAppliedNode(
        scheduledNodeID: String,
        appliedNodeID: String,
        indexByNodeID: [String: Int]
    ) -> Bool {
        guard let scheduledIndex = indexByNodeID[scheduledNodeID],
              let appliedIndex = indexByNodeID[appliedNodeID],
              scheduledIndex < appliedIndex else {
            return true
        }
        return (appliedIndex - scheduledIndex) > 1
    }

    static func exactCaseLabel(from code: String?) -> String? {
        guard let code, !code.isEmpty, code != "nil" else { return nil }
        guard code.first == "." else {
            return code
        }

        var label = "."
        for character in code.dropFirst() {
            guard character.isLetter || character.isNumber || character == "_" else {
                break
            }
            label.append(character)
        }
        return label.count > 1 ? label : nil
    }

    static func actionOriginLabel(_ source: SessionGraph.ActionNode.Source) -> String {
        switch source {
        case .user:
            return "USER"
        case .action, .effect, .system:
            return "CODE"
        }
    }
}
