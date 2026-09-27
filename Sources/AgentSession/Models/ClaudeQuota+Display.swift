//
//  ClaudeQuota+Display.swift
//  AgentSession
//
//  The window's display name: `five_hour` is the 5-hour session, `seven_day` is Weekly, a per-
//  model weekly cap is `Weekly · Model`, and an unknown key reads as its words.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension ClaudeQuota.NamedWindow {
    /// The window's display name: `five_hour` is the 5-hour session, `seven_day` is Weekly,
    /// a per-model weekly cap is `Weekly · Model`, and an unknown key reads as its words.
    public var label: String {
        switch key {
        case "five_hour", "session": return String(localized: "5-hour session", bundle: .module, comment: "Plan-limit window name: the rolling five-hour usage window")
        case "seven_day": return String(localized: "Weekly", bundle: .module, comment: "Plan-limit window name: the weekly usage window")
        case "weekly_all": return String(localized: "Weekly · all models", bundle: .module, comment: "Plan-limit window name: the weekly window across every model")
        default:
            if key.hasPrefix("weekly_scoped:") {
                return String(localized: "Weekly · \(String(key.dropFirst("weekly_scoped:".count)))", bundle: .module,
                              comment: "Plan-limit window name: the weekly window for one model; the argument is the model name, such as Opus")
            }
            if key.hasPrefix("seven_day_") {
                let model = key.dropFirst("seven_day_".count).replacingOccurrences(of: "_", with: " ").capitalized
                return String(localized: "Weekly · \(model)", bundle: .module,
                              comment: "Plan-limit window name: the weekly window for one model; the argument is the model name, such as Opus")
            }
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

extension ClaudeQuota.Window {
    /// When the window rolls over, in words: `resets in 1d 2h`, `resets in 1h 30m`,
    /// `resets in 5m`, `resets now`. Nil when the endpoint gave no reset time.
    public func resetDescription(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let secs = Int(resetsAt.timeIntervalSince(now))
        if secs <= 0 { return String(localized: "resets now", bundle: .module, comment: "Plan-limit window: the usage window rolls over now") }
        let h = secs / 3600, m = (secs % 3600) / 60
        if h >= 24 { return String(localized: "resets in \(h / 24)d \(h % 24)h", bundle: .module, comment: "Plan-limit window: time until it rolls over, in days (d) and hours (h)") }
        if h > 0 { return String(localized: "resets in \(h)h \(m)m", bundle: .module, comment: "Plan-limit window: time until it rolls over, in hours (h) and minutes (m)") }
        return String(localized: "resets in \(m)m", bundle: .module, comment: "Plan-limit window: time until it rolls over, in minutes (m)")
    }
}

extension ClaudeQuota.Spend {
    /// `£12.34 of £100.00` — both amounts in the account's currency. Formatted in a fixed
    /// locale so GBP, USD and EUR read as `£`, `$`, `€` on every Mac.
    public var summary: String {
        String(localized: "\(formatted(usedMinor)) of \(formatted(limitMinor))", bundle: .module,
               comment: "Extra-usage spend: the amount used of the monthly limit, both as currency, such as £12.34 of £100.00")
    }

    /// One amount in minor units as currency text.
    public func formatted(_ minor: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = exponent
        f.maximumFractionDigits = exponent
        let value = Decimal(minor) / pow(Decimal(10), exponent)
        return f.string(from: value as NSDecimalNumber) ?? "\(value) \(currency)"
    }
}
