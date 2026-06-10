//
//  PlanPreview.swift
//  SleepBank
//
//  A tiny shared channel so the alertness curve can drive the home-screen battery:
//  while you're building a plan (nap/walk/workout), the ring previews the peak Alert
//  Score that plan would reach and "charges" toward it as you drag. Nil = no active
//  plan, so the ring shows your right-now score.
//

import Foundation

@Observable
final class PlanPreview {
    static let shared = PlanPreview()
    /// Peak predicted alertness (0…1) under the current draft plan, or nil if none.
    var level: Double?
    /// When that peak occurs.
    var peakTime: Date?
    /// A time the user is scrubbing to on the bare curve (no plan) — the battery reads
    /// the level there. Nil = show "now". Tapping the battery clears it.
    var scrubTime: Date?
}
