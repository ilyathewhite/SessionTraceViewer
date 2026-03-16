//
//  TraceViewerState.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/13/26.
//

import Foundation
import ReducerArchitecture

extension TraceViewer.StoreState {
    struct SessionData {
        let orderedStoreTraces: [TraceSession.StoreTrace]
        let timelineDataByStoreID: [String: TraceViewer.TimelineData]
        let childrenByParentID: [String: [TraceSession.StoreTrace]]
        let rootStoreTraces: [TraceSession.StoreTrace]
        let childKeyLineTextByStoreID: [String: String]
        let statusTextByStoreID: [String: String]
        let eventCountByStoreID: [String: Int]

        init(traceSession: TraceSession) {
            let orderedStoreTraces = Self.orderedStoreTraces(from: traceSession)
            let availableStoreIDs = Set(orderedStoreTraces.map(\.id))
            let timelineDataByStoreID = Dictionary(
                uniqueKeysWithValues: traceSession.storeTraces.map { storeTrace in
                    (
                        storeTrace.id,
                        TraceViewer.TimelineData(
                            traceCollection: storeTrace.traceCollection,
                            storeInstanceID: storeTrace.storeInstanceID,
                            storeName: storeTrace.displayName
                        )
                    )
                }
            )

            var parentStoreIDByStoreID: [String: String] = [:]
            var childrenByParentID: [String: [TraceSession.StoreTrace]] = [:]
            for storeTrace in orderedStoreTraces {
                guard let parentStoreID = Self.normalizedParentStoreID(
                    for: storeTrace,
                    availableStoreIDs: availableStoreIDs
                ) else {
                    continue
                }
                parentStoreIDByStoreID[storeTrace.id] = parentStoreID
                childrenByParentID[parentStoreID, default: []].append(storeTrace)
            }

            let rootStoreTraces = orderedStoreTraces.filter {
                parentStoreIDByStoreID[$0.id] == nil
            }

            var childKeyLineTextByStoreID: [String: String] = [:]
            var statusTextByStoreID: [String: String] = [:]
            var eventCountByStoreID: [String: Int] = [:]

            for storeTrace in orderedStoreTraces {
                let timelineData = timelineDataByStoreID[storeTrace.id]
                if let childKeyLineText = Self.childKeyLineText(
                    for: storeTrace,
                    parentStoreIDByStoreID: parentStoreIDByStoreID
                ) {
                    childKeyLineTextByStoreID[storeTrace.id] = childKeyLineText
                }
                if let statusText = Self.storeStatusText(
                    for: storeTrace,
                    timelineData: timelineData
                ) {
                    statusTextByStoreID[storeTrace.id] = statusText
                }
                eventCountByStoreID[storeTrace.id] = timelineData?.orderedIDs.count ?? 0
            }

            self.orderedStoreTraces = orderedStoreTraces
            self.timelineDataByStoreID = timelineDataByStoreID
            self.childrenByParentID = childrenByParentID
            self.rootStoreTraces = rootStoreTraces
            self.childKeyLineTextByStoreID = childKeyLineTextByStoreID
            self.statusTextByStoreID = statusTextByStoreID
            self.eventCountByStoreID = eventCountByStoreID
        }

        private static func orderedStoreTraces(from traceSession: TraceSession) -> [TraceSession.StoreTrace] {
            traceSession.storeTraces
                .enumerated()
                .sorted { lhs, rhs in
                    switch (lhs.element.startedAt, rhs.element.startedAt) {
                    case let (.some(lhsStartedAt), .some(rhsStartedAt)):
                        if lhsStartedAt != rhsStartedAt {
                            return lhsStartedAt < rhsStartedAt
                        }
                    case (.some, nil):
                        return true
                    case (nil, .some):
                        return false
                    case (nil, nil):
                        break
                    }
                    return lhs.offset < rhs.offset
                }
                .map(\.element)
        }

        private static func normalizedParentStoreID(
            for storeTrace: TraceSession.StoreTrace,
            availableStoreIDs: Set<String>
        ) -> String? {
            guard let parentStoreID = storeTrace.parentStoreInstanceID,
                  parentStoreID != storeTrace.id,
                  availableStoreIDs.contains(parentStoreID) else {
                return nil
            }
            return parentStoreID
        }

        private static func storeStatusText(
            for storeTrace: TraceSession.StoreTrace,
            timelineData: TraceViewer.TimelineData?
        ) -> String? {
            if storeTrace.startedAt != nil, storeTrace.endedAt == nil {
                return "Active"
            }

            let startedAt = storeTrace.startedAt ?? timelineData?.firstDatedEventAt
            let endedAt = storeTrace.endedAt ?? timelineData?.lastDatedEventAt

            guard let startedAt,
                  let endedAt else {
                return nil
            }

            return TraceViewer.formatStoreDuration(endedAt.timeIntervalSince(startedAt))
        }

        private static func childKeyLineText(
            for storeTrace: TraceSession.StoreTrace,
            parentStoreIDByStoreID: [String: String]
        ) -> String? {
            guard parentStoreIDByStoreID[storeTrace.id] != nil else {
                return nil
            }
            guard let childKeyInParentStore = normalizedStoreText(storeTrace.childKeyInParentStore) else {
                return nil
            }
            guard childKeyInParentStore != normalizedStoreText(storeTrace.displayName) else {
                return nil
            }

            let storeTypeName = storeTypeName(from: storeTrace.storeInstanceID)
            let shortStoreTypeName = storeTypeName
                .split(separator: ".")
                .last
                .map(String.init)
                ?? storeTypeName
            let defaultChildKeys = Set([
                storeTypeName,
                shortStoreTypeName,
                "StateStore<\(storeTypeName)>",
                "StateStore<\(shortStoreTypeName)>"
            ])
            guard !defaultChildKeys.contains(childKeyInParentStore) else {
                return nil
            }

            return "as \(childKeyInParentStore)"
        }

        private static func normalizedStoreText(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private static func storeTypeName(from storeInstanceID: String) -> String {
            if let suffixRange = storeInstanceID.range(of: ".s", options: .backwards) {
                let suffix = storeInstanceID[suffixRange.upperBound...]
                if !suffix.isEmpty && suffix.allSatisfy(\.isNumber) {
                    return String(storeInstanceID[..<suffixRange.lowerBound])
                }
            }
            return storeInstanceID
        }
    }

    init(
        traceSession: TraceSession,
        defaultStoreVisibility: TraceViewer.DefaultStoreVisibility = .allVisible
    ) {
        let sessionData = SessionData(traceSession: traceSession)
        let storeVisibilityByID = Self.makeDefaultStoreVisibilityByID(
            for: traceSession,
            sessionData: sessionData,
            defaultStoreVisibility: defaultStoreVisibility
        )

        self.defaultStoreVisibility = defaultStoreVisibility
        self.traceSession = traceSession
        self.storeVisibilityByID = storeVisibilityByID
        self.sessionData = sessionData
        self.viewerData = TraceViewer.makeViewerData(
            traceSession: traceSession,
            storeVisibilityByID: storeVisibilityByID,
            localDataByStoreID: sessionData.timelineDataByStoreID
        )
        self.storeLayerRootCache = []
        self.storeLayerCache = []
        rebuildStoreLayerCache()
    }

    func storeLayerRoots() -> [TraceViewer.StoreLayer] {
        storeLayerRootCache
    }

    func storeLayers() -> [TraceViewer.StoreLayer] {
        storeLayerCache
    }

    mutating func replaceTraceSession(_ traceSession: TraceSession) {
        let previousVisibilityByID = storeVisibilityByID

        self.traceSession = traceSession
        self.sessionData = .init(traceSession: traceSession)
        let defaultVisibilityByID = Self.makeDefaultStoreVisibilityByID(
            for: traceSession,
            sessionData: sessionData,
            defaultStoreVisibility: defaultStoreVisibility
        )
        var nextVisibilityByID: [String: Bool] = [:]
        for storeTrace in traceSession.storeTraces {
            nextVisibilityByID[storeTrace.id] =
                previousVisibilityByID[storeTrace.id]
                ?? defaultVisibilityByID[storeTrace.id]
                ?? false
        }
        storeVisibilityByID = nextVisibilityByID
        rebuildViewerData()
        rebuildStoreLayerCache()
    }

    mutating func setStoreVisibility(id: String, isVisible: Bool) {
        guard let currentVisibility = storeVisibilityByID[id] else { return }
        guard currentVisibility != isVisible else {
            return
        }

        storeVisibilityByID[id] = isVisible
        rebuildViewerData()
        rebuildStoreLayerCache()
    }

    mutating func toggleStoreVisibility(id: String) {
        guard let currentVisibility = storeVisibilityByID[id] else { return }
        setStoreVisibility(id: id, isVisible: !currentVisibility)
    }

    mutating func showStore(id: String, additively: Bool) {
        guard let isVisible = storeVisibilityByID[id], !isVisible else { return }

        if additively {
            setStoreVisibility(id: id, isVisible: true)
        }
        else {
            showOnlyStore(id: id)
        }
    }

    mutating func showOnlyStore(id: String) {
        guard storeVisibilityByID[id] != nil else { return }
        guard storeVisibilityByID.contains(where: { storeID, isVisible in
            storeID == id ? !isVisible : isVisible
        }) else {
            return
        }

        for storeID in storeVisibilityByID.keys {
            storeVisibilityByID[storeID] = storeID == id
        }
        rebuildViewerData()
        rebuildStoreLayerCache()
    }

    private mutating func rebuildViewerData() {
        viewerData = TraceViewer.makeViewerData(
            traceSession: traceSession,
            storeVisibilityByID: storeVisibilityByID,
            localDataByStoreID: sessionData.timelineDataByStoreID
        )
        contentVersion += 1
    }

    private func flattenStoreLayers(_ storeLayers: [TraceViewer.StoreLayer]) -> [TraceViewer.StoreLayer] {
        storeLayers.flatMap { storeLayer in
            [storeLayer] + flattenStoreLayers(storeLayer.children)
        }
    }

    private static func makeDefaultStoreVisibilityByID(
        for traceSession: TraceSession,
        sessionData: SessionData,
        defaultStoreVisibility: TraceViewer.DefaultStoreVisibility
    ) -> [String: Bool] {
        switch defaultStoreVisibility {
        case .allVisible:
            return Dictionary(
                uniqueKeysWithValues: traceSession.storeTraces.map { ($0.id, true) }
            )

        case .firstCreatedOnly:
            guard let firstCreatedStoreID = sessionData.orderedStoreTraces.first?.id else {
                return [:]
            }
            return Dictionary(
                uniqueKeysWithValues: traceSession.storeTraces.map {
                    ($0.id, $0.id == firstCreatedStoreID)
                }
            )
        }
    }

    private mutating func rebuildStoreLayerCache() {
        var builtStoreIDs: Set<String> = []

        func buildStoreLayer(
            from storeTrace: TraceSession.StoreTrace,
            path: inout Set<String>
        ) -> TraceViewer.StoreLayer {
            let inserted = path.insert(storeTrace.id).inserted
            let childLayers: [TraceViewer.StoreLayer]
            if inserted {
                childLayers = (sessionData.childrenByParentID[storeTrace.id] ?? []).compactMap { childStoreTrace in
                    guard !builtStoreIDs.contains(childStoreTrace.id) else { return nil }
                    return buildStoreLayer(from: childStoreTrace, path: &path)
                }
                path.remove(storeTrace.id)
            }
            else {
                childLayers = []
            }

            builtStoreIDs.insert(storeTrace.id)
            return .init(
                id: storeTrace.id,
                displayName: storeTrace.displayName,
                isVisible: storeVisibilityByID[storeTrace.id] ?? true,
                childKeyLineText: sessionData.childKeyLineTextByStoreID[storeTrace.id],
                statusText: sessionData.statusTextByStoreID[storeTrace.id],
                eventCount: sessionData.eventCountByStoreID[storeTrace.id] ?? 0,
                children: childLayers
            )
        }

        var roots: [TraceViewer.StoreLayer] = []
        for storeTrace in sessionData.rootStoreTraces {
            guard !builtStoreIDs.contains(storeTrace.id) else { continue }
            var path: Set<String> = []
            roots.append(buildStoreLayer(from: storeTrace, path: &path))
        }

        for storeTrace in sessionData.orderedStoreTraces where !builtStoreIDs.contains(storeTrace.id) {
            var path: Set<String> = []
            roots.append(buildStoreLayer(from: storeTrace, path: &path))
        }

        storeLayerRootCache = roots
        storeLayerCache = flattenStoreLayers(roots)
    }
}

extension TraceViewer {
    static func traceSession(from traceCollection: SessionTraceCollection) -> TraceSession {
        let storeInstanceID = traceCollection.sessionGraph.storeInstanceID.rawValue
        return .init(
            sessionID: "viewer.single-session.\(storeInstanceID)",
            title: traceCollection.title,
            hostName: nil,
            processName: nil,
            startedAt: nil,
            storeTraces: [
                .init(
                    storeInstanceID: storeInstanceID,
                    storeName: traceCollection.title,
                    hostName: nil,
                    processName: nil,
                    startedAt: nil,
                    traceCollection: traceCollection
                )
            ]
        )
    }

    static func formatStoreDuration(_ duration: TimeInterval) -> String {
        let roundedSeconds = max(Int(duration.rounded()), 0)
        let day = 24 * 60 * 60
        let hour = 60 * 60
        let minute = 60

        if roundedSeconds >= day {
            let days = roundedSeconds / day
            let hours = (roundedSeconds % day) / hour
            return durationText(
                primaryValue: days,
                primaryUnit: "d",
                secondaryValue: hours,
                secondaryUnit: "h"
            )
        }

        if roundedSeconds >= hour {
            let hours = roundedSeconds / hour
            let minutes = (roundedSeconds % hour) / minute
            return durationText(
                primaryValue: hours,
                primaryUnit: "h",
                secondaryValue: minutes,
                secondaryUnit: "m"
            )
        }

        if roundedSeconds >= minute {
            let minutes = roundedSeconds / minute
            let seconds = roundedSeconds % minute
            return durationText(
                primaryValue: minutes,
                primaryUnit: "m",
                secondaryValue: seconds,
                secondaryUnit: "s"
            )
        }

        return "\(roundedSeconds)s"
    }

    private static func durationText(
        primaryValue: Int,
        primaryUnit: String,
        secondaryValue: Int,
        secondaryUnit: String
    ) -> String {
        let primary = "\(primaryValue)\(primaryUnit)"
        guard secondaryValue > 0 else { return primary }
        return "\(primary), \(secondaryValue)\(secondaryUnit)"
    }
}
