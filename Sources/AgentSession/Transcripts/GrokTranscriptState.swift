//
//  GrokTranscriptState.swift
//  AgentSession
//
//  The accumulated parse state for one Grok Build session: prompts, replies, tool calls and file
//  edits.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// The accumulated parse state for one Grok Build `chat_history.jsonl`.
///
/// One line per `ConversationItem` (`xai-grok-sampling-types/src/conversation.rs`, tagged by
/// `type`): `system`, `user`, `assistant`, `tool_result`, `backend_tool_call`, `reasoning`. Grok
/// REWRITES the file on compaction, rewind and pruning, always by temp file and rename, so
/// ``TranscriptCache`` sees a new inode and re-parses; appends are read incrementally. Usage is
/// not in this file (see ``GrokSessionIndex/usage(ofSession:)``).
struct GrokTranscriptState: TranscriptParsing {
    init() {}

    /// The timeline.
    private var buffer = EventBuffer()
    /// Paths the session's edits named, as written (relative ones are the session cwd's).
    private var edited = Set<String>()

    // MARK: - Ingestion

    /// Folds one history line into the state.
    mutating func ingest(lineData: Data) {
        guard let item = JSONFile.object(from: lineData) else { return }
        switch item["type"] as? String {
        case "user":
            guard let text = Self.typedText(item) else { return }
            buffer.append(
                TimelineEvent(
                    kind: .userPrompt, title: TranscriptText.promptTitle, detail: TranscriptText.firstLine(text),
                    filePath: nil, timestamp: "", fullText: text))
        case "assistant":
            let model = item["model_id"] as? String
            let text = (item["content"] as? String ?? "").trimmed
            if !text.isEmpty {
                buffer.append(
                    TimelineEvent(
                        kind: .assistantText, title: "Grok", detail: TranscriptText.firstLine(text),
                        filePath: nil, timestamp: "", model: model, fullText: text))
            }
            for call in item["tool_calls"] as? [[String: Any]] ?? [] { ingestToolCall(call, model: model) }
        case "tool_result":
            guard let id = item["tool_call_id"] as? String else { return }
            buffer.attachResult(toolUseID: id, text: item["content"] as? String ?? "", isError: false)
        case "backend_tool_call":
            ingestBackendCall(item["kind"] as? [String: Any] ?? [:])
        default:
            break  // system prompt, reasoning
        }
    }

    /// A model tool call: an edit is the file it writes; a shell tool carries its command.
    private mutating func ingestToolCall(_ call: [String: Any], model: String?) {
        let name = call["name"] as? String ?? "tool"
        let raw = call["arguments"] as? String ?? ""
        let args = JSONFile.object(from: Data(raw.utf8)) ?? [:]
        let id = call["id"] as? String
        if name == "apply_patch" {
            for path in ApplyPatch.paths((args["patch"] ?? args["input"]) as? String ?? raw) {
                appendEdit(name, path, anchor: nil, model: model, id: id)
            }
        } else if Self.editTools.contains(name), let path = Self.firstString(args, Self.pathArguments) {
            appendEdit(name, path, anchor: (args["new_string"] as? String).flatMap(TranscriptText.anchor), model: model, id: id)
        } else {
            let command = Self.shellTools.contains(name) ? args["command"] as? String : nil
            let subject = command ?? Self.firstString(args, Self.subjectArguments) ?? ""
            buffer.append(
                TimelineEvent(
                    kind: .toolUse, title: name, detail: TranscriptText.firstLine(subject, 120), filePath: nil,
                    timestamp: "", command: command, model: model, toolUseID: id))
        }
    }

    private mutating func appendEdit(_ tool: String, _ path: String, anchor: String?, model: String?, id: String?) {
        edited.insert(path)
        buffer.append(
            TimelineEvent(
                kind: .fileEdit, title: tool, detail: TranscriptText.shortPath(path), filePath: path,
                timestamp: "", anchor: anchor, model: model, toolUseID: id))
    }

    /// A server-side tool xAI ran for the model: web or X search, or the code interpreter.
    private mutating func ingestBackendCall(_ kind: [String: Any]) {
        guard let tool = kind["tool_type"] as? String, Self.backendTools.contains(tool) else { return }
        let action = kind["action"] as? [String: Any]
        let subject = (action?["query"] as? String) ?? (action?["url"] as? String) ?? ""
        buffer.append(
            TimelineEvent(kind: .toolUse, title: tool, detail: TranscriptText.firstLine(subject, 120), filePath: nil, timestamp: ""))
    }

    // MARK: - Materialization

    /// Nil: Grok keeps usage beside the history, not in it.
    var usageResult: AgentUsage? { nil }
    var eventsResult: [TimelineEvent] { buffer.events }
    var summaryResult: AgentSummary { AgentSummary(editedFiles: edited) }
}

// MARK: - Grok Build's vocabulary

extension GrokTranscriptState {
    /// Tools that write a file, across the toolsets (`xai-grok-agent/src/config.rs`): grok-build's
    /// `search_replace` and `write`, opencode's `edit` and `write`, hashline's `hashline_edit`.
    static let editTools: Set<String> = ["search_replace", "write", "edit", "hashline_edit"]
    /// Shell tools: `run_terminal_command` (grok-build, hashline, codex), `run_terminal_cmd`
    /// (concise), `bash` (opencode).
    static let shellTools: Set<String> = ["run_terminal_command", "run_terminal_cmd", "bash"]
    /// The server-side tools (`backend_tool_call.kind.tool_type`).
    static let backendTools: Set<String> = ["web_search", "x_search", "code_interpreter"]
    /// Argument keys holding an edited file's path.
    static let pathArguments = ["file_path", "target_file", "path"]
    /// The arguments that best name what another call is about, in order.
    static let subjectArguments = ["target_file", "file_path", "path", "pattern", "query", "url", "description", "command"]

    /// What the person typed, or nil when the item is not theirs. Grok marks everything it injects
    /// with `synthetic_reason` (an interjection, typed mid-turn, is the person's); an unknown reason
    /// is Grok's too. A typed prompt is stored inside `<user_query>` — with a lead-in when the
    /// previous turn was interrupted, or when it arrived mid-turn — so the tag's inside is the
    /// prompt. The session's `<user_info>` preamble carries no reason at all and is not a prompt.
    static func typedText(_ item: [String: Any]) -> String? {
        if let reason = item["synthetic_reason"] as? String, reason != "interjection" { return nil }
        let parts = item["content"] as? [[String: Any]] ?? []
        let text = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        if let open = text.range(of: "<user_query>"), let close = text.range(of: "</user_query>", range: open.upperBound..<text.endIndex) {
            return String(text[open.upperBound..<close.lowerBound]).trimmed.nonEmpty
        }
        let trimmed = text.trimmed
        return trimmed.hasPrefix("<user_info>") ? nil : trimmed.nonEmpty
    }

    private static func firstString(_ args: [String: Any], _ keys: [String]) -> String? {
        keys.lazy.compactMap { args[$0] as? String }.first { !$0.isEmpty }
    }
}
