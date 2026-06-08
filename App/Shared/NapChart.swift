//
//  NapChart.swift
//  SleepBank
//
//  Turns a completed NapRecord into SleepSamples for the recap chart. Watch-only
//  sensors give us onset and wake, so the honest recap is two segments: awake
//  while settling, then asleep until the alarm. When EEG fusion lands we can
//  subdivide the asleep portion into real stages.
//

import Foundation
import SleepChartKit
import SleepBankCore

enum NapChart {
    static func samples(from record: NapRecord) -> [SleepSample] {
        if let onset = record.onset {
            return [
                SleepSample(stage: .awake, startDate: record.start, endDate: onset),
                SleepSample(stage: .asleepCore, startDate: onset, endDate: record.end),
            ]
        } else {
            // Never fell asleep — the whole window was awake.
            return [SleepSample(stage: .awake, startDate: record.start, endDate: record.end)]
        }
    }

    /// Minutes from session start to detected onset (sleep latency), if any.
    static func onsetLatencyMinutes(_ record: NapRecord) -> Int? {
        guard let onset = record.onset else { return nil }
        return Int(onset.timeIntervalSince(record.start) / 60)
    }
}
