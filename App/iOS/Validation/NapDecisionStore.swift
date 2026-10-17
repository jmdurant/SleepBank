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

    init(url: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.url = url ?? docs.appendingPathComponent("nap-decisions.json")
        load()
    }

    @discardableResult
    func add(_ record: NapDecisionRecord) -> Bool {
        var next = records.filter { $0.id != record.id }
        next.insert(record, at: 0)
        do {
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            records = next
            return true
        } catch {
            print("[NapDecisionStore] Trace not saved; withholding ACK: \(error)")
            return false
        }
    }

    /// Total feature rows across all naps — the size of the training set.
    var epochCount: Int { records.reduce(0) { $0 + $1.epochs.count } }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([NapDecisionRecord].self, from: data) else { return }
        records = decoded
    }

}
