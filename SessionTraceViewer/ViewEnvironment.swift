//
//  ViewEnvironment.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import SwiftUI
import AppKit

enum ViewerTheme {
    struct SemanticFamily {
        let base: Color
        let graph: Color
    }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255)
    }

    static let background = rgb(246, 247, 249)

    static let timelinePanelBackground = rgb(244, 246, 248)
    static let timelineGraphBackground = Color.white
    static let inspectorPanelBackground = rgb(240, 242, 245)
    static let timelineGuide = rgb(235, 238, 241)
    static let solidBranchLine = rgb(154, 159, 165)
    static let dottedBranchLine = rgb(122, 127, 133)
    static let nodeStroke = Color.white
    static let timestampText = rgb(122, 128, 135)

    static let rowFill = Color.white
    static let rowSelectedFill = rgb(225, 236, 251)
    static let rowSelectedStroke = rgb(171, 197, 236)
    static let rowInactiveSelectedFill = rgb(234, 238, 242)
    static let rowInactiveSelectedStroke = rgb(208, 215, 223)
    static let rowStroke = rgb(223, 227, 231)
    static let rowTopHighlight = Color.white
    static let rowLiftShadow = Color.black.opacity(0.035)
    static let badgeBackground = rgb(237, 240, 243)
    static let overviewStroke = rgb(223, 227, 231)
    static let overviewGuide = rgb(208, 222, 241)
    static let overviewSelection = rgb(96, 151, 228)
    static let overviewSelectionRing = rgb(154, 189, 235)
    static let overviewSelectionDot = Color.white
    static let overviewAreaBackground = rgb(232, 236, 241)
    static let sectionBackground = Color.white
    static let sectionStroke = rgb(223, 227, 231)
    static let metricRowBackground = rgb(247, 248, 250)
    static let valueChangedBackground = rgb(242, 245, 250)
    static let valueChangedAccent = rgb(105, 119, 148)
    static let diffOldHighlightBackground = rgb(255, 235, 233)
    static let diffOldHighlightText = rgb(207, 34, 46)
    static let diffNewHighlightBackground = rgb(218, 251, 225)
    static let diffNewHighlightText = rgb(26, 127, 55)

    static let stateFamily = SemanticFamily(
        base: rgb(118, 125, 42),
        graph: rgb(122, 134, 164)
    )
    static let mutationFamily = SemanticFamily(
        base: rgb(80, 128, 87),
        graph: rgb(108, 156, 104)
    )
    static let effectFamily = SemanticFamily(
        base: rgb(178, 126, 56),
        graph: rgb(208, 150, 76)
    )
    static let flowFamily = SemanticFamily(
        base: rgb(69, 127, 130),
        graph: rgb(90, 150, 154)
    )
    static let batchFamily = SemanticFamily(
        base: rgb(136, 98, 124),
        graph: rgb(164, 122, 150)
    )
    static let publishFamily = SemanticFamily(
        base: rgb(52, 140, 128),
        graph: rgb(72, 166, 148)
    )
    static let cancelFamily = SemanticFamily(
        base: rgb(126, 132, 142),
        graph: rgb(150, 156, 168)
    )

    static let flow = flowFamily.base
    static let state = stateFamily.base
    static let mutation = mutationFamily.base
    static let effect = effectFamily.base
    static let batch = batchFamily.base
    static let publish = publishFamily.base
    static let cancel = cancelFamily.base

    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let inspectorPropertyText = rgb(112, 118, 126)
    static let scopeBarAllText = rgb(70, 76, 84)
    static let scopeBarAllBackground = rgb(230, 234, 238)
    static let scopeBarAllStroke = rgb(184, 191, 198)
    static let scopeBarFlowText = rgb(22, 74, 96)
    static let scopeBarFlowBackground = rgb(224, 238, 244)
    static let scopeBarFlowStroke = rgb(167, 192, 204)
    static let scopeBarUserText = rgb(70, 76, 84)
    static let scopeBarUserBackground = rgb(230, 234, 238)
    static let scopeBarUserStroke = rgb(184, 191, 198)

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
            return rgb(82, 89, 24)
        case .mutation:
            return rgb(31, 76, 40)
        case .effect:
            return rgb(104, 68, 20)
        case .batch:
            return rgb(78, 52, 75)
        case .publish:
            return rgb(18, 79, 70)
        case .cancel:
            return rgb(68, 74, 84)
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
            return stateFamily.graph
        case .mutation:
            return mutationFamily.graph
        case .effect:
            return effectFamily.graph
        case .batch:
            return batchFamily.graph
        case .publish:
            return publishFamily.graph
        case .cancel:
            return cancelFamily.graph
        }
    }

    static func chipBackground(for kind: TraceViewer.EventColorKind) -> Color {
        switch kind {
        case .state:
            return rgb(242, 245, 220)
        case .mutation:
            return rgb(232, 241, 233)
        case .effect:
            return rgb(246, 238, 227)
        case .batch:
            return rgb(240, 233, 238)
        case .publish:
            return rgb(230, 243, 240)
        case .cancel:
            return rgb(236, 238, 241)
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
            return rgb(194, 200, 142)
        case .mutation:
            return rgb(176, 196, 180)
        case .effect:
            return rgb(208, 190, 164)
        case .batch:
            return rgb(192, 178, 188)
        case .publish:
            return rgb(170, 198, 191)
        case .cancel:
            return rgb(188, 191, 197)
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
                color: ViewerTheme.rowLiftShadow,
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

extension View {
    func viewerListCardStyle(selected: Bool = false, isFocused: Bool = true) -> some View {
        modifier(ViewerListCardModifier(isSelected: selected, isFocused: isFocused))
    }

    func viewerPanelCardStyle() -> some View {
        modifier(ViewerPanelCardModifier())
    }
}
