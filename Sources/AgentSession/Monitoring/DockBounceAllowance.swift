//
//  DockBounceAllowance.swift
//  AgentSession
//
//  At most one Dock bounce each time the person is away from the app.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// At most one Dock bounce each time the person is away from the app, however many agents
/// finish or start waiting meanwhile — Terminal's manner, not a bounce per event. The badge says
/// how things stand; the bounce only says "something changed since you left", once.
public struct DockBounceAllowance: Equatable, Sendable {
    /// True once this absence's bounce has been used.
    public private(set) var spent = false

    /// A fresh allowance: the first request may bounce.
    public init() {}

    /// Whether this request may bounce; true at most once until ``renew()``.
    public mutating func take() -> Bool {
        guard !spent else { return false }
        spent = true
        return true
    }

    /// The person came back to the app: the next absence gets its own bounce.
    public mutating func renew() { spent = false }
}
