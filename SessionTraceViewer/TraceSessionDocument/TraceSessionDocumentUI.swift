//
//  TraceSessionDocumentUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import ReducerArchitecture
import SwiftUI

struct TraceSessionDocumentView: View {
    let document: TraceSessionDocument
    @State private var selectedStoreID: String?
    @StateObject private var traceViewerStore: TraceViewer.Store

    init(document: TraceSessionDocument) {
        self.document = document
        self._selectedStoreID = State(initialValue: document.session.firstStoreTrace?.id)
        self._traceViewerStore = StateObject(
            wrappedValue: TraceViewer.store(
                traceCollection: document.session.firstStoreTrace?.traceCollection
                    ?? .placeholder(
                        title: "Store Trace",
                        storeInstanceID: "document.placeholder.store"
                    )
            )
        )
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(
                    minWidth: 240,
                    idealWidth: 280,
                    maxWidth: 360,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )

            TraceViewer.ContentView(traceViewerStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1240, minHeight: 860)
        .onAppear(perform: syncTraceViewerIfNeeded)
        .onChange(of: selectedStoreID) { _, _ in
            syncTraceViewerIfNeeded()
        }
    }

    private var selectedStore: TraceSession.StoreTrace? {
        document.session.storeTrace(id: selectedStoreID)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(document.session.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ViewerTheme.primaryText)

                ForEach(sessionSubtitleLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(ViewerTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(ViewerTheme.sectionBackground)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(document.session.storeTraces) { storeTrace in
                        TraceSessionStoreRow(
                            storeTrace: storeTrace,
                            isSelected: storeTrace.id == selectedStore?.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedStoreID = storeTrace.id
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(ViewerTheme.timelinePanelBackground)
        }
    }

    private var sessionSubtitleLines: [String] {
        var lines: [String] = []
        lines.append(
            document.session.storeTraces.count == 1
                ? "1 store"
                : "\(document.session.storeTraces.count) stores"
        )
        if let processName = normalized(document.session.processName),
           processName != document.session.title {
            lines.append(processName)
        }
        if let hostName = normalized(document.session.hostName) {
            lines.append(hostName)
        }
        return lines
    }

    private func syncTraceViewerIfNeeded() {
        guard let traceCollection = selectedStore?.traceCollection else { return }
        traceViewerStore.send(.mutating(.replaceTraceCollection(traceCollection)))
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct TraceSessionStoreRow: View {
    let storeTrace: TraceSession.StoreTrace
    let isSelected: Bool

    private var selectionBackgroundColor: Color {
        isSelected ? ViewerTheme.rowSelectedFill : .clear
    }

    private var selectionStrokeColor: Color {
        isSelected ? ViewerTheme.rowSelectedStroke : .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(ViewerTheme.effect)
                    .frame(width: 8, height: 8)

                Text(storeTrace.displayName)
                    .font(.headline)
                    .foregroundStyle(ViewerTheme.primaryText)
                    .lineLimit(1)
            }

            Text(storeTrace.storeInstanceID)
                .font(.system(size: 12))
                .foregroundStyle(ViewerTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionBackgroundColor)
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(selectionStrokeColor, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }
}
