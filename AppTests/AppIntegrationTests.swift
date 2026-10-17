import XCTest
import HealthKit
import SleepBankCore
@testable import SleepBank

final class AppIntegrationTests: XCTestCase {
    func testRecordingStorageDefaultsToLocalDocuments() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: NapFiles.syncPreferenceKey)
        defer { defaults.set(previous, forKey: NapFiles.syncPreferenceKey) }
        defaults.removeObject(forKey: NapFiles.syncPreferenceKey)
        XCTAssertFalse(NapFiles.iCloudSyncEnabled)
        XCTAssertEqual(NapFiles.documentsDirectory(), FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }

    func testAppRegistersWidgetDeepLinkScheme() {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("sleepbank"))
    }

    func testHealthKitAdapterUsesResolvedTimelineForChartAndTotals() {
        let start = Date(), end = start.addingTimeInterval(7 * 3600)
        let type = HKCategoryType(.sleepAnalysis)
        let samples = [
            HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: start, end: end),
            HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start, end: end)
        ]
        let timeline = HealthSleepTimeline.resolve(samples, start: start, end: end)
        XCTAssertEqual(timeline.reduce(0) { $0 + $1.duration }, 7 * 3600)
        let chart = HealthSleepTimeline.chartSamples(timeline)
        XCTAssertEqual(chart.count, 1)
        XCTAssertEqual(chart.first?.stage, .asleepCore)
    }
}
