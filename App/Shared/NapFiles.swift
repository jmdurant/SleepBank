//
//  NapFiles.swift
//  SleepBank
//
//  Where per-nap export files go (iCloud Drive container, syncing to the Mac) and
//  how they're keyed. Each nap writes two files sharing one stamp:
//    eeg-<stamp>.csv       — raw 4-channel EEG (RawEEGRecorder), staged by YASA
//    features-<stamp>.csv  — per-epoch sensor features (this file)
//  The Mac merge script joins them by <stamp> + time into a labeled training table.
//

import Foundation
import SleepBankCore

enum NapFiles {
    static let iCloudContainer = "iCloud.com.doctordurant.sleepbank"

    /// iCloud Documents (syncs to the Mac) when available, else local Documents.
    /// Call off the main thread — resolving the ubiquity container can block.
    static func documentsDirectory() -> URL {
        let fm = FileManager.default
        if let container = fm.url(forUbiquityContainerIdentifier: iCloudContainer) {
            let docs = container.appendingPathComponent("Documents")
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            return docs
        }
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func stamp(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// Write the nap's per-epoch sensor features alongside its EEG (background).
    static func writeFeatures(_ record: NapDecisionRecord, stamp: String) {
        DispatchQueue.global(qos: .utility).async {
            var rows = ["t,hr,hrv,movement,stillSeconds,eegOnset,eegDeep,breathing,spo2,phase"]
            for e in record.epochs {
                var c: [String] = []
                c.append(String(format: "%.0f", e.t))
                c.append(e.heartRate.map(String.init) ?? "")
                c.append(e.hrv.map { String(format: "%.1f", $0) } ?? "")
                c.append(String(format: "%.3f", e.movement))
                c.append(String(format: "%.0f", e.stillSeconds))
                c.append(e.eegOnset.map { String(format: "%.3f", $0) } ?? "")
                c.append(e.eegDeep ? "1" : "0")
                c.append(e.breathing.map { String(format: "%.1f", $0) } ?? "")
                c.append(e.spo2.map { String(format: "%.0f", $0) } ?? "")
                c.append(e.phase)
                rows.append(c.joined(separator: ","))
            }
            let url = documentsDirectory().appendingPathComponent("features-\(stamp).csv")
            try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
