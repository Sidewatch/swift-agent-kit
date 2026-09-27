//
//  FileStat.swift
//  AgentSession
//
//  What a poll needs to know about a file without reading it: size, mtime, inode.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What a poll needs to know about a file without reading it: size, mtime, inode.
struct FileStat: Equatable {
    /// Bytes on disk.
    let size: UInt64
    /// Last modification time.
    let mtime: Date?
    /// Changes when the file is replaced rather than appended to.
    let inode: UInt64

    /// Nil when the file cannot be stat'ed.
    init?(path: String) {
        guard let att = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        size = (att[.size] as? NSNumber)?.uint64Value ?? 0
        mtime = att[.modificationDate] as? Date
        inode = (att[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}
