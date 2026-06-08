//
//  NapDecisionStore.swift
//  SleepBank
//
//  Phone-side log of nap decision records synced from the watch. The backing
//  data for the validation screen and the CreateML export.
//

import Foundation
import SleepBankCore

@Observable
class NapDecisionStore {

    static let shared = NapDecisionStore()

    private(set) var records: [NapDecisionRecord] = []
    private let url: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("nap-decisions.json")
        load()
    }

    func add(_ record: NapDecisionRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)   // most recent first
        save()
    }

    /// Total feature rows across all naps — the size of the training set.
    var epochCount: Int { records.reduce(0) { $0 + $1.epochs.count } }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([NapDecisionRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
