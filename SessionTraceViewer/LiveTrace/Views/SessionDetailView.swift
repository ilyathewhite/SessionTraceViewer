//
//  SessionDetailView.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import ReducerArchitecture
import SwiftUI

extension LiveTrace {
    struct SessionDetailView: View {
        let session: StoreState.Session
        let traceViewerStore: TraceViewer.Store
        let selectStore: (String) -> Void

        private let metadataColor = ViewerTheme.timestampText

        var body: some View {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.title3.weight(.semibold))
                        if let selectedStore = session.selectedStore {
                            Text(selectedStore.displayName)
                                .font(.headline)
                                .foregroundStyle(ViewerTheme.primaryText)
                        }
                        SessionDescriptionView(lines: session.subtitleLines)
                            .font(.system(size: 12))
                            .foregroundStyle(metadataColor)
                        if let startedAtText = session.startedAtText {
                            Text(startedAtText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(metadataColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    Text(session.selectedStoreStatusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(metadataColor)
                }
                .padding(.top, 12)
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .background(ViewerTheme.sectionBackground)

                Divider()

                HSplitView {
                    storeSidebar
                        .frame(
                            minWidth: 220,
                            idealWidth: 250,
                            maxWidth: 320,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )

                    traceViewerStore.contentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }

        private var storeSidebar: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stores")
                        .font(.headline)
                    Text(
                        session.storeTraces.count == 1
                            ? "1 traced store"
                            : "\(session.storeTraces.count) traced stores"
                    )
                    .font(.caption)
                    .foregroundStyle(ViewerTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ViewerTheme.sectionBackground)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.storeTraces) { storeTrace in
                            StoreTraceRow(
                                storeTrace: storeTrace,
                                summaryText: session.storeSummaryText(for: storeTrace),
                                isSelected: storeTrace.id == session.selectedStore?.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectStore(storeTrace.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(ViewerTheme.timelinePanelBackground)
            }
        }
    }

    struct StoreTraceRow: View {
        let storeTrace: TraceSession.StoreTrace
        let summaryText: String
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

                Text(summaryText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ViewerTheme.secondaryText)
                .lineLimit(1)
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
}
