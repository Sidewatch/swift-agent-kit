//
//  ProgramStatusState.swift
//  AgentStatus
//
//  The `state` of a Program Status Protocol (OSC 7501) record, spelled as the protocol spells it.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The `state` of a Program Status Protocol (OSC 7501) record. The raw values are the
/// protocol's own words — what a program writes after `state=` — so a terminal's record maps
/// onto this by raw value and a test pins each word.
public enum ProgramStatusState: String, CaseIterable, Equatable, Sendable {
    /// At its prompt with nothing in flight.
    case idle
    /// Work in flight.
    case working
    /// A task completed.
    case done
    /// Stopped until the person acts; the record's `kind` says how.
    case blocked
    /// A task stopped on an error.
    case error
}
