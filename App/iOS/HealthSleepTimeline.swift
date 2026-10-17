import Foundation
import HealthKit
import SleepBankCore
import SleepChartKit

/// Shared normalization for summaries, charts, averages and bedtime history.
enum HealthSleepTimeline {
    static func resolve(_ samples: [HKCategorySample], start: Date, end: Date) -> [SleepTimeline.Sample] {
        let inputs = samples.compactMap { sample -> SleepTimeline.Sample? in
            let stage: SleepTimeline.Stage
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleepUnspecified: stage = .asleep
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            default: return nil
            }
            return .init(start: sample.startDate, end: sample.endDate, stage: stage,
                         source: sample.sourceRevision.source.bundleIdentifier)
        }
        return SleepTimeline.resolve(inputs, within: DateInterval(start: start, end: end))
    }

    static func chartSamples(_ samples: [SleepTimeline.Sample]) -> [SleepSample] {
        samples.map { sample in
            let stage: SleepStage
            switch sample.stage {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleep: stage = .asleepUnspecified
            case .core: stage = .asleepCore
            case .deep: stage = .asleepDeep
            case .rem: stage = .asleepREM
            }
            return SleepSample(stage: stage, startDate: sample.start, endDate: sample.end)
        }
    }
}
