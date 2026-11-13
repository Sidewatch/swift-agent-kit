//
//  HookSpoolReader.swift
//  AgentStatus
//
//  Taking the events hooks have left in the spool folder.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Takes the events hooks have written into a spool folder (``HookSpool``): each finished file is
/// read once and removed, oldest first, whether or not it held an event anyone can use. A file
/// still being written is left for the next pass. The folder is the host's own; anything in it
/// that is not an event file is someone else's mistake and is left alone.
public enum HookSpoolReader {
    /// One event and the terminal its hook ran in.
    public struct Delivery: Equatable, Sendable {
        /// The id the host gave that terminal's shell.
        public let terminalID: String
        /// What the agent reported.
        public let event: AgentHookEvent
    }

    /// The most files taken in one pass; more wait for the next. An agent sends a handful an hour.
    public static let batchLimit = 200

    /// Reads and removes the finished event files in `folder`, oldest first.
    public static func drain(_ folder: URL) -> [Delivery] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [])
            .compactMap { url -> (url: URL, terminal: String, written: Date, size: Int)? in
                guard let terminal = HookSpool.terminalID(ofFileNamed: url.lastPathComponent),
                    let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
                else { return nil }
                return (url, terminal, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
            }
            .sorted { ($0.written, $0.url.lastPathComponent) < ($1.written, $1.url.lastPathComponent) }
            .prefix(batchLimit)
        var deliveries: [Delivery] = []
        for file in files {
            // Removed whatever it holds: a file nothing can read would otherwise be read every pass.
            defer { try? FileManager.default.removeItem(at: file.url) }
            guard file.size <= ClaudeHookPayload.sizeLimit, let data = try? Data(contentsOf: file.url),
                let event = ClaudeHookPayload.event(from: data)
            else { continue }
            deliveries.append(Delivery(terminalID: file.terminal, event: event))
        }
        return deliveries
    }
}
