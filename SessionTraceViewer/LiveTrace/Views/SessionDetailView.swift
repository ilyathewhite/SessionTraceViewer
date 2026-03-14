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
        let saveSession: () -> Void

        private let metadataColor = ViewerTheme.timestampText

        var body: some View {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.title3.weight(.semibold))
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

                    VStack(alignment: .trailing, spacing: 8) {
                        Button(action: saveSession) {
                            Label("Save Session", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Text(session.statusText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(metadataColor)
                    }
                }
                .padding(.top, 12)
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .background(ViewerTheme.sectionBackground)

                Divider()

                traceViewerStore.contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
