//
//  LiveTraceUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 3/3/26.
//

import SwiftUI
import ReducerArchitecture

struct LiveTraceWindowView: View {
    @EnvironmentObject private var liveTraceStore: LiveTraceStore

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 1320, minHeight: 900)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Traces")
                    .font(.headline)
                Text(liveTraceStore.serverStatus.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(ViewerTheme.sectionBackground)

            Divider()

            List(selection: $liveTraceStore.selectedSessionID) {
                ForEach(liveTraceStore.sessions) { session in
                    LiveTraceSessionRow(session: session)
                        .tag(session.id)
                }
            }
            .listStyle(.sidebar)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    @ViewBuilder
    private var detail: some View {
        if let session = liveTraceStore.selectedSession {
            LiveTraceSessionDetailView(session: session)
        }
        else {
            ContentUnavailableView(
                "Waiting For Live Trace",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Enable `store.logConfig.liveTrace` in the traced app and keep SessionTraceViewer open.")
            )
        }
    }
}

private struct LiveTraceSessionRow: View {
    @ObservedObject var session: LiveTraceSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isEnded ? ViewerTheme.cancel : ViewerTheme.publish)
                    .frame(width: 8, height: 8)
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
            }

            LiveTraceSessionDescriptionView(lines: session.subtitleLines)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        if session.isEnded {
            return "Ended \(session.lastUpdatedAt.formatted(date: .omitted, time: .standard))"
        }
        return "Updated \(session.lastUpdatedAt.formatted(date: .omitted, time: .standard))"
    }
}

private struct LiveTraceSessionDetailView: View {
    @ObservedObject var session: LiveTraceSessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.title3.weight(.semibold))
                    LiveTraceSessionDescriptionView(lines: session.subtitleLines)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let startedAt = session.startedAt {
                        Text("Started \(startedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
                            .fill(session.isEnded ? ViewerTheme.badgeBackground : ViewerTheme.chipBackground(for: .publish))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(session.isEnded ? ViewerTheme.rowStroke : ViewerTheme.chipStroke(for: .publish), lineWidth: 1)
                    )
            }
            .padding(12)
            .background(ViewerTheme.sectionBackground)

            Divider()

            TraceViewer.ContentView(session.traceViewerStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LiveTraceSessionDescriptionView: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
