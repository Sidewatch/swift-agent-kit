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
/// `session_kind` (`subagent…`), and is not the conversation. The folder is named from the cwd
/// Grok saw, so every spelling of the path (``PathForms``) is tried. The session chosen is held
/// while it is being written (``SessionChoice``); a miss is remembered briefly (``LookupMisses``).
final class GrokSessionIndex: @unchecked Sendable {
    /// Longest folder name Grok writes before it switches to a slug and a hash (`paths.rs`).
    static let maxBucketName = 255

    private let sessionsRoot: URL
    /// Lists folders; its count is the test seam proving a remembered miss lists nothing.
    let reader = DirectoryReader()
    private let choice = SessionChoice()
    private let misses = LookupMisses()
    private let lock = NSLock()
    /// Session folder path → whether it is a sub-agent's (a session's kind never changes).
    private var isSubagentByPath: [String: Bool] = [:]

    /// An index over `sessionsRoot` (`$GROK_HOME/sessions`, default `~/.grok/sessions`).
    init(sessionsRoot: URL) { self.sessionsRoot = sessionsRoot }

    /// The top-level session's `chat_history.jsonl` being written for `root`, or nil.
    func latestSession(for root: URL) -> URL? {
        misses.remembering(root.path) { choice.choose(for: root.path, newest: newestSession(for: root)) }
    }

    /// The working directory of the newest top-level session started in a SUBFOLDER of `project`,
    /// or nil — every bucket's own path read back (`cwd(ofBucket:)`) and matched by prefix.
    func latestSessionRoot(under project: URL) -> URL? {
        let parents = PathForms.of(project).map { $0 + "/" }
        return misses.remembering("under:" + project.path) {
            var best: (cwd: String, date: Date)?
            for bucket in reader.contents(of: sessionsRoot) ?? [] {
                guard let cwd = Self.cwd(ofBucket: bucket), parents.contains(where: { cwd.hasPrefix($0) }) else { continue }
                for session in reader.contents(of: bucket) ?? [] where !isSubagent(session) {
                    let history = session.appendingPathComponent("chat_history.jsonl")
                    if let date = history.modificationDate, best.map({ date > $0.date }) ?? true { best = (cwd, date) }
                }
            }
            return best.map { URL(fileURLWithPath: $0.cwd, isDirectory: true) }
        }
    }

    /// The path a bucket stands for: the `.cwd` file of the slug-and-hash form, else its name
    /// percent-decoded (the inverse of `encode`).
    static func cwd(ofBucket bucket: URL) -> String? {
        if let file = try? String(contentsOf: bucket.appendingPathComponent(".cwd"), encoding: .utf8) {
            return file.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return bucket.lastPathComponent.removingPercentEncoding
    }

    /// The newest top-level session's history across every bucket a spelling of `root` names.
    private func newestSession(for root: URL) -> URL? {
        var histories: [(url: URL, date: Date)] = []
        for path in PathForms.of(root) {
            guard let bucket = bucket(for: path), let sessions = reader.contents(of: bucket) else { continue }
            for session in sessions where !isSubagent(session) {
                let history = session.appendingPathComponent("chat_history.jsonl")
                if let date = history.modificationDate { histories.append((history, date)) }
            }
        }
        return DirectoryReader.newest(histories)
    }

    /// The project's folder: its cwd percent-encoded, or — for a name too long — the folder whose
    /// `.cwd` file holds the path (the slug-and-hash form, whose BLAKE3 hash is not recomputed).
    private func bucket(for path: String) -> URL? {
        let name = Self.encode(path)
        if name.utf8.count <= Self.maxBucketName { return sessionsRoot.appendingPathComponent(name, isDirectory: true) }
        let buckets = reader.contents(of: sessionsRoot) ?? []
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
        return AgentUsage(
            contextTokens: signals?["contextTokensUsed"] as? Int ?? 0,
            contextLimit: signals?["contextWindowTokens"] as? Int ?? 0,
            outputTokens: session?["outputTokens"] as? Int ?? 0,
            costUSD: Double(session?["costUsdTicks"] as? Int ?? 0) / 1e10)
    }
}
