//
//  LookupMisses.swift
//  AgentSession
//
//  Remembers, briefly, that a lookup found nothing, so idle polling does not repeat it.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Remembers, briefly, that a lookup found nothing, so idle polling does not repeat it. A host
/// polls several candidate folders from several timers; with no session anywhere, each tick
/// would list the same directories again. A miss answers nil for ``interval`` without looking;
/// a hit is never remembered, and clears the miss, so a session that appears is seen on the
/// first look after the interval.
final class LookupMisses: @unchecked Sendable {
    /// How long a miss is believed.
    static let interval: TimeInterval = 2

    private let lock = NSLock()
    private var missedAt: [String: Date] = [:]

    /// `lookup`'s answer for `key`, or nil without calling it while a recent miss stands.
    func remembering<T>(_ key: String, now: Date = Date(), _ lookup: () -> T?) -> T? {
        if isFresh(key, now: now) { return nil }
        let value = lookup()
        lock.lock(); defer { lock.unlock() }
        missedAt[key] = value == nil ? now : nil
        return value
    }

    /// Whether a miss recorded for `key` is still believed at `now`.
    func isFresh(_ key: String, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let at = missedAt[key] else { return false }
        return now.timeIntervalSince(at) < Self.interval
    }
}
