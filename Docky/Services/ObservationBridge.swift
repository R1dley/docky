//
//  ObservationBridge.swift
//  Docky
//
//  Bridge between the `Observation` framework's
//  `withObservationTracking` and Combine's `AnyCancellable` /
//  `Set<AnyCancellable>` lifecycle pattern. Lets the existing
//  `cancellables.store(in:)` ergonomics continue to work after
//  services migrate from `ObservableObject + @Published` to
//  `@Observable`.
//
//  Behavior: `observe(_:)` runs `action` once (registering reads of
//  any `@Observable` properties accessed inside it), then re-runs it
//  whenever any of those tracked properties changes — coalesced and
//  hopped to the main actor. The returned `AnyCancellable` stops
//  re-running on cancel/deallocate.
//
//  Caveats vs. the Combine `.sink` pattern this replaces:
//    • `onChange` from `withObservationTracking` only fires once per
//      observation-window. We re-install on each change, so we don't
//      miss subsequent updates, but each fire is "any of the tracked
//      reads changed" without telling us which one.
//    • Equality dedupe is NOT free (Combine's `removeDuplicates()`
//      had to be opted in). Property setters that short-circuit on
//      equal values inside `didSet` still avoid emitting; the
//      Observation framework fires unconditionally otherwise.
//

import Combine
import Foundation
import Observation

@discardableResult
@MainActor
func observeChanges(
    _ action: @escaping @MainActor () -> Void
) -> AnyCancellable {
    let state = ObserveBridgeState()

    func install() {
        guard !state.isCancelled else { return }
        withObservationTracking {
            action()
        } onChange: {
            // `onChange` is called from the mutating thread, before
            // the new value is installed. Re-install on the next
            // main-actor tick so reads inside `action()` see the
            // mutation result.
            Task { @MainActor in
                guard !state.isCancelled else { return }
                install()
            }
        }
    }

    install()
    return AnyCancellable { state.isCancelled = true }
}

private final class ObserveBridgeState: @unchecked Sendable {
    var isCancelled = false
}
