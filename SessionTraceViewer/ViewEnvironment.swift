//
//  ViewEnvironment.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI
import AppKit

enum ViewerTheme {
    private final class ThemeBundleToken: NSObject {}

    private static let bundle = Bundle(for: ThemeBundleToken.self)

    private static func color(_ name: String) -> Color {
        Color("Theme/\(name)", bundle: bundle)
    }

    private static let white = color("Base/White")

    static let background = color("Surfaces/AppBackground")

    static let timelinePanelBackground = color("Surfaces/TimelinePanel")
    static let timelineGraphBackground = white
    static let inspectorPanelBackground = color("Surfaces/InspectorPanel")
    static let traceViewerContentBackground = color("Surfaces/TraceViewerContent")
    static let traceViewerScopeBarBackground = background
    static let traceViewerInsetPanelBackground = traceViewerContentBackground
    static let traceViewerInsetPanelInnerShadow = color("Shadows/InsetPanelInner")
    static let traceViewerInsetPanelInnerShadowSoft = color("Shadows/InsetPanelInnerSoft")
    static let traceViewerScopeCapsuleShadow = color("Shadows/ScopeCapsule")
    static let timelineGuide = color("Lines/TimelineGuide")
    static let solidBranchLine = color("Lines/SolidBranch")
    static let dottedBranchLine = color("Lines/DottedBranch")
    static let nodeStroke = white
    static let timestampText = color("Text/Timestamp")

    static let rowFill = white
    static let rowSelectedFill = color("Rows/SelectedFill")
    static let rowSelectedStroke = color("Rows/SelectedStroke")
    static let rowInactiveSelectedFill = color("Rows/InactiveSelectedFill")
    static let rowInactiveSelectedStroke = color("Rows/InactiveSelectedStroke")
    static let rowStroke = color("Rows/Stroke")
    static let rowTopHighlight = white
    static let rowLiftShadow = color("Shadows/RowLift")
    static let listItemShadow = traceViewerScopeCapsuleShadow
    static let detailCardShadow = traceViewerScopeCapsuleShadow
    static let badgeBackground = color("Surfaces/Badge")
    static let overviewStroke = rowStroke
    static let overviewGuide = color("Overview/Guide")
    static let overviewSelection = color("Overview/Selection")
    static let overviewSelectionRing = color("Overview/SelectionRing")
    static let overviewSelectionDot = white
    static let overviewAreaBackground = color("Surfaces/OverviewArea")
    static let overviewRegionBackground = color("Surfaces/OverviewRegion")
    static let overviewRegionShadow = color("Shadows/OverviewRegion")
    static let overviewRegionSelectedShadow = color("Shadows/OverviewRegionSelected")
    static let sectionBackground = white
    static let sectionStroke = rowStroke
    static let sectionStrokeMuted = color("Lines/SectionStrokeMuted")
    static let metricRowBackground = color("Surfaces/MetricRow")
    static let valueChangedBackground = color("Surfaces/ValueChanged")
    static let valueChangedAccent = color("Text/ValueChangedAccent")
    static let diffOldHighlightBackground = color("Surfaces/DiffOldHighlight")
    static let diffOldRowTint = color("Surfaces/DiffOldRowTint")
    static let diffOldHighlightText = color("Text/DiffOldHighlight")
    static let diffNewHighlightBackground = color("Surfaces/DiffNewHighlight")
    static let diffNewRowTint = color("Surfaces/DiffNewRowTint")
    static let diffNewHighlightText = color("Text/DiffNewHighlight")

    static let flow = color("Semantic/Base/Flow")
    static let state = color("Semantic/Base/State")
    static let mutation = color("Semantic/Base/Mutation")
    static let effect = color("Semantic/Base/Effect")
    static let batch = color("Semantic/Base/Batch")
    static let publish = color("Semantic/Base/Publish")
    static let cancel = color("Semantic/Base/Cancel")

    static let primaryText = color("Text/Primary")
    static let primaryTextMuted = color("Text/PrimaryMuted")
    static let secondaryText = color("Text/Secondary")
    static let tertiaryText = color("Text/Tertiary")
    static let inspectorPropertyText = color("Text/InspectorProperty")
    static let scopeBarAllText = color("ScopeBar/AllText")
    static let scopeBarAllBackground = color("ScopeBar/AllBackground")
    static let scopeBarAllStroke = color("ScopeBar/AllStroke")
    static let scopeBarFlowText = color("ScopeBar/FlowText")
    static let scopeBarFlowBackground = color("ScopeBar/FlowBackground")
    static let scopeBarFlowStroke = color("ScopeBar/FlowStroke")
    static let scopeBarUserText = scopeBarAllText
    static let scopeBarUserBackground = scopeBarAllBackground
    static let scopeBarUserStroke = scopeBarAllStroke
    static let tooltipText = white
    static let tooltipBackground = color("Surfaces/Tooltip")
    static let tooltipShadow = color("Shadows/Tooltip")

    static func color(for kind: TraceViewer.EventKind) -> Color {
        switch kind {
        case .state:
            return state
        case .flow:
            return flow
        case .mutation:
            return mutation
        case .effect:
            return effect
        case .batch:
            return batch
        }
    }

    static func color(for kind: TraceViewer.EventColorKind) -> Color {
        switch kind {
        case .state:
            return state
        case .mutation:
            return mutation
        case .effect:
            return effect
        case .batch:
            return batch
        case .publish:
            return publish
        case .cancel:
            return cancel
        }
    }

    static func chipText(for kind: TraceViewer.EventColorKind) -> Color {
        switch kind {
        case .state:
            return color("Semantic/Chip/Text/State")
        case .mutation:
            return color("Semantic/Chip/Text/Mutation")
        case .effect:
            return color("Semantic/Chip/Text/Effect")
        case .batch:
            return color("Semantic/Chip/Text/Batch")
        case .publish:
            return color("Semantic/Chip/Text/Publish")
        case .cancel:
            return color("Semantic/Chip/Text/Cancel")
        }
    }

    static func chipText(for kind: TraceViewer.EventKind) -> Color {
        switch kind {
        case .state:
            return chipText(for: TraceViewer.EventColorKind.state)
        case .flow:
            return scopeBarFlowText
        case .mutation:
            return chipText(for: TraceViewer.EventColorKind.mutation)
        case .effect:
            return chipText(for: TraceViewer.EventColorKind.effect)
        case .batch:
            return chipText(for: TraceViewer.EventColorKind.batch)
        }
    }

    static func graphColor(for kind: TraceViewer.EventColorKind) -> Color {
        switch kind {
        case .state:
            return color("Semantic/Graph/State")
        case .mutation:
            return color("Semantic/Graph/Mutation")
        case .effect:
            return color("Semantic/Graph/Effect")
        case .batch:
            return color("Semantic/Graph/Batch")
        case .publish:
            return color("Semantic/Graph/Publish")
        case .cancel:
            return color("Semantic/Graph/Cancel")
        }
    }

    static func chipBackground(for kind: TraceViewer.EventColorKind) -> Color {
        switch kind {
        case .state:
            return color("Semantic/Chip/Background/State")
        case .mutation:
            return color("Semantic/Chip/Background/Mutation")
        case .effect:
            return color("Semantic/Chip/Background/Effect")
        case .batch:
            return color("Semantic/Chip/Background/Batch")
        case .publish:
            return color("Semantic/Chip/Background/Publish")
        case .cancel:
            return color("Semantic/Chip/Background/Cancel")
        }
    }

    static func chipBackground(for kind: TraceViewer.EventKind) -> Color {
        switch kind {
        case .state:
            return chipBackground(for: TraceViewer.EventColorKind.state)
        case .flow:
            return scopeBarFlowBackground
        case .mutation:
            return chipBackground(for: TraceViewer.EventColorKind.mutation)
        case .effect:
            return chipBackground(for: TraceViewer.EventColorKind.effect)
        case .batch:
            return chipBackground(for: TraceViewer.EventColorKind.batch)
        }
    }

    static func chipStroke(for kind: TraceViewer.EventColorKind) -> Color {
        switch kind {
        case .state:
            return color("Semantic/Chip/Stroke/State")
        case .mutation:
            return color("Semantic/Chip/Stroke/Mutation")
        case .effect:
            return color("Semantic/Chip/Stroke/Effect")
        case .batch:
            return color("Semantic/Chip/Stroke/Batch")
        case .publish:
            return color("Semantic/Chip/Stroke/Publish")
        case .cancel:
            return color("Semantic/Chip/Stroke/Cancel")
        }
    }

    static func chipStroke(for kind: TraceViewer.EventKind) -> Color {
        switch kind {
        case .state:
            return chipStroke(for: TraceViewer.EventColorKind.state)
        case .flow:
            return scopeBarFlowStroke
        case .mutation:
            return chipStroke(for: TraceViewer.EventColorKind.mutation)
        case .effect:
            return chipStroke(for: TraceViewer.EventColorKind.effect)
        case .batch:
            return chipStroke(for: TraceViewer.EventColorKind.batch)
        }
    }

}

struct ViewerListCardModifier: ViewModifier {
    let isSelected: Bool
    let isFocused: Bool

    private var fillColor: Color {
        guard isSelected else { return ViewerTheme.rowFill }
        return isFocused ? ViewerTheme.rowSelectedFill : ViewerTheme.rowInactiveSelectedFill
    }

    private var strokeColor: Color {
        guard isSelected else { return ViewerTheme.rowStroke }
        return isFocused ? ViewerTheme.rowSelectedStroke : ViewerTheme.rowInactiveSelectedStroke
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Color.clear : ViewerTheme.rowTopHighlight, lineWidth: 1)
                    .padding(1)
            )
            .shadow(
                color: ViewerTheme.listItemShadow,
                radius: isSelected ? 3 : 1.4,
                x: 0,
                y: 1
            )
    }
}

struct ViewerPanelCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ViewerTheme.sectionBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ViewerTheme.rowStroke, lineWidth: 1)
            )
            .shadow(
                color: ViewerTheme.rowLiftShadow,
                radius: 1.4,
                x: 0,
                y: 1
            )
    }
}

struct ViewerInsetPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Rectangle()
                    .fill(ViewerTheme.traceViewerInsetPanelBackground)
            )
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        ViewerTheme.traceViewerInsetPanelInnerShadow,
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 3)
            }
            .overlay(alignment: .leading) {
                LinearGradient(
                    colors: [
                        ViewerTheme.traceViewerInsetPanelInnerShadowSoft,
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 3)
            }
    }
}

extension View {
    func viewerListCardStyle(selected: Bool = false, isFocused: Bool = true) -> some View {
        modifier(ViewerListCardModifier(isSelected: selected, isFocused: isFocused))
    }

    func viewerPanelCardStyle() -> some View {
        modifier(ViewerPanelCardModifier())
    }

    func viewerInsetPanelStyle() -> some View {
        modifier(ViewerInsetPanelModifier())
    }
}
