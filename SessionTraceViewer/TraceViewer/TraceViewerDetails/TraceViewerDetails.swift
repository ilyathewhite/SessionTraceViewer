//
//  TraceViewerDetails.swift
//  SessionTraceViewer
//
//  Created by Codex on 3/10/26.
//

import Foundation
import ReducerArchitecture

enum TraceViewerDetails: StoreNamespace {
    typealias PublishedValue = Void
    typealias StoreEnvironment = Never
    typealias EffectAction = Never

    enum MutatingAction {
        case updateSelection(EventInspector.Selection)
    }

    struct StoreState {
        var selection: EventInspector.Selection
    }
}

extension TraceViewerDetails {
    @MainActor
    static func store(selection: EventInspector.Selection) -> Store {
        Store(.init(selection: selection), env: nil)
    }

    @MainActor
    static func reduce(_ state: inout StoreState, _ action: MutatingAction) -> Store.SyncEffect {
        switch action {
        case .updateSelection(let selection):
            guard state.selection != selection else { return .none }
            state.selection = selection
            return .none
        }
    }
}
