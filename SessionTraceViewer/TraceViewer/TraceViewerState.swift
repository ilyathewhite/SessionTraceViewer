//
//  TraceViewerState.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/13/26.
//

import Foundation
import ReducerArchitecture

extension TraceViewer.StoreState {
    init(traceSession: TraceSession) {
        self.traceSession = traceSession
        self.storeVisibilityByID = Dictionary(
            uniqueKeysWithValues: traceSession.storeTraces.map { ($0.id, true) }
        )
        self.viewerData = TraceViewer.makeViewerData(
            traceSession: traceSession,
            storeVisibilityByID: storeVisibilityByID
        )
    }

    func storeLayerRoots() -> [TraceViewer.StoreLayer] {
        let orderedTraces = orderedStoreTraces
        let childrenByParentID = storeChildrenByParentID
        let timelineDataByStoreID = storeTimelineDataByStoreID
        let rootStoreIDs = Set(rootStoreTraces.map(\.id))
        var builtStoreIDs: Set<String> = []

        func buildStoreLayer(
            from storeTrace: TraceSession.StoreTrace,
            path: inout Set<String>
        ) -> TraceViewer.StoreLayer {
            let inserted = path.insert(storeTrace.id).inserted
            let childLayers: [TraceViewer.StoreLayer]
            if inserted {
                childLayers = (childrenByParentID[storeTrace.id] ?? []).compactMap { childStoreTrace in
                    guard !builtStoreIDs.contains(childStoreTrace.id) else { return nil }
                    return buildStoreLayer(from: childStoreTrace, path: &path)
                }
                path.remove(storeTrace.id)
            }
            else {
                childLayers = []
            }

            builtStoreIDs.insert(storeTrace.id)
            let timelineData = timelineDataByStoreID[storeTrace.id]
            return .init(
                id: storeTrace.id,
                displayName: storeTrace.displayName,
                isVisible: storeVisibilityByID[storeTrace.id] ?? true,
                childKeyLineText: childKeyLineText(for: storeTrace),
                statusText: storeStatusText(
                    for: storeTrace,
                    timelineData: timelineData
                ),
                eventCount: timelineData?.orderedIDs.count ?? 0,
                children: childLayers
            )
        }

        var roots: [TraceViewer.StoreLayer] = []
        for storeTrace in orderedTraces where rootStoreIDs.contains(storeTrace.id) {
            guard !builtStoreIDs.contains(storeTrace.id) else { continue }
            var path: Set<String> = []
            roots.append(buildStoreLayer(from: storeTrace, path: &path))
        }

        for storeTrace in orderedTraces where !builtStoreIDs.contains(storeTrace.id) {
            var path: Set<String> = []
            roots.append(buildStoreLayer(from: storeTrace, path: &path))
        }

        return roots
    }

    func storeLayers() -> [TraceViewer.StoreLayer] {
        flattenStoreLayers(storeLayerRoots())
    }

    mutating func replaceTraceSession(_ traceSession: TraceSession) {
        self.traceSession = traceSession
        var nextVisibilityByID: [String: Bool] = [:]
        for storeTrace in traceSession.storeTraces {
            nextVisibilityByID[storeTrace.id] = storeVisibilityByID[storeTrace.id] ?? true
        }
        storeVisibilityByID = nextVisibilityByID
        rebuildViewerData()
    }

    mutating func setStoreVisibility(id: String, isVisible: Bool) {
        guard let currentVisibility = storeVisibilityByID[id] else { return }
        let descendantIDs = storeDescendantIDs(of: id)
        let affectedStoreIDs = descendantIDs.union([id])
        guard currentVisibility != isVisible
                || affectedStoreIDs.contains(where: { storeVisibilityByID[$0] != isVisible }) else {
            return
        }

        for affectedStoreID in affectedStoreIDs {
            storeVisibilityByID[affectedStoreID] = isVisible
        }
        rebuildViewerData()
    }

    mutating func toggleStoreVisibility(id: String) {
        guard let currentVisibility = storeVisibilityByID[id] else { return }
        setStoreVisibility(id: id, isVisible: !currentVisibility)
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
    }

    private mutating func rebuildViewerData() {
        viewerData = TraceViewer.makeViewerData(
            traceSession: traceSession,
            storeVisibilityByID: storeVisibilityByID
        )
        contentVersion += 1
    }

    private var orderedStoreTraces: [TraceSession.StoreTrace] {
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

    private var traceSessionStoreIDs: Set<String> {
        Set(traceSession.storeTraces.map(\.id))
    }

    private var storeTimelineDataByStoreID: [String: TraceViewer.TimelineData] {
        Dictionary(
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
    }

    private var storeChildrenByParentID: [String: [TraceSession.StoreTrace]] {
        let availableStoreIDs = traceSessionStoreIDs
        return orderedStoreTraces.reduce(into: [:]) { partialResult, storeTrace in
            guard let parentStoreID = normalizedParentStoreID(
                for: storeTrace,
                availableStoreIDs: availableStoreIDs
            ) else {
                return
            }
            partialResult[parentStoreID, default: []].append(storeTrace)
        }
    }

    private var rootStoreTraces: [TraceSession.StoreTrace] {
        let availableStoreIDs = traceSessionStoreIDs
        return orderedStoreTraces.filter {
            normalizedParentStoreID(for: $0, availableStoreIDs: availableStoreIDs) == nil
        }
    }

    private func storeDescendantIDs(of storeID: String) -> Set<String> {
        var descendantIDs: Set<String> = []
        var stack: [String] = storeChildrenByParentID[storeID]?.map(\.id) ?? []

        while let nextStoreID = stack.popLast() {
            if descendantIDs.insert(nextStoreID).inserted {
                stack.append(contentsOf: storeChildrenByParentID[nextStoreID]?.map(\.id) ?? [])
            }
        }

        return descendantIDs
    }

    private func normalizedParentStoreID(
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

    private func flattenStoreLayers(_ storeLayers: [TraceViewer.StoreLayer]) -> [TraceViewer.StoreLayer] {
        storeLayers.flatMap { storeLayer in
            [storeLayer] + flattenStoreLayers(storeLayer.children)
        }
    }

    private func storeStatusText(
        for storeTrace: TraceSession.StoreTrace,
        timelineData: TraceViewer.TimelineData?
    ) -> String? {
        if storeTrace.startedAt != nil, storeTrace.endedAt == nil {
            return "Active"
        }

        let eventDates = timelineData?.orderedIDs.compactMap { timelineID in
            timelineData?.itemsByID[timelineID]?.date
        } ?? []
        let startedAt = storeTrace.startedAt ?? eventDates.min()
        let endedAt = storeTrace.endedAt ?? eventDates.max()

        guard let startedAt,
              let endedAt else {
            return nil
        }

        return TraceViewer.formatStoreDuration(endedAt.timeIntervalSince(startedAt))
    }

    private func childKeyLineText(for storeTrace: TraceSession.StoreTrace) -> String? {
        guard normalizedParentStoreID(
            for: storeTrace,
            availableStoreIDs: traceSessionStoreIDs
        ) != nil else {
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

    private func normalizedStoreText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func storeTypeName(from storeInstanceID: String) -> String {
        if let suffixRange = storeInstanceID.range(of: ".s", options: .backwards) {
            let suffix = storeInstanceID[suffixRange.upperBound...]
            if !suffix.isEmpty && suffix.allSatisfy(\.isNumber) {
                return String(storeInstanceID[..<suffixRange.lowerBound])
            }
        }
        return storeInstanceID
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
