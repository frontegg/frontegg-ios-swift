//
//  RefreshGate.swift
//  FronteggSwift
//
//  Serializes token-refresh entry so only one refresh runs at a time.
//  Replaces the previous non-atomic `refreshingToken` check-then-set
//  (setRefreshingToken dispatches async to main), which let two concurrent
//  refreshes both pass the guard and issue duplicate rotating-refresh-token
//  requests — the loser 401'd and cleared credentials, a spurious logout
//  of a valid session (FR-25927).
//

import Foundation

actor RefreshGate {
    private var inProgress = false

    /// Atomically claims the refresh slot. Returns true if the caller may
    /// proceed with a refresh; false if one is already in progress.
    func tryBegin() -> Bool {
        if inProgress {
            return false
        }
        inProgress = true
        return true
    }

    /// Releases the slot so a subsequent refresh may begin.
    func end() {
        inProgress = false
    }
}
