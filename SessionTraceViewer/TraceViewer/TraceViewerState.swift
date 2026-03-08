//
//  TraceViewerState.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 3/8/26.
//

import Foundation
import ReducerArchitecture

extension TraceViewer.StoreState {
    struct CommitGraphLayout {
        let laneByID: [String: Int]
        let predecessorIDsByID: [String: [String]]
        let edgeLineKindByPredecessorID: [String: [String: TraceViewer.EdgeLineKind]]
        let sharedColumnAnchorByID: [String: String]
        let maxLane: Int
    }

    struct OverviewGraphPresentation {
        let nodes: [OverviewGraphNode]
        let nodeByID: [String: OverviewGraphNode]
        let graphIDByTimelineID: [String: String]
        let maxLane: Int
    }

    private static var scopeBarEventKinds: [TraceViewer.EventKind] {
        [
            .state,
            .mutation,
            .effect,
            .flow,
        ]
    }

    init(traceCollection: SessionTraceCollection) {
        self.traceCollection = traceCollection
        self.graph = traceCollection.sessionGraph

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
                    if !Self.shouldShowAppliedNode(
                        scheduledNodeID: action.id.rawValue,
                        appliedNodeID: mutation.id.rawValue,
                        indexByNodeID: indexByNodeID
                    ) {
                        hiddenAppliedNodeIDs.insert(mutation.id.rawValue)
                    }
                }
            case .effect:
                for effect in effectsByStartedActionID[action.id.rawValue] ?? [] {
                    if !Self.shouldShowAppliedNode(
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
        for mutation in mutationsByActionID.values.joined() where !hiddenAppliedNodeIDs.contains(mutation.id.rawValue) {
            visibleAppliedMutationActionIDs.insert(mutation.actionID.rawValue)
        }
        var visibleAppliedEffectActionIDs: Set<String> = []
        for effect in effectsByStartedActionID.values.joined() where !hiddenAppliedNodeIDs.contains(effect.id.rawValue) {
            if let startedByActionID = effect.startedByActionID {
                visibleAppliedEffectActionIDs.insert(startedByActionID.rawValue)
            }
        }
        let hiddenAppliedMutationByActionID = Dictionary(
            uniqueKeysWithValues: mutationsByActionID
                .compactMap { actionID, mutations -> (String, SessionGraph.MutationNode)? in
                    guard !visibleAppliedMutationActionIDs.contains(actionID.rawValue) else { return nil }
                    let hiddenMutations = mutations
                        .filter { hiddenAppliedNodeIDs.contains($0.id.rawValue) }
                        .sorted { lhs, rhs in lhs.order < rhs.order }
                    guard let mutation = hiddenMutations.first else { return nil }
                    return (actionID.rawValue, mutation)
                }
        )
        let hiddenAppliedEffectByActionID = Dictionary(
            uniqueKeysWithValues: effectsByStartedActionID
                .compactMap { actionID, effects -> (String, SessionGraph.EffectNode)? in
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
            guard let item = Self.makeItem(
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

        self.orderedIDs = orderedIDs
        self.itemsByID = itemsByID
        self.childrenByParentID = normalizedChildrenByParentID
        self.descendantCountByID = descendantCountByID

        let commitGraphLayout = Self.buildCommitGraphLayout(
            graph: traceCollection.sessionGraph,
            orderedIDs: orderedIDs,
            itemsByID: itemsByID,
            parentByChildID: Self.makeParentByChildID(from: traceCollection.sessionGraph.edges)
        )
        let overviewGraphPresentation = Self.buildOverviewGraphPresentation(
            orderedTimelineIDs: orderedIDs,
            itemsByID: itemsByID,
            laneByTimelineID: commitGraphLayout.laneByID,
            predecessorIDsByTimelineID: commitGraphLayout.predecessorIDsByID,
            edgeLineKindByPredecessorID: commitGraphLayout.edgeLineKindByPredecessorID,
            sharedColumnAnchorByID: commitGraphLayout.sharedColumnAnchorByID,
            maxTimelineLane: commitGraphLayout.maxLane
        )
        self.overviewGraphNodes = overviewGraphPresentation.nodes
        self.overviewGraphNodeByID = overviewGraphPresentation.nodeByID
        self.overviewGraphIDByTimelineID = overviewGraphPresentation.graphIDByTimelineID
        self.overviewGraphMaxLane = overviewGraphPresentation.maxLane

        self.scopeFilter = .all
        self.collapsedIDs = []
        self.selectedID = orderedIDs.first
    }

    var visibleIDs: [String] {
        var hiddenIDs: Set<String> = []
        var visible: [String] = []
        visible.reserveCapacity(orderedIDs.count)

        for id in orderedIDs {
            guard !hiddenIDs.contains(id) else { continue }
            visible.append(id)

            if collapsedIDs.contains(id) {
                hiddenIDs.formUnion(descendants(of: id))
            }
        }
        return visible
    }

    var visibleItems: [TraceViewer.TimelineItem] {
        visibleIDs.compactMap { itemsByID[$0] }
    }

    var scopeBarKinds: [TraceViewer.EventKind] {
        Self.scopeBarEventKinds
    }

    var isAllEventKindsSelected: Bool {
        guard case .all = scopeFilter else { return false }
        return true
    }

    var isUserEventFilterSelected: Bool {
        switch scopeFilter {
        case .all:
            return false
        case .custom(let selection):
            return selection.includesUserEvents
        }
    }

    var selectableVisibleIDs: [String] {
        visibleIDs.filter { id in
            guard let item = itemsByID[id] else { return false }
            return matchesScopeFilter(item)
        }
    }

    private func matchesScopeFilter(_ item: TraceViewer.TimelineItem) -> Bool {
        switch scopeFilter {
        case .all:
            return true
        case .custom(let selection):
            return selection.eventKinds.contains(item.kind)
                || (selection.includesUserEvents && item.isUserSourceEvent)
        }
    }

    var visibleOverviewGraphNodes: [OverviewGraphNode] {
        let visibleTimelineIDSet = Set(visibleIDs)
        return overviewGraphNodes.filter { node in
            guard let timelineID = node.timelineID else {
                return true
            }
            return visibleTimelineIDSet.contains(timelineID)
        }
    }

    var selectableVisibleOverviewGraphNodes: [OverviewGraphNode] {
        let selectableVisibleIDSet = Set(selectableVisibleIDs)
        return visibleOverviewGraphNodes.filter { node in
            guard let selectionTimelineID = node.selectionTimelineID else { return false }
            return selectableVisibleIDSet.contains(selectionTimelineID)
        }
    }

    var selectableVisibleOverviewGraphNodeIDs: [String] {
        selectableVisibleOverviewGraphNodes.map(\.id)
    }

    var selectedOverviewGraphNodeID: String? {
        guard let selectedID else { return nil }
        return overviewGraphIDByTimelineID[selectedID]
    }

    var selectedItem: TraceViewer.TimelineItem? {
        guard let selectedID else { return nil }
        return itemsByID[selectedID]
    }

    var selectedPreviousStateItem: TraceViewer.TimelineItem? {
        guard let selectedID,
              let selectedItem = itemsByID[selectedID],
              case .state = selectedItem.node,
              let selectedIndex = orderedIDs.firstIndex(of: selectedID),
              selectedIndex > 0 else {
            return nil
        }

        for index in stride(from: selectedIndex - 1, through: 0, by: -1) {
            guard let item = itemsByID[orderedIDs[index]] else { continue }
            if case .state = item.node {
                return item
            }
        }
        return nil
    }

    var eventInspectorSelection: EventInspector.Selection {
        .init(
            item: selectedItem,
            previousStateItem: selectedPreviousStateItem
        )
    }

    func isCollapsed(_ id: String) -> Bool {
        collapsedIDs.contains(id)
    }

    func isEventKindSelected(_ kind: TraceViewer.EventKind) -> Bool {
        guard case .custom(let selection) = scopeFilter else { return false }
        return selection.eventKinds.contains(kind)
    }

    func isSelectableTimelineID(_ id: String) -> Bool {
        guard visibleIDs.contains(id),
              let item = itemsByID[id] else {
            return false
        }
        return matchesScopeFilter(item)
    }

    func isSelectableOverviewGraphNodeID(_ id: String) -> Bool {
        guard let selectionTimelineID = overviewGraphNodeByID[id]?.selectionTimelineID else {
            return false
        }
        return isSelectableTimelineID(selectionTimelineID)
    }

    func hasChildren(_ id: String) -> Bool {
        !(childrenByParentID[id] ?? []).isEmpty
    }

    func collapsedDescendantCount(for id: String) -> Int {
        guard collapsedIDs.contains(id) else { return 0 }
        return descendantCountByID[id] ?? 0
    }

    func timelineSelectionID(forOverviewGraphNodeID id: String) -> String? {
        overviewGraphNodeByID[id]?.selectionTimelineID
    }

    func descendants(of id: String) -> Set<String> {
        var result: Set<String> = []
        var stack: [String] = childrenByParentID[id] ?? []

        while let next = stack.popLast() {
            if result.insert(next).inserted {
                stack.append(contentsOf: childrenByParentID[next] ?? [])
            }
        }
        return result
    }

    func ancestors(of id: String) -> Set<String> {
        var parentByChild: [String: String] = [:]
        for (parent, children) in childrenByParentID {
            for child in children where parentByChild[child] == nil {
                parentByChild[child] = parent
            }
        }

        var ancestors: Set<String> = []
        var cursor = id
        while let parent = parentByChild[cursor] {
            if !ancestors.insert(parent).inserted { break }
            cursor = parent
        }
        return ancestors
    }

    mutating func clampSelection(
        anchorID: String? = nil,
        prefersFirstSelectable: Bool = false
    ) {
        let visibleIDs = visibleIDs
        let selectableVisibleIDs = selectableVisibleIDs
        guard !selectableVisibleIDs.isEmpty else {
            selectedID = nil
            return
        }

        if let selectedID, selectableVisibleIDs.contains(selectedID) {
            return
        }

        if prefersFirstSelectable {
            selectedID = selectableVisibleIDs.first
            return
        }

        let selectableVisibleIDSet = Set(selectableVisibleIDs)
        let anchorID = anchorID ?? selectedID
        if let anchorID,
           let anchorIndex = visibleIDs.firstIndex(of: anchorID) {
            for candidateIndex in anchorIndex..<visibleIDs.count {
                let candidateID = visibleIDs[candidateIndex]
                if selectableVisibleIDSet.contains(candidateID) {
                    selectedID = candidateID
                    return
                }
            }

            if anchorIndex > 0 {
                for candidateIndex in stride(from: anchorIndex - 1, through: 0, by: -1) {
                    let candidateID = visibleIDs[candidateIndex]
                    if selectableVisibleIDSet.contains(candidateID) {
                        selectedID = candidateID
                        return
                    }
                }
            }
        }

        selectedID = selectableVisibleIDs.first
    }

    mutating func selectAllEventKinds() {
        scopeFilter = .all
        clampSelection(prefersFirstSelectable: true)
    }

    mutating func selectEvent(id: String) {
        guard itemsByID[id] != nil else {
            return
        }
        if !isSelectableTimelineID(id) {
            scopeFilter = .all
        }
        selectedID = id
    }

    mutating func toggleEventKindFilter(_ kind: TraceViewer.EventKind) {
        switch scopeFilter {
        case .all:
            scopeFilter = .custom(.init(eventKinds: [kind]))
        case .custom(var selection):
            if selection.eventKinds.contains(kind) {
                selection.eventKinds.remove(kind)
            }
            else {
                selection.eventKinds.insert(kind)
            }
            scopeFilter = .custom(selection)
        }
        clampSelection(prefersFirstSelectable: true)
    }

    mutating func toggleUserEventFilter() {
        switch scopeFilter {
        case .all:
            scopeFilter = .custom(.init(includesUserEvents: true))
        case .custom(var selection):
            selection.includesUserEvents.toggle()
            scopeFilter = .custom(selection)
        }
        clampSelection(prefersFirstSelectable: true)
    }

    mutating func selectVisible(offset: Int) {
        let selectableVisibleIDs = selectableVisibleIDs
        guard !selectableVisibleIDs.isEmpty else {
            selectedID = nil
            return
        }

        if selectedID == nil {
            selectedID = selectableVisibleIDs.first
            return
        }

        guard let selectedID,
              let currentIndex = selectableVisibleIDs.firstIndex(of: selectedID) else {
            self.selectedID = selectableVisibleIDs.first
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), selectableVisibleIDs.count - 1)
        self.selectedID = selectableVisibleIDs[nextIndex]
    }

    mutating func selectGraphNode(offset: Int) {
        let visibleNodes = selectableVisibleOverviewGraphNodes
        guard !visibleNodes.isEmpty else {
            selectedID = nil
            return
        }

        let step = offset > 0 ? 1 : -1
        let startIndex: Int = {
            guard let selectedOverviewGraphNodeID,
                  let currentIndex = visibleNodes.firstIndex(where: { $0.id == selectedOverviewGraphNodeID }) else {
                return step > 0 ? -1 : visibleNodes.count
            }
            return currentIndex
        }()

        var index = startIndex
        while true {
            index += step
            guard visibleNodes.indices.contains(index) else { return }
            guard let selectionTimelineID = visibleNodes[index].selectionTimelineID else { continue }
            selectedID = selectionTimelineID
            return
        }
    }

    mutating func selectFirstVisible() {
        selectedID = selectableVisibleIDs.first
    }

    mutating func selectLastVisible() {
        selectedID = selectableVisibleIDs.last
    }

    mutating func focusOnSelection() {
        guard let selectedID else { return }
        let protected = ancestors(of: selectedID)
            .union(descendants(of: selectedID))
            .union([selectedID])

        for id in orderedIDs where hasChildren(id) && !protected.contains(id) {
            collapsedIDs.insert(id)
        }
        clampSelection()
    }

    mutating func replaceTraceCollection(_ traceCollection: SessionTraceCollection) {
        let previousSelectedID = selectedID
        let previousCollapsedIDs = collapsedIDs
        let previousScopeFilter = scopeFilter

        self = .init(traceCollection: traceCollection)
        scopeFilter = previousScopeFilter
        collapsedIDs = previousCollapsedIDs.intersection(Set(orderedIDs))
        if let previousSelectedID,
           itemsByID[previousSelectedID] != nil {
            selectedID = previousSelectedID
        }
        clampSelection(anchorID: previousSelectedID)
    }

    static func makeItem(
        node: SessionGraph.Node,
        initialStateID: String?,
        childrenByParentID: [String: [String]],
        actionByID: [String: SessionGraph.ActionNode],
        visibleAppliedMutationActionIDs: Set<String>,
        visibleAppliedEffectActionIDs: Set<String>,
        hiddenAppliedMutationByActionID: [String: SessionGraph.MutationNode],
        hiddenAppliedEffectByActionID: [String: SessionGraph.EffectNode]
    ) -> TraceViewer.TimelineItem? {
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
                let source = Self.actionOriginLabel(action.source)
                let exactCase = Self.exactCaseLabel(from: action.action) ?? action.action
                return "\(source) • \(exactCase)"
            }()
            let eventKind: TraceViewer.EventKind
            let eventColorKind: TraceViewer.EventColorKind
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
                subtitle: actionName.map { _ in "applied mutation • action=\(mutation.actionID)" } ?? "applied mutation • action=\(mutation.actionID)",
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
                if effectName != nil {
                    return "applied effect • \(details)"
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

    private static func appliedEffectLabel(_ effect: SessionGraph.EffectNode) -> String {
        ".\(effect.kind.rawValue)"
    }

    private static func exactCaseLabel(from code: String?) -> String? {
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

    private static func actionOriginLabel(_ source: SessionGraph.ActionNode.Source) -> String {
        switch source {
        case .user:
            return "USER"
        case .action, .effect, .system:
            return "CODE"
        }
    }

    static func makeParentByChildID(
        from edges: [SessionGraph.Edge]
    ) -> [String: String] {
        var parentByChildID: [String: String] = [:]
        for edge in edges {
            switch edge {
            case .nested(let nested):
                parentByChildID[nested.childNodeID] = nested.parentNodeID
            case .contains(let contains):
                if parentByChildID[contains.nodeID] == nil {
                    parentByChildID[contains.nodeID] = contains.batchID.rawValue
                }
            default:
                break
            }
        }
        return parentByChildID
    }

    static func buildCommitGraphLayout(
        graph: SessionGraph,
        orderedIDs: [String],
        itemsByID: [String: TraceViewer.TimelineItem],
        parentByChildID: [String: String]
    ) -> CommitGraphLayout {
        var actionProducerByNodeID: [String: String] = [:]
        var effectEmitterByNodeID: [String: String] = [:]
        var startedEffectsByActionID: [String: [SessionGraph.StartedEffectEdge]] = [:]
        var startedActionByEffectID: [String: String] = [:]
        var emittedEdgesByEffectID: [String: [SessionGraph.EmittedActionEdge]] = [:]
        var childNodeIDsByBatchID: [String: [String]] = [:]
        var inputStateByMutatingActionID: [String: String] = [:]
        var resultActionByStateID: [String: String] = [:]
        var mutatingActionIDs: Set<String> = []
        for edge in graph.edges {
            switch edge {
            case .applied(let applied):
                mutatingActionIDs.insert(applied.actionID.rawValue)
            case .startedEffect(let startedEffect):
                startedEffectsByActionID[startedEffect.actionID.rawValue, default: []].append(startedEffect)
                startedActionByEffectID[startedEffect.effectID.rawValue] = startedEffect.actionID.rawValue
            case .producedAction(let produced):
                actionProducerByNodeID[produced.nodeID] = produced.actionID.rawValue
            case .emittedAction(let emitted):
                effectEmitterByNodeID[emitted.nodeID] = emitted.effectID.rawValue
                emittedEdgesByEffectID[emitted.effectID.rawValue, default: []].append(emitted)
            case .contains(let contains):
                childNodeIDsByBatchID[contains.batchID.rawValue, default: []].append(contains.nodeID)
            case .stateInput(let stateInput):
                inputStateByMutatingActionID[stateInput.actionID.rawValue] = stateInput.stateID.rawValue
            case .stateResult(let stateResult):
                resultActionByStateID[stateResult.stateID.rawValue] = stateResult.actionID.rawValue
            default:
                break
            }
        }

        let firstStartedEffectByActionID: [String: String] = startedEffectsByActionID.mapValues { startedEffects in
            startedEffects
                .sorted { lhs, rhs in
                    if lhs.order == rhs.order {
                        return lhs.effectID < rhs.effectID
                    }
                    return lhs.order < rhs.order
                }
                .first?
                .effectID.rawValue ?? ""
        }
        .filter { !$0.value.isEmpty }

        for item in itemsByID.values {
            switch item.node {
            case .state:
                break
            case .action(let action):
                if action.kind == .mutating {
                    mutatingActionIDs.insert(action.id.rawValue)
                }
            case .mutation(let mutation):
                mutatingActionIDs.insert(mutation.actionID.rawValue)
            case .effect, .batch:
                break
            }
        }

        var effectNodeByID: [String: SessionGraph.EffectNode] = [:]
        for node in graph.nodes {
            guard case .effect(let effect) = node else { continue }
            effectNodeByID[effect.id.rawValue] = effect
        }

        func directSourceEffectID(for actionID: String) -> String? {
            guard let item = itemsByID[actionID],
                  case .action(let action) = item.node else {
                return nil
            }
            guard case .effect(let effectID) = action.source else {
                return nil
            }
            return effectID.rawValue
        }

        var branchEffectByNodeID: [String: String] = [:]
        var mainBranchNodeIDs: Set<String> = []
        var branchResolutionStack: Set<String> = []
        func resolveBranchEffectID(for nodeID: String) -> String? {
            if let cached = branchEffectByNodeID[nodeID] {
                return cached
            }
            if mainBranchNodeIDs.contains(nodeID) {
                return nil
            }
            guard branchResolutionStack.insert(nodeID).inserted else {
                return nil
            }
            defer { branchResolutionStack.remove(nodeID) }

            guard let item = itemsByID[nodeID] else {
                mainBranchNodeIDs.insert(nodeID)
                return nil
            }

            let effectID: String?
            switch item.node {
            case .state:
                effectID = nil
            case .effect(let effect):
                effectID = effect.id.rawValue

            case .action(let action):
                if let directEffectID = directSourceEffectID(for: action.id.rawValue) {
                    effectID = directEffectID
                }
                else if let startedEffectID = firstStartedEffectByActionID[action.id.rawValue] {
                    effectID = startedEffectID
                }
                else if action.kind == .effect {
                    // Standalone effect actions are still effect threads even
                    // when runEffect yields .none or no explicit effect node.
                    effectID = "action-thread:\(action.id.rawValue)"
                }
                else if mutatingActionIDs.contains(action.id.rawValue) || action.kind == .mutating {
                    effectID = nil
                }
                else {
                    effectID = nil
                }

            case .mutation:
                effectID = nil

            case .batch:
                if let emittedByEffectID = effectEmitterByNodeID[nodeID] {
                    effectID = emittedByEffectID
                }
                else if let parentID = parentByChildID[nodeID] {
                    effectID = resolveBranchEffectID(for: parentID)
                }
                else {
                    effectID = nil
                }
            }

            if let effectID {
                branchEffectByNodeID[nodeID] = effectID
            }
            else {
                mainBranchNodeIDs.insert(nodeID)
            }
            return effectID
        }

        var parentEffectByEffectID: [String: String] = [:]
        for effect in effectNodeByID.values {
            if let startedByActionID = effect.startedByActionID,
               let parentEffectID = directSourceEffectID(for: startedByActionID.rawValue) {
                parentEffectByEffectID[effect.id.rawValue] = parentEffectID
            }
        }

        var firstIndexByEffectID: [String: Int] = [:]
        var lastIndexByEffectID: [String: Int] = [:]
        for (index, id) in orderedIDs.enumerated() {
            guard let effectID = resolveBranchEffectID(for: id) else { continue }
            if firstIndexByEffectID[effectID] == nil {
                firstIndexByEffectID[effectID] = index
            }
            lastIndexByEffectID[effectID] = index
        }
        let indexByNodeID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) })

        for (effectID, _) in effectNodeByID {
            guard let startIndex = orderedIDs.firstIndex(of: effectID) else { continue }
            if let existingFirst = firstIndexByEffectID[effectID] {
                firstIndexByEffectID[effectID] = min(existingFirst, startIndex)
            }
            else {
                firstIndexByEffectID[effectID] = startIndex
            }
            let existingLast = lastIndexByEffectID[effectID] ?? startIndex
            lastIndexByEffectID[effectID] = max(existingLast, startIndex)
        }

        let syncScheduledEffectActionIDsByBatchID: [String: [String]] = itemsByID.reduce(
            into: [:]
        ) { partialResult, pair in
            guard case .batch(let batch) = pair.value.node,
                  batch.kind == .syncFanOut else {
                return
            }

            let effectActionIDs = (childNodeIDsByBatchID[pair.key] ?? []).filter { childID in
                guard let childItem = itemsByID[childID],
                      case .action(let action) = childItem.node else {
                    return false
                }
                return action.kind == .effect
            }
            guard effectActionIDs.count > 1 else { return }
            partialResult[pair.key] = effectActionIDs
        }

        var groupedStartIndexByEffectID: [String: Int] = [:]
        var groupedStartRankByEffectID: [String: Int] = [:]
        var sharedColumnAnchorByID: [String: String] = [:]
        for (batchID, actionIDs) in syncScheduledEffectActionIDsByBatchID {
            guard let batchIndex = orderedIDs.firstIndex(of: batchID) else { continue }
            for (rank, actionID) in actionIDs.enumerated() {
                sharedColumnAnchorByID[actionID] = batchID
                guard let effectID = resolveBranchEffectID(for: actionID) else { continue }
                groupedStartIndexByEffectID[effectID] = batchIndex
                groupedStartRankByEffectID[effectID] = rank
            }
        }

        let effectIDsByStartOrder = firstIndexByEffectID.keys.sorted { lhs, rhs in
            let leftIndex = groupedStartIndexByEffectID[lhs] ?? firstIndexByEffectID[lhs] ?? .max
            let rightIndex = groupedStartIndexByEffectID[rhs] ?? firstIndexByEffectID[rhs] ?? .max
            if leftIndex == rightIndex {
                let leftRank = groupedStartRankByEffectID[lhs] ?? .max
                let rightRank = groupedStartRankByEffectID[rhs] ?? .max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs < rhs
            }
            return leftIndex < rightIndex
        }

        var laneByEffectID: [String: Int] = [:]
        var activeLaneByEffectID: [String: Int] = [:]
        var occupiedEffectLanes: Set<Int> = []
        var maxLane = 0

        for effectID in effectIDsByStartOrder {
            let startIndex = groupedStartIndexByEffectID[effectID] ?? firstIndexByEffectID[effectID] ?? .max

            let expiredEffects = activeLaneByEffectID.keys.filter { activeEffectID in
                (lastIndexByEffectID[activeEffectID] ?? .max) < startIndex
            }
            for activeEffectID in expiredEffects {
                if let releasedLane = activeLaneByEffectID.removeValue(forKey: activeEffectID) {
                    occupiedEffectLanes.remove(releasedLane)
                }
            }

            let parentLane = parentEffectByEffectID[effectID]
                .flatMap { laneByEffectID[$0] } ?? 0
            let highestActiveLane = activeLaneByEffectID.values.max() ?? 0
            var laneCandidate = max(
                parentLane + 1,
                highestActiveLane > 0 ? highestActiveLane + 1 : 1
            )
            while occupiedEffectLanes.contains(laneCandidate) {
                laneCandidate += 1
            }

            laneByEffectID[effectID] = laneCandidate
            activeLaneByEffectID[effectID] = laneCandidate
            occupiedEffectLanes.insert(laneCandidate)
            maxLane = max(maxLane, laneCandidate)
        }

        var laneByID: [String: Int] = [:]
        for id in orderedIDs {
            if case .state = itemsByID[id]?.node {
                laneByID[id] = 0
                continue
            }

            if let effectID = resolveBranchEffectID(for: id) {
                let lane = laneByEffectID[effectID] ?? 1
                laneByID[id] = lane
                maxLane = max(maxLane, lane)
            }
            else {
                let nodeIndex = indexByNodeID[id] ?? 0
                var occupiedLanes: Set<Int> = []
                for (effectID, lane) in laneByEffectID {
                    guard let firstIndex = groupedStartIndexByEffectID[effectID] ?? firstIndexByEffectID[effectID],
                          let lastIndex = lastIndexByEffectID[effectID] else { continue }
                    guard firstIndex <= nodeIndex && nodeIndex <= lastIndex else { continue }
                    occupiedLanes.insert(lane)
                }

                var laneCandidate = 1
                while occupiedLanes.contains(laneCandidate) {
                    laneCandidate += 1
                }
                laneByID[id] = laneCandidate
                maxLane = max(maxLane, laneCandidate)
            }
        }

        func causalPredecessors(for id: String) -> [String] {
            guard let item = itemsByID[id] else { return [] }

            var predecessorIDs: [String] = []
            switch item.node {
            case .state(let state):
                if let resultActionID = resultActionByStateID[state.id.rawValue] {
                    predecessorIDs.append(resultActionID)
                }
            case .action(let action):
                var hasExplicitCausalSource = false
                switch action.source {
                case .action(let actionID):
                    predecessorIDs.append(actionID.rawValue)
                    hasExplicitCausalSource = true
                case .effect(let effectID):
                    predecessorIDs.append(effectID.rawValue)
                    hasExplicitCausalSource = true
                case .user, .system:
                    break
                }
                if (mutatingActionIDs.contains(action.id.rawValue) || action.kind == .mutating),
                   !hasExplicitCausalSource,
                   let inputStateID = inputStateByMutatingActionID[action.id.rawValue] {
                    predecessorIDs.append(inputStateID)
                }

            case .mutation(let mutation):
                predecessorIDs.append(mutation.actionID.rawValue)

            case .effect(let effect):
                if let actionID = effect.startedByActionID {
                    predecessorIDs.append(actionID.rawValue)
                }

            case .batch:
                if let actionID = actionProducerByNodeID[id] {
                    predecessorIDs.append(actionID)
                }
                if let effectID = effectEmitterByNodeID[id] {
                    predecessorIDs.append(effectID)
                }
                if predecessorIDs.isEmpty, let parentID = parentByChildID[id] {
                    predecessorIDs.append(parentID)
                }
            }

            return predecessorIDs.uniqued()
        }

        let visibleNodeIDs = Set(itemsByID.keys)
        var predecessorAliasByHiddenNodeID: [String: String] = [:]
        for edge in graph.edges {
            switch edge {
            case .applied(let applied):
                guard !visibleNodeIDs.contains(applied.mutationID.rawValue) else { break }
                guard visibleNodeIDs.contains(applied.actionID.rawValue) else { break }
                predecessorAliasByHiddenNodeID[applied.mutationID.rawValue] = applied.actionID.rawValue

            default:
                break
            }
        }

        func resolveVisibleNodeID(_ id: String) -> String? {
            var currentID = id
            var visited: Set<String> = []
            while !visibleNodeIDs.contains(currentID) {
                guard visited.insert(currentID).inserted else { return nil }
                guard let aliasID = predecessorAliasByHiddenNodeID[currentID] else { return nil }
                currentID = aliasID
            }
            return currentID
        }

        func isAsyncEffectKind(_ kind: SessionGraph.EffectNode.Kind) -> Bool {
            kind.rawValue.hasPrefix("async") || kind == .publisher
        }

        var asyncContextByActionID: [String: Bool] = [:]
        var asyncContextActionResolutionStack: Set<String> = []
        var asyncContextByEffectID: [String: Bool] = [:]
        var asyncContextEffectResolutionStack: Set<String> = []

        func isActionInAsyncContext(_ actionID: String) -> Bool {
            if let cached = asyncContextByActionID[actionID] {
                return cached
            }
            guard asyncContextActionResolutionStack.insert(actionID).inserted else {
                return false
            }
            defer { asyncContextActionResolutionStack.remove(actionID) }

            guard let item = itemsByID[actionID],
                  case .action(let action) = item.node else {
                asyncContextByActionID[actionID] = false
                return false
            }

            let isAsyncContext: Bool
            switch action.source {
            case .effect(let effectID):
                isAsyncContext = isEffectInAsyncContext(effectID.rawValue)
            case .action(let sourceActionID):
                isAsyncContext = isActionInAsyncContext(sourceActionID.rawValue)
            case .user, .system:
                isAsyncContext = false
            }

            asyncContextByActionID[actionID] = isAsyncContext
            return isAsyncContext
        }

        func isEffectInAsyncContext(_ effectID: String) -> Bool {
            if let cached = asyncContextByEffectID[effectID] {
                return cached
            }
            guard asyncContextEffectResolutionStack.insert(effectID).inserted else {
                return false
            }
            defer { asyncContextEffectResolutionStack.remove(effectID) }

            guard let effectNode = effectNodeByID[effectID] else {
                asyncContextByEffectID[effectID] = false
                return false
            }

            if isAsyncEffectKind(effectNode.kind) {
                asyncContextByEffectID[effectID] = true
                return true
            }

            let inheritedAsyncContext: Bool = {
                guard let startedByActionID = effectNode.startedByActionID else { return false }
                return isActionInAsyncContext(startedByActionID.rawValue)
            }()

            asyncContextByEffectID[effectID] = inheritedAsyncContext
            return inheritedAsyncContext
        }

        var effectThreadPredecessorByNodeID: [String: String] = [:]
        for (effectID, emittedEdges) in emittedEdgesByEffectID {
            let sortedEmittedEdges = emittedEdges.sorted { lhs, rhs in
                if lhs.emissionIndex == rhs.emissionIndex {
                    if lhs.order == rhs.order {
                        return lhs.nodeID < rhs.nodeID
                    }
                    return lhs.order < rhs.order
                }
                return lhs.emissionIndex < rhs.emissionIndex
            }

            let anchorID: String? = {
                if let visibleEffectID = resolveVisibleNodeID(effectID) {
                    return visibleEffectID
                }
                if let startedActionID = startedActionByEffectID[effectID],
                   let visibleStartedActionID = resolveVisibleNodeID(startedActionID) {
                    return visibleStartedActionID
                }
                return nil
            }()

            var previousVisibleNodeID = anchorID
            for emittedEdge in sortedEmittedEdges {
                guard let emittedVisibleNodeID = resolveVisibleNodeID(emittedEdge.nodeID) else { continue }
                if let previousVisibleNodeID, previousVisibleNodeID != emittedVisibleNodeID {
                    if effectThreadPredecessorByNodeID[emittedVisibleNodeID] == nil {
                        effectThreadPredecessorByNodeID[emittedVisibleNodeID] = previousVisibleNodeID
                    }
                }
                previousVisibleNodeID = emittedVisibleNodeID
            }
        }

        var predecessorIDsByID: [String: [String]] = [:]
        var edgeLineKindByPredecessorID: [String: [String: TraceViewer.EdgeLineKind]] = [:]

        func edgeLineKind(to nodeID: String) -> TraceViewer.EdgeLineKind {
            guard let nodeItem = itemsByID[nodeID] else { return .solid }
            switch nodeItem.node {
            case .action(let action):
                return isActionInAsyncContext(action.id.rawValue) ? .dotted : .solid

            case .effect(let effect):
                return isEffectInAsyncContext(effect.id.rawValue) ? .dotted : .solid

            case .state, .mutation, .batch:
                return .solid
            }
        }

        for id in orderedIDs {
            var predecessorIDs = causalPredecessors(for: id).compactMap { predecessorID in
                resolveVisibleNodeID(predecessorID)
            }
            let threadPredecessorID = effectThreadPredecessorByNodeID[id]
            let prefersSingleThreadPredecessor: Bool = {
                guard let item = itemsByID[id] else { return false }
                guard case .action(let action) = item.node else { return false }
                if case .effect = action.source {
                    return true
                }
                return false
            }()
            if prefersSingleThreadPredecessor, let threadPredecessorID {
                // For effect-sourced actions, prefer one continuation edge to avoid
                // synthetic + causal double incoming edges.
                predecessorIDs = [threadPredecessorID]
            }
            predecessorIDs = predecessorIDs.uniqued()
            predecessorIDsByID[id] = predecessorIDs

            let lineKindByPredecessor: [String: TraceViewer.EdgeLineKind] = Dictionary(
                uniqueKeysWithValues: predecessorIDs.map { predecessorID in
                    return (predecessorID, edgeLineKind(to: id))
                }
            )
            edgeLineKindByPredecessorID[id] = lineKindByPredecessor
        }

        return .init(
            laneByID: laneByID,
            predecessorIDsByID: predecessorIDsByID,
            edgeLineKindByPredecessorID: edgeLineKindByPredecessorID,
            sharedColumnAnchorByID: sharedColumnAnchorByID,
            maxLane: max(maxLane, 0)
        )
    }

    static func buildOverviewGraphPresentation(
        orderedTimelineIDs: [String],
        itemsByID: [String: TraceViewer.TimelineItem],
        laneByTimelineID: [String: Int],
        predecessorIDsByTimelineID: [String: [String]],
        edgeLineKindByPredecessorID: [String: [String: TraceViewer.EdgeLineKind]],
        sharedColumnAnchorByID: [String: String],
        maxTimelineLane: Int
    ) -> OverviewGraphPresentation {
        var graphLaneByTimelineID = laneByTimelineID.mapValues { max($0, 1) }
        for timelineID in orderedTimelineIDs {
            guard let item = itemsByID[timelineID] else { continue }
            if case .state = item.node {
                graphLaneByTimelineID[timelineID] = 0
            }
            else if graphLaneByTimelineID[timelineID] == nil {
                graphLaneByTimelineID[timelineID] = 1
            }
        }

        let knownGraphNodeIDs = Set(orderedTimelineIDs)
        var nodes: [OverviewGraphNode] = []
        nodes.reserveCapacity(orderedTimelineIDs.count)
        var nodeByID: [OverviewGraphNode.ID: OverviewGraphNode] = [:]
        var graphIDByTimelineID: [String: String] = [:]
        var columnByTimelineID: [String: Int] = [:]
        var maxLane = max(maxTimelineLane, 0)
        var nextColumn = 0

        for timelineID in orderedTimelineIDs {
            guard let item = itemsByID[timelineID] else { continue }
            let kind: OverviewGraphNode.Kind = {
                switch item.kind {
                case .state:
                    return .state
                case .flow:
                    return .flow
                case .mutation:
                    return .mutation
                case .effect:
                    return .effect
                case .batch:
                    return .batch
                }
            }()

            let column: Int = {
                if let anchorID = sharedColumnAnchorByID[timelineID],
                   let anchorColumn = columnByTimelineID[anchorID] {
                    return anchorColumn + 1
                }
                return nextColumn
            }()
            columnByTimelineID[timelineID] = column
            nextColumn = max(nextColumn, column + 1)

            let lane: Int = {
                if case .state = item.node { return 0 }
                return max(graphLaneByTimelineID[timelineID] ?? 1, 1)
            }()
            maxLane = max(maxLane, lane)

            let node = OverviewGraphNode(
                id: timelineID,
                kind: kind,
                colorKind: item.colorKind,
                column: column,
                lane: lane,
                predecessorIDs: (predecessorIDsByTimelineID[timelineID] ?? [])
                    .filter { knownGraphNodeIDs.contains($0) }
                    .uniqued(),
                edgeLineKindByPredecessorID: edgeLineKindByPredecessorID[timelineID] ?? [:],
                timelineID: timelineID,
                selectionTimelineID: timelineID
            )
            nodes.append(node)
            nodeByID[node.id] = node
            graphIDByTimelineID[timelineID] = timelineID
        }

        return .init(
            nodes: nodes,
            nodeByID: nodeByID,
            graphIDByTimelineID: graphIDByTimelineID,
            maxLane: max(maxLane, 0)
        )
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
        // Keep both only if something else happened between scheduled and applied.
        return (appliedIndex - scheduledIndex) > 1
    }
}
