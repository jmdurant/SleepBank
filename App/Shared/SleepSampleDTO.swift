//
//  SleepSampleDTO.swift
//  SleepBank
//
//  A Codable mirror of SleepChartKit's SleepSample so we can ship sleep timelines
//  over WatchConnectivity (which only moves plist/Data, and SleepSample isn't
//  Codable). Converts both directions.
//

import Foundation
import SleepChartKit

struct SleepSampleDTO: Codable, Hashable {
    let stage: Int          // SleepStage.rawValue
    let start: Date
    let end: Date

    init(_ sample: SleepSample) {
        self.stage = sample.stage.rawValue
        self.start = sample.startDate
        self.end = sample.endDate
    }

    var sleepSample: SleepSample {
        SleepSample(
            stage: SleepStage(rawValue: stage) ?? .asleepUnspecified,
            startDate: start,
            endDate: end
        )
    }
}

extension Array where Element == SleepSample {
    var dtos: [SleepSampleDTO] { map(SleepSampleDTO.init) }
}

extension Array where Element == SleepSampleDTO {
    var sleepSamples: [SleepSample] { map(\.sleepSample) }
}
