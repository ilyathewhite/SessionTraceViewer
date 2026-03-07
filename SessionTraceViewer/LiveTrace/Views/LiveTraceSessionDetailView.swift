//
//  LiveTraceSessionDetailView.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/7/26.
//

import ReducerArchitecture
import SwiftUI

extension LiveTrace {
    struct SessionDetailView: View {
        let session: StoreState.Session
        let traceViewerStore: TraceViewer.Store?

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

                    Spacer()

                    Text(session.isEnded ? "Ended" : "Live")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    session.isEnded
                                        ? ViewerTheme.badgeBackground
                                        : ViewerTheme.chipBackground(for: .publish)
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    session.isEnded
                                        ? ViewerTheme.rowStroke
                                        : ViewerTheme.chipStroke(for: .publish),
                                    lineWidth: 1
                                )
                        )
                }
                .padding(.top, 12)
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .background(ViewerTheme.sectionBackground)

                Divider()

                if let traceViewerStore {
                    traceViewerStore.contentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                else {
                    ContentUnavailableView(
                        "Preparing Trace",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("Waiting for the first live trace payload for this session.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ViewerTheme.sectionBackground)
                }
            }
        }
    }
}
