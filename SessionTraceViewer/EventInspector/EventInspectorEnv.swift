import ReducerArchitecture

extension EventInspector {
    @MainActor
    static func syncInlineDiff(store: Store) -> @MainActor (StringDiff.Input?) -> Void {
        { [weak store] input in
            guard let store else { return }
            syncInlineDiff(store: store, input: input)
        }
    }

    @MainActor
    static func syncInlineDiff(store: Store, input: StringDiff.Input?) {
        let existingStore: StringDiff.Store? = store.child()
        store.removeChild(existingStore, delay: false)

        guard let input else { return }
        store.addChild(StringDiff.inlineStore(input: input))
    }
}
