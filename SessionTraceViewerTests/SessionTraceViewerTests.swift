import Foundation
import XCTest
import ReducerArchitecture
import Testing
@testable import SessionTraceViewer

@Suite
struct ModelTests {}

extension ModelTests {
    @Suite struct TraceSessionDocumentModelTests {}
}

extension ModelTests.TraceSessionDocumentModelTests {
    @Test
    func testNewTraceSessionDocumentStartsAsRecordingDocument() {
        let document = TraceSessionDocument()

        XCTAssertTrue(document.isRecording)
        XCTAssertEqual(document.session.storeTraces.count, 0)
        if case .recording(let port) = document.recordingMode {
            XCTAssertEqual(port, LiveTraceDefaults.defaultPort)
        }
        else {
            XCTFail("Expected a new trace session document to start in recording mode.")
        }
    }

    @Test
    func testLoadedTraceSessionDocumentIsStatic() {
        let session = TraceSession.placeholder(
            title: "Saved Session",
            sessionID: "saved.session"
        )
        let document = TraceSessionDocument(loadedSession: session)

        XCTAssertFalse(document.isRecording)
        XCTAssertEqual(document.recordingMode, .staticTrace)
        XCTAssertEqual(document.session, session)
    }

    @Test
    func testRecordingDocumentUpdatesSavedSnapshotWithoutStopping() {
        var document = TraceSessionDocument()
        let session = TraceSession.placeholder(
            title: "Recorded Session",
            sessionID: "recorded.session"
        )

        document.updateRecordingSnapshot(with: session)

        XCTAssertTrue(document.isRecording)
        XCTAssertEqual(document.session, session)
        if case .recording(let port) = document.recordingMode {
            XCTAssertEqual(port, LiveTraceDefaults.defaultPort)
        }
        else {
            XCTFail("Expected the document to remain in recording mode while syncing snapshots.")
        }
    }

    @Test
    func testStaticDocumentIgnoresRecordingSnapshotUpdates() {
        let session = TraceSession.placeholder(
            title: "Saved Session",
            sessionID: "saved.session"
        )
        var document = TraceSessionDocument(loadedSession: session)

        document.updateRecordingSnapshot(
            with: .placeholder(
                title: "Unexpected Recording Session",
                sessionID: "unexpected.recording.session"
            )
        )

        XCTAssertFalse(document.isRecording)
        XCTAssertEqual(document.session, session)
    }

    @Test
    func testTraceSessionDocumentWritesOnlyLZMAContentType() {
        XCTAssertEqual(
            TraceSessionDocument.writableContentTypes,
            [.sessionTraceLZMA]
        )
    }

    @Test
    func testTraceSessionDocumentSuggestedFilenameStripsTrailingLZMAExtension() {
        XCTAssertEqual(
            TraceSessionDocument.suggestedFilename(from: "TraceSession.lzma"),
            "TraceSession"
        )
        XCTAssertEqual(
            TraceSessionDocument.suggestedFilename(from: "TraceSession"),
            "TraceSession"
        )
    }
}

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
func makeStateFromGeneratedTrace() async throws -> TraceViewerList.StoreState {
    let store = TestTraceFeature.store()
    let collectionTask = liveTraceCollectionTask(for: store)

    store.send(.mutating(.increment))

    let collection = try await collectionTask.value
    return TraceViewerList.StoreState(traceCollection: collection)
}

@MainActor
func makeStateFromSyncScheduledEffectsTrace() async throws -> TraceViewerList.StoreState {
    let store = SyncScheduledEffectsFeature.store()
    let collectionTask = liveTraceCollectionTask(for: store)

    let task = store.send(.mutating(.scheduleEffects))
    await task?.value

    let collection = try await collectionTask.value
    return TraceViewerList.StoreState(traceCollection: collection)
}

@MainActor
func makeCombinedTraceSessionForTests() async throws -> TraceSession {
    let alphaCollection = try await makeStateFromGeneratedTrace().traceCollection
    try await Task.sleep(for: .milliseconds(20))

    let betaCollection = try await makeStateFromSyncScheduledEffectsTrace().traceCollection
    try await Task.sleep(for: .milliseconds(20))

    let gammaCollection = try await makeStateFromGeneratedTrace().traceCollection

    return TraceSession(
        sessionID: "combined.trace-session.tests",
        title: "Combined Trace Session",
        hostName: "Test Host",
        processName: "SessionTraceViewerTests",
        startedAt: Date(timeIntervalSince1970: 100),
        storeTraces: [
            .init(
                storeInstanceID: "alpha.s1",
                storeName: "Alpha Store",
                hostName: nil,
                processName: nil,
                startedAt: Date(timeIntervalSince1970: 100),
                endedAt: Date(timeIntervalSince1970: 110),
                traceCollection: alphaCollection
            ),
            .init(
                storeInstanceID: "beta.s2",
                storeName: "Beta Store",
                hostName: nil,
                processName: nil,
                startedAt: Date(timeIntervalSince1970: 105),
                endedAt: Date(timeIntervalSince1970: 130),
                traceCollection: betaCollection
            ),
            .init(
                storeInstanceID: "gamma.s3",
                storeName: "Gamma Store",
                hostName: nil,
                processName: nil,
                startedAt: Date(timeIntervalSince1970: 140),
                endedAt: Date(timeIntervalSince1970: 150),
                traceCollection: gammaCollection
            )
        ]
    )
}

@MainActor
func makeHierarchicalTraceSessionForTests() async throws -> TraceSession {
    let collection = try await makeStateFromGeneratedTrace().traceCollection

    return TraceSession(
        sessionID: "hierarchical.trace-session.tests",
        title: "Hierarchical Trace Session",
        hostName: "Test Host",
        processName: "SessionTraceViewerTests",
        startedAt: Date(timeIntervalSince1970: 200),
        storeTraces: [
            .init(
                storeInstanceID: "root.s1",
                storeName: "Root Store",
                hostName: nil,
                processName: nil,
                startedAt: Date(timeIntervalSince1970: 200),
                endedAt: Date(timeIntervalSince1970: 230),
                traceCollection: collection
            ),
            .init(
                storeInstanceID: "child.a.s2",
                storeName: "Child Store A",
                parentStoreInstanceID: "root.s1",
                childKeyInParentStore: "childA",
                hostName: nil,
                processName: nil,
                startedAt: Date(timeIntervalSince1970: 205),
                endedAt: Date(timeIntervalSince1970: 225),
                traceCollection: collection
            ),
            .init(
                storeInstanceID: "grandchild.s3",
                storeName: "Grandchild Store",
                parentStoreInstanceID: "child.a.s2",
                childKeyInParentStore: "grandchild",
                hostName: nil,
                processName: nil,
                startedAt: Date(timeIntervalSince1970: 210),
                endedAt: Date(timeIntervalSince1970: 220),
                traceCollection: collection
            ),
            .init(
                storeInstanceID: "child.b.s4",
                storeName: "Child Store B",
                parentStoreInstanceID: "root.s1",
                childKeyInParentStore: "childB",
                hostName: nil,
                processName: nil,
                startedAt: Date(timeIntervalSince1970: 215),
                endedAt: Date(timeIntervalSince1970: 228),
                traceCollection: collection
            ),
            .init(
                storeInstanceID: "independent.s5",
                storeName: "Independent Store",
                hostName: nil,
                processName: nil,
                startedAt: Date(timeIntervalSince1970: 240),
                endedAt: Date(timeIntervalSince1970: 250),
                traceCollection: collection
            )
        ]
    )
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

func makeGraphInput(from viewerData: TraceViewer.ViewerData) -> TraceViewerGraph.Input {
    .init(
        visibleTimelineIDs: viewerData.orderedIDs,
        selectableTimelineIDs: viewerData.orderedIDs,
        selectedTimelineID: viewerData.orderedIDs.first
    )
}

@MainActor
func liveTraceCollectionTask<Nsp: StoreNamespace>(
    for store: Nsp.Store
) -> Task<SessionTraceCollection, Error> {
    let collector = LiveTraceEnvelopeCollector()
    configureLiveTraceForTests(store: store, collector: collector)
    return Task {
        try await collector.waitForFirstStableCollection()
    }
}

@MainActor
private func configureLiveTraceForTests<Nsp: StoreNamespace>(
    store: Nsp.Store,
    collector: LiveTraceEnvelopeCollector
) {
    let originalConfig = LiveTraceConfig.shared
    collector.setOriginalConfig(originalConfig)

    var config = originalConfig
    config.networkEnabled = false
    config.envelopeHandler = { [weak collector] envelope in
        collector?.receive(envelope)
    }
    LiveTraceConfig.shared = config
    store.logConfig.liveTraceEnabled = .selfOnly
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

final class LiveTraceEnvelopeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionOrder: [String] = []
    private var accumulators: [String: LiveTraceSessionAccumulator] = [:]
    private var originalConfig: LiveTraceConfig?

    @MainActor
    func setOriginalConfig(_ config: LiveTraceConfig) {
        originalConfig = config
    }

    deinit {
        guard let originalConfig else { return }
        Task { @MainActor in
            LiveTraceConfig.shared = originalConfig
        }
    }

    func receive(_ envelope: LiveTraceEnvelope) {
        lock.lock()
        defer { lock.unlock() }

        var accumulator = accumulators[envelope.sessionID] ?? {
            sessionOrder.append(envelope.sessionID)
            return .init(
                title: "Live Trace",
                sessionID: envelope.sessionID
            )
        }()
        accumulator.apply(envelope)
        accumulators[envelope.sessionID] = accumulator
    }

    func waitForFirstStableCollection(
        timeout: Duration = .seconds(1)
    ) async throws -> SessionTraceCollection {
        let session = try await waitForFirstStableSession(timeout: timeout)
        guard let collection = session.firstStoreTrace?.traceCollection else {
            throw NSError(
                domain: "SessionTraceViewerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for live trace collection."]
            )
        }
        return collection
    }

    func waitForFirstStableSession(
        timeout: Duration = .seconds(1)
    ) async throws -> TraceSession {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var lastSignature: (Int, Int)?
        var stableSamples = 0

        while clock.now < deadline {
            if let session = firstSession() {
                let signature = (
                    session.storeTraces.reduce(0) { $0 + $1.traceCollection.sessionGraph.nodes.count },
                    session.storeTraces.reduce(0) { $0 + $1.traceCollection.sessionGraph.edges.count }
                )
                if signature.0 > 0 {
                    if lastSignature?.0 == signature.0 && lastSignature?.1 == signature.1 {
                        stableSamples += 1
                    }
                    else {
                        lastSignature = signature
                        stableSamples = 0
                    }

                    if stableSamples >= 3 {
                        return session
                    }
                }
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        throw NSError(
            domain: "SessionTraceViewerTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for live trace collection."]
        )
    }

    private func firstCollection() -> SessionTraceCollection? {
        firstSession()?.firstStoreTrace?.traceCollection
    }

    private func firstSession() -> TraceSession? {
        lock.lock()
        defer { lock.unlock() }

        guard let sessionID = sessionOrder.first,
              let accumulator = accumulators[sessionID] else {
            return nil
        }
        return accumulator.session
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

func eventInspectorActions(
    in effect: EventInspector.Store.Effect
) -> [EventInspector.Store.Action] {
    switch effect {
    case .action(let action, _):
        return [action]
    case .actions(let actions, _):
        return actions
    case .none:
        return []
    default:
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

func makeEventInspectorEnv(
    syncInlineDiff: @escaping @MainActor (StringDiff.Input?) -> Void = { _ in },
    openDiffWindow: @escaping @MainActor (StringDiff.Input) -> Void = { _ in },
    openExternalDiff: @escaping @MainActor (StringDiff.Input) -> Bool = { _ in true },
    openValueWindow: @escaping @MainActor (EventInspector.ValueWindowInput) -> Void = { _ in }
) -> EventInspector.StoreEnvironment {
    .init(
        syncInlineDiff: syncInlineDiff,
        openDiffWindow: openDiffWindow,
        openExternalDiff: openExternalDiff,
        openValueWindow: openValueWindow
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
