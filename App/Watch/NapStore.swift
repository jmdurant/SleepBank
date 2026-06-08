//
//  NapStore.swift
//  SleepBank Watch App
//
//  Local persistence for completed naps. Plain Codable-to-JSON in the app
//  container — enough to back the descriptive sleep bank. (CloudKit/WatchConnectivity
//  sync to the phone comes later; this keeps the wrist self-sufficient.)
//

import Foundation
import SleepBankCore

@Observable
class NapStore {
    private(set) var records: [NapRecord] = []
    private let url: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("naps.json")
        load()
    }

    func add(_ record: NapRecord) {
        records.append(record)
        save()
    }

    // Descriptive bank — plain totals, no formulas.
    var minutesToday: Int { NapBank.minutesAsleep(on: Date(), in: records) }
    var countToday: Int { NapBank.count(on: Date(), in: records) }
    var minutesThisWeek: Int { NapBank.minutesAsleepLast7Days(endingAt: Date(), in: records) }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([NapRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
