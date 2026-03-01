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
    static let rowStroke = rgb(223, 227, 231)
    static let rowTopHighlight = Color.white
    static let rowLiftShadow = Color.black.opacity(0.035)
    static let badgeBackground = rgb(237, 240, 243)
    static let overviewStroke = rgb(223, 227, 231)
    static let overviewGuide = rgb(208, 222, 241)
    static let overviewSelection = rgb(96, 151, 228)
    static let overviewSelectionRing = rgb(154, 189, 235)
    static let overviewSelectionDot = Color.white
    static let sectionBackground = Color.white
    static let sectionStroke = rgb(223, 227, 231)
    static let metricRowBackground = rgb(247, 248, 250)
    static let valueChangedBackground = rgb(242, 245, 250)
    static let valueChangedAccent = rgb(105, 119, 148)

    static let stateFamily = SemanticFamily(
        base: rgb(94, 104, 128),
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
    static let actionFamily = SemanticFamily(
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

    static let action = actionFamily.base
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

    static func color(for kind: TraceViewer.EventKind) -> Color {
        switch kind {
        case .state:
            return state
        case .action:
            return action
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
        case .action:
            return action
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

    static func graphColor(for kind: TraceViewer.EventColorKind) -> Color {
        switch kind {
        case .state:
            return stateFamily.graph
        case .action:
            return actionFamily.graph
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
            return rgb(236, 240, 247)
        case .action:
            return rgb(232, 242, 243)
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

    static func chipStroke(for kind: TraceViewer.EventColorKind) -> Color {
        switch kind {
        case .state:
            return rgb(202, 210, 224)
        case .action:
            return rgb(192, 216, 217)
        case .mutation:
            return rgb(193, 215, 195)
        case .effect:
            return rgb(227, 208, 183)
        case .batch:
            return rgb(212, 193, 206)
        case .publish:
            return rgb(190, 220, 214)
        case .cancel:
            return rgb(208, 213, 220)
        }
    }

}

struct ViewerListCardModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? ViewerTheme.rowSelectedFill : ViewerTheme.rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? ViewerTheme.rowSelectedStroke : ViewerTheme.rowStroke, lineWidth: 1)
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

extension View {
    func viewerListCardStyle(selected: Bool = false) -> some View {
        modifier(ViewerListCardModifier(isSelected: selected))
    }
}
