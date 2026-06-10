//
//  SleepBasis.swift
//  SleepBank
//
//  How last night sets today's curve offset. Sleep Score needs Apple-Watch-grade
//  data (duration + efficiency); the Hours basis works with any tracker that logs
//  duration (Oura, a manual entry, no watch at all). Auto picks Sleep Score when
//  quality data is present, else falls back to Hours.
//

import Foundation

enum SleepBasis: String, CaseIterable, Identifiable {
    case auto, sleepScore, hours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:       return "Auto"
        case .sleepScore: return "Sleep Score"
        case .hours:      return "Sleep debt (hours)"
        }
    }

    /// Read from the same key Settings writes via @AppStorage.
    static var current: SleepBasis {
        SleepBasis(rawValue: UserDefaults.standard.string(forKey: "sleepBasis") ?? "") ?? .auto
    }
}
