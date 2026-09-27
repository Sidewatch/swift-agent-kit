//
//  TimelineEvent.swift
//  AgentSession
//
//  A single entry in an agent's activity timeline — a user prompt, a line of
//  assistant text, a tool call, or a file edit — in the agent-agnostic model.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One entry in an agent's activity timeline, normalized across agents.
///
/// Adapters map each agent's own transcript format onto a stream of these, so a
/// review surface can render any agent's activity identically. `Equatable`, so
/// a polling surface can compare a fresh transcript read against what it last
/// rendered and skip the rebuild when nothing changed.
public struct TimelineEvent: Equatable, Sendable {

    /// The category of a timeline entry, which drives its glyph and styling.
    public enum Kind: Sendable {

        /// A prompt typed by the human operator.
        case userPrompt

        /// A line of assistant (model) prose.
        case assistantText

        /// A tool invocation that is not a file edit (shell, search, …).
        case toolUse

        /// A tool invocation that writes to a file on disk.
        case fileEdit
    }

    /// Who wrote a prompt.
    public enum Source: Sendable {
        /// The person at the keyboard.
        case person
        /// The agent tool itself: a background task finishing, a sub-agent reporting back.
        case agent
    }

    /// The category of this entry.
    public let kind: Kind

    /// A short title — the speaker (`"You"` / `"Claude"`) or the tool name.
    public let title: String

    /// The one-line detail: prompt text, prose, a command, or a shortened path.
    public let detail: String

    /// The file this entry touched, if any (for `.fileEdit` and path tools).
    public internal(set) var filePath: String?

    /// A short `HH:MM` timestamp, or `""` when unknown.
    public let timestamp: String

    /// For a `.fileEdit`, a distinctive line of the text the edit inserted — used to
    /// locate *where in the file* the edit landed (so a follow-mode reader jumps to the
    /// edit, not the file's first diff hunk). Nil for whole-file writes and non-edits.
    public let anchor: String?

    /// For a shell tool call, the WHOLE command as the agent ran it — every line of a heredoc,
    /// every `&&` link. `detail` keeps its first 120 characters for the feed; a review surface
    /// that classifies what the agent ran (a `psql -c "DELETE …"` two lines down) needs all of
    /// it. Nil for every other entry.
    public let command: String?

    /// The tokens one assistant MESSAGE reported, attached to the first event that message
    /// produced (a message is one model call; its text and tool blocks share the bill).
    public struct Usage: Equatable, Sendable {
        /// Token counts by kind: fresh input, cache writes, cache reads, output.
        public let input: Int, cacheWrite: Int, cacheRead: Int, output: Int
        /// One message's token counts.
        public init(input: Int, cacheWrite: Int, cacheRead: Int, output: Int) {
            self.input = input; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead; self.output = output
        }
    }
    /// The usage and the model of the message this event came from; nil for the message's
    /// later events and for user prompts. Summing a turn's events gives the turn's bill.
    public internal(set) var usage: Usage?
    /// The model id that message ran on, alongside `usage`.
    public internal(set) var model: String?
    /// The agent's tool-call id (`tool_use.id`), so a later `tool_result` can be matched to it.
    public let toolUseID: String?

    /// For a tool call, what the tool returned — the `tool_result` block matched by
    /// `toolUseID`, kept to its LAST `resultCap` characters (a test runner's summary is at the
    /// end) — and whether the tool reported an error. Set after the call's event, when the
    /// result arrives in the next user message.
    public var result: String?
    /// Whether the tool reported its `result` as an error.
    public var resultIsError: Bool = false
    /// How many trailing characters of a tool result are kept.
    public static let resultCap = 6_000

    /// For a prompt or a reply, its whole text (`detail` is only the first line), kept to its
    /// first ``fullTextCap`` characters so a pasted log cannot hold the timeline's memory.
    public let fullText: String?
    /// How many leading characters of a prompt's or reply's text are kept.
    public static let fullTextCap = 20_000
    /// Who wrote a prompt; `.person` for every other entry.
    public let source: Source

    /// Creates a timeline entry.
    public init(
        kind: Kind, title: String, detail: String, filePath: String?, timestamp: String, anchor: String? = nil, command: String? = nil,
        usage: Usage? = nil, model: String? = nil, toolUseID: String? = nil, fullText: String? = nil, source: Source = .person
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.filePath = filePath
        self.timestamp = timestamp
        self.anchor = anchor
        self.command = command
        self.usage = usage
        self.model = model
        self.toolUseID = toolUseID
        self.fullText = fullText.map { $0.count > Self.fullTextCap ? String($0.prefix(Self.fullTextCap)) + "…" : $0 }
        self.source = source
    }
}
