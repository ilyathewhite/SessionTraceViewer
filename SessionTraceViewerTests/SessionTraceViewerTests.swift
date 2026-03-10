import Foundation
import XCTest
import ReducerArchitecture
import Testing
@testable import SessionTraceViewer

@Suite
struct ModelTests {}

enum TestTraceFeature: StoreNamespace {
    typealias PublishedValue = Void

    struct StoreEnvironment {}

    enum MutatingAction {
        case increment
    }

    enum EffectAction {
        case none
    }

    struct StoreState {
        var count = 0
    }
}

enum SyncScheduledEffectsFeature: StoreNamespace {
    typealias PublishedValue = Void

    struct StoreEnvironment {}

    enum MutatingAction {
        case scheduleEffects
    }

    enum EffectAction {
        case startAlpha
        case startBeta
    }

    struct StoreState {
        var startedEffects: [String] = []
    }
}

extension TestTraceFeature {
    @MainActor
    static func store() -> Store {
        Store(.init(), env: .init())
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .increment:
            state.count += 1
            if state.count == 1 {
                return .action(.mutating(.increment))
            }
            return .none
        }
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        .none
    }
}

extension SyncScheduledEffectsFeature {
    @MainActor
    static func store() -> Store {
        Store(.init(), env: .init())
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .scheduleEffects:
            return .actions([
                .effect(.startAlpha),
                .effect(.startBeta)
            ])
        }
    }

    @MainActor
    static func runEffect(_ env: StoreEnvironment, _ state: StoreState, _ action: EffectAction) -> Store.Effect {
        switch action {
        case .startAlpha, .startBeta:
            return .asyncAction {
                try? await Task.sleep(for: .milliseconds(20))
                return .none
            }
        }
    }
}

@MainActor
func makeStateFromGeneratedTrace() throws -> TraceViewerList.StoreState {
    let name = "SessionTraceViewerTests-\(UUID().uuidString)"
    let store = TestTraceFeature.store()
    store.logConfig.sessionTraceFilename = name

    store.send(.mutating(.increment))
    store.saveSessionTraceIfNeeded()

    let traceURL = try savedTraceURL(named: name)
    defer { try? FileManager.default.removeItem(at: traceURL) }

    let data = try Data(contentsOf: traceURL)
    let collection = try SessionTraceCollection(fileData: data)
    return TraceViewerList.StoreState(traceCollection: collection)
}

@MainActor
func makeStateFromSyncScheduledEffectsTrace() async throws -> TraceViewerList.StoreState {
    let name = "SessionTraceViewerSyncEffects-\(UUID().uuidString)"
    let store = SyncScheduledEffectsFeature.store()
    store.logConfig.sessionTraceFilename = name

    let task = store.send(.mutating(.scheduleEffects))
    await task?.value
    store.saveSessionTraceIfNeeded()

    let traceURL = try savedTraceURL(named: name)
    defer { try? FileManager.default.removeItem(at: traceURL) }

    let data = try Data(contentsOf: traceURL)
    let collection = try SessionTraceCollection(fileData: data)
    return TraceViewerList.StoreState(traceCollection: collection)
}

func makeStateFromRecordMeetingTrace() throws -> TraceViewerList.StoreState {
    let traceURL = URL(fileURLWithPath: "/Users/ilya/Development/RecordMeeting.lzma")
    let data = try Data(contentsOf: traceURL)
    let collection = try SessionTraceCollection(fileData: data)
    return TraceViewerList.StoreState(traceCollection: collection)
}

func makeGraphState(from state: TraceViewerList.StoreState) -> TraceViewerGraph.StoreState {
    .init(
        traceCollection: state.traceCollection,
        input: state.graphInput
    )
}

func savedTraceURL(named name: String) throws -> URL {
    let fileManager = FileManager.default
    let cachesURL = try fileManager.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
    )
    let logsURL = cachesURL.appendingPathComponent("ReducerLogs")
    let files = try fileManager.contentsOfDirectory(
        at: logsURL,
        includingPropertiesForKeys: nil
    )
    guard let url = files.first(where: { file in
        let stem = file.deletingPathExtension().lastPathComponent
        return stem == name
    }) else {
        throw NSError(
            domain: "SessionTraceViewerTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Saved trace '\(name)' not found in \(logsURL.path)"]
        )
    }
    return url
}

func exactCaseLabel(from code: String?) -> String? {
    guard let code, !code.isEmpty, code != "nil" else { return nil }
    guard code.first == "." else { return code }

    var label = "."
    for character in code.dropFirst() {
        guard character.isLetter || character.isNumber || character == "_" else {
            break
        }
        label.append(character)
    }
    return label.count > 1 ? label : nil
}

func overviewEffectActionNode(
    named actionCase: String,
    in state: TraceViewerList.StoreState
) -> TraceViewerGraph.OverviewGraphNode? {
    overviewEffectActionNode(
        named: actionCase,
        in: state.graphState,
        itemsByID: state.itemsByID
    )
}

func overviewEffectActionNode(
    named actionCase: String,
    in graphState: TraceViewerGraph.StoreState,
    itemsByID: [String: TraceViewer.TimelineItem]
) -> TraceViewerGraph.OverviewGraphNode? {
    graphState.overviewGraphNodes.first { node in
        guard let item = itemsByID[node.id],
              case .action(let action) = item.node else {
            return false
        }
        return action.actionCase == actionCase && action.kind == .effect
    }
}

extension TraceViewerList.StoreState {
    var graph: SessionGraph {
        traceCollection.sessionGraph
    }

    var graphState: TraceViewerGraph.StoreState {
        makeGraphState(from: self)
    }

    var overviewGraphNodes: [TraceViewerGraph.OverviewGraphNode] {
        graphState.overviewGraphNodes
    }

    var overviewGraphNodeByID: [String: TraceViewerGraph.OverviewGraphNode] {
        graphState.overviewGraphNodeByID
    }

    var visibleOverviewGraphNodes: [TraceViewerGraph.OverviewGraphNode] {
        graphState.visibleOverviewGraphNodes
    }

    var selectableVisibleOverviewGraphNodeIDs: [String] {
        graphState.selectableVisibleOverviewGraphNodeIDs
    }

    var selectedOverviewGraphNodeID: String? {
        graphState.selectedOverviewGraphNodeID
    }

    var graphPresentation: TraceViewerGraph.Presentation {
        graphState.presentation
    }
}

func timelineActions(in effect: TraceViewerList.Store.SyncEffect) -> [TraceViewerList.Store.Action] {
    switch effect {
    case .action(let action):
        return [action]
    case .actions(let actions):
        return actions
    case .none:
        return []
    }
}

func eventInspectorSyncActions(
    in effect: EventInspector.Store.SyncEffect
) -> [EventInspector.Store.Action] {
    switch effect {
    case .action(let action):
        return [action]
    case .actions(let actions):
        return actions
    case .none:
        return []
    }
}

func containsResetTimelineListFocusAction(in effect: TraceViewerList.Store.SyncEffect) -> Bool {
    timelineActions(in: effect).contains { action in
        if case .effect(.resetTimelineListFocus) = action {
            return true
        }
        return false
    }
}

func scrolledTimelineID(in effect: TraceViewerList.Store.SyncEffect) -> String? {
    timelineActions(in: effect).compactMap { action in
        guard case .effect(.scrollTimelineListToID(let id)) = action else { return nil }
        return id
    }.last
}

func graphActions(in effect: TraceViewerGraph.Store.SyncEffect) -> [TraceViewerGraph.Store.Action] {
    switch effect {
    case .action(let action):
        return [action]
    case .actions(let actions):
        return actions
    case .none:
        return []
    }
}

func publishedGraphSelection(
    in effect: TraceViewerGraph.Store.SyncEffect
) -> TraceViewerGraph.PublishedValue? {
    graphActions(in: effect).compactMap { action in
        guard case .publish(let selection) = action else { return nil }
        return selection
    }
    .last
}

func liveTraceActions(in effect: LiveTrace.Store.SyncEffect) -> [LiveTrace.Store.Action] {
    switch effect {
    case .action(let action):
        return [action]
    case .actions(let actions):
        return actions
    case .none:
        return []
    }
}

func syncsSelectedLiveTraceViewer(in effect: LiveTrace.Store.SyncEffect) -> Bool {
    liveTraceActions(in: effect).contains { action in
        if case .effect(.syncSelectedTraceViewer) = action {
            return true
        }
        return false
    }
}

func makeEventInspectorEnv() -> EventInspector.StoreEnvironment {
    .init(
        syncInlineDiff: { _ in },
        openDiffWindow: { _ in }
    )
}

func formattedStateValue(property: String, in item: TraceViewer.TimelineItem) -> String? {
    guard case .state(let stateNode) = item.node else { return nil }
    return stateNode.state
        .first(where: { $0.property == property })?
        .value
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\t", with: "\t")
}
