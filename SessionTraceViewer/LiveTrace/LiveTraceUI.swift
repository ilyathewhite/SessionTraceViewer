//
//  LiveTraceUI.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 3/3/26.
//

import SwiftUI
import AppKit
import ReducerArchitecture

struct LiveTraceWindowView: View {
    @EnvironmentObject private var liveTraceStore: LiveTraceStore
    @FocusState private var sidebarHasFocus: Bool
    @Environment(\.controlActiveState) private var controlActiveState

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

            sidebarSessions
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

    private var sidebarSessions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(liveTraceStore.sessions) { session in
                        LiveTraceSessionRow(
                            session: session,
                            isSelected: session.id == liveTraceStore.selectedSessionID,
                            selectionIsFocused: sidebarSelectionIsFocused
                        )
                        .id(session.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            liveTraceStore.selectedSessionID = session.id
                            sidebarHasFocus = true
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(ViewerTheme.timelinePanelBackground)
            .focusable()
            .focusEffectDisabled()
            .focused($sidebarHasFocus)
            .onAppear {
                scrollToSelected(using: proxy, animated: false)
            }
            .onChange(of: liveTraceStore.selectedSessionID) { _, _ in
                scrollToSelected(using: proxy)
            }
            .onMoveCommand(perform: handleSidebarMove)
        }
    }

    private var sidebarSelectionIsFocused: Bool {
        sidebarHasFocus && controlActiveState == .key
    }

    private func scrollToSelected(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard let selectedSessionID = liveTraceStore.selectedSessionID else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(selectedSessionID, anchor: .center)
            }
        }
        else {
            proxy.scrollTo(selectedSessionID, anchor: .center)
        }
    }

    private func handleSidebarMove(_ direction: MoveCommandDirection) {
        guard sidebarHasFocus else { return }
        switch direction {
        case .up:
            selectRelativeSession(offset: -1)
        case .down:
            selectRelativeSession(offset: 1)
        default:
            break
        }
    }

    private func selectRelativeSession(offset: Int) {
        guard !liveTraceStore.sessions.isEmpty else { return }
        guard let selectedSessionID = liveTraceStore.selectedSessionID,
              let currentIndex = liveTraceStore.sessions.firstIndex(where: { $0.id == selectedSessionID }) else {
            liveTraceStore.selectedSessionID = liveTraceStore.sessions.first?.id
            return
        }

        let nextIndex = min(
            max(currentIndex + offset, 0),
            liveTraceStore.sessions.count - 1
        )
        liveTraceStore.selectedSessionID = liveTraceStore.sessions[nextIndex].id
    }

}

private struct LiveTraceSessionRow: View {
    @ObservedObject var session: LiveTraceSessionViewModel
    let isSelected: Bool
    let selectionIsFocused: Bool
    
    private var metadataColor: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    private var selectionBackgroundColor: Color {
        guard isSelected else { return .clear }
        return selectionIsFocused ? ViewerTheme.rowSelectedFill : ViewerTheme.rowInactiveSelectedFill
    }

    private var selectionStrokeColor: Color {
        guard isSelected else { return .clear }
        return selectionIsFocused ? ViewerTheme.rowSelectedStroke : ViewerTheme.rowInactiveSelectedStroke
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isEnded ? ViewerTheme.cancel : ViewerTheme.publish)
                    .frame(width: 8, height: 8)
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(ViewerTheme.primaryText)
                    .lineLimit(1)
            }

            LiveTraceSessionDescriptionView(lines: session.subtitleLines)
                .font(.system(size: 12))
                .foregroundStyle(metadataColor)

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(metadataColor)
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

    private var statusText: String {
        if session.isEnded {
            return "Ended \(session.lastUpdatedAt.formatted(date: .omitted, time: .standard))"
        }
        return "Updated \(session.lastUpdatedAt.formatted(date: .omitted, time: .standard))"
    }
}

private struct LiveTraceSessionDetailView: View {
    @ObservedObject var session: LiveTraceSessionViewModel
    private let metadataColor = ViewerTheme.timestampText

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.title3.weight(.semibold))
                    LiveTraceSessionDescriptionView(lines: session.subtitleLines)
                        .font(.system(size: 12))
                        .foregroundStyle(metadataColor)
                    if let startedAt = session.startedAt {
                        Text("Started \(startedAt.formatted(date: .abbreviated, time: .standard))")
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
                            .fill(session.isEnded ? ViewerTheme.badgeBackground : ViewerTheme.chipBackground(for: .publish))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(session.isEnded ? ViewerTheme.rowStroke : ViewerTheme.chipStroke(for: .publish), lineWidth: 1)
                    )
            }
            .padding(.top, 12)
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
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
