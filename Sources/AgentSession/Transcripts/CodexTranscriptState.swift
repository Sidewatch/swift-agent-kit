//
//  CodexTranscriptState.swift
//  AgentSession
//
//  The accumulated parse state for one Codex CLI rollout: prompts, replies, tool calls, file
//  edits and token usage.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// The accumulated parse state for one Codex CLI rollout (`~/.codex/sessions/…/rollout-*.jsonl`).
///
/// Built on the records Codex persists in EVERY history mode (`codex-rs/rollout/src/policy.rs`):
/// `response_item` messages, tool calls and their outputs, plus `turn_context` and `token_count`.
/// The `event_msg` user and agent messages and `patch_apply_end` are written only in the legacy
/// mode, so nothing here depends on them.
struct CodexTranscriptState: TranscriptParsing {
    init() {}

    /// The timeline.
    private var buffer = EventBuffer()
    /// Absolute paths the session's patches touched.
    private var edited = Set<String>()
    /// The working directory patches are relative to (`session_meta` / `turn_context`).
    private var cwd: String?
    /// The model in use (`turn_context`).
    private var model: String?
    /// The latest cumulative and per-call token counts, and the model's context window.
    private var totals: TokenCounts?
    private var contextWindow: Int?

    /// One `token_count` reading.
    private struct TokenCounts {
        let input, cached, output: Int
        init(_ usage: [String: Any]) {
            input = usage["input_tokens"] as? Int ?? 0
            cached = usage["cached_input_tokens"] as? Int ?? 0
            output = usage["output_tokens"] as? Int ?? 0
        }
    }

    // MARK: - Ingestion

    /// Folds one rollout line into the state.
    mutating func ingest(lineData: Data) {
        guard let obj = JSONFile.object(from: lineData), let payload = obj["payload"] as? [String: Any] else { return }
        let ts = TranscriptText.shortTime(obj["timestamp"] as? String)
        switch obj["type"] as? String {
        case "session_meta", "turn_context":
            if let dir = payload["cwd"] as? String { cwd = dir }
            if let m = payload["model"] as? String, !m.isEmpty { model = m }
        case "response_item":
            ingestResponseItem(payload, ts: ts)
        case "event_msg" where payload["type"] as? String == "token_count":
            ingestTokenCount(payload)
        default:
            break
        }
    }

    private mutating func ingestResponseItem(_ item: [String: Any], ts: String) {
        switch item["type"] as? String {
        case "message":
            ingestMessage(item, ts: ts)
        case "function_call":
            ingestToolCall(name: item["name"] as? String ?? "tool", arguments: item["arguments"] as? String,
                           callID: item["call_id"] as? String, ts: ts)
        case "custom_tool_call":
            ingestToolCall(name: item["name"] as? String ?? "tool", arguments: item["input"] as? String,
                           callID: item["call_id"] as? String, ts: ts)
        case "local_shell_call":
            let action = item["action"] as? [String: Any]
            let command = Self.shellCommand(action?["command"])
            buffer.append(TimelineEvent(kind: .toolUse, title: "shell", detail: TranscriptText.firstLine(command ?? "", 120),
                                        filePath: nil, timestamp: ts, command: command, model: model,
                                        toolUseID: (item["call_id"] as? String) ?? (item["id"] as? String)))
        case "function_call_output", "custom_tool_call_output":
            guard let id = item["call_id"] as? String else { return }
            let (text, failed) = Self.outputText(item["output"])
            buffer.attachResult(toolUseID: id, text: text, isError: failed)
        default:
            break
        }
    }

    /// A message: the person's prompt (unless Codex injected it), or the model's reply.
    private mutating func ingestMessage(_ item: [String: Any], ts: String) {
        let content = item["content"] as? [[String: Any]] ?? []
        let texts = content.compactMap { $0["text"] as? String }
        switch item["role"] as? String {
        case "user":
            guard Self.isTypedByPerson(item, content: content), let text = texts.first(where: { !$0.trimmed.isEmpty }) else { return }
            let detail = TranscriptText.firstLine(text)
            buffer.append(TimelineEvent(kind: .userPrompt, title: TranscriptText.promptTitle, detail: detail, filePath: nil, timestamp: ts))
        case "assistant":
            let text = texts.joined(separator: "\n").trimmed
            guard !text.isEmpty else { return }
            buffer.append(TimelineEvent(kind: .assistantText, title: "Codex", detail: TranscriptText.firstLine(text),
                                        filePath: nil, timestamp: ts, model: model))
        default:
            break   // developer / system instructions are not part of the conversation
        }
    }

    /// A tool call: an `apply_patch` is the files it edits; a shell tool carries its command; any
    /// other tool shows its name and first argument line.
    private mutating func ingestToolCall(name: String, arguments: String?, callID: String?, ts: String) {
        let args = arguments.flatMap { JSONFile.object(from: Data($0.utf8)) }
        if name == "apply_patch" {
            let patch = (args?["input"] as? String) ?? arguments ?? ""
            for path in ApplyPatch.paths(patch) {
                let absolute = path.hasPrefix("/") ? path : ((cwd ?? "") as NSString).appendingPathComponent(path)
                edited.insert(absolute)
                buffer.append(TimelineEvent(kind: .fileEdit, title: name, detail: TranscriptText.shortPath(absolute), filePath: absolute,
                                            timestamp: ts, model: model, toolUseID: callID))
            }
            return
        }
        let command = Self.shellCommand(args?["cmd"] ?? args?["command"])
        let detail = command.map { TranscriptText.firstLine($0, 120) } ?? TranscriptText.firstLine(arguments ?? "", 120)
        buffer.append(TimelineEvent(kind: .toolUse, title: name, detail: detail, filePath: nil, timestamp: ts,
                                    command: command, model: model, toolUseID: callID))
    }

    /// A `token_count`: the session's cumulative totals, and this call's usage billed to the
    /// latest event (Codex reports usage after the call, not on it).
    private mutating func ingestTokenCount(_ payload: [String: Any]) {
        guard let info = payload["info"] as? [String: Any] else { return }
        if let total = info["total_token_usage"] as? [String: Any] { totals = TokenCounts(total) }
        if let window = info["model_context_window"] as? Int { contextWindow = window }
        if let last = info["last_token_usage"] as? [String: Any] {
            let call = TokenCounts(last)
            buffer.billLatest(TimelineEvent.Usage(input: max(0, call.input - call.cached), cacheWrite: 0,
                                                  cacheRead: call.cached, output: call.output), model: model)
            lastCallContext = call.input + call.output
        }
    }

    /// The last call's context size (its input plus output).
    private var lastCallContext = 0

    // MARK: - Materialization

    /// Context, output and cost. Cost comes from ``ModelPricing``, which has no OpenAI prices, so
    /// it is zero (and not shown) rather than a guess.
    var usageResult: AgentUsage? {
        guard let totals else { return nil }
        let cost = ModelPricing.cost(model: model ?? "", input: max(0, totals.input - totals.cached), cacheWrite: 0,
                                     cacheRead: totals.cached, output: totals.output)
        return AgentUsage(contextTokens: lastCallContext, contextLimit: contextWindow ?? 272_000,
                          outputTokens: totals.output, costUSD: cost)
    }

    var eventsResult: [TimelineEvent] { buffer.events }
    var summaryResult: AgentSummary { AgentSummary(editedFiles: edited) }
}

// MARK: - Codex's vocabulary

extension CodexTranscriptState {
    /// Whether a user-role message is the person's, by Codex's own rule
    /// (`is_user_turn_boundary`): not when any content item is context Codex injected. A current
    /// rollout tags each item's kind (`user.*` is the person's); an older one is judged by the
    /// fragment markers — a text that is one `<tag>…</tag>` element, AGENTS.md instructions, or
    /// one of Codex's warnings.
    static func isTypedByPerson(_ item: [String: Any], content: [[String: Any]]) -> Bool {
        let passthrough = item["internal_chat_message_metadata_passthrough"] as? [String: Any]
        if let kinds = passthrough?["content_item_kinds"] as? [String], !kinds.isEmpty, kinds.count == content.count {
            return kinds.contains { $0.hasPrefix("user.") }
        }
        return !content.contains { ($0["text"] as? String).map(isContextualText) ?? false }
    }

    /// The warnings Codex injects as user messages (`legacy_*_warning.rs`), matched exactly so a
    /// prompt that merely starts "Warning:" is still the person's.
    private static let warnings = [
        "Warning: apply_patch was requested via ",
        "Warning: Your account was flagged for potentially high-risk cyber activity",
        "Warning: The maximum number of unified exec processes you can keep open is",
    ]

    /// Codex's injected-context shapes, from `codex-rs/core/src/context/`.
    static func isContextualText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("# AGENTS.md instructions") || warnings.contains(where: t.hasPrefix) { return true }
        guard t.hasPrefix("<"), let close = t.firstIndex(of: ">") else { return false }
        let tag = t[t.index(after: t.startIndex)..<close].split(separator: " ").first.map(String.init) ?? ""
        return !tag.isEmpty && !tag.hasPrefix("/") && t.hasSuffix("</\(tag)>")
    }

    /// A shell tool's command: `exec_command`'s `cmd`, `shell_command`'s `command` string, or the
    /// legacy `shell` argv — a `bash -lc <script>` argv reads as its script.
    static func shellCommand(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let argv = value as? [String], !argv.isEmpty else { return nil }
        if argv.count == 3, ["-lc", "-c"].contains(argv[1]) { return argv[2] }
        return argv.joined(separator: " ")
    }

    /// A tool output's text: a plain string, one `{text}` item, a list of them, or the legacy JSON
    /// string `{"output": …, "metadata": {"exit_code": …}}`; failed when it reports a non-zero exit.
    static func outputText(_ output: Any?) -> (String, Bool) {
        if let s = output as? String {
            if let legacy = JSONFile.object(from: Data(s.utf8)), let inner = legacy["output"] as? String {
                let exit = (legacy["metadata"] as? [String: Any])?["exit_code"] as? Int
                return (inner, (exit ?? 0) != 0)
            }
            return (s, false)
        }
        if let item = output as? [String: Any] { return ((item["text"] as? String) ?? "", false) }
        if let items = output as? [[String: Any]] { return (items.compactMap { $0["text"] as? String }.joined(separator: "\n"), false) }
        return ("", false)
    }
}
