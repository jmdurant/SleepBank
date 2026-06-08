//
//  HeartRateSample.swift
//  SleepBank
//
//  A single timestamped heart-rate reading. Shared between the watch nap
//  session and (later) the phone for logging and onset analysis.
//

import Foundation

struct HeartRateSample: Codable, Hashable {
    let timestamp: Date
    let bpm: Int
}
