//
//  TraceViewerListState.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 3/8/26.
//

import Foundation
import ReducerArchitecture

extension TraceViewerList.StoreState {
    private static var scopeBarEventKinds: [TraceViewer.EventKind] {
        [
            .state,
            .mutation,
            .effect,
            .flow,
        ]
    }

    init(traceCollection: SessionTraceCollection) {
        let timelineData = TraceViewer.TimelineData(traceCollection: traceCollection)

        self.traceCollection = timelineData.traceCollection
        self.orderedIDs = timelineData.orderedIDs
        self.itemsByID = timelineData.itemsByID
        self.childrenByParentID = timelineData.childrenByParentID
        self.descendantCountByID = timelineData.descendantCountByID
        self.scopeFilter = .all
        self.collapsedIDs = []
        self.selectedID = timelineData.orderedIDs.first
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

    var graphInput: TraceViewerGraph.Input {
        .init(
            visibleTimelineIDs: visibleIDs,
            selectableTimelineIDs: selectableVisibleIDs,
            selectedTimelineID: selectedID
        )
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

    func hasChildren(_ id: String) -> Bool {
        !(childrenByParentID[id] ?? []).isEmpty
    }

    func collapsedDescendantCount(for id: String) -> Int {
        guard collapsedIDs.contains(id) else { return 0 }
        return descendantCountByID[id] ?? 0
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
}
