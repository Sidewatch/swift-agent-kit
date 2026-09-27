//
//  TranscriptState.swift
//  AgentSession
//
//  The accumulated parse state for one Claude Code JSONL transcript: per-line
//  ingestion plus materialization of the usage / events / summary results.
//
//  Created by David Sherlock on 7/16/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// The accumulated parse state for one Claude Code JSONL transcript: running cost and token
/// totals, the current and peak context size, the model in use, and the message ids already
/// counted, so a re-read after an append never double counts.
struct TranscriptState {

    /// Explicit rather than memberwise, because the private accumulators below would make a
    /// synthesised init private and unreachable from the cache.
    init() {}


    // MARK: - Usage accumulators

    /// Estimated spend so far, in US dollars.
    private var cost = 0.0

    /// Total output tokens across deduplicated API responses.
    private var totalOut = 0

    /// The most recent non-zero context window (input + cache + output tokens).
    private var curCtx = 0

    /// The largest context window seen (drives the 200k-vs-1M limit guess).
    private var maxCtx = 0

    /// The most recent real model name seen (drives pricing).
    private var model = "claude"

    /// `message.id` / `requestId` values already priced. Claude Code writes one
    /// JSONL line per assistant content block, each repeating the same message
    /// id and an identical usage object — each API response must count once.
    private var seenMessageIDs = Set<String>()

    // MARK: - Events buffer

    /// The most recent events reported: enough for a long session's last several prompts (one
    /// busy prompt can run hundreds of tool calls).
    static let eventCap = 2_000
    /// How many of the newest events keep their tool output whole; older ones keep its END,
    /// where a test run's or build's summary sits, so the buffer's memory stays near what 300
    /// whole events cost.
    static let fullResultCount = 300
    static let olderResultCap = 400

    /// The activity timeline, oldest first, trimmed live to ``eventCap`` so the
    /// buffer stays bounded no matter how long the session runs. Trimming as we
    /// go is equivalent to parsing everything and taking the suffix.
    private var events: [TimelineEvent] = []

    // MARK: - Summary accumulators

    /// Absolute paths of every file an edit tool wrote to.
    private var edited = Set<String>()


    // MARK: - Ingestion

    /// Folds one complete transcript line into the state.
    ///
    /// The line is parsed as raw JSON bytes (JSONL is UTF-8 by spec); malformed
    /// or non-object lines are skipped, never fatal. All three result streams
    /// (usage / events / summary) are updated from the single parse.
    mutating func ingest(lineData: Data) {
        guard let obj = JSONFile.object(from: lineData) else { return }
        ingestUsage(obj)
        ingestEvent(obj)
        ingestSummary(obj)
    }

    /// Updates the token/cost accumulators from one parsed line.
    private mutating func ingestUsage(_ obj: [String: Any]) {
        guard let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any] else { return }
        if let m = msg["model"] as? String, !m.isEmpty, m != "<synthetic>" { model = m }
        let inp = usage["input_tokens"] as? Int ?? 0
        let cw = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cr = usage["cache_read_input_tokens"] as? Int ?? 0
        let out = usage["output_tokens"] as? Int ?? 0
        let id = (msg["id"] as? String) ?? (obj["requestId"] as? String)
        let isDuplicate = id.map { !seenMessageIDs.insert($0).inserted } ?? false
        if !isDuplicate {
            cost += ModelPricing.cost(model: model, input: inp, cacheWrite: cw, cacheRead: cr, output: out)
            totalOut += out
        }
        // Duplicates carry identical values, so the context window is safe to update.
        let ctx = inp + cw + cr + out
        if ctx > 0 { curCtx = ctx }
        maxCtx = max(maxCtx, ctx)
    }

    /// Whether a user-role line is something the person typed, from Claude Code's own marks: a
    /// sub-agent's report (`origin.kind` "peer"), a background task's notice, a command's
    /// output (`isMeta`) and the summary a compaction leaves (`isCompactSummary`) all ride on
    /// user-role lines without being prompts. Nil for a transcript too old to carry the marks.
    static func isTypedByPerson(_ obj: [String: Any]) -> Bool? {
        if obj["isMeta"] as? Bool == true || obj["isCompactSummary"] as? Bool == true { return false }
        guard let origin = obj["origin"] as? [String: Any], let kind = origin["kind"] as? String else { return nil }
        return kind == "human"
    }

    /// A prompt's text without the wrapper a paste arrives in (`<pasted_content …>…`) or the
    /// `[Image #4]` markers attached screenshots leave.
    static func unwrapped(_ text: String) -> String {
        text.replacingOccurrences(of: #"</?pasted_content[^>]*>|\[Image #\d+\]\s*"#, with: "", options: .regularExpression)
    }

    /// Appends this line's timeline events (if any), keeping the buffer capped.
    private mutating func ingestEvent(_ obj: [String: Any]) {
        // A message typed while the agent works is queued, then absorbed into the running turn:
        // it has no user line of its own, and from that moment the agent works on it.
        if obj["type"] as? String == "queue-operation", obj["operation"] as? String == "remove",
           obj["reason"] as? String == "absorbed_mid_turn", let text = obj["content"] as? String {
            append(TimelineEvent(kind: .userPrompt, title: String(localized: "You", bundle: .module, comment: "Timeline row title for a prompt the person typed to the agent"),
                                 detail: Self.firstLine(Self.unwrapped(text)), filePath: nil, timestamp: Self.shortTime(obj["timestamp"] as? String)))
            return
        }
        guard let msg = obj["message"] as? [String: Any] else { return }
        let type = obj["type"] as? String ?? ""
        let ts = Self.shortTime(obj["timestamp"] as? String)

        if type == "user" {
            let typed = Self.isTypedByPerson(obj)
            if let s = msg["content"] as? String {
                if typed ?? !s.hasPrefix("<") {
                    append(TimelineEvent(kind: .userPrompt, title: String(localized: "You", bundle: .module, comment: "Timeline row title for a prompt the person typed to the agent"), detail: Self.firstLine(Self.unwrapped(s)), filePath: nil, timestamp: ts))
                }
            } else if let arr = msg["content"] as? [[String: Any]] {
                // Tool results ride back on a user message: attach each to its call by id.
                for block in arr where (block["type"] as? String) == "tool_result" {
                    guard let id = block["tool_use_id"] as? String,
                          let index = events.lastIndex(where: { $0.toolUseID == id }) else { continue }
                    let text: String
                    if let s = block["content"] as? String { text = s }
                    else if let parts = block["content"] as? [[String: Any]] { text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n") }
                    else { text = "" }
                    // A spilled result is read back from its file (its END is what a summary reader wants).
                    let resolved = PersistedOutput.resolved(text, cap: TimelineEvent.resultCap)
                    events[index].result = resolved.count > TimelineEvent.resultCap ? "…" + String(resolved.suffix(TimelineEvent.resultCap)) : resolved
                    events[index].resultIsError = (block["is_error"] as? Bool) ?? false
                }
                let texts = arr.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }
                if !texts.isEmpty, typed ?? true {
                    append(TimelineEvent(kind: .userPrompt, title: String(localized: "You", bundle: .module, comment: "Timeline row title for a prompt the person typed to the agent"), detail: Self.firstLine(Self.unwrapped(texts.joined(separator: " "))), filePath: nil, timestamp: ts))
                }
            }
        } else if type == "assistant", let arr = msg["content"] as? [[String: Any]] {
            // The message's bill rides on its FIRST event only — one model call, one charge —
            // and a replayed message (same id) carries none, like `ingestUsage`.
            let messageModel = (msg["model"] as? String).flatMap { $0.isEmpty || $0 == "<synthetic>" ? nil : $0 }
            var pendingUsage: TimelineEvent.Usage? = nil
            if let u = msg["usage"] as? [String: Any] {
                let id = (msg["id"] as? String) ?? (obj["requestId"] as? String)
                if id.map({ !billedMessageIDs.contains($0) }) ?? true {
                    if let id { billedMessageIDs.insert(id) }
                    pendingUsage = TimelineEvent.Usage(input: u["input_tokens"] as? Int ?? 0, cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0,
                                                       cacheRead: u["cache_read_input_tokens"] as? Int ?? 0, output: u["output_tokens"] as? Int ?? 0)
                }
            }
            func bill() -> TimelineEvent.Usage? { defer { pendingUsage = nil }; return pendingUsage }
            for block in arr {
                switch block["type"] as? String {
                case "text":
                    if let t = (block["text"] as? String)?.trimmed, !t.isEmpty {
                        append(TimelineEvent(kind: .assistantText, title: "Claude", detail: Self.firstLine(t), filePath: nil, timestamp: ts,
                                             usage: bill(), model: messageModel))
                    }
                case "tool_use":
                    let name = block["name"] as? String ?? "tool"
                    let input = block["input"] as? [String: Any] ?? [:]
                    let (detail, path) = Self.toolDetail(input)
                    let isEdit = Self.editTools.contains(name)
                    append(TimelineEvent(kind: isEdit ? .fileEdit : .toolUse, title: name, detail: detail, filePath: path, timestamp: ts,
                                         anchor: isEdit ? Self.editAnchor(input) : nil,
                                         command: isEdit ? nil : (input["command"] as? String),
                                         usage: bill(), model: messageModel, toolUseID: block["id"] as? String))
                default: break
                }
            }
        }
    }

    /// Message ids whose usage already rode on an event, so a replayed line is not billed twice.
    private var billedMessageIDs = Set<String>()

    /// Appends one event and trims the buffer to the cap.
    private mutating func append(_ event: TimelineEvent) {
        events.append(event)
        let aging = events.count - Self.fullResultCount - 1
        if aging >= 0, let result = events[aging].result, result.count > Self.olderResultCap {
            events[aging].result = "…" + String(result.suffix(Self.olderResultCap))
        }
        if events.count > Self.eventCap { events.removeFirst(events.count - Self.eventCap) }
    }

    /// Updates the edited-files set from one line.
    private mutating func ingestSummary(_ obj: [String: Any]) {
        guard obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let arr = msg["content"] as? [[String: Any]] else { return }
        for block in arr where block["type"] as? String == "tool_use" {
            let name = block["name"] as? String ?? ""
            let input = block["input"] as? [String: Any] ?? [:]
            // NotebookEdit's parameter is notebook_path, not file_path.
            if Self.editTools.contains(name),
               let fp = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) { edited.insert(fp) }
        }
    }

    // MARK: - Materialization

    /// The usage telemetry as the public API reports it, or `nil` when the
    /// transcript carries no usage records at all.
    var usageResult: AgentUsage? {
        guard maxCtx > 0 else { return nil }
        // Claude does not publish the window, so it is inferred from the largest context observed.
        let limit = maxCtx > 200_000 ? 1_000_000 : 200_000
        return AgentUsage(contextTokens: curCtx, contextLimit: limit, outputTokens: totalOut, costUSD: cost)
    }

    /// The activity timeline as the public API reports it (last 300, oldest first).
    var eventsResult: [TimelineEvent] { Array(events.suffix(Self.eventCap)) }

    /// The edited-files roll-up as the public API reports it.
    var summaryResult: AgentSummary { AgentSummary(editedFiles: edited) }

    // MARK: - Static helpers (shared parsing vocabulary)

    /// The tools that write to a file on disk. Read-only tools (Read, Grep, Glob, LS)
    /// also carry a path but must NOT be classified as ``TimelineEvent/Kind/fileEdit``.
    private static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]


    /// Derives a one-line detail string (and a navigable path, when the input
    /// carries one) from a tool call's input dictionary.
    private static func toolDetail(_ input: [String: Any]) -> (String, String?) {
        if let fp = input["file_path"] as? String { return (shortPath(fp), fp) }
        if let np = input["notebook_path"] as? String { return (shortPath(np), np) }
        if let p = input["path"] as? String { return (shortPath(p), p) }
        if let cmd = input["command"] as? String { return (firstLine(cmd, 120), nil) }
        if let pat = input["pattern"] as? String { return (pat, nil) }
        if let q = input["query"] as? String { return (firstLine(q, 120), nil) }
        return ("", nil)
    }

    /// A distinctive line of the text an edit inserts, to locate where the edit landed.
    /// `Edit` → its `new_string`; `MultiEdit` → the *last* sub-edit's `new_string` (where
    /// the agent finished); `Write`/`NotebookEdit` → nil (whole-file, no single anchor).
    /// Returns the first inserted line long enough to be findable (skips braces/blanks).
    private static func editAnchor(_ input: [String: Any]) -> String? {
        let source: String?
        if let ns = input["new_string"] as? String {
            source = ns
        } else if let edits = input["edits"] as? [[String: Any]],
                  let last = edits.last, let ns = last["new_string"] as? String {
            source = ns
        } else {
            source = nil
        }
        guard let text = source else { return nil }
        // `isNewline`, never the Character "\n": a CRLF file keeps its endings in `new_string`,
        // and "\r\n" is ONE Character in Swift, so a "\n" split never divides it and the anchor
        // would be the whole inserted text, which no single line can contain.
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 4 { return String(t.prefix(200)) }
        }
        return nil
    }

    /// The trimmed first line of `s`, truncated to `max` characters with an ellipsis.
    /// Internal (not private) so every adapter shares one truncation rule.
    static func firstLine(_ s: String, _ max: Int = 160) -> String {
        // `isNewline`: "\r\n" is one Character, so a "\n" split would keep a CRLF prompt whole.
        let line = s.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isNewline).first.map(String.init) ?? s
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > max ? String(t.prefix(max)) + "…" : t
    }

    /// Compresses an absolute path to its last two components (`.../Dir/File.swift`).
    private static func shortPath(_ p: String) -> String {
        let tail = p.pathTail()
        return tail == p ? p : ".../" + tail
    }

    /// Renders a `Date` as `HH:mm` on the viewer's local clock.
    /// Transcript timestamps are UTC Zulu — convert to the viewer's local clock,
    /// falling back to the raw UTC HH:MM slice only if the string is unparseable.
    /// Internal (not private) so every adapter shares one time-rendering rule.
    static func shortTime(_ iso: String?) -> String {
        guard let iso else { return "" }
        if let date = ISOTimestamp.date(iso) {
            return ClockFormat.hhmm(date)
        }
        guard let tPart = iso.split(separator: "T").dropFirst().first else { return "" }
        return String(tPart.prefix(5))
    }
}
