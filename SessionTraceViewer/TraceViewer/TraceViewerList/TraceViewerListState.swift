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

    private static func parentIDByChildID(
        from childrenByParentID: [String: [String]]
    ) -> [String: String] {
        var parentIDByChildID: [String: String] = [:]
        for (parentID, childIDs) in childrenByParentID {
            for childID in childIDs where parentIDByChildID[childID] == nil {
                parentIDByChildID[childID] = parentID
            }
        }
        return parentIDByChildID
    }

    private static func descendantIDsByID(
        orderedIDs: [String],
        childrenByParentID: [String: [String]]
    ) -> [String: Set<String>] {
        var descendantIDsByID: [String: Set<String>] = [:]

        func descendantIDs(for id: String) -> Set<String> {
            if let cached = descendantIDsByID[id] {
                return cached
            }

            var collectedDescendantIDs: Set<String> = []
            for childID in childrenByParentID[id] ?? [] {
                collectedDescendantIDs.insert(childID)
                collectedDescendantIDs.formUnion(descendantIDs(for: childID))
            }
            descendantIDsByID[id] = collectedDescendantIDs
            return collectedDescendantIDs
        }

        for id in orderedIDs {
            _ = descendantIDs(for: id)
        }

        return descendantIDsByID
    }

    private static func ancestorIDsByID(
        orderedIDs: [String],
        parentIDByChildID: [String: String]
    ) -> [String: Set<String>] {
        var ancestorIDsByID: [String: Set<String>] = [:]

        for id in orderedIDs {
            var ancestors: Set<String> = []
            var cursor = id
            while let parentID = parentIDByChildID[cursor] {
                if !ancestors.insert(parentID).inserted { break }
                cursor = parentID
            }
            ancestorIDsByID[id] = ancestors
        }

        return ancestorIDsByID
    }

    init(traceCollection: SessionTraceCollection) {
        self.init(
            viewerData: TraceViewer.makeViewerData(
                traceSession: TraceViewer.traceSession(from: traceCollection),
                storeVisibilityByID: [
                    traceCollection.sessionGraph.storeInstanceID.rawValue: true
                ]
            )
        )
    }

    init(viewerData: TraceViewer.ViewerData) {
        let orderedIDSet = Set(viewerData.orderedIDs)
        let indexByID = Dictionary(
            uniqueKeysWithValues: viewerData.orderedIDs.enumerated().map { ($1, $0) }
        )
        let parentIDByChildID = Self.parentIDByChildID(from: viewerData.childrenByParentID)
        let descendantIDsByID = Self.descendantIDsByID(
            orderedIDs: viewerData.orderedIDs,
            childrenByParentID: viewerData.childrenByParentID
        )
        let ancestorIDsByID = Self.ancestorIDsByID(
            orderedIDs: viewerData.orderedIDs,
            parentIDByChildID: parentIDByChildID
        )
        let itemIDByIdentity = Dictionary(
            uniqueKeysWithValues: viewerData.itemsByID.values.map { item in
                (
                    ItemIdentity(
                        storeInstanceID: item.storeInstanceID,
                        localNodeID: item.localNodeID
                    ),
                    item.id
                )
            }
        )

        self.traceCollection = viewerData.primaryTraceCollection
        self.visibleStoreCount = viewerData.visibleStoreTraces.count
        self.orderedIDs = viewerData.orderedIDs
        self.orderedIDSet = orderedIDSet
        self.indexByID = indexByID
        self.itemsByID = viewerData.itemsByID
        self.itemIDByIdentity = itemIDByIdentity
        self.childrenByParentID = viewerData.childrenByParentID
        self.descendantIDsByID = descendantIDsByID
        self.ancestorIDsByID = ancestorIDsByID
        self.descendantCountByID = viewerData.descendantCountByID
        self.scopeFilter = .all
        self.collapsedIDs = []
        self.selectedID = viewerData.orderedIDs.first
        self.visibleIDs = []
        self.visibleIndexByID = [:]
        self.visibleItems = []
        self.selectableVisibleIDs = []
        self.selectableVisibleIndexByID = [:]
        self.selectableVisibleIDSet = []
        self.graphInput = .init(
            visibleTimelineIDs: [],
            selectableTimelineIDs: [],
            selectedTimelineID: nil
        )
        self.selectedItem = nil
        self.selectedPreviousStateItem = nil
        self.eventInspectorSelection = .init(item: nil, previousStateItem: nil)
        refreshDerivedData()
    }

    var hasVisibleStores: Bool {
        visibleStoreCount > 0
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

    private func matchesScopeFilter(_ item: TraceViewer.TimelineItem) -> Bool {
        switch scopeFilter {
        case .all:
            return true
        case .custom(let selection):
            return selection.eventKinds.contains(item.kind)
                || (selection.includesUserEvents && item.isUserSourceEvent)
        }
    }

    func isCollapsed(_ id: String) -> Bool {
        collapsedIDs.contains(id)
    }

    func isEventKindSelected(_ kind: TraceViewer.EventKind) -> Bool {
        guard case .custom(let selection) = scopeFilter else { return false }
        return selection.eventKinds.contains(kind)
    }

    func isSelectableTimelineID(_ id: String) -> Bool {
        selectableVisibleIDSet.contains(id)
    }

    func hasChildren(_ id: String) -> Bool {
        !(childrenByParentID[id] ?? []).isEmpty
    }

    func collapsedDescendantCount(for id: String) -> Int {
        guard collapsedIDs.contains(id) else { return 0 }
        return descendantCountByID[id] ?? 0
    }

    func descendants(of id: String) -> Set<String> {
        descendantIDsByID[id] ?? []
    }

    func ancestors(of id: String) -> Set<String> {
        ancestorIDsByID[id] ?? []
    }

    mutating func clampSelection(
        anchorID: String? = nil,
        prefersFirstSelectable: Bool = false,
        refreshVisibility: Bool = false
    ) {
        if refreshVisibility {
            refreshVisibilityDerivedData()
        }

        defer {
            refreshSelectionDerivedData()
        }

        let visibleIDs = visibleIDs
        let selectableVisibleIDs = selectableVisibleIDs
        guard !selectableVisibleIDs.isEmpty else {
            selectedID = nil
            return
        }

        if let selectedID, selectableVisibleIDSet.contains(selectedID) {
            return
        }

        if prefersFirstSelectable {
            selectedID = selectableVisibleIDs.first
            return
        }

        let selectableVisibleIDSet = self.selectableVisibleIDSet
        let anchorID = anchorID ?? selectedID
        if let anchorID,
           let anchorIndex = visibleIndexByID[anchorID] {
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
        refreshVisibilityDerivedData()
        clampSelection(prefersFirstSelectable: true)
    }

    mutating func selectEvent(id: String) {
        guard itemsByID[id] != nil else {
            return
        }
        if !isSelectableTimelineID(id) {
            scopeFilter = .all
            refreshVisibilityDerivedData()
        }
        selectedID = id
        refreshSelectionDerivedData()
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
        refreshVisibilityDerivedData()
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
        refreshVisibilityDerivedData()
        clampSelection(prefersFirstSelectable: true)
    }

    mutating func selectVisible(offset: Int) {
        let selectableVisibleIDs = selectableVisibleIDs
        guard !selectableVisibleIDs.isEmpty else {
            selectedID = nil
            refreshSelectionDerivedData()
            return
        }

        if selectedID == nil {
            selectedID = selectableVisibleIDs.first
            refreshSelectionDerivedData()
            return
        }

        guard let selectedID,
              let currentIndex = selectableVisibleIndexByID[selectedID] else {
            self.selectedID = selectableVisibleIDs.first
            refreshSelectionDerivedData()
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), selectableVisibleIDs.count - 1)
        self.selectedID = selectableVisibleIDs[nextIndex]
        refreshSelectionDerivedData()
    }

    mutating func selectFirstVisible() {
        selectedID = selectableVisibleIDs.first
        refreshSelectionDerivedData()
    }

    mutating func selectLastVisible() {
        selectedID = selectableVisibleIDs.last
        refreshSelectionDerivedData()
    }

    mutating func focusOnSelection() {
        guard let selectedID else { return }
        let protected = ancestors(of: selectedID)
            .union(descendants(of: selectedID))
            .union([selectedID])

        for id in orderedIDs where hasChildren(id) && !protected.contains(id) {
            collapsedIDs.insert(id)
        }
        clampSelection(refreshVisibility: true)
    }

    mutating func replaceViewerData(_ viewerData: TraceViewer.ViewerData) {
        let previousSelectedID = selectedID
        let previousSelectedItem = previousSelectedID.flatMap { itemsByID[$0] }
        let previousCollapsedIDs = collapsedIDs
        let previousScopeFilter = scopeFilter

        self = .init(viewerData: viewerData)
        scopeFilter = previousScopeFilter
        collapsedIDs = previousCollapsedIDs.intersection(orderedIDSet)
        refreshVisibilityDerivedData()
        if let previousSelectedID,
           itemsByID[previousSelectedID] != nil {
            selectedID = previousSelectedID
            clampSelection(anchorID: previousSelectedID)
            return
        }

        if let previousSelectedItem,
           let matchingSelectedID = selectionID(matching: previousSelectedItem) {
            selectedID = matchingSelectedID
            clampSelection(anchorID: matchingSelectedID)
            return
        }

        guard let previousSelectedItem else {
            clampSelection()
            return
        }

        let selectableVisibleIDs = selectableVisibleIDs
        guard !selectableVisibleIDs.isEmpty else {
            selectedID = nil
            refreshSelectionDerivedData()
            return
        }

        if let nextID = selectableVisibleIDs.first(where: { candidateID in
            guard let candidate = itemsByID[candidateID] else { return false }
            return Self.compareSelectionPosition(
                previous: previousSelectedItem,
                candidate: candidate
            )
        }) {
            selectedID = nextID
        }
        else {
            selectedID = selectableVisibleIDs.last
        }
        refreshSelectionDerivedData()
    }

    func selectionID(matching previousSelectedItem: TraceViewer.TimelineItem) -> String? {
        itemIDByIdentity[.init(
            storeInstanceID: previousSelectedItem.storeInstanceID,
            localNodeID: previousSelectedItem.localNodeID
        )]
    }

    static func compareSelectionPosition(
        previous: TraceViewer.TimelineItem,
        candidate: TraceViewer.TimelineItem
    ) -> Bool {
        switch (previous.date, candidate.date) {
        case let (previousDate?, candidateDate?) where previousDate != candidateDate:
            return candidateDate > previousDate
        case (.some, nil):
            return false
        case (nil, .some):
            return true
        default:
            break
        }

        if previous.storeInstanceID == candidate.storeInstanceID {
            return candidate.order > previous.order
        }
        if previous.order != candidate.order {
            return candidate.order > previous.order
        }
        return candidate.id > previous.id
    }

    mutating func replaceTraceCollection(_ traceCollection: SessionTraceCollection) {
        replaceViewerData(
            TraceViewer.makeViewerData(
                traceSession: TraceViewer.traceSession(from: traceCollection),
                storeVisibilityByID: [
                    traceCollection.sessionGraph.storeInstanceID.rawValue: true
                ]
            )
        )
    }

    private mutating func refreshDerivedData() {
        refreshVisibilityDerivedData()
        refreshSelectionDerivedData()
    }

    private mutating func refreshVisibilityDerivedData() {
        var hiddenIDs: Set<String> = []
        var nextVisibleIDs: [String] = []
        var nextVisibleItems: [TraceViewer.TimelineItem] = []
        var nextSelectableVisibleIDs: [String] = []
        nextVisibleIDs.reserveCapacity(orderedIDs.count)
        nextVisibleItems.reserveCapacity(orderedIDs.count)
        nextSelectableVisibleIDs.reserveCapacity(orderedIDs.count)

        for id in orderedIDs {
            guard !hiddenIDs.contains(id) else { continue }
            nextVisibleIDs.append(id)
            if let item = itemsByID[id] {
                nextVisibleItems.append(item)
                if matchesScopeFilter(item) {
                    nextSelectableVisibleIDs.append(id)
                }
            }

            if collapsedIDs.contains(id) {
                hiddenIDs.formUnion(descendants(of: id))
            }
        }

        visibleIDs = nextVisibleIDs
        visibleIndexByID = Dictionary(
            uniqueKeysWithValues: nextVisibleIDs.enumerated().map { ($1, $0) }
        )
        visibleItems = nextVisibleItems
        selectableVisibleIDs = nextSelectableVisibleIDs
        selectableVisibleIndexByID = Dictionary(
            uniqueKeysWithValues: selectableVisibleIDs.enumerated().map { ($1, $0) }
        )
        selectableVisibleIDSet = Set(selectableVisibleIDs)
    }

    private mutating func refreshSelectionDerivedData() {
        selectedItem = selectedID.flatMap { itemsByID[$0] }
        selectedPreviousStateItem = previousStateItem(for: selectedItem, selectedID: selectedID)
        graphInput = .init(
            visibleTimelineIDs: visibleIDs,
            selectableTimelineIDs: selectableVisibleIDs,
            selectedTimelineID: selectedID
        )
        eventInspectorSelection = .init(
            item: selectedItem,
            previousStateItem: selectedPreviousStateItem
        )
    }

    private func previousStateItem(
        for selectedItem: TraceViewer.TimelineItem?,
        selectedID: String?
    ) -> TraceViewer.TimelineItem? {
        guard let selectedID,
              let selectedItem,
              case .state = selectedItem.node,
              let selectedIndex = indexByID[selectedID],
              selectedIndex > 0 else {
            return nil
        }

        for index in stride(from: selectedIndex - 1, through: 0, by: -1) {
            guard let item = itemsByID[orderedIDs[index]] else { continue }
            if item.storeInstanceID == selectedItem.storeInstanceID,
               case .state = item.node {
                return item
            }
        }
        return nil
    }
}
