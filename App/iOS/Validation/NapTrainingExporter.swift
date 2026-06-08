//
//  NapTrainingExporter.swift
//  SleepBank
//
//  Exports the accumulated nap traces as a CreateML-ready CSV — one row per
//  epoch, labeled asleep/awake. Mirrors SexKit's CreateMLExporter workflow:
//  AirDrop the CSV to a Mac → CreateML → Tabular Classifier → target column
//  "label" → train → .mlmodel.
//
//  Label source, best first:
//    • eeg   — Muse onset index (gold standard)
//    • apple — Apple's retrospective staging of the window
//    • self  — our own onset decision (weak / circular; filter these out in
//              CreateML if you want only high-quality labels)
//

import Foundation
import SleepBankCore

enum NapTrainingExporter {

    static func exportCSV(records: [NapDecisionRecord]) async -> URL? {
        let comparator = AppleSleepComparator()
        var rows: [String] = [
            "napId,napType,t,hr,hrv,movement,stillSeconds,eegOnset,eegDeep,breathing,label,labelSource",
        ]

        for record in records {
            // Apple labels need the comparison; compute once per nap.
            let comparison = await comparator.compare(record)
            for e in record.epochs {
                let epochTime = record.start.addingTimeInterval(e.t)
                let (label, source) = self.label(epoch: e, epochTime: epochTime,
                                                 record: record, comparison: comparison)
                rows.append([
                    record.id.uuidString,
                    record.type.rawValue,
                    String(format: "%.0f", e.t),
                    e.heartRate.map(String.init) ?? "",
                    e.hrv.map { String(format: "%.1f", $0) } ?? "",
                    String(format: "%.3f", e.movement),
                    String(format: "%.0f", e.stillSeconds),
                    e.eegOnset.map { String(format: "%.3f", $0) } ?? "",
                    e.eegDeep ? "1" : "0",
                    e.breathing.map { String(format: "%.1f", $0) } ?? "",
                    label,
                    source,
                ].joined(separator: ","))
            }
        }

        let csv = rows.joined(separator: "\n")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("SleepBank_NapTraining_\(records.count)naps.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("[NapTrainingExporter] write failed: \(error)")
            return nil
        }
    }

    private static func label(epoch e: NapEpochFeatures, epochTime: Date,
                              record: NapDecisionRecord,
                              comparison: AppleNapComparison) -> (String, String) {
        if let eeg = e.eegOnset {
            return (eeg >= 0.6 ? "asleep" : "awake", "eeg")
        }
        if comparison.appleRecorded, let appleOnset = comparison.appleOnset {
            return (epochTime >= appleOnset ? "asleep" : "awake", "apple")
        }
        if let onset = record.onset {
            return (epochTime >= onset ? "asleep" : "awake", "self")
        }
        return ("awake", "self")
    }
}
