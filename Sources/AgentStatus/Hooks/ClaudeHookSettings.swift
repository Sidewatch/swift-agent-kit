//
//  ClaudeHookSettings.swift
//  AgentStatus
//
//  Adding the host's hooks to Claude Code's settings file, and taking them out again.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The host's hooks in a Claude Code settings file (`~/.claude/settings.json`): one command hook,
/// run in the background, under each event the host listens to. Everything else in the file is the
/// person's and is carried through untouched; the host's own entries are recognised by their
/// command, so installing twice changes nothing and removing takes out exactly what was put in.
public enum ClaudeHookSettings {
    /// The events listened to. None of them can decide anything for the agent as installed here: the
    /// hook runs in the background (`async`), where Claude Code ignores whatever it returns.
    public static let events = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"]

    /// A settings file that cannot be changed safely.
    public enum Failure: Error, Equatable {
        /// The file is not a JSON object, or its `hooks` are not the shape Claude Code documents.
        /// It is left alone: rewriting what cannot be read would lose the person's settings.
        case unreadable
    }

    /// Whether every listened event has the host's hook in `settings`. False for no file.
    public static func isInstalled(in settings: Data?) -> Bool {
        guard let root = try? object(settings), let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in (hooks[event] as? [[String: Any]])?.contains(where: isOurs) ?? false }
    }

    /// `settings` with the host's hook under every listened event, added where missing. Nil or
    /// empty `settings` is a new file.
    public static func installing(in settings: Data?) throws -> Data {
        var root = try object(settings)
        var hooks = try hookTable(root)
        for event in events {
            var groups = try groups(hooks[event])
            if !groups.contains(where: isOurs) { groups.append(group) }
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return try data(root)
    }

    /// `settings` without the host's hooks: its groups removed, an event left with none removed,
    /// and `hooks` itself removed when nothing is left in it.
    public static func removing(from settings: Data?) throws -> Data {
        var root = try object(settings)
        var hooks = try hookTable(root)
        for (event, value) in hooks {
            guard let kept = (value as? [[String: Any]])?.filter({ !isOurs($0) }) else { continue }
            hooks[event] = kept.isEmpty && (value as? [[String: Any]])?.isEmpty == false ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return try data(root)
    }

    /// The matcher group the host adds: no matcher (every event of the kind), one background command.
    static var group: [String: Any] {
        ["hooks": [["type": "command", "command": HookSpool.command, "async": true] as [String: Any]]]
    }

    /// Whether a matcher group is the host's: it runs the spool command and nothing else.
    static func isOurs(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]], handlers.count == 1 else { return false }
        return (handlers[0]["command"] as? String)?.contains("$" + HookSpool.folderVariable) ?? false
    }

    private static func object(_ settings: Data?) throws -> [String: Any] {
        guard let settings, !settings.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else { return [:] }
        guard let root = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any] else { throw Failure.unreadable }
        return root
    }

    private static func hookTable(_ root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else { throw Failure.unreadable }
        return hooks
    }

    private static func groups(_ value: Any?) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let groups = value as? [[String: Any]] else { throw Failure.unreadable }
        return groups
    }

    private static func data(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
