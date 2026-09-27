//
//  ForegroundInfo.swift
//  AgentStatus
//
//  These travelled as loose parameters with nil defaults, and omitting one silently degraded
//  the derivation — forget the args and an npm-installed agent reports `.running` — while every
//  stale caller kept compiling.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// These travelled as loose parameters with nil defaults, and omitting one silently degraded
/// the derivation — forget the args and an npm-installed agent reports `.running` — while every
/// stale caller kept compiling. All `let`, no defaults, no memberwise silence: adding a field
/// is a compile error at every construction site, which is the entire reason this exists.
public struct ForegroundInfo: Equatable, Sendable {
    /// Whether a foreground program is running (foreground pgid ≠ the shell's).
    public let isBusy: Bool
    /// The foreground process name, nil when idle at the prompt.
    public let process: String?
    /// Its executable path — how an agent whose binary is named after its version is recognised.
    public let processPath: String?
    /// Its argv — how an npm/pip-installed agent hiding inside `node`/`python` is recognised.
    public let processArgs: String?
    public init(isBusy: Bool, process: String?, processPath: String?, processArgs: String?) {
        self.isBusy = isBusy; self.process = process; self.processPath = processPath; self.processArgs = processArgs
    }
}

/// An unacknowledged signal from the agent running in a terminal.
///
