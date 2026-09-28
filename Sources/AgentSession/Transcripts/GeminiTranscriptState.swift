//
//  GeminiTranscriptState.swift
//  AgentSession
//
//  The accumulated parse state for one Gemini CLI session: prompts, replies, tool calls, file
//  edits and token usage.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// The accumulated parse state for one Gemini CLI session (`chats/session-*.jsonl`).
///
/// Folds lines the way Gemini's own loader does (`loadConversationRecord` in
/// `packages/core/src/services/chatRecordingService.ts`): a record with an `id` is a message, and
/// a later record with the same id REPLACES it (Gemini re-appends a reply as its tokens and tool
/// results arrive); `$rewindTo` drops that message and everything after it; a `$set` carrying
/// `messages` is a checkpoint that replaces them all. So the state is keyed by message, and the
/// timeline is built from the surviving messages when it is read.
struct GeminiTranscriptState: TranscriptParsing {
    init() {}

    /// One message's contribution to the timeline.
    private struct Entry {
        var events: [TimelineEvent] = []
        var edits: [String] = []
        var tokens: Tokens?
        var model: String?
    }

    /// One reply's `tokens` (`TokensSummary`).
    private struct Tokens {
        let input, cached, output, total: Int
        init?(_ value: Any?) {
            guard let t = value as? [String: Any] else { return nil }
            input = t["input"] as? Int ?? 0
            cached = t["cached"] as? Int ?? 0
            // Thinking is billed as output; `candidatesTokenCount` leaves it out.
            output = (t["output"] as? Int ?? 0) + (t["thoughts"] as? Int ?? 0)
            total = t["total"] as? Int ?? 0
        }
    }

    /// The messages, in first-seen order, and where each id sits.
    private var entries: [Entry] = []
    private var ids: [String] = []
    private var position: [String: Int] = [:]

    // MARK: - Ingestion

    /// Folds one session line into the state.
    mutating func ingest(lineData: Data) {
        guard let record = JSONFile.object(from: lineData) else { return }
        if let rewind = record["$rewindTo"] as? String {
            rewindTo(rewind)
        } else if let id = record["id"] as? String {
            upsert(id: id, Self.entry(for: record))
        } else if let set = record["$set"] as? [String: Any], let messages = set["messages"] as? [[String: Any]] {
            entries = []; ids = []; position = [:]
            for message in messages { if let id = message["id"] as? String { upsert(id: id, Self.entry(for: message)) } }
        }
    }

    /// Replaces the message `id`, keeping its place, or appends it.
    private mutating func upsert(id: String, _ entry: Entry) {
        if let i = position[id] { entries[i] = entry; return }
        position[id] = entries.count
        ids.append(id)
        entries.append(entry)
        trimIfNeeded()
    }

    /// Drops the message `id` and everything after it; everything when `id` is unknown.
    private mutating func rewindTo(_ id: String) {
        let cut = position[id] ?? 0
        for dropped in ids[cut...] { position[dropped] = nil }
        ids.removeSubrange(cut...)
        entries.removeSubrange(cut...)
    }

    /// Keeps the newest ``EventBuffer/cap`` messages, dropping the oldest in batches so the index
    /// is rebuilt rarely.
    private mutating func trimIfNeeded() {
        let batch = 500
        guard entries.count > EventBuffer.cap + batch else { return }
        entries.removeFirst(batch)
        ids.removeFirst(batch)
        position = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
    }

    // MARK: - Materialization

    /// Context (the last reply's total), output and cost. Cost comes from ``ModelPricing``, which
    /// has no Google prices, so it is zero (and not shown) rather than a guess.
    var usageResult: AgentUsage? {
        let billed = entries.filter { $0.tokens != nil }
        guard let last = billed.last?.tokens else { return nil }
        let model = billed.last?.model ?? ""
        let input = billed.reduce(0) { $0 + max(0, $1.tokens!.input - $1.tokens!.cached) }
        let cached = billed.reduce(0) { $0 + $1.tokens!.cached }
        let output = billed.reduce(0) { $0 + $1.tokens!.output }
        let cost = ModelPricing.cost(model: model, input: input, cacheWrite: 0, cacheRead: cached, output: output)
        return AgentUsage(contextTokens: last.total, contextLimit: Self.contextLimit, outputTokens: output, costUSD: cost)
    }

    var eventsResult: [TimelineEvent] {
        var buffer = EventBuffer()
        for entry in entries { for event in entry.events { buffer.append(event) } }
        return buffer.events
    }

    var summaryResult: AgentSummary { AgentSummary(editedFiles: Set(entries.flatMap(\.edits))) }

    /// Gemini's models take a million-token window.
    static let contextLimit = 1_048_576
}

// MARK: - Gemini's vocabulary

extension GeminiTranscriptState {
    /// The tools that write a file (`EDIT_TOOL_NAMES` in `tools/tool-names.ts`).
    static let editTools: Set<String> = ["replace", "write_file"]
    /// The shell tool (`SHELL_TOOL_NAME`), whose `command` is the script it runs.
    static let shellTool = "run_shell_command"
    /// The arguments that best name what a tool call is about, in order
    /// (`tools/definitions/base-declarations.ts`).
    static let subjectArguments = ["file_path", "dir_path", "pattern", "query", "url", "prompt", "path", "name", "description"]

    /// One message's events: a prompt, or a reply's text then its tool calls, billed with the
    /// reply's tokens. `info`, `error` and `warning` messages are Gemini's, not the conversation.
    private static func entry(for message: [String: Any]) -> Entry {
        let ts = TranscriptText.shortTime(message["timestamp"] as? String)
        var entry = Entry()
        switch message["type"] as? String {
        case "user":
            let text = partsText(message["displayContent"] ?? message["content"]).trimmed
            guard isTypedByPerson(text) else { return entry }
            entry.events = [
                TimelineEvent(
                    kind: .userPrompt, title: TranscriptText.promptTitle, detail: TranscriptText.firstLine(text),
                    filePath: nil, timestamp: ts, fullText: text, turnKey: message["id"] as? String)
            ]
        case "gemini":
            let model = message["model"] as? String
            entry.model = model
            let text = partsText(message["content"]).trimmed
            if !text.isEmpty {
                entry.events.append(
                    TimelineEvent(
                        kind: .assistantText, title: "Gemini", detail: TranscriptText.firstLine(text),
                        filePath: nil, timestamp: ts, model: model, fullText: text))
            }
            for call in message["toolCalls"] as? [[String: Any]] ?? [] {
                let (event, edited) = toolEvent(call, model: model, fallbackTime: ts)
                entry.events.append(event)
                if let edited { entry.edits.append(edited) }
            }
            entry.tokens = Tokens(message["tokens"])
            if let t = entry.tokens, !entry.events.isEmpty {
                entry.events[entry.events.count - 1].usage = TimelineEvent.Usage(
                    input: max(0, t.input - t.cached), cacheWrite: 0,
                    cacheRead: t.cached, output: t.output)
            }
        default:
            break
        }
        return entry
    }

    /// A tool call as a timeline event, with the file it edits when it is an edit.
    private static func toolEvent(_ call: [String: Any], model: String?, fallbackTime: String) -> (TimelineEvent, String?) {
        let name = call["name"] as? String ?? "tool"
        let args = call["args"] as? [String: Any] ?? [:]
        let ts = (call["timestamp"] as? String).map(TranscriptText.shortTime) ?? fallbackTime
        let id = call["id"] as? String
        var event: TimelineEvent
        var edited: String?
        if editTools.contains(name), let path = args["file_path"] as? String {
            edited = path
            event = TimelineEvent(
                kind: .fileEdit, title: name, detail: TranscriptText.shortPath(path), filePath: path,
                timestamp: ts, anchor: (args["new_string"] as? String).flatMap(TranscriptText.anchor),
                model: model, toolUseID: id)
        } else {
            let command = name == shellTool ? args["command"] as? String : nil
            let subject = command ?? subjectArguments.lazy.compactMap { args[$0] as? String }.first ?? ""
            event = TimelineEvent(
                kind: .toolUse, title: name, detail: TranscriptText.firstLine(subject, 120), filePath: nil,
                timestamp: ts, command: command, model: model, toolUseID: id)
        }
        let (text, failed) = resultText(call)
        if !text.isEmpty {
            event.result = text.count > TimelineEvent.resultCap ? "…" + String(text.suffix(TimelineEvent.resultCap)) : text
        }
        event.resultIsError = failed
        return (event, edited)
    }

    /// Whether a user message is the person's, by Gemini's own rule (`isIgnoredUserContent` in
    /// `utils/sessionUtils.ts`): not empty, not a `/` command or `?` help, not injected context.
    static func isTypedByPerson(_ trimmed: String) -> Bool {
        !(trimmed.isEmpty || trimmed.hasPrefix("/") || trimmed.hasPrefix("?")
            || trimmed.hasPrefix("<session_context>") || trimmed.hasPrefix("<hook_context>"))
    }

    /// A `PartListUnion`'s text: a string, one part, or a list of either (`partListUnionToString`).
    static func partsText(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let part = value as? [String: Any] { return part["text"] as? String ?? "" }
        if let list = value as? [Any] { return list.map(partsText).joined() }
        return ""
    }

    /// A tool call's output: what the person was shown (`resultDisplay`) when it is text, else
    /// the function response's `output` or `error`; failed when the call's status is `error`.
    static func resultText(_ call: [String: Any]) -> (String, Bool) {
        let failed = call["status"] as? String == "error"
        if let shown = call["resultDisplay"] as? String { return (shown, failed) }
        let responses = (call["result"] as? [[String: Any]] ?? []).compactMap {
            ($0["functionResponse"] as? [String: Any])?["response"] as? [String: Any]
        }
        let text = responses.compactMap { ($0["output"] as? String) ?? ($0["error"] as? String) }.joined(separator: "\n")
        return (text, failed || responses.contains { $0["error"] != nil })
    }
}
