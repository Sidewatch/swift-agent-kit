//
//  ProgramStatusReport.swift
//  AgentStatus
//
//  One Program Status Protocol (OSC 7501) record: what the program in the terminal says about itself.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One Program Status Protocol (OSC 7501) record as the terminal holds it: what the program in
/// the terminal says about itself. The terminal keeps one record per `id` and hands the host the
/// whole set on every change; ``ReportedActivity`` turns the set into one verdict.
///
/// Text fields are the program's own, untrusted: show them as plain text.
public struct ProgramStatusReport: Equatable, Sendable {
    /// The record's path (`build`, `build/tests`); empty for the root record, the program itself.
    public let id: String
    public let state: ProgramStatusState
    /// What a blocked program needs; nil for every other state.
    public let kind: ProgramStatusKind?
    /// 0…100 while working or blocked, when the program reports it.
    public let progress: Int?
    /// The program's name, from this record or its nearest named ancestor.
    public let app: String?
    public let title: String?
    public let message: String?

    public init(
        id: String = "", state: ProgramStatusState, kind: ProgramStatusKind? = nil, progress: Int? = nil,
        app: String? = nil, title: String? = nil, message: String? = nil
    ) {
        self.id = id
        self.state = state
        self.kind = kind
        self.progress = progress
        self.app = app
        self.title = title
        self.message = message
    }
}
