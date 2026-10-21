//
//  TranscriptTail.swift
//  AgentSession
//
//  What changed in a transcript since the last look, by count and a fingerprint of its tail.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Change detection for a polled transcript: which events are new since the previous poll.
///
/// Events carry no stable id, so a change is the count plus a content fingerprint of the last event.
/// An adapter caps what it returns (the latest 300 events), and past that cap the count stops
/// growing: the new events are then everything after the previously-seen tail event, found by its
/// fingerprint at its LAST occurrence so a repetitive run never counts old events again. With no
/// overlap at all only the newest event is new. The FIRST look at a transcript baselines silently: an
/// existing session's history is not fresh activity.
public struct TranscriptTail: Sendable {
    /// What one poll found.
    public enum Change: Equatable, Sendable {
        /// The first look (or the first after ``reset()``): nothing is reported as new.
        case baselined
        /// The tail is as it was.
        case unchanged
        /// These events are new, oldest first.
        case fresh(ArraySlice<TimelineEvent>)
    }

    /// Whether a baseline is held.
    public private(set) var hasBaseline = false
    private var count = 0
    private var signature = ""
    private var tailFingerprint = ""

    /// An empty tail; the first ``observe(_:)`` baselines.
    public init() {}

    /// Compares `events` (the transcript as read now, non-empty) with the previous poll and takes them
    /// as the new baseline.
    public mutating func observe(_ events: [TimelineEvent]) -> Change {
        guard let last = events.last else { return .unchanged }
        let now = "\(events.count)|\(Self.fingerprint(last))"
        guard hasBaseline else { remember(events, signature: now); return .baselined }
        guard now != signature else { return .unchanged }
        let fresh = freshEvents(in: events)
        remember(events, signature: now)
        return .fresh(fresh)
    }

    /// Forgets the baseline (another transcript, or none): the next poll baselines again.
    public mutating func reset() { self = TranscriptTail() }

    /// The events after the previous poll's tail.
    private func freshEvents(in events: [TimelineEvent]) -> ArraySlice<TimelineEvent> {
        if events.count > count { return events[count...] }
        if let seen = events.lastIndex(where: { Self.fingerprint($0) == tailFingerprint }) { return events[(seen + 1)...] }
        return events.suffix(1)
    }

    private mutating func remember(_ events: [TimelineEvent], signature: String) {
        hasBaseline = true
        count = events.count
        self.signature = signature
        tailFingerprint = events.last.map(Self.fingerprint) ?? ""
    }

    /// One event's content, standing in for the id events do not carry.
    static func fingerprint(_ event: TimelineEvent) -> String {
        "\(event.kind)|\(event.title)|\(event.timestamp)|\(event.detail)"
    }
}
