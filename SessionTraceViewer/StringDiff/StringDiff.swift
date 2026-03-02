//
//  StringDiff.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/2/26.
//

import Foundation
import SwiftUI

import ReducerArchitecture

enum StringDiff: StoreNamespace {
    static let windowID = "string-diff-window"

    typealias PublishedValue = Void

    typealias StoreEnvironment = Never
    typealias EffectAction = Never
    typealias MutatingAction = Void

    enum PresentationStyle {
        case standard
        case inlineEmbedded
    }

    struct WindowRequest: Hashable, Codable {
        let title: String
        let string1Caption: String
        let string1: String
        let string2Caption: String
        let string2: String
    }

    struct StoreState {
        private enum DiffSide {
            case old
            case new

            var highlightBackground: Color {
                switch self {
                case .old:
                    ViewerTheme.diffOldHighlightBackground
                case .new:
                    ViewerTheme.diffNewHighlightBackground
                }
            }

            var highlightText: Color {
                switch self {
                case .old:
                    ViewerTheme.diffOldHighlightText
                case .new:
                    ViewerTheme.diffNewHighlightText
                }
            }
        }

        let title: String
        let presentationStyle: PresentationStyle
        let string1Caption: String
        let string1: AttributedString
        let string2Caption: String
        let string2: AttributedString

        private static func diffAttributedString(
            for string: String,
            comparedTo otherString: String,
            side: DiffSide
        ) -> AttributedString {
            var attributedString = AttributedString(string)
            if attributedString.startIndex != attributedString.endIndex {
                let fullRange = attributedString.startIndex..<attributedString.endIndex
                attributedString[fullRange].foregroundColor = ViewerTheme.primaryText
            }

            let diffFromOther = otherString.difference(from: string)
            for removal in diffFromOther.removals {
                guard case .remove(offset: let offset, element: _, associatedWith: _) = removal else {
                    assertionFailure()
                    continue
                }

                let index = attributedString.index(
                    attributedString.startIndex,
                    offsetByCharacters: offset
                )
                attributedString[index...index].backgroundColor = side.highlightBackground
                attributedString[index...index].foregroundColor = side.highlightText
            }
            return attributedString
        }

        init(
            title: String,
            presentationStyle: PresentationStyle,
            string1Caption: String,
            string1: String,
            string2Caption: String,
            string2: String
        ) {
            self.title = title
            self.presentationStyle = presentationStyle
            self.string1Caption = string1Caption
            self.string2Caption = string2Caption

            self.string1 = Self.diffAttributedString(for: string1, comparedTo: string2, side: .old)
            self.string2 = Self.diffAttributedString(for: string2, comparedTo: string1, side: .new)
        }
    }
}

extension StringDiff {
    @MainActor
    static func store(
        title: String,
        presentationStyle: PresentationStyle = .standard,
        string1Caption: String,
        string1: String,
        string2Caption: String,
        string2: String
    ) -> Store {
        Store(
            .init(
                title: title,
                presentationStyle: presentationStyle,
                string1Caption: string1Caption,
                string1: string1,
                string2Caption: string2Caption,
                string2: string2
            ),
            env: nil
        )
    }

    @MainActor
    static func store(windowRequest: WindowRequest) -> Store {
        store(
            title: windowRequest.title,
            presentationStyle: .standard,
            string1Caption: windowRequest.string1Caption,
            string1: windowRequest.string1,
            string2Caption: windowRequest.string2Caption,
            string2: windowRequest.string2
        )
    }
}
