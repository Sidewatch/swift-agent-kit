//
//  SubagentWork.swift
//  AgentSession
//
//  What one sub-agent did, as its own transcript records it.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What a sub-agent did for the tool call that started it. An agent that hands work to a sub-agent
/// records only the call and the report that came back; what the sub-agent ran and wrote is in the
/// sub-agent's own transcript.
public struct SubagentWork: Equatable, Sendable {
    /// The kind of sub-agent, as the agent names it (`"general-purpose"`); empty when it does not say.
    public let type: String
    /// How many tool calls it has made.
    public let toolCalls: Int
    /// The files it wrote, in the order it first wrote each.
    public let editedFiles: [String]
    /// Whether it has finished.
    public let isFinished: Bool

    /// One sub-agent's work.
    public init(type: String, toolCalls: Int, editedFiles: [String], isFinished: Bool) {
        self.type = type
        self.toolCalls = toolCalls
        self.editedFiles = editedFiles
        self.isFinished = isFinished
    }
}
