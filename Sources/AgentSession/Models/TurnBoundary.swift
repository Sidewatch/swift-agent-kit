//
//  TurnBoundary.swift
//  AgentSession
//
//  Splitting a flat timeline into agent turns — the run of events from one user prompt to
//  just before the next.
//
//  Created by David Sherlock on 7/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One agent turn: the run of timeline events from a user prompt up to just before the next.
///
/// A turn is the natural unit of review — "what did the agent do in response to what I asked" —
/// and the span a checkpoint pair brackets.
public struct TurnBoundary: Equatable {

    /// Index of the turn's opening `.userPrompt` event in the source timeline.
    public let start: Int

    /// Index of the turn's last event in the source timeline (inclusive).
    public let end: Int

    /// The prompt text that opened the turn, for labelling it.
    public let prompt: String

    /// The opening event's `HH:MM` timestamp, or `""` when unknown.
    public let timestamp: String

    /// What tells the opening prompt apart from an identical one (``TimelineEvent/turnKey``):
    /// its full timestamp, its message id, its prompt number. Nil when the agent gives none.
    public let key: String?

    /// Creates a turn boundary.
    ///
    /// - Parameters:
    ///   - start: Index of the opening `.userPrompt` event.
    ///   - end: Index of the final event in the turn.
    ///   - prompt: The opening prompt's text.
    ///   - timestamp: The opening event's timestamp.
    ///   - key: What tells the prompt apart from an identical one, if the agent records it.
    public init(start: Int, end: Int, prompt: String, timestamp: String, key: String? = nil) {
        self.start = start
        self.end = end
        self.prompt = prompt
        self.timestamp = timestamp
        self.key = key
    }

    /// The number of events in the turn.
    public var count: Int { end - start + 1 }

    /// A stable identifier for the turn: FNV-1a over its opening prompt and its ``key`` (else its
    /// `HH:MM` timestamp), stable across relaunches and ref-name-safe. Must not be a position
    /// (`ClaudeTranscriptState` trims events from the FRONT, shifting every index and orphaning
    /// persisted checkpoints) nor `hashValue` (seeded per process). Without a key, two turns opened
    /// by the same text in the same minute — of any day — share an id; the key is what prevents it.
    public var id: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array("\(key ?? timestamp)|\(prompt)".utf8) {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        return "turn-" + String(hash, radix: 16)
    }

    /// Splits a chronological timeline into turns, oldest first.
    ///
    /// Every `.userPrompt` opens a turn and closes the previous one. Events *before* the first
    /// prompt (a resumed session's replayed tail) belong to no turn and are dropped, not folded
    /// into a prompt that didn't cause them. Empty when no prompt appears.
    public static func turns(in events: [TimelineEvent]) -> [TurnBoundary] {
        let starts = events.indices.filter { events[$0].kind == .userPrompt }
        guard !starts.isEmpty else { return [] }
        return starts.enumerated().map { position, start in
            // A turn runs to just before the next prompt, or to the end of the feed.
            let end = position + 1 < starts.count ? starts[position + 1] - 1 : events.count - 1
            return TurnBoundary(
                start: start, end: end,
                prompt: events[start].detail, timestamp: events[start].timestamp, key: events[start].turnKey)
        }
    }

    /// The turn containing the event at `index`, or `nil` when it precedes the first prompt.
    ///
    /// - Parameters:
    ///   - index: An index into the same timeline the turns were computed from.
    ///   - turns: The turns from ``turns(in:)``.
    /// - Returns: The enclosing turn, or `nil`.
    public static func turn(containing index: Int, in turns: [TurnBoundary]) -> TurnBoundary? {
        turns.last { $0.start <= index && index <= $0.end }
    }

    /// The distinct files edited during this turn, in first-touched order.
    ///
    /// - Parameter events: The timeline the turn indexes into.
    /// - Returns: Repo-relative paths, deduplicated.
    public func editedFiles(in events: [TimelineEvent]) -> [String] {
        guard start <= end, events.indices.contains(start), events.indices.contains(end) else { return [] }
        var seen = Set<String>()
        var files: [String] = []
        for event in events[start...end] where event.kind == .fileEdit {
            if let path = event.filePath, seen.insert(path).inserted { files.append(path) }
        }
        return files
    }
}
