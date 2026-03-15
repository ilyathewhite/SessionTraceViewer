//
//  TraceViewerUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import ReducerArchitecture
import SwiftUI

extension TraceViewer: StoreUINamespace {
    struct ContentView: StoreContentView {
        typealias Nsp = TraceViewer
        
        @ObservedObject var store: Store
        @StateObject private var traceViewerListStore = TraceViewerList.store()
        @StateObject private var traceViewerGraphStore = TraceViewerGraph.store()

        private let timelineListIdealWidth: CGFloat = 420
        private let timelineListMinimumWidth: CGFloat = 220

        init(_ store: Store) {
            self.store = store
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    ViewerTheme.background
                        .ignoresSafeArea()

                    VisibleStoreContentView(
                        listStore: traceViewerListStore,
                        graphStore: traceViewerGraphStore,
                        timelineListWidth: timelineListWidth(for: geometry.size.width),
                        moveGraphSelection: moveGraphSelection
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.borderless)
            .preferredColorScheme(.light)
            .connectOnAppear {
                let parentStore = store
                let traceViewerListStore = traceViewerListStore
                let traceViewerGraphStore = traceViewerGraphStore

                traceViewerListStore.bind(to: parentStore, on: \.viewerData) {
                    .mutating(.replaceViewerData($0))
                }

                traceViewerGraphStore.bind(to: parentStore, on: \.viewerData) {
                    .mutating(.replaceViewerData($0))
                }

                traceViewerGraphStore.bind(to: traceViewerListStore, on: \.graphInput) {
                    .mutating(.updateInput($0))
                }

                traceViewerListStore.bindPublishedValue(of: traceViewerGraphStore) {
                    .mutating(
                        .selectEvent(
                            id: $0.timelineID,
                            shouldFocus: $0.shouldFocusTimelineList
                        )
                    )
                }
            }
        }

        private func timelineListWidth(for availableWidth: CGFloat) -> CGFloat {
            let preferredWidth = min(
                timelineListIdealWidth,
                max(timelineListMinimumWidth, availableWidth * 0.42)
            )
            return min(max(availableWidth - 1, 0), preferredWidth)
        }

        private var moveGraphSelection: (Int) -> Void {
            { offset in
                traceViewerGraphStore.send(
                    .mutating(
                        .selectAdjacentNode(
                            offset: offset,
                            shouldFocusTimelineList: true
                        )
                    )
                )
            }
        }
    }

    struct VisibleStoreContentView: View {
        @ObservedObject var listStore: TraceViewerList.Store
        @ObservedObject var graphStore: TraceViewerGraph.Store
        let timelineListWidth: CGFloat
        let moveGraphSelection: (Int) -> Void

        var body: some View {
            VStack(spacing: 0) {
                if listStore.state.hasVisibleStores {
                    graphStore.contentView

                    Divider()

                    ScopeBarSectionView(store: listStore)

                    Divider()

                    if listStore.state.visibleItems.isEmpty {
                        emptyTimelinePlaceholder
                    }
                    else {
                        HStack(spacing: 8) {
                            TraceViewerList.ContentView(
                                listStore,
                                moveGraphSelection: moveGraphSelection
                            )
                            .frame(width: timelineListWidth)
                            .frame(maxHeight: .infinity)

                            TraceViewerDetails.SelectionContentView(
                                selection: listStore.state.eventInspectorSelection
                            )
                            .id(detailsSelectionIdentity)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .viewerInsetPanelStyle()
                        .background(ViewerTheme.traceViewerContentBackground)
                    }
                }
                else {
                    noVisibleStoresPlaceholder
                }
            }
        }

        private var detailsSelectionIdentity: String {
            let selectedItemID = listStore.state.eventInspectorSelection.item?.id ?? "none"
            let previousStateItemID = listStore.state.eventInspectorSelection.previousStateItem?.id ?? "none"
            return "\(selectedItemID)::\(previousStateItemID)"
        }

        private var noVisibleStoresPlaceholder: some View {
            ContentUnavailableView(
                "No Store Selected",
                systemImage: "eye.slash",
                description: Text("Show a store in the sidebar to inspect its timeline and details.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .viewerInsetPanelStyle()
            .background(ViewerTheme.traceViewerContentBackground)
        }

        private var emptyTimelinePlaceholder: some View {
            ContentUnavailableView(
                "No Timeline Events",
                systemImage: "list.bullet",
                description: Text("The visible stores do not contain any recorded events.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .viewerInsetPanelStyle()
            .background(ViewerTheme.traceViewerContentBackground)
        }
    }

    struct ScopeBarSectionView: View {
        @ObservedObject var store: TraceViewerList.Store

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    TraceViewer.ScopeBarButton(
                        title: "All",
                        isSelected: store.state.isAllEventKindsSelected,
                        textColor: ViewerTheme.scopeBarAllText,
                        backgroundColor: ViewerTheme.scopeBarAllBackground,
                        strokeColor: ViewerTheme.scopeBarAllStroke
                    ) {
                        store.send(.mutating(.selectAllEventKinds))
                    }

                    TraceViewer.ScopeBarButton(
                        title: "User",
                        isSelected: store.state.isUserEventFilterSelected,
                        textColor: ViewerTheme.scopeBarUserText,
                        backgroundColor: ViewerTheme.scopeBarUserBackground,
                        strokeColor: ViewerTheme.scopeBarUserStroke
                    ) {
                        store.send(.mutating(.toggleUserEventFilter))
                    }

                    HStack(spacing: 4) {
                        ForEach(store.state.scopeBarKinds, id: \.self) { kind in
                            TraceViewer.ScopeBarButton(
                                title: kind.rawValue,
                                isSelected: store.state.isEventKindSelected(kind),
                                textColor: ViewerTheme.chipText(for: kind),
                                backgroundColor: ViewerTheme.chipBackground(for: kind),
                                strokeColor: ViewerTheme.chipStroke(for: kind)
                            ) {
                                store.send(.mutating(.toggleEventKindFilter(kind)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ViewerTheme.traceViewerScopeBarBackground)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(ViewerTheme.sectionStroke)
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    struct StoreLayersOutlineView: View {
        @ObservedObject var store: TraceViewer.Store
        let rowVerticalPadding: CGFloat
        @State private var expandedStoreIDs: Set<String> = []
        @State private var knownExpandableStoreIDs: Set<String> = []

        init(store: TraceViewer.Store, rowVerticalPadding: CGFloat = 3) {
            self.store = store
            self.rowVerticalPadding = rowVerticalPadding
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(outlineEntries) { entry in
                    StoreLayerOutlineRow(
                        storeLayer: entry.storeLayer,
                        depth: entry.depth,
                        isExpanded: entry.isExpanded,
                        rowVerticalPadding: rowVerticalPadding
                    ) {
                        toggleExpansion(for: entry.storeLayer)
                    } toggleVisibility: {
                        store.send(
                            .mutating(
                                .setStoreVisibility(
                                    id: entry.storeLayer.id,
                                    isVisible: !entry.storeLayer.isVisible
                                )
                            )
                        )
                    } isolateStore: {
                        store.send(
                            .mutating(
                                .showOnlyStore(id: entry.storeLayer.id)
                            )
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                syncExpansionState(with: store.state.storeLayerRoots())
            }
            .onChange(of: store.state.storeLayerRoots()) { _, newRoots in
                syncExpansionState(with: newRoots)
            }
        }

        private var outlineEntries: [StoreLayerOutlineEntry] {
            flattenedEntries(
                from: store.state.storeLayerRoots(),
                depth: 0
            )
        }

        private func flattenedEntries(
            from storeLayers: [TraceViewer.StoreLayer],
            depth: Int
        ) -> [StoreLayerOutlineEntry] {
            storeLayers.flatMap { storeLayer in
                let isExpanded = storeLayer.children.isEmpty || expandedStoreIDs.contains(storeLayer.id)
                let children = isExpanded
                    ? flattenedEntries(from: storeLayer.children, depth: depth + 1)
                    : []
                return [.init(
                    storeLayer: storeLayer,
                    depth: depth,
                    isExpanded: isExpanded
                )] + children
            }
        }

        private func toggleExpansion(for storeLayer: TraceViewer.StoreLayer) {
            guard !storeLayer.children.isEmpty else { return }
            if expandedStoreIDs.contains(storeLayer.id) {
                expandedStoreIDs.remove(storeLayer.id)
            }
            else {
                expandedStoreIDs.insert(storeLayer.id)
            }
        }

        private func syncExpansionState(with roots: [TraceViewer.StoreLayer]) {
            let expandableStoreIDs = Set(allExpandableStoreIDs(in: roots))
            if knownExpandableStoreIDs.isEmpty {
                expandedStoreIDs = expandableStoreIDs
            }
            else {
                let newExpandableStoreIDs = expandableStoreIDs.subtracting(knownExpandableStoreIDs)
                expandedStoreIDs.formUnion(newExpandableStoreIDs)
                expandedStoreIDs.formIntersection(expandableStoreIDs)
            }
            knownExpandableStoreIDs = expandableStoreIDs
        }

        private func allExpandableStoreIDs(in roots: [TraceViewer.StoreLayer]) -> [String] {
            roots.flatMap { storeLayer in
                let descendantIDs = allExpandableStoreIDs(in: storeLayer.children)
                if storeLayer.children.isEmpty {
                    return descendantIDs
                }
                return [storeLayer.id] + descendantIDs
            }
        }
    }

    struct StoreLayerOutlineRow: View {
        let storeLayer: TraceViewer.StoreLayer
        let depth: Int
        let isExpanded: Bool
        let rowVerticalPadding: CGFloat
        let toggleExpansion: () -> Void
        let toggleVisibility: () -> Void
        let isolateStore: () -> Void
        @State private var isHovered = false

        private let baseLeadingPadding: CGFloat = 8
        private let indentationWidth: CGFloat = 16
        private let disclosureWidth: CGFloat = 14
        private let actionButtonSize: CGFloat = 22
        private let actionButtonsWidth: CGFloat = 48

        private var rowTitleColor: Color {
            storeLayer.isVisible ? ViewerTheme.primaryText : ViewerTheme.secondaryText
        }

        private var controlTintColor: Color {
            storeLayer.isVisible ? ViewerTheme.secondaryText : ViewerTheme.tertiaryText
        }

        private var hiddenContentOpacity: Double {
            storeLayer.isVisible ? 1 : 0.64
        }

        var body: some View {
            HStack(spacing: 8) {
                disclosureButton

                VStack(alignment: .leading, spacing: 1) {
                    Text(storeLayer.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(rowTitleColor)
                        .lineLimit(1)

                    if let childKeyLineText = storeLayer.childKeyLineText {
                        Text(childKeyLineText)
                            .font(.system(size: 11))
                            .foregroundStyle(controlTintColor)
                            .lineLimit(1)
                    }

                    Text(storeLayer.metadataText)
                        .font(.system(size: 11))
                        .foregroundStyle(controlTintColor)
                        .lineLimit(1)
                }
                .opacity(hiddenContentOpacity)

                Spacer(minLength: 0)

                actionButtons
            }
            .padding(.leading, baseLeadingPadding + CGFloat(depth) * indentationWidth)
            .padding(.trailing, 10)
            .padding(.vertical, rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
        }

        @ViewBuilder
        private var disclosureButton: some View {
            if storeLayer.children.isEmpty {
                Color.clear
                    .frame(width: disclosureWidth, height: disclosureWidth)
            }
            else {
                Button(action: toggleExpansion) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(controlTintColor)
                        .opacity(hiddenContentOpacity)
                        .frame(width: disclosureWidth, height: disclosureWidth)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse Child Stores" : "Expand Child Stores")
            }
        }

        private var actionButtons: some View {
            ZStack(alignment: .trailing) {
                if !storeLayer.isVisible && !isHovered {
                    HStack(spacing: 4) {
                        Color.clear
                            .frame(width: actionButtonSize, height: actionButtonSize)
                        statusIconSlot
                    }
                }

                HStack(spacing: 4) {
                    hoverActionButton(
                        systemName: "viewfinder",
                        helpText: storeLayer.isVisible
                            ? "Hide Other Stores"
                            : "Show This Store Only",
                        action: isolateStore
                    )

                    hoverActionButton(
                        systemName: storeLayer.isVisible ? "eye" : "eyebrow",
                        fallbackSystemName: storeLayer.isVisible ? nil : "eye.slash",
                        helpText: storeLayer.isVisible
                            ? "Hide Store Subtree"
                            : "Show Store Subtree",
                        action: toggleVisibility
                    )
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .accessibilityHidden(!isHovered)
            }
            .frame(width: actionButtonsWidth, alignment: .trailing)
        }

        private func hoverActionButton(
            systemName: String,
            fallbackSystemName: String? = nil,
            helpText: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                iconView(
                    systemName: systemName,
                    fallbackSystemName: fallbackSystemName
                )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(controlTintColor)
                    .frame(width: actionButtonSize, height: actionButtonSize)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(ViewerTheme.sectionBackground)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(ViewerTheme.sectionStroke, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityLabel(helpText)
        }

        private var statusIconSlot: some View {
            iconView(
                systemName: "eyebrow",
                fallbackSystemName: "eye.slash"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(controlTintColor)
            .opacity(hiddenContentOpacity)
            .frame(width: actionButtonSize, height: actionButtonSize)
        }

        @ViewBuilder
        private func iconView(
            systemName: String,
            fallbackSystemName: String?
        ) -> some View {
            if let symbolImage = NSImage(
                systemSymbolName: systemName,
                accessibilityDescription: nil
            ) {
                Image(nsImage: symbolImage)
            }
            else if let fallbackSystemName {
                Image(systemName: fallbackSystemName)
            }
            else {
                Image(systemName: systemName)
            }
        }
    }

    struct StoreLayerOutlineEntry: Identifiable {
        let storeLayer: TraceViewer.StoreLayer
        let depth: Int
        let isExpanded: Bool

        var id: String {
            storeLayer.id
        }
    }
}
