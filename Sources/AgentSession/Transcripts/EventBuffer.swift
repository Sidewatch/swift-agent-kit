//
//  EventBuffer.swift
//  AgentSession
//
//  The bounded activity timeline every transcript parser appends to.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The bounded activity timeline every transcript parser appends to: the newest ``cap`` events,
/// the newest ``fullResultCount`` of them keeping their tool output whole and older ones only its
/// end, where a test run's or build's summary sits — so memory stays near what 300 whole events
/// cost however long the session runs.
struct EventBuffer {
    /// How many of the most recent events are kept: enough for a long session's last several
    /// prompts (one busy prompt can run hundreds of tool calls).
    static let cap = 2_000
    /// How many of the newest events keep their tool output whole.
    static let fullResultCount = 300
    /// How much of an older event's output is kept (its end).
    static let olderResultCap = 400

    /// The events, oldest first.
    private(set) var events: [TimelineEvent] = []

    /// Appends `event`, trimming the output of the one that just aged past ``fullResultCount``
    /// and dropping the oldest beyond ``cap``.
    mutating func append(_ event: TimelineEvent) {
        events.append(event)
        let aging = events.count - Self.fullResultCount - 1
        if aging >= 0, let result = events[aging].result, result.count > Self.olderResultCap {
            events[aging].result = "…" + String(result.suffix(Self.olderResultCap))
        }
        if events.count > Self.cap { events.removeFirst(events.count - Self.cap) }
    }

    /// Attaches a tool's output to the call it answers (the latest event with that id), keeping
    /// the end of an output longer than ``TimelineEvent/resultCap``. An unknown id is ignored.
    mutating func attachResult(toolUseID id: String, text: String, isError: Bool) {
        guard let index = events.lastIndex(where: { $0.toolUseID == id }) else { return }
        let resolved = PersistedOutput.resolved(text, cap: TimelineEvent.resultCap)
        events[index].result = resolved.count > TimelineEvent.resultCap ? "…" + String(resolved.suffix(TimelineEvent.resultCap)) : resolved
        events[index].resultIsError = isError
    }

    /// Bills a model call to the latest event that carries no bill yet — for a format that
    /// reports usage after the call rather than on it.
    mutating func billLatest(_ usage: TimelineEvent.Usage, model: String?) {
        guard let index = events.lastIndex(where: { $0.usage == nil }) else { return }
        events[index].usage = usage
        if events[index].model == nil { events[index].model = model }
    }
}
