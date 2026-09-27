//
//  GrokSessionIndex.swift
//  AgentSession
//
//  Finds a project's newest Grok Build session, and reads the usage Grok records beside it.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Finds the newest Grok Build session for a project. Grok files a session as a FOLDER,
/// `<grok home>/sessions/<encoded cwd>/<session id>/` holding `chat_history.jsonl` and
/// `summary.json` (`xai-grok-config/src/paths.rs`, `xai-grok-shell/src/session/storage/jsonl`).
/// A sub-agent's session is an ordinary folder too, told apart only by its summary's
/// `session_kind` (`subagent…`), and is not the conversation.
final class GrokSessionIndex: @unchecked Sendable {
    /// Longest folder name Grok writes before it switches to a slug and a hash (`paths.rs`).
    static let maxBucketName = 255

    private let sessionsRoot: URL
    private let lock = NSLock()
    /// Session folder path → whether it is a sub-agent's (a session's kind never changes).
    private var isSubagentByPath: [String: Bool] = [:]

    /// An index over `sessionsRoot` (`$GROK_HOME/sessions`, default `~/.grok/sessions`).
    init(sessionsRoot: URL) { self.sessionsRoot = sessionsRoot }

    /// The newest top-level session's `chat_history.jsonl` for `root`, or nil.
    func latestSession(for root: URL) -> URL? {
        guard let bucket = bucket(for: root.standardizedFileURL.path),
              let sessions = try? FileManager.default.contentsOfDirectory(at: bucket, includingPropertiesForKeys: nil) else { return nil }
        var best: (url: URL, date: Date)?
        for session in sessions where !isSubagent(session) {
            let history = session.appendingPathComponent("chat_history.jsonl")
            guard let date = history.modificationDate else { continue }
            if best.map({ date > $0.date }) ?? true { best = (history, date) }
        }
        return best?.url
    }

    /// The project's folder: its cwd percent-encoded, or — for a name too long — the folder whose
    /// `.cwd` file holds the path (the slug-and-hash form, whose BLAKE3 hash is not recomputed).
    private func bucket(for path: String) -> URL? {
        let name = Self.encode(path)
        if name.utf8.count <= Self.maxBucketName { return sessionsRoot.appendingPathComponent(name, isDirectory: true) }
        let buckets = (try? FileManager.default.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: nil)) ?? []
        return buckets.first { bucket in
            (try? String(contentsOf: bucket.appendingPathComponent(".cwd"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) == path
        }
    }

    /// Grok's folder name for a cwd: `urlencoding::encode`, which keeps `A–Z a–z 0–9 - _ . ~`
    /// and writes every other UTF-8 byte as `%XX` in upper-case hex.
    static func encode(_ path: String) -> String {
        let kept = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~".utf8)
        return path.utf8.map { kept.contains($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }.joined()
    }

    /// Whether a session folder is a sub-agent's, from its `summary.json`; remembered.
    private func isSubagent(_ session: URL) -> Bool {
        lock.lock()
        if let known = isSubagentByPath[session.path] { lock.unlock(); return known }
        lock.unlock()
        guard let summary = JSONFile.object(at: session.appendingPathComponent("summary.json")) else { return false }
        let subagent = (summary["session_kind"] as? String)?.hasPrefix("subagent") ?? false
        lock.lock(); isSubagentByPath[session.path] = subagent; lock.unlock()
        return subagent
    }

    /// The usage Grok records beside a session, not in its history: the context size in
    /// `signals.json` (`contextTokensUsed` of `contextWindowTokens`) and the session's output and
    /// provider-reported cost in `usage.json` (`costUsdTicks`, 10¹⁰ per dollar). Nil without either.
    static func usage(ofSession history: URL) -> AgentUsage? {
        let folder = history.deletingLastPathComponent()
        let signals = JSONFile.object(at: folder.appendingPathComponent("signals.json"))
        let session = JSONFile.object(at: folder.appendingPathComponent("usage.json"))?["session"] as? [String: Any]
        guard signals != nil || session != nil else { return nil }
        return AgentUsage(contextTokens: signals?["contextTokensUsed"] as? Int ?? 0,
                          contextLimit: signals?["contextWindowTokens"] as? Int ?? 0,
                          outputTokens: session?["outputTokens"] as? Int ?? 0,
                          costUSD: Double(session?["costUsdTicks"] as? Int ?? 0) / 1e10)
    }
}
