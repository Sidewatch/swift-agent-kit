//
//  DockBadgeVotes.swift
//  AgentSession
//
//  One Dock badge for an app whose windows each watch their own agent.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One Dock badge for an app whose windows each watch their own agent: each window votes for the
/// badge it wants (or none), and the tile shows the most urgent vote — a question (`?`) outranks
/// a wait (`●`) — clearing only when no window wants one. Without this, one window clearing its
/// badge would clear another's.
public struct DockBadgeVotes: Equatable, Sendable {
    /// The badge an agent with a question asks for.
    public static let question = "?"
    /// The badge an agent waiting on the person asks for.
    public static let waiting = "●"

    private var votes: [String: String] = [:]

    /// No votes: no badge.
    public init() {}

    /// The badge the tile shows: a question if any window asks one, else any other vote, else none.
    public var label: String? {
        if votes.values.contains(Self.question) { return Self.question }
        return votes.values.contains(Self.waiting) ? Self.waiting : votes.values.min()
    }

    /// Records `voter`'s badge (nil withdraws its vote) and returns the badge the tile now shows.
    @discardableResult
    public mutating func set(_ badge: String?, for voter: String) -> String? {
        votes[voter] = badge
        return label
    }
}
