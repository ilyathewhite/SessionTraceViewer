//
//  EventInspectorFormatting.swift
//  SessionTraceViewer
//
//  Created by Ilya Belenkiy on 2/25/26.
//

import Foundation
import ReducerArchitecture

enum EventInspectorFormatter {
    struct ValueChange: Equatable {
        let oldValue: String
        let newValue: String
    }

    struct ValueRow: Identifiable, Equatable {
        let id: String
        let property: String
        let value: String
        let isChanged: Bool
        let change: ValueChange?
        let isExpandable: Bool
        let isExpandedByDefault: Bool
    }

    private static let missingValuePlaceholder = "<missing>"

    static func effectSubtitle(_ effect: SessionGraph.EffectNode) -> String {
        var parts: [String] = [effect.kind.rawValue]
        if effect.lifecycle == .cancelled {
            parts.append(effect.lifecycle.rawValue)
        }
        if effect.isAsynchronous {
            parts.append("async")
        }
        if effect.isLongLived {
            parts.append("long-lived")
        }
        if let key = effect.cancellationKey {
            parts.append("key=\(key)")
        }
        return parts.joined(separator: " • ")
    }

    static func timestamp(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
                .secondFraction(.fractional(3))
        )
    }

    static func keyValues(for item: TraceViewer.TimelineItem) -> [(String, String)] {
        switch item.node {
        case .state(let state):
            return [
                ("captured", timestamp(state.capturedAt))
            ]

        case .action(let action):
            return [
                ("action", formattedAction(action.action)),
                ("call site", callSiteLabel(action.callSite)),
                ("nested level", String(action.nestedLevel)),
                ("received", timestamp(action.receivedAt)),
                ("completed", timestamp(action.completedAt))
            ]

        case .mutation(let mutation):
            return [
                ("action", mutation.actionID.rawValue),
                ("nested level", String(mutation.nestedLevel)),
                ("diffCount", String(mutation.propertyDiff.count)),
                ("applied", timestamp(mutation.appliedAt))
            ]

        case .effect(let effect):
            var rows: [(String, String)] = [
                ("kind", effect.kind.rawValue),
                ("async", effect.isAsynchronous ? "true" : "false"),
                ("longLived", effect.isLongLived ? "true" : "false"),
                ("nested level", String(effect.nestedLevel)),
                ("startedBy", effect.startedByActionID?.rawValue ?? "-"),
                ("cancellation", effect.cancellationKey ?? "-"),
                ("emitted", String(effect.emittedActionCount))
            ]
            if effect.lifecycle == .cancelled {
                rows.insert(("lifecycle", effect.lifecycle.rawValue), at: 1)
            }
            return rows

        case .batch(let batch):
            return [
                ("kind", batch.kind.rawValue),
                ("count", String(batch.actionCount)),
                ("nested level", String(batch.nestedLevel))
            ]
        }
    }

    static func valueRows(
        for item: TraceViewer.TimelineItem,
        previousStateItem: TraceViewer.TimelineItem?
    ) -> [ValueRow]? {
        guard case .state(let state) = item.node else {
            return nil
        }

        let previousValuesByProperty: [String: String]? = {
            guard let previousStateItem,
                  case .state(let previousState) = previousStateItem.node else {
                return nil
            }
            return Dictionary(
                uniqueKeysWithValues: previousState.state.map { pair in
                    (pair.property, formattedCodeString(pair.value))
                }
            )
        }()

        return state.state.map { pair in
            let formattedValue = formattedCodeString(pair.value)
            let isChanged = previousValuesByProperty.map { valuesByProperty in
                valuesByProperty[pair.property] != formattedValue
            } ?? false
            let change = isChanged ? ValueChange(
                oldValue: previousValuesByProperty?[pair.property] ?? missingValuePlaceholder,
                newValue: formattedValue
            ) : nil

            return .init(
                id: pair.property,
                property: pair.property,
                value: formattedValue,
                isChanged: isChanged,
                change: change,
                isExpandable: isExpandableValue(formattedValue),
                isExpandedByDefault: shouldExpandByDefault(formattedValue)
            )
        }
    }

    static func valueNeedsExpansion(_ value: String) -> Bool {
        isExpandableValue(formattedCodeString(value))
    }

    static func valueExpandsByDefault(_ value: String) -> Bool {
        shouldExpandByDefault(formattedCodeString(value))
    }

    private static func callSiteLabel(_ callSite: SessionGraph.ActionNode.CallSite?) -> String {
        guard let callSite else { return "-" }
        return "\(callSite.file):\(callSite.line)"
    }

    private static func formattedAction(_ action: String) -> String {
        formattedCodeString(action)
    }

    private static func formattedCodeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    private static func isExpandableValue(_ value: String) -> Bool {
        lineCount(of: value) > 1
    }

    private static func shouldExpandByDefault(_ value: String) -> Bool {
        guard isExpandableValue(value) else { return true }
        return lineCount(of: value) < 10
    }

    private static func lineCount(of value: String) -> Int {
        max(value.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
    }
}
