//
//  ClockFormat.swift
//  AgentSession
//
//  `HH:mm` in a fixed locale, once.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// `HH:mm` in a fixed locale, built once (DateFormatter is expensive). `en_US_POSIX` pins it:
/// otherwise a 12-hour region rewrites even an explicit `dateFormat`.
enum ClockFormat {
    /// The shared formatter: 24-hour, local time zone.
    static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "14:05" for `date`, local time.
    static func hhmm(_ date: Date) -> String { hhmm.string(from: date) }
}
